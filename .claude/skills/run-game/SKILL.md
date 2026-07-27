---
name: run-game
description: Build, launch, drive and screenshot the game, and iterate on its UI against the style guide. Use when running or driving the game, capturing its screens, verifying a change in the real window, or building/changing any UI in the presentation package.
---

# Running the game and seeing its UI

This is the loop that built the Chart Table ([#281](https://github.com/ssalter21/fantasy-ship-game/issues/281)):
**read the guide → build → capture → look → iterate**. Every command below has been run; every limit below is
one that actually bit.

The point of the loop is that **you are the feedback channel, not the maintainer**. Don't ship a screen you
have not looked at, and don't ask the maintainer what it looks like — take a shot and open it.

## Read the style guide before you draw

`docs/ui/style-guide.md` is the fixed target for "good": exact palette values, the 40/20 type scale, the
saturation rule, Pixelify Sans via `#load`, and the rules for raylib. **Read it before writing draw calls, not
after.**
It answers what the palette is, why there is no bold, and why a size is a font rather than a parameter.

Two rules from it that decide the *shape* of your code, so you want them before you start rather than in review:

- **Split composition from polling.** A new screen needs a `draw_X_screen(state)` that the blocking loop calls
  *and* capture calls. Compose buttons inside a poll loop and `--capture` photographs the screen with its
  buttons missing. `draw_chart_table` and `draw_option_screen` are the worked examples; the other four screens
  are the counter-example.
- **Reach for no layout system.** A centred stack is a pure function of a few constants, hit-tested and drawn
  from one call — see `chart_table_buttons` in `presentation/chart_table.odin`.

Found a gap in the guide? **Fix the guide**, don't make a one-off decision at the call site. #281 found six and
fixed all six there.

## Build

```powershell
odin build cmd/game        # under a second; produces ./game.exe
odin build cmd/headless

foreach ($pkg in 'core/combat','core/voyage','core/ship','core/sim','presentation','presentation/cutaway','cmd/headless') { odin test $pkg }
# 403 core (54+131+140+78), 87 presentation, 11 presentation/cutaway, 1 cmd/headless — same list CI runs
```

There is **no wildcard**: `odin test core/...` is a syntax error ("Empty directory that contains no .odin
files"). Name each package. CI checks `$LASTEXITCODE` after every invocation for a real reason — a later
passing package resets it and masks an earlier failure.

**A test binary is named for its package directory and deleted on the way out** — so `odin test presentation`
writes and removes `presentation.exe`, which no longer collides with the `game.exe` a build produces
(`cmd/game` holds only the thin main, #433). CI still passes `-out:` to send each test binary to the runner's
temp dir, keeping every invocation's path its own.

**CI runs the same package list**, the UI tests included ([#292](https://github.com/ssalter21/fantasy-ship-game/issues/292))
— `.github/workflows/ci.yml` executes it in the same order, so a green PR check does mean
`chart_table_test.odin`, `capture_test.odin` and `presentation_test.odin` passed. Run them locally anyway —
the loop is a few seconds, and it's the difference between finding a break now and finding it after a push.

## Capture: the screens, without playing the game

**Shooting one screen is the loop you want.** Name it and nothing else runs:

```bash
odin run cmd/game -- --shot build          # or --shot=build
```

Under a second, one PNG, then the process exits. The shot lands in `docs/ui/shots/` at the same number and
filename a full run gives it (`05-build.png`), so a shot taken this way is interchangeable with one from the
walk. `--shot` beats `--capture` when both are passed.

An unknown name — or a bare `--shot` — prints the names that exist and exits 1 without opening a window, so
**ask for a wrong name to get the list** rather than hunting for it:

```
capture: no shot named "buld". Shots: chart-table, chart-table-hover, home, home-chart-rising, … (The voyage
screens are --capture only.)
```

Those are the **standalone** screens — the entries of `capture_shots` in `presentation/capture.odin`, the
registry of every state capture can set up without a voyage. The walk's own screens (`travel`, `options`,
`trade`, `refit`, `battle`, `ended`) need the scripted session and are reachable only through the full run.

**A state is a line in that table, not a source edit.** Each entry pairs a name with a `stage` (builds the
world it draws from — a ship, a ticked Sim — and runs once) and a `frame` (composes one frame, and runs
twice, so it may arrange a drag or a cursor but must not allocate). A `frame` returning false says the state
could not be arranged — a missing roster item, a berth with nowhere to put a hover — and nothing is shot.
Adding a state means adding a line and its `frame`; a test checks the names are unique and that each shot
carries its walk-order number.

A targeted run that writes nothing — a screen that bailed out, or a shot that couldn't be moved into
`docs/ui/shots/` — says so and exits 1. It never reports a file that isn't there.

```bash
odin run cmd/game -- --capture
```

The whole gallery: takes every `capture_shots` entry, then walks a scripted voyage for the rest — 38 PNGs to
`docs/ui/shots/` (gitignored, regenerable) in about 40s. The registry is the same one `--shot` reads, so there
is no second list to drift; it reuses `draw_scene` and the real `dispatch` untouched, so what the game draws is
what gets shot. Reach for it when you want the gallery or a voyage screen; reach for `--shot` the other 90% of
the time.

**Never kill a capture mid-walk to get at one shot.** That was the old recipe and it is what `--shot` replaces:
deleting the shots directory out from under a running walk makes every subsequent `os.rename` fail, stranding
raylib's screenshots in the repo root — where **`*.png` is not gitignored**, so a later `git add .` commits 35
battle screens. If you find loose `NN-*.png` beside `game.exe`, that's what happened:

```powershell
Get-ChildItem -Filter '??-*.png' | Remove-Item        # repo root, not docs/ui/shots
```

If you do run the full walk, use **PowerShell**, not the Bash tool: this repo's Git Bash has no `pkill`, and
backgrounding with `&` there blocks the tool until the walk finishes.

## Look every time — then check the numbers

**Open the PNG with the Read tool.** A shot you didn't open is not feedback, and a blank frame is a failure to
launch.

Then, before you believe a *value* you think you see: **scan the pixels**. Eyeballing a shot is not measuring
one. Two sessions in a row have now read banding into the Chart Table's vignette that is not there — it is a
clean gradient, corners exactly `#050B18`, centre `#081429`.

```bash
python -c "
from PIL import Image
im = Image.open('docs/ui/shots/00-chart-table.png').convert('RGB')
w, h = im.size
for name, (x, y) in {'top-left': (2, 2), 'centre': (w//2, h//2), 'bottom-right': (w-3, h-3)}.items():
    print(name, '#%02X%02X%02X' % im.getpixel((x, y)))
"
```

Any claim about a colour, a size or an alignment should come off a scan like this and be checked against the
guide's stated value.

**The scan settles a value; it cannot judge a screen.** Three pixels have nothing to say about whether the
spacing reads, whether the eye lands where you meant it to, or whether the thing is simply ugly. That is what
looking is for, and it is why a scan never stands in for one.

## Zoom into a shot, and diff two of them

`scripts/shot.py` sits between looking and scanning: detail the eye cannot resolve at 1:1, and a comparison
against the *previous shot* rather than against your memory of it.

```bash
python scripts/shot.py zoom 00-chart-table top-left --factor 3
python scripts/shot.py diff 05-build 06-build-hover
```

Both take a bare shot name (resolved against `docs/ui/shots/`, `.png` optional) or a path, and write under
`docs/ui/shots/zoom/` and `docs/ui/shots/diff/` — gitignored and regenerable, like the shots themselves.

**Park your "before" outside `docs/ui/shots/` first.** Shots are written under fixed filenames, so the next
`--capture` — or the next `--shot` of the same screen — overwrites the very frame you meant to diff against.
Copy the before-shot somewhere else, or send output there with `--out` (zoom) and `--out-dir` (diff):

```bash
cp docs/ui/shots/05-build.png /tmp/before.png     # survives the next capture
python scripts/shot.py diff /tmp/before.png 05-build --out-dir /tmp/diff
```

**Zoom** crops a region and magnifies it by an integer factor (default 3), **nearest-neighbour**, so a pixel
stays a hard-edged square and you are looking at the real pixels rather than at an interpolation of them.
Cropping the ship screen's top-left quadrant at 3x is what exposed the sky/cloud resolution mismatch that is
invisible at 1:1.

Named regions mean you rarely need coordinates: `full`, `top`, `bottom`, `left`, `right`, the four quadrants
(`top-left`, `top-right`, `bottom-left`, `bottom-right`), and `centre` (the middle half, spelled `center` too).
They are fractions of the shot, so a name means the same thing at any resolution. `x,y,w,h` in pixels still
works for a particular widget.

**Diff** writes a side-by-side (before left, after right) *and* a mask: the after-shot dimmed to a grey ghost
with every changed pixel in magenta, so you see *what* changed and *where in the frame* it sits at once. It
prints the changed-pixel count and percentage, the bounding box of the change, and the **max channel delta** —
read that last number before you believe a diff, because a max delta of 2 is noise, not a design change.

**Diffing two identical shots says so and writes nothing.** That is the useful answer: an empty mask looks
exactly like a mask you forgot to open.

The two compose, and that is the main way to use them: diff to find *where* the change is, then zoom that
region — the mask's printed bounding box is the region argument. The printed numbers tell you a change landed
and how far it reached; they do not tell you the screen reads. They aim the look, they don't stand in for it.

Sizes must match; a mismatch is reported with both dimensions rather than silently padded.

**This is an instrument for 2D chrome.** Geometry bugs on the 3D ship screen are invisible rather than small,
and magnifying a correctly-drawn but wrong-facing surface tells you nothing. The workbench's normal paint and
wireframe views are what serve those (below).

## Context budget: look every iteration, scout the source

This loop spends context faster than it produces code: a screen that lands in a ~750-line diff can burn a 250K+
session, and almost none of it reaches the diff. It goes to *process* — mostly source files full-read to find a
seam. An implementation session's target is **150K**, and it's defended here, where the spending happens.

Measured on this repo, so no session has to re-derive it:

- one 1244x700 capture shot — **~1,160 tokens**
- `view.odin`, 1,136 lines — **~14,000 tokens**
- `build_surface.odin`, 977 lines — **~12,000 tokens**

A screenshot costs roughly **8% of one read of the file you are editing**. Looking is the cheap part of this
loop; budget it like it is.

- **Look at the screen every iteration.** Every time you change what is drawn, capture and open the shot. A
  change you have not looked at is unverified — and no pixel probe will tell you the layout is now crowded, the
  caret sits under the wrong row, or the whole screen reads flat. A session that economises on looking has
  optimised away its only feedback signal.
- **Scout source, full-read only to edit — this is the actual sink.** To learn *what `build_card_dims` returns
  and where the seam sits*, send a sub-agent into the big render files (`view.odin` and `build_surface.odin`,
  a thousand lines each) and keep the digest it reports back; the code informs your edit without settling
  permanently into the window. Full-read a file only for the lines you are about to change. One avoided
  full-read pays for a dozen looks.
- **Read the shots you are iterating on, not the gallery.** A full walk writes **38 per run**; one to three of
  them are yours. `--shot <name>` writes exactly the one you asked for, so the other 37 never exist to be read.
- **Push noisy investigation into a sub-agent.** Tracing how the encounter frame, build surface and a retired
  loop fit together is fan-out reading — dispatch it and keep the findings, not the file dumps.
- **Size the work to one screen, one seam.** A ticket scoped to a single screen opens few files and looks at
  few shots. That, not a token count, is what keeps the session inside budget.

## What capture cannot see

Capture is the fast path, not the whole picture. Three blind spots, all real:

- **Only the states someone named.** Capture has no mouse, so it cannot *discover* a hover, a drag or a frame
  mid-animation — but it can be told where the cursor is. Those are entries in `capture_shots` like any other
  screen (`chart-table-hover`, `build-hover`, `build-placing`, `home-chart-rising`), each shot by name in a
  second. What is invisible is the state nobody has added yet, and the fix is a line in the table — **never a
  hard-coded cursor edited in, shot, and reverted**, which is the old recipe and strands the repo one
  forgotten `git checkout` away from a wrong screen.
- **The outer loop, at all.** `capture_main` has its own entry and never enters `chart_table_loop`, so the one
  structure ADR-0022 changed is invisible. Verifying *Begin → voyage → back*, or that *Quit* quits, needs the
  real window (below).
- **Silent culling.** A wrongly-wound `rl.DrawTriangle` draws *nothing* rather than something wrong, so a
  resting shot looks fine and the bug ships. If a shape is missing, suspect winding before you suspect colour.
- **Anything the fullscreen blit does.** The player session composes into a render texture and blits it;
  `--capture` draws at logical size with no texture in the path. A whole class of bug lives only in the real
  window — see the style guide's "A render texture loses alpha". Measure translucency there, never in a shot.

## The hull workbench: stop iterating on the ship screen by text

```bash
odin run cmd/game -- --workbench
```

The ship screen has a fourth entry beside `--capture` and the session, and **use it before editing any number
in `cutaway/galleon.odin`**. It draws the real `draw_ship_cutaway` into the real logical frame with a control
panel over it:

- **Every curve in the loft is a slider** — keel camber, sheer, the entry, the run, the wale, tumblehome. The
  ship redraws under the mouse. `C` copies the tuned `GALLEON_LOFT` to the clipboard as Odin to paste back;
  the tool never writes to the repo. `R` returns to the shipped hull and the shipped framing.
- **`N` paints by normal** — +x red, +y green, +z blue, negatives dark. Turn this on *first* when a surface
  looks merely dull. Every hard bug on this screen has been a face pointing the wrong way, and in normal paint
  that looks like a slightly-off shade; here it is the wrong colour outright.
- **`M` is wireframe** — the loft's resolution, degenerate quads, and daylight between two pieces that should
  meet. (rlgl batches geometry, so wire mode needs `DrawRenderBatchActive` either side of it or it lands on
  whatever was in flight. `draw_ship_cutaway` does that.)
- **The camera flies** — yaw, distance, height, look and fov, plus the wheel to dolly. This is the one that
  answers *is this thing actually solid*: orbit and a room standing through the planking is obvious.

The shipped framing is not tunable and must not become so: `galleon_view` builds from the five constants and
`galleon_view_from` exists only for this tool. A test asserts the two agree.

Why it is not in the Forge: **the Forge never imports `presentation/`**, in writing, and everything that paints
this hull lives there. Moving it needs the galleon's painter and the palette extracted into shared packages.

## Drive the real window when capture can't reach it

Synthetic Win32 input against the running process. This is what verified the outer loop's two quit paths, and
it works — clicking *Quit* exits 0.

```powershell
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
}
"@
$p = Start-Process -FilePath ".\game.exe" -PassThru
Start-Sleep -Seconds 3
$p.Refresh()
$h = $p.MainWindowHandle
[void][W]::SetForegroundWindow($h)
# Client coords -> screen coords. The window has a title bar; do not skip this.
$pt = New-Object W+POINT; $pt.X = 512; $pt.Y = 446   # Quit, per chart_table_buttons()
[void][W]::ClientToScreen($h, [ref]$pt)
[void][W]::SetCursorPos($pt.X, $pt.Y)
Start-Sleep -Milliseconds 600
[W]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)   # LEFTDOWN
Start-Sleep -Milliseconds 80
[W]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)   # LEFTUP
if ($p.WaitForExit(8000)) { "exited=$($p.ExitCode)" } else { "STILL RUNNING"; $p.Kill() }
```

Derive the coordinates from the layout procs (`chart_table_buttons()`), don't measure them off a screenshot by
eye. **`ClientToScreen` is not optional** — raylib's coordinates are client-relative and the window is not at
the origin.

**Closing the window quits the game, from anywhere** — including mid-voyage (ADR-0023). One
`window_quit_if_closed()` in `presentation/presentation.odin` is the only thing that answers a close; every blocking loop
calls it once per frame and no loop has a close-fallback. If you add a render loop, call it — a loop that
polls `rl.WindowShouldClose()` itself will silently swallow the close.

Two things about that flag, both measured, because plausible wrong accounts of it have now shipped twice (see
ADR-0023): it does **not** latch, and it is **not** consumed on read. It survives exactly one frame — three
reads within a frame all return `true` — and raylib clears it in `EndDrawing`'s event poll. Don't reason about
it; probe it.

Driving a close is `PostMessage($h, 0x0010, ...)` (`WM_CLOSE`) against the window handle, alongside the
synthetic mouse above. `WaitForExit` then tells you whether it stopped.

## Odds and ends

- `rl.TakeScreenshot` runs its filename through `GetFileName()` and writes to the process's **cwd**, so a path
  prefix is silently dropped. `capture_write` moves each shot into `docs/ui/shots/` afterwards.
- Capture draws every frame **twice** before shooting. `TakeScreenshot` reads back the framebuffer
  `EndDrawing` just presented, so a single draw screenshots the *previous* frame. Keep the double draw.
- There is no `cmd/capture`: capture lives in the presentation package beside the private `draw_scene`,
  `Game_State` and `dispatch` it photographs, and `cmd/game` enters it behind `--capture` and `--shot`
  (ADR-0003 argues against linking the renderer into `cmd/headless`, not against this).
- The scripted walk declines everything and cannot target a *particular* screen — it reaches *a* screen of most
  kinds, and never opens a Refit at all. `--shot` targets by name, but only among the standalone screens.
- A targeted shot stages its own scene and draws nothing else — the frame you asked for is composed and
  double-drawn exactly as the full walk composes it, from a world nothing else has touched.

## Relation to /run and /verify

This **is** the project skill those two go looking for; it is not a thing beside them.

- `/run` greps `.claude/skills/*/SKILL.md` description lines for one that describes launching this app, and
  follows it verbatim instead of its generic fallback patterns. That's this file.
- `/verify` probes `.claude/skills/` for `verifier-*` or `run-*` and uses the latter's build/launch primitives
  as its handle — hence the `run-` prefix. For a UI change, the evidence it wants is a capture shot you looked
  at, plus the real window where capture can't see.
