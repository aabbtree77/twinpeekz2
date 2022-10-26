import nimgl/glfw
#import nimgl/opengl
import opengl
import glm #this changes echo mat4f type, no nice output without this
import std/strutils
import std/typetraits

import scene
import rendering
import camera

type Window_State_Struct* = object
  pos*, size*: array[2, int32]
  full_scr_state*:  bool
  full_scr_change*: bool
  cam*:           Camera
  rengine*:       RenderEngine

var WINDOW_STATE*: Window_State_Struct


proc mouseCamRotate(wn: GLFWWindow, xPos, yPos: float64): void {.cdecl.} = 

  if WINDOW_STATE.cam.firstMouse: 
    WINDOW_STATE.cam.lastX = float32(xPos)
    WINDOW_STATE.cam.lastY = float32(yPos)
    WINDOW_STATE.cam.firstMouse = false
 
  var
    xOffset = float32(xPos) - WINDOW_STATE.cam.lastX
    yOffset = WINDOW_STATE.cam.lastY - float32(yPos)

  WINDOW_STATE.cam.lastX = float32(xPos)
  WINDOW_STATE.cam.lastY = float32(yPos)

  xOffset = xOffset * WINDOW_STATE.cam.mouseSpeed
  yOffset = yOffset * WINDOW_STATE.cam.mouseSpeed
  WINDOW_STATE.cam.Rotate(yOffset, xOffset)


proc mouseZoom(wn: GLFWWindow, xOffset, yOffset: float64): void {.cdecl.} =
        
  var fovDeg = WINDOW_STATE.cam.fovDeg
  fovDeg = fovDeg + float32(yOffset)
  
  if fovDeg < 1.0:
    WINDOW_STATE.cam.fovDeg = 1.0
  
  if fovDeg > 45.0: 
    WINDOW_STATE.cam.fovDeg = 45.0
  
  if fovDeg >= 1.0 and fovDeg <= 45.0:
    WINDOW_STATE.cam.fovDeg = fovDeg
 
  let fvdeg = WINDOW_STATE.cam.fovDeg
  UpdateProjection(WINDOW_STATE.cam,
                   WINDOW_STATE.cam.fovDeg, 
                   WINDOW_STATE.cam.zNear, 
                   WINDOW_STATE.cam.zFar)


proc key_handler(ww: GLFWWindow, key: int32, scan: int32, 
                 action: int32, mods: int32): void {.cdecl.} =

  if key == GLFWKey.Escape and action == GLFWPress:
    if false:
      echo "Escape pressed"
      echo "Cam matrices after Rendering Loop:"
      echo "proj: "
      echo WINDOW_STATE.cam.proj.type.name
      echo $cast[Mat4[system.float32]](WINDOW_STATE.cam.proj)
      echo "view: "
      echo WINDOW_STATE.cam.view
      echo "projView: "
      echo WINDOW_STATE.cam.projView
      echo "invProjView: "
      echo WINDOW_STATE.cam.invProjView

    ww.setWindowShouldClose(true)

  if key == GLFWKey.F11 and action == GLFWPress:
    echo "F11 pressed"
    WINDOW_STATE.full_scr_change = true
        

proc fb_resize(ww: GLFWWindow, width: int32, height: int32): void {.cdecl.} = 
  WINDOW_STATE.cam.UpdateAspectRatio(float32(width) / float32(height))
  WINDOW_STATE.rengine.width = int32(width)
  WINDOW_STATE.rengine.height = int32(height)
  resizeRendering(WINDOW_STATE.rengine)
  glViewport(0, 0, width, height)

