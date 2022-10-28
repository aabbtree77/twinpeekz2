import opengl
import glm
import shaders
import scene
import camera

import std/bitops
import std/typetraits

const 
  TEX_UNIT_BASECOLOR         = 0
  TEX_UNIT_METALLICROUGHNESS = 1
  TEX_UNIT_DEPTH             = 2
  TEX_UNIT_VOLUMETRIC        = 3
  TEX_UNIT_SHADOW_MAP_BASE   = 4
  MAX_LIGHTS                 = 8 #sync this value in shaders

type FrameBuffer = object 
  fboID:         uint32
  colorBufferID: uint32
  zBufferID:     uint32


type RenderEngine* = object
  width*, height*: int32
  hdrProg*:       Shader
  volProg*:       Shader
  postprProg*:    Shader
  dirLightProg*:  Shader
  screenQuad*:    MeshGPUBufferIDs
  query*:         array[4, uint32]
  volFB*:         FrameBuffer
  hdrFB*:         FrameBuffer


proc makeFrameBuffer(width: int32, height: int32): FrameBuffer =

  var fboID: uint32
  glGenFramebuffers(1, fboID.addr)

  var colorBufferID: uint32
  glGenTextures(1, colorBufferID.addr)
  glBindTexture(GL_TEXTURE_2D, colorBufferID)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F.GLint, width.GLint, height.GLint, 0, GL_RGBA.GLenum, cGL_FLOAT, nil)

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)

  var zBufferID: uint32
  glGenTextures(1, zBufferID.addr)
  glBindTexture(GL_TEXTURE_2D, zBufferID)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT.GLint, width.GLint, height.GLint, 0, GL_DEPTH_COMPONENT.GLenum, GL_UNSIGNED_BYTE, nil)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

  # Attach buffers to FBO
  glBindFramebuffer(GL_FRAMEBUFFER, fboID)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, colorBufferID, 0)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, zBufferID, 0)

  if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
    echo "Incomplete frame buffer: ", $distinctBase(glCheckFramebufferStatus(GL_FRAMEBUFFER))
    return FrameBuffer()
  

  # Bind hdr framebuffer
  glBindFramebuffer(GL_FRAMEBUFFER, 0)

  return FrameBuffer(fboID: fboID, colorBufferID: colorBufferID, zBufferID: zBufferID)


