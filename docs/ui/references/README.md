# UI references

Reference images for the `effort:ui-capability` map ([#275](https://github.com/ssalter21/fantasy-ship-game/issues/275)),
gathered by the maintainer in [Gather the reference images](https://github.com/ssalter21/fantasy-ship-game/issues/276).

## What these are for — read this first

**The written art direction these fed is [`docs/ui/style-guide.md`](../style-guide.md). Read that first — it
is the followable output. These are its raw material.**

**The nine scenes are palette and tone references. They are not layout references.**

Not one of the nine scenes contains a UI: no buttons, no panels, no menus, no type, no HUD. They therefore say
nothing about spacing, typography, or hierarchy, and the style guide must **not** try to read those out of
them. What they do fix, consistently, is a colour world and a tonal register.

The map's `## Notes` frame — "craft, not art" — still holds. Take the palette; invent the craft.

**`menu/menu-ui-mock.png` is the exception, and it is a look reference, not a spec.** It is the one image here
that *is* a UI, and it fixes the style guide's chrome palette and hierarchy. But its **contents are wrong for
this game** — see the `menu/` table below before taking anything but colour and proportion from it.

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
| `menu-ui-mock.png` | **The chrome palette and the hierarchy.** The only image here that is a UI. | **Look reference, not a spec** — see the warning below. Its solid fills are exact and were sampled directly into the style guide; its *translucency* is not internally consistent (it is a painting of a UI, not a rendered one), so its alpha cannot be reverse-engineered. |
| `treasure-map.jpg` | **The Chart Table's background.** Not a reference — an intended asset. | Also useful for *framing*: the torn parchment edge and dark border are the only framing signal in the whole set. **Watermarked ("Magnific") — cannot ship as-is.** Sourcing a shippable equivalent is [#284](https://github.com/ssalter21/fantasy-ship-game/issues/284). |

### The mock is a look reference, not a spec

Three things in `menu-ui-mock.png` are **actively wrong for this game**. Do not build them:

- **Its menu items are not the Chart Table's.** [#278](https://github.com/ssalter21/fantasy-ship-game/issues/278)
  settled that the Chart Table holds a title, **Begin a voyage**, **Quit**, and nothing else, and that it is
  **stateless**. The mock's *Continue Voyage* (there is no save), *Crew & Codex* (meta-progression, out of
  scope), *Settings*, and its `SEED TIDEBORN-4417` line (seeding policy, out of scope) are illustrative only.
- **Its input model is not the game's.** It shows `↑↓ NAVIGATE  ⏎ SELECT`; every menu in this game is mouse
  click-polling and nothing reads arrow keys.
- **Its aspect ratio is not the game's.** 1421×787 (1.806) against the window's 1024×700 (1.463). Its layout
  cannot be transplanted by scaling — only its proportions transfer.

**It is also not the shippable background.** Its provenance is unrecorded, and #284's bar was a shippable file
*plus* a provenance line. See #284.

## style/

| Image | Chosen for | Notes |
| --- | --- | --- |
| `colour-palette.webp` | **The _world_ palette** — `zone_tint`'s Coastal / Open_Sea / Deep. Named for intent, not content. | Despite the name it is a scene (a mountain valley at dusk), not a swatch sheet. #280 split the palette in two: this image fixes the **world** (the sea being depicted), the mock fixes the **chrome** (what is drawn on top of it). It does **not** set the chrome colours — it is a dusk valley, not the navy/amber world the rest of the set agrees on. |
| `wave.jpg` | Cyan/turquoise mid-tones; the sea's colour | Bright daylight end of the range. Watermarked (depositphotos). |
| `menu-port-tropical.jpg` | Bright end of the palette; a port in daylight | The most "readable" image in the set — high value contrast, clear silhouettes. |
| `island-tropical.jpg` | Saturated tropical greens against cyan | Watermarked (Adobe Stock). |
| `ship-night.jpg` | **The amber-on-navy accent relationship**, at its clearest | Small warm lantern points against a large cold field. If one image drives the accent rule, it is this one. |
| `ship-battle.jpg` | Amber accent at its most extreme (muzzle flare on navy) | Same relationship as `ship-night`, louder. Watermarked (Magnific). |
| `floating-port.jpg` | Sky/cloud blues; airy end of the range | Watermarked (Dreamstime). |
| `pirate-port.jpg` | Atmosphere and mood only — **the outlier** | **Not pixel art** (painted concept art), and dark/desaturated where the rest are bright/saturated. Do not derive palette from this one; it contradicts the other eight. Kept because the maintainer liked the mood. |

## Typeface — settled

**Resolved by [#280](https://github.com/ssalter21/fantasy-ship-game/issues/280): the game adopts
[Pixelify Sans](https://github.com/google/fonts/tree/main/ofl/pixelifysans) (SIL OFL 1.1).** The reasoning,
the measured size scale, and the full rejection list live in [`docs/ui/style-guide.md`](../style-guide.md#type).

**Pixel Pirate was rejected on licence** — it is not adoptable, and this is not a "revisit later":

- At least three distinct fonts share the name: one by *SparklyDest* (dafont, tagged "100% Free", TTF), a
  *Fontalicious* "PixelPirate" **sold commercially** via FontBros, and a FontStruct one credited to
  *Caly Martin*. Which one fontmeme serves is still unconfirmed — the page blocks automated fetches.
- dafont's "100% Free" is an author-supplied **tag, not a licence file**, and the font is described as derived
  from the *Pirates of the Caribbean* logo type — a trademark/derivative question given the public itch.io
  page. **Do not adopt it without a licence document.**

`typeface.htm` was saved to settle the above and **captured nothing** — it is a Google *"Redirect Notice"*
interstitial, not the fontmeme page, and contains no font data. It is kept only so the next person does not
re-save it expecting an answer.
