# A consistent painted galleon at a fixed perspective: where the art comes from

Scoped by GitHub issue [#505](https://github.com/ssalter21/fantasy-ship-game/issues/505)
(effort: sprite art, [#503](https://github.com/ssalter21/fantasy-ship-game/issues/503)).

**Question.** What can produce a consistent painted galleon at a fixed perspective, *repeatably*?
The art must be revisable: when the look changes, the same ship has to come back at the same
perspective, or every screen in the game drifts apart. PixelLab — the only image MCP wired into
this repo — is pixel-art only and cannot serve a painted look.

Four candidates, each answered on four axes: **(a)** can it hold a fixed perspective across
regenerations? **(b)** can it produce a *matched set* — hull plus room interiors that read as one
ship? **(c)** what does one revision cost in money and turnaround? **(d)** what does it cost per
month?

Prices and model names were checked against first-party pricing pages and model cards in **July
2026**; where a figure could not be verified from the owning source it is marked so.

---

## Recommendation

**Structure-conditioned local diffusion, with the control image rendered by the game itself.** It
is the only candidate of the four where "same perspective" is a *mechanical* property rather than a
statistical one: the geometry is supplied as an image, so it cannot drift, and the look is carried
separately by prompt, model and seed — which is exactly the axis that has to stay revisable. Every
other candidate re-derives the perspective from scratch on each revision.

Two qualifications, both concrete, both below:

1. **The normal render is *not* directly usable as a ControlNet input.** Three mismatches
   (encoding, coordinate space, face-facing) plus a fourth practical one (the backdrop is in the
   frame). All four are small changes in `presentation/ship_paint.odin` and
   `presentation/ship_cutaway.odin` — but they are changes, not zero.
2. **Current-generation models take *depth* and *edges*, not normals.** Normal-map conditioning
   peaked with SD 1.5 and SDXL; the Flux / SD3.5 / Qwen-Image generation ships Canny, Depth, Pose
   and Soft-Edge and no normal mode. The repo's *wireframe* render is nearer to a usable control
   image than its normal render is, and a depth mode — which does not exist yet — is about ten
   lines given what `ship_lit` already does.

---

## 1. Hosted image models

### What exists now

| Model | Price per image | Source |
|---|---|---|
| Gemini 3 Pro Image ("Nano Banana Pro") | $0.134 at 1K/2K; $0.24 at 4K | [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing) |
| Gemini 3.1 Flash Image | $0.045 (0.5K) / $0.067 (1K) / $0.101 (2K) / $0.151 (4K) | ibid. |
| Gemini 3.1 Flash Lite Image | $0.0336 at 1K | ibid. |
| Gemini 2.5 Flash Image | ~$0.039 | ibid. |
| Imagen 4 | Fast $0.02 / Standard $0.04 / Ultra $0.06 | ibid. |
| GPT Image 2 (1024²) | Low $0.006 / Medium $0.053 / High $0.211 | [OpenAI image generation guide](https://developers.openai.com/api/docs/guides/image-generation) |
| GPT Image 1.5 (1024²) | Low $0.009 / Medium $0.034 / High $0.133 | ibid. |
| GPT Image 1 Mini (1024²) | Low $0.005 / Medium $0.011 / High $0.036 | ibid. |
| FLUX.2 [max] | from $0.07 | [BFL pricing](https://docs.bfl.ai/quick_start/pricing) |
| FLUX.2 [flex] | from $0.05 | ibid. |
| FLUX.2 [pro] | from $0.03 text-to-image, from $0.045 editing | ibid. |
| FLUX.2 [klein] 9B | from $0.015 | ibid. |
| FLUX.1 Kontext [pro] / [max] | $0.04 / $0.08 | ibid. |

Two things about that table matter more than the numbers.

**First: BFL no longer sells structural conditioning.** FLUX.1 Depth and FLUX.1 Canny were
announced as part of FLUX.1 Tools ([BFL, Nov 2024](https://bfl.ai/blog/24-11-21-tools)) and are
absent from the current pricing page — the FLUX.1 rows there are Kontext, 1.1 [pro] and Fill only
([docs.bfl.ai](https://docs.bfl.ai/quick_start/pricing)). The open-weight checkpoints remain on
Hugging Face. So the one hosted API that ever offered depth/canny conditioning as a first-party
endpoint has withdrawn it; hosted conditioning today means renting someone else's ControlNet
deployment, which puts it in §2, not here.

**Second: what the hosted models offer instead is *reference images*, and that is a different
guarantee.** FLUX.2 "can reference up to 10 images simultaneously with the best character, product,
and style consistency available today" ([BFL, FLUX.2 announcement](https://bfl.ai/blog/flux-2)).
Gemini's image models take "Up to 10 images of objects with high-fidelity to include in the final
image", "Up to 4 images of characters to maintain character consistency" and "Up to 3 images to be
used as style references" ([Gemini image generation
docs](https://ai.google.dev/gemini-api/docs/image-generation)); Gemini 3 Pro Image takes up to 6
object and 5 character references. Those keep *identity* stable. Neither vendor documents any
depth, normal or edge control input, and neither documents a geometric guarantee.

### (a) Fixed perspective across regenerations — **no**

This is the decisive finding, and both vendors say it themselves.

OpenAI, on its own image API: *"Despite improved instruction following, the model may have
difficulty placing elements precisely in structured or layout-sensitive compositions."* And on
masks — the strongest spatial hint the API accepts — *"Masking with GPT Image is entirely
prompt-based. The model uses the mask as guidance, but may not follow its exact shape with complete
precision."* ([OpenAI image generation
guide](https://developers.openai.com/api/docs/guides/image-generation).)

Google's image-generation documentation contains no spatial-control mechanism at all: composition
is described in prose in the prompt, and no depth/normal/edge input is supported ([Gemini image
generation docs](https://ai.google.dev/gemini-api/docs/image-generation)).

Feeding the shipped shaded frame back in as an edit/reference image gets *close* to the framing —
it is the best a hosted model can do — but "close" is the failure mode this ticket exists to
prevent. `GALLEON_EYE` is five knobs dialled to a tenth of a degree
(`presentation/cutaway/galleon.odin`: yaw 55.75°, dist 6.92, height 0.0, look 1.14, fov 55.24), and
the cutaway's room faces are hit-tested against a projection derived from exactly those numbers
(`cutaway.galleon_room_at`, `galleon_project`). Art whose perspective is *approximately* that
projection breaks the drag targets, not just the look.

### (b) A matched set — **partly, and it degrades on revision**

Reference-image conditioning is genuinely good at this: generate the hull, then pass the hull as a
style + object reference for each of the eight room interiors. Consistency of *palette, brushwork
and material* is what these features are built for.

The problem is the revision cycle. Change the look and the anchor image changes, so every
downstream asset is regenerated against a new anchor — and because the anchor itself was generated,
not authored, its own drift compounds. There is no artefact in the loop that is *stable by
construction*; the ship's identity lives in a PNG that gets replaced. Qwen's own release notes for
Qwen-Image-Edit-2511 name the failure directly, listing "mitigate image drift, improved character
consistency" as the things that needed fixing ([Qwen-Image-Edit-2511 model
card](https://huggingface.co/Qwen/Qwen-Image-Edit-2511)) — drift across edits is a known, named
property of this family, being actively reduced rather than eliminated.

### (c) Cost per revision

Assume one revision = one matched set. The map fixes the inventory's upper bound at **8 berths**,
"at most 4 exposed as fixed weather-deck structures … the rest below-deck" (#503), so a set is
roughly **1 hull + up to 8 room interiors + backdrop pieces ≈ 12 images**. Landing a usable one
takes several attempts; at **8 attempts per asset ≈ 100 generations per pass**:

| Route | Per pass (~100 gens at ~1 MP) |
|---|---|
| GPT Image 2, High | ~$21 |
| Gemini 3 Pro Image, 1K/2K | ~$13 |
| FLUX.2 [max] | ~$7 |
| Gemini 3.1 Flash Image, 1K | ~$7 |
| Imagen 4 Standard | ~$4 |
| FLUX.2 [pro], text-to-image | ~$3 |

Turnaround: minutes to an hour of wall clock for the generation itself. **The money is not the cost
here — the cost is that the perspective has to be re-won each pass.**

### (d) Per month — **$0 idle**

All three vendors are pay-as-you-go with no subscription floor. BFL states "No subscriptions, no
seat fees. Only pay for what you generate" ([bfl.ai/pricing](https://bfl.ai/pricing)); Google's
image models list "Free tier: not available" but are billed per image ([Gemini API
pricing](https://ai.google.dev/gemini-api/docs/pricing)); OpenAI bills per image with no seat fee
([pricing](https://developers.openai.com/api/docs/pricing)). Google's Batch tier halves the rate —
Gemini 3 Pro Image at $0.067 instead of $0.134 at 1K/2K — which suits an offline asset bake well.

---

## 2. Local diffusion with structure conditioning

### The mechanism, and why it answers the question

ControlNet adds a trainable copy of the diffusion encoder that takes a **spatial conditioning
image** — depth, edges, normals, pose — and injects it into the frozen base model, so the output's
*structure* is supplied rather than inferred ([Zhang, Rao & Agrawala, *Adding Conditional Control
to Text-to-Image Diffusion Models*, arXiv:2302.05543](https://arxiv.org/abs/2302.05543)).

That is a categorically different guarantee from every other candidate here. The perspective is not
described, remembered or referenced — it is **handed to the model as pixels**. Regenerate with a new
prompt, a new base model, a new style LoRA, a new palette, and the silhouette, the deck lines and
the room openings land in the same pixels, because the control image did not change. **The look and
the geometry become independently revisable**, which is precisely the property #505 is asking for.

And this repo is unusually well placed for it, exactly as #503 says: `Ship_Paint` already has
`.Normals` ("+x red, +y green, +z blue, each negative dark") and `.Wires`
(`presentation/ship_debug.odin`), and `--hull-sheet` photographs every mode from six named eyes at
full frame size (`presentation/hull_sheet.odin`; `WINDOW_WIDTH :: 1244`, `WINDOW_HEIGHT :: 700`).
A control image of the *exact shipped frame* is one flag away.

### Is the normal render directly usable? **No — four concrete mismatches**

lllyasviel's ControlNet 1.1 normal model is explicit that renders are welcome: *"the Normal 1.1 can
interpret real normal maps from rendering engines as long as the colors are correct (blue is front,
red is left, green is top)"*, following ScanNet's protocol
([ControlNet-v1-1-nightly README](https://github.com/lllyasviel/ControlNet-v1-1-nightly)). The
reference encoding is a plain symmetric remap — `norm_rgb = ((norm + 1) * 0.5) * 255`, no channel
reorder and no sign flip ([`utils/utils.py`,
baegwangbin/surface_normal_uncertainty](https://raw.githubusercontent.com/baegwangbin/surface_normal_uncertainty/main/utils/utils.py)).

Against that protocol, the repo's `.Normals` paint fails on four counts:

**(i) The encoding is a diagnostic fold, and the sign is unrecoverable.** `ship_lit` maps each axis
through

```odin
axis :: proc(v: f32) -> u8 {
    return u8(clamp(v > 0 ? 235 * v : 70 * -v, 0, 255))
}
```

(`presentation/ship_paint.odin`). Both signs climb *upward from 0*, so a perpendicular surface is
channel 0 and a channel value of 50 could be `v = +0.21` or `v = −0.71`. The protocol needs 128 for
perpendicular and a monotone ramp across the whole range. This is not a colour-space conversion that
can be applied to the PNG afterwards — the information is already gone. It has to be a **new paint
mode**, not a post-process.

**(ii) The normals are world space; the protocol wants camera space.** Repo axes are "x = ship
length (stern −x, bow +x), y = up, z = beam" and the port side (−z) is the cut side
(`presentation/cutaway/galleon.odin`). `GALLEON_CAM_YAW :: 55.75` means the camera sits off the port
bow — position `(≈5.92, 0, ≈−3.90)` looking at `(0.2, 1.14, 0)` — so the view axis is a general
rotation of the world frame, not an axis swap. Green happens to line up (world +y is up in both).
Red happens to line up in *sign* — the code comment "the bow looms on the left" confirms world +x
projects to image-left, which is where the protocol puts red — but only approximately, because the
yaw is 55.75° and not 90°. Blue is inverted outright: world +z points *away* from this camera, and
the protocol's blue is "front", toward it.

The fix is not per-channel flips; it is to encode against the camera basis, which
`ship_paint_view` already caches (`ship_eye`) and `galleon_view_from` already builds:

```
R = (dot(n, −right)  + 1) * 0.5 * 255   // protocol X = image-left
G = (dot(n,  up)     + 1) * 0.5 * 255   // protocol Y = up
B = (dot(n, −forward)+ 1) * 0.5 * 255   // protocol Z = toward the camera
```

*Unverified:* whether the protocol's "red is left" means the +R half-space faces image-left or
image-right is worth confirming with one test render before trusting it — an inverted horizontal
axis is the classic ControlNet-normal failure and lllyasviel's phrasing is prose, not a formula.

**(iii) The face-facing rule is deliberately backwards for this purpose.** `ship_facing` returns the
raw winding normal under `.Normals` on purpose — *"Turning it toward the eye is what makes a face
wound backwards paint the same colour as a right one — which would leave that mode unable to show
the one defect it is turned on to find"* (`presentation/ship_paint.odin`). A control image needs the
opposite: the *visible* side's normal, flipped toward the eye, or every interior surface the cutaway
looks into reports as facing away. So the diagnostic mode and the control mode want opposite
behaviour from the same procedure — another reason this is a distinct mode rather than a reuse.
(`ship_inboard_dusk` is already correctly bypassed under `.Normals`, so that one is free.)

**(iv) The frame is not ship-only.** `draw_ship_cutaway` calls `draw_ship_sky`, `draw_ship_sea` and
`draw_ship_wake` before the 3D pass and `draw_ship_waterline` after it, under *every* paint mode
(`presentation/ship_cutaway.odin`) — the hull-sheet comment even notes that "the 2D backdrop behind
her lands where it does in play". A control render therefore carries a sky and a sea whose roster
swatches would be read as normals. A control mode has to suppress the 2D passes and emit the ship
against a flat background (or with alpha), so the conditioning speaks only about the hull.

**Verdict:** a *normal render in the form `ship_debug.odin` currently emits* is **not** directly
usable. A conforming one is a small, well-localised addition — one `Ship_Paint` variant, one branch
in `ship_lit`, one guard in `draw_ship_cutaway`, and the hull sheet picks it up for free because it
iterates `for paint in Ship_Paint`.

### But normals are the wrong target for current models

Normal conditioning is a *previous-generation* control mode:

| Base model | Normal mode available? | Modes actually shipped |
|---|---|---|
| SD 1.5 | **yes** — `control_v11p_sd15_normalbae` | depth, normal, canny, lineart, softedge, mlsd, seg, pose, scribble ([README](https://github.com/lllyasviel/ControlNet-v1-1-nightly)) |
| SDXL | **yes** — union model, mode 12 | Openpose, Depth, Canny, Lineart, AnimeLineart, Mlsd, Scribble, Hed, Pidi (Softedge), Teed, Segment, **Normal** ([xinsir/controlnet-union-sdxl-1.0](https://huggingface.co/xinsir/controlnet-union-sdxl-1.0)) |
| SD 3.5 Large | no | Blur, Canny, Depth only ([Stability AI](https://stability.ai/news-updates/sd3-5-large-controlnets), [model card](https://huggingface.co/stabilityai/stable-diffusion-3.5-controlnets)) |
| Qwen-Image (20B) | no | canny, soft edge, depth, pose ([InstantX/Qwen-Image-ControlNet-Union](https://huggingface.co/InstantX/Qwen-Image-ControlNet-Union)); Qwen-Image-Edit-2509 adds native "depth maps, edge maps, keypoint maps, and more" ([model card](https://huggingface.co/Qwen/Qwen-Image-Edit-2509)) |
| FLUX.2 [dev] (32B) | no | no native structural conditioning documented on the [model card](https://huggingface.co/black-forest-labs/FLUX.2-dev); third-party union ControlNets exist |

So the practical reading of "the repo can emit structure renders for free" is **not** "use the
normal mode". It is:

- **`.Wires` is nearly a lineart/canny/mlsd/scribble control image today** — it is the loft's own
  edges, which is exactly what those modes eat, and it needs only the backdrop suppressed and the
  strokes rendered dark-on-light. Canny and lineart are supported by *every* base model in the
  table.
- **A `.Depth` mode does not exist and should.** It is the best-supported mode across every
  current base, and it is trivial here: `ship_lit` already receives the surface and `ship_eye` is
  already cached, so depth is `distance(point, ship_eye)` normalised over the hull's extent. And
  depth from a renderer is *explicitly* sanctioned: ControlNet 1.1's depth model "can work on real
  depth map from rendering engines", was trained "not over-fitted to one preprocessor" and handles
  "even … real depth created by 3D engines"
  ([README](https://github.com/lllyasviel/ControlNet-v1-1-nightly)).
  *Caveat:* that guarantee is stated for the SD 1.5 model. SD 3.5's depth ControlNet was trained on
  DepthFM output ([model card](https://huggingface.co/stabilityai/stable-diffusion-3.5-controlnets))
  and Qwen's union on depth-anything
  ([model card](https://huggingface.co/InstantX/Qwen-Image-ControlNet-Union)); neither states
  render-depth compatibility, so a normalisation pass matching the estimator's output distribution
  is the open risk. Cheap to test — one render, one generation.
- **Two modes at once is normal practice.** Flux ControlNet Union Pro 2.0 conditions on Canny,
  Depth, Soft Edge, Pose and Grayscale simultaneously; depth + canny together is the standard
  tight-structure recipe. The repo can emit both from the same frame.

### (a) Fixed perspective — **yes, mechanically**

The control image *is* the perspective. `--hull-sheet` already guarantees byte-identical pixels
across runs (it is a shot-manifest entry hashed by `scripts/shot.py`, and
`presentation/hull_sheet.odin` states "two runs must write byte-identical pixels — the check
re-renders it"), so the conditioning input is reproducible by the same machinery that already
guards the procedural render. That is the strongest form of this property available in any
candidate: the perspective is version-controlled Odin source, not an artefact anyone can drift.

### (b) A matched set — **yes, and this is the underrated part**

Every asset in the set is conditioned on a render of *the same hull from the same eye*. The room
interiors are not "matched to" the hull by resemblance; they are cut from it. And a **style LoRA**
trained once on the chosen look, applied over the control image, pins the *painterly* half the way
the control image pins the geometric half — so "the look changed" becomes "swap the LoRA and
re-run", with the perspective untouched by construction. Qwen-Image's ControlNet stack explicitly
supports LoRA alongside conditioning ([Qwen-Image ControlNet
Union](https://huggingface.co/InstantX/Qwen-Image-ControlNet-Union)).

This also offers something to the map's open item, *"the regression story for painted art"*: if the
generation is a committed ComfyUI workflow JSON plus a fixed seed plus a committed control render,
then the whole asset bake is a reproducible build step, and the existing hash-a-render discipline
extends to it. *Unverified:* bit-exact reproducibility of diffusion output across driver or GPU
changes — I found no first-party statement guaranteeing it, and floating-point kernel selection
makes it doubtful. Treat "same seed ⇒ same image" as true within one fixed software/hardware stack
only.

### (c) Cost per revision — **effectively free in money; hours in setup, minutes thereafter**

Marginal cost of a local pass is electricity. Two routes:

- **On the machine in front of us.** This box has an **AMD Radeon RX 9070** (queried via
  `Win32_VideoController`; WMI reports 4 GB because `AdapterRAM` is a 32-bit field — the RX 9070
  Series carries "16GB of GDDR6 memory" on up to 64 RDNA 4 compute units,
  [AMD](https://www.amd.com/en/newsroom/press-releases/2025-2-28-amd-unveils-next-generation-amd-rdna-4-architectu.html)).
  AMD's **ROCm 7.2.1** supports "Radeon™ GPUs (9000 & select 7000 Series)" on native
  Windows, with **PyTorch** the only listed framework there — ONNX Runtime is Linux-only
  ([ROCm on Radeon, native Windows compatibility](https://rocm.docs.amd.com/projects/radeon/en/latest/docs/compatibility/native_windows/native_win_compatibility.html)).
  So local generation is supported, but on the second-class rail of a CUDA-shaped ecosystem, and
  16 GB means the 20B/32B-class models need quantisation. **This is the real cost of the local
  route, and it is paid in setup friction, not dollars.** *Unverified:* generation latency for a
  20B model on an RX 9070 under ROCm/Windows — no first-party benchmark found. Do not assume it.
- **Rented, if the local rail bites.** Replicate publishes $0.001525/sec for an H100 and
  $0.000975/sec for an L40S ([replicate.com/pricing](https://replicate.com/pricing)). At an assumed
  20 s/image that is ~$0.03 per generation — about **$3 for a 100-generation pass**, cheaper than
  every hosted per-image route in §1 *and* structure-conditioned. Training a style LoRA is ~20
  minutes of the same H100, ≈$1.83.

Turnaround for a revision once the pipeline exists: **minutes**. Re-render the control sheet, change
the prompt or LoRA, re-run the workflow, composite. That is the number that decides this ticket.

### (d) Per month — **$0**

No subscription, no seat fee, weights on disk. Hardware is already owned.

### Licensing — **check this before picking a base model**

The game ships and (per the itch.io page) is a public product, so the *model* licence matters, not
just the output licence:

- **FLUX.2 [dev]** is under the **FLUX Non-Commercial License**
  ([model card](https://huggingface.co/black-forest-labs/FLUX.2-dev)). Its Outputs clause is
  permissive — *"We claim no ownership rights in and to the Outputs"* and *"You may use Output for
  any purpose (including for commercial purposes), except as expressly prohibited herein"* — but
  Non-Commercial Purpose is defined to exclude *"revenue-generating activity"* and applies to use
  of the *model*
  ([LICENSE-FLUX1-dev §1.c, §2.d](https://github.com/black-forest-labs/flux/blob/main/model_licenses/LICENSE-FLUX1-dev)).
  Running the model to bake assets for a sold game sits in the gap between those two clauses. **Not
  a technical question — get it decided, or avoid the model.** BFL sells a self-hosted commercial
  licence.
- **FLUX.2 [klein]** is **Apache 2.0**, as is the FLUX.2 VAE ([BFL](https://bfl.ai/blog/flux-2)).
- **Qwen-Image / Qwen-Image-Edit** are **Apache 2.0**
  ([model card](https://huggingface.co/Qwen/Qwen-Image)) — the cleanest licence in the field, 20B,
  with a union ControlNet and native depth/edge conditioning.
- **SD 3.5 + its ControlNets** are under the Stability AI Community License: free commercially
  below **$1M** annual revenue ([Stability AI](https://stability.ai/news-updates/sd3-5-large-controlnets)).
- **SDXL** — the only base with a *normal* control mode — is OpenRAIL++, commercially usable, but
  is an older base and will read less painterly than the 2025–26 models.

**On licence and capability together, Qwen-Image (Apache 2.0, depth + canny + soft edge + pose) is
the default pick; SD 3.5 Large is the fallback; SDXL union is the option if normals turn out to
matter more than base-model quality.**

---

## 3. Commissioned art from a game artist

### (a) Fixed perspective — **yes on the first delivery, expensively on every revision**

An artist handed the shaded render, or a wireframe/normal print of it, will match the perspective —
this is ordinary paint-over work and humans are good at it. The problem is that the perspective
lives in the artist's hand, not in a file. Every revision re-buys it, and every revision is a
negotiation.

### (b) A matched set — **the strongest of the four**

This is what a human artist is uniquely good at: nine images that read as one ship, with consistent
material logic, light and wear. No other candidate matches it on quality of the *set*.

### (c) Cost per revision

I could not verify per-piece commission quotes from a primary source — professional rates are
quoted privately and no first-party aggregate is published. The closest verifiable anchors are
marketplace rate pages. Upwork publishes, for its own marketplace, a median hourly rate of **$25**
for illustrators with a typical range of **$15–$30**, and **$25–$40/hr** for concept artists
([Upwork illustrator rates](https://www.upwork.com/hire/illustrators/cost/); *fetched from search
snippets of upwork.com — direct fetch was blocked, treat as indicative*).

At 12 assets × ~6 h at $25/h that is **≈$1,800 per full pass**, and a partial revision is not
proportionally cheaper because re-establishing consistency across the set is most of the work.
**Turnaround is days to weeks per round**, plus brief-and-review latency. That is the killer for an
effort whose whole premise is "the look will change".

### (d) Per month — **$0 idle**, but no accumulated leverage: pass *n+1* costs the same as pass 1.

---

## 4. Hand-painting in-house

### (a) Fixed perspective — **yes**, by painting over the shipped render. Same as §3: repeatable by hand, not by machine.

### (b) A matched set — **yes**, subject to the painter's skill.

### (c) Cost per revision

No cash, all calendar. The same ~72 h of work; the market value of that time, per BLS, is $54.27/hr
mean for Special Effects Artists and Animators (SOC 27-1014), $112,870 mean annual, May 2025
([BLS OEWS](https://www.bls.gov/oes/current/oes271014.htm); *bls.gov blocked direct fetch — figure
taken from a bls.gov-restricted search of the same page, treat as indicative*) — so **≈$3,900 of
labour value per pass**, and weeks of wall clock.

### (d) Per month — **$0 cash**; the cost is that no other ticket moves while a pass is in flight.

---

## Side by side

| | Fixed perspective | Matched set | One revision | Per month |
|---|---|---|---|---|
| **Hosted models** | **No.** Reference images pin identity, not geometry; OpenAI documents difficulty with "layout-sensitive compositions" and no vendor accepts a structural control map | Partly — good style/identity carry, but the anchor is itself generated, so drift compounds | $3–$21 per ~100-generation pass; minutes–hour | $0 |
| **Local + structure conditioning** | **Yes, mechanically.** The control image *is* the perspective, rendered by the game, byte-reproducible | **Yes** — every asset cut from the same hull render; a style LoRA pins the look separately | ~$0 local / ~$3 rented; **minutes** once built. Setup is hours–days (ROCm on Windows, 16 GB, quantisation) | $0 |
| **Commissioned** | Yes on delivery; re-bought each revision | **Best** | ≈$1,800 and days–weeks (indicative) | $0 idle, no leverage |
| **Hand-painted** | Yes | Yes | ≈72 h ≈ $3,900 of time (indicative); weeks | $0 cash |

---

## Consequences / handoff

- **The recommendation is local structure-conditioned diffusion, on depth + edges, not normals.**
  It is the only candidate where a revision costs minutes and the perspective cannot drift, and it
  is the only one whose per-revision cost *falls* as the pipeline matures.
- **Prerequisite work, all in `presentation/`, all small.** Add a control-render paint mode (or two:
  `.Depth`, and `.Normal_Map` in `(v+1)/2` camera-space encoding if SDXL union is chosen); flip
  `ship_facing` toward the eye under it; guard the sky/sea/wake/waterline passes in
  `draw_ship_cutaway`; render the ship against a flat background or with alpha. The hull sheet picks
  new modes up for free (`for paint in Ship_Paint`).
- **First experiment, and it is cheap.** One control render of `GALLEON_EYE` at 1244×700 → Qwen-Image
  + union ControlNet (depth) → one painted galleon. That single run answers the two live unknowns at
  once: whether render-derived depth conditions cleanly on an estimator-trained ControlNet, and
  whether an RX 9070 under ROCm/Windows is a workable rail.
- **Decide the FLUX licence question before it becomes load-bearing.** FLUX.2 [dev] is the strongest
  open model and the murkiest licence for a sold game; Qwen-Image is Apache 2.0 and nearly as good.
- **Do not discard the human.** The recommendation is not "no artist" — it is that the artist's time
  is better spent on *the look* (one reference painting, or the LoRA training set) than on
  re-establishing the same perspective twelve times per revision.
- **Feeds:** #509 and #510 (blocked by this ticket), and the map's open items on the regression story
  and the ongoing content cost, both of which change shape if the asset bake becomes a reproducible
  build step.
