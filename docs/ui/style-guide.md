# UI style guide

The written art direction for this game's UI. Every UI session reads this before drawing anything.

Its job is to make "good" a **fixed target** rather than a per-session guess. Where it gives a number, use
that number. Where it gives a principle, apply the principle. Where it is silent, it is silent on purpose —
see [What this guide does not cover](#what-this-guide-does-not-cover).

Written for [Write the style guide](https://github.com/ssalter21/fantasy-ship-game/issues/280), on the
`effort:ui-capability` map ([#275](https://github.com/ssalter21/fantasy-ship-game/issues/275)).

> **This is a clean-slate rewrite.** It supersedes an earlier navy direction — "one palette, and it is a depth
> ramp," grounded on the near-black `#081127` — which read as clinical and cold and drifted away from the
> reference set's actual brightness. The target now is **bright, high-contrast, saturated 16-bit**, derived from
> the daylight images the old guide had buried. The shipped `COLOUR_*` constants still hold the old navy values;
> re-colouring them is the follow-on and is out of scope here (see
> [What this guide does not cover](#what-this-guide-does-not-cover)).

## Craft, not art

"Good" here means **shapes, a real typeface, a deliberate palette, spacing, hierarchy, and framing**. It does
not mean illustration. The UI reads as programmer art today because of raylib's stock font, raylib's stock
named colours (`LIGHTGRAY` / `BEIGE` / `MAROON`), and no hierarchy — not because art is missing. Every rule
below is reachable with raylib primitives (`DrawRectangleRec`, `DrawRectangleLinesEx`, `DrawTextEx`,
`DrawTriangle`, `DrawPoly`) and no new renderer.

## Where this came from

`docs/ui/references/` holds nine scenes gathered in
[#276](https://github.com/ssalter21/fantasy-ship-game/issues/276), plus one mock. They are not equal, and which
one leads is the whole difference between this guide and its predecessor. Read
`docs/ui/references/README.md` before them.

- **`style/island-tropical.jpg` is the keystone.** It is the clearest statement of the target: a saturated
  turquoise sea, warm tan cliffs, vivid layered greens, purple-white clouds. Every colour is turned *up*. The
  palette below is sampled from it, with **`style/menu-port-tropical.jpg`** and **`menu/treasure-map.jpg`** as
  supporting witnesses (the port for its bright daylight sea, the map for its parchment-and-sand world).
- **`menu/menu-ui-mock.png` is a layout reference only.** It is the one image that *is* a UI, so it still fixes
  **hierarchy and proportion** — but it is a *navy* mock, and it no longer sets colour. Take its stack, its
  centred title, its caret-and-scrim hover; leave its palette.
- **`style/ship-night.jpg` and `style/ship-battle.jpg` are accent witnesses only.** They show a warm point
  punching against a cold field — the amber relationship — and nothing else. They are night scenes; do not read
  a ground colour out of them.
- **`style/colour-palette.webp` stays demoted.** A dusk mountain valley, not a sea. Do not derive palette from
  it.

## The palette

**There is one palette. It is a flat, high-contrast roster, and everything draws from it** — the chrome, the
world, the chart, the map. Not a ramp: a fixed set of named swatches, and no screen may reach outside it. That
shared roster is the whole anti-clash guarantee. The chrome cannot fight the world because they are painted from
the same tin.

### The contrast engine is warm-versus-cool

The brightness in `island-tropical` is not a dark ground with a bright accent. It is **saturated cyan sea
clashing against warm sand and white foam**, with vivid green between them. That warm-vs-cool clash is the
mechanism — carry it into every screen. High contrast here means a *hue* clash at *high* value, not a value
drop into shadow.

### Two grounds: the sea is the world, parchment is where words live

The sea is bright and saturated, which is glorious behind a ship and hostile behind a paragraph. So the roster
carries **two grounds**, and the rule for which is simple:

- **The sea `#1FA9D0` is the backdrop** — the world, the map's water, the space a ship sails. Break it up with
  islands, sky, and foam; never paint a flat wall of it edge to edge.
- **Parchment `#EBD9A6` is the ground for text** — menus, panels, stat blocks, and the run-map. Dark ink on
  warm parchment is the high-contrast, legible, unmistakably-pirate surface the words sit on.

This is the reference set resolving itself: `island-tropical` is the sea, `treasure-map` is the parchment, and
a pirate UI is charts drawn on paper over open water.

### The roster

These are law. Values are starting points, tuned in-engine by eye — but the *relationships* (which is brighter,
which is warmer, which is scarce) are not up for renegotiation.

**Cool — the sea and its field**

| Role | Hex | RGB | Is |
| --- | --- | --- | --- |
| **Sea — field** | `#1FA9D0` | 31, 169, 208 | The sea, and the world backdrop. Replaces `RAYWHITE`/navy `COLOUR_DEEP`. |
| **Sea — bright** | `#2CC3DE` | 44, 195, 222 | The loud turquoise. Near-surface water, highlights. |
| **Shallow** | `#63E2EC` | 99, 226, 236 | Brightest cool. The halo where water meets land; the eye's rest point. |
| **Sea — deep** | `#1786BC` | 23, 134, 188 | Distance, deepest water, and interactive borders on parchment. |
| **Foam** | `#F2FBFB` | 242, 251, 251 | Whitecaps, dividers, the brightest thing allowed. |

**Sky** (for screens that show it)

| Role | Hex | RGB |
| --- | --- | --- |
| Sky — high | `#3F79C0` | 63, 121, 192 |
| Sky | `#5A93D2` | 90, 147, 210 |
| Horizon haze | `#8FBCE8` | 143, 188, 232 |
| Cloud | `#EEF1F8` | 238, 241, 248 |
| Cloud shadow | `#B7BCE0` | 183, 188, 224 |

**Warm neutral — land and parchment** (all *desaturated* warm; see [the saturation rule](#the-saturation-rule))

| Role | Hex | RGB | Is |
| --- | --- | --- | --- |
| **Parchment** | `#EBD9A6` | 235, 217, 166 | The ground for text: panels, menus, the map. |
| **Sand** | `#D2A968` | 210, 169, 104 | Land body, panel shade, dividers on parchment. |
| **Cliff** | `#B98A50` | 185, 138, 80 | Deeper sand; borders; the shadowed edge of land. |
| **Rock** | `#7E5C3A` | 126, 92, 58 | Shadow under land; the darkest warm. |
| **Trunk** | `#875F38` | 135, 95, 56 | Palms, timber. |

**Foliage** (vivid — this is where the old guide was most muted)

| Role | Hex | RGB |
| --- | --- | --- |
| Green — highlight | `#9BDE57` | 155, 222, 87 |
| Green — light | `#57C94D` | 87, 201, 77 |
| Green | `#2FA23E` | 47, 162, 62 |
| Green — deep | `#1B6A2B` | 27, 106, 43 |

**Accents**

| Role | Hex | RGB | Notes |
| --- | --- | --- | --- |
| **Amber — action** | `#FFB020` | 255, 176, 32 | **Reserved.** The one thing you can act on. See [the amber rule](#the-amber-rule). |
| **Ink on amber** | `#40260A` | 64, 38, 10 | The only text colour that goes on amber. |
| **Coral-red — reserved** | `#E1552B` | 225, 85, 43 | Held back: the chart's X-mark now, danger/damage later. Scarce by law. |

**Text tones** (hierarchy is carried by colour — see [Hierarchy](#hierarchy))

| Role | Hex | RGB | Notes |
| --- | --- | --- | --- |
| **Ink — primary** | `#12333F` | 18, 51, 63 | Titles and body on parchment. Deep teal, not black. |
| **Ink — muted** | `#4C7385` | 76, 115, 133 | Secondary and help text on parchment. |
| **Faded ink — recessive** | `#9C8A63` | 156, 138, 99 | Present, read last (version stamp). Faded map-ink. |
| **Cream** | `#F3E6C4` | 243, 230, 196 | The rare light heading placed *over* the sea, not on parchment. |

### The saturation rule

**Neutral warm is desaturated. Saturated warm is amber, and amber alone.**

This is the rule that lets the world be sandy without stealing the button. Parchment, sand, cliff, and rock are
all *low-saturation* warm; amber `#FFB020` is *high-saturation* warm. The eye separates them by saturation, so a
whole parchment panel can sit under a single amber control and the amber still reads as "act here." A second
saturated warm anywhere on screen breaks the rule — that is what coral-red's reservation protects.

Two rules fall out of the roster:

- **Never `RAYWHITE`, `LIGHTGRAY`, `BEIGE`, `MAROON`, `SKYBLUE`, `GRAY`, or `WHITE` again.** Every stock raylib
  named colour has a replacement above. The stock palette is the single largest programmer-art signal in the
  current build.
- **Text colour is hierarchy.** Rank by colour first, size second — there are only two type sizes (below).

### The amber rule

`#FFB020` means **"this is the thing you can act on right now."** Nothing else may use it.

It only works because it is scarce. In `style/ship-night.jpg` — the image that drives it — the warm points
occupy a tiny fraction of a large cold field, and that ratio *is* the effect. An amber that appears three times
on a screen means nothing. One amber per screen is the target; two is a smell; three is a bug.

Concretely: the actionable control is amber-filled with `#40260A` ink. Everything else interactive is
outlined in `#1786BC` (or steel, on a dark ground) with a matching label over a translucent ground.

**Amber marks the default action, not the pointer.** This game is mouse-driven, so *any* control can be hovered
— and amber-on-hover would put two ambers on screen the moment you hover a non-default control. The resolution
(found building the Chart Table, [#281](https://github.com/ssalter21/fantasy-ship-game/issues/281)):

- **Amber is assigned, not tracked.** The screen's default action is amber-filled and stays amber whatever the
  mouse does. A screen with no default action has no amber.
- **Hover is carried by the caret and the scrim** — the `▶` moves to the hovered control, and its translucent
  ground lifts. Both read clearly and neither spends amber.

### Coral-red is reserved

`#E1552B` is held back on purpose. Today it is **the chart's X-mark** — the one warm point on the map. Later it
is **danger and damage**. It is never the "go" colour (that is amber's job, and red-as-go would fight the Fight
stage), and it never appears twice on a screen. Its scarcity is its meaning, exactly like amber's.

### The map is parchment

The run-map is being rebuilt as **an actual chart — a piece of parchment**, not a tinted sea. When that lands,
the map's ground is `#EBD9A6`, its water is drawn *on* the paper in the sea tones, its land is sand and
foliage, and its markers are re-derived against parchment. `menu/treasure-map.jpg` is the reference for that
surface — it is promoted from "form and framing only" to a genuine palette source for the map.

Until the rebuild, keep the map's colours light:

- **Encounter category (`stage_tint`) — principle only.** The mechanism survives any palette and is worth not
  re-litigating: **category is hue, state is brightness, and only the *current* node/chip goes amber.** That is
  what keeps "amber means act" alive on a busy map. The five category hues themselves are *not* pinned here —
  they get re-derived against the parchment ground in the map rebuild. Do not spend effort tuning them against
  the current navy field.

### `zone_tint` — the three sea stops

`zone_tint` carries the sea's own tones for the three water zones — `Coastal`, `Open_Sea`, `Deep`. Drawn from
the roster's cool column (bright shallow → sea → sea-deep), they are **ambient**: a background band and an
unrevealed encounter's generic marker. If a zone tint is ever the brightest thing on screen, it is being
misused.

One limit is recorded rather than hidden, and it is a *code* fact, out of this pass's scope: `draw_scene`
clears the voyage canvas to a light ground and the zone band draws at low alpha, so an untuned tint washes out.
The values survive the wash only when lifted, and they land true when the canvas ground itself becomes a sea
tone — i.e. when the voyage screens are re-coloured. That is the follow-on, not this guide.

### The chart's own tones

The Chart Table draws a chart because [#278](https://github.com/ssalter21/fantasy-ship-game/issues/278) settled
that the screen *is* a chart with buttons over it. It is **drawn from the roster with raylib primitives, not
sourced as an image** — that costs no bytes against ADR-0009's self-contained exe, raises no licence question,
and cannot clash with the chrome because both draw from the one roster.

Its parts map straight onto the roster: **water** in the sea tones, **land** in sand and cliff, **foliage** in
the greens, **grid** in `#1786BC` at low alpha, and the **X-mark** in coral-red. Two rules came out of drawing
it, both the kind that produce a screen that looks broken rather than wrong:

- **The world must never outshine the chrome.** Peak luminance of any chart element must sit below the title's.
  The chart is the ground; the buttons are the figure.
- **Alpha composites per draw, not per figure — so a translucent figure cannot have a brightness.** Overlapping
  translucent primitives stack toward opaque. If a shape is built from overlapping primitives (a compass rose,
  say), give it an **opaque dim tone**; it is the only way its peak is predictable from the constant.

And one trap that a compass rose walks into: **`DrawTriangle` culls clockwise winding, drawing nothing at
all.** A rose wound the wrong way renders its hub and none of its spokes — a silent, total no-op. Wind
counter-clockwise.

## Type

**Pixelify Sans**, SIL Open Font License 1.1.

- Source: <https://github.com/google/fonts/tree/main/ofl/pixelifysans>. Ships in the repo at
  `assets/fonts/PixelifySans.ttf`.
- Licence verified by reading the `OFL.txt` in the archive — not a tag on a download page. OFL 1.1 permits
  embedding and redistribution in a commercial binary.
- **Embed it via Odin `#load`.** [ADR-0009 (playtest distribution)](../adr/0009-playtest-distribution.md)
  commits to a "native, self-contained Windows `game.exe`"; a font shipped as a sidecar file breaks that. Load
  with `rl.LoadFontFromMemory`. (Note: two ADRs share the number 0009 — the relevant one is *playtest
  distribution*, not *node graph*.)

### The size scale

**Two sizes. That is the whole scale.**

| Size | Role |
| --- | --- |
| **40px** | The Chart Table title. Display only. |
| **20px** | Everything else. |

This is measured, not minimalist. Pixelify Sans is a pixel font on a 20px design grid, and it does not render
cleanly off it:

| Size | Antialiased pixels | Verdict |
| --- | --- | --- |
| 10px | **78%** | mush — unusable |
| **20px** | **2%** | pixel-perfect |
| 30px | 12% | acceptable |
| **40px** | 13% | good |
| 60px | 10% | good, if a screen ever needs it |

**There is no clean size below 20px.** Any 12/14/16 call sites must grow. That is a real cost of a pixel font —
Silkscreen bottoms out at 16px the same way — and it is why hierarchy here is carried by **colour**, which is
free, rather than by size, which is not.

### A size is a font, not a parameter

The scale is **two `rl.Font`s, not one font drawn at two sizes.** One `rl.Font` is one glyph atlas rasterized
at one size: ask `DrawTextEx` for 20px from an atlas baked at 40 and it resamples, giving up exactly the
pixel-exactness the table was measured to buy. Bake each size once and keep both (`cmd/game/ui.odin`'s
`ui_font_title` / `ui_font_body`).

Two things that go with it, both mandatory and neither obvious:

- **Set the texture filter to `POINT`.** raylib defaults a font atlas to bilinear, which softens it on upload
  and silently undoes the whole antialiasing measurement. `rl.SetTextureFilter(font.texture, .POINT)`
  immediately after loading.
- **The default codepoint set is ASCII 32–126.** `LoadFontFromMemory` with a nil codepoint list bakes that and
  no more, so `·` (U+00B7) and `—` (U+2014) are **not** in the atlas by default despite the face carrying them.
  Retiring the em-dash workaround needs an explicit codepoint list, not just the font.

### No bold, ever

`PixelifySans[wght].ttf` is a variable font (`wght` 400–700), Google publishes **no static instances**, and
raylib's stb_truetype **ignores variable axes entirely** — it renders the default (400) instance. A guide that
said "use the Bold weight" would be unfollowable, which is the exact failure this guide exists to prevent.

If a bold is ever genuinely needed it must be **pre-instanced at build time** with `fonttools varLib.instancer`
and embedded as a second blob. Do not reach for it first: the reference set carries no weight contrast, only
size and colour.

### Rejected typefaces, and why

Recorded so they are not rediscovered and re-litigated:

| Face | Rejected because |
| --- | --- |
| **Pixel Pirate** | **Licence.** At least three distinct fonts share the name (one free on dafont, one *sold commercially* by FontBros); the "100% Free" tag is author-typed, not a licence file; it is described as derived from the *Pirates of the Caribbean* logo type; and this game has a public itch.io page, so redistribution rights are real. `docs/ui/references/typeface.htm` was saved to settle this and captured a Google redirect notice instead — it contains no font data. **Do not adopt without a licence document.** |
| **Press Start 2P** | **Measured overflow.** At 16px it is ~16px/char: `Hull 20/20  DUR 3  SPD 2` renders 384px into a 348px ship panel, and `Reallocate a fitting` renders 320px into a 220px button. It does not fit this game. |
| **VT323** | **Never crisp** — 46–98% antialiased at every size 8–34. A curvy face; reads as a DOS terminal rather than 16-bit. |
| **Micro5**, **Jersey10** | Illegible mush at body sizes; 12 printable Latin-1 gaps each (`±`, `²`, `³`, `µ`). |
| **Silkscreen** | **Runner-up, and a close one.** Crisper than Pixelify (10% AA at 32px), static, complete Latin-1, 31KB. Rejected because it reads **all-caps**, and this game has prose — `battle_event_text`, `fitting_summary_lines`, `condition_intent`. Caps cannot carry prose. Revisit only if the restyle finds Pixelify too soft, and know that changing face later means redoing every screen. |

### One thing the font fixes for free

raylib's built-in font carries only codepoints 32–255, so an em-dash renders as `?` — which is why some code
says `"none"` instead. **Pixelify Sans carries U+2014.** Once it is embedded (with an explicit codepoint list),
that workaround can go.

## Glyphs are shapes, not text

The mock draws `▶` `◆` `↑` `↓` `⏎`. **Draw these with raylib primitives, never as text.**

This is measured, not stylistic. Of every candidate face examined, **none** carries `◆` (U+25C6) or `⏎`
(U+23CE), and the only one carrying `▶ ↑ ↓` is Press Start 2P — which is rejected on width. Depending on a font
for these glyphs means depending on a font that does not exist.

| Mark | Draw with |
| --- | --- |
| `▶` selection caret | `rl.DrawTriangle` |
| `◆` diamond bullet | `rl.DrawPoly` with 4 sides, or a rotated `DrawRectanglePro` |
| `↑` `↓` arrows | `rl.DrawTriangle` + `rl.DrawRectangleRec` |

Anything in printable Latin-1 (32–126, 160–255) is safe as text: `·` (U+00B7) and `—` (U+2014) both render.
Above U+00FF, assume a shape.

## Spacing, hierarchy, framing

### Hierarchy

Words live on parchment, so the primary hierarchy is **dark ink on a warm ground**, ranked by colour:

1. **Title / heading** — `#12333F` ink at 40px on parchment (or `#F3E6C4` cream if placed over the sea).
   Biggest thing on screen.
2. **The action** — amber `#FFB020` fill with `#40260A` ink. The only saturated warm mass.
3. **Other controls** — `#1786BC` border and label over a translucent ground. Present, clearly clickable,
   visibly not the default.
4. **Body and hints** — muted ink `#4C7385`, 20px.
5. **The version stamp** — faded ink `#9C8A63`. Findable, never read first.

There is no bold, no second font, and only two sizes. **Colour carries the hierarchy.** If a screen needs a new
level, reach for a tone from the roster, not a new size.

**The version stamp is shared chrome, and it forks.** A styled screen draws its own stamp; the unstyled voyage
screens still draw the stock-`GRAY`, 12px one. The two converge when the restyle lands. Expect the same fork for
anything else shared between a styled screen and an unstyled one.

### Framing

The framing signal is **the torn parchment edge**, not a dark vignette. The old navy guide darkened the screen
to near-black at its edges; that reintroduces exactly the cold, clinical frame this rewrite is removing. Frame
with paper: a sand-and-cliff torn border, the treasure-map's own device.

For panels, framing is a **2px border in the tone that states the panel's role** — `#1786BC` for interactive,
`#B98A50` cliff for inert — over a translucent ground, not a filled box. Let the world read through unselected
panels; that translucency is what makes chrome sit *on* a world rather than cover it. Starting alpha for a
scrim: `rl.Fade(ground, 0.55)`, tuned by eye.

### Proportions

The mock's layout **cannot be copied** — its aspect is 1.806 against the window's 1.463. What transfers is its
proportions. Measured from the mock and scaled to 1024×700, as a **starting point** for the Chart Table, not a
spec:

| Element | In the mock | At 1024×700 |
| --- | --- | --- |
| Button width | 494px = 34.8% of width | **~356px** |
| Button height | 51px = 6.5% of height | **~45px** |
| Button pitch | 72px = 9.1% of height | **~64px** (≈19px gap) |
| Title centre | 16.4% of height | **y ≈ 115** |
| Hint row | 93.5% of height | **y ≈ 655** |
| Horizontal | title and buttons both centred | centred |

The button stack is centred horizontally but its **labels are left-aligned inside** each row, with the caret in
the left margin. That asymmetry is deliberate: a centred label in a centred box has no anchor for the eye to run
down. Give pitch, not a starting `y` — centre the stack in the space the title leaves and record the number you
chose.

## Rules for raylib

- **`rl.DrawTextEx`, not `rl.DrawText`.** `DrawText` uses the built-in font. Every text call must pass the
  loaded font. This is the single change that retires most of the programmer-art read.
- `DrawTextEx` takes a **`spacing`** parameter. The mock's title and subtitle are visibly letterspaced. Pixelify
  at 40px renders a repo-length title at ~385px unspaced; close the gap to the mock's ~441px-at-1024 with
  `spacing` ≈ 8, not with a bigger size.
- **Split composition from polling.** Any new screen needs a `draw_X_screen(state)` that the loop calls *and*
  capture calls. Compose buttons inside a poll loop and `--capture` photographs the screen with its buttons
  missing.
- Text reaches drawing as `fmt.ctprintf` temp-allocator strings, freed by the per-frame
  `free_all(context.temp_allocator)`. Nothing here changes that.

## What this guide does not cover

- **A layout system.** Deliberately not designed. A centred button stack is a pure function of a few constants,
  hit-tested and drawn from one call — the idiom `option_screen_boxes` already established. The only helper
  wanted and missing is a measure-then-place text centring helper. The proportions above are a starting point,
  not a grid.
- **Re-colouring the shipped screens.** The `COLOUR_*` constants (`COLOUR_DEEP`, `COLOUR_GROUND`,
  `COLOUR_STEEL`, `COLOUR_CREAM`, `COLOUR_CYAN`, …) still hold the old navy values, and the built screens
  (Chart Table, Fight, Trade, the Build surface) still draw them. Migrating them to this roster — and growing
  every sub-20px call site — is the follow-on UI work this guide exists to feed. This guide states the target;
  it does not create the migration.
- **Art assets.** Illustration, ship art, node icons. Out of scope, with one carve-out: a *sourced* Chart Table
  background image ([#284](https://github.com/ssalter21/fantasy-ship-game/issues/284)), which would now be an
  improvement in **depiction**, not palette. The mock is **not** it, and its provenance is unrecorded.
- **The Chart Table's contents.** Settled by
  [#278](https://github.com/ssalter21/fantasy-ship-game/issues/278), not here.
