# Shop — four options, and what they asked for

The first run of `design-a-screen` (`.claude/skills/design-a-screen/SKILL.md`), against a screen
that exists. Four sub-agents in parallel, no shared context, one governing constraint each.

Open [`index.html`](index.html) to judge them side by side at full resolution. **Nothing here has
been chosen yet** — that is a human's call, and this file records what was produced so the
decision can be made against evidence rather than memory.

## The constraints, and the axis each one broke

Step 1 of the skill names what the screen currently takes for granted. The Shop's answers:

| Axis | The Shop as it ships |
| --- | --- |
| Ground | Sea. The world fills the frame. |
| Containment | Unbacked parchment cards, no panel. |
| Figure / ground | The world is the subject; content sits beside it. |
| Axis | A single column down the right edge. |

One agent per axis, each fixed to a different value — never two on the same axis:

| Option | Axis broken | The brief |
| --- | --- | --- |
| [`mostly-parchment`](mostly-parchment.html) | Ground | The screen is mostly parchment; the world is a margin, not the field. |
| [`no-container`](no-container.html) | Containment | No panel and no card. Content sits directly on the world. |
| [`ship-behind`](ship-behind.html) | Figure / ground | The ship *is* the background; content lies on top of her. |
| [`not-a-column`](not-a-column.html) | Axis | The stock does not run down a column. Order it some other way. |

## Did they actually diverge

The failure this skill exists to fix was measured at **82% pixel-identical**. This run
(`python scripts/mock-divergence.py shop`):

| Pair | Identical |
| --- | --- |
| mostly-parchment vs ship-behind | 8.9% |
| mostly-parchment vs no-container | 10.8% |
| no-container vs ship-behind | 12.3% |
| not-a-column vs ship-behind | 12.7% |
| mostly-parchment vs not-a-column | 17.3% |
| **no-container vs not-a-column** | **67.7%** |

Five of six pairs share under a fifth of their pixels. The closest pair is the one worth reading:
`no-container` and `not-a-column` both keep the shipped **ground** (sea) and the shipped
**figure/ground** (world behind, content in front), so most of what they agree on is water. They
still differ where their briefs differ. But it is the honest reading of the number that two
constraints leaving two axes alone will land nearer each other than either lands to
`mostly-parchment`, which changes what the screen is made of.

## What each option asked for that `ui.odin` does not have

This is the list [#493](https://github.com/ssalter21/fantasy-ship-game/issues/493) builds from.
Building the widget layer *before* the mockups existed would have risked building the wrong
components; these are the ones four independent designs actually reached for.

**Asked for by more than one option — the strong signal:**

- **A measure-and-place text helper**, with an `anchor` axis (left / centre / right). Named by
  three of the four. Every right-aligned price and every centred label is a `MeasureTextEx` at the
  call site today, or it is wrong.
- **A placement helper that works against another rect** — `ui_place_beside(anchor, side, size)`.
  Named by `not-a-column` and `ship-behind`. All layout today is `x0 + i*pitch`; there is no
  vocabulary at all for "beside this other thing".
- **`ui_rule(rect, weight, tone)`** — a divider whose *weight* is the hierarchy signal. Named by
  `mostly-parchment` (five rules do the work boxes do elsewhere) and `no-container` (weight states
  whether a line separates or is a control).
- **An affordability axis on the card/row proc**, resolving to one shade factor plus an ink pair.
  Named by three. Dimming is three coordinated edits today, so a screen can dim two of three and
  ship.
- **A crate glyph as a primitive** — `ui_glyph_crate` / `ui_price`. Named by two, and it appears on
  every screen that shows a price.

**Asked for by one option, and worth recording as a cost rather than a plan:**

- `mostly-parchment`: a **surface axis** on the panel — `raised | flush | inset`. `ui_nine_slice`
  only makes a thing sit *above* its ground; parchment-on-parchment needs containment *carved*.
  Also a `ui_table(rect, columns)`, and a **face axis** on the button (`outlined | raised | tab`),
  because "outlined over a translucent ground" was written for controls over the *world* and there
  is nothing to separate from on full parchment.
- `no-container`: a **text style that carries its own legibility over water** — fill plus an ink
  edge, measured at two opposed corners because one was not enough over a whitecap. And a **text
  ramp for the water ground**: parchment has three ink levels, water has exactly one
  (`COLOUR_CREAM_BRIGHT`), so this option had to borrow surface swatches as ink.
- `ship-behind`: a **`ship_feature_point(ship, feature)`** anchor in screen space, without which
  the design is not portable at all; a leader line; an anchor ring; and a real **placement
  solver** rather than a layout struct. Its note also records that the shipped 0.95 dim factor is
  invisible against the hull's shadowed underbody — *a dim factor is relative to the ground the
  card is on*, which stops being one constant as soon as cards scatter.
- `not-a-column`: a **card at three sizes** with the size class driving padding and row pitch
  together, a rank-to-size map so size is derived from the stock rather than hand-assigned, and a
  **tether** whose derivation is the non-obvious part (struck at the midpoint of the span the two
  rects *share*, not the card's own midpoint). Its note also states the cost honestly: a ring has
  four sides, so a fifth stock item has nowhere to go.

**What nobody asked for:** a third type size. All four carried the screen on 32/16 with colour
doing the rest. That is worth knowing next to
[#497](https://github.com/ssalter21/fantasy-ship-game/issues/497), which opens the scale above 32
on the strength of a different argument — hierarchy on a *title*, not on a stock card.

## Keeping the rejections

**Nothing here gets deleted.** In HTML the cost of keeping all four forever is four files, and a
direction that was not chosen is still a data point about what this game looks like — the reason a
thing was not chosen is worth more later than the absence of it. `render/` holds the shots the
divergence measurement was taken from and is regenerable.
