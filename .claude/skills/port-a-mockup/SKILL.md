---
name: port-a-mockup
description: Port a chosen browser mockup into the presentation package as an Odin screen — through the widget vocabulary, with its geometry in a steerable layout block. Use when implementing a picked design, turning a mockup into a screen, or when direct-a-screen has produced a decision and someone has to build it.
---

# Port a mockup

`direct-a-screen` ends at a decision and says so: *it does not implement*. `run-game` picks up at
build-and-capture. This is the stage between them, and it is the one where a design either lands on
the roster or quietly drifts off it.

The porting **table** lives in [`docs/ui/mock/README.md`](../../../docs/ui/mock/README.md) and is
not restated here — read it, it is the mapping and it is short. This file is about the four
decisions the table does not make for you.

## The failure this exists to fix

Five screens each grew their own implementation of "a rectangle with text in it". The cost was
never the duplication; it was that **a look change had to be made five times and therefore never
was.**

The widget layer retired that, and the measurement is the point: changing the card frame's inner
ring from sand to sea-deep — *one list literal* in `scripts/make-ui-frames.py` — moved **eight
screens**. A port that hand-rolls its own chrome rebuilds exactly the thing that bought, and it
will pass review because it looks right in the one shot you took.

## Prerequisites

- **The chosen mockup**, and its closing **port-cost block** — its level, what its direction
  forced, what it needed from `ui.odin` that does not exist, and what it invented or broke. That
  block is step 1's input.
- **A level this can port.** `house` ports as drawn. `off-style` ports too, but its `invented`
  field is work you are agreeing to: an off-roster colour is a swatch that has to enter
  `docs/ui/style-guide.md` and the roster deliberately, and a third type size is a new atlas.
  **A `free` mockup does not arrive here** — its `broke` field is engine work, and it owes another
  round at `house` or `off-style` first. If one reaches you, stop and say so; do not port it by
  quietly deleting the parts raylib cannot draw, because what is left is a design nobody chose.
- [`docs/ui/mock/README.md`](../../../docs/ui/mock/README.md) — the CSS→Odin table.
- [`docs/ui/style-guide.md`](../../../docs/ui/style-guide.md) — the rules. Not the rationale;
  you are following rules here, not changing them.
- The screen as it ships: `odin run cmd/game -- --shot <name>`, and **open it**.

## 1. Settle the missing components first, at the widget layer

Read the mockup's note. If it needs something `ui_widgets.odin` does not have, you have three
honest moves and one dishonest one:

- **Build the widget**, in `presentation/ui_widgets.odin`, over the existing axes. It is a
  component the moment a second screen would want it.
- **Find the widget that already covers it** under a different name — most "new" demands are an
  `Ui_Emphasis` step or an `Ui_Elevation` the caller did not know about.
- **Narrow the design**, and say so. A control the vocabulary cannot express is a decision to take
  deliberately, not to discover halfway through.
- **Not this:** solve it at the call site with a raw draw. That is how five screens got five
  rectangles.

**Do this before porting the layout**, not during. A component invented mid-port is shaped by the
one screen in front of you.

## 2. Port through the widgets — a call site names a role, never a value

Reach for `ui_panel` / `ui_card` / `ui_button` / `ui_heading` / `ui_divider` / `ui_icon` /
`ui_alarm` / `ui_text`. **Nothing takes an `rl.Color`, a font size, or a raw spacing** — that is
what makes the guide's rules unbreakable through these procs rather than merely written down.

| Axis | Values | What you are naming |
| --- | --- | --- |
| `Ui_Emphasis` | `Primary` `Secondary` `Muted` `Unavailable` | rank *within* a block. `Unavailable` dims **by tone, never alpha** — over bright water, alpha costs a surface its own ground. |
| `Ui_Elevation` | `Inset` `Flush` `Raised` `Floating` | how far off its ground. `Floating` casts; the shadow is a second rectangle, which is what raylib has. |
| `Ui_Level` | `Display` 48 · `Title` 32 · `Body` 16 | **size says which block to read first; colour ranks within it.** The scale is closed at three. |
| `Ui_Space` | `None` 0 · `Hair` 2 · `Tight` 4 · `Snug` 8 · `Base` 12 · `Wide` 16 · `Loose` 24 · `Vast` 32 | every gap, inset and pitch. Re-rhythming a screen is then a change of names, not a hunt for numbers. |
| `Ui_Ground` | `Parchment` `Water` | decides what ink is legible: dark ink on parchment, light over water, never the other way round. |

