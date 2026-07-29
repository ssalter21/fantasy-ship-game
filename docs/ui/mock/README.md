# Mocking a screen in the browser

Design a screen here, then port it to Odin. The `direct-a-screen` skill runs this at N directions
× n options a round; a single mockup by hand is the same thing with the interview skipped. Either
way this is the **divergent, exploratory** half of UI design moved out of the compiled game — not the game itself, and not the simulation core, which
stay exactly where they are.

Open `shop.html` in a browser. That is the whole loop: edit, save, refresh. No compile, no
capture, no PNG in anyone's context.

```
docs/ui/mock/
  harness.css          the stage, the roster, and every constraint CSS can enforce
  pixel-operator.css   the game's face as a data URI (generated; see below)
  shop.html            the worked example — the Shop as it ships today
  <screen>/
    README.md          the rounds: what was briefed, what was picked, and why
    r1/                one round of the `direct-a-screen` skill
      <direction>--<example>.html
      render/          a PNG per option
      index.html       the contact sheet, generated — options grouped by direction
    r2/                the next round, its reference being r1's winner
```

Two hyphens between a direction and its example, because both halves are themselves hyphenated
names: `torn-chart--ship-behind` splits and `torn-chart-ship-behind` is a guess.

Nothing in the game builds against or reads any of this. It is a tool beside the game.

## Why a harness at all

Because a mockup has to be **honest**, and that is the whole of its difficulty. CSS can draw a
great many things raylib cannot — a blur, a rounded corner, a radial gradient, a half-pixel edge —
and a loop that ends with someone in love with a mockup that cannot ship has cost more than it
saved. The harness's job is to make the browser as poor a renderer as the game is.

The cost is paid once, here. After this, a mockup is an HTML file.

## The three levels

Not every mockup is trying to ship. `direct-a-screen` briefs some directions deliberately off the
house style, and some off the renderer entirely, because *"what would this look like if we threw
the palette out"* is a question worth a picture. **A mockup therefore declares what it is playing
by**, in its note block, and everything below applies at the level it declared.

| Level | The roster and the type scale | What raylib can draw | Ports? |
| --- | --- | --- | --- |
| `house` | binding | binding | yes, as drawn |
| `off-style` | thrown out — any palette, any type size, coral unreserved | binding | yes; the port adds swatches |
| `free` | thrown out | thrown out — blur, rounded corners, transforms | **no** |

`off-style` is nearly always what "no constraints" actually means, and it still ports: a colour is
a colour to a draw call. `free` is for the question that is worth a picture you cannot build — its
findings are not failures, they are the engine work its look would cost, and the checker prints
them as such.

**Three things bind at every level**, `free` included: the **1244×700 stage** (it is the window,
not a style — a mockup at another size cannot be set beside the others and judged), the
**harness link**, and the **note block**.

Only `free` is a CSS matter. The style layer was never enforced by the stylesheet — a roster name
is a variable, not a rule — so `harness.css` has exactly one door out, `class="stage free"`, and
`check-mock.py` holds the other two. The checker fails a mockup whose declared level and stage
class disagree, so a mockup cannot claim `house` while drawing with a blur.

## The note block

Every mockup closes with one, and the checker fails without it. It is the option's **port cost**,
and when somebody is standing in front of nine options it is half the decision — the prettiest of
nine is not the pick if it is the one that costs a month.

```html
<div class="note">
  <h1>Shop — the stock laid around her</h1>
  <dl class="port-cost">
    <dt>level</dt><dd class="level">off-style</dd>
    <dt>forced</dt><dd>No column, so the cards are dealt against the hull and the eye
      travels round her rather than down a rail.</dd>
    <dt>missing</dt><dd>A measure-and-place text helper with an anchor axis.</dd>
    <dt>invented</dt><dd>Two greys off the roster for the deck planking.</dd>
    <dt>broke</dt><dd>—</dd>
  </dl>
  <p>… whatever else the author needs to say …</p>
</div>
```

| Field | What goes in it |
| --- | --- |
| `level` | `house`, `off-style` or `free`. **Required** — it is what decides which rules bind. |
| `forced` | What the direction made this mockup do differently. **Required**: a mockup that cannot say this has not been briefed, it has been decorated. |
| `missing` | What it needed from `ui.odin` that does not exist. This is how mockups feed the widget layer — the components worth building are the ones several independent designs reached for. |
| `invented` | Colour or type outside the roster and the two sizes. Empty at `house`. |
| `broke` | Which renderer rule it broke, and therefore what engine work it costs. Empty unless `free`. |

**A field with nothing to say is left out**, rather than filled with "n/a". Only `level` and
`forced` are required.

## The rules

Everything the stylesheet can refuse, it refuses with `!important` inside `.stage`, so an
author's own rule loses rather than quietly winning. Everything it cannot is checked:

```bash
python scripts/check-mock.py                      # every mockup under docs/ui/mock/
python scripts/check-mock.py docs/ui/mock/shop.html
```

**Enforced by `harness.css`** — write these and nothing happens:

