# Mocking a screen in the browser

Design a screen here, then port it to Odin. This is the **divergent, exploratory** half of UI
design moved out of the compiled game — not the game itself, and not the simulation core, which
stay exactly where they are.

Open `shop.html` in a browser. That is the whole loop: edit, save, refresh. No compile, no
capture, no PNG in anyone's context.

```
docs/ui/mock/
  harness.css          the stage, the roster, and every constraint CSS can enforce
  pixel-operator.css   the game's face as a data URI (generated; see below)
  shop.html            the worked example — the Shop as it ships today
```

Nothing in the game builds against or reads any of this. It is a tool beside the game.

## Why a harness at all

Because a mockup has to be **honest**, and that is the whole of its difficulty. CSS can draw a
great many things raylib cannot — a blur, a rounded corner, a radial gradient, a half-pixel edge —
and a loop that ends with someone in love with a mockup that cannot ship has cost more than it
saved. The harness's job is to make the browser as poor a renderer as the game is.

The cost is paid once, here. After this, a mockup is an HTML file.

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

**Not enforced, and on you:**

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