proc initRendering*(scn: var Scene, width: int32, height: int32): RenderEngine =

  let
    hdrProg = MakeShaders("./shaders/hdr_vert.glsl", "./shaders/hdr_frag.glsl")
    volProg = MakeShaders("./shaders/vol_vert.glsl", "./shaders/vol_frag.glsl")
    postprProg = MakeShaders("./shaders/postpr_vert.glsl", "./shaders/postpr_frag.glsl")
    dirLightProg = MakeShaders("./shaders/lightDir_vert.glsl", "./shaders/lightDir_frag.glsl")
  
  #[
  //BTW, arrays on GPU turn out to be a nasty area. Simply declaring arrays of MAX_LIGHTS
  //and then sending only the needed type of light num < MAX_LIGHTS breaks things as the
  //unused arrays or array elements interfere in some hard to predict/debug ways even
  //when the shader needs for instance just the first 0-th element of a single cube texture
  //array.
  //The solution is to fill all the arrays completely with pregenerated texture units and
  //then save them into the light structs. The lights can then later be also removed during
  //the rendering in a safer way.
  ]#

  glUseProgram(hdrProg.ID)
  hdrProg.SetInt("albedoMap", TEX_UNIT_BASECOLOR)
  hdrProg.SetInt("metalRoughMap", TEX_UNIT_METALLICROUGHNESS)
  #//for it, lht := range scn.lights {
  #//It's not completely clear if sending the same texture unit number into cube and 2d
  #//texture samples is a good idea, but it works.
  for it in 0..<MAX_LIGHTS:
    let textureUnit = it + TEX_UNIT_SHADOW_MAP_BASE
    hdrProg.SetInt("dirlights[" & $it & "].txrUnit", int32(textureUnit))
    if it < len(scn.lights):
      scn.lights[it].txrUnit = uint32(textureUnit) #save for the use in the render loop


  glUseProgram(volProg.ID)
  volProg.SetInt("shadowMap", TEX_UNIT_DEPTH)

  for it in 0..<MAX_LIGHTS:
    let textureUnit = it + TEX_UNIT_SHADOW_MAP_BASE
    volProg.SetInt("dirlights[" & $it & "].txrUnit", int32(textureUnit))


  glUseProgram(postprProg.ID)
  postprProg.SetInt("hdrTexture", TEX_UNIT_BASECOLOR)
  postprProg.SetInt("volTexture", TEX_UNIT_VOLUMETRIC)

  let quadVertices: seq[array[3, float32]] = 
    @[[-1.0'f32, 1.0'f32, 0.0'f32], 
      [-1.0'f32, -1.0'f32, 0.0'f32], 
      [1.0'f32, 1.0'f32, 0.0'f32], 
      [1.0'f32, -1.0'f32, 0.0'f32]]
  
  let quadUvs: seq[array[2,float32]] = 
    @[[0.0'f32, 1.0'f32], [0.0'f32, 0.0'f32], [1.0'f32, 1.0'f32], [1.0'f32, 0.0'f32]]
  
  let quadIndices: seq[uint32] = @[0'u32, 1'u32, 2'u32, 1'u32, 3'u32, 2'u32]

  var meshgeom = MeshGeometry(
          vertArray: quadVertices,
          uvArray:   quadUvs,
          normArray: @[],
          indArray:  quadIndices)
          
  let screenQuad = uploadMeshToGPU(meshgeom)

  glEnable(GL_CULL_FACE)
  glEnable(GL_DEPTH_TEST)
  #glDepthFunc(GL_LESS)

  var query: array[4, uint32]
  glGenQueries(4, query[0].addr)

  var volFB = makeFrameBuffer(width, height)

  var hdrFB = makeFrameBuffer(width, height)

  return RenderEngine(
          width:        width,
          height:       height,
          hdrProg:      hdrProg,
          volProg:      volProg,
          postprProg:   postprProg,
          dirLightProg: dirLightProg,
          screenQuad:   screenQuad,
          query:        query,
          volFB:        volFB,
          hdrFB:        hdrFB)



proc resizeFrameBuffer(fb: FrameBuffer, width: int32, height: int32) =
  glBindTexture(GL_TEXTURE_2D, fb.colorBufferID)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F.GLint, width, height, 0, GL_RGBA, cGL_FLOAT, nil)
  glBindTexture(GL_TEXTURE_2D, fb.zBufferID)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT.GLint, width, height, 0, GL_DEPTH_COMPONENT, GL_UNSIGNED_BYTE, nil)


proc resizeRendering*(reng: RenderEngine) =
  resizeFrameBuffer(reng.volFB, reng.width, reng.height)
  resizeFrameBuffer(reng.hdrFB, reng.width, reng.height)
  glViewport(0, 0, reng.width, reng.height)


proc drawMesh(msh: MeshGPUBufferIDs, shdrProgID: uint32) =
  
  glBindVertexArray(msh.vaoID)

  var loc = uint32(glGetAttribLocation(shdrProgID, cstring("inPosition")))
  if loc >= 0:
    glBindBuffer(GL_ARRAY_BUFFER, msh.vertexBufferID)
    glVertexAttribPointer(loc, 3, cGL_FLOAT, false, 0, nil)
    glEnableVertexAttribArray(loc)
  else:
    echo "drawInstance could not find uniform: inPosition"
    quit(QuitFailure)
 
  # These <uint32, GLenum> mismatches are very annoying, that's how
  # I test them directly in code before fixing them. In this case
  # the need for distinctBase:
  #let 
  #  aa: bool = msh.normalBufferID > 0
  #  bb: bool = msh.normalBufferID != distinctBase(GL_INVALID_VALUE)
      
  if (msh.normalBufferID > 0 and 
     (msh.normalBufferID != distinctBase(GL_INVALID_VALUE))):
    loc = uint32(glGetAttribLocation(shdrProgID, cstring("inNormal")))
    if loc >= 0:
      glBindBuffer(GL_ARRAY_BUFFER, msh.normalBufferID)
      glVertexAttribPointer(loc, 3, cGL_FLOAT, false, 0, nil)
      glEnableVertexAttribArray(loc)
    else:
      echo "drawInstance could not find uniform: inNormal"
      quit(QuitFailure)
          
  
  if (msh.uvBufferID > 0 and 
     (msh.uvBufferID != distinctBase(GL_INVALID_VALUE))):
    loc = uint32(glGetAttribLocation(shdrProgID, cstring("inTexCoord")))
    if loc >= 0:
      glBindBuffer(GL_ARRAY_BUFFER, msh.uvBufferID)
      glVertexAttribPointer(loc, 2, cGL_FLOAT, false, 0, nil)
      glEnableVertexAttribArray(loc)
    else:
      echo "drawInstance could not find uniform: inTexCoord"
      quit(QuitFailure)
 
          
  glDrawElements(GL_TRIANGLES, msh.lenIndices, GL_UNSIGNED_INT, nil)


proc drawMeshVertOnly(instance: var DrawableInstance, shdrProg: Shader) =

  shdrProg.SetMat4("model", instance.model_matrix)
  glBindVertexArray(instance.mesh.vaoID)

  glBindBuffer(GL_ARRAY_BUFFER, instance.mesh.vertexBufferID)
  #//Vert attr loc 0:
  glVertexAttribPointer(0, 3, cGL_FLOAT, false, 0, nil)
  glEnableVertexAttribArray(0)

  glDrawElements(GL_TRIANGLES, instance.mesh.lenIndices, GL_UNSIGNED_INT, nil)


proc setLightParams(lht: var Light, shd: Shader, str: string) = 

  shd.SetVec3(str & ".dir", lht.dir)
  shd.SetVec3(str & ".color", lht.color)
  shd.SetFloat(str & ".intensity", lht.intensity)
  shd.SetMat4(str & ".dirWorldToProj", lht.projView)

proc mainRendering*(scn: var Scene, rengine: RenderEngine, cam: var Camera): array[5, float64] =

  var timeOpenGLms: array[5, float64]
  
  #[
  // Update shadow maps, they will be drawn for each light into its corresponding lht.FBOID
  //framebuffer with depth texture attachment created with initShadowMap() in scene.go.
  //TD: Think about framebuffer objects spread in: (i) scn.lights Light struct and (ii) rengine RenderEngine struct.
  //This is alright, but shows how low level graphics API concepts spread into different things.
  //Scene and RenderEngine has no clear borders as to what belongs where, e.g. this is not a rigorous math question:
  //Do shadow map framebuffer ids belong to the light struct in the scene, or RenderEngine's shadow map stage, which
  //is not clearly delineated in RenderEngine struct BTW.
  ]#

  #//----------------------------------------------------------------------------------------------------------------
  
  glBeginQuery(GL_TIME_ELAPSED, rengine.query[0])
  glEnable(GL_DEPTH_TEST)

  for it, lht in scn.lights:

    glBindFramebuffer(GL_FRAMEBUFFER, lht.FBOID)
    glViewport(0, 0, lht.shMapWidth, lht.shMapHeight)
    glClear(GL_DEPTH_BUFFER_BIT)

    var proj: Mat4f
    let zNear = float32(0.1) #should these be different per light, adaptive?
    let zFar = float32(100.0)
    proj = ortho(-30.0'f32, 30.0'f32, -30.0'f32, 30.0'f32, zNear, zFar)
    
    #If dir and up are aligned LookAtV will output NaN matrices!!!
     
    #dir lht has no position, but we still need to position it
    # so that the shadow map is centered. Anything outside that light-cam view
    # won't cast a shadow. Expanding the ortho box looses resolution.
    # Let's emit a ray from the Sponza floor center towards -lht.dir:  
    let pos = vec3f(0.0, 0.0, 0.0) - (50.0.float32 * lht.dir.normalize)

    # lookAt needs an up vector to build a reference frame
    #let lhtdir_n = normalize(lht.dir)
    #let pos_aux = vec3f(2.1, -1.7, -1.0)
    #let up = lhtdir_n - (dot(pos_aux, lhtdir_n) * lhtdir_n)
    
    # up = Z_AXIS here is just a helper vector to get the x-axis and then a full ref frame 
    # in the light-cam space. It should not be parallel to lht.dir  
    var projView = proj * lookAt(pos, pos + lht.dir, Z_AXIS)

    #echo "Lights projView :"
    #echo projView

    glUseProgram(rengine.dirLightProg.ID)
    rengine.dirLightProg.SetMat4("projView", projView)

    for it2, unused in scn.drawables:
      drawMeshVertOnly(scn.drawables[it2], rengine.dirLightProg)
    
    scn.lights[it].projView = projView
  
  #[
  //(0, 0) arguments would change for "multi-viewport" settings, "the lower left corner of the viewport rectangle, in pixels".
  //Framebuffer texture resolution is different for shadow map stages and hdr/vol passes.
  //hdr/vol pass resolution reacts to glfw window resizes, but shadowmap resolutions are fixed when setting up lights in scene.go.
  ]#

  glViewport(0, 0, rengine.width, rengine.height)
  glEndQuery(GL_TIME_ELAPSED)

  #// Draw scene to the HDR frame buffer
  #//---------------------------------------------------------------------------------------------
  
  glBeginQuery(GL_TIME_ELAPSED, rengine.query[1])
  glBindFramebuffer(GL_FRAMEBUFFER, rengine.hdrFB.fboID)
  #//gl.BindFramebuffer(GL_FRAMEBUFFER, 0) #//Screen

  let bgColor = vec3f(0.0, 0.0, 1.0)
  glClearColor(bgColor[0], bgColor[1], bgColor[2], 1.0)
  glClear(
    GLbitfield(
      bitor(distinctBase(GL_COLOR_BUFFER_BIT), 
          distinctBase(GL_DEPTH_BUFFER_BIT))))

  glUseProgram(rengine.hdrProg.ID)
  rengine.hdrProg.SetVec3("camPos", cam.pos)
  rengine.hdrProg.SetInt("numDirLights", int32(len(scn.lights)))

  #[
  //Activate and bind depth textures, quite a ceremony, but they get into a .glsl file via texture ints.
  //These ints are set in initRendering and are esentially global texture ids/variables.
  //In a GLSL program they become sampler2D/samplerCube, find a concrete variable in .glsl first, and
  //then search for its texture associations in higher level programs.
  //TD: need to better manage those ints to remove max lights bounds and such, but this exists due to
  //a static nature of GPU shaders, probably a hassle to use an array with a variable number of structs.
  ]#

  for it, unused in scn.lights:
    glActiveTexture(GLenum(distinctBase(GL_TEXTURE0) + scn.lights[it].txrUnit))
    glBindTexture(GL_TEXTURE_2D, scn.lights[it].txrID)

    let str = "dirlights[" & $it & "]"
    scn.lights[it].setLightParams(rengine.hdrProg, str)
  
  #//glCheckError()
  #//return
  for unused, instance in scn.drawables:
    var pvm = cam.projView * instance.model_matrix
    rengine.hdrProg.SetMat4("projViewModel", pvm)
    var imm = instance.model_matrix
    rengine.hdrProg.SetMat4("model", imm)

    #[
    //TD if there is no texture file upload material.diffuseColor to the shaders instead
    //the field and value is set there in the scene just in case, but not used for now.
    //Meshes without all the proper textures are simply not loaded at the moment.
    ]#

    glActiveTexture(GLenum(distinctBase(GL_TEXTURE0) + TEX_UNIT_BASECOLOR))
    glBindTexture(GL_TEXTURE_2D, instance.baseColorTextureID)

    glActiveTexture(GLenum(distinctBase(GL_TEXTURE0) + TEX_UNIT_METALLICROUGHNESS))
    glBindTexture(GL_TEXTURE_2D, instance.metallicRoughnessTextureID)

    drawMesh(instance.mesh, rengine.hdrProg.ID)
  

  glEndQuery(GL_TIME_ELAPSED)

  #// Draw vol pass
  #//---------------------------------------------------------------------------------------------
  glBeginQuery(GL_TIME_ELAPSED, rengine.query[2])
  glDisable(GL_DEPTH_TEST)
  glBindFramebuffer(GL_FRAMEBUFFER, rengine.volFB.fboID)

  glUseProgram(rengine.volProg.ID)
  #//gl.ActiveTexture(gl.TEXTURE0 + TEX_UNIT_BASECOLOR)
  #//gl.BindTexture(gl.TEXTURE_2D, rengine.hdrFB.colorBufferID)

  glActiveTexture(GLenum(distinctBase(GL_TEXTURE0) + TEX_UNIT_DEPTH))
  glBindTexture(GL_TEXTURE_2D, rengine.hdrFB.zBufferID)

  rengine.volProg.SetInt("numDirLights", int32(len(scn.lights)))

  #//Activate and bind depth textures
  for it, unused in scn.lights:
    glActiveTexture(GLenum(distinctBase(GL_TEXTURE0) + scn.lights[it].txrUnit))
    glBindTexture(GL_TEXTURE_2D, scn.lights[it].txrID)

    let str = "dirlights[" & $it & "]"
    scn.lights[it].setLightParams(rengine.volProg, str)
  

  rengine.volProg.SetMat4("invProjView", cam.invProjView)
  rengine.volProg.SetVec3("camPos", cam.pos)
  rengine.volProg.SetFloat("screenWidth", float32(rengine.width))
  rengine.volProg.SetFloat("screenHeight", float32(rengine.height))
  rengine.volProg.SetInt("volumetricAlgo", 1) #//0 for visibility accumulation experiments
  rengine.volProg.SetFloat("scatteringZFar", float32(100.0))
  rengine.volProg.SetInt("scatteringSamples", 64)

  drawMesh(rengine.screenQuad, rengine.volProg.ID)
  glEndQuery(GL_TIME_ELAPSED)

  #// Draw resulting frame buffer to screen with gamma correction and tone mapping
  #//----------------------------------------------------------------------------------------------
  
  glBeginQuery(GL_TIME_ELAPSED, rengine.query[3])
  glBindFramebuffer(GL_FRAMEBUFFER, 0) #//Screen
  glUseProgram(rengine.postprProg.ID)

  #//fmt.Printf("ns=%v, interleave=%v, shader=%v\n", 24, 3, "science")
  glActiveTexture(GLenum(distinctBase(GL_TEXTURE0) + TEX_UNIT_BASECOLOR))
  glBindTexture(GL_TEXTURE_2D, rengine.hdrFB.colorBufferID)

  glActiveTexture(GLenum(distinctBase(GL_TEXTURE0) + TEX_UNIT_VOLUMETRIC))
  glBindTexture(GL_TEXTURE_2D, rengine.volFB.colorBufferID)

  rengine.postprProg.SetInt("hdrVolMixType", 0)
  rengine.postprProg.SetFloat("clampPower", 0.8) #//adjustable only when hdrVolMixType !=0
  rengine.postprProg.SetFloat("gamma", 2.2)
  rengine.postprProg.SetFloat("exposure", 5.0)

  drawMesh(rengine.screenQuad, rengine.postprProg.ID)
  glEndQuery(GL_TIME_ELAPSED)

  var elapsedTime: uint64
  var totalms = float64(0.0)
  for i in 0..<4:
    glGetQueryObjectui64v(rengine.query[i], GL_QUERY_RESULT, elapsedTime.addr)
    timeOpenGLms[i] = float64(elapsedTime) / 1000000.0
    totalms = totalms + timeOpenGLms[i]
  
  timeOpenGLms[4] = totalms
  return timeOpenGLms

