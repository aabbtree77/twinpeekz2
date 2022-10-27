import glm
include gltfguzbamod

import flatty/binny    
#import flatty/hexPrint

import std/typetraits

type 
  Scene* = object 
    drawables*: seq[DrawableInstance]
    lights*:    seq[Light]

  #These will be on GPU, but first preload to CPU
  MeshGeometry* = object
    vertArray*: seq[array[3,float32]]
    uvArray*:   seq[array[2,float32]]
    normArray*: seq[array[3,float32]]
    indArray*:  seq[uint32]


  MeshGPUBufferIDs* = object
    vaoID*:          uint32
    vertexBufferID*: uint32
    normalBufferID*: uint32
    uvBufferID*:     uint32
    indexBufferID*:  uint32
    lenIndices*:     int32


  DrawableInstance* = object
    mesh*:                       MeshGPUBufferIDs
    model_matrix*:               Mat4f
    baseColorTextureID*:         uint32
    metallicRoughnessTextureID*: uint32


  Light* = object
    dir*:         Vec3f
    color*:       Vec3f
    intensity*:   float32
    projView*:    Mat4f
    shMapWidth*:  int32
    shMapHeight*: int32
    txrID*:       uint32
    txrUnit*:     uint32
    FBOID*:       uint32
    rerender*:    bool
  

proc read_positions(model: Model, primitive: Primitive): seq[array[3,float32]] = 

  let
    accessor = model.accessors[primitive.attributes.position]    
    bufferView = model.bufferViews[accessor.bufferView]    
    byteOffset = accessor.byteOffset + bufferView.byteOffset    
    byteLength = accessor.count * accessor.kind.componentCount() * accessor.componentType.size()            
    binstr = model.buffers[bufferView.buffer]    

  var positions: seq[array[3,float32]]    

  if accessor.componentType.size() == 4:
    for it in countup(byteOffset, byteOffset + byteLength - 1, 12):    
      let x = binstr.readFloat32(it)     
      let y = binstr.readFloat32(it+4)     
      let z = binstr.readFloat32(it+8)     
      positions.add([x, y, z])      
      #echo it, " ", x, " ", y, " ", z    
  else:
    echo "Check GLTF accessors -> componentType, it should be 5126 (FLOAT)"
    echo "GLTF positions should be float32 of byte size 4" 
    quit(QuitFailure)
  
  return positions

proc read_normals(model: Model, primitive: Primitive): seq[array[3,float32]] = 

  let
    accessor = model.accessors[primitive.attributes.normal]    
    bufferView = model.bufferViews[accessor.bufferView]    
    byteOffset = accessor.byteOffset + bufferView.byteOffset    
    byteLength = accessor.count * accessor.kind.componentCount() * accessor.componentType.size()            
    binstr = model.buffers[bufferView.buffer]    

  var normals: seq[array[3,float32]]    

  if accessor.componentType.size() == 4:
    for it in countup(byteOffset, byteOffset + byteLength - 1, 12):    
      let x = binstr.readFloat32(it)     
      let y = binstr.readFloat32(it+4)     
      let z = binstr.readFloat32(it+8)     
      normals.add([x, y, z])      
      #echo it, " ", x, " ", y, " ", z    
  else:
    echo "Check GLTF accessors -> componentType, it should be 5126 (FLOAT)"
    echo "GLTF normals should be float32 of byte size 4" 
    quit(QuitFailure)

  return normals


proc read_uvs(model: Model, primitive: Primitive): seq[array[2,float32]] = 

  let
    accessor = model.accessors[primitive.attributes.texcoord0]    
    bufferView = model.bufferViews[accessor.bufferView]    
    byteOffset = accessor.byteOffset + bufferView.byteOffset    
    byteLength = accessor.count * accessor.kind.componentCount() * accessor.componentType.size()            
    binstr = model.buffers[bufferView.buffer]    

  var uvs: seq[array[2,float32]]    
  
  if accessor.componentType.size() == 4:
    for it in countup(byteOffset, byteOffset + byteLength - 1, 8):    
      let x = binstr.readFloat32(it)     
      let y = binstr.readFloat32(it+4)     
      uvs.add([x, y])   
  else:
    echo "Check GLTF accessors -> componentType, it should be 5126 (FLOAT)"
    echo "GLTF uvs/textcoord0 should be float32 of byte size 4" 
    quit(QuitFailure)

  return uvs


