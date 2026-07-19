# ship-sprite.png — provenance

The sailing ship: a PixelLab 8-direction pixel-art sprite, the one raster on the Chart's
otherwise-procedural live layer (a little vessel *on* the map, not a mark drawn *in* it).
Sourced + embedded per spec `docs/specs/0001-parchment-treasure-chart.md` §5/§9 (build step 4,
issue #349); embedded with `#load` in `cmd/game/art.odin`, drawn by `draw_ship_sprite`
(`cmd/game/view.odin`) resting on the current node in place of the retired amber ring+dot.

- **Tool:** PixelLab MCP `create_8_direction_object` (object `a1ad1886-75b7-4204-90b2-03bca0d3896d`,
  size 64 → 68×68 native, high top-down). Objects, not characters — a ship is a prop.
- **Prompt:** "a small wooden sailing ship, a single-masted sloop with one billowing off-white
  cream canvas sail and a dark brown wooden hull, tiny pixel-art vessel seen from above on an old
  treasure map, warm sepia and muted brown tones only, no bright colors, no orange, no gold, no
  amber." The anti-amber wording keeps the sprite off the reserved accent (spec §8): the page
  spends coral only on the Haven X.
- **Layout:** the eight returned rotations (north, north-east, east, south-east, south,
  south-west, west, north-west) are composited into a single horizontal strip in that heading
  order — `Ship_Heading` N, NE, E, SE, S, SW, W, NW left-to-right (`tmp/compose.py`, run once, not
  shipped). Each frame is a 68×68 square; the strip is 544×68. `draw_ship_sprite` reads the frame
  size from the sheet height, so a heading indexes column `int(heading) * height`.
- **Conform:** none needed. Scan of every opaque pixel across the eight frames found **0
  amber/orange/gold pixels** — the warm hull sits in muted brown, the sail in cream, both already
  on the parchment register. Transparency (RGBA) is preserved from the source, so the sprite
  composites cleanly over its faint parchment chip.

Regenerate: re-run `create_8_direction_object` with the prompt above (high top-down, size 64),
download the eight rotation URLs, and re-composite into the N,NE,E,SE,S,SW,W,NW strip.
