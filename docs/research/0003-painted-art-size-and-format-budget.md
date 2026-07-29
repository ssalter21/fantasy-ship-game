# Painted art: the size and format budget for a self-contained exe

Scoped by GitHub issue [#506](https://github.com/ssalter21/fantasy-ship-game/issues/506)
(effort: sprite art, [#503](https://github.com/ssalter21/fantasy-ship-game/issues/503)).

**Question.** The exe embeds its assets and procedural rendering keeps today's art bill tiny.
Painted ship and world art is a different order of magnitude. Establish, as numbers: how
assets are embedded and what that costs at scale; what raylib can load and whether a
compressed format is on the table; what resolution the art actually needs; and what total
download is acceptable for a playtest.

Every number below is measured on this machine at commit `2884d9b`, or quoted from a primary
source. Where a number could not be verified it says so — see
[What could not be verified](#what-could-not-be-verified).

**Measurement environment.** Odin `dev-2026-05-nightly:ea5175d`, whose `vendor:raylib`
declares `VERSION :: "5.5"` (`vendor/raylib/raylib.odin:137-140`). Windows 11.

---

## 1. Answers in one place

| Question | Answer |
| --- | --- |
| Embedding mechanism | `#load` — a compile-time byte array, **verbatim, uncompressed**. 1 asset byte = 1 exe byte. |
| Today's embedded art bill | **97,086 B** (94.8 KiB) across 7 files — **5.9%** of the 1,635,840 B release exe. |
| Lossy compression on the table? | **Yes.** JPEG decodes in the pinned build — verified, not assumed. But **RGB only, no alpha**. |
| Lossless alternative to PNG? | QOI decodes, but is **22% larger** than a tuned PNG. No win. |
| GPU-compressed on the table? | **Yes.** BC1/DXT1 DDS loads, at a fixed **0.5 B/px**. Cannot be authored by raylib. |
| Resolution the art needs | **1244x700 and no more — today.** The render texture is the ceiling, not the display. |
| Real upscale on a 1080p display | **1.5429x**, bilinear. 1440p: 2.0571x. 4K: 3.0857x. |
| Documented download budget | **None exists.** Current tester download: **1,635,840 B (1.56 MiB)**. itch's hard ceiling: 30 GB. |

The single most consequential finding is §4: **authoring painted art above 1244 px wide buys
nothing under the current pipeline**, because `fullscreen_target` rasterizes every frame at
1244x700 before upscaling. The format question is cheap; the render-target question is the
one that decides the budget.

---

## 2. How assets are embedded today, and what it costs at scale

### The mechanism

Seven files reach the binary through Odin's `#load`, which reads the file at compile time into
a constant byte slice:

| Symbol | File | Bytes | Dimensions | Mode |
| --- | --- | --- | --- | --- |
| `MENU_ISLAND_PNG` | `assets/art/menu-island-day.png` | 41,012 | 400x272 | RGB, 272 colours |
| `SHIP_SPRITE_PNG` | `assets/art/ship-sprite.png` | 22,751 | 544x68 | RGBA, 82 colours |
| `PIXEL_OPERATOR_TTF` | `assets/fonts/PixelOperator.ttf` | 17,272 | — | TTF |
| `PARCHMENT_PAGE_PNG` | `assets/art/parchment-page.png` | 15,502 | 400x400 | RGBA, 5 colours |
| `UI_FRAME_BUTTON_PNG` | `assets/art/ui-frame-button.png` | 202 | 48x16 | RGBA, 4 colours |
| `UI_FRAME_PANEL_PNG` | `assets/art/ui-frame-panel.png` | 186 | 24x24 | RGBA, 4 colours |
| `UI_FRAME_CARD_PNG` | `assets/art/ui-frame-card.png` | 161 | 16x16 | RGBA, 3 colours |
| **Total embedded** | | **97,086** | 307,392 px of art | |

Sites: `presentation/art.odin:21,28,36,43,44,45` and `presentation/ui.odin:108`. `grep -rn
'#load' --include=*.odin` finds only these plus three in `forge/forge_test.odin`, which load
Odin source as test fixtures, not assets.

`assets/` on disk totals 137,136 B. The 40,050 B gap is `menu-island-night.png` (32,118 B, the
dusk variant `art.odin:20` keeps beside the day one but does not embed), three provenance notes
and the font licence. **Verified**: a 64-byte slice from the middle of each embedded PNG is
present byte-for-byte in the release exe; the same test on `menu-island-night.png` returns
false, confirming it is genuinely not shipped.

### What the mechanism costs at scale

**It costs exactly the file size, three times over, and never less.**

1. **In the binary.** `#load` is verbatim — there is no compression step and PE sections are not
   compressed. Measured: every embedded asset's bytes appear literally in the exe. So the art
   bill is *the sum of the encoded files*, and the encoder you author with is the only lever.
   Measured exe sizes at this commit:

   | Build | Command | Bytes |
   | --- | --- | --- |
   | Debug | `odin build cmd/game` | 2,016,256 |
   | Release (what ships) | `odin build cmd/game -o:speed -subsystem:windows -define:GIT_SHA=…` | **1,635,840** |

   97,086 / 1,635,840 = **5.94%** of the shipped exe is asset bytes today.

2. **In resident memory, permanently.** A `#load`ed array is read-only data in the image. It is
   paged in on first touch at `art_load` and never freed — `art_unload`
   (`presentation/art.odin:77-84`) releases the *GPU* textures, not the embedded bytes. There is
   no streaming and no unload path, by construction.

3. **In VRAM, as uncompressed RGBA8.** `art_texture` (`art.odin:59-65`) decodes to an `Image`,
   uploads, and unloads the CPU copy. `LoadTextureFromImage` uploads at the image's pixel
   format; PNG decodes to `UNCOMPRESSED_R8G8B8A8` (verified, §3), i.e. **4 B/px regardless of
   the file size**. Today: 307,392 px x 4 = **1,229,568 B (1.17 MiB)** of texture VRAM, plus
   `fullscreen_target` at 1244x700 x 4 = **3,481,600 B (3.32 MiB)** for colour alone
   (`fullscreen.odin:21`).

**The consequence for painted art.** File size and VRAM are *decoupled*: a JPEG that is 7x
smaller on disk still costs 4 B/px in VRAM. So the format choice controls the download, and the
*resolution* choice controls VRAM. They must be budgeted separately.

**A second consequence, for the release pipeline.** `scripts/release.ps1` builds a single
monolithic exe and `butler push`es it. itch's own docs say butler "diffs your build against the
previous one with an rsync-style algorithm that matches **fixed-size blocks**"
([itch.io butler docs, pushing builds](https://itch.io/docs/butler/pushing.html)). Because the
assets are inside the binary, changing one asset's *length* shifts every byte after it and
defeats fixed-block matching — a one-pixel art fix can force a near-full re-upload. And a tester
on a browser download-key link (the path `docs/distribution.md` documents) receives **the whole
exe every time** regardless; patching only helps testers using the itch app.

---

## 3. What raylib can load, and whether a compressed format is on the table

Two sources, and they disagree — which is why the empirical test matters.

### What raylib's own config says

raylib 5.5's `src/config.h` enables, for image loading:

```
#define SUPPORT_FILEFORMAT_PNG      1
#define SUPPORT_FILEFORMAT_GIF      1
#define SUPPORT_FILEFORMAT_QOI      1
#define SUPPORT_FILEFORMAT_DDS      1
```

and leaves BMP, TGA, **JPG**, PSD, HDR, PIC, KTX, ASTC, PKM and PVR commented out
([config.h @ 5.5](https://github.com/raysan5/raylib/blob/5.5/src/config.h)).

**But that is not the shipped behaviour.** The same file enables clipboard support, which
force-defines three formats back on:

```
#define SUPPORT_CLIPBOARD_IMAGE    1

#if defined(SUPPORT_CLIPBOARD_IMAGE)
    #ifndef SUPPORT_FILEFORMAT_BMP
        #define SUPPORT_FILEFORMAT_BMP 1
    #endif
    #ifndef SUPPORT_FILEFORMAT_PNG
        #define SUPPORT_FILEFORMAT_PNG 1
    #endif
    #ifndef SUPPORT_FILEFORMAT_JPG
        #define SUPPORT_FILEFORMAT_JPG 1
    #endif
    ...
#endif
```

`LoadImageFromMemory` dispatches on the `fileType` string under exactly these guards
([rtextures.c @ 5.5](https://github.com/raysan5/raylib/blob/5.5/src/rtextures.c)). So **JPEG
should load**, contrary to the commented-out line — a conclusion no one should take on trust.

### What the pinned prebuilt binary actually does

Probed directly against `vendor/raylib/windows/raylib.lib` with a throwaway Odin harness: for
each extension, `ExportImage` then `LoadImageFromMemory` on the resulting bytes, no window
opened (these are CPU-side calls). Payload: a real painted frame at 1920x1080.

| Extension | Exports? | Decodes? | Decoded pixel format | 1920x1080 painted frame |
| --- | --- | --- | --- | --- |
| `.png` | yes | **yes** | `UNCOMPRESSED_R8G8B8` / `…R8G8B8A8` | 3,001,831 B |
| `.qoi` | yes | **yes** | `UNCOMPRESSED_R8G8B8` / `…R8G8B8A8` | 2,612,609 B |
| `.jpg` / `.jpeg` | yes | **yes** | `UNCOMPRESSED_R8G8B8` — **no alpha** | **404,956 B** |
| `.bmp` | yes | **yes** | `UNCOMPRESSED_R8G8B8` | 6,220,854 B |
| `.dds` (BC1/DXT1) | no | **yes** | `COMPRESSED_DXT1_RGB` | fixed 0.5 B/px |
| `.tga` `.gif` `.ktx` `.hdr` `.psd` | no | untested / disabled | — | — |

The DDS row required a hand-built fixture: raylib cannot *write* DDS, so a minimal 64x64
BC1/DXT1 file was assembled from the format spec and fed to `LoadImageFromMemory`. It returned
`64x64 format=COMPRESSED_DXT1_RGB` from a 2,176-byte file — **the GPU-compressed path is real
and it works**.

### So: is a compressed format on the table?

**Yes, three of them, and each answers a different question.**

- **JPEG is on the table and it is the big lever** — 404,956 B against 3,001,831 B for the same
  frame, a **7.4x** reduction. Its hard limit is that it decodes to `UNCOMPRESSED_R8G8B8`:
  **JPEG cannot carry alpha.** It is viable for opaque full-frame backdrops (sky, sea, islands)
  and not viable for the galleon or her rooms, which need cutouts over what is behind them.
- **QOI is a dead end for size.** raylib's QOI (2,612,609 B) beats raylib's *own* PNG writer
  (3,001,831 B) by 13% — but a tuned PNG encoder produces **2,138,112 B** for that identical
  image, so QOI is **22% larger** than PNG done properly. Which exposes a separate trap:
  **raylib's `ExportImage` PNG writer is 40% worse than a tuned encoder.** Decode is unaffected,
  so this is purely an authoring rule — never let raylib write the shipped PNG.
- **BC1 DDS is a fixed 0.5 B/px** and is the only option that shrinks *VRAM* as well as disk
  (8x against RGBA8). At 1244x700 that is 425 KiB per plate — worse than JPEG on disk, better
  than everything in VRAM. It cannot be authored in-repo without adding a BC encoder, and it is
  lossy in a way tuned for photographs, not for a 25-swatch palette.

**Not on the table:** WebP, AVIF, and any modern codec. None appear in `config.h` at any
setting; adding one means vendoring a decoder, which conflicts with `vendor:raylib` being
maintained upstream (`docs/research/0001-rendering-library.md`).

---

## 4. What resolution the art actually needs

### The pipeline, from source

- Logical size is `WINDOW_WIDTH :: 1244`, `WINDOW_HEIGHT :: 700`
  (`presentation/presentation.odin:20,22`). Aspect 1.7771 — within 0.04% of 16:9.
- The player session allocates `fullscreen_target = rl.LoadRenderTexture(WINDOW_WIDTH,
  WINDOW_HEIGHT)` and sets it to `.BILINEAR` (`presentation/fullscreen.odin:21-24`), with the
  comment "A non-integer upscale with POINT would shimmer; BILINEAR trades a hint of softness
  for even scaling."
- `frame_begin` points every draw at that target; `frame_end` blits it with
  `letterbox_fit`'s uniform `scale = min(screen_w / 1244, screen_h / 700)`
  (`fullscreen.odin:39-45, 51-60, 70-97`).
- When fullscreen is not initialised — `--capture`, `--shot`, tests — both degrade to plain
  `Begin/EndDrawing` and draw at exact logical size (`fullscreen.odin:2-8, 52-55, 74-77`).

### The upscale factor, on real displays

Steam's Hardware & Software Survey for **June 2026** gives the primary-display distribution
([Steam Hardware Survey](https://store.steampowered.com/hwsurvey/Steam-Hardware-Software-Survey-Welcome-to-Steam)).
Applying `letterbox_fit` to the top entries:

| Display | Share | Upscale | Bound by | Crisp art would need | Letterbox bars |
| --- | --- | --- | --- | --- | --- |
| 1920x1080 | **51.12%** | **1.5429x** | height | 1919x1080 | 1 px |
| 2560x1440 | 21.44% | 2.0571x | height | 2559x1440 | 1 px |
| 2560x1600 | 5.64% | 2.0579x | width | 2560x1441 | 159 px |
| 3840x2160 | 4.95% | 3.0857x | height | 3839x2160 | 1 px |
| 3440x1440 | 3.09% | 2.0571x | height | 2559x1440 | 881 px |
| 1920x1200 | 2.56% | 1.5434x | width | 1920x1080 | 120 px |
| 1366x768 | 2.32% | 1.0971x | height | 1365x768 | 1 px |

**Half of players see a 1.543x bilinear upscale; three-quarters see 1.54x or 2.06x. None of
them see an integer scale**, which is why `fullscreen_init` chose BILINEAR over POINT.

### And therefore — the finding that governs the budget

**The render texture is the ceiling, not the display.** Everything is rasterized into a fixed
1244x700 target and *then* upscaled. So a painted backdrop authored at 1920x1080 is downsampled
to 1244x700 on the way in and blurred back up to 1080p on the way out: **it costs 2.4x the bytes
and delivers no additional sharpness whatsoever.**

Three exits, and the composite-architecture ticket has to pick one before any art is authored:

1. **Accept the softness.** Author at ≤1244x700. Cheapest in every dimension; the shipped screen
   stays 1.54x soft for half of players. Note this is what already happens to the existing
   sourced art, in spite of `art.odin:9` authoring at native resolution and forcing `.POINT`
   filtering — that POINT upload is undone downstream by the BILINEAR blit of the whole frame.
2. **Size `fullscreen_target` to the monitor.** Then art wants 1920x1080 / 2560x1440 / 3840x2160
   and the numbers in §5 apply at those rows. Cost is not the art: every hit-test and layout
   constant in `presentation/` is written against 1244x700, and `SetMouseOffset` /
   `SetMouseScale` exist precisely so they need not change (`fullscreen.odin:47-60`).
3. **Split the layers.** Keep UI chrome and the cutaway at logical resolution — map #503 already
   scopes chrome out — and blit only the painted backdrop directly to the framebuffer at native
   resolution, outside the render texture. Gets the sharpness where painted art shows it most,
   for one plate's worth of bytes.

**One consequence worth flagging to the regression story** that map #503 lists as unspecified:
because `--capture` and `--shot` bypass `fullscreen_target`, every PNG in `docs/ui/shots/` and
every hash in `docs/ui/shot-manifest.txt` is at exact 1244x700. **The shot gallery does not show
what players see** — it cannot photograph the upscale, exactly as it could not photograph the
alpha bug `fullscreen.odin:84-91` documents.

### The galleon's own footprint

Not isolated — see [What could not be verified](#what-could-not-be-verified). The available
bound: differencing two `--hull-sheet` tiles shot from different eyes, everything that moves
when the camera orbits fits in **904x562 px** of the 1244x700 frame (72% x 80%). That includes
the sea and horizon, which also move, so the hull alone is smaller. Sizing painted galleon
plates needs a real segmentation against the chosen composite.

---

## 5. The size budget, measured

### Method

The repo's own painted style references (`docs/ui/references/style/*.jpg`, 8 images — the
reference set `art.odin:16` names as the art direction) were cover-cropped and Lanczos-resized
to each candidate resolution and encoded in each candidate format. Rates are the mean of the 8.

**Caveat that cuts one way only:** the references are JPEGs, so the decoded pixels carry
high-frequency ringing that a lossless encoder must reproduce faithfully. This inflates the
**PNG-24** column — treat it as an upper bound. The quantized and JPEG columns are largely
unaffected, since both discard exactly the kind of detail that artefacts are made of.

### One full-frame painted plate, mean of 8 references

| Format | 1244x700 | 1920x1080 | 2560x1440 | 3840x2160 |
| --- | --- | --- | --- | --- |
| PNG-24 (RGB, tuned) | 1,114 KiB (1.31 B/px) | 2,210 KiB (1.09) | 3,391 KiB (0.94) | 6,073 KiB (0.75) |
| PNG-8, 256 colours | 406 KiB (0.48) | 815 KiB (0.40) | 1,261 KiB (0.35) | 2,266 KiB (0.28) |
| PNG-8, 64 colours | 259 KiB (0.30) | 511 KiB (0.25) | 780 KiB (0.22) | 1,375 KiB (0.17) |
| **PNG-8, 32 colours** | **198 KiB (0.23)** | **385 KiB (0.19)** | **590 KiB (0.16)** | **1,026 KiB (0.13)** |
| PNG-8, 16 colours | 143 KiB (0.17) | 273 KiB (0.13) | 407 KiB (0.11) | 694 KiB (0.09) |
| JPEG q90 | 212 KiB (0.249) | 389 KiB (0.192) | 572 KiB (0.159) | 993 KiB (0.123) |
| JPEG q85 | 173 KiB (0.203) | 318 KiB (0.157) | 470 KiB (0.130) | 813 KiB (0.100) |
| JPEG q75 | 131 KiB (0.155) | 244 KiB (0.121) | 362 KiB (0.101) | 625 KiB (0.077) |
| BC1 DDS (fixed) | 425 KiB (0.500) | 1,012 KiB (0.500) | 1,800 KiB (0.500) | 4,050 KiB (0.500) |
| BMP / raw RGBA (VRAM) | 3,402 KiB (4.0) | 8,100 KiB (4.0) | 14,400 KiB (4.0) | 32,400 KiB (4.0) |

Dithered and undithered quantization measured identical to the byte at every colour count and
resolution — the palette size is what costs, not the dither.

### The palette law is the compression budget

`docs/ui/style-guide.md` lists **25 unique hex swatches**, and the `create-assets` skill states
"The palette is one flat roster, and it is law… no asset may reach outside it"
(`.claude/skills/create-assets/SKILL.md`). A roster-conformed asset therefore fits a
**32-colour PNG-8**, and that row is the one to budget against: **0.23 B/px at logical
resolution — 5.7x cheaper than PNG-24 and cheaper than JPEG q90, while staying lossless and
keeping alpha.**

This is the finding that most changes the shape of the answer. **Because the palette is law,
the interesting format question is not "lossy or lossless" — it is "indexed or truecolour".**
Painted art that obeys the roster is indexed art wearing a different name, and indexed PNG beats
every lossy option on this list *and* carries the alpha the galleon needs. JPEG's 7.4x only
materialises for art that spends thousands of colours, which the style guide forbids.

Corroboration from the repo's own shipped files, which are roster-conformed already:

| Asset | B/px | Colours |
| --- | --- | --- |
| `parchment-page.png` (RGBA) | 0.097 | 5 |
| `menu-island-night.png` (RGB) | 0.295 | 104 |
| `menu-island-day.png` (RGB) | 0.377 | 272 |
| `ship-sprite.png` (RGBA) | 0.615 | 82 |
| A whole procedurally rendered game screen, `--shot build` | **0.107** | 1,366 |

That last row is worth its own sentence: **an entire shipped frame at 1244x700, PNG'd, is 93,105
B** — roughly what the *entire* current asset bill costs. It is also 12x cheaper per pixel than
the painted-reference PNG-24 rate, which is the size of the gap between what this game draws
today and what painted art costs.

### Sprites that need alpha

JPEG is unavailable here (RGB only, verified §3). Measured on a painted reference at
representative sprite sizes:

| Size | PNG-32 (truecolour + alpha) | JPEG q88 + 1-bit alpha PNG |
| --- | --- | --- |
| 600x400 | 352 KiB | 65 KiB |
| 1244x830 | 1,194 KiB | 191 KiB |
| 1920x1280 | 2,262 KiB | 341 KiB |

The two-file colour+mask scheme works and is ~6x smaller, at the cost of a hard-edged cutout and
two assets per sprite. **A 32-colour PNG-8 with alpha is the better answer** given the palette
law — same order of magnitude as the JPEG scheme, one file, real alpha, lossless. These figures
are a worst case: the rects are filled edge to edge, whereas a real cutout is mostly transparent
and compresses far better.

### What a full inventory costs

Extrapolated as rate x area from the measured rates, over inventories sized from map #503's own
scope (backdrop plates; galleon plates at the 904x562 bound; room paints at 250x180, for the 8
berths and 4 exposed structures). **These are extrapolations, not measured composites.**

| Inventory | Target | Pixels | PNG-24 | PNG-8/32col | JPEG q90 | BC1 | VRAM if all resident |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Lean: 4 frames + 1 galleon + 12 rooms | 1244x700 | 4.6 Mpx | 5.7 MiB | **1.0 MiB** | 1.1 MiB | 2.2 MiB | 17.4 MiB |
| Mid: 8 frames + 3 galleon + 20 rooms | 1244x700 | 9.5 Mpx | 11.8 MiB | **2.1 MiB** | 2.2 MiB | 4.5 MiB | 36.1 MiB |
| Broad: 12 frames + 6 galleon + 40 rooms | 1244x700 | 15.5 Mpx | 19.3 MiB | **3.4 MiB** | 3.7 MiB | 7.4 MiB | 59.0 MiB |
| Lean | 1920x1080 | 10.9 Mpx | 11.3 MiB | 2.0 MiB | 2.0 MiB | 5.2 MiB | 41.4 MiB |
| Mid | 1920x1080 | 22.6 Mpx | 23.4 MiB | 4.1 MiB | 4.1 MiB | 10.8 MiB | 86.0 MiB |
| Broad | 1920x1080 | 36.8 Mpx | 38.3 MiB | 6.7 MiB | 6.7 MiB | 17.6 MiB | 140.4 MiB |
| Mid | 3840x2160 | 90.2 Mpx | 64.5 MiB | 11.2 MiB | 10.6 MiB | 43.0 MiB | 344.1 MiB |
| Broad | 3840x2160 | 147.2 Mpx | 105.3 MiB | 18.3 MiB | 17.3 MiB | 70.2 MiB | 561.6 MiB |

**Read the bolded column.** A roster-conformed painted inventory at logical resolution puts the
exe between **2.6 and 5.0 MiB** all-in (1.54 MiB of code plus 1.0–3.4 MiB of art) — a 1.6x to
3.1x growth on today's 1.56 MiB, and still under 5 MiB. The same inventory in PNG-24 at 4K is
**105 MiB and 562 MiB of VRAM**, which is a different project. The format and resolution
choices span a 100x range, and the palette law already picks most of the winning end.

---

## 6. What total download size is acceptable for a playtest

### What the prior work actually decided

The `effort:playtest-distribution` label covers five closed issues — #43 (map), #44 (SHA stamp),
#45 (`scripts/release.ps1`), #46 (itch.io + smoke test), #47 (ADR + runbook) — landing
[ADR-0009](../adr/0009-playtest-distribution.md) and [`docs/distribution.md`](../distribution.md).

**None of them states a size budget, a size target, or a size constraint.** Read in full:
ADR-0009's Decision and Consequences, its "Out of scope (deliberate)" list, the runbook, and all
five issue bodies including #46's six acceptance criteria. The word does not appear. The pipeline
was built to prove delivery works, not to fit a budget: "separate 'does delivery work?' from 'is
the game good?'" (#46).

So there is no acceptable-download figure to report, and inventing one would be a preference
dressed as a finding. What follows is what *is* established.

### The current distribution, measured

- `scripts/release.ps1` builds `dist/game.exe` with `-o:speed -subsystem:windows -define:GIT_SHA=<sha>`
  and `butler push`es the `dist/` directory to `<ITCH_TARGET>:windows`. `dist/` holds **only
  `game.exe`** — the script's own docstring records that "Odin's `vendor:raylib` links
  statically on Windows, so the produced exe needs no raylib DLL beside it… There is therefore
  no DLL to bundle into `dist/`."
- **A tester's entire download is one file: 1,635,840 B (1.56 MiB)** at this commit.
- The itch project is Restricted per ADR-0009, and `https://teapy.itch.io/fantasy-ship-game`
  returns **HTTP 404** without a download key — consistent with that setting, and the reason no
  published build size could be read off the page.

### What itch.io actually imposes

| Constraint | Value | Source |
| --- | --- | --- |
| butler build ceiling | "the itch.io backend will reject builds with a total **uncompressed size that exceeds 30GB**" | [itch.io butler docs](https://itch.io/docs/butler/pushing.html) (first-party) |
| Web uploader per file | 1 GB default, raisable to 2 GB | itch.io community threads, incl. [butler FAQ](https://itch.io/t/46291/uploading-large-games-faq) by butler's author. Not first-party docs — treat as indicative |
| butler per-file | "butler is a more advanced uploader and has no such technical limits" | same FAQ |
| Upload efficiency | fixed-size-block rsync diff + Brotli; "a 300MB build might only send 120MB" | [itch.io butler docs](https://itch.io/docs/butler/pushing.html) |

**itch.io imposes no constraint that binds here.** Every scenario in §5 — including the 105 MiB
worst case — is three orders of magnitude under 30 GB. The distribution channel is simply not
the limiting factor, and the budget is therefore a judgement about tester experience, not a
platform ceiling.

### What the numbers do bound

The one hard, channel-side fact worth carrying into the decision: **a download-key tester
re-downloads the whole exe on every build** (`docs/distribution.md` — the tester's step is
opening a browser link). butler's patching only serves testers running the itch app. So the exe
size is paid per build per tester, not once, which argues for the indexed-PNG end of §5 on
iteration-speed grounds even though nothing about it is a hard limit. A 3 MiB exe stays in
"click and it's there" territory; a 105 MiB one makes every art fix a wait.

---

## What could not be verified

Stated plainly rather than estimated:

1. **The galleon's isolated on-screen footprint.** The `--hull-sheet` background is a sky/sea
   gradient that changes with the camera, so differencing two eyes bounds hull *and* sea
   together at 904x562 px. No flat-background render exists to segment against. §4's figure is
   an upper bound, not the hull.
2. **GIF decoding.** Enabled in `config.h` at 5.5, but raylib has no GIF writer, so no fixture
   could be produced by the roundtrip method. Untested — and irrelevant to this question
   (256 colours, animation-oriented).
3. **KTX / PVR / ASTC / PKM.** Commented out in `config.h`; not probed. If a GPU-compressed
   container beyond DDS is ever wanted, this needs re-testing against the pinned lib.
4. **The published build's size on itch.io.** The project is Restricted and the page 404s without
   a key. The 1.56 MiB figure is a local release build at this commit, not a read of what is
   currently served.
5. **PNG-24 rates for cleanly authored painted art.** The reference set is JPEGs, whose decode
   artefacts inflate lossless encoding. The PNG-24 column is an upper bound; the exact
   over-statement is unmeasured because no cleanly authored painted asset exists in-repo yet.
6. **An acceptable download size.** No such number exists in the repo, in ADR-0009, in the
   runbook, or in issues #43–#47. It is a decision that has not been made, not a fact that was
   hard to find.
7. **Whether raylib 6.0 changes any of this.** `docs/research/0001-rendering-library.md` notes
   6.0 bindings merged upstream on 2026-07-07, but this machine's Odin
   (`dev-2026-05-nightly`) pins **5.5**. Every format result above is 5.5's. An Odin upgrade
   should re-run the probe in §3.

---

## Consequences / handoff

- **Format ruling to take into the composite-architecture ticket: indexed PNG-8, ≤32 colours,
  authored with a tuned encoder — not raylib's.** It is lossless, keeps alpha, measures 0.23 B/px
  at logical resolution, beats JPEG q90, and follows automatically from a palette law the project
  already enforces. JPEG stays available as a fallback for any opaque full-frame plate that
  genuinely needs thousands of colours; DDS/BC1 stays available if VRAM rather than download ever
  becomes the constraint.
- **Never let `rl.ExportImage` write a shipped asset** — measured 40% larger than a tuned PNG for
  identical pixels. Authoring-side rule; worth a line in the `create-assets` skill.
- **The resolution question is a render-target question and it blocks the art.** Under today's
  pipeline, art above 1244x700 is bytes spent for no sharpness. Deciding between the three exits
  in §4 has to precede authoring, because it moves the budget by 2.4x (1080p) or 9.5x (4K) in
  area, and it is the difference between a 3 MiB exe and a 100 MiB one.
- **The embedding mechanism does not need to change** for any scenario in §5. `#load` is verbatim
  and uncompressed, so the file *is* the cost — but at the indexed-PNG rate a full painted
  inventory lands the exe under 5 MiB, well inside what a monolithic self-contained binary
  carries comfortably. ADR-0009's self-containment commitment survives painted art intact.
- **What still needs deciding, and by whom:** the acceptable download figure (a maintainer call —
  the numbers above bound the options, itch.io does not); the render-target exit (§4); and the
  galleon's real footprint, once the composite is settled.
- **Feeds:** the composite-architecture and asset-inventory tickets under
  [#503](https://github.com/ssalter21/fantasy-ship-game/issues/503), and the regression-story gap
  that map lists as unspecified — §4's note that `--capture` cannot photograph the upscale bears
  directly on it.