**The build enforces this.** `no_screen_strokes_its_own_chrome`
(`presentation/ui_contract_test.odin`) reads the package's own sources and fails on
`rl.DrawRectangle` / `Rec` / `V` / `Pro` / `Lines` / `LinesEx` outside a named exemption list.

> **The exemption list is not the fix.** Its entries are the world painters, the tools, and the
> voyage screens still on the superseded navy ramp — each one a claim that those rectangles are
> *not chrome*. **A screen you are porting never earns an entry.** If the check names your file,
> the answer is a widget or step 1, never a line in `EXEMPT`.

One known edge, so you do not mistake it for permission: the gradient calls are deliberately
absent from the check, because they draw the vignette, the title scrim and the sky. A *panel* built
out of a gradient slips through. Don't.

## 3. The geometry goes in one layout block, beside its shipped literal

Not scattered as constants. Three names, and `presentation/offer_shop.odin` is the worked example:

```odin
Offer_Shop_Layout :: struct { col_x, col_w, col_y0, card_h, pitch: f32, /* … */ }
OFFER_SHOP_LAYOUT :: Offer_Shop_Layout { col_x = 820, col_w = 392, /* … */ }
offer_shop_layout := OFFER_SHOP_LAYOUT   // what the screen draws from; only the workbench moves it
```

**What does *not* go in the block is what the widgets own.** Border weight, the cast shadow's
throw and the type sizes were fields on that struct until the screen drew with widgets, and are now
a frame, an `Ui_Elevation` and a `Ui_Level`. *A size a screen can drag is a size a screen can
invent, and an invented size is an atlas nobody baked.*

This is also what makes the screen steerable in stage 4 — the last mile of tuning then costs a drag
rather than a rebuild. Adding it to the workbench is two edits (`presentation/screen_workbench.odin`):
the layout block above, and a `workbench_screens` row naming the capture shot, a knob proc, and the
constant `C` replaces. A test asserts every field has exactly one knob, that each knob's range
contains its shipped value, and that the emit names them all.

**Do not hand-tune the numbers in the block.** Land them roughly, then hand the screen to
`--workbench` and a human. Guessing a number, rebuilding and shooting it is the loop that stage
exists to delete.

## 4. Split composition from polling

The screen needs a `draw_X_screen(state)` that the blocking loop calls **and** capture calls.
Compose buttons inside a poll loop and `--capture` photographs the screen with its buttons missing.
`draw_chart_table` and `draw_option_screen` are the worked examples.

If the screen wants a new capture state — a hover, a drag mid-flight — that is a row in
`capture_shots` with a `stage` and a `frame`, **never** a hard-coded cursor edited in, shot and
reverted.

## 5. Verify, and name what else you moved

```bash
odin build cmd/game
odin test presentation                                  # the contract test lives here
odin run cmd/game -- --shot <name>                      # then OPEN it
python scripts/shot.py diff main:<NN>-<name> <NN>-<name>
python scripts/shot.py check                            # what else did the port move?
```

`check` is the step a port most often skips and most needs: porting a screen through shared chrome
moves screens you did not open. The report is names — a port you expected to touch one screen and
that names nine **is the finding**. Then `diff prev:<shot> <shot>` to see how, look, and only then
`accept`.

**A shot you did not open is not verification.** Three pixels cannot tell you the spacing reads or
that the thing is simply ugly.

## What this skill does not do

- **It does not choose.** If there is no picked mockup, you are in `direct-a-screen`, and a human
  picks.
- **It does not tune.** Rough numbers here; `--workbench <screen>` and a human eye there. That
  split is what keeps tuning out of the model's context entirely.
- **It does not re-colour the voyage screens.** `fight`, `trade`, `encounter_frame` and `view` are
  on the superseded navy ramp and named in the contract's exemption list with their reason. That
  migration is the style guide's deferred follow-on, not something a port smuggles in.