proc main(): void =

  discard glfwInit()

  glfwWindowHint(GLFWResizable, GLFW_TRUE)
  glfwWindowHint(GLFWContextVersionMajor, 4)
  glfwWindowHint(GLFWContextVersionMinor, 1)
  glfwWindowHint(GLFWOpenGLProfile, GLFWOpenGLCoreProfile)

  var mon: GLFWMonitor = glfwGetPrimaryMonitor()
  var vmode: ptr GLFWVidmode = mon.getVideoMode()
  let window = glfwCreateWindow(vmode.width, vmode.height, "Sponza", nil, nil)
  window.makeContextCurrent()

  # Init OpenGL:
  #
  # For "nimgl/opengl":
  # discard glInit()
  # echo "OpenGL ", $glVersionMajor , "." , $glVersionMinor
  #
  # For "opengl":
  loadExtensions()
  let glVersion = cast[cstring](glGetString(GL_VERSION))
  echo glVersion

  window.getWindowSize(WINDOW_STATE.size[0].addr, WINDOW_STATE.size[1].addr)
  window.getWindowPos(WINDOW_STATE.pos[0].addr, WINDOW_STATE.pos[1].addr)
  WINDOW_STATE.full_scr_state = false


  #//Init scene, rendering
  #//-------------------------------------------------------------------------------------------------------------------------
  var scene = initScene()
  echo "Drawables: ", len(scene.drawables)
  echo "Lights: ", len(scene.lights)

  var
    fbWidth: int32
    fbHeight: int32
  window.getFramebufferSize(fbWidth.addr, fbHeight.addr)

  WINDOW_STATE.cam = makeCam()
  WINDOW_STATE.cam.UpdateAspectRatio(float32(fbWidth) / float32(fbHeight))

  WINDOW_STATE.rengine = scene.initRendering(int32(fbWidth), int32(fbHeight))
  resizeRendering(WINDOW_STATE.rengine)
  
  #Lock and hide mouse cursor
  window.setInputMode(GLFWCursorSpecial, GLFWCursorHidden)

  discard window.setKeyCallback(key_handler)
  discard window.setFramebufferSizeCallback(fb_resize)
  discard window.setCursorPosCallback(GLFWCursorposfun(mouseCamRotate))
  discard window.setScrollCallback(GLFWScrollfun(mouseZoom))

  if false:
    echo "Cam matrices before Rendering Loop:"
    echo "proj: "
    echo WINDOW_STATE.cam.proj
    echo "view: "
    echo WINDOW_STATE.cam.view
    echo "projView: "
    echo WINDOW_STATE.cam.projView
    echo "invProjView: "
    echo WINDOW_STATE.cam.invProjView
    echo "invProjViewtemp: "
    var temp = WINDOW_STATE.cam.invProjView
    echo temp



  #Rendering loop
  #[-----------------------------------------------------------------------
  /*Enable v-sync (0-off, 1-on in glfwSwapInterval)
  You might also need adjust your card settings, i.e. executing this helped for my GTX 760 setup:
  nvidia-settings --assign CurrentMetaMode="nvidia-auto-select +0+0 { ForceFullCompositionPipeline = On }"
  See https://github.com/godlikepanos/anki-3d-engine/issues/59
  ]#
  
  glfwSwapInterval(0)

  var time_OpenGL_ms: array[5, float64]

  var time_passed_sec: float64 = glfwGetTime()
  var time_start_sec = time_passed_sec
  var frames: int = 0
  var fps: float64 = 0.0
  var deltaT: float64 = 0.0

  while not window.windowShouldClose:

    time_passed_sec = glfwGetTime()
    
    if (time_passed_sec-time_start_sec > 1.0) and (frames > 10):
      deltaT = (time_passed_sec-time_start_sec)/float64(frames)
      fps = 1.0/deltaT
      time_start_sec = time_passed_sec
      frames = 0
      #echo("deltaT = ", (deltaT*1000.0).formatFloat(ffDecimal, 4), "ms., FPS = ", 
      #fps.formatFloat(ffDecimal, 1))
    
    frames = frames + 1

    WINDOW_STATE.cam.updateViaKeyboard(window, deltaT)
    #echo "deltaT = ", (deltaT*1000.0).formatFloat(ffDecimal, 2), "ms." 

    if WINDOW_STATE.full_scr_change:
      if not WINDOW_STATE.full_scr_state:
        #Save non-full scr window pos and size to restore it later
        window.getWindowSize(WINDOW_STATE.size[0].addr, WINDOW_STATE.size[1].addr)
        window.getWindowPos(WINDOW_STATE.pos[0].addr, WINDOW_STATE.pos[1].addr)

        mon = glfwGetPrimaryMonitor()
        vmode = mon.getVideoMode()
        window.setWindowMonitor(mon, 0, 0, vmode.width, vmode.height, vmode.refreshRate)
        #TD: update camera, viewport gets updated automatically via resize callback?!
      else:
        mon = glfwGetPrimaryMonitor()
        vmode = mon.getVideoMode()
        window.setWindowMonitor(nil, WINDOW_STATE.pos[0], WINDOW_STATE.pos[1], 
                          WINDOW_STATE.size[0], WINDOW_STATE.size[1], vmode.refreshRate)
        #TD: update camera, viewport gets updated automatically via resize callback?!
                        
      WINDOW_STATE.full_scr_state = not WINDOW_STATE.full_scr_state
      WINDOW_STATE.full_scr_change = false
              

    time_OpenGL_ms = scene.mainRendering(WINDOW_STATE.rengine, WINDOW_STATE.cam)
    #fmt.Println("time_OpenGL_ms=", time_OpenGL_ms)

    window.swapBuffers()
    glfwPollEvents()
        
main()
