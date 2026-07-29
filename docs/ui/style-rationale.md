# UI style rationale

The **why** behind `style-guide.md`. Nothing here is a rule, and a session following the rules
never needs to open it.

The guide used to carry both at once, and that was the right call while the direction was being
argued out — it is why decisions here do not get re-litigated. But it made every session pay for
the argument in order to read the conclusion, and the argument is the larger half. So the two are
separated rather than one of them written worse: **`style-guide.md` is what to do, this is why**.

**Read this when you are about to change a rule**, or when a rule looks arbitrary and you want to
know what it cost to arrive at. Everything below was load-bearing evidence at the time it was
written, and none of it has been shortened in the move.

Where a rule now lives in code rather than in prose — the widgets enforce most of them
(`presentation/ui_widgets.odin`) — the guide points at the procedure and this file keeps the
reasoning that produced it.

---

## Where this came from

`docs/ui/references/` holds eight scenes gathered in
[#276](https://github.com/ssalter21/fantasy-ship-game/issues/276). They are not equal, and which
one leads is the whole difference between this guide and its predecessor. Read
`docs/ui/references/README.md` before them — it also records two images that fed this guide and have since
been **removed** from the repo (a navy UI mock and a parchment treasure-map), whose decisions are captured
below so the guide stands on its own without them.

- **`style/island-tropical.jpg` is the keystone.** It is the clearest statement of the target: a saturated
  turquoise sea, warm tan cliffs, vivid layered greens, purple-white clouds. Every colour is turned *up*. The
  palette below is sampled from it, with **`style/menu-port-tropical.jpg`** as a supporting witness for its
  bright daylight sea. The parchment-and-sand world had a second witness, a `treasure-map` reference now
  **removed** from the repo (recorded in the references README).
- **The layout came from a `menu-ui-mock.png`, since removed** — the one reference image that *was* a UI. It
  fixed **hierarchy and proportion** only; being a *navy* mock, it never set colour. Its stack, its centred
  title, and its caret-and-scrim hover are taken forward; its proportions are measured out under
  [Proportions](style-guide.md#proportions) below, so the guide no longer needs the image itself.
- **`style/ship-night.jpg` and `style/ship-battle.jpg` are retired.** They witnessed one thing — a small warm
  point punching against a large cold field — and that relationship was the amber accent, which this guide no
  longer carries. They are night scenes on a navy ground the palette has moved off; do not read colour of any
  kind out of them.
- **`style/colour-palette.webp` stays demoted.** A dusk mountain valley, not a sea. Do not derive palette from
  it.

### Never mix a warm into a cool to get a neutral

**`colour_mix` between opposite hues passes through grey. If a tone needs to be softer, take the alpha down
or the value down — do not walk it across the wheel.**

This is the roster's one booby trap, and it has now produced three separate bugs from three different
call sites, every one of them written as "warm it up a bit" or "haze it back a bit":

- The horizon glare was `mix(horizon haze, parchment, 0.5)` — blue into yellow, meant to read as tropical
  heat. It measured **6% saturation**: a neutral grey band straight across the middle of the frame, and the
  largest flat area on the screen.
- The submerged hull was lerped from lit copper toward the sea's turquoise. Every strake at mid-depth landed
  near the midpoint of that line and came out the same dead sage.
- The island strand was `mix(sand, glare, 0.5)`, to set the beach back into the distance. Same two hues, same
  grey.

The mix is not wrong because the ratio is wrong; it is wrong because the *path* runs through the middle of
the wheel. Halfway between two opposite hues is neutral by construction, and no ratio avoids it — moving the
ratio only moves where the grey lands.

What to reach for instead:

- **Softer, more distant, hazier → `rl.Fade`.** Let what is already behind it do the mixing optically. The
  tone keeps its own hue all the way down. This is the right answer for atmospheric perspective.
- **Darker or lighter → `colour_shade`.** It scales the channels and cannot cross the axis.
- **A genuine hue shift → go the short way round.** Mix from a neighbour rather than from the opposite: the
  glare warms a *cool* (`mix(shallow, parchment, 0.24)`), so it travels a quarter-turn instead of a half and
  keeps 41% saturation.
- **Light passing through something → absorb and scatter, not lerp.** Attenuate each channel by its own
  coefficient and add the medium's own lit colour back on top. Absorption only takes a channel down and
  scatter only puts a saturated tone in, so neither step can land on neutral. `hull_water` is the worked
  example.

**Scan it before you believe it.** All three of these looked plausible in source and read as "a bit flat" on
screen. What identified them was a saturation scan; nothing in the code says "grey".

### No bold — but now by choice, not by constraint

Under Pixelify Sans a bold was *unreachable*: it is a variable font (`wght` 400–700) with no static instances,
and raylib's stb_truetype ignores variable axes, rendering only the 400 default. Pixel Operator removes that
constraint — it ships a real **static** `PixelOperator-Bold.ttf`, which stb_truetype would rasterize fine as a
third embedded blob.

So the rule is now a design choice, not a technical one: **still no bold.** The mock used no weight contrast,
only size and colour, and adding a weight would be a new hierarchy signal this guide deliberately does without.
If one is ever genuinely wanted the path is now trivial (embed the Bold blob, bake a third `rl.Font`) — but
reach for a tone from the ramp first.

### Rejected typefaces, and why

Recorded so they are not rediscovered and re-litigated:

| Face | Rejected because |
| --- | --- |
| **Pixelify Sans** | **Adopted, then replaced — ambiguous digits.** It carried the whole first styling pass, but its numerals share the letterforms' skeletons (`0`/`O`, `1`/`l`/`I`, `5`/`S`), and this UI is almost entirely numbers. A rounded pixel face on a 20px grid; crisp there but soft above it. Replaced by Pixel Operator. Its removal is the reason the size scale moved 20/40 → 16/32. |
| **Pixel Pirate** | **Licence.** At least three distinct fonts share the name (one free on dafont, one *sold commercially* by FontBros); the "100% Free" tag is author-typed, not a licence file; it is described as derived from the *Pirates of the Caribbean* logo type; and this game has a public itch.io page, so redistribution rights are real. A saved capture meant to settle this caught only a Google redirect notice — no font data — and has since been deleted; the fontmeme page blocks automated fetches. **Do not adopt without a licence document.** |
| **Press Start 2P** | **Measured overflow.** At 16px it is ~16px/char: `Hull 20/20  DUR 3  SPD 2` renders 384px into a 348px ship panel, and `Reallocate a fitting` renders 320px into a 220px button. It does not fit this game. |
| **VT323** | **Never crisp** — 46–98% antialiased at every size 8–34. A curvy face; reads as a DOS terminal rather than 16-bit. |
| **Micro5**, **Jersey10** | Illegible mush at body sizes; 12 printable Latin-1 gaps each (`±`, `²`, `³`, `µ`). |
| **Silkscreen** | **The Pixelify runner-up.** Crisper than Pixelify (10% AA at 32px), static, complete Latin-1, 31KB. Rejected because it reads **all-caps**, and this game has prose — `battle_event_text`, `fitting_summary_lines`, `condition_intent`. Caps cannot carry prose. When Pixelify's soft digits later forced a second search, Pixel Operator — mixed-case *and* crisp — won over Silkscreen for the same all-caps reason. |
| **Pixel Operator Mono / Departure Mono** | **The digit-fix runners-up.** Both give unambiguous, tabular numerals (Departure has a dotted zero — the strongest `0≠O` signal of any candidate). Rejected for prose: monospace runs wide and clips the game's battle text, and Departure reads sci-fi terminal rather than 16-bit fantasy. Pixel Operator (proportional, same family as the Mono) fixes the digits without the width cost. |

### One thing the font fixes for free

raylib's built-in font carries only codepoints 32–255, so an em-dash renders as `?` — which is why some code
says `"none"` instead. **Pixel Operator carries U+2014** (and the game draws U+2014 ×261 and U+00B7 ×29, both
in the atlas). Once it is embedded, that workaround can go.

### How the size scale was measured

This is measured, not minimalist. Pixel Operator is a **native-16px** pixel font: it is pixel-perfect only on
integer multiples of its 16px em, and mush off that grid.

| Size | Antialiased pixels | Verdict |
| --- | --- | --- |
| 12px | **99%** | mush — unusable |
| **16px** | **0%** | pixel-perfect |
| 20px | **86%** | mush — the old scale's body size |
| 24px | 58% | bad |
| **32px** | **0%** | pixel-perfect |
| 40px | 40% | soft — the old scale's title size |
| **48px** | **0%** | pixel-perfect, if a screen ever needs a bigger title |

### Where the proportions came from

These proportions were **measured from the now-removed `menu-ui-mock.png`** (recorded in the references README)
and scaled to 1024×700 — a **starting point** for the Chart Table, not a spec. The mock's own layout could not
be copied regardless: its aspect was 1.806 against the window's 1.463, so only its proportions transfer.

### Why Pixel Operator, and not the first face

- **Why this face and not the first one.** The UI shipped on Pixelify Sans first; it was replaced because its
  digits share the letters' skeletons — `0`/`O`, `1`/`l`/`I`, `5`/`S` collide — and in a UI where almost
  everything the player weighs is a number, a numeral that does not announce itself as a numeral is the wrong
  face. Pixel Operator's digits are distinct (flagged `1`, narrow `0`), it is static, and it is CC0. See the
  rejected-typefaces table for the full record.