proc read_vert_indices(model: Model, primitive: Primitive): seq[uint32] = 

  let
    accessor = model.accessors[primitive.indices]    
    bufferView = model.bufferViews[accessor.bufferView]    
    byteOffset = accessor.byteOffset + bufferView.byteOffset    
    byteLength = accessor.count * accessor.kind.componentCount() * accessor.componentType.size()            
    binstr = model.buffers[bufferView.buffer]    
  #echo accessor.count, " ", accessor.kind.componentCount(), " ", 
  #     accessor.componentType.size(), " ", accessor.byteOffset
  
  var indices: seq[uint32]    
  
  if accessor.componentType.size() == 1:
    for it in countup(byteOffset, byteOffset + byteLength - 1, 1):    
      let x = binstr.readUint8(it)
      indices.add(x.uint32)     
  elif accessor.componentType.size() == 2:
    for it in countup(byteOffset, byteOffset + byteLength - 1, 2):    
      let x = binstr.readUint16(it)
      indices.add(x.uint32)     
      #echo it, " ", x    
  elif accessor.componentType.size() == 4:
    for it in countup(byteOffset, byteOffset + byteLength - 1, 4):    
      let x = binstr.readUint32(it)
      indices.add(x.uint32)     
  else:
      echo "Check GLTF accessors -> componentType, it should be in 5120..5126"
      echo "GLTF primitive.indices should be of byte size either 1, 2 or 4" 
      quit(QuitFailure)

  return indices



proc uploadMeshToGPU*(mshIN: var MeshGeometry): MeshGPUBufferIDs =

  var mshOUT: MeshGPUBufferIDs
  mshOUT.lenIndices = int32(len(mshIN.indArray))


  glGenVertexArrays(1, mshOUT.vaoID.addr)
  glBindVertexArray(mshOUT.vaoID)

  var byte_length: int
  var binstr: string 

  # vertex positions
  echo "len(mshIN.vertArray): ", len(mshIN.vertArray)
  if len(mshIN.vertArray) > 0:
    byte_length = len(mshIN.vertArray)*3*int(sizeof(float32))
    binstr = newString(byte_length)
    for it in 0..<len(mshIN.vertArray):  
      binstr.writeFloat32(12*it, mshIN.vertArray[it][0])     
      binstr.writeFloat32(12*it+4, mshIN.vertArray[it][1])     
      binstr.writeFloat32(12*it+8, mshIN.vertArray[it][2])     
                      
    glGenBuffers(1, mshOUT.vertexBufferID.addr)
    glBindBuffer(GL_ARRAY_BUFFER, mshOUT.vertexBufferID)
    glBufferData(GL_ARRAY_BUFFER, byte_length, binstr[0].addr, GL_STATIC_DRAW)

  # uvs
  echo "len(mshIN.uvArray): ", len(mshIN.uvArray)
  if len(mshIN.uvArray) > 0:
    byte_length = len(mshIN.uvArray)*2*int(sizeof(float32))
    binstr = newString(byte_length)
    for it in 0..<len(mshIN.uvArray):  
      binstr.writeFloat32(8*it, mshIN.uvArray[it][0])     
      binstr.writeFloat32(8*it+4, mshIN.uvArray[it][1])     
     
    glGenBuffers(1, mshOUT.uvBufferID.addr)
    glBindBuffer(GL_ARRAY_BUFFER, mshOUT.uvBufferID)
    glBufferData(GL_ARRAY_BUFFER, byte_length, binstr[0].addr, GL_STATIC_DRAW)

  # normals
  echo "len(mshIN.normArray): ", len(mshIN.normArray)
  if len(mshIN.normArray) > 0:
    byte_length = len(mshIN.normArray)*3*int(sizeof(float32))

    binstr = newString(byte_length)
    for it in 0..<len(mshIN.normArray):  
      binstr.writeFloat32(12*it, mshIN.normArray[it][0])     
      binstr.writeFloat32(12*it+4, mshIN.normArray[it][1])     
      binstr.writeFloat32(12*it+8, mshIN.normArray[it][2])     
     
    glGenBuffers(1, mshOUT.normalBufferID.addr)
    glBindBuffer(GL_ARRAY_BUFFER, mshOUT.normalBufferID)
    glBufferData(GL_ARRAY_BUFFER, byte_length, binstr[0].addr, GL_STATIC_DRAW)

  # vertex indices
  echo "len(mshIN.indArray): ", len(mshIN.indArray) 
  if len(mshIN.indArray) > 0:
    byte_length = len(mshIN.indArray)*1*int(sizeof(uint32))
    binstr = newString(byte_length)
    for it in 0..<len(mshIN.indArray):  
      binstr.writeUint32(4*it, mshIN.indArray[it])     

    glGenBuffers(1, mshOUT.indexBufferID.addr)
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, mshOUT.indexBufferID)
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, byte_length, binstr[0].addr, GL_STATIC_DRAW)

  return mshOUT


