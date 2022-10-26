# This code is based on two sources:
# 1)
# MIT-licensed code by Ryan Oldenburg:
# https://github.com/guzba/gltfviewer/blob/master/src/gltfviewer/shaders.nim
# 2)
# MIT-licensed code by Jack Mott:
# https://github.com/jackmott/easygl/blob/master/src/easygl/utils.nim

import opengl
import glm

type Shader* = object 
  ID*: uint32


proc getErrorLog(
  id: GLuint,
  lenProc: typeof(glGetShaderiv),
  strProc: typeof(glGetShaderInfoLog)
): string =
  ## Gets the error log from compiling or linking shaders.
  var length: GLint = 0
  lenProc(id, GL_INFO_LOG_LENGTH, length.addr)
  var log = newString(length.int)
  strProc(id, length, nil, log.cstring)
  return log

proc MakeShaders*(vertexPath: string, fragmentPath: string): Shader =

  let vertShaderSrc: string = readFile(vertexPath)
  let fragShaderSrc: string = readFile(fragmentpath)

  ## Compiles the shader files and links them into a program, returning that id.
  var vertShader, fragShader: GLuint

  # Compile the shaders
  block shaders:
    var vertShaderArray = allocCStringArray([vertShaderSrc])
    var fragShaderArray = allocCStringArray([fragShaderSrc])

    defer:
      deallocCStringArray(vertShaderArray)
      deallocCStringArray(fragShaderArray)

    # With "nimgl/opengl" we would have to dispense with deallocs
    # most likely this way:
    #let vertShaderArray = cast[cstring](vertShaderSrc)
    #let fragShaderArray = cast[cstring](fragShaderSrc)

    var isCompiled: GLint

    vertShader = glCreateShader(GL_VERTEX_SHADER)
    glShaderSource(vertShader, 1, vertShaderArray, nil)
    glCompileShader(vertShader)
    glGetShaderiv(vertShader, GL_COMPILE_STATUS, isCompiled.addr)

    if isCompiled == 0:
      echo vertShaderSrc
      echo "Vertex shader compilation failed:"
      echo getErrorLog(vertShader, glGetShaderiv, glGetShaderInfoLog)
      quit()

    fragShader = glCreateShader(GL_FRAGMENT_SHADER)
    glShaderSource(fragShader, 1, fragShaderArray, nil)
    glCompileShader(fragShader)
    glGetShaderiv(fragShader, GL_COMPILE_STATUS, isCompiled.addr)

    if isCompiled == 0:
      echo fragShaderSrc
      echo "Fragment shader compilation failed:"
      echo getErrorLog(fragShader, glGetShaderiv, glGetShaderInfoLog)
      quit()

  # Attach shaders to a GL program
  var program = glCreateProgram()
  glAttachShader(program, vertShader)
  glAttachShader(program, fragShader)

  glLinkProgram(program)

  var isLinked: GLint
  glGetProgramiv(program, GL_LINK_STATUS, isLinked.addr)
  if isLinked == 0:
    echo "Linking shaders failed:"
    echo getErrorLog(program, glGetProgramiv, glGetProgramInfoLog)
    quit()

  
  return Shader(ID: program)


proc SetBool*(s: Shader, name: string, value: bool) =
  
  var intValue: int32 = 0
  if value: intValue = 1
  let loc = glGetUniformLocation(s.ID, name)
  if loc == -1: echo "Could not find uniform: ", name
  glUniform1i(loc, intValue)


proc SetInt*(s: Shader, name: string, value: int32) =

  let loc = glGetUniformLocation(s.ID, name)
  if loc == -1: echo "Could not find uniform: ", name
  glUniform1i(loc, value)


proc SetFloat*(s: Shader, name: string, value: float32) =

  let loc = glGetUniformLocation(s.ID, name)
  if loc == -1: echo "Could not find uniform: ", name
  glUniform1f(loc, value)


proc SetVec2*(s: Shader, name: string, value: var Vec2f) =

  let loc = glGetUniformLocation(s.ID, name)
  if loc == -1: echo "Could not find uniform: ", name
  glUniform2fv(loc, 1, value.caddr)


proc SetVec3*(s: Shader, name: string, value: var Vec3f) =

  let loc = glGetUniformLocation(s.ID, name)
  if loc == -1: echo "Could not find uniform: ", name
  glUniform3fv(loc, 1, value.caddr)


proc SetMat4*(s: Shader, name: string, value: var Mat4f) =

  let loc = glGetUniformLocation(s.ID, name)
  if loc == -1: echo "Could not find uniform: ", name
  #var temp = value.transpose
  #glUniformMatrix4fv(loc, 1, false, temp.caddr)
  glUniformMatrix4fv(loc, 1, false, value.caddr)


