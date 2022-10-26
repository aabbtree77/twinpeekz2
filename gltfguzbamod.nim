import base64, json, pixie, os, opengl, glm, strformat, strutils, flatty/binny


type
  
  BufferView* = object
    buffer*: int
    byteOffset*, byteLength*, byteStride*: Natural

  Texture = object
    source: Natural
    sampler: int

  Sampler = object
    magFilter, minFilter, wrapS, wrapT: GLint

  BaseColorTexture = object
    index: int

  MetallicRoughnessTexture = object
    index: int

  PBRMetallicRoughness = object
    apply: bool
    baseColorTexture: BaseColorTexture
    metallicRoughnessTexture: MetallicRoughnessTexture

  Material = object
    name: string
    pbrMetallicRoughness: PBRMetallicRoughness

  InterpolationKind = enum
    iLinear, iStep, iCubicSpline

  AnimationSampler = object
    input, output: Natural # Accessor indices
    interpolation: InterpolationKind

  AnimationPath = enum
    pTranslation, pRotation, pScale, pWeights

  AnimationTarget = object
    node: Natural
    path: AnimationPath

  AnimationChannel = object
    sampler: Natural
    target: AnimationTarget

  AnimationState = object
    prevTime: float
    prevKey: int

  Animation = object
    samplers: seq[AnimationSampler]
    channels: seq[AnimationChannel]

  AccessorKind = enum
    atSCALAR, atVEC2, atVEC3, atVEC4, atMAT2, atMAT3, atMAT4

  Accessor* = object
    bufferView*, byteOffset*, count*: Natural
    componentType*: GLenum
    kind*: AccessorKind

  PrimitiveAttributes* = object
    position*, normal*, color0*, texcoord0*: int

  Primitive* = object
    attributes*: PrimitiveAttributes
    indices, material: int
    mode: GLenum

  Mesh = object
    name: string
    primitives*: seq[Natural]

  Node = object
    name: string
    kids: seq[Natural]
    mesh*: int
    applyMatrix: bool
    matrix: Mat4f
    rotation: Vec4f
    translation, scale: Vec3f

  Scene_GLTF = object
    nodes: seq[Natural]

  Model* = ref object
    # All of the data that is indexed into
    buffers*: seq[string]
    bufferViews*: seq[BufferView]
    textures*: seq[Texture]
    samplers*: seq[Sampler]
    images*: seq[Image]
    animations*: seq[Animation]
    materials*: seq[Material]
    accessors*: seq[Accessor]
    primitives*: seq[Primitive]
    meshes*: seq[Mesh]
    nodes*: seq[Node]
    scenes*: seq[Scene_GLTF]

    # State
    bufferIds*, textureIds*, vertexArrayIds*: seq[GLuint]
    animationState*: seq[AnimationState]

    # Model properties
    scene*: Natural

func size(componentType: GLenum): Natural =
  case componentType:
    of cGL_BYTE, cGL_UNSIGNED_BYTE:
      1
    of cGL_SHORT, cGL_UNSIGNED_SHORT:
      2
    of GL_UNSIGNED_INT, cGL_FLOAT:
      4
    else:
      raise newException(Exception, "Unexpected componentType")

func componentCount(accessorKind: AccessorKind): Natural =
  case accessorKind:
    of atSCALAR:
      1
    of atVEC2:
      2
    of atVEC3:
      3
    of atVEC4, atMAT2:
      4
    of atMAT3:
      9
    of atMAT4:
      16

template read[T](buffer: ptr string, byteOffset: int, index = 0): auto =
  cast[ptr T](buffer[byteOffset + (index * sizeof(T))].addr)[]

proc readVec3f(buffer: ptr string, byteOffset, index: int): Vec3f =
  var v: Vec3f
  v[0] = read[float32](buffer, byteOffset, index)
  v[1] = read[float32](buffer, byteOffset, index + 1)
  v[2] = read[float32](buffer, byteOffset, index + 2)
  return v

