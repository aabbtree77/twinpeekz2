> “These mist covered mountains <br>
> Are a home now for me <br>
> But my home is the lowlands <br>
> And always will be”<br>

This is the Nim rewrite of [the code in Go](https://github.com/aabbtree77/twinpeekz).

<table align="center">
    <tr>
    <th align="center">Volumetric Lighting</th>
    </tr>
    <tr>
    <td>
    <img src="./Scr-2022-10-25-red.png"  alt="Sponza rendered in Nim" width="100%" >
    </td>
    </tr>
</table>


## Setup

```console
nimble install nimgl opengl glm flatty
nim c -r --hints:off -d:release main.nim 
```

## Nim Setup

* Install Nim via [Choosenim](https://www.linuxhowto.net/how-to-install-nim-programming-language-on-linux/):

    ```console
    curl https://nim-lang.org/choosenim/init.sh -sSf | sh
    ...
    tokyo@tokyo-Z87-DS3H:~$ nim -v
    Nim Compiler Version 1.6.8 [Linux: amd64]
    Compiled at 2022-09-27
    Copyright (c) 2006-2021 by Andreas Rumpf

    git hash: c9f46ca8c9eeca8b5f68591b1abe14b962f80a4c
    active boot switches: -d:release
    ```

    Set the path in ".bashrc" as indicated in the command prompt.

    Consider a more specialized [text editor] which can at least highlight the Nim code.
    My choice is [NeoVim](https://github.com/nim-lang/Nim/wiki/Editor-Support) as I prefer something simple snappy lightweight. Its Nim plugin is newer than that of Vim.

* Install NeoVim:

    ```console
    sudo apt install neovim -y
    mkdir $HOME/.config/nvim
    ```

* Install [Plug](https://github.com/junegunn/vim-plug#neovim):

    ```console
    sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
         https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
    cd $HOME/.config/nvim
    gedit init.vim     
    ```

* Install this [NeoVim plugin](https://github.com/alaviss/nim.nvim/issues/19) 
  
    Copy-paste and save this into init.vim:
    
    ```
    call plug#begin('~/.vim/plugged')
    Plug 'alaviss/nim.nvim'
    call plug#end()  
    
    set nofoldenable
    ```
    
    Add this line to ~/.vim/plugged/nim.nvim/syntax/nim.vim:
    
    ```
    highlight link nimSugUnknown NONE
    ```
    
    in order to remove red highlights for unknown symbols, clf. [this issue](https://github.com/alaviss/nim.nvim/issues/39).
    
    Run nvim, press Esc and :PlugInstall, :q, restart nvim. Use gd and ctrl+o to jump/get back into type/function definitions.
    
* Compile and run [gltfviewer](https://github.com/guzba/gltfviewer) to test it all:

    ```console
    git clone https://github.com/guzba/gltfviewer.git $HOME/gltfviewer
    cd $HOME/gltfviewer
    nimble install
    nim c -r ./src/gltfviewer.nim
    ```    

# Further Comments/Random Thoughts

A perennial question is whether a modern static non-GC language such as Nim could become the one. I will share my experience/doubts about it.
There are also a few tricky points and choices documented here in case someone or future me will use this code/rewrite it in some language X.

## GLFW/Windowing

**Tricky point:** passing user data into the GLFW window event callback functions. 

There are three ways: (i) global/static variables,
(ii) [glfwgetwindowuserpointer](https://discourse.glfw.org/t/what-is-a-possible-use-of-glfwgetwindowuserpointer/1294/2), and (iii) lambda functions.

Go: I tried all the three ways and chose the third option as it was remarkably simple, just use mydata.f(...) instead of the usual f(...) and f sees all the variables in mydata when called, meeting all the original callback signature requirements of f(...) as if mydata did not even exist. 

Nim: Nim allows one to change [the scope of the functions with pragmas](https://nim-lang.org/docs/manual.html#types-procedural-type), IIAR. However, the callback functions are already defined with the "{.cdecl.}" pragma in the GLFW bindings which would not let the callbacks be turned into lambdas with "{.closure.}". So I went the global/static variable way.

## GLTF Loading

GLTF requires parsing json and following the GLTF 2.0 spec to load data into code.

**Tricky point 1**. [GLTF viewer](https://github.com/guzba/gltfviewer) is a lot slower than [this surprisingly fast library in Go](https://github.com/qmuntal/gltf/issues/26).
The problem is that the Nim code reads all the images into a big intermediate Nim sequence of images before uploading them into the GPU buffers. I only made this even slower by pre-extracting the mesh data on the CPU in a similar way. In addition, there is always some "ref object" in Nim waiting to be replaced with "object". Interestingly, this problem disappears when compiling with "d:release" or even "d:danger" flags. Without them, it takes about 25s. to load Sponza, with them it is as instantaneous as the Go code. 

**Tricky point 2:** The possibility of 1-byte or 2-byte data in the GLTF buffers. Notice that everything is converted to four-byte floats and integers before uploading them to the GPU even if initially data can be of different sizes, e.g. see the function "read_vert_indices". These wrong byte sizes usually evade the compiler. The bugs are found only with Renderdoc, test cube, and the correct working examples outside the code.

**Tricky point 3.** I missed "glGenerateMipmap(GL_TEXTURE_2D)" at first, and without it nothing seemed to work, unlike in the Go code. Debugging such OpenGL texture function misses is a lot harder than debugging mesh geometry.  

## Nim/C-FFI Peculiarities

This line bypassed the Go compiler, but was caught in Nim:

```c
gl.TexParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
```

The third argument expects a float, but I am passing in an OpenGL (integer) constant here. This demanded a change to "gl.TexParameteri" in Nim. Such an error had no consequence in Go at the runtime though.

Nim adds some friction with its types marked as "distinct", which is the case with GLenum and GLint. One needs to cast explicitly a lot more. In addition, the const/let/var mutability system hits with "cannot take an address of an expression" more often than needed. Uploading constant data to the GPU demands sending pointers/addresses and the compiler then demands adjusting mutability.

One can find a tricky case of "Mat4[system.float32]" vs. "Mat4f" when printing an array value in "main.nim" with "import glm" or without it. Without importing the library, the system treats an otherwise exported/visible variable "WINDOW_STATE.cam.view" as having type "Mat4f" which does not use a pretty printing operator $ overloaded in the package "glm".
The types "Mat4[system.float32]" and "Mat4f" seem to be the same as far as the math is concerned, but not with pretty printing which is picked up only with the "Mat4[system.float32]" type.

## Vector Math

Nim's operator overloading shines, but there is a trade off with nonreachable code paths due to all the templates and overloading. I have suffered from this in C++ before. 

Consider [this Go function](https://github.com/g3n/engine/blob/b5c63e94be77871a78a9062f816b90d3af58b6c1/math32/math.go#L105):

```go
func Sqrt(v float32) float32 {
	return float32(math.Sqrt(float64(v)))
} 
```

It won't impress a type theorist, but do we really need that whole layer with generics and code substitution here? If you get into "go generate" and templates [this way](https://github.com/go-gl/mathgl/blob/master/mgl32/matrix.tmpl) with the big lib mentality then perhaps yes. Since Go version 1.18 one can use [generic types](https://planetscale.com/blog/generics-can-make-your-go-code-slower), but I would not bother.

There is also [a pointless split between "vmath" and "glm"](https://github.com/treeform/vmath/issues/42). I went with the "glm" library as this is the one I used with Go and C++ before. All the camera/geometry stuff mapped so well rather directly. There is a magic ".caddr" operator to upload uniforms on the GPU. I did not have to worry about any row-major vs column-major issues at all, though somebody did before me ;).

## The Choice of GLFW Bindings

There are quite a few choices despite a tiny community. They all have minor intricate variations, i.e. consider [these GLFW function signatures](https://github.com/glfw/glfw/blob/a465c1c32e0754d3de56e01c59a0fef33202f04c/src/monitor.c#L306-L326):

```c
GLFWAPI GLFWmonitor** glfwGetMonitors(int* count)
GLFWAPI GLFWmonitor* glfwGetPrimaryMonitor(void)
```

Here "GLFWmonitor" is some opaque C struct hidden under platform specific layers, the "GLFWAPI" macro can be ignored. 

Input: C semantics with __struct**__ and __struct*__.  

What do these output types become in Go and Nim bindings?

[Go: go-gl/glfw/v3.3](https://github.com/go-gl/glfw/blob/62640a716d485dcbf341a7c187227a4a99fb1eba/v3.3/glfw/monitor.go#L56-L83): __[]*struct__ and __*struct__.

[Nim: treeform/staticglfw](https://github.com/treeform/staticglfw/blob/f6a40acf98466c3a11ab3f074a70d570c297f82b/src/staticglfw.nim#L429-L430): __ptr pointer__ and __pointer__.   

[Nim: nimgl/glfw](https://github.com/nimgl/nimgl/blob/309d6ed8164ad184ed5bbb171c9f3d9d1c11ff81/src/nimgl/glfw.nim#L1740-L1767): __ptr UncheckedArray[ptr object]__ and __ptr object__. Notice the missing pointer reported in [this issue](https://github.com/nimgl/nimgl/issues/54) which then got [fixed](https://github.com/nimgl/glfw/commit/52a06d468ac8e5f6afaf92b4070973cb0fb6c58c).

[jyapayne/nim-glfw](https://github.com/jyapayne/nim-glfw/blob/master/src/glfw/glfw_standalone.nim): __ptr ptr object__, __ptr object__ and pragma.

[gcr/turbo-mush](https://github.com/gcr/turbo-mush/blob/0ccdfb09946fcb5c5056b3fd94dd75e00272584a/glfw.nim#L950): __ptr ptr cint__, __ptr cint__.

They are all fine, most likely. I chose "nim/glfw" as it looks to be the most consolidating and future-proof.
    
## The Choice of OpenGL Bindings

Let's examine the OpenGL function
 
```c
void glShaderSource(	GLuint shader,
GLsizei count,
const GLchar **string,
const GLint *length);
```
    
In particular, let's focus on the third argument, i.e. ****string** which in reality is just a shader code, text. Let's see what this entails in Go and Nim. 
  
In Go with go-gl bindings, the type becomes __**uint8__ and the conversion is achieved with a special function [gl.Strs](https://github.com/go-gl/gl/blob/726fda9656d66a68688c09275cd7b8107083bdae/v2.1/gl/conversions.go#L90), clf. [the code by Nicholas Blaskey](https://github.com/NicholasBlaskey/gophergl/blob/6459203ed630d94f155c4a1dc8d0f427cda1b3fc/Open/gl/shader.go#L18). One needs to append Go strings with "null termination", i.e. "\x00". For the record, a similar function in [Ada](https://github.com/flyx/OpenGLAda/blob/60dc457f969216e1f814d52baaa2d4395bf00858/opengl/src/implementation/gl-files.adb). This gets messy.

In Nim, there are two main cases revolving around the packages "opengl" and "nimgl/opengl".

1. **cstringArray** in the package "opengl": [gltfviewer](https://github.com/guzba/gltfviewer/blob/31ea77829426db9c43249362d9ede483a135b864/src/gltfviewer/shaders.nim#L15) uses **cstringArray** with **allocCStringArray** and **dealloc**. Jack Mott does [the same](https://github.com/jackmott/easygl/blob/9a987b48409875ffb0521f3887ae25571ff60347/src/easygl.nim#L294), but with **deallocCStringArray**, see also [Samulus-2017](https://github.com/Samulus/toycaster). [pseudo-random](https://github.com/pseudo-random/geometryutils/blob/553ff09471fd2646aad8443c9639ea7b91fca626/src/geometryutils/shader.nim#L49) and [treeform](https://github.com/treeform/shady/blob/51c59c5764b30a2c404c162caa5a7c72d50f97d6/src/shady/demo.nim#L48) skip deallocations. [Jason Beetham](https://github.com/beef331/truss3d/blob/5ca3eafcdc3d769f25a6555efc214a2bed7d0127/src/truss3D/shaders.nim#L38) gets by with casting. [Arne Döring](https://github.com/krux02/opengl-sandbox/blob/7d55a0b9368f8f1dcda7140c251e724c93af46a3/fancygl/glwrapper.nim#L888) does the same with self-hosted [bindings](https://github.com/krux02/opengl-sandbox/blob/7d55a0b9368f8f1dcda7140c251e724c93af46a3/glad/gl.nim#L1634) which have the same "glShaderSource" signature.

2. **ptr cstring** in the package "nimgl/opengl": [Elliot Waite](https://github.com/elliotwaite/nim-opengl-tutorials-by-the-cherno/blob/cfce01842ef2bf6712747885c620c1f549454f67/ep15/shader.nim#L49) simply casts Nim's string to **cstring** and takes **addr**, without deallocations. [anon767](https://github.com/anon767/nimgl-breakout/blob/19d4b7638d26432a0daccce3433ea06f80ac3cdc/src/shader.nim#L23) does the same.      

Having made the choice of "nimgl/glfw" previously one would be inclined to go with "nimgl/opengl", but the "opengl" case looks cleaner so you will find the latter in this code. Notice that OpenGL is initialized with **"glInit()"** in "nim/opengl", but is is the function **loadExtensions()** that does it in "opengl". 

## Void*

What is the Go/Nim answer to the type __void*__? Consider this OpenGL function:

```c
void glVertexAttribPointer(	
GLuint index,
GLint size,
GLenum type,
GLboolean normalized,
GLsizei stride,
const void * pointer);
```

Go with go-gl bindings: The type becomes __unsafe.Pointer__, clf. [this file](https://raw.githubusercontent.com/go-gl/gl/master/v4.1-core/gl/package.go). [The auxiliary "PtrOffset" function](https://github.com/go-gl/gl/blob/726fda9656d66a68688c09275cd7b8107083bdae/v4.1-core/gl/conversions.go#L62) turns an integer into a required pointer with the __unsafe.Pointer(uintptr(offset)__ expression. My Go code in this repo sets everywhere __PtrOffset(0)__ as an argument to glVertexAttribPointer.

Nim: The type is __pointer__, clf. [this file](https://raw.githubusercontent.com/nimgl/opengl/master/src/opengl.nim). [gltfviewer](https://github.com/guzba/gltfviewer/blob/c151dc0df66a7f9730e2f7ad4ee7170504a69864/src/gltfviewer/gltf.nim#L419) uses only __nil__ value, but the case with non-zero offsets can be found in [easygl](https://github.com/jackmott/easygl/blob/9a987b48409875ffb0521f3887ae25571ff60347/src/easygl.nim#L369), e.g. [here](https://github.com/jackmott/easygl/blob/9a987b48409875ffb0521f3887ae25571ff60347/examples/advanced_opengl/blending.nim#L111) which boils down to expressions such as 

```nim
cast[pointer](3*float32.sizeof()). 
```

[Another example](https://github.com/elliotwaite/nim-opengl-tutorials-by-the-cherno/blob/cfce01842ef2bf6712747885c620c1f549454f67/ep19/vertex_array.nim#L21) (with the "nim/opengl" package instead of "opengl") emphasizes the __ByteAddress__ type instead of "int" before casting to Nim's "pointer", somewhat resembling Go's "uintptr".  

## [Nim's Case/Style Insensitivity](https://github.com/nim-lang/RFCs/issues/456) Bites

[Check this out](https://github.com/nimgl/nimgl/blob/309d6ed8164ad184ed5bbb171c9f3d9d1c11ff81/src/nimgl/glfw.nim#L857):

```nim
GLFWCursorSpecial* = 0x00033001 ## Originally GLFW_CURSOR but conflicts with GLFWCursor type
``` 

In the original GLFW C interface we have the GLFW_CURSOR constant and the GLFWCursor structure. In Nim these two become the same due its style rules.

Here is another "ouch" situation in the "opengl" Nim package. Assume a perfectly normal-looking OpenGL function call somewhere in the user code:

```nim
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F.GLint, width.GLint, height.GLint, 0, GL_RGBA.GLenum, GL_FLOAT, nil)
```

It does not compile however. The problem is that GL_FLOAT constant maps to "GLfloat* = float32" in [opengl/private/types.nim](https://github.com/nim-lang/opengl/blob/e53096f4e7f581b5c90c1912441f3059be97e0d9/src/opengl/private/types.nim#L15). A fix is to set the 8th argument to

```nim
glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F.GLint, width.GLint, height.GLint, 0, GL_RGBA.GLenum, cGL_FLOAT, nil)
```

It maps to the correct "cGL_FLOAT* = 0x1406.GLenum" constant in [opengl/private/constants.nim]. 

This is not as bad as Go's variable capitalization though. None of this is critical.

## Multiple Hopeless Attempts to Make OpenGL Better

[stisa-2017](https://github.com/stisa/crow), [AlxHnr-2017](https://github.com/AlxHnr/3d-opengl-demo), [floooh-2019](https://github.com/floooh/sokol-nim/issues/5), [jackmott-2019](https://github.com/jackmott/easygl), [krux02-2020](https://github.com/krux02/opengl-sandbox), [liquidev-2021](https://github.com/liquidev/aglet), [treeform-2022](https://github.com/treeform/shady)...

## Where Has My libGL Gone? 

An ldd check on the final Ubuntu compiled binaries in Go and Nim:

Go:
```console
tokyo@tokyo-Z87-DS3H:~/twinpeekz$ ldd twinpeekz
linux-vdso.so.1 (0x00007ffc9cd9c000)
libGL.so.1 => /lib/x86_64-linux-gnu/libGL.so.1 (0x00007f8ea74a3000)
libX11.so.6 => /lib/x86_64-linux-gnu/libX11.so.6 (0x00007f8ea7363000)
libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007f8ea727c000)
libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f8ea7054000)
libGLdispatch.so.0 => /lib/x86_64-linux-gnu/libGLdispatch.so.0 (0x00007f8ea6f9c000)
libGLX.so.0 => /lib/x86_64-linux-gnu/libGLX.so.0 (0x00007f8ea6f66000)
libxcb.so.1 => /lib/x86_64-linux-gnu/libxcb.so.1 (0x00007f8ea6f3c000)
/lib64/ld-linux-x86-64.so.2 (0x00007f8ea7543000)
libXau.so.6 => /lib/x86_64-linux-gnu/libXau.so.6 (0x00007f8ea6f36000)
libXdmcp.so.6 => /lib/x86_64-linux-gnu/libXdmcp.so.6 (0x00007f8ea6f2e000)
libbsd.so.0 => /lib/x86_64-linux-gnu/libbsd.so.0 (0x00007f8ea6f16000)
libmd.so.0 => /lib/x86_64-linux-gnu/libmd.so.0 (0x00007f8ea6f07000)
``` 

Nim:
```console
tokyo@tokyo-Z87-DS3H:~/twinpeekz2$ ldd main
linux-vdso.so.1 (0x00007fff13588000)
libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007f5e74d60000)
libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f5e74b38000)
/lib64/ld-linux-x86-64.so.2 (0x00007f5e7505d000)
```

The sizes of the binaries: 4.7MB (Go: default), 2.0MB (Nim: default), 1.1MB (Nim: d:release), 977KB (Nim: d:danger). 

## White Space

Nim/Python white spaces bite in double loops where one needs to be extra careful not to push the last lines of the inner loop into the outter space, esp. when tabs are only two-spaced, esp. when the loops are long, esp. when editing/rewriting them later. I like "gofmt" with "vim-go" a lot more.

Naked imports are not a problem at all with Nim, paradoxically. You get into definitions with the right tools very quickly (I use [alaviss/nim.nvim](https://github.com/alaviss/nim.nvim)), and the code becomes very readable and terse without those package namespaces. 

Nim's "include" introduces duplication errors while "import" is demanding w.r.t. the manual markings of visibility. I got to think of everything as a separate module/package, while the Go "package system" made me think less. 

## Final Thoughts/Rant

A static non-GC language is a tough space to be in, if not hopeless. Way too many evolving features, nondebuggable code paths. People get clever. 

If pressed, the choice between the archaic and the modern is 50-50 with no good answers. Nim will help with modules, packages, compilation, pleasant syntax and scope, alaviss/nim.nvim. There are quite a few hyper productive heroes in the Nim's OpenGL space, e.g. [treeform](https://github.com/treeform), [krux02](https://github.com/krux02)... None of this is decisive enough though. Googling is not very productive and you need to deal with FFI to C and a complex evolving language. Either way is not really about productivity. 

In addition, programming desktop 3D seems to revolve around some big libs and certain chunks of knowledge separated from the language: GLFW/SDL, GLTF/Assimp, MGL vector math, stb_image, OpenGL and GLSL.

This makes me think that a "better C/C++" and a strive for universalism with the static non-GC path is a dead end. The problem is not really the compile time per se, but the people who literally want everything while having such limited resources. Multiple compiler backends, graphics, web, performance, productivity, parallelism, fancy types with proofs... It is the same story every god damn time: Ada, [Ark](https://github.com/ark-lang/ark), ATS, D, Nim, Zig, Odin, c3, kit, cyclone, [ion](https://github.com/tjpalmer/ion), quaint, myrddin, carp, carbon, v, jai...

I now begin to appreciate the Unreal/Unity/Godot or the languages such as Go a lot more than I used to. Nim feels a bit like Julia in the scientific computing. One just needs a better packaged GPU-adapted open source Matlab instead of the whole Lisp-like software engineering layer with macros and static type annotations. We do have a decent solution in scientific computing (Python+Anaconda), but nothing like that exists in 3D.
