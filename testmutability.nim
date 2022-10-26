import glm
import typetraits

type
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
 

var lights: seq[Light]

var light0 = Light(
        dir:         vec3f(1.0, -0.5, -0.5),
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


lights.add(light0)
lights.add(light1)


for it in lights:  
  #echo lights[it].intensity
  echo it.type.name
  var varit = it
  varit.intensity = 1000.0
  echo it.intensity, " ", varit.intensity
