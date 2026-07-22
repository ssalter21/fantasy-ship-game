---
name: create-assets
description: Generate the game's pixel-art assets — ship sprites, sea tiles, node icons, UI panels, fonts — through the PixelLab MCP, conformed to the style guide's palette ramp and embedded in the self-contained exe. Use when creating, regenerating, or sourcing any game art asset.
---

# Generating game art with PixelLab

The loop mirrors run-game's: **read the guide → generate → poll → download → conform → wire → look**.
PixelLab produces the pixel art; *you* are the one who makes it fit this game, and this game has a fixed art
direction that most generated art will miss on the first shot.

The pixellab tools are an HTTP MCP server (`pixellab`, `https://api.pixellab.ai/mcp`). Before anything else,
confirm it is connected — call `get_balance`. No tools surfaced means the server is not attached to this
session; stop and say so rather than working around it.

## Read the style guide, and pick a target it actually wants

`docs/ui/style-guide.md` is the fixed target for "good" — the same guide run-game reads. Two of its rulings
decide whether an asset belongs here at all, so read them *before* you generate, not after:

- **This game draws its chrome, it does not source it.** The Chart Table's background, its rose, its buttons
  are raylib primitives, drawn from the ramp — precisely so they *cannot* clash with the palette. A generated
  panel or button is swimming against that current. The legitimate targets for sourced art are the ones the
  guide files under **out of scope with a carve-out**: illustration, **ship art**, **node icons**, and a
  *sourced* Chart Table background ([#284](https://github.com/ssalter21/fantasy-ship-game/issues/284)). Generate
  those. Don't generate UI chrome that the guide already draws — you'd be replacing measured, conformant
  primitives with art that has to be dragged back onto the ramp.
- **The palette is one ramp, and it is law.** Exact hexes: Deep `#081127`, Mid `#0A1C30`, Shallow `#0E2E3F`,
  vignette `#050B18`; amber `#F7A72B` is reserved for *the* action and nothing else. Generated art will not
  land on these hexes on its own — conforming it (below) is the step that makes it this game's art rather than
  generic pixel art.

**Completion criterion:** you can name the asset, the guide section that sanctions it, and the ramp stops it
must resolve to — or you've concluded it should be drawn, not generated, and stopped.

## The tool map

Pick the `create_*` tool by what the asset *is*. Each has a matching `get_*` (poll/download), `list_*`, and
`delete_*`.

| Asset | Tool | Notes |
| --- | --- | --- |
| A ship, from every angle | `create_8_direction_object` | 8 rotations for map/travel; `size` 32–168. Ships are objects, not characters. |
| A ship / prop, one view | `create_map_object` | Transparent background; fast (15–30s). Expires after 8h — **download promptly**. |
| A node / encounter icon | `create_map_object` | Small, transparent, one per stage kind (Fight, Trade, Shop…). |
| Sea / coast autotiles | `create_topdown_tileset` | 16-tile Wang set; `lower_description` deep water, `upper_description` coast. |
| A sourced chart background | `create_map_object` or `create_1_direction_object` | The #284 carve-out. Must not outshine the chrome (below). |
| A UI panel (rare) | `create_ui_asset` | Only where the guide sanctions sourced chrome — usually it doesn't. |
| A pixel font | `create_font` | Alternative to Pixelify Sans; the guide's type rules and `#load` embedding still apply. |

`get_balance`, `list_objects`, `list_characters`, `agent_help` round it out. Reach for `agent_help` when a
tool's parameters are unclear — it answers from PixelLab's own docs.

## The async shape: create → poll → download

Every generator is a queue, not a call. This is the mechanical core and it is the same for every tool:

1. `create_*` returns an **id** and processes in the background — objects ~15–30s, ships/tilesets **2–5
   minutes**. It does *not* return the image.
2. Poll `get_*(id)` until status is complete. It reports progress; a completed result carries a **public
   download URL** (the UUID is the access key — no auth header needed).
3. Download that URL to disk yourself — `curl -o assets/art/<name>.png <url>`. The MCP does not write files;
   nothing reaches the repo until you fetch it. `create_map_object` results **expire after 8 hours**, so
   download before you do anything else.

**Steer at creation, not after.** Pass the ramp into `create_*`: a `color_palette` hint (e.g.
`"navy #081127 deep, cyan #6FE0EC highlight, amber #F7A72B accent"`) and a style-reference image
(`background_image` / `style_image_base64`) built from `docs/ui/references/` — `ship-night.jpg` and
`ship-battle.jpg` are the two references that carry this game's amber-on-navy register. A good reference image
does more than any text hint. Use `seed` so a regenerate is a variation, not a fresh roll.

**Completion criterion:** the PNG is on disk under `assets/`, opened once with Read, and it is the asset you
asked for — not a placeholder or a failed frame.

## Conform it to the ramp

Generated art lands *near* the palette, never *on* it, and "near" is what reads as a foreign asset. Snap it,
then measure it — the same discipline run-game's style loop uses, don't trust your eyes:

- **Quantize to the ramp.** Map every pixel to its nearest ramp stop / tone (the tables in the guide's
  *Palette* section). A short PIL pass does it; verify afterward by sampling corners and mass, exactly as
  run-game's pixel-scan does, and check each sampled hex against the guide's stated value.
- **The world must never outshine the chrome.** The guide's hard rule for anything behind the UI: peak
  luminance of a background asset must sit **below the title's**. A sourced chart background that reads brighter
  than the cream title is the #284 trap — measure the peak, don't eyeball it.
- **Amber stays scarce.** If PixelLab sprinkled amber across a sprite, it just broke the amber rule. Amber is
  reserved for the actionable control; a ship or a tile that ships amber pixels dilutes the one signal the whole
  palette is built to protect. Quantize those warms to cream or khaki.

## Make it self-contained

An asset that ships as a loose file breaks ADR-0009's self-contained `game.exe` — the same reason the font is
embedded, not shipped beside the binary. Follow the font's worked example in `presentation/ui.odin`:

- **Embed with `#load`**, as `PIXEL_OPERATOR_TTF :: #load("../assets/fonts/PixelOperator.ttf")` does — the
  path is relative to the source file, so from `presentation/` it is one level up. Put art under `assets/`
  beside `fonts/`.
- **Load the texture after `InitWindow`** (the atlas is a GPU resource) and **set its filter to `POINT`** —
  `rl.SetTextureFilter(tex, .POINT)`. raylib defaults to bilinear, which softens pixel art on upload and undoes
  the whole point of generating at native resolution. This is the identical trap the font atlas hits.
- **Split composition from polling**, like every screen: an asset drawn inside a poll loop is invisible to
  `--capture`. Draw it in a `draw_X` proc the loop *and* capture call.

## Look — hand off to run-game

You have not shipped an asset you have not seen *in the game*. Don't re-verify here; this is exactly what
run-game exists for. Build, `--capture` the screen the asset appears on, open the shot, and drive the real
window where capture can't reach. run-game owns that loop and its context budget — follow it.

## Credits are real money

PixelLab generations bill the account. `get_balance` before a batch. `pro` and `v3` modes cost more than
`standard`/`template` — the paid tools take `confirm_cost` and will wait for it. Don't spin a generate loop
that regenerates on every near-miss; steer with a reference image and a `seed` so each roll is deliberate.
