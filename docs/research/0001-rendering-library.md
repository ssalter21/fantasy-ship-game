# Odin 2D rendering/windowing library survey

Scoped by GitHub issue #5. Constraints from ADR-0002 and ADR-0003: the library must be
drivable imperatively from application code that owns its own loop (`run_session` is the
one driver loop; UI mode nests a blocking render loop inside its `Event_Sink`/`Input_Source`
callbacks), and it must be import-graph-isolatable to `cmd/game` only, since headless must
never touch it even at compile time.

## vendor:raylib

**Where it lives**: in-tree in the Odin compiler repo at
[`vendor/raylib`](https://github.com/odin-lang/Odin/tree/master/vendor/raylib) -
`raylib.odin`, `raymath.odin`, `raygui.odin`, `easings.odin`, prebuilt binaries per platform
(`windows/`, `linux/`, `linux-arm64/`, `macos/`, `wasm/`), a `LICENSE`, and a `README.md`.

**Maintenance/versioning**: the top-level [`vendor/README.md`](https://github.com/odin-lang/Odin/blob/master/vendor/README.md)
states vendor packages "are curated and maintained by the Odin team," and PRs against
`vendor:` shouldn't be opened without consulting them first. raylib bindings are actively
kept current: commit history on the `vendor/raylib` path shows "Raylib 6.0 bindings update;
add `vendor:*` policy to its `README.md`" merged 2026-07-07, followed by fix commits on
2026-07-07 and 2026-07-09 (`raymath: Vector3DistanceSqr(t)`) -
[commit history](https://github.com/odin-lang/Odin/commits/master/vendor/raylib).

**Upstream project health** ([raysan5/raylib](https://github.com/raysan5/raylib)): 33,770
stars, 3,189 forks, 20 open issues, last push 2026-07-07. Release cadence: `6.0` published
2026-04-23, `5.5` published 2024-11-18, `5.0` published 2023-11-18 (via GitHub Releases API).
The README advertises an active Discord, Reddit (`r/raylib`), and YouTube presence.

**Loop model**: "you write the loop." The canonical example bundled in the vendor README:

```odin
rl.InitWindow(800, 450, "raylib [core] example - basic window")
for !rl.WindowShouldClose() {
    rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)
        rl.DrawText("Congrats! You created your first window!", 190, 200, 20, rl.LIGHTGRAY)
    rl.EndDrawing()
}
rl.CloseWindow()
```
([source](https://github.com/odin-lang/Odin/blob/master/vendor/raylib/README.md)). This is
directly the "blocking modal loop" shape ADR-0002 calls for: a UI-mode `Event_Sink` can
call `BeginDrawing`/draw calls/`EndDrawing` in its own poll-draw-repeat loop and just return
when done, with no framework callback structure to fight.

**Headless behavior - documented risk, not a strength**: raylib does not document a safe
headless/no-display path. [raysan5/raylib#4801](https://github.com/raysan5/raylib/issues/4801)
reports that `InitWindow()` segfaults (rather than failing gracefully) when no window/GL
context can be created - including the no-`DISPLAY` case - and that `IsWindowReady()` always
returns `true` even though its doc comment implies it should allow the caller to detect and
exit on failure. There is no core, first-party "software renderer"/offscreen mode described
in raylib's own docs; headless-friendly forks (e.g. `icodealot/raylib-go-headless`) exist only
as separate Go-binding projects, not part of `vendor:raylib`. This is consistent with why
ADR-0003 wants the headless/UI split to be a compile-time package-import fact rather than
trusting the library to behave when uninitialized or unused.

## vendor:sdl2 and vendor:sdl3

**Where they live**: also in-tree - [`vendor/sdl2`](https://github.com/odin-lang/Odin/tree/master/vendor/sdl2)
and [`vendor/sdl3`](https://github.com/odin-lang/Odin/tree/master/vendor/sdl3). Both are
extensive per-module binding sets (`sdl_audio.odin`, `sdl_events.odin`, `sdl_render.odin`,
`sdl_video.odin`, `sdl_joystick.odin`, etc.; sdl3 additionally has `sdl3_gpu.odin` for SDL3's
newer GPU API), plus prebuilt `SDL2.dll`/`SDL3.dll` + `.lib`, a `gamecontrollerdb.txt`, and
sub-bindings for `image/`, `mixer/` (sdl2 only), `ttf/`, `net/` (sdl2 only). Per
[`vendor/README.md`](https://github.com/odin-lang/Odin/blob/master/vendor/README.md) these
are "Bindings for the cross platform multimedia API SDL2/SDL3 and its sub-projects," under
the same Odin-team-curated policy as raylib.

**Maintenance/versioning**: both actively touched. `vendor/sdl2` commit history shows a merge
on 2025-12-11 ("Merge pull request #5984 from dozn/patch-4"); `vendor/sdl3` shows more recent
and more frequent churn, most recently 2026-06-26 ("Remove non-exported `joystick_lock`") and
2026-06-23 ("Correct numerous issues with SDL3 and add missing procedures") - see
[sdl2 history](https://github.com/odin-lang/Odin/commits/master/vendor/sdl2) and
[sdl3 history](https://github.com/odin-lang/Odin/commits/master/vendor/sdl3). This reads as
SDL3 bindings still catching up/stabilizing against a newer upstream API relative to the
longer-settled SDL2 bindings.

**Upstream project health** ([libsdl-org/SDL](https://github.com/libsdl-org/SDL), the SDL3
source - SDL2 has since merged into the same repo's history): 16,074 stars, 2,854 forks, 766
open issues, last push 2026-07-08. Recent point releases roughly monthly:
`release-3.4.12` (2026-07-01), `release-3.4.10` (2026-05-31), `release-3.4.8` (2026-05-02).

**Loop model**: lower-level than raylib - SDL gives you windowing/input/GPU context (plus an
`SDL_Render` 2D renderer API, e.g. `sdl_render.odin`/`sdl3_render.odin`, so it isn't pure
OpenGL plumbing either) and expects an explicit poll loop. SDL3's own docs describe two
supported shapes: the traditional `main()` with your own `while` loop calling
`SDL_PollEvent`, fully supported; and a newer *optional* callback style
(`SDL_AppInit`/`SDL_AppIterate`/`SDL_AppEvent`/`SDL_AppQuit`) that SDL drives instead -
explicitly documented as "completely optional and you can ignore it if you're happy using a
standard 'main' function"
([SDL3 README-main-functions](https://wiki.libsdl.org/SDL3/README-main-functions)). Used in
its traditional mode, this fits ADR-0002's shape as well as raylib does; it just requires
building more of the 2D drawing convenience yourself (more DIY per the project's "more
learning" framing, but also more work before a vertical slice renders anything).

**Headless behavior**: SDL documents a "dummy" (aka `null`) video driver, selectable via the
`SDL_VIDEO_DRIVER` hint (`SDL_VIDEODRIVER` recognized for SDL2-era back-compat), intended for
running without a real display -
[`SDL3/SDL_HINT_VIDEO_DRIVER`](https://wiki.libsdl.org/SDL3/SDL_HINT_VIDEO_DRIVER). This is
better-documented graceful-degradation behavior than raylib's crash-on-headless issue above.
It does not change the project's architecture decision, though - ADR-0003 already makes
headless never import the rendering package regardless of how well that package would have
behaved if it had been imported, so this is a minor point in SDL's favor on general library
robustness, not a factor that changes the compile-time isolation requirement.

## vendor:sokol

**Where it lives - not in-tree.** Odin's own `vendor/` directory (enumerated via the GitHub
API against
[`odin-lang/Odin/vendor`](https://github.com/odin-lang/Odin/tree/master/vendor)) contains
`box2d, box3d, cgltf, commonmark, compress, curl, darwin, directx, egl, fontstash, ggpo,
glfw, kb_text_shape, libc, libc-shim, lua, microui, miniaudio, nanovg, OpenEXRCore, OpenGL,
portmidi, raylib, sdl2, sdl3, stb, vulkan, wasm, wgpu, windows, x11, zlib` - there is no
`sokol` entry. Odin bindings for the sokol headers instead live in a separate repo,
[floooh/sokol-odin](https://github.com/floooh/sokol-odin), maintained by Andre Weissflog
(floooh), the author of sokol itself - not the Odin core team. This confirms the "third
party, not vendor/" structure flagged in the issue.

**Maintenance activity**: very actively synced. Recent commits on `sokol-odin` are
auto-generated syncs against upstream header changes, e.g. "updated
(link to a floooh/sokol commit)" on 2026-07-08, 2026-07-07, 2026-07-02, 2026-06-11,
2026-06-05, 2026-05-29 (x2), 2026-05-28 -
[commit history](https://github.com/floooh/sokol-odin/commits/main). `sokol-odin` itself: 274
stars, last push 2026-07-08. Upstream [floooh/sokol](https://github.com/floooh/sokol): 10,058
stars, 652 forks, 133 open issues, last push 2026-07-08.

**Loop model - inverted from raylib/SDL**: sokol_app.h's own header docs describe an
application providing an `sapp_desc` with callback pointers: `init_cb` ("called once after
the application window, 3D rendering context and swap chain have been created"), `frame_cb`
("the per-frame callback, which is usually called 60 times per second"), `cleanup_cb`
("called once right before the application quits"), and `event_cb` for input/other events
([sokol_app.h](https://raw.githubusercontent.com/floooh/sokol/master/sokol_app.h) doc
comments). sokol_app owns `main()`/the loop and calls back into your code - the opposite of
raylib's and SDL's "you write the `while` loop" shape, and a poor fit for ADR-0002: making
`run_session` the single outermost driver loop with UI's `Event_Sink` nesting its own
blocking poll-draw loop is straightforward when you control the loop (raylib/SDL), and
awkward when the render library insists on owning `main` and calling `frame_cb` on its own
schedule instead of being called by your `Event_Sink` between decisions.

**Headless behavior**: not documented one way or the other in the header comments fetched
here. `init_cb`'s doc text treats window + 3D context + swapchain creation as a hard
precedent ("called once after [they] have been created"), with no mention of a windowless or
offscreen mode. Stating this as "undocumented," not "confirmed absent," since the full sokol
header set (sokol_gfx.h separately from sokol_app.h) wasn't exhaustively reviewed.

## Other options (one line each)

- **vendor:glfw + vendor:OpenGL** - also official, in-tree Odin bindings
  ([glfw](https://github.com/odin-lang/Odin/tree/master/vendor/glfw),
  [OpenGL](https://github.com/odin-lang/Odin/tree/master/vendor/OpenGL)) for the classic
  GLFW-window-plus-raw-GL-calls stack; more DIY than raylib (no 2D draw calls at all - you'd
  write your own batch renderer), likely more plumbing than a vertical slice needs right now.
- **vendor:wgpu** - official, in-tree bindings to wgpu-native
  ([vendor/wgpu](https://github.com/odin-lang/Odin/tree/master/vendor/wgpu),
  [pkg docs](https://pkg.odin-lang.org/vendor/wgpu/)); WebGPU itself is still evolving spec
  (community binding docs describe the API as still in "Working Draft" -
  [Capati/wgpu-odin](https://github.com/Capati/wgpu-odin)), more modern-GPU-API complexity
  than 2D sprite drawing needs.
- **Community wgpu bindings** (e.g. [Capati/wgpu-odin](https://github.com/Capati/wgpu-odin),
  [JopStro/webgpu-odin](https://github.com/JopStro/webgpu-odin)) - alternatives to
  vendor:wgpu, same complexity concern applies.
- **Dear ImGui-adjacent bindings** (e.g.
  [ThisDevDane/odin-imgui](https://github.com/ThisDevDane/odin-imgui),
  [Capati/odin-imgui](https://github.com/Capati/odin-imgui)) - immediate-mode debug/tool UI
  layered on top of an existing backend (SDL/GLFW + GL/Vulkan/D3D11), per the
  [Dear ImGui bindings wiki](https://github.com/ocornut/imgui/wiki/Bindings); solves in-game
  debug tooling, not the base 2D rendering question, so orthogonal to this decision.

## Recommendation

**Pick vendor:raylib.**

1. **Maturity/stability of bindings**: raylib and SDL2/SDL3 are equally official, in-tree,
   Odin-team-curated vendor packages per
   [`vendor/README.md`](https://github.com/odin-lang/Odin/blob/master/vendor/README.md), both
   with commits within the last two days as of this writing (raylib: 2026-07-09; sdl3:
   2026-06-26). sokol-odin is also very actively maintained, but lives outside the Odin core
   team's own tree - its bindings' compatibility with future Odin compiler releases depends on
   a third party ([floooh/sokol-odin](https://github.com/floooh/sokol-odin)) rather than the
   compiler team itself, a materially different support model. Advantage: raylib/SDL, tied.

2. **Ease of driving a game loop headless can bypass entirely**: this is the deciding
   criterion. raylib's `for !WindowShouldClose() { BeginDrawing()...EndDrawing() }` and SDL's
   traditional explicit `SDL_PollEvent` loop both match ADR-0002's required shape - an
   application-owned loop that a blocking `Event_Sink`/`Input_Source` implementation can nest
   inside itself, called by `run_session`, not the other way around. sokol_app inverts this:
   it owns `main()` and drives `frame_cb`/`init_cb`/`cleanup_cb` on its own schedule, which
   fights the "UI nests a render loop inside its callback, `run_session` stays outermost"
   design from ADR-0002 rather than fitting it. Advantage: raylib/SDL over sokol; roughly tied
   between raylib and SDL on this criterion alone, since both are "you write the loop"
   libraries.

3. **Community support**: raylib has the largest community by GitHub stars among the three
   (33,770 vs. SDL's 16,074 vs. sokol's 10,058) and an explicitly beginner/game-dev-oriented
   ecosystem (Discord, Reddit, YouTube channel, "+140 code examples," "+70 language bindings"
   per raylib's own README). SDL's larger open-issue count (766 vs. raylib's 20) reflects a
   broader low-level surface area rather than instability. Advantage: raylib.

4. **Fit with the from-scratch custom-engine learning goal**: this is the one criterion where
   SDL's lower-level nature is arguably a better match - more manual event/window/context
   plumbing means more learning, per the project's own framing. But raylib is still a thin C
   library you call into directly (no scene graph, no asset pipeline, no engine-owned update
   loop) - it satisfies "thin layer we control the loop around" just as much as SDL does, it's
   simply higher-level about the drawing calls themselves (`DrawTexture`/`DrawRectangle`
   immediate calls vs. SDL's explicit renderer/texture object management). Given the vertical
   slice's scope (2D sprite-level rendering, not a custom 2D batch renderer as its own
   learning goal), raylib's higher-level draw calls reduce the amount of infrastructure that
   has to be built before anything is on screen, without giving up control of the loop.
   Advantage: roughly tied, slight edge to SDL for "more DIY," but not enough to outweigh
   raylib's wins on criteria 2 and 3.

Weighing all four, **raylib** is the pick: it ties or wins on three of the four criteria and
is only arguably behind SDL on the fourth. One caveat to carry forward: raylib's `InitWindow`
is documented to crash (not fail gracefully) when a window/GL context can't be created
([raysan5/raylib#4801](https://github.com/raysan5/raylib/issues/4801)) - this is not a
blocker given ADR-0003 already guarantees the headless executable never imports the
rendering package, but it means `cmd/game` itself should never be expected to run correctly
on a headless CI runner, by design, not just by convention.
