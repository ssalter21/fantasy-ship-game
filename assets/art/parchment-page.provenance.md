# parchment-page.png — provenance

The warm aged treasure-map page the Chart is inked onto, with its rough torn deckled edge
baked into the same texture. Sourced + embedded per spec `docs/specs/0001-parchment-treasure-chart.md`
§2/§9 (build step 2, issue #347); embedded with `#load` in `cmd/game/art.odin` and blitted to
fill `MAP_AREA` in place of the retired blue depth-graded water + graticule.

- **Tool:** PixelLab MCP `create_map_object` (basic mode, 400×400, high top-down, flat shading,
  low detail, lineless). The one raster on this surface; the live ink layer stays procedural.
- **Prompt (final of three rolls):** "A single ragged torn-off piece of old weathered map paper
  lying flat, viewed straight from above … Every one of the four edges is jagged, ripped and
  frayed — never smooth, never rolled … warm cream (#EBD9A6) with faint uneven aged brown blotches
  and one or two soft tea stains, its torn rim darkening to warm brown … Blank surface." (Earlier
  rolls came back as rolled scrolls; the anti-scroll wording is what produced a flat torn sheet.)
- **Conform** (`tmp/conform.py`, run once, not shipped): the generator returns an opaque near-white
  surround, so a border flood-fill over near-white low-saturation pixels knocks it out to
  transparency (the dark torn edge seals the paper interior). Every remaining pixel is then
  quantized to the spec §8 parchment roster — Parchment `#EBD9A6`, Sand `#D2A968`, Cliff `#B98A50`,
  Rock `#7E5C3A` — with a hard alpha cut so no soft AA halo survives POINT upscaling. This also
  delivers the spec's 16-bit register (flat blocks, hard edges, no gradients).
- **Verified after conform:** 0 off-roster pixels; mass ≈ 60% Parchment ground / 25.8% transparent
  surround / rim in Sand·Cliff·Rock; peak luminance 217 (the Parchment ground — no bright white).

Regenerate: re-run `create_map_object` with the prompt above, then re-run the conform pass
(flood-fill knockout → roster quantize → hard alpha) against the spec §8 roster.
