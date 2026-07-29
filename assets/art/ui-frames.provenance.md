# ui-frame-{panel,card,button}.png — provenance

The three chrome frames the screens blit instead of stroking, added by
[#490](https://github.com/ssalter21/fantasy-ship-game/issues/490). Embedded with `#load` in
`presentation/art.odin`, blitted by `ui_nine_slice` (`presentation/ui_frame.odin`).

| File | Native | Slice inset | States |
| --- | --- | --- | --- |
| `ui-frame-panel.png` | 24×24 | 7 | 1 |
| `ui-frame-card.png` | 16×16 | 5 | 1 |
| `ui-frame-button.png` | 48×16 | 5 | 3 — rest, hover, press, left to right |

- **Tool:** none. These are **authored**, not generated — `scripts/make-ui-frames.py` places every
  pixel and is deterministic, so the PNGs are reproducible from source and a change to a border
  weight is a diff in that script rather than a new binary to take on trust.
- **Why authored rather than through PixelLab.** Two reasons, and the second is the load-bearing
  one. First, budget: `create_ui_asset` costs 20–40 generations per call and the account was on a
  trial with 10 remaining and $0.00 credits, so three frames were not fundable. Second, and the
  reason this is not merely a substitution — the guide's conform step exists because generated art
  lands *near* the palette and never *on* it, and "near" is exactly what reads as a foreign object
  when the thing behind it (`menu-island-day.png`) is exactly on the roster. Chrome is the one
  class of asset where conforming afterwards is not good enough. Art placed a pixel at a time is on
  the roster by construction.
- **Conform:** none needed, and that is the point. A scan of every opaque pixel finds only roster
  swatches: panel `#7E5C3A` / `#B98A50` / `#D2A968` / `#EBD9A6`; card `#1786BC` / `#D2A968` /
  `#EBD9A6`; button `#1786BC` / `#B98A50` / `#D2A968` / `#EBD9A6`. No saturated warm, so the
  reserved coral `#E1552B` stays scarce.
- **Composition.** The panel is the heaviest chrome, for a surface holding other things: a rock
  outline over a cliff-and-sand bevel with a gilt tick at each corner. The card is flatter, for a
  thing *in* a panel: the sea-deep border the Offer/Shop stock already reads by. The button carries
  its three faces side by side, differing by **structure rather than tint** — hover thickens the
  outline so the edge lights, press swaps the bevel so the face reads pushed in — which is what a
  pixel-art control does and what keeps every state on the roster.
- **Slice discipline.** All corner art sits inside each frame's inset, so 9-slicing stretches only
  the flat runs and every corner blits at native size. `ui_nine_slice` snaps its destination to
  whole pixels (rounding *edges*, never origin and size apart) and the textures load with a `POINT`
  filter, so nothing resamples the grid.

Regenerate: `python scripts/make-ui-frames.py`. Replacing these with PixelLab output later is a
drop-in — keep the filenames, the native sizes and the slice insets above, and quantize the result
to the roster exactly.
