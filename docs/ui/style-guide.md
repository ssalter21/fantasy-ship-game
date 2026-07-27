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
  [Proportions](#proportions) below, so the guide no longer needs the image itself.
- **`style/ship-night.jpg` and `style/ship-battle.jpg` are retired.** They witnessed one thing — a small warm
  point punching against a large cold field — and that relationship was the amber accent, which this guide no
  longer carries. They are night scenes on a navy ground the palette has moved off; do not read colour of any
  kind out of them.
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

This is the reference set resolving itself: `island-tropical` is the sea, the (since-removed) `treasure-map`
was the parchment, and a pirate UI is charts drawn on paper over open water.

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
| Cloud shadow | `#92B7E0` | 146, 183, 224 |

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
| **Coral-red — reserved** | `#E1552B` | 225, 85, 43 | Held back: the chart's X-mark now, danger/damage later. Scarce by law. See [the saturation rule](#the-saturation-rule). |

**Text tones** (hierarchy is carried by colour — see [Hierarchy](#hierarchy))

| Role | Hex | RGB | Notes |
| --- | --- | --- | --- |
| **Ink — primary** | `#12333F` | 18, 51, 63 | Titles and body on parchment. Deep teal, not black. |
| **Ink — muted** | `#4C7385` | 76, 115, 133 | Secondary and help text on parchment. |
| **Faded ink — recessive** | `#9C8A63` | 156, 138, 99 | Present, read last (version stamp). Faded map-ink. |
| **Cream** | `#F3E6C4` | 243, 230, 196 | The rare light heading placed *over* the sea, not on parchment. |

### The saturation rule

**Neutral warm is desaturated. The only *saturated* warm on the roster is coral-red, and it is reserved.**

This is the rule that lets the world be sandy without any of that sand reading as a signal. Parchment, sand,
cliff, rock, and trunk are all *low-saturation* warm; coral-red `#E1552B` is *high-saturation* warm. The eye
separates them by saturation, so a whole parchment panel can carry a single coral mark and the mark still
reads as the one loud thing on it. A second saturated warm anywhere on screen breaks the rule — that is what
coral-red's reservation protects, and it is why the guide will not spend a saturated warm on ordinary chrome.

Two rules fall out of the roster:

- **Never `RAYWHITE`, `LIGHTGRAY`, `BEIGE`, `MAROON`, `SKYBLUE`, `GRAY`, or `WHITE` again.** Every stock raylib
  named colour has a replacement above. The stock palette is the single largest programmer-art signal in the
  current build.
- **Text colour is hierarchy.** Rank by colour first, size second — there are only two type sizes (below).

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

### Controls do not have a signal colour

**No colour on the roster means "act here."** Every interactive control is drawn the same way: outlined in
`#1786BC` (or steel, on a dark ground) with a matching label over a translucent ground. A screen's default
action is distinguished by **where it sits and what it says**, not by a fill.

This retires the amber accent the earlier draft of this guide reserved for the actionable control. That accent
was inherited from the navy direction, and it was witnessed by two night scenes (`ship-night`, `ship-battle`)
whose whole point was a small warm point against a large cold field. The palette moved to a bright, saturated,
warm-and-cool daylight ground, and on that ground the warm point stopped being scarce and stopped being loud —
a saturated warm control sitting on parchment reads as more parchment. **Do not reintroduce it**, and do not
substitute another roster tone in its place: coral-red is reserved for danger and the chart's X, and spending
any other colour on "the default action" would just re-run the same argument in a new hue.

If a screen genuinely needs to single one control out, that is a layout and wording problem first. Raise it
before reaching for a colour.

### Hover is carried by the caret and the scrim

This game is mouse-driven, so *any* control can be hovered, and hover must never be confused with state that
was assigned to the control before the mouse arrived. The resolution (found building the Chart Table,
[#281](https://github.com/ssalter21/fantasy-ship-game/issues/281)) is that hover is carried by two things and
nothing else:

- The `▶` caret **moves to the hovered control**.
- The hovered control's **translucent ground lifts** — same tone, higher alpha.

Both read clearly, both are reversible the instant the mouse leaves, and neither changes a control's colour.

### Coral-red is reserved

`#E1552B` is held back on purpose. Today it is **the chart's X-mark** — the one warm point on the map. Later it
is **danger and damage**. It is never the "go" colour — red-as-go would fight the Fight stage — and it never
appears twice on a screen. Its scarcity is its meaning; it is the roster's only saturated warm, and spending it
anywhere else spends the whole signal.

### The map is parchment

The run-map is being rebuilt as **an actual chart — a piece of parchment**, not a tinted sea. When that lands,
the map's ground is `#EBD9A6`, its water is drawn *on* the paper in the sea tones, its land is sand and
foliage, and its markers are re-derived against parchment. The parchment surface was taken from a `treasure-map`
reference (since **removed** — see the references README); the sourced Chart Table background in
[#284](https://github.com/ssalter21/fantasy-ship-game/issues/284) and the parchment-chart build now carry it
forward.

Until the rebuild, keep the map's colours light:

- **Encounter category (`stage_tint`) — principle only.** The mechanism survives any palette and is worth not
  re-litigating: **category is hue, state is brightness.** The current node is not a third colour — it is
  marked by the ship sprite resting on it, which is what keeps a busy map from having to spend an accent on
  "you are here." The five category hues themselves are *not* pinned here — they get re-derived against the
  parchment ground in the map rebuild. Do not spend effort tuning them against the current navy field.

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

## The backdrop is drawn at one art resolution

The world behind the chrome — sky, sun, cloud, island, sea — is **16-bit-era pixel art: hard edges, flat blocks
of colour, no gradients, limited ramps per hue** (`docs/ui/references/README.md`, "Tonal register"). That is a
claim about **resolution** before it is one about colour, and it only holds if every mark in the backdrop
agrees on the same one. A smooth sky behind blocky clouds is two resolutions on one screen; the screen then
reads as pixel art with a vector field behind it, however good either half is on its own.

**One number fixes it: `BACKDROP_PIXEL` = 4 logical pixels to the art pixel** — a 311×175 art frame inside the
1244×700 logical one. Both axes divide exactly, so the lattice reaches all four edges with no part-pixel hiding
at two of them. `presentation/backdrop.odin` is the only place that implements the rule, so the decision is not
re-taken at a call site.

- **Nothing in the backdrop reaches the screen off the lattice.** Individual marks go through `backdrop_block`,
  which floors near edges, ceils far ones, and never lets a mark shrink below one art pixel — a wave crest
  rounded away to zero width is a hole in the water, not a finer detail. `backdrop_grade` and `backdrop_disc`
  lay their own rows out in whole cells from lattice-aligned edges instead, so they are on it by construction.
  Nothing else in the backdrop calls a raylib draw directly.
- **A grade is a short ramp of flat stops, never an interpolation.** `rl.DrawRectangleGradientV` interpolates
  per *screen* pixel — measured on a ship-screen shot, **49 distinct blues across 50 vertical samples of sky**.
  `backdrop_grade` paints `steps + 1` colours instead: a full sky column on that same screen now holds **9**,
  the 7 of its main ramp plus the glare's. Choose the count per grade rather than globally — a stop's visible
  height is its grade's span divided by the count, so the same count over a short span puts the steps close
  enough together to read as stripes.
- **The crossings between stops are dithered, not ruled.** A handful of flat bands across a whole sky is Mach
  banding. An ordered 4×4 threshold matrix indexed in *art pixels* carries each crossing, and the dither cell
  being one art pixel is precisely what makes the sky read at the resolution the sea's chop is already drawn at.
- **No circles.** `rl.DrawCircleV` is a polygon fan with a smooth edge — the one shape in the sky that snapping
  its arguments cannot fix. `backdrop_disc` fills it row by row on the lattice instead.
- **The lattice is coarse enough to change how a mark has to be *made*, not just where it lands.** A scatter of
  marks that reads as broken at sub-pixel heights closes up into a solid bar once every mark is a cell wide and
  starts on a cell boundary — the foam along the waterline is the worked example. On the lattice, "broken" has
  to be built in: walk the cells and leave some unlit, rather than scatter and trust the gaps.

**Verify under magnification, never at 1:1.** A dither cell is 4px; eyes cannot tell an on-lattice sea from an
off-lattice one at 1:1, and two sessions have now read banding into a clean gradient elsewhere on this screen.
Take a capture shot, then crop and scale `NEAREST` to see the cells, and count colours to settle the ramp:

```bash
python -c "
from PIL import Image
im = Image.open('docs/ui/shots/04-build.png').convert('RGB')
im.crop((880,450,1120,560)).resize((960,440), Image.NEAREST).save('/tmp/zoom.png')   # then open it
print(len({im.getpixel((30, y)) for y in range(0, 424)}), 'distinct colours down the sky')
"
```

Both halves matter. The count settles the ramp; only the crop shows whether the marks are on the lattice, and
neither judges whether the screen is any good — that is what looking is for.

**The rule governs the logical frame, and the blit softens all of it equally.** Fullscreen scales 1244×700 to
the monitor at a non-integer factor through a `BILINEAR` filter, so a presented art pixel is neither 4px nor
hard-edged. That does not reopen the decision: the filter reaches the ship's own edges and the cloud's alike, so
what it changes is the whole frame's softness, not the relationship between two halves of it. Measure the
lattice in the logical frame, where it is exact.

**The ship herself is not on this lattice.** She is lit 3D geometry drawn at full resolution, and the rule
governs the world she floats in, not her. Whether the two should agree is a separate question and a separate
decision.

## Type

**Pixel Operator**, Creative Commons Zero (CC0) 1.0 — public domain.

- Source: <https://www.dafont.com/pixel-operator.font> (by Jayvee Enaguas).
- Licence verified by reading the font's own `name` table (IDs 13/14 record the CC0 dedication) — not a tag
  someone typed on a download page. CC0 waives all rights: embedding and redistribution in a commercial binary
  need no attribution. `assets/fonts/PixelOperator-LICENSE.txt` keeps the credit for provenance, not obligation.
- **Embed it via Odin `#load`.** [ADR-0009 (playtest distribution)](../adr/0009-playtest-distribution.md)
  commits to a "native, self-contained Windows `game.exe`"; a font shipped as a sidecar file breaks that. Load
  with `rl.LoadFontFromMemory`. (Note: two ADRs share the number 0009 — the relevant one is *playtest
  distribution*, not *node graph*.)
- **Why this face and not the first one.** The UI shipped on Pixelify Sans first; it was replaced because its
  digits share the letters' skeletons — `0`/`O`, `1`/`l`/`I`, `5`/`S` collide — and in a UI where almost
  everything the player weighs is a number, a numeral that does not announce itself as a numeral is the wrong
  face. Pixel Operator's digits are distinct (flagged `1`, narrow `0`), it is static, and it is CC0. See the
  rejected-typefaces table for the full record.

### The size scale

**Two sizes. That is the whole scale.**

| Size | Role |
| --- | --- |
| **32px** | The Chart Table title. Display only. |
| **16px** | Everything else. |

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

**The clean sizes are 16, 32, 48 — nothing between.** The old 40/20 scale (measured for Pixelify Sans) landed
on two of Pixel Operator's *worst* sizes, so the swap moved the scale to 32/16, the two crisp sizes nearest the
old pair, preserving the exact 2:1 title:body ratio. Body dropped 20→16, which also eases the width budgets a
tight face fights (see Press Start 2P below). Hierarchy is still carried by **colour**, not size — but that is
now the house style, not, as it was under Pixelify, a workaround for a face with no clean size below 20px. 16px
*is* clean; colour still carries the levels because two sizes is the whole scale and always was.

### A size is a font, not a parameter

The scale is **two `rl.Font`s, not one font drawn at two sizes.** One `rl.Font` is one glyph atlas rasterized
at one size: ask `DrawTextEx` for 16px from an atlas baked at 32 and it resamples, giving up exactly the
pixel-exactness the table was measured to buy. Bake each size once and keep both (`presentation/ui.odin`'s
`ui_font_title` / `ui_font_body`).

Two things that go with it, both mandatory and neither obvious:

- **Set the texture filter to `POINT`.** raylib defaults a font atlas to bilinear, which softens it on upload
  and silently undoes the whole antialiasing measurement. `rl.SetTextureFilter(font.texture, .POINT)`
  immediately after loading.
- **The default codepoint set is ASCII 32–126.** `LoadFontFromMemory` with a nil codepoint list bakes that and
  no more, so `·` (U+00B7) and `—` (U+2014) are **not** in the atlas by default despite the face carrying them.
  Retiring the em-dash workaround needs an explicit codepoint list, not just the font.

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

### What Pixel Operator does *not* carry

Measured against the game's actual drawn strings, nothing that matters — but recorded so it is not
rediscovered. It lacks `→` (U+2192), exactly as Pixelify did; the Shop's cargo projection already draws ASCII
`->`, and the game's other `→` uses are all in **code comments**, never rendered. It also has 12 printable
Latin-1 gaps (`¤ § ª ­ ¯ ² ³ ¹ º ¼ ½ ¾`) — none of which the game draws. If a future string needs one of these,
check the atlas before assuming it is there.

## Glyphs are shapes, not text

The mock drew `▶` `◆` `↑` `↓` `⏎`. **Draw these with raylib primitives, never as text.**

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

1. **Title / heading** — `#12333F` ink at 32px on parchment (or `#F3E6C4` cream if placed over the sea).
   Biggest thing on screen.
2. **Controls** — `#1786BC` border and label over a translucent ground. Present, clearly clickable. All of
   them look alike: [no colour marks the default action](#controls-do-not-have-a-signal-colour).
3. **Body and hints** — muted ink `#4C7385`, 16px.
4. **The version stamp** — faded ink `#9C8A63`. Findable, never read first.

There is no bold, no second font, and only two sizes. **Colour carries the hierarchy.** If a screen needs a new
level, reach for a tone from the roster, not a new size.

**The version stamp is shared chrome, and it forks.** A styled screen draws its own stamp; the unstyled voyage
screens still draw the stock-`GRAY`, 12px one. The two converge when the restyle lands. Expect the same fork for
anything else shared between a styled screen and an unstyled one.

### Framing

The framing signal is **the torn parchment edge**, not a dark vignette. The old navy guide darkened the screen
to near-black at its edges; that reintroduces exactly the cold, clinical frame this rewrite is removing. Frame
with paper: a sand-and-cliff torn border — the framing device of a treasure map.

For panels, framing is a **2px border in the tone that states the panel's role** — `#1786BC` for interactive,
`#B98A50` cliff for inert — over a translucent ground, not a filled box. Let the world read through unselected
panels; that translucency is what makes chrome sit *on* a world rather than cover it. Starting alpha for a
scrim: `rl.Fade(ground, 0.55)`, tuned by eye.

### Proportions

These proportions were **measured from the now-removed `menu-ui-mock.png`** (recorded in the references README)
and scaled to 1024×700 — a **starting point** for the Chart Table, not a spec. The mock's own layout could not
be copied regardless: its aspect was 1.806 against the window's 1.463, so only its proportions transfer.

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
- `DrawTextEx` takes a **`spacing`** parameter. The mock's title and subtitle were visibly letterspaced; that
  is where it comes from. Pixel Operator at 32px renders the repo-length title well under the mock's width
  unspaced — close that gap with `spacing`, not with a bigger size. The mock's title was **~614px in the mock's
  own 1421px-wide space, i.e. ~43% of the window's width**, which is the figure that transfers: ~440px at 1024,
  reached at `spacing` = **13** (measured 432px; keep it an integer so glyphs stay on the pixel grid). Note the
  spacing is face- *and* size-specific: Pixelify at the old 40px hit the same ~43% at `spacing` ≈ 8, so a
  smaller face on a narrower em needs more — re-measure, never copy the old number.
- **Split composition from polling.** Any new screen needs a `draw_X_screen(state)` that the loop calls *and*
  capture calls. Compose buttons inside a poll loop and `--capture` photographs the screen with its buttons
  missing.
- Text reaches drawing as `fmt.ctprintf` temp-allocator strings, freed by the per-frame
  `free_all(context.temp_allocator)`. Nothing here changes that.

### In 3D, light the surface — never `DrawCube`

raylib's immediate-mode 3D carries **no lights**. `rl.DrawCube` paints all six faces one flat colour, so a box
drawn with it has no top, no shadowed side and no volume: it reads as a sticker, and a whole ship built from
them reads as stacked cardboard. That was the ship screen's first pass.

The fix is not a shader and not more outlines — it is **one flat shade per surface, off that surface's own
normal**, which `presentation/ship_paint.odin` supplies as `ship_quad` / `ship_quad_lit` / `ship_box`:

- **Every 3D surface goes through those, not through `DrawCube`.** A curve is then modelled by the light running
  across it, which is what lets a lofted hull read as a hull without a single drawn line.
- **Flat, not smooth.** One shade per facet. The art is blocky; a faceted hull keeps its strakes reading as
  planking, where interpolated normals would airbrush them away.
- **The palette does not change.** Every colour that reaches the screen is still a roster swatch — `colour_shade`
  multiplies it, so a lit face and a shadowed one are the same swatch under different light rather than two
  swatches kept in step by hand.
- **Wind quads both ways.** raylib culls back faces into *nothing*, and a cutaway is looked into from angles that
  see the inside of half of what is drawn. A wrongly-wound face is a silent hole, not a wrong colour.
- **Cloth is not timber.** Canvas is one thickness with the sun behind it as often as in front, so it is lit off
  `abs(dot)` and brighter for it (`ship_quad_cloth`). Sails shaded like planks come out grey and dead.
- **Light the side the eye is on.** Winding both ways means half of what is drawn is seen from behind, and the two
  sides of a surface do not face the same way. `ship_facing` flips the normal toward the camera before shading, so
  the underside of a deck is lit as an underside. Skip it and every horizontal surface is painted with the sun
  falling on its *top* — on a camera at the waterline, which sees the bottom of every deck and castle roof on the
  ship, that alone is the difference between a solid and a stack of flat lids.
- **Water goes over the light, not under it.** A submerged strake is lit first and washed toward the sea's colour
  second (`ship_lit` → `hull_water` → `ship_quad_flat`). Tinting the timber and *then* shading the result down
  turns her copper into a dark olive wedge beside bright turquoise, which reads as a hole in her side.

### A render texture loses alpha, and translucency pays for it

Fullscreen composes into a `RenderTexture` and blits it (`presentation/fullscreen.odin`). raylib's default blend
multiplies **alpha** by alpha as well as colour, so a target that starts opaque loses alpha wherever anything
translucent is drawn into it — `a=0.85` over `a=1` leaves `0.87`, and it compounds. Composite that against the
black letterbox and every soft mark on screen comes back up to a fifth darker than it was drawn.

The blit therefore takes the target's colour verbatim and discards its alpha, via
`rlgl.SetBlendFactorsSeparate(ONE, ZERO, ONE, ZERO, …)` under `BlendMode.CUSTOM_SEPARATE`. Two things follow:
**`--capture` cannot photograph this** — capture draws at logical size with no texture in the path — and a
windowed run cannot either. Sun haze, glitter, foam and highlight washes have to be checked in the **real
fullscreen window**, by measuring, not by eye.

## What this guide does not cover

- **A layout system.** Deliberately not designed. A centred button stack is a pure function of a few constants,
  hit-tested and drawn from one call — the idiom `option_screen_boxes` already established. The only helper
  wanted and missing is a measure-then-place text centring helper. The proportions above are a starting point,
  not a grid.
- **Re-colouring the shipped screens.** The `COLOUR_*` constants (`COLOUR_DEEP`, `COLOUR_GROUND`,
  `COLOUR_STEEL`, `COLOUR_CREAM`, `COLOUR_CYAN`, …) still hold the old navy values, and the built screens
  (Chart Table, Fight, Trade, the Build surface) still draw them. Migrating them to this roster — and rebaking
  every call site onto the 16/32 scale (16px being the crisp body size; the odd 12/14 have no clean equivalent
  and snap to 16) — is the follow-on UI work this guide exists to feed. This guide states the target; it does
  not create the migration.
- **Art assets.** Illustration, ship art, node icons. Out of scope, with one carve-out: a *sourced* Chart Table
  background image ([#284](https://github.com/ssalter21/fantasy-ship-game/issues/284)), which would now be an
  improvement in **depiction**, not palette. The removed mock was **not** it, and its provenance was never recorded.
- **The Chart Table's contents.** Settled by
  [#278](https://github.com/ssalter21/fantasy-ship-game/issues/278), not here.
