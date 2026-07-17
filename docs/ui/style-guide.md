# UI style guide

The written art direction for this game's UI. Every UI session reads this before drawing anything.

Its job is to make "good" a **fixed target** rather than a per-session guess. Where it gives a number, use
that number. Where it gives a principle, apply the principle. Where it is silent, it is silent on purpose —
see [What this guide does not cover](#what-this-guide-does-not-cover).

Written for [Write the style guide](https://github.com/ssalter21/fantasy-ship-game/issues/280), on the
`effort:ui-capability` map ([#275](https://github.com/ssalter21/fantasy-ship-game/issues/275)).

## Craft, not art

"Good" here means **shapes, a real typeface, a deliberate palette, spacing, hierarchy, and framing**. It does
not mean illustration. The UI reads as programmer art today because of raylib's stock font, raylib's stock
named colours (`LIGHTGRAY` / `BEIGE` / `MAROON`), and no hierarchy — not because art is missing. Every rule
below is reachable with raylib primitives (`DrawRectangleRec`, `DrawRectangleLinesEx`, `DrawTextEx`,
`DrawTriangle`, `DrawPoly`) and no new renderer.

## Where this came from, and what the mock is not

Two sources, and they are **not** equal.

`docs/ui/references/` holds nine scenes gathered in
[#276](https://github.com/ssalter21/fantasy-ship-game/issues/276). None of them contains a UI. They fix a
colour world and a 16-bit register; they say nothing about layout or type. Read
`docs/ui/references/README.md` before them.

`docs/ui/references/menu/menu-ui-mock.png` is different: it is the one reference that **is** a UI. It fixes
this guide's chrome palette and its hierarchy. But it is a **look reference, not a specification**, and three
things in it are actively wrong for this game:

- **Its menu items are not the Chart Table's.**
  [#278](https://github.com/ssalter21/fantasy-ship-game/issues/278) settled that the Chart Table holds a
  title, **Begin a voyage**, **Quit**, and nothing else, and that it is **stateless**. The mock's
  *Continue Voyage* (there is no save), *Crew & Codex* (meta-progression, out of scope), *Settings*, and its
  `SEED TIDEBORN-4417` line (seeding policy, out of scope) are illustrative only. Do not build them.
- **Its input model is not the game's.** The mock shows `↑↓ NAVIGATE  ⏎ SELECT`. Every menu in this game is
  mouse click-polling; nothing reads arrow keys.
- **Its aspect ratio is not the game's.** The mock is 1421×787 (**1.806**); the window is 1024×700
  (**1.463**). Its layout cannot be transplanted by scaling. Use its *proportions and hierarchy*, re-laid out.

One more property worth knowing before you sample it yourself: the mock is a **painting of a UI, not a
rendered one**. Its solid fills are exact and trustworthy, but its translucency is not internally consistent
(the same overlay lightens the island and tints the water by different amounts, which no single alpha
produces). Take its solids as law and its transparency as a target to match by eye.

## Palette

Three palettes, with a boundary that matters. Getting this wrong is the most likely way to misread this guide,
so the boundary is stated first:

| Palette | Governs | Source |
| --- | --- | --- |
| **Chrome** | Everything drawn *on top of* the world: panels, buttons, borders, text, states | the mock |
| **World** | The world being depicted: `zone_tint`'s ambient bands | `style/colour-palette.webp` |
| **Semantic** | `stage_tint` — meaning that must read on **both** | constrained by both, owned by neither |

### Chrome — sampled from the mock

Exact values, sampled from `menu-ui-mock.png`. These are law.

| Role | Hex | RGB | Notes |
| --- | --- | --- | --- |
| **Ground** | `#081127` | 8, 17, 39 | The dominant field. Replaces `RAYWHITE` as the canvas. |
| **Ground (water/mid)** | `#0A1C30` | 10, 28, 48 | One step up from ground; large calm areas. |
| **Vignette / edge** | `#050B18` | 5, 11, 24 | Darkest tone. Frames the screen; see [Framing](#framing). |
| **Amber — action** | `#F7A72B` | 247, 167, 43 | **Reserved.** See [The amber rule](#the-amber-rule). |
| **Ink on amber** | `#08122B` | 8, 18, 43 | The only text colour that goes on amber. Never cream. |
| **Steel — interactive** | `#8AA9D6` | 138, 169, 214 | Unselected controls: their border *and* their label. |
| **Cream — display** | `#E7D2A3` | 231, 210, 163 | Titles and headings only. Parchment, not white. |
| **Cyan — emphasis** | `#6FE0EC` | 111, 224, 236 | Subtitles, taglines, the eye's rest point. Sparingly. |
| **Cyan — dim** | `#57B5C3` | 87, 181, 195 | Hints and secondary help text. |
| **Blue — recessive** | `#3A5A82` | 58, 90, 130 | Text that must be present but never read first (version stamp). |

Two rules that fall out of this table:

- **Never `RAYWHITE`, `LIGHTGRAY`, `BEIGE`, `MAROON`, `SKYBLUE`, `GRAY`, or `WHITE` again.** Every stock
  raylib named colour has a replacement above. The stock palette is the single largest programmer-art signal
  in the current build.
- **Text colour is hierarchy.** There are six text tones here (ink, steel, cream, cyan, dim cyan, recessive
  blue) and only two type sizes (below). Rank by colour first, size second.

### The amber rule

`#F7A72B` means **"this is the thing you can act on right now."** Nothing else may use it.

This is the strongest signal in the whole reference set, and it only works because it is scarce. In
`style/ship-night.jpg` — the image that drives it — the warm points occupy a tiny fraction of a large cold
field, and that ratio *is* the effect. An amber that appears three times on a screen means nothing.

Concretely: the selected/hovered/actionable control is amber-filled with `#08122B` ink. Everything else
interactive is steel-bordered with a steel label on a translucent ground. One amber per screen is the target;
two is a smell; three is a bug.

**Amber marks the default action, not the pointer.** "The hovered control is amber" and "one amber per screen"
are the same rule only in the mock, where one caret moves and nothing else can be selected. This game is
mouse-driven, so *any* control can be hovered — and the moment you hover a non-default one, amber-on-hover puts
two ambers on screen and the rule eats itself. The resolution, found while building the Chart Table
([#281](https://github.com/ssalter21/fantasy-ship-game/issues/281)):

- **Amber is assigned, not tracked.** The screen's default action is amber-filled and stays amber whatever the
  mouse does. A screen with no default action has no amber.
- **Hover is carried by the caret and the scrim** — the `▶` moves to the hovered control, and its translucent
  ground lifts (`0.55` → `0.75`). Both read clearly and neither spends amber.

### World — sampled from `colour-palette.webp`

`zone_tint` (`view.odin:44`) colours the world, not the chrome, so it is drawn from the valley rather than the
mock. Values below are the quantized dominants of the named regions.

| Zone | Hex | RGB | Drawn from |
| --- | --- | --- | --- |
| `Coastal` | `#5AC3C7` | 90, 195, 199 | the valley's shallow water — bright turquoise |
| `Open_Sea` | `#1A78B1` | 26, 120, 177 | the valley's mid sky — saturated mid blue |
| `Deep` | `#0D4652` | 13, 70, 82 | the valley's deep water — dark teal |
| fallback (no zone) | `#22404A` | 34, 64, 74 | the valley's neutral shadow — slate |

Keep the existing usage: these are drawn as a background band at `Fade(..., 0.18)` (`view.odin:178`), and as
an unrevealed encounter's generic marker (`view.odin:132`). They are **ambient**. If a zone tint is ever the
brightest thing on screen, it is being misused.

Land green, where a screen needs it: `#5C8648` (92, 134, 72) mid, `#32583B` (50, 88, 59) shadow, `#B3CC5A`
(179, 204, 90) highlight. The mock's islands agree closely enough that these are safe on chart backgrounds.

### Semantic — `stage_tint`

`stage_tint` (`view.odin:81`) is the awkward one, and it is worth understanding why before changing it.

It is used in **two places on purpose**: the node markers on the map (world) and the chips in the encounter
strip (chrome). That is the property to protect — *a Battle node and a Battle chip must read as the same
thing*. So `stage_tint` cannot be assigned to either palette. It is a third category, legible against both.

It is also, today, a **five-hue rainbow** — `Fight`→`MAROON`, `Offer`→`LIME`, `Trade`→`ORANGE`,
`Shop`→`SKYBLUE`, `Reward`→`GOLD` — which directly contradicts [the amber rule](#the-amber-rule). Two of those
five are amber-adjacent. You cannot have Trade shouting orange and Reward shouting gold and still have amber
mean "look here."

**The resolution: category is hue, state is brightness.**

Each stage kind keeps a distinct hue, so the node/chip identity survives — but muted, pulled into the
palette's register, and never at full saturation:

| Stage kind | Label | Hex | RGB | Was |
| --- | --- | --- | --- | --- |
| `Fight` | Battle | `#A6485A` | 166, 72, 90 | `MAROON` |
| `Offer` | Items | `#6E9E5A` | 110, 158, 90 | `LIME` |
| `Trade` | Trade | `#B4794A` | 180, 121, 74 | `ORANGE` |
| `Shop` | Market / Port | `#4E8CB8` | 78, 140, 184 | `SKYBLUE` |
| `Reward` | Loot | `#C0A45E` | 192, 164, 94 | `GOLD` |
| fallback | — | `#4A5568` | 74, 85, 104 | `GRAY` |

Then **state** is what goes bright: the current stage's chip, and the node you are standing on, take
`#F7A72B`. Nothing else does.

The cost of this, stated so it is not rediscovered as a bug: **`Reward` loses gold as its identity** and
`Trade` loses orange. They become muted hues that only go bright when current. That is deliberate — it is the
price of amber meaning something, and it was weighed and accepted rather than overlooked.

## Type

**Pixelify Sans**, SIL Open Font License 1.1.

- Source: <https://github.com/google/fonts/tree/main/ofl/pixelifysans>
- Licence verified by reading the `OFL.txt` that ships in the archive — not a tag someone typed on a
  download page. OFL 1.1 permits embedding and redistribution in a commercial binary.
- **Embed it via Odin `#load`.** [ADR-0009 (playtest distribution)](../adr/0009-playtest-distribution.md)
  commits to a "native, self-contained Windows `game.exe`", proven against a real tester's machine; a font
  shipped as a sidecar file breaks that. Load with `rl.LoadFontFromMemory`.
  (Note: two ADRs share the number 0009 — the relevant one is *playtest distribution*, not *node graph*.)

### The size scale

**Two sizes. That is the whole scale.**

| Size | Role |
| --- | --- |
| **40px** | The Chart Table title. Display only. |
| **20px** | Everything else. |

This is not minimalism for its own sake — it is measured. Pixelify Sans is a pixel font on a 20px design
grid, and it does not render cleanly off it:

| Size | Antialiased pixels | Verdict |
| --- | --- | --- |
| 10px | **78%** | mush — unusable |
| **20px** | **2%** | pixel-perfect |
| 30px | 12% | acceptable |
| **40px** | 13% | good |
| 60px | 10% | good, if a screen ever needs it |

**There is no clean size below 20px.** The current 12/14/16 have no equivalent and must grow. That is a real
cost of adopting any pixel font — Silkscreen bottoms out at 16px the same way — and it is why hierarchy here
is carried by **colour**, which is free, rather than by size, which is not.

### A size is a font, not a parameter

The scale above is **two `rl.Font`s, not one font drawn at two sizes.** One `rl.Font` is one glyph atlas
rasterized at one size: ask `DrawTextEx` for 20px from an atlas baked at 40 and it resamples, giving up exactly
the pixel-exactness the table above was measured to buy. Bake each size once and keep both
(`cmd/game/ui.odin`'s `ui_font_title` / `ui_font_body`).

Two things that go with it, both mandatory and neither obvious:

- **Set the texture filter to `POINT`.** raylib defaults a font atlas to bilinear, which softens it on upload
  and silently undoes the whole antialiasing measurement — the font is then *exactly* as mushy as the guide
  says it must not be. `rl.SetTextureFilter(font.texture, .POINT)` immediately after loading.
- **The default codepoint set is ASCII 32–126.** `LoadFontFromMemory` with a nil codepoint list bakes that and
  no more, so `·` (U+00B7) and `—` (U+2014) are **not** in the atlas by default despite the face carrying them.
  Retiring `view.odin`'s em-dash workaround (below) needs an explicit codepoint list, not just the font.

### No bold, ever

`PixelifySans[wght].ttf` is a variable font (`wght` 400–700), Google publishes **no static instances**, and
raylib's stb_truetype **ignores variable axes entirely** — it renders the default (400) instance. A guide that
said "use the Bold weight" would be unfollowable, which is the exact failure this guide exists to prevent.

If a bold is ever genuinely needed it must be **pre-instanced at build time** with `fonttools varLib.instancer`
and embedded as a second blob. Do not reach for it first: the mock itself uses no weight contrast, only size
and colour.

### Rejected typefaces, and why

Recorded so they are not rediscovered and re-litigated:

| Face | Rejected because |
| --- | --- |
| **Pixel Pirate** | **Licence.** At least three distinct fonts share the name (one free on dafont, one *sold commercially* by FontBros); the "100% Free" tag is author-typed, not a licence file; it is described as derived from the *Pirates of the Caribbean* logo type; and this game has a public itch.io page, so redistribution rights are real. `docs/ui/references/typeface.htm` was saved to settle this and captured a Google redirect notice instead — it contains no font data. **Do not adopt without a licence document.** |
| **Press Start 2P** | **Measured overflow.** At 16px it is ~16px/char: `Hull 20/20  DUR 3  SPD 2` renders 384px into a 348px ship panel, and `Reallocate a fitting` renders 320px into a 220px button. It does not fit this game. |
| **VT323** | **Never crisp** — 46–98% antialiased at every size 8–34. It is a curvy face, and reads as a DOS terminal rather than 16-bit. |
| **Micro5**, **Jersey10** | Illegible mush at body sizes; 12 printable Latin-1 gaps each (`±`, `²`, `³`, `µ`). |
| **Silkscreen** | **Runner-up, and a close one.** Crisper than Pixelify (10% AA at 32px), static, complete Latin-1, 31KB. Rejected because it reads **all-caps**, and this game has prose — `battle_event_text`, `fitting_summary_lines`, `condition_intent`. Caps cannot carry prose. Revisit only if the restyle finds Pixelify too soft, and know that changing face later means redoing every screen. |

### One thing the font fixes for free

`view.odin:290-293` documents that raylib's built-in font carries only codepoints 32–255, so an em-dash
renders as `?` — which is why that code says `"none"` instead. **Pixelify Sans carries U+2014.** Once it is
embedded, that workaround can go.

## Glyphs are shapes, not text

The mock draws `▶` `◆` `↑` `↓` `⏎`. **Draw these with raylib primitives, never as text.**

This is measured, not stylistic. Of every candidate face examined, **none** carries `◆` (U+25C6) or `⏎`
(U+23CE), and the only one carrying `▶ ↑ ↓` is Press Start 2P — which is rejected on width. Depending on a
font for these glyphs means depending on a font that does not exist.

| Mark | Draw with |
| --- | --- |
| `▶` selection caret | `rl.DrawTriangle` |
| `◆` diamond bullet | `rl.DrawPoly` with 4 sides, or a rotated `DrawRectanglePro` |
| `↑` `↓` arrows | `rl.DrawTriangle` + `rl.DrawRectangleRec` |

Anything in printable Latin-1 (32–126, 160–255) is safe as text: `·` (U+00B7) and `—` (U+2014) both render.
Above U+00FF, assume a shape.

## Spacing, hierarchy, framing

### Hierarchy

The mock's order of attention, and the mechanism that produces it:

1. **Title** — 40px, cream `#E7D2A3`, on the darkest ground. Biggest thing on screen by a wide margin.
2. **The action** — amber `#F7A72B` fill. The only saturated warm mass.
3. **Other controls** — steel `#8AA9D6` border and label on a translucent ground. Present, clearly clickable,
   visibly not the default.
4. **Hints** — dim cyan `#57B5C3`, 20px, bottom of screen.
5. **The version stamp** — recessive blue `#3A5A82`. Findable, never read first.

Note what is *not* doing the work: there is no bold, no second font, and only two sizes. **Colour carries the
hierarchy.** If a screen needs a new level, reach for a tone from the chrome table, not a new size.

**The version stamp is shared chrome, and this guide forks it.** Levels 1–4 above describe a screen; level 5
describes `view.odin:514`'s `draw_version_stamp`, which the five out-of-scope voyage screens *also* draw — at
12px, in the stock font, in stock `GRAY`. Restyling it in place would restyle those five screens, so a styled
screen draws its own stamp (`draw_chart_table_version_stamp`) and the two converge when the restyle lands.
Expect the same fork for anything else shared between a styled screen and an unstyled one.

### Framing

The torn parchment edge and dark border are the only framing signal in the entire reference set, and the mock
keeps them as a **vignette**: the screen darkens to `#050B18` at its edges. That is the frame — not a drawn
border.

For panels, framing is a **2px border in the tone that states the panel's role** (steel for interactive,
recessive blue for inert) over a translucent ground, not a filled box. The mock's unselected rows let the
chart read through them; that translucency is what makes chrome sit *on* a world rather than cover it.

Starting alpha for a scrim: `rl.Fade(ground, 0.55)`, tuned by eye. The mock cannot give a real number here —
its transparency is painted, not composited (see [above](#where-this-came-from-and-what-the-mock-is-not)).

### Proportions

The mock's layout **cannot be copied** — its aspect is 1.806 against the window's 1.463. What transfers is its
proportions. Measured from the mock and scaled to 1024×700, as a **starting point** for
[Build the Chart Table](https://github.com/ssalter21/fantasy-ship-game/issues/281), not a spec:

| Element | In the mock | At 1024×700 |
| --- | --- | --- |
| Button width | 494px = 34.8% of width | **~356px** |
| Button height | 51px = 6.5% of height | **~45px** |
| Button pitch | 72px = 9.1% of height | **~64px** (≈19px gap) |
| Title centre | 16.4% of height | **y ≈ 115** |
| Hint row | 93.5% of height | **y ≈ 655** |
| Horizontal | title and buttons both centred | centred |

The button stack is centred horizontally but its **labels are left-aligned inside** each row, with the caret
in the left margin. That asymmetry is deliberate in the mock and worth keeping: a centred label in a centred
box has no anchor for the eye to run down.

**The table has no vertical origin for the stack, on purpose.** It gives pitch, not a starting `y`, and the
mock's own origin does not transfer — it stacks four items where the Chart Table has two, so copying its `y`
leaves a two-item stack sitting wrong in the field. Centre the stack in the space the title leaves and record
the number you chose (the Chart Table's is `CHART_TABLE_BUTTON_Y0`).

## Rules for raylib

- **`rl.DrawTextEx`, not `rl.DrawText`.** `DrawText` uses the built-in font. Every text call must pass the
  loaded font. This is the single change that retires most of the programmer-art read.
- `DrawTextEx` takes a **`spacing`** parameter. The mock's title and subtitle are visibly letterspaced; that
  is where it comes from. Pixelify at 40px renders a repo-length title at ~385px unspaced, narrower than the
  mock's title — close that gap with `spacing`, not with a bigger size. The mock's title is **~614px in the
  mock's own 1421px-wide space, i.e. ~43% of the window's width**, which is the figure that transfers: ~441px
  at 1024, reached at `spacing` ≈ 8. (Read as *mock* pixels the number implies `spacing` ≈ 19 and a title that
  falls apart; scale it before using it.)
- **Split composition from polling.** Any new screen needs a `draw_X_screen(state)` that the loop calls *and*
  capture calls. Compose buttons inside a poll loop and `--capture` photographs the screen with its buttons
  missing — see [#277](https://github.com/ssalter21/fantasy-ship-game/issues/277) and the comment at
  `menu.odin:461-465`.
- Text reaches drawing as `fmt.ctprintf` temp-allocator strings, freed by the per-frame
  `free_all(context.temp_allocator)`. Nothing here changes that.

## What this guide does not cover

- **A layout system.** Deliberately not designed, and **the first styled screen agrees**: building the Chart
  Table ([#281](https://github.com/ssalter21/fantasy-ship-game/issues/281)) reached for no stacking, alignment
  or constraint anything. A centred button stack is a pure function of five constants, hit-tested and drawn
  from one call (`chart_table_buttons`) — the idiom `option_screen_boxes` already established, and the one to
  copy. The **only** thing wanted and missing was a measure-then-place text helper, `MeasureTextEx` → subtract
  → halve being written out at each centred string. A two-button screen is too small to justify more; the
  restyle's five dense panels are where the real evidence will come from. The proportions above are a starting
  point, not a grid.
- **Restyling the five existing screens** (battle, travel, refit, trade, shop). Out of scope for the
  `effort:ui-capability` map. This guide states the target; it does not create a migration. Their 12/14/16/20
  call sites do not move until someone takes that effort — at which point every size below 20px must grow.
- **Art assets.** Illustration, ship art, node icons. Out of scope, with one carve-out: the Chart Table's
  background. Getting a *shippable* one is
  [#284](https://github.com/ssalter21/fantasy-ship-game/issues/284) — the mock is **not** it, and its
  provenance is unrecorded.
- **The Chart Table's contents.** Settled by
  [#278](https://github.com/ssalter21/fantasy-ship-game/issues/278), not here.