| Refused | Because |
| --- | --- |
| `border-radius` | Nothing rounds a rectangle's corner. A rounded frame is a 9-slice sprite. |
| `filter`, `backdrop-filter` | There is no blur pass. A soft edge is painted into a sprite or it is absent. |
| `text-shadow` | Glyphs blit from an atlas. |
| `transform` | Every draw call takes absolute coordinates. |
| `transition`, `animation` | A mockup is one frame. Motion is judged in the game, not here. |
| `box-shadow` | raylib's shadow is a second rectangle — use `.cast-shadow`, which draws one. |
| font smoothing | A pixel face resampled is the thing this game exists to avoid. |

**Enforced by `check-mock.py`** — rules about *values*, which no stylesheet can express:

- **Every colour is a roster swatch, or a uniform shade of one.** Use the `--var` names. A shade
  is allowed because `colour_shade` exists in Odin, and the checker names the swatch and factor it
  resolved to so the port is obvious. A hand-typed hex that is not a shade of anything fails.
- **Gradients are one axis.** `linear-gradient(to bottom|top|left|right, …)` and nothing else,
  because `DrawRectangleGradientV` and `DrawRectangleGradientH` are the only gradient calls there
  are. A radial or an angled gradient has no draw call behind it.
- **Positions and sizes are whole pixels.** A `10.5px` edge is resampled by the browser and cannot
  be asked for in a draw call at all.
- **The stage is exactly 1244×700.** A layout measured at any other size is a layout the game will
  never show.

**Which of those bind depends on the level.** The colour rule binds at `house`; at `off-style` and
`free` an off-roster colour is *reported* as a swatch the port would have to add. The gradient and
whole-pixel rules bind at `house` and `off-style`; at `free` they are reported as engine work. The
stage size binds everywhere.

**Not enforced, and on you** (and all of it `house`-level — an `off-style` or `free` direction is
briefed to break exactly these):

- **Two type sizes.** `--title` (32px) and `--body` (16px). Pixel Operator is a native-16px face
  and these are the sizes it is measured 0% antialiased at. A mockup wanting a third size is
  proposing a new atlas — legitimate, but say so in the mockup's note rather than typing a number.
- **Text tone follows its ground.** `--ink` / `--ink-muted` on parchment; `--cream-bright` over
  water. Never the other way round.
- **Coral is reserved.** `--coral` is the roster's only saturated warm and it means danger or
  damage. A mockup that spends it on an accent has broken the one signal the palette protects.
- **Don't redraw what already exists and already looks right.** The galleon in `shop.html` is a
  brown block, on purpose. Block in the solved parts so the unsolved part has the right amount of
  screen around it.

## Judging a round

```bash
python scripts/mock-contact-sheet.py <screen>        # the latest round
python scripts/mock-contact-sheet.py <screen> r1     # a named one
```

Renders every option in the round and writes its `index.html`: full resolution, **grouped by
direction**, each option's port-cost fields repeated under its frame. Across the rows you are
choosing what the screen is; inside a row you are choosing which arrangement of that idea reads
best. Open it — that page is what a human picks from.

## Porting a mockup back to Odin

The mapping is small because the harness has already thrown away everything that does not map.

| CSS | Odin |
| --- | --- |
| `position: absolute; left/top/width/height` | the `rl.Rectangle` a draw proc is handed |
| `background: var(--x)` | `rl.DrawRectangleRec(rect, COLOUR_X)` |
| `background: #shade-of-x` | `colour_shade(COLOUR_X, factor)` — the checker prints the factor |
| `border: Npx solid var(--x)` | `rl.DrawRectangleLinesEx(rect, N, COLOUR_X)` — or better, a frame |
| `.frame-panel` / `.frame-card` / `.frame-button` | `ui_nine_slice(UI_FRAME_PANEL, rect)` and friends |
| `.cast-shadow` | a second `DrawRectangleRec` at the offset, under `rl.Fade(COLOUR_SEA_DEEP, 0.45)` |
| `linear-gradient(to bottom, a, b)` | `rl.DrawRectangleGradientV(x, y, w, h, A, B)` |
| `font-size: var(--body)`, text | `rl.DrawTextEx(ui_font_body, text, pos, UI_BODY_SIZE, 1, tone)` |
| `opacity: n` on a fill | `rl.Fade(colour, n)` |
| `text-align: center` | measure with `rl.MeasureTextEx`, then centre the origin yourself |
| a repeated block (`.card`) | one draw proc taking a rect, called per item |
| the geometry constants themselves | a layout struct + `--workbench <screen>` (run-game skill) |

**Nothing else maps.** If a mockup needs something not in this table, the port is not a port — it
is a new draw capability, and that is a decision to take deliberately rather than discover halfway
through an afternoon.

**Where the numbers go.** A ported screen's geometry belongs in one layout struct beside its
shipped literal (`Offer_Shop_Layout` / `OFFER_SHOP_LAYOUT` / `offer_shop_layout` in
`presentation/offer_shop.odin`), not scattered as constants — that is what makes the screen
steerable in `--workbench` afterwards, so the last mile of tuning costs a drag rather than a
rebuild.

## Regenerating the embedded face

```bash
python scripts/make-mock-font.py
```

Writes `pixel-operator.css`. The face is embedded as a data URI rather than linked because Chrome
refuses to load a `file://` font through `url()`, and the failure is silent: the mockup still looks
fine and every measurement taken off it is wrong. Re-run this only if `assets/fonts/PixelOperator.ttf`
changes.
