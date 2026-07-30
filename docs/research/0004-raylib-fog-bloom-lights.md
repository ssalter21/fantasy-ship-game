# What raylib and the Odin vendor bindings give us for fog, bloom and lights

Scoped by GitHub issue [#513](https://github.com/ssalter21/fantasy-ship-game/issues/513)
(effort: lit-world, [#511](https://github.com/ssalter21/fantasy-ship-game/issues/511)).

**Question.** This codebase has zero shaders — no `LoadShader`, no `BeginShaderMode` anywhere.
Before the effort commits to a lighting architecture, establish what the platform actually hands
us, as verified facts with sources rather than recollection.

## How this was verified, and what that is worth

Three classes of evidence appear below, tagged so a reader can weigh them:

- **[binding]** — read directly out of the Odin vendor binding on this machine.
  Odin `dev-2026-05-nightly:ea5175d`, at
  `<odin>/vendor/raylib/raylib.odin` and `<odin>/vendor/raylib/rlgl/rlgl.odin`.
  **These files are byte-identical (modulo line endings) to the CI-pinned `dev-2026-06` tag** —
  verified by diffing against
  [`raylib.odin@dev-2026-06`](https://github.com/odin-lang/Odin/blob/dev-2026-06/vendor/raylib/raylib.odin)
  and [`rlgl.odin@dev-2026-06`](https://github.com/odin-lang/Odin/blob/dev-2026-06/vendor/raylib/rlgl/rlgl.odin),
  both `IDENTICAL`. So every binding claim here holds at the version CI actually builds
  (`.github/workflows/ci.yml`, `release: dev-2026-06`).
- **[raylib]** — read out of raylib's own C source at the `5.5` tag, which is the version the
  binding wraps (`raylib.odin:201` says "Bindings for raylib v5.5"; the Linux/macOS foreign
  imports name `libraylib.so.550` / `libraylib.550.dylib`, `rlgl.odin:138-146`).
- **[probe]** — measured by compiling and running an actual Odin program against the actual
  vendored `raylib.lib` on this machine. Two probes were built and run; both compiled on the
  first attempt. Their full output is in [Appendix: probe results](#appendix-probe-results).

Anything not established by one of those three is marked **unverified** in place.

## Summary of verdicts

| # | Question | Verdict |
|---|---|---|
| 1 | Shader API coverage in the Odin binding | **Complete and usable.** Every named symbol is exposed with a workable signature. Two real gaps, both survivable; one latent ABI mismatch worth knowing. |
| 2 | raylib's reference implementations | Fog is **distance-to-camera, per-fragment, in-scene** — not depth-texture post. Multi-light is forward, **capped at 4**, fused into the same shader as fog. Bloom/blur are **single-pass and hardcoded to 800x450**. |
| 3 | **The depth-buffer question** | **`LoadRenderTexture` gives a depth _renderbuffer_, not a sampleable texture — you cannot sample scene depth from it.** But a hand-built depth-texture FBO works, is a first-party raylib pattern, and every call it needs is in the Odin binding. Proven both ways by probe. |
| 4 | Projection-override interaction | **Works, and the override does reach shader uniforms.** `matProjection` is auto-bound and rlgl uploads the overridden matrix at flush time. |
| 5 | rlgl batching vs. shader mode | **No hazard.** `BeginShaderMode`/`EndShaderMode` flush the batch themselves. This is unlike wire mode, which does not — the repo's existing manual flushes are necessary and shader mode needs no equivalent. |
| 6 | GLSL version | **GLSL 330 / desktop OpenGL 3.3 core.** Confirmed twice: the string `#version 330` is the only GLSL version present in the shipped `raylib.lib`, and `rlgl.GetVersion()` returns `OPENGL_33` at runtime. |

There is also a **finding the ticket did not ask for that outranks most of the ones it did** —
see [The finding that reframes the decision](#the-finding-that-reframes-the-decision).

---

## 1. Shader API coverage in the Odin binding

**Verdict: complete and usable.** Every symbol the ticket names is exposed, with a signature you
can call. No `#+private` omissions in the shader area — `raylib.odin` has no `#+private` marker at
all, and everything below is inside the public `foreign lib` block.

**[binding]** From `<odin>/vendor/raylib/raylib.odin`:

| Symbol | Line | Notes |
|---|---|---|
| `LoadShader(vsFileName, fsFileName: cstring) -> Shader` | 1006 | |
| `LoadShaderFromMemory(vsCode, fsCode: cstring) -> Shader` | 1007 | |
| `IsShaderValid(shader) -> bool` | 1008 | aliased `IsShaderReady` at 1813 |
| `GetShaderLocation(shader, uniformName: cstring) -> c.int` | 1009 | |
| `GetShaderLocationAttrib(shader, attribName: cstring) -> c.int` | 1010 | |
| `SetShaderValue(shader, #any_int locIndex, value: rawptr, uniformType: ShaderUniformDataType)` | 1013 | |
| `SetShaderValueV(shader, #any_int locIndex, value: rawptr, uniformType, count: c.int)` | 1014 | |
| `SetShaderValueMatrix(shader, #any_int locIndex, mat: Matrix)` | 1015 | |
| `SetShaderValueTexture(shader, #any_int locIndex, texture: Texture2D)` | 1016 | |
| `UnloadShader(shader)` | 1017 | |
| `BeginShaderMode(shader)` / `EndShaderMode()` | 989-990 | |
| `ShaderLocationIndex` enum (30 members) | 710-741 | |
| `ShaderUniformDataType` enum (`FLOAT`…`SAMPLER2D`) | 744-755 | |

Two binding niceties worth knowing:

- **`#any_int` on `locIndex`** (lines 1013-1016) means a `ShaderLocationIndex` enum member can be
  passed straight where a raw `c.int` location is expected, without a cast. The comment at
  `raylib.odin:1012` says this is deliberate. **[probe]** Confirmed: probe 1 calls
  `rl.SetShaderValue(sh, rl.ShaderLocationIndex.COLOR_DIFFUSE, &vec, .VEC4)` and it compiles.
- **`value: rawptr`** — not a generic. Any `^T` converts implicitly, so `&density` and `&arr`
  both work, but there is **no type checking between the pointer and the
  `ShaderUniformDataType`**. Passing `.VEC3` with a `^f32` compiles and reads 12 bytes off a
  4-byte object. This is the one place in the shader API where the Odin binding gives no more
  safety than C.

### Gap 1 (real, minor): `rlSetUniformMatrices` is not bound

**[raylib]** raylib 5.5 declares `void rlSetUniformMatrices(int locIndex, const Matrix *mat, int count)`
([`rlgl.h:776`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L776)).
**[binding]** The Odin `rlgl.odin` binds `SetUniformMatrix` (line 554) but **not**
`SetUniformMatrices`. There is no `SetShaderValueMatrices` in `raylib.odin` either.

Consequence: an array of `mat4` uniforms (the usual shape for shadow-cascade or bone matrices)
has to be uploaded one matrix at a time, or the symbol declared locally in a small
`foreign import`. Not blocking for fog/bloom/lights, none of which need matrix arrays.

### Gap 2 (latent but real): `rlgl.VertexBuffer` is a raylib **5.0** struct against a 5.5 library

This one is worth recording because it is the kind of thing that produces inexplicable garbage
rather than a compile error.

**[binding]** `rlgl.odin:282-291` declares:

```odin
VertexBuffer :: struct {
	elementCount: c.int,
	vertices:  [^]f32,
	texcoords: [^]f32,
	colors:    [^]u8,          // <-- no `normals` field
	indices:   [^]VertexBufferIndexType,
	vaoId:     c.uint,
	vboId:     [4]c.uint,      // <-- 4, not 5
}
```

**[raylib]** That is exactly raylib **5.0**'s layout
([`rlgl.h@5.0:344-358`](https://github.com/raysan5/raylib/blob/5.0/src/rlgl.h#L344-L358)).
raylib **5.5** — the version actually linked — inserted `float *normals;` between `texcoords`
and `colors` and grew the array to `vboId[5]`
([`rlgl.h@5.5:381-396`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L381-L396)).

So `rlgl.VertexBuffer` (and therefore `rlgl.RenderBatch.vertexBuffer`, `rlgl.odin:305-313`) is
**ABI-mismatched against the linked library**: reading `.colors` yields the `normals` pointer,
`.indices` yields `colors`, and so on.

**Currently harmless** — the repo never reads a `RenderBatch`; it only calls
`rlgl.DrawRenderBatchActive()` (`presentation/ship_cutaway.odin:132,142`), which passes nothing.
**Becomes a live bug** the moment anyone touches `LoadRenderBatch` / `SetRenderBatchActive` to
get a bigger or a second batch. The related stale marker: `rlgl.odin:113` declares
`VERSION :: "5.0"`. **[probe]** Probe 1 printed `rlgl binding VERSION const = 5.0` against a
library that reports `OPENGL_33` and contains raylib 5.5's shaders — so the constant is a
documentation bug, not a build switch.

### Not a gap: the `GRAPHICS_API_OPENGL_*` constants look wrong but do not bite

**[binding]** `rlgl.odin:157-162` sets `GRAPHICS_API_OPENGL_21 :: true` and
`GRAPHICS_API_OPENGL_33 :: GRAPHICS_API_OPENGL_21`. These are Odin-side compile-time constants
used only for the binding's own `when` branches; they do **not** control how `raylib.lib` was
built. They read as claiming GL 2.1, while the shipped library is GL 3.3 (see §6). Checked every
branch that depends on them — `VertexBufferIndexType` (`rlgl.odin:279`, keys off `ES2` only),
`DEFAULT_BATCH_BUFFER_ELEMENTS` (keys off `ES2`), and the `GRAPHICS_API_OPENGL_11` block at
`rlgl.odin:422` (false) — and none diverge between 2.1 and 3.3. Harmless, but do not read those
constants as a statement about the GL version; use `rlgl.GetVersion()`.

---

## 2. What raylib ships as reference implementations, and what their shape implies

**[raylib]** raylib 5.5 ships 26 shader examples in
[`examples/shaders/`](https://github.com/raysan5/raylib/tree/5.5/examples/shaders). The relevant
ones: `shaders_fog.c`, `shaders_basic_lighting.c` + `rlights.h`, `shaders_postprocessing.c`
(which includes `FX_BLOOM` and `FX_BLUR`), `shaders_write_depth.c`, `shaders_deferred_render.c`,
`shaders_hybrid_render.c`, `shaders_shadowmap.c`, `shaders_spotlight.c`.

### Fog: distance-to-camera, per-fragment, in-scene — **not** depth-texture post-processing

This directly answers the ticket's either/or, and the answer is the second option.

**[raylib]** [`fog.fs`](https://github.com/raysan5/raylib/blob/5.5/examples/shaders/resources/shaders/glsl330/fog.fs)
computes, at lines 78 and 85:

```glsl
float dist = length(viewPos - fragPosition);
float fogFactor = 1.0/exp((dist*fogDensity)*(dist*fogDensity));
...
finalColor = mix(fogColor, finalColor, fogFactor);
```

`fragPosition` is world-space position interpolated from the vertex shader
([`lighting.vs:25`](https://github.com/raysan5/raylib/blob/5.5/examples/shaders/resources/shaders/glsl330/lighting.vs#L25):
`fragPosition = vec3(matModel*vec4(vertexPosition, 1.0))`), and `viewPos` is a `vec3` uniform the
application pushes. **No depth texture, no depth sampling, no second pass.** The fog is
exponential-squared in true Euclidean distance to the eye — not in NDC depth — which is
why it needs no depth buffer at all.

It is also **fused into the lighting shader rather than layered after it**: `fog.fs` is the
lighting shader (it carries the whole `lights[MAX_LIGHTS]` loop, lines 53-69) with a fog `mix`
appended at line 94, after gamma correction at line 75. raylib's idiom is *one* forward shader
that does lighting and fog together, per fragment, while drawing the scene.

**[probe]** Probe 2 measured this working on **this repo's actual geometry idiom**. Two quads
drawn with `rl.DrawTriangle3D` under a fog shader, camera at `z=8`:

| quad | expected distance | shader-measured distance | fog factor |
|---|---|---|---|
| `z=6` | 2.0 | `16/255*32 = 2.008` | `241/255 = 0.945` |
| `z=-8` | 16.0 | `128/255*32 = 16.06` | `6/255 = 0.024` |

So `fragPosition` is **exactly correct in world space** for rlgl batch geometry, and
distance-to-camera fog works on it as-is. The reason it works: for batch geometry rlgl's
`matModel` is `RLGL.State.transform` = identity, and `rlVertex3f` has already applied any
transform on the CPU ([`rlgl.h:1499-1504`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L1499-L1504)),
so the position attribute *is* the world position and `matModel*vertexPosition` is a no-op.

### Multi-light: forward, capped at 4, uniforms pushed on change (not per frame)

**[raylib]** [`rlights.h`](https://github.com/raysan5/raylib/blob/5.5/examples/shaders/rlights.h):

- `#define MAX_LIGHTS 4` (line 39). The **same** cap is hardcoded independently in the shader
  (`fog.fs:18`, `#define MAX_LIGHTS 4`). Raising it means editing *both*, in lockstep.
- `CreateLight` (line 121) resolves **five** uniform locations per light by string name —
  `lights[%i].enabled`, `.type`, `.position`, `.target`, `.color` (lines 134-138) — **once**, at
  creation.
- `UpdateLightValues` (line 150) pushes those five uniforms with five `SetShaderValue` calls.

**Does it need per-light uniforms set per frame?** No — `UpdateLightValues` is called on change,
not per frame. But **`viewPos` must be set every frame** the camera moves, because both the
lighting (`viewD` at `fog.fs:48`) and the fog (`dist` at line 78) are computed relative to it.
So the per-frame cost of raylib's model is *one* `vec3` upload, not `5 x lightCount`.

**Practical light-count ceiling.** The binding cost is not uniform slots, it is the fragment
loop: `fog.fs:53` is `for (int i = 0; i < MAX_LIGHTS; i++)` with the enable test *inside* the
loop (line 55). The loop runs `MAX_LIGHTS` times **per fragment regardless of how many lights are
enabled** — disabling a light saves nothing. So the cost is `MAX_LIGHTS x fragments`, paid
whether or not the lights are on. Raising `MAX_LIGHTS` to 8 doubles the per-fragment cost of
every lit pixel on screen even with one light lit.

That is the ceiling that matters at this repo's scale, and it is a *shader cost* ceiling, not an
API ceiling. The uniform-slot ceiling is far away and not the binding constraint: each `Light` is
12 float-equivalent components, and OpenGL 3.3 core guarantees at least 1024
`GL_MAX_FRAGMENT_UNIFORM_COMPONENTS` — *(spec minimum cited from the GL 3.3 core specification;
**unverified** for this machine's actual GPU, which would need a `glGetIntegerv` query that rlgl
does not expose)*. raylib's own answer for "more lights than a forward loop wants" is a separate
example, [`shaders_deferred_render.c`](https://github.com/raysan5/raylib/blob/5.5/examples/shaders/shaders_deferred_render.c) —
i.e. upstream treats "many lights" as an architecture change, not a constant bump.

**Porting hazard in `rlights.h` worth flagging:** line 153 is
`SetShaderValue(shader, light.enabledLoc, &light.enabled, SHADER_UNIFORM_INT)` where
`light.enabled` is declared `bool` (line 48). That reads 4 bytes from a 1-byte object and only
works by struct-padding luck. Ported literally to Odin — where `bool` is also 1 byte — it is the
same over-read. Use an explicit `i32` field. Also note `attenuation`/`attenuationLoc` are
declared in the `Light` struct (lines 52, 60) and **never wired to anything** — dead fields; the
shader has no distance attenuation at all.

### Bloom and blur: single-pass, hardcoded resolution, and not really bloom

**[raylib]** `shaders_postprocessing.c` is the reference shape, and it is exactly the
post-processing shape this repo already has half of: `LoadRenderTexture` (line 113), draw the
scene into it, then `BeginShaderMode(fs)` + `DrawTextureRec(target.texture, ...)` y-flipped
(lines 147-150). **It samples `texture0` only — colour. It never touches depth.** Further
confirmation that fog is not a post-process in raylib's idiom.

[`bloom.fs`](https://github.com/raysan5/raylib/blob/5.5/examples/shaders/resources/shaders/glsl330/bloom.fs):
a single-pass 5x5 box blur (25 taps, lines 30-36) added to the source colour (line 39).
Two things about its shape matter:

- **There is no bright-pass threshold.** It blurs and adds *everything*, so it is a
  glow/haze-over-the-whole-frame, not bloom in the "bright things bleed" sense. Getting real
  bloom means adding a luminance threshold pass.
- **`const vec2 size = vec2(800, 450)` is hardcoded** (line 16). At this repo's 1244x700 logical
  frame the glow radius would be wrong by ~1.5x. It must become a uniform.

[`blur.fs`](https://github.com/raysan5/raylib/blob/5.5/examples/shaders/resources/shaders/glsl330/blur.fs):
a 5-tap linear-sampled Gaussian with the standard `0.2270/0.3162/0.0703` weights (line 21) —
but note lines 30-31 offset by `vec2(offset[i])/renderWidth`, i.e. **the same amount in x and y**.
That is a *diagonal* blur, not a separable horizontal-then-vertical Gaussian; `renderHeight`
(line 18) is declared and never used. It is a simplification in raylib's own example, not a
reference-quality separable blur.

**Implication for the shape of a real bloom here:** raylib's examples do not give you one. A
correct bloom is bright-pass → horizontal blur → vertical blur → composite, which is three
render textures and four passes. What raylib ships is a starting point for a *haze*, and a haze
may well be what this game wants — but that should be a decision, not an inheritance.

---

## 3. The depth-buffer question — the load-bearing fact

**Verdict: NO. A post-process pass cannot sample scene depth from a `LoadRenderTexture` target.
Its depth attachment is a renderbuffer, which is not sampleable. But the fix is small, is a
first-party raylib pattern, and every call it needs is already in the Odin binding.**

### Why not

**[binding]** `raylib.odin:230-239` — the struct *looks* like it should work, and this is the trap:

```odin
RenderTexture :: struct {
	id:       c.uint,             // OpenGL framebuffer object id
	texture: Texture,             // Color buffer attachment texture
	depth:   Texture,             // Depth buffer attachment texture   <-- typed Texture
}
```

`depth` is typed `Texture`. It is not one.

**[raylib]** [`rtextures.c:4239-4275`](https://github.com/raysan5/raylib/blob/5.5/src/rtextures.c#L4239-L4275),
`LoadRenderTexture`, lines 4257 and 4265:

```c
target.depth.id = rlLoadTextureDepth(width, height, true);   // true == useRenderBuffer
...
rlFramebufferAttach(target.id, target.depth.id, RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_RENDERBUFFER, 0);
```

And [`rlgl.h:3331-3384`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L3331-L3384),
`rlLoadTextureDepth`, takes the `else` branch when `useRenderBuffer` is true (lines 3369-3380):

```c
glGenRenderbuffers(1, &id);
glBindRenderbuffer(GL_RENDERBUFFER, id);
glRenderbufferStorage(GL_RENDERBUFFER, glInternalFormat, width, height);
```

So `RenderTexture2D.depth.id` is a **renderbuffer name**, from a different GL object namespace
than texture names. It cannot be bound to a `sampler2D`. It exists only so depth *testing* works
inside the FBO.

Corollary gotcha: `LoadRenderTexture` also hardcodes `target.depth.format = 19` with the
comment `//DEPTH_COMPONENT_24BIT?` (`rtextures.c:4260`). **[probe]** In Odin that integer lands in
the `PixelFormat` enum, so probe 1 printed
`depth.format = COMPRESSED_ETC2_RGB`. The field is meaningless — do not read it.

### Proven both ways by probe

**[probe]** Probe 1 ran the discriminating test — attach `LoadRenderTexture`'s `depth.id` to a
fresh FBO **as `TEXTURE2D`**. If it were a texture, the FBO would be complete:

```
[4] LoadRenderTexture: fbo=1 color.id=3 depth.id=1 depth.format=COMPRESSED_ETC2_RGB
WARNING: FBO: [ID 2] Framebuffer has incomplete attachment
    LoadRenderTexture().depth.id attached as TEXTURE2D -> complete=false
[5] hand-built depth-TEXTURE FBO: id=3 depthTex=6 complete=true
    rlgl.LoadTextureDepth(..,true)=2 (renderbuffer)  (..,false)=6 (texture)
```

`complete=false` on the renderbuffer-as-texture attachment, `complete=true` on the hand-built
depth **texture**. That is the fact, measured on this machine against this library.

### The escape hatch, and it is first-party

**[raylib]** raylib ships the workaround as an example:
[`shaders_write_depth.c:116-152`](https://github.com/raysan5/raylib/blob/5.5/examples/shaders/shaders_write_depth.c#L116-L152)
defines `LoadRenderTextureDepthTex`, which is `LoadRenderTexture` with two lines changed
(lines 134 and 142):

```c
target.depth.id = rlLoadTextureDepth(width, height, false);   // false => real depth TEXTURE
rlFramebufferAttach(target.id, target.depth.id, RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_TEXTURE2D, 0);
```

**[binding]** Every call that needs is in the Odin binding: `rlgl.LoadFramebuffer` (541),
`rlgl.EnableFramebuffer` (441), `rlgl.LoadTexture` (529), `rlgl.LoadTextureDepth` (530),
`rlgl.FramebufferAttach` (542), `rlgl.FramebufferComplete` (543), `rlgl.DisableFramebuffer` (442),
`rlgl.UnloadTexture` (535), `rlgl.UnloadFramebuffer` (544), plus the
`rlgl.FramebufferAttachType` / `rlgl.FramebufferAttachTextureType` enums (341-364). **[probe]**
Probe 1 ported it to Odin in ~10 lines and it came back `complete=true`. Note
`FramebufferAttach` takes `attachType`/`texType` as `c.int`, not the enums, so the enum members
need an `i32(...)` cast.

**[raylib]** One forward-looking check, since this decision has to outlive the Odin pin: raylib
**6.0** has **not** changed this. [`rtextures.c@6.0:4251-4283`](https://github.com/raysan5/raylib/blob/6.0/src/rtextures.c#L4251-L4283)
is still `rlLoadTextureDepth(width, height, true)` attached as `RL_ATTACHMENT_RENDERBUFFER`. So
the finding is stable across the raylib 6.0 binding update that landed in Odin master on
2026-07-07 (see `docs/research/0001-rendering-library.md`).

### What this decides

Depth-based fog **as a post-process** is not available for free, but it is not blocked either —
it costs a hand-rolled FBO instead of `LoadRenderTexture`. Weigh that against the fact that
**raylib's own fog does not want a depth buffer at all** (§2), and that in-scene distance fog was
measured working on this repo's existing geometry (§2, probe 2). The depth texture is what you
need for effects that must reconstruct *scene* geometry from a full-screen pass — SSAO, depth of
field, soft particles, god rays — not for fog.

---

## 4. The projection-override interaction

**Verdict: it works, and the override does reach shader uniforms.** No special handling needed.

**[binding]** The site is `presentation/ship_cutaway.odin:119-126`: `rl.BeginMode3D(view.camera)`
then `rlgl.SetMatrixProjection(view.projection)`, replacing the matrix `BeginMode3D` derived from
the camera.

**Why it is safe.** **[raylib]** `rlSetMatrixProjection` is a pure state assignment with no GL
call and no flush ([`rlgl.h:4665-4670`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L4665-L4670)):

```c
void rlSetMatrixProjection(Matrix projection) { RLGL.State.projection = projection; }
```

The matrix is consumed later, at flush time, inside `rlDrawRenderBatch`
([`rlgl.h:2984-3008`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L2984-L3008)):

```c
Matrix matMVP = rlMatrixMultiply(RLGL.State.modelview, RLGL.State.projection);
glUniformMatrix4fv(RLGL.State.currentShaderLocs[RL_SHADER_LOC_MATRIX_MVP], 1, false, rlMatrixToFloat(matMVP));

if (RLGL.State.currentShaderLocs[RL_SHADER_LOC_MATRIX_PROJECTION] != -1)
{
    glUniformMatrix4fv(RLGL.State.currentShaderLocs[RL_SHADER_LOC_MATRIX_PROJECTION], 1, false, rlMatrixToFloat(RLGL.State.projection));
}
```

So **the overridden matrix is what gets uploaded**, to both `mvp` and `matProjection`, for any
shader that declares them — there is no separate "real" projection a shader could disagree with.
The same block also feeds `matView` (`RLGL.State.modelview`), `matModel` (`RLGL.State.transform`)
and `matNormal` (`transpose(inverse(transform))`), each guarded by a `!= -1` check, so a shader
gets exactly the matrices it names.

**[probe]** Probe 1 measured it end to end:

```
[6] projection after BeginMode3D  = matrix[1.5088834, 0, 0, 0; 0, 2.4142137, 0, 0; 0, 0, -1.00002, -0.0200002; 0, 0, -1, 0]
    projection after SetMatrixProjection = matrix[2, 0, 0, 0; 0, 3, 0, 0; 0, 0, -1, -0.2; 0, 0, 0, 1]
    round-trips exactly = true
    projection still overridden after Begin/EndShaderMode = true
```

The override round-trips bit-exactly through `rlgl.GetMatrixProjection()`, and — the part that
matters for §5 — **it survives entering and leaving shader mode**, because the projection is rlgl
state and shader mode only swaps the GL program.

**[probe]** And the uniform is genuinely bound: probe 1 reported
`locs[.MATRIX_PROJECTION] = 10` for a shader declaring `uniform mat4 matProjection`, i.e.
`LoadShaderFromMemory` auto-resolved it into the `Shader.locs` array, which is precisely the
`!= -1` condition the upload above is guarded by.

**The one caveat, and it is the same one the repo already documents.** Because
`SetMatrixProjection` does not flush, it applies to *everything still queued in the batch*, not
just to geometry issued after it. The existing comment at `ship_cutaway.odin:120-124` states this
correctly ("this replaces the one rlgl will settle the queued batch with"). It is safe there only
because `BeginMode3D` flushes first (`rcore.c:1026`), so the batch is empty when the override
lands. **A shader-based effect must preserve that ordering**: override the projection while the
batch is empty, or flush first. Reconstructing world position from a projection inverse is fine
under the override — the shader is handed the overridden matrix, so it inverts the matrix that
actually drew the geometry.

---

## 5. rlgl batching vs. shader mode

**Verdict: no hazard, and no flush discipline required. Shader mode flushes itself.** This is
genuinely different from wire mode, and the asymmetry is worth understanding rather than
cargo-culting the existing flushes.

**[raylib]** `BeginShaderMode` is a one-liner delegating to `rlSetShader`
([`rcore.c:1131-1134`](https://github.com/raysan5/raylib/blob/5.5/src/rcore.c#L1131-L1134)), and
`rlSetShader` **flushes the batch itself** before changing the program
([`rlgl.h:4400-4410`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L4400-L4410)):

```c
void rlSetShader(unsigned int id, int *locs)
{
    if (RLGL.State.currentShaderId != id)
    {
        rlDrawRenderBatch(RLGL.currentBatch);      // <-- the flush
        RLGL.State.currentShaderId = id;
        RLGL.State.currentShaderLocs = locs;
    }
}
```

`EndShaderMode` is the same call with the default shader
([`rcore.c:1137-1140`](https://github.com/raysan5/raylib/blob/5.5/src/rcore.c#L1137-L1140)), so
it flushes on the way out too. **Both edges are covered. Adding
`rlgl.DrawRenderBatchActive()` around `BeginShaderMode`/`EndShaderMode` is redundant.**

**Why wire mode is different** — and why the repo's existing flushes at
`ship_cutaway.odin:132,142` are load-bearing rather than superstition. **[raylib]**
`rlEnableWireMode` is a bare GL call with no flush
([`rlgl.h:1971-1977`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L1971-L1977)):

```c
void rlEnableWireMode(void) { glPolygonMode(GL_FRONT_AND_BACK, GL_LINE); }
```

`glPolygonMode` takes effect at the next *draw*, so it retroactively applies to everything rlgl
has queued but not yet drawn — exactly the "part solid, part mesh" symptom the repo's comment
describes. The distinction is a clean rule:

> **rlgl state that is a GL call on a queued vertex stream needs a manual flush; rlgl state that
> is routed through `rlSetShader` or a `Begin*Mode` in `rcore.c` does not.**

**[raylib]** The `Begin*` functions that already flush for you, all in `rcore.c`:
`BeginMode3D` (1026), `EndMode3D` (1065), `BeginTextureMode` (1081), `EndTextureMode` (1112),
`BeginScissorMode` (1159). Which is why the comment at `hull_sheet.odin:250-254` is right that
`BeginTextureMode`/`EndTextureMode` flush at both ends. `BeginBlendMode`
(`rcore.c:1144`) delegates to `rlSetBlendMode`, which flushes on a mode change the same way
`rlSetShader` does.

**The one caveat, from the `if` in `rlSetShader`:** the flush is **conditional on the shader id
actually changing**. `BeginShaderMode(s)` while `s` is already current is a complete no-op — no
flush, no state change. So nesting shader modes, or calling `BeginShaderMode` twice with the same
shader and relying on the second for a flush, will not do what it looks like. If a flush is
needed at a point where the shader is not changing, call `rlgl.DrawRenderBatchActive()`
explicitly.

**[probe]** Probe 2 confirmed the clean path is GL-error-free: `rlgl.CheckErrors()` after
`InitWindow`, after loading two shaders, after a full `BeginTextureMode` →
`BeginMode3D` → `BeginShaderMode` → batch 3D geometry → `EndShaderMode` → `EndMode3D` →
`EndTextureMode` frame, and at shutdown — **no error at any checkpoint**. (Probe 1 did report one
`GL_INVALID_OPERATION`; that was traced to its own deliberately-invalid
renderbuffer-attached-as-texture test from §3, and probe 2 was written to isolate the clean path
and confirm it. The shader path itself is clean.)

---

## 6. GLSL version and portability

**Verdict: GLSL 330 — desktop OpenGL 3.3 core.** Established twice, independently, by
measurement rather than inference.

**[probe]** Evidence 1 — the shipped static library. Scanning the actual
`<odin>/vendor/raylib/windows/raylib.lib` for GLSL version directives returns **exactly two
matches, both `#version 330`**, and nothing else. Those are rlgl's built-in default vertex and
fragment shaders, whose source is `#if`-selected by the `GRAPHICS_API_OPENGL_*` macro the library
was compiled with ([`rlgl.h:4857-4939`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L4857-L4939)
— `#version 120` for `_21`, `#version 330` for `_33`, `#version 100` for `ES2`). Only the 330
variant is present, so the vendored Windows library was built `GRAPHICS_API_OPENGL_33` — which is
also raylib's compiled-in default when nothing is specified
([`rlgl.h:152-158`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L152-L158)).

**[probe]** Evidence 2 — the library's own runtime answer. Probe 1:

```
[1] rlgl.GetVersion() = OPENGL_33
```

`rlgl.odin:316-322` documents that enum member as "OpenGL 3.3 (GLSL 330)".

**[raylib]** raylib's examples encode the same expectation:
`#if defined(PLATFORM_DESKTOP) #define GLSL_VERSION 330 #else #define GLSL_VERSION 100`
(`shaders_write_depth.c:20-24`), and the desktop shader resources live in
`resources/shaders/glsl330/`. **So raylib's `glsl330/*.fs` files can be used verbatim.**

### What GLSL 330 constrains

Since the game ships as a self-contained Windows exe with a statically-linked
`vendor:raylib` (`.github/workflows/ci.yml`, `scripts/release.ps1`), GL 3.3 core is the whole
target. Available and not: `texture()` (not `texture2D`), `in`/`out`, explicit
attribute locations, integer ops, `gl_FragDepth`, MRT, uniform blocks, `textureGrad`. **Not**
available without raising the target: compute shaders (4.3), SSBOs (4.3),
`imageLoad`/`imageStore` (4.2), explicit uniform locations (4.3), tessellation (4.0).

Two practical consequences:

- **rlgl's compute-shader and SSBO bindings are dead on this build.** `rlgl.odin` binds
  `LoadComputeShaderProgram`, `ComputeShaderDispatch`, `LoadShaderBuffer`, `BindShaderBuffer`
  etc. (lines 546-559) — but **[raylib]** every one is compiled only under
  `GRAPHICS_API_OPENGL_43`. They will link (the symbols exist) and do nothing. Do not design a
  GPU-compute path on them without first rebuilding raylib for 4.3, which means abandoning the
  vendored binary.
- A **separable two-pass blur is the right shape** for bloom here, since 3.3 has no compute path
  to do it in one dispatch.

**Unverified:** whether the *hardware* on target machines exceeds 3.3 is irrelevant — the
vendored library requests a 3.3 core context regardless, so 3.3 is the ceiling until raylib is
rebuilt.

---

## The finding that reframes the decision

This was not one of the six questions, but it is the fact that most constrains a lighting
architecture here, and it is not visible from either raylib's docs or the ticket.

**This repo draws no models. Every 3D surface goes through rlgl's immediate-mode batch — and
that batch is not being given normals.**

**[binding]** A census of `rl.Draw*` calls across `presentation/` returns **no `DrawModel`, no
`DrawMesh`, no `Material`, no `Shader`** — the 3D calls are `rl.DrawTriangle3D` (8 sites) and
`rl.DrawCylinderEx` (2 sites). **[raylib]** Both are pure batch emitters:
`DrawTriangle3D` is `rlBegin(RL_TRIANGLES)` / `rlColor4ub` / three `rlVertex3f`
([`rmodels.c:218-226`](https://github.com/raysan5/raylib/blob/5.5/src/rmodels.c#L218-L226)), and
`DrawCylinderEx` likewise ([`rmodels.c:616`](https://github.com/raysan5/raylib/blob/5.5/src/rmodels.c#L616)).
**Neither calls `rlNormal3f`.**

This cuts two ways, and the split is the useful part:

**Good news — `BeginShaderMode` actually applies to this repo's geometry.** This is *not* true of
`DrawModel`/`DrawMesh`, which bind `material.shader` and ignore shader mode entirely. Because
everything here goes through the batch, and the batch draws with
`RLGL.State.currentShaderId`, a single `BeginShaderMode` covers the whole ship. That makes a
custom forward shader unusually cheap to adopt here — no materials, no meshes, no model loading.

**Bad news — there are no normals in the vertex stream, so per-fragment lighting has nothing to
work with.** **[raylib]** raylib 5.5 *does* carry a normal attribute in the batch: `rlVertexBuffer`
gained `float *normals` ([`rlgl.h:381-396`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L381-L396),
absent in 5.0), it is bound at attribute location 2 as `vertexNormal`
([`rlgl.h:2800-2805`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L2800-L2805),
[`4215`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L4215)), and `rlVertex3f` writes
the current normal into it per vertex
([`rlgl.h:1541-1543`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L1541-L1543)). The
plumbing is all there. But `rlNormal3f` only sets *sticky state*
([`rlgl.h:1577-1599`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L1577-L1599)), and
nothing in this repo's draw path ever calls it.

**[probe]** Probe 2 measured exactly this, painting `abs(fragNormal)` into RGB:

```
(b) DrawTriangle3D          -> |fragNormal| as RGB = [0, 0, 0, 255]
    rlBegin + rlNormal3f    -> |fragNormal| as RGB = [0, 0, 255, 255]
    => DrawTriangle3D supplies a normal: false
    => hand-rolled supplies (0,0,1):     true
```

So: **`rl.DrawTriangle3D` delivers a normal of `(0,0,0)` to the shader. A hand-rolled
`rlgl.Begin` / `rlgl.Normal3f` / `rlgl.Vertex3f` triangle delivers the real one.** All of those
are bound: `rlgl.Begin` (396), `End` (397), `Vertex3f` (400), `Normal3f` (402), `Color4ub` (403);
`rlgl.TRIANGLES` is the mode constant.

### Why this matters more than it sounds

The repo **already has a lighting model** — it is just on the CPU, one flat colour per surface.
`presentation/ship_paint.odin` defines `SHIP_SUN` (line 20), `SHIP_AMBIENT`/`SHIP_SUNLIGHT`/
`SHIP_SKY_FILL`/`SHIP_SEA_FILL` (26-33), and `ship_lit` (65) computes
`ambient + sunlight*lambert + hemisphere fill` per surface from that surface's normal, handing the
result to `ship_quad_flat` as a flat vertex colour (164-169, four `DrawTriangle3D` calls per quad
so both windings are drawn).

That model is already straining against its own flatness in two documented places:

- **`ship_quad_lit` slices tall quads** (`ship_paint.odin:110-121`) specifically because "a quad
  is one flat colour, so a surface that stands a fathom tall takes the dusk of its own midpoint
  and nothing else" — the comment records measuring `#523D23` uniformly from y=450 to y=510. That
  is a per-vertex-interpolation problem being solved by subdividing geometry.
- **`ship_inboard_dusk` / `HULL_TINT_SPAN`** (`ship_paint.odin:122+`, `ship_hull.odin:70`) is a
  hand-rolled depth fade — i.e. this repo already has fog, computed on the CPU per surface.

Both are exactly what a per-fragment shader computes for free. So the lighting decision is not
"add lighting", it is **"move an existing CPU per-surface model to a per-fragment GPU model"** —
and the enabling prerequisite is emitting normals, which means replacing `rl.DrawTriangle3D`
with a small `rlgl.Begin`/`Normal3f`/`Vertex3f` primitive in `ship_paint.odin`. That is a
contained change to one file's lowest-level helpers, and it is the gate on everything else.

**Batch budget, since it becomes relevant if geometry is subdivided further.** **[binding]**
`rlgl.DEFAULT_BATCH_BUFFER_ELEMENTS` is 8192 (`rlgl.odin:171`), and buffers are allocated at
`bufferElements*4` vertices — 32768 vertices — after which **[raylib]** `rlVertex3f` auto-flushes
mid-stream at a primitive boundary ([`rlgl.h:1509-1529`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h#L1509-L1529)).
At 12 vertices per quad today (4 triangles, both windings) that is ~2730 quads per flush.
An auto-flush is correct but it re-uploads state, so heavy subdivision is a performance question,
not a correctness one.

---

## What could only be settled by compiling — and was

Everything the ticket flagged as compile-only got compiled. Both probes built on the first
attempt against the real vendored `raylib.lib`, which is itself the answer to §1: the entire
shader API surface compiles with the signatures documented above.

- **Probe 1** — shader API surface, `rlgl.GetVersion()`, the depth-attachment discrimination
  test, the hand-built depth-texture FBO, and the projection round-trip.
- **Probe 2** — GL-error cleanliness of the shader path, the `vertexNormal` measurement, and the
  distance-fog measurement.

Both were throwaway single-file Odin packages (~180 and ~140 lines) and are **not committed** —
they were built and run under a scratch directory that was removed. To reproduce, the minimal
programs are:

- *Depth question:* `InitWindow`; `rl.LoadRenderTexture`; attach its `.depth.id` to a fresh
  `rlgl.LoadFramebuffer()` as `FramebufferAttachTextureType.TEXTURE2D`; assert
  `rlgl.FramebufferComplete` is `false`. Then `rlgl.LoadTextureDepth(w, h, false)`, attach as
  `TEXTURE2D`, assert `true`. ~25 lines.
- *Normals question:* `LoadShaderFromMemory` with a fragment shader of
  `finalColor = vec4(abs(fragNormal), 1.0)`; inside `BeginShaderMode`, draw one quad with
  `rl.DrawTriangle3D` and one with `rlgl.Begin`/`Normal3f`/`Vertex3f`; read both back with
  `rl.LoadImageFromTexture` + `rl.GetImageColor`. ~40 lines.

**Still unverified**, and honestly so:

- This machine's actual `GL_MAX_FRAGMENT_UNIFORM_COMPONENTS`. rlgl exposes no `glGetIntegerv`, so
  settling it needs a GL loader (`vendor:OpenGL`) alongside raylib. The GL 3.3 spec minimum of
  1024 is cited above as a floor, not as this GPU's value. Not on the critical path: the
  light-count ceiling is the per-fragment loop, not uniform slots.
- Whether the raylib **6.0** binding (in Odin master since 2026-07-07, not in the `dev-2026-06`
  pin) changes any of §1's binding gaps. The depth behaviour was checked and is unchanged; the
  `rlgl.VertexBuffer` layout was not re-checked against 6.0.
- Performance. Nothing here is a frame-time measurement. The claim that raylib's light loop costs
  `MAX_LIGHTS x fragments` is read off the shader source, not profiled.

## Consequences / handoff

1. **Fog should be in-scene and per-fragment, not post-process.** It is raylib's idiom, it needs
   no depth texture, and it was measured working on this repo's existing geometry with correct
   world-space distances. Post-process depth fog is possible but costs a hand-built FBO for no
   gain over the in-scene version.
2. **Per-fragment lighting is gated on emitting normals.** `rl.DrawTriangle3D` delivers
   `(0,0,0)`. Replacing `ship_quad_flat`'s four `DrawTriangle3D` calls with an
   `rlgl.Begin`/`Normal3f`/`Vertex3f` primitive is the prerequisite, and it is contained to
   `presentation/ship_paint.odin`.
3. **A single `BeginShaderMode` covers the whole ship**, because nothing here uses
   `DrawModel`/`Material`. This is a real structural advantage and it is worth not losing by
   moving to meshes.
4. **No new flush discipline.** Shader mode self-flushes at both edges; the existing wire-mode
   flushes stay because `glPolygonMode` does not. Do not rely on a repeated `BeginShaderMode` to
   flush — the flush is conditional on the shader id changing.
5. **The projection override is not an obstacle.** The overridden matrix is the one uploaded to
   `mvp` and `matProjection`. Keep the invariant that the batch is empty when the override lands.
6. **Bloom needs building, not copying.** raylib's `bloom.fs` has no bright-pass and a hardcoded
   800x450; `blur.fs` blurs diagonally. Budget a bright-pass + two-pass separable blur, and
   parameterise resolution to 1244x700.
7. **Do not touch `rlgl.RenderBatch`/`VertexBuffer` from Odin** until the binding's 5.0-era struct
   is fixed upstream, or a local corrected struct is declared. Worth an upstream Odin issue.
8. **Light count: treat 4 as the design budget.** Raising `MAX_LIGHTS` costs per-fragment time
   for every lit pixel whether or not the lights are enabled, and must be changed in the shader
   and the host code in lockstep.
9. **Compute shaders and SSBOs are not available** on the vendored GL 3.3 build, despite the
   bindings existing. Any design that assumes them is designing for a raylib rebuild.

## Sources

**Odin vendor binding** (`dev-2026-05-nightly:ea5175d` locally; verified identical to `dev-2026-06`)
- [`vendor/raylib/raylib.odin@dev-2026-06`](https://github.com/odin-lang/Odin/blob/dev-2026-06/vendor/raylib/raylib.odin)
- [`vendor/raylib/rlgl/rlgl.odin@dev-2026-06`](https://github.com/odin-lang/Odin/blob/dev-2026-06/vendor/raylib/rlgl/rlgl.odin)

**raylib 5.5** (the linked library)
- [`src/rlgl.h`](https://github.com/raysan5/raylib/blob/5.5/src/rlgl.h) — batch, shader state, matrices, depth textures, default shaders
- [`src/rcore.c`](https://github.com/raysan5/raylib/blob/5.5/src/rcore.c) — `Begin*Mode` flush behaviour
- [`src/rtextures.c`](https://github.com/raysan5/raylib/blob/5.5/src/rtextures.c) — `LoadRenderTexture`
- [`src/rmodels.c`](https://github.com/raysan5/raylib/blob/5.5/src/rmodels.c) — `DrawTriangle3D`, `DrawCylinderEx`
- [`examples/shaders/`](https://github.com/raysan5/raylib/tree/5.5/examples/shaders) — `shaders_fog.c`, `rlights.h`, `shaders_postprocessing.c`, `shaders_write_depth.c`, and `resources/shaders/glsl330/{fog.fs,lighting.vs,bloom.fs,blur.fs}`

**raylib 5.0 / 6.0** (for the version deltas)
- [`src/rlgl.h@5.0`](https://github.com/raysan5/raylib/blob/5.0/src/rlgl.h) — pre-`normals` `rlVertexBuffer`
- [`src/rtextures.c@6.0`](https://github.com/raysan5/raylib/blob/6.0/src/rtextures.c) — `LoadRenderTexture` unchanged

**This repo**
- `presentation/ship_cutaway.odin` (projection override, wire-mode flushes), `presentation/ship_paint.odin` (the existing CPU lighting model), `presentation/ship_hull.odin` (`HULL_TINT_SPAN`), `presentation/fullscreen.odin` (`LoadRenderTexture` use), `presentation/hull_sheet.odin` (flush reasoning), `.github/workflows/ci.yml` (the `dev-2026-06` pin), `docs/research/0001-rendering-library.md`

## Appendix: probe results

Probe 1 — API surface, GL version, depth attachment, projection override:

```
[1] rlgl.GetVersion() = OPENGL_33
    rlgl binding VERSION const = 5.0
    MAX_SHADER_LOCATIONS = 32, DEFAULT_BATCH_BUFFER_ELEMENTS = 8192
[2] LoadShaderFromMemory -> id=6 valid=true
    GetShaderLocation(mvp) = 18
    GetShaderLocation(matProjection) = 10
    GetShaderLocation(matView) = 14
    GetShaderLocation(matModel) = 2
    GetShaderLocation(matNormal) = 6
    GetShaderLocation(colDiffuse) = 0
    GetShaderLocation(texture0) = 30
    GetShaderLocation(fogDensity) = 1
    GetShaderLocation(viewPos) = 31
    GetShaderLocation(probeVec4) = 22
    GetShaderLocationAttrib(vertexPosition) = 0
    GetShaderLocationAttrib(vertexTexCoord) = 1
    GetShaderLocationAttrib(vertexNormal) = 2
    GetShaderLocationAttrib(vertexColor) = 3
    locs[.MATRIX_PROJECTION] = 10  locs[.VERTEX_NORMAL] = 2  locs[.MATRIX_MVP] = 18
[3] SetShaderValue / V / Matrix / Texture all linked and returned
[4] LoadRenderTexture: fbo=1 color.id=3 depth.id=1 depth.format=COMPRESSED_ETC2_RGB
WARNING: FBO: [ID 2] Framebuffer has incomplete attachment
    LoadRenderTexture().depth.id attached as TEXTURE2D -> complete=false (false => it is a renderbuffer)
[5] hand-built depth-TEXTURE FBO: id=3 depthTex=6 complete=true
    rlgl.LoadTextureDepth(..,true)=2 (renderbuffer)  (..,false)=6 (texture)
[6] projection after BeginMode3D  = matrix[1.5088834, 0, 0, 0; 0, 2.4142137, 0, 0; 0, 0, -1.00002, -0.0200002; 0, 0, -1, 0]
    projection after SetMatrixProjection = matrix[2, 0, 0, 0; 0, 3, 0, 0; 0, 0, -1, -0.2; 0, 0, 0, 1]
    round-trips exactly = true
    projection still overridden after Begin/EndShaderMode = true
WARNING: GL: Error detected: GL_INVALID_OPERATION
[7] survived a full frame with a custom shader over batch 3D geometry
```

The `GL_INVALID_OPERATION` is probe 1's own deliberate step-[4] misuse (attaching a renderbuffer
name as a texture); probe 2 isolates the clean path and reports no error at any checkpoint.

Probe 2 — GL-error cleanliness, normals, distance fog:

```
-- after InitWindow --
-- after LoadShaderFromMemory x2 --
-- after clean shader-mode 3D frame --
(b) DrawTriangle3D          -> |fragNormal| as RGB = [0, 0, 0, 255]
    rlBegin + rlNormal3f    -> |fragNormal| as RGB = [0, 0, 255, 255]
    => DrawTriangle3D supplies a normal: false
    => hand-rolled supplies (0,0,1):     true
-- after fog frames --
(c) near quad (~2 units): fogFactor=241/255  dist=16/255*32
    far  quad (~16 units): fogFactor=6/255  dist=128/255*32
    => distance-to-camera fog varies with depth on batch geometry: true
-- final --
done, no GL error printed above means clean
```