proc loadTextureGLTFBaseColor(model: Model, primitive: Primitive): (uint32, bool) =

  var output = (0.uint32, false) 

  if primitive.material >= 0:    
  
    let material = model.materials[primitive.material]    
    
    if material.pbrMetallicRoughness.apply:

      let baseColorTexture = material.pbrMetallicRoughness.baseColorTexture
      if baseColorTexture.index >= 0:    
        let
          texture = model.textures[baseColorTexture.index]
          image = model.images[texture.source].addr

        var textureID: uint32
        glGenTextures(1, textureID.addr)
        glBindTexture(GL_TEXTURE_2D, textureID)

        glTexImage2D( GL_TEXTURE_2D,       
                      0,    
                      GL_RGBA.GLint,        
                      image.width.GLint,    
                      image.height.GLint,    
                      0,    
                      GL_RGBA.GLenum,    
                      GL_UNSIGNED_BYTE,    
                      image.data[0].addr        
                    )    

        if texture.sampler >= 0:    
          let sampler = model.samplers[texture.sampler]    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, sampler.magFilter)    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, sampler.minFilter)    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, sampler.wrapS)    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, sampler.wrapT)    
        else:    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)

        glGenerateMipmap(GL_TEXTURE_2D)
        
        glBindTexture(GL_TEXTURE_2D, 0)
        output = (textureID, true)
  
  return output


proc loadTextureGLTFMetallicRoughness(model: Model, primitive: Primitive): (uint32, bool) =

  var output = (0.uint32, false) 
  if primitive.material >= 0:    
    let material = model.materials[primitive.material]    
    if material.pbrMetallicRoughness.apply:
      let metallicRoughnessTexture = material.pbrMetallicRoughness.metallicRoughnessTexture
      if metallicRoughnessTexture.index >= 0:    
        let
          texture = model.textures[metallicRoughnessTexture.index]
          image = model.images[texture.source].addr

        var textureID: uint32
        glGenTextures(1, textureID.addr)
        glBindTexture(GL_TEXTURE_2D, textureID)

        glTexImage2D( GL_TEXTURE_2D,       
                      0,    
                      GL_RGBA.GLint,        
                      image.width.GLint,    
                      image.height.GLint,    
                      0,    
                      GL_RGBA.GLenum,    
                      GL_UNSIGNED_BYTE,    
                      image.data[0].addr        
                    )    
    
        if texture.sampler >= 0:    
          let sampler = model.samplers[texture.sampler]    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, sampler.magFilter)    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, sampler.minFilter)    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, sampler.wrapS)    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, sampler.wrapT)    
        else:    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)    
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)

        glGenerateMipmap(GL_TEXTURE_2D)
        
        glBindTexture(GL_TEXTURE_2D, 0)
        output = (textureID, true)
  
  return output


# Fill in texture and framebuffer IDs
proc initShadowMap(lht: var Light) =

  glGenTextures(1, lht.txrID.addr)

  #Init shadow map textures
  glBindTexture(GL_TEXTURE_2D, lht.txrID)
  
  glTexImage2D( GL_TEXTURE_2D,       
                0,    
                GL_DEPTH_COMPONENT.GLint,        
                lht.shMapWidth.GLint,    
                lht.shMapHeight.GLint,    
                0,    
                GL_DEPTH_COMPONENT.GLenum,    
                cGL_FLOAT,    
                nil        
              )    

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)

  # Init FBO
  glGenFramebuffers(1, lht.FBOID.addr)
  glBindFramebuffer(GL_FRAMEBUFFER, lht.FBOID)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, lht.txrID, 0)

  glReadBuffer(GL_NONE) #No color texture will be used
  glDrawBuffer(GL_NONE) #No color texture will be used
  glBindFramebuffer(GL_FRAMEBUFFER, 0)


proc loadMeshFromGLTF(model: Model, primitive: Primitive): (MeshGeometry, bool) =
  
  let
    positions = model.read_positions(primitive)
    normals = model.read_normals(primitive)
    uvs = model.read_uvs(primitive)
    vert_indices = model.read_vert_indices(primitive)
  
  return (MeshGeometry(vertArray: positions, 
                         uvArray: uvs, 
                       normArray: normals, 
                        indArray: vert_indices), true)



