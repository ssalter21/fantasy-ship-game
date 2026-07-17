---
name: run-game
description: Build, launch, drive and screenshot the game, and iterate on its UI against the style guide. Use when running or driving the game, capturing its screens, verifying a change in the real window, or building/changing any UI in cmd/game.
---

# Running the game and seeing its UI

This is the loop that built the Chart Table ([#281](https://github.com/ssalter21/fantasy-ship-game/issues/281)):
**read the guide → build → capture → look → iterate**. Every command below has been run; every limit below is
one that actually bit.

The point of the loop is that **you are the feedback channel, not the maintainer**. Don't ship a screen you
have not looked at, and don't ask the maintainer what it looks like — take a shot and open it.

## Read the style guide before you draw

`docs/ui/style-guide.md` is the fixed target for "good": exact palette values, the 40/20 type scale, the amber
rule, Pixelify Sans via `#load`, and the rules for raylib. **Read it before writing draw calls, not after.**
It answers what the palette is, why there is no bold, and why a size is a font rather than a parameter.

Two rules from it that decide the *shape* of your code, so you want them before you start rather than in review:

- **Split composition from polling.** A new screen needs a `draw_X_screen(state)` that the blocking loop calls
  *and* capture calls. Compose buttons inside a poll loop and `--capture` photographs the screen with its
  buttons missing. `draw_chart_table` and `draw_option_screen` are the worked examples; the other four screens
  are the counter-example.
- **Reach for no layout system.** A centred stack is a pure function of a few constants, hit-tested and drawn
  from one call — see `chart_table_buttons` in `cmd/game/chart_table.odin`.

Found a gap in the guide? **Fix the guide**, don't make a one-off decision at the call site. #281 found six and
fixed all six there.

## Build

```powershell
odin build cmd/game        # under a second; produces ./game.exe
odin build cmd/headless

foreach ($pkg in 'cmd/game','core/combat','core/voyage','core/ship','core/sim') { odin test $pkg }
# 25 + 45 + 124 + 75 + 61 = 25 cmd/game and 305 core
```

There is **no wildcard**: `odin test core/...` is a syntax error ("Empty directory that contains no .odin
files"). Name each package. CI checks `$LASTEXITCODE` after every invocation for a real reason — a later
passing package resets it and masks an earlier failure.

**`odin test cmd/game` deletes the `game.exe` you just built** — the test binary takes the same name and is
cleaned up on the way out. So **test first, then build**. A launch that fails with "no such file" right after a
green test run is this, not your change.

**CI does not run the `cmd/game` tests.** `.github/workflows/ci.yml` only *builds* `cmd/game` — which compiles
its `_test.odin` files and so catches a broken test file, but never executes the 25 tests in it — and runs
`odin test` for the four `core/*` packages only. Everything covering the UI (`chart_table_test.odin`,
`capture_test.odin`, `main_test.odin`) is therefore **yours to run locally**; a green PR check is not evidence
they pass.

## Capture: the screens, without playing the game

```bash
odin run cmd/game -- --capture
```

Walks a scripted voyage and writes real PNGs to `docs/ui/shots/` (gitignored, regenerable). 43 shots, ~75s.
It reuses `draw_scene` and the real `dispatch` untouched, so what the game draws is what gets shot — there is
no second copy to drift.

**`00-chart-table.png` is written at frame 0, about 1 second in.** Everything after it is the voyage walk,
paying ~75s for animations capture cannot photograph anyway. If the screen you're iterating on is the Chart
Table, kill the run as soon as your shot exists — that turns a 75s loop into a ~2s one:

```powershell
Remove-Item -Recurse -Force docs/ui/shots -ErrorAction SilentlyContinue
Start-Process odin -ArgumentList 'run','cmd/game','--','--capture' -PassThru -WindowStyle Hidden | Out-Null
while (-not (Test-Path 'docs/ui/shots/00-chart-table.png')) { Start-Sleep -Milliseconds 100 }
Get-Process game -ErrorAction SilentlyContinue | Stop-Process -Force
```

Use **PowerShell** for this, not the Bash tool: this repo's Git Bash has **no `pkill`**, and backgrounding the
run with `&` there makes the Bash tool block until the full 75s walk finishes — you get neither the kill nor
the time back. Expect one or two extra shots past the one you wanted; the walk keeps going until the kill
lands.

## Look — and don't trust your eyes

**Open the PNG with the Read tool.** A shot you didn't open is not feedback, and a blank frame is a failure to
launch.

Then, before you believe what you see: **scan the pixels**. Eyeballing a shot is not measuring one. Two
sessions in a row have now read banding into the Chart Table's vignette that is not there — it is a clean
gradient, corners exactly `#050B18`, centre `#081429`.

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

## What capture cannot see

Capture is the fast path, not the whole picture. Three blind spots, all real:

- **Resting states only.** Capture has no mouse, so it shoots `draw_chart_table(-1)` — no hover. Half the
  Chart Table's design (the amber caret, the scrim lift) is invisible to it. Verifying hover means temporarily
  hard-coding the hovered index in the capture call, shooting, and reverting.
- **The outer loop, at all.** `capture_main` has its own entry and never enters `chart_table_loop`, so the one
  structure ADR-0022 changed is invisible. Verifying *Begin → voyage → back*, or that *Quit* quits, needs the
  real window (below).
- **Silent culling.** A wrongly-wound `rl.DrawTriangle` draws *nothing* rather than something wrong, so a
  resting shot looks fine and the bug ships. If a shape is missing, suspect winding before you suspect colour.

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

**Known hazard while driving:** `rl.WindowShouldClose()` **consumes** the close flag rather than latching it —
it reports `true` on exactly one call and `false` after. Closing the window mid-voyage therefore *hangs*: the
first menu loop eats the flag and the next blocks forever. This predates the Chart Table and is not yours; see
[#290](https://github.com/ssalter21/fantasy-ship-game/issues/290). Quitting *at* the Chart Table is fine.

## Odds and ends

- `rl.TakeScreenshot` runs its filename through `GetFileName()` and writes to the process's **cwd**, so a path
  prefix is silently dropped. `capture_write` moves each shot into `docs/ui/shots/` afterwards.
- Capture draws every frame **twice** before shooting. `TakeScreenshot` reads back the framebuffer
  `EndDrawing` just presented, so a single draw screenshots the *previous* frame. Keep the double draw.
- There is no `cmd/capture`: `draw_scene`, `Game_State` and `dispatch` are all `package main`, so Odin rejects
  a sibling executable. Capture lives in `cmd/game` behind `--capture` on purpose (ADR-0003 argues against
  linking the renderer into `cmd/headless`, not against this).
- The scripted walk declines everything and cannot target a *particular* screen — it reaches *a* screen of most
  kinds, and never opens a Refit at all.

## Relation to /run and /verify

This **is** the project skill those two go looking for; it is not a thing beside them.

- `/run` greps `.claude/skills/*/SKILL.md` description lines for one that describes launching this app, and
  follows it verbatim instead of its generic fallback patterns. That's this file.
- `/verify` probes `.claude/skills/` for `verifier-*` or `run-*` and uses the latter's build/launch primitives
  as its handle — hence the `run-` prefix. For a UI change, the evidence it wants is a capture shot you looked
  at, plus the real window where capture can't see.