proc readVec4f(buffer: ptr string, byteOffset, index: int): Vec4f =
  var q: Vec4f
  q[0] = read[float32](buffer, byteOffset, index)
  q[1] = read[float32](buffer, byteOffset, index + 1)
  q[2] = read[float32](buffer, byteOffset, index + 2)
  q[3] = read[float32](buffer, byteOffset, index + 3)
  return q


proc loadModelJson*(
    jsonRoot: JsonNode,
    modelDir = "",
    buffers: seq[string] = @[]
  ): Model =

  result = Model()

  var bufferIndex = 0
  for entry in jsonRoot["buffers"]:
    var data: string
    if "uri" in entry:
      let uri = entry["uri"].getStr()
      if uri.startsWith("data:application/"):
        data = decode(uri.split(',')[1])
      else:
        data = readFile(joinPath(modelDir, uri))
    else:
      data = buffers[bufferIndex][0 ..< entry["byteLength"].getInt()]
      inc bufferIndex
    assert len(data) == entry["byteLength"].getInt()
    result.buffers.add(data)

  for entry in jsonRoot["bufferViews"]:
    var bufferView = BufferView()
    bufferView.buffer = entry["buffer"].getInt()
    bufferView.byteOffset = entry{"byteOffset"}.getInt()
    bufferView.byteLength = entry["byteLength"].getInt()
    bufferView.byteStride = entry{"byteStride"}.getInt()

    if entry.hasKey("target"):
      let target = entry["target"].getInt()
      if target notin @[GL_ARRAY_BUFFER.int, GL_ELEMENT_ARRAY_BUFFER.int]:
        raise newException(Exception, &"Invalid bufferView target {target}")

    result.bufferViews.add(bufferView)

  if jsonRoot.hasKey("textures"):
    for entry in jsonRoot["textures"]:
      var texture = Texture()
      texture.source = entry["source"].getInt()

      if entry.hasKey("sampler"):
        texture.sampler = entry["sampler"].getInt()
      else:
        texture.sampler = -1

      result.textures.add(texture)

  if jsonRoot.hasKey("images"):
    for entry in jsonRoot["images"]:
      var image: Image
      if entry.hasKey("uri"):
        let uri = entry["uri"].getStr()
        if uri.startsWith("data:image/png"):
          image = decodeImage(decode(uri.split(',')[1]))
        elif uri.endsWith(".png") or uri.endsWith(".jpg") or uri.endsWith(".jpeg"):
          image = readImage(joinPath(modelDir, uri))
        else:
          raise newException(Exception, &"Unsupported file extension {uri}")
      elif entry.hasKey("bufferView"):
        let
          bufferViewIndex = entry["bufferView"].getInt()
          bv = result.bufferViews[bufferViewIndex]
          ib = result.buffers[bv.buffer]
          imageData = ib[bv.byteOffset ..< bv.byteOffset + bv.byteLength]
        image = decodeImage(imageData)
      else:
        raise newException(Exception, "Unsupported image type")

      result.images.add(image)

  if jsonRoot.hasKey("samplers"):
    for entry in jsonRoot["samplers"]:
      var sampler = Sampler()

      if entry.hasKey("magFilter"):
        sampler.magFilter = entry["magFilter"].getInt().GLint
      else:
        sampler.magFilter = GL_LINEAR

      if entry.hasKey("minFilter"):
        sampler.minFilter = entry["minFilter"].getInt().GLint
      else:
        sampler.minFilter = GL_LINEAR_MIPMAP_LINEAR

      if entry.hasKey("wrapS"):
        sampler.wrapS = entry["wrapS"].getInt().GLint
      else:
        sampler.wrapS = GL_REPEAT

      if entry.hasKey("wrapT"):
        sampler.wrapT = entry["wrapT"].getInt().GLint
      else:
        sampler.wrapT = GL_REPEAT

      result.samplers.add(sampler)

  if jsonRoot.hasKey("materials"):
    for entry in jsonRoot["materials"]:
      var material = Material()
      material.name = entry{"name"}.getStr()

      if entry.hasKey("pbrMetallicRoughness"):
        let pbrMetallicRoughness = entry["pbrMetallicRoughness"]
        material.pbrMetallicRoughness.apply = true
        
        if pbrMetallicRoughness.hasKey("baseColorTexture"):
          let baseColorTexture = pbrMetallicRoughness["baseColorTexture"]
          material.pbrMetallicRoughness.baseColorTexture.index =
            baseColorTexture["index"].getInt()
        else:
          material.pbrMetallicRoughness.baseColorTexture.index = -1
        
        if pbrMetallicRoughness.hasKey("metallicRoughnessTexture"):
          let metallicRoughnessTexture = pbrMetallicRoughness["metallicRoughnessTexture"]
          material.pbrMetallicRoughness.metallicRoughnessTexture.index =
            metallicRoughnessTexture["index"].getInt()
        else:
          material.pbrMetallicRoughness.metallicRoughnessTexture.index = -1


      result.materials.add(material)

  if jsonRoot.hasKey("animations"):
    for entry in jsonRoot["animations"]:
      var animation = Animation()

      for entry in entry["samplers"]:
        var animationSampler = AnimationSampler()
        animationSampler.input = entry["input"].getInt()
        animationSampler.output = entry["output"].getInt()

        let interpolation = entry["interpolation"].getStr()
        case interpolation:
          of "LINEAR":
            animationSampler.interpolation = iLinear
          of "STEP":
            animationSampler.interpolation = iStep
          of "CUBICSPLINE":
            animationSampler.interpolation = iCubicSpline
          else:
            raise newException(
              Exception,
              &"Unsupported animation sampler interpolation {interpolation}"
            )

        animation.samplers.add(animationSampler)

      for entry in entry["channels"]:
        var animationChannel = AnimationChannel()
        animationChannel.sampler = entry["sampler"].getInt()
        animationChannel.target.node = entry["target"]["node"].getInt()

        let path = entry["target"]["path"].getStr()
        case path:
          of "translation":
            animationChannel.target.path = pTranslation
          of "rotation":
            animationChannel.target.path = pRotation
          of "scale":
            animationChannel.target.path = pScale
          of "weights":
            animationChannel.target.path = pWeights
          else:
            raise newException(
              Exception,
              &"Unsupported animation channel path {path}"
            )

        animation.channels.add(animationChannel)

      result.animations.add(animation)

  for entry in jsonRoot["accessors"]:
    var accessor = Accessor()
    #echo entry["bufferView"].getInt()
    accessor.bufferView = entry["bufferView"].getInt()
    accessor.byteOffset = entry{"byteOffset"}.getInt()
    accessor.count = entry["count"].getInt()
    accessor.componentType = entry["componentType"].getInt().GLenum

    let accessorKind = entry["type"].getStr()
    case accessorKind:
      of "SCALAR":
        accessor.kind = atSCALAR
      of "VEC2":
        accessor.kind = atVEC2
      of "VEC3":
        accessor.kind = atVEC3
      of "VEC4":
        accessor.kind = atVEC4
      of "MAT2":
        accessor.kind = atMAT2
      of "MAT3":
        accessor.kind = atMAT3
      of "MAT4":
        accessor.kind = atMAT4
      else:
        raise newException(
          Exception,
          &"Invalid accessor type {accessorKind}"
        )

    result.accessors.add(accessor)

  for entry in jsonRoot["meshes"]:
    var mesh = Mesh()
    mesh.name = entry{"name"}.getStr()

    for entry in entry["primitives"]:
      var
        primitive = Primitive()
        attributes = entry["attributes"]

      if attributes.hasKey("POSITION"):
        primitive.attributes.position = attributes["POSITION"].getInt()
      else:
        primitive.attributes.position = -1

      if attributes.hasKey("NORMAL"):
        primitive.attributes.normal = attributes["NORMAL"].getInt()
      else:
        primitive.attributes.normal = -1

      if attributes.hasKey("COLOR_0"):
        primitive.attributes.color0 = attributes["COLOR_0"].getInt()
      else:
        primitive.attributes.color0 = -1

      if attributes.hasKey("TEXCOORD_0"):
        primitive.attributes.texcoord0 = attributes["TEXCOORD_0"].getInt()
      else:
        primitive.attributes.texcoord0 = -1

      if entry.hasKey("indices"):
        primitive.indices = entry["indices"].getInt()
      else:
        primitive.indices = -1

      if entry.hasKey("material"):
        primitive.material = entry["material"].getInt()
      else:
        primitive.material = -1

      if entry.hasKey("mode"):
        primitive.mode = entry["mode"].getInt().GLenum
      else:
        primitive.mode = GL_TRIANGLES

      result.primitives.add(primitive)
      mesh.primitives.add(len(result.primitives) - 1)

    result.meshes.add(mesh)

  for entry in jsonRoot["nodes"]:
    var node = Node()
    node.name = entry{"name"}.getStr()

    if entry.hasKey("children"):
      for child in entry["children"]:
        node.kids.add(child.getInt())

    if entry.hasKey("mesh"):
      node.mesh = entry["mesh"].getInt()
    else:
      node.mesh = -1

    if entry.hasKey("matrix"):
      node.applyMatrix = true

      let values = entry["matrix"]
      assert len(values) == 16
      for i in 0 ..< 4:
        for j in 0 ..< 4:
          node.matrix[i, j] = values[j * 4 + i].getFloat().float32

    if entry.hasKey("rotation"):
      let values = entry["rotation"]
      assert len(values) == 4
      node.rotation[0] = values[0].getFloat().float32
      node.rotation[1] = values[1].getFloat().float32
      node.rotation[2] = values[2].getFloat().float32
      node.rotation[3] = values[3].getFloat().float32

    if entry.hasKey("translation"):
      let values = entry["translation"]
      assert len(values) == 3
      node.translation[0] = values[0].getFloat().float32
      node.translation[1] = values[1].getFloat().float32
      node.translation[2] = values[2].getFloat().float32

    if entry.hasKey("scale"):
      let values = entry["scale"]
      assert len(values) == 3
      node.scale[0] = values[0].getFloat().float32
      node.scale[1] = values[1].getFloat().float32
      node.scale[2] = values[2].getFloat().float32

    result.nodes.add(node)

  for entry in jsonRoot["scenes"]:
    var scene = Scene_GLTF()
    for node in entry["nodes"]:
      scene.nodes.add(node.getInt())
    result.scenes.add(scene)

  result.scene = jsonRoot["scene"].getInt()

proc loadModelJsonFile*(file: string): Model =
  result = Model()
  let
    jsonRoot = parseJson(readFile(file))
    modelDir = splitPath(file)[0]

  return loadModelJson(jsonRoot, modelDir=modelDir)

proc loadModelBinaryFile*(file: string): Model =
  let
    data = string(readFile(file))
    magic = data.readUint32(0)
    version = data.readUint32(4)
    length = data.readUint32(8)

  doAssert magic == 0x46546C67
  doAssert version == 2
  doAssert length.int == data.len

  var
    i = 12
    jsonData: string
    buffers: seq[string]
  while i < data.len:
    var
      chunkLength = data.readUint32(i)
      chunkType = data.readUint32(i+4)
      chunkData = data.readStr(i+8, chunkLength.int)
      isJson = chunkType == 0x4E4F534A
    i += 8 + chunkLength.int
    if isJson:
      jsonData = chunkData
    else:
      buffers.add(chunkData)

  loadModelJson(parseJson(jsonData), buffers=buffers)

proc loadModel*(file: string): Model =
  echo &"Loading {file}"
  if file.endsWith(".glb"):
    loadModelBinaryFile(file)
  else:
    loadModelJsonFile(file)
