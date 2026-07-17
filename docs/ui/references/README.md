# UI references

Reference images for the `effort:ui-capability` map ([#275](https://github.com/ssalter21/fantasy-ship-game/issues/275)),
gathered by the maintainer in [Gather the reference images](https://github.com/ssalter21/fantasy-ship-game/issues/276).

## What these are for — read this first

**These are palette and tone references. They are not layout references.**

Not one image here contains a UI: no buttons, no panels, no menus, no type, no HUD. They therefore say
nothing about spacing, typography, or hierarchy, and the style guide must **not** try to read those out of
them. What they do fix, consistently, is a colour world and a tonal register.

The map's `## Notes` frame — "craft, not art" — still holds. Take the palette; invent the craft.

### The palette these agree on

Across eight of the nine, the same four-part colour world recurs:

- **Deep navy / indigo grounds** — the dominant field (`ship-night`, `ship-battle`, `treasure-map` water)
- **Saturated cyan / turquoise** — the mid-tone and the eye's rest point (`wave`, `menu-port-tropical`, `island-tropical`)
- **Warm amber / orange accents** — lanterns, muzzle flare, sun. Always *small*, always punching against blue.
  This is the accent colour, and its scarcity is the point.
- **Sand / parchment cream** — the light neutral (`treasure-map`, beaches)

The blue-versus-amber opposition is the strongest signal in the set. It is a complementary pairing, and it is
what should replace raylib's stock `LIGHTGRAY` / `BEIGE` / `MAROON`.

### Tonal register

16-bit-era pixel art: hard edges, flat blocks of colour, no gradients, limited ramps per hue.

## Provenance and rights — important

Most of these are **watermarked stock or aggregator exports** (Magnific, Adobe Stock, Dreamstime,
depositphotos). That is fine for what they are — internal references, never redistributed, never shipped.

It stops being fine the moment an image is promoted to a shipped asset. See `menu/` below.

## menu/

| Image | Chosen for | Notes |
| --- | --- | --- |
| `treasure-map.jpg` | **The menu screen's background.** Not a reference — an intended asset. | Also useful for *framing*: the torn parchment edge and dark border are the only framing signal in the whole set. **Watermarked ("Magnific") — cannot ship as-is.** Sourcing a shippable equivalent is tracked separately. |

## style/

| Image | Chosen for | Notes |
| --- | --- | --- |
| `colour-palette.webp` | **The palette source.** Named for intent, not content. | Despite the name it is a scene (a mountain valley at dusk), not a swatch sheet. The name records that the maintainer wants the palette drawn from it. |
| `wave.jpg` | Cyan/turquoise mid-tones; the sea's colour | Bright daylight end of the range. Watermarked (depositphotos). |
| `menu-port-tropical.jpg` | Bright end of the palette; a port in daylight | The most "readable" image in the set — high value contrast, clear silhouettes. |
| `island-tropical.jpg` | Saturated tropical greens against cyan | Watermarked (Adobe Stock). |
| `ship-night.jpg` | **The amber-on-navy accent relationship**, at its clearest | Small warm lantern points against a large cold field. If one image drives the accent rule, it is this one. |
| `ship-battle.jpg` | Amber accent at its most extreme (muzzle flare on navy) | Same relationship as `ship-night`, louder. Watermarked (Magnific). |
| `floating-port.jpg` | Sky/cloud blues; airy end of the range | Watermarked (Dreamstime). |
| `pirate-port.jpg` | Atmosphere and mood only — **the outlier** | **Not pixel art** (painted concept art), and dark/desaturated where the rest are bright/saturated. Do not derive palette from this one; it contradicts the other eight. Kept because the maintainer liked the mood. |

## Typeface candidate

The maintainer flagged **Pixel Pirate** — <https://fontmeme.com/fonts/pixel-pirate-font/>

Unresolved, and deliberately left to the style guide ticket:

- **Which font this actually is.** At least three distinct fonts share the name: one by *SparklyDest*
  (dafont, tagged "100% Free", TTF), a *Fontalicious* "PixelPirate" **sold commercially** via FontBros, and a
  FontStruct one credited to *Caly Martin*. The fontmeme page blocks automated fetches, so which one it
  serves is unconfirmed.
- **Licence.** dafont's "100% Free" is an author-supplied tag, not a licence file. The font is also described
  as derived from the *Pirates of the Caribbean* logo type — a trademark/derivative question if this ships
  commercially.
- **8px bitmap.** It renders cleanly only at exact multiples (8/16/24/32). The current UI uses 12/14/16, so
  adopting it forces a type-scale change. Per the map's Notes, it must be embedded via `#load`
  (ADR-0009: the exe stays self-contained).