proc initScene*(): Scene =

  #const folderPath = "/home/tokyo/Sponza_GLTF2_png/"
  #const gltfFileToLoad = folderPath & "Sponza.gltf"

  const folderPath = "/home/tokyo/Sponza_GLTF2/"
  const gltfFileToLoad = folderPath & "Sponza.gltf"


  #const folderPath = "/home/tokyo/Cube/glTF/"
  #const gltfFileToLoad = folderPath & "Cube.gltf"
  
  #const folderPath = "/home/tokyo/SciFiHelmet/glTF/"
  #const gltfFileToLoad = folderPath & "SciFiHelmet.gltf"



  var model: Model = loadModel(gltfFileToLoad)
  echo "Model: Json part is OK"

  #Exercise: Get bbox over all the assets to know the global scale
  var 
    loadedMeshPtrs: seq[MeshGPUBufferIDs]
    loadedTextureBaseColorIDs: seq[uint32]
    loadedTextureMetallicRoughnessIDs: seq[uint32]

  for node in model.nodes:
    if node.mesh < 0:
      continue                                 

    for it, unused in model.meshes[node.mesh].primitives:

      let primitive = model.primitives[it]

      echo it, " ", primitive.type.name 
        
      var (meshGeom, exists0) = model.loadMeshFromGLTF(primitive)
      echo "meshGeom: ", exists0, " ", meshGeom.type.name 
      if not exists0: continue
      var meshGPU  = uploadMeshToGPU(meshGeom)
      
      echo "meshGPU: ", meshGPU.type.name 

      var (textureBaseColorID, exists1) = 
        model.loadTextureGLTFBaseColor(primitive)
      echo "textureBaseColorID: ", exists1, " ", textureBaseColorID.type.name 
      if not exists1: continue

      var (textureMetallicRoughnessID, exists2) = 
        model.loadTextureGLTFMetallicRoughness(primitive)
      echo "textureMetallicRoughnessID: ", exists2, " ", textureMetallicRoughnessID.type.name 
      if not exists2: continue

      loadedMeshPtrs.add(meshGPU)
      loadedTextureBaseColorIDs.add(textureBaseColorID)
      loadedTextureMetallicRoughnessIDs.add(textureMetallicRoughnessID)
      echo "Loaded primitive: ", $it

  #[ This does not work:
  var mWorldCommon = mat4f(
    1.0'f32, 0.0'f32, 0.0'f32, 0.0'f32,
    0.0'f32, 1.0'f32, 0.0'f32, 0.0'f32,
    0.0'f32, 0.0'f32, 1.0'f32, 0.0'f32,
    0.0'f32, 0.0'f32, 0.0'f32, 1.0'f32)
   ]#

  # This is the way: 
  var mWorldCommon = mat4f(
    vec4f(1.0, 0.0, 0.0, 0.0),
    vec4f(0.0, 1.0, 0.0, 0.0),
    vec4f(0.0, 0.0, 1.0, 0.0),
    vec4f(0.0, 0.0, 0.0, 1.0))

  var instances: seq[DrawableInstance]
  
  for i in 0..<len(loadedMeshPtrs):
    var inst = DrawableInstance(
      mesh: loadedMeshPtrs[i],
      model_matrix: mWorldCommon,
      baseColorTextureID: loadedTextureBaseColorIDs[i],
      metallicRoughnessTextureID: loadedTextureMetallicRoughnessIDs[i])
    instances.add(inst)
  
  var lights: seq[Light]

  var light0 = Light(
          dir:         vec3f(0.1, -0.6, -1.0),
          color:       vec3f(1.0 * 2.0, 0.8 * 2.0, 0.6 * 2.0),
          intensity:   900.0,
          shMapWidth:  4096,
          shMapHeight: 4096,
          rerender:    true)

  var light1 = Light(
          dir:         vec3f(1, -0.25, -0.25),
          color:       vec3f(1.0 * 2.0, 0.8 * 2.0, 0.6 * 2.0),
          intensity:   900.0,
          shMapWidth:  4096,
          shMapHeight: 4096,
          rerender:    true)

  light0.initShadowMap()
  #light1.initShadowMap()

  lights.add(light0)
  #lights.add(light1)

  return Scene(drawables: instances, lights: lights)

