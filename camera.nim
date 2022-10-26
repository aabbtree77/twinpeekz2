import nimgl/glfw
import glm
import math

const Z_AXIS = vec3f(0.0, 0.0, 1.0)

type Camera* = object
  view*:        Mat4f
  proj*:        Mat4f
  projView*:    Mat4f
  invProjView*: Mat4f

  pos*: Vec3f
  dir*: Vec3f
  up*:  Vec3f

  pitch*: float32
  yaw*:   float32

  fovDeg*:      float32
  aspectRatio*: float32
  zNear*:       float32
  zFar*:        float32

  shiftSpeed*: float32
  rotSpeed*:   float32
  mouseSpeed*: float32
  firstMouse*: bool
  lastX*:      float32
  lastY*:      float32


proc UpdateOrientation*(cam: var Camera, pos, dir, up: Vec3f) =

  cam.pos = pos
  cam.dir = dir.normalize()
  cam.up = up

  let radius = length(vec2f(cam.dir[0], cam.dir[1]))
  cam.pitch = degrees(arctan2(cam.dir[2], radius))
  cam.yaw = degrees(arctan2(cam.dir[1], cam.dir[0]))

  let center = pos + cam.dir
  cam.view = lookAt(pos, center, up)
  cam.projView = cam.proj * cam.view
  cam.invProjView = cam.projView.inverse


proc UpdateProjection*(cam: var Camera, fov, zNear, zFar: float32) =

  cam.fovDeg = fov
  cam.zNear = zNear
  cam.zFar = zFar
  cam.proj = perspective(radians(cam.fovDeg), cam.aspectRatio, zNear, zFar)
  cam.projView = cam.proj * cam.view
  cam.invProjView = cam.projView.inverse


proc UpdateAspectRatio*(cam: var Camera, aspectRatio: float32) =

  cam.aspectRatio = aspectRatio
  cam.proj = perspective(radians(cam.fovDeg), 
                  cam.aspectRatio, cam.zNear, cam.zFar)
  cam.projView = cam.proj * cam.view
  cam.invProjView = cam.projView.inverse


proc makeCam*(): Camera =

  var cam: Camera
  # Sponza takes approx 30x17x12 meters centered roughly at the origin
  cam.UpdateOrientation(vec3f(10.0, -4.5, 4.0), vec3f(-1.0, 0.9, 0.0), Z_AXIS)
  cam.aspectRatio = 1.0
  cam.UpdateProjection(45.0, 0.1, 100.0)
  cam.shiftSpeed = float32(1.5)
  cam.rotSpeed = float32(40.0)
  cam.mouseSpeed = float32(0.1)
  cam.firstMouse = true
  return cam


proc Translate*(cam: var Camera, trans: Vec3f) =

  cam.pos = cam.pos + trans
  let center = cam.pos + cam.dir
  cam.view = lookAt(cam.pos, center, cam.up)
  cam.projView = cam.proj * cam.view
  cam.invProjView = cam.projView.inverse


proc Rotate*(cam: var Camera, dpitch, dyaw: float32) =

  cam.pitch = max(-89.5, min(cam.pitch+dpitch, 89.5))
  cam.yaw = cam.yaw + dyaw

  cam.dir[0] = cos(radians(cam.pitch)) * cos(radians(cam.yaw))
  cam.dir[1] = cos(radians(cam.pitch)) * sin(radians(cam.yaw))
  cam.dir[2] = sin(radians(cam.pitch))
  cam.dir = cam.dir.normalize

  let center = cam.pos + cam.dir
  cam.view = lookAt(cam.pos, center, cam.up)
  cam.projView = cam.proj * cam.view
  cam.invProjView = cam.projView.inverse


proc updateViaKeyboard*(cam: var Camera, wn: GLFWWindow, deltaT: float64) =

  let
    shiftIncr = float32(cam.shiftSpeed * float32(deltaT))
    rotIncr = float32(cam.rotSpeed * float32(deltaT))

  if wn.getKey(GLFWKey.W) == GLFWPress:
    var dir = cam.dir
    dir[2] = 0.0
    dir = dir.normalize
    cam.Translate(dir * shiftIncr)
  
  if wn.getKey(GLFWKey.S) == GLFWPress: 
    var dir = cam.dir * (-1.0)
    dir[2] = 0.0
    dir = dir.normalize
    cam.Translate(dir * shiftIncr)
  
  if wn.getKey(GLFWKey.A) == GLFWPress: 
    var right = cross(cam.dir, Z_AXIS)
    cam.Translate(right.normalize * (-shiftIncr))
  
  if wn.getKey(GLFWKey.D) == GLFWPress: 
    var right = cross(cam.dir, Z_AXIS)
    cam.Translate(right.normalize * shiftIncr)
  
  if wn.getKey(GLFWKey.E) == GLFWPress: 
    cam.Translate(Z_AXIS * shiftIncr)
  
  if wn.getKey(GLFWKey.C) == GLFWPress:
    cam.Translate(Z_AXIS * (-shiftIncr))
  
  if wn.getKey(GLFWKey.Up) == GLFWPress:
    cam.Rotate(rotIncr, 0.0)
  
  if wn.getKey(GLFWKey.Left) == GLFWPress:
    cam.Rotate(0.0, rotIncr)
  
  if wn.getKey(GLFWKey.Down) == GLFWPress:
    cam.Rotate(-rotIncr, 0.0)
  
  if wn.getKey(GLFWKey.Right) == GLFWPress:
    cam.Rotate(0.0, -rotIncr)
  
