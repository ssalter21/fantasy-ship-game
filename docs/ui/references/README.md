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

**`menu/menu-ui-mock.png` is the exception, and it is a *layout* reference, not a palette one.** It is the one
image here that *is* a UI, so it fixes the style guide's **hierarchy and proportion**. But it is a **navy** mock
and **no longer sets colour** — see the `menu/` table below.

### The palette these agree on

Across the daylight set the same bright, saturated colour world recurs — and `style/island-tropical.jpg` states
it most clearly, which is why the style guide makes it the **keystone**:

- **Saturated turquoise sea** — the dominant cool and the eye's rest point (`island-tropical`,
  `menu-port-tropical`, `wave`). Bright, high-value, not navy.
- **Warm tan sand and parchment** — the neutral the world sits on (`island-tropical` cliffs, `treasure-map`
  paper, beaches). Desaturated warm.
- **Vivid greens** — a full ramp from deep shadow to a yellow-green highlight (`island-tropical` palms,
  `island-tropical`'s inland). Where the earlier navy direction was most muted.
- **A single warm accent** — amber/orange, always *small*, always punching against blue (`ship-night` lanterns,
  `ship-battle` flare). Its scarcity is the point.

The clash between **saturated cyan and warm sand** is the strongest signal in the daylight set — a warm-vs-cool
opposition at high value. That clash, not a dark ground, is what the style guide builds its contrast on, and it
is what should replace raylib's stock `LIGHTGRAY` / `BEIGE` / `MAROON`.

> **This supersedes an earlier reading.** A previous pass reconciled the set as *one depth ramp* — navy as deep
> water, teal as shallow — and grounded the whole UI on a near-black navy. That read the *night* scenes
> (`ship-night`, `ship-battle`, and the navy `menu-ui-mock`) as the palette's spine and demoted the daylight
> ones. It produced a clinical, cold UI that drifted from the references' actual brightness. The set is not a
> depth ramp; it is a **bright daylight world with a scarce warm accent**, and the guide now derives from the
> daylight images directly.

### Tonal register

16-bit-era pixel art: hard edges, flat blocks of colour, no gradients, limited ramps per hue.

## Provenance and rights — important

Most of these are **watermarked stock or aggregator exports** (Magnific, Adobe Stock, Dreamstime,
depositphotos). That is fine for what they are — internal references, never redistributed, never shipped.

It stops being fine the moment an image is promoted to a shipped asset. See `menu/` below.

## menu/

| Image | Chosen for | Notes |
| --- | --- | --- |
| `menu-ui-mock.png` | **Hierarchy and proportion only.** The one image here that is a UI. | **Layout reference, not a palette one.** It is a *navy* mock; the style guide takes its stack, its centred title, its left-aligned labels, and its caret-and-scrim hover model — and **leaves its colour**, which the daylight set overrules. Its solid fills are exact but navy; its *translucency* is not internally consistent (it is a painting of a UI, not a rendered one), so its alpha cannot be reverse-engineered either. Its **contents are wrong for this game** — see the warning below. |
| `treasure-map.jpg` | **The parchment map surface, and framing.** Promoted. | The run-map is being rebuilt as an actual chart — a piece of parchment — and this is its reference: sand-and-cream paper, water drawn *on* the paper, a red compass rose and X. It is the palette source for that surface, not just the torn-edge framing device. **Still watermarked ("Magnific") — cannot ship as-is**; a *sourced* map image remains [#284](https://github.com/ssalter21/fantasy-ship-game/issues/284). Its warmth is a feature here, not a threat: parchment is *desaturated* warm, so it coexists with the scarce, *saturated* amber accent (see the guide's saturation rule). |

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
| `island-tropical.jpg` | **The keystone.** The clearest statement of the target palette. | Saturated turquoise sea, warm tan cliffs, a full vivid green ramp, purple-white clouds — every colour turned up. The style guide's roster is sampled from it. Watermarked (Adobe Stock) — reference only, never shipped. |
| `menu-port-tropical.jpg` | Supporting witness: the bright daylight sea and a port | The most "readable" image in the set — high value contrast, clear silhouettes, terracotta roofs against blue water. Backs the keystone's sea. |
| `wave.jpg` | The brightest cyan/turquoise mid-tones | The daylight-end of the sea's colour. Watermarked (depositphotos). |
| `ship-night.jpg` | **The amber-on-blue accent relationship**, at its clearest | Small warm lantern points against a large cold field. If one image drives the accent rule, it is this one. **Accent witness only** — a night scene; do not read a ground colour from it. |
| `ship-battle.jpg` | Amber accent at its most extreme (muzzle flare on blue) | Same relationship as `ship-night`, louder. **Accent witness only.** Watermarked (Magnific). |
| `floating-port.jpg` | Sky/cloud blues; airy end of the range | Watermarked (Dreamstime). |
| `colour-palette.webp` | **Nothing. Demoted.** | Despite the name it is a scene (a mountain valley at dusk), not a swatch sheet — **and not a sea**. It sits at one hue at every depth and cannot express the bright daylight world the sea references do. Kept as a scene; **do not derive palette from it.** |
| `pirate-port.jpg` | Atmosphere and mood only — **the outlier** | **Not pixel art** (painted concept art), and dark/desaturated where the rest are bright/saturated. Do not derive palette from this one; it contradicts the daylight set. Kept because the maintainer liked the mood. |

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
