# Spec 0001 — The Parchment Treasure Chart

**Status:** Build-ready. This is the destination artifact of the `effort:treasure-chart` wayfinding map
([#334](https://github.com/ssalter21/fantasy-ship-game/issues/334)). It consolidates seven resolved
decisions into one implementation doc a build session can execute in a single push.

**What it is:** reskin the Chart map as a **full-window aged-parchment treasure map** — a torn-edge paper
page filling the window, nodes drawn as hand-inked doodles keyed to encounter type, an **X marking the
treasure**, sepia dotted routes laid out so **no two ever cross**, and a **pixel-art ship that sails along
the route** when the player picks their next destination. It *replaces* the current blue nautical-chart
look (graticule water, steel ink, amber snap) on this screen.

**Mode:** this map was spec-first — every decision below is locked. Producing shipping assets and the live
`cmd/game` implementation are the build (see [Out of scope](#out-of-scope)). By-eye tuning numbers are
called out inline as *build-time dials*, not open decisions.

### Source decisions (detail lives in the ticket, not restated here)

| # | Ticket | Locks |
|---|--------|-------|
| [#335](https://github.com/ssalter21/fantasy-ship-game/issues/335) | Screen model | overlay-not-screen, unfurl gesture, sail-then-leave |
| [#336](https://github.com/ssalter21/fantasy-ship-game/issues/336) | Parchment page & border | aged page, torn edge, sourced texture + procedural live layer |
| [#337](https://github.com/ssalter21/fantasy-ship-game/issues/337) | Map ink language | Idiom-A doodles, node states, dotted routes, no amber |
| [#338](https://github.com/ssalter21/fantasy-ship-game/issues/338) | Zero-crossing layout | constrain the generator (planar by construction) |
| [#339](https://github.com/ssalter21/fantasy-ship-game/issues/339) | The sailing ship | PixelLab 8-dir sprite, ride the route, 0.5s ease |
| [#343](https://github.com/ssalter21/fantasy-ship-game/issues/343) | Travel juice | foam+stipple spume, bob+heel, arrival ink bloom, no sound |
| [#342](https://github.com/ssalter21/fantasy-ship-game/issues/342) | Fog-of-war | per-node hiding + light visited recession, no regions |

---

## 1. Screen model & navigation (#335)

The parchment map is a **reskin of the existing raised-chart overlay**, not a new screen.

- **No new top-level screen enum.** Navigation stays driven by the Sim's `Phase`
  (`core/sim/sim.odin:36`). `home_loop` (`cmd/game/build_surface.odin:742`) remains the owner; the
  parchment map is the reskinned "raised" state of today's chart overlay
  (`chart_raise`/`chart_target`/`chart_settle`).
- **Centred page, Build cutaway framing all four sides** — dominant but not window-edge-to-edge, consistent
  with the centred-chart layout already shipped. The existing `chart_offset`
  (`build_surface.odin:722`) already centres `MAP_AREA` horizontally and slides it up; keep that framing.
- **Two-state toggle, no peek.** The chart tab (`home_chart_tab_rect`, `build_surface.odin:730`) is the
  "unfurl the map" gesture. Old press-drag swipe stays retired.
  - **Enter:** tap the tab → map unfurls (`chart_target = 1`).
  - **Leave:** tap the tab again **or click anywhere on the visible Build margin** → rolls down
    (`chart_target = 0`). *Click-outside-to-dismiss on the four-sided margin is a new affordance to add.*
  - **Default on arriving at Home:** rolled-down (Build showing), `chart_raise` starts at 0.
- **Ship panel / refit reachability:** the Build surface frames the map while it's up but is **inert for
  refit** there; refit is one roll-down away. The `Awaiting_Refit` / `build_surface_loop` model
  (`main.odin:182-183`) is **untouched** by this work — it is a separate Sim phase and surface.

### Destination selection — sail-then-leave (couples #335 ↔ #339)

Today selection is **one-shot**: clicking a reachable node returns `Command_Travel_To{node_id}` the *same
frame* (`build_surface.odin:769-783`). This spec **replaces that** with a sail phase:

1. Player clicks the X-marked / reachable node on the fully-unfurled map (`chart_raise>=1 && chart_target>=1`).
2. `home_loop` enters a **sailing sub-state** (input-swallowed, like the existing mid-flip continue at
   `build_surface.odin:789-792`): store a **pending destination** + an **eased progress field**, and *do not*
   return the command yet.
3. Play #339's ship-sail on the still-unfurled map.
4. On arrival (or skip), return `Command_Travel_To{node_id = pending_dest}`.

The sail must be **skippable** (a click or Space snaps to arrival) so it is never a forced wait.

> **Build note — where the sail state lives.** Chart overlay state is currently *loop-local* in `home_loop`
> (`chart_raise`, `chart_target` are locals, `build_surface.odin:752-755`), fine because it re-tweens each
> frame. The sail phase spans frames and must **survive across `home_loop` calls**, so add fields to
> `Game_State` (alongside `visited`/`positions`/`voyage_map`, `main.odin:96-98`): e.g.
> `sail_pending: Maybe(voyage.Node_ID)` and `sail_progress: f32`. Model the tween on the existing
> `chart_settle` scaffolding (`GetFrameTime` dt + `linalg.lerp`, `build_surface.odin:705`).

---

## 2. The parchment page & border (#336)

The visual anchor everything is inked onto. **Warm aged paper, never a dark navy vignette** (the retired look).

- **Ground:** Parchment `#EBD9A6`, filling the page. Aged with Sand/Cliff mottling and a couple of faint warm
  tea-stains (`Cliff #B98A50` / `Rock #7E5C3A` at low alpha).
- **Register:** 16-bit — hard edges, flat blocks, no gradients. Authored low-res (~256–512px long edge),
  upscaled **POINT** (same pipeline as the font and the shipped menu / chart-table island backgrounds).
- **The framing edge is the whole frame:** a **rough torn deckled paper rim** at the page boundary,
  deepening outward **Sand `#D2A968` → Cliff `#B98A50` → Rock `#7E5C3A`**, irregular (not a clean rectangle).
  **No rope band, no compass-rose corners** (mocked and rejected). This torn edge **replaces the dark
  vignette** — remove the `draw_vignette` call (`build_surface.odin:364`) on this surface.
- **Typography:** one face, **Pixel Operator** at the **32 / 16** scale. Title inked 32px `Ink #12333F`,
  letterspaced via `DrawTextEx` `spacing`; secondary Ink-muted 16px. **Hierarchy by colour, not weight**
  (Ink → Ink-muted → Faded-ink).

Mock (approved): https://claude.ai/code/artifact/4f7ed0cd-49b5-4afb-8f1c-dc03962a229f

---

## 3. Map ink language — Idiom A "Cartographer's hand" (#337)

Fine sepia **hairline doodles** drawn as raylib primitives on top of the parchment (the live layer stays
procedural, except the ship — see §5). Small hand-wobble; crisp, not noisy.

**Ink weight (this revises #336's "doodles = faded hairline" note):** node **identity** inks in **strong
sepia — Rock `#7E5C3A`** (Trunk `#875F38` acceptable for warmth). **Faded-ink `#9C8A63`** is reserved for the
**recessive** register only (unexplored `?` buoys, charted-not-yet routes). Identity reads before recession.

### The doodle set — one mark per identity

The current classifier is `node_mark` → `Node_Mark :: enum{Home, Island, Dock, Diamond, Buoy}`
(`view.odin:143,156`). Node types come from `Node_Kind :: enum{Start, Encounter, Haven}`
(`voyage.odin:214`); an `Encounter`'s sub-identity is its opening `Stage_Kind :: enum{Fight, Offer, Trade,
Shop, Reward}` (`stage.odin:27`), and **`Shop` is the only revealing kind** (`voyage_stage_kind_reveals`,
`stage.odin:361`). Map each to a doodle:

| Source | Doodle | Means |
|--------|--------|-------|
| `Node_Kind.Start` | **home port** — pier + hut + pennant | you weigh anchor here |
| `Node_Kind.Haven` | **treasure island + the coral X** (`#E1552B`) | the run's end — the X marks the treasure |
| `Encounter` revealed · `Stage_Kind.Shop` | **anchor** | a landfall / port you can route to |
| `Encounter` revealed · `Stage_Kind.Fight` | **crossed cutlasses** | a battle |
| `Encounter` revealed · `Stage_Kind.Offer` | **scroll** | take-it-or-leave-it |
| `Encounter` revealed · `Stage_Kind.Trade` | **balance scales** | a trade |
| `Encounter` revealed · `Stage_Kind.Reward` | **treasure chest** | cargo & coin |
| `Encounter` masked (`encounter = nil`) | **`?` buoy** — dotted, Faded-ink | hidden until reached (most nodes) |

> **Build note.** Today `Node_Mark` collapses all revealed encounters to `Diamond`. Split `Diamond` by the
> revealed `Stage_Kind` so cutlasses/scroll/scales/chest render distinctly; keep `Home`/`Island`/`Buoy`.
> The X is the **only spend of coral (`#E1552B`) on the page** — it rides the Haven and nothing else.

### Node states — ink treatment layered over any doodle

Reachability comes from `voyage.voyage_travel_options(voyage_map, current_node_id, visited)`
(`view.odin:244`); `visited` from `state.visited[]`.

- **Charted (seen, not reachable):** plain strong-ink doodle.
- **Reachable now:** a **Sea-deep `#1786BC`** dashed ring (parchment's interactive tone). *Replaces today's
  steel ring at `view.odin:304-313`.*
- **Reachable · unknown:** the Sea-deep ring **plus a short coral danger tick** at the buoy's shoulder
  (reuse `draw_danger_tick`).
- **Visited:** doodle drawn faded (~0.3 alpha) — a memory.
- **Current (ship stands here):** the **pixel ship sprite** rests on the node (owned by §5). This supersedes
  #337's "inked sepia glyph" and today's amber ring+dot (`view.odin:319-321`). **No amber.**

### Route trails — dotted sepia, hand-wavy, weight says state

Edge state is `edge_is_sailable` / both-endpoints-visited today (`view.odin:257-264`).

- **Sailable now:** bold sepia **dashes** (weight ~3) from the ship to each reachable node.
- **Already sailed:** **solid** sepia ink line (weight ~3) — the wake left behind.
- **Charted, not yet:** faint **Faded-ink dots** (weight ~2, sparse).
- **Curve:** gently **hand-wavy** (quadratic bezier + perpendicular hand-wobble), not ruled-straight. Nodes
  sit lane-adjacent after §4, so routes are short and the wobble reads without tangling.

**No amber anywhere on the map.** How the player *confirms* a destination is the build's call within §1's
sail-then-leave; the ink language does not add an amber affordance.

Prototype (approved, Idiom A): https://claude.ai/code/artifact/edcd87b6-6225-49d7-8a73-0b5043459c1c

---

## 4. Zero-crossing layout (#338)

Guarantee **zero route crossings** by **constraining the generator**, not by render-time repositioning
(which can only *reduce* crossings — a `C₄/K₂,₂` between adjacent layers crosses for every lane ordering).
`compute_node_positions` (`view.odin:18`) stays unchanged: `x = layer` column, `y = lane` row.

The constraint is localized to `core/voyage/generation.odin` (`voyage_map_create`, `generation.odin:54`),
in the edge-wiring step 5 (`generation.odin:190-251`):

1. **Monotone forward wiring** — tile each next layer's lane axis into contiguous, ordered blocks (one per
   parent, sharing boundary children). Ordered blocks ⇒ no lane inversion ⇒ zero forward crossings, while
   keeping branching + full coverage. Lands at the forward picks `generation.odin:205-237` (where lane
   indices `v := b0 + rand.int_max(...)` are chosen).
2. **Laterals restricted to adjacent lanes** (`i ↔ i+1`) — no node sits between the endpoints, so a straight
   same-layer segment overlaps nothing. Lands at the lateral loop `generation.odin:241-251`
   (`voyage_add_edge` at `LATERAL_EDGE_CHANCE 0.15`).
3. **Monotone in-guarantee** so the out-degree cap never orphans a node.

"Connected nodes adjacent" falls out for free (short routes — good for the ship arc in §5).

**Proven:** prototype over 200 maps (~52 nodes each) — RANDOM avg 140.7 crossings → CONSTRAINED **0.00, max
0**, full connectivity preserved. Detail + runnable prototype: `docs/research/0002-zero-crossing-chart-layout.md`
and `docs/research/assets/0002-planar-proto.py` (merged in [#341](https://github.com/ssalter21/fantasy-ship-game/pull/341)).

---

## 5. The sailing ship (#339)

The ship is a **PixelLab 8-direction pixel-art sprite** — deliberately the **one raster on the inked page**,
a little vessel *on* the map rather than a mark drawn *in* it. (Maintainer's call over the ink-glyph
recommendation.) **This revises #336/#337:** the resting current-node marker **is this sprite** (facing a
default heading), not a procedural glyph; everything else on the live layer stays procedural ink.

- **Size/style:** ~1.3× node radius, sits on a **faint parchment chip** so routes don't muddy under it.
  **No amber**, at rest or sailing.
- **Frames:** 8 baked directional frames (N, NE, E, SE, S, SW, W, NW).

### Motion — replaces today's amber snap (`view.odin:319-321`)

1. **Sail-then-leave phase** (per §1): `home_loop` gains a pending-destination + eased progress field
   (`Game_State`, see §1 build note), modelled on `chart_raise`/`chart_settle` (`GetFrameTime` dt). Plays the
   sail, *then* returns `Command_Travel_To`.
2. **Rides the drawn route:** the sprite follows the **same hand-wavy bezier** the route trail is drawn on,
   current node → selected node.
3. **Orient to heading — 8-way snap:** face the curve tangent quantised to the nearest 45°.
4. **Timing: ease-in-out, 0.5s.** Snappy, weighted at both ends.
5. **Wake fills solid:** the leg being sailed draws **solid sepia behind the sprite** and **dashed ahead** —
   the line converts sailable-dash → sailed-solid *as the sprite passes*. Other reachable dashes dim during
   the sail.
6. **Skippable:** a click or Space snaps to arrival.
7. **On arrival:** `current_node_id` commits to the destination, the leg is permanently solid-ink wake,
   reachable rings clear and recompute from the new node, the sprite rests there as the current marker.

Prototype (approved, pixel sprite / sail / ease-in-out 0.5s / wake-fills-solid):
https://claude.ai/code/artifact/63880dfa-3f29-4c4f-b222-d1bbff302700

---

## 6. Travel juice (#343)

On-map polish layered on §5's locked sail. **No amber.**

1. **Spume — foam flecks + sepia stipple (both):** pale-parchment **foam flecks** flung off the bow (drift +
   fade in ~0.5s) *over* the solid wake, **and** faded-ink (`#9C8A63`) **sepia stipple** settling *into* the
   wake behind the sprite. Transient — **not** a permanent mark; the solid sepia wake stays the only lasting
   line. *Density: build-time dial.*
2. **Sprite life — bob + heel ("rock"), sailing and at rest:** gentle vertical **bob** + **heel** (roll into
   travel direction) while sailing; a **subtle idle rock continues at rest** on the current node. Overlay on
   the baked 8-way frame (the heading snap is unchanged). *Amplitudes: build-time dial — swell, not jitter.*
3. **Arrival flourish — ink bloom on every arrival:** a small **sepia ink ripple** blooms outward from the
   node (~0.6s, fades) — "the ink just set." **No page-settle** (re-litigates the chart-raise motion; reads
   seasick — rejected). *X-glint on landing the Haven: optional build-time nicety, not mandated.*
4. **Sound — fully deferred to the build.** No cues specified here (this is a visual spec). The build owns
   whether a sail/arrival cue exists at all.

Prototype (approved): https://claude.ai/code/artifact/86fede5d-772c-43fa-a19f-6ff3933a7ba7

---

## 7. Fog-of-war (#342)

**Per-node hiding is the whole fog-of-war treatment**, plus a **light faded-ink recession keyed to
`visited`**. **No region/territory layer.**

- The Sim **broadcasts the entire map at voyage start** and masks only *encounter identity*
  (`encounter = nil`), drawn as the **`?` buoy** (§3). That buoy **is** the fog — it is the whole of what the
  Sim hides. Identity reveals per node on `Event_Arrived_At_Node` (`sim.odin:277`); shops/ports read from
  turn one (`voyage_encounter_reveals`, `sim.odin:502`).
- **No `hidden` flag, no region/layer/distance concept** exists in the Sim, so the parchment does **not**
  distinguish charted-vs-uncharted *areas*. "Unexplored" = a charted stop whose contents aren't known yet.
- **Light recession on top** (keeps a uniform chart from reading flat): keyed off the client's real
  `visited` overlay (maintained in dispatch, `main.odin:221`) — sailed trail inks strong (`Rock #7E5C3A`),
  road-not-yet-sailed recedes toward Faded-ink `#9C8A63`. **Recession, not concealment** — every node stays
  legible; every reveal the Sim grants (turn-one ports, the destination X) stays visible.
- **Ruled out — Option A (undrawn/hazier territory ahead):** fights the Sim; would erase the turn-one X and
  visible ports. Off the table on the model, not taste.

*Recession strength: build-time dial* (from "barely" to a fuller fade). Prototype:
https://claude.ai/code/artifact/efadb9d4-b8c2-48af-b88b-b28fbc13c250

---

## 8. Palette reference (roster colours only)

| Element | Swatch |
|---|---|
| Page ground | Parchment `#EBD9A6` |
| Mottle / stains | Sand `#D2A968`, Cliff `#B98A50`, Rock `#7E5C3A` |
| Torn edge (outward) | Sand `#D2A968` → Cliff `#B98A50` → Rock `#7E5C3A` |
| Node identity ink (strong) | Rock `#7E5C3A` (Trunk `#875F38` for warmth) |
| Recessive ink (unexplored, charted-not-yet) | Faded-ink `#9C8A63` |
| Reachable ring / interactive tone | Sea-deep `#1786BC` |
| The X, coral danger tick, Haven glint | Coral-red `#E1552B` — the one warm accent the page spends |
| Title / subtitle type | Ink `#12333F` / Ink-muted `#4C7385` |
| **Amber** | **Absent everywhere on this screen** |

---

## 9. Assets

Split per #336: **static page furniture is sourced (PixelLab), the moving live layer stays procedural.**

| Asset | Approach | Notes |
|---|---|---|
| **Parchment page** (ground + mottle + tea-stains) | **PixelLab texture**, embedded | one background texture, like the menu / chart-table island. ~256–512px long edge, POINT-upscaled. |
| **Torn deckled edge** | **PixelLab texture**, embedded | irregular rim, Sand→Cliff→Rock; may be baked into the page texture or a separate overlay. |
| **Ship sprite** | **PixelLab 8-direction sprite**, embedded | 8 baked headings, ~1.3× node radius, sits on a faint chip. The one raster on the live layer. |
| Node doodles (home port, island+X, anchor, cutlasses, scroll, scales, chest, `?` buoy) | **Procedural** raylib ink | Idiom-A hairlines, strong sepia. |
| Routes, rings, danger tick, X, spume, ink bloom | **Procedural** raylib | live layer, generated per run. |
| Type | Existing **Pixel Operator** at 32/16 | already embedded (`ui.odin:45`). |

**Why the split is safe:** the page/edge is never interactive, so a sourced texture can't clash with chrome;
the "draw the chart procedurally" guidance still governs the moving layer that could. Byte cost ~150KB/texture,
trivial against the self-contained exe (ADR-0009).

**Embed idiom** (matches the shipped menu island, `cmd/game/art.odin`): compile-time
`PARCHMENT_PAGE_PNG :: #load("../../assets/art/parchment-page.png")` → `[]u8`; GPU-load after `InitWindow`
via a loader alongside `menu_art_load` (`art.odin:32`) —
`rl.LoadImageFromMemory(".png", raw_data(bytes), i32(len(bytes)))`, `rl.LoadTextureFromImage`,
`rl.SetTextureFilter(tex, .POINT)`; unload with `rl.UnloadTexture`. Bytes live under `assets/art/`; provenance
recorded next to the asset per the `assets/<kind>/` + licence-neighbour precedent. Producing the shipping
assets themselves is the build (Out of scope of the spec — use the `create-assets` skill / PixelLab MCP).

---

## 10. Concrete code surface

Grouped by file, with the current anchors and what changes.

### `core/voyage/generation.odin` — zero-crossing constraint (§4)
- `voyage_map_create` (`:54`), edge-wiring step 5 (`:190-251`). Add monotone-block forward wiring at the
  forward picks (`:205-237`) and restrict laterals to adjacent lanes (`:241-251`). Lanes are assigned at
  materialization (`:93-108`). No change to `Map`/`Node` shape.

### `core/voyage/voyage.odin` — model (read-only reference)
- `Node{id, zone, kind, encounter, layer, lane, depth}` (`:238`), `Node_Kind{Start, Encounter, Haven}`
  (`:214`), `Map{nodes, edges: [][]Node_ID}` (`:252`). Sub-identity via `Stage_Kind` (`stage.odin:27`),
  revealing kind `voyage_stage_kind_reveals` (`stage.odin:361`). **No schema change** — the reskin reads the
  existing model.

### `cmd/game/view.odin` — the whole chart reskin (§2, §3, §5, §6, §7)
- `draw_map_water` (`:193`) → **replace** with the parchment page (sourced texture blit + procedural
  recession). Retire the blue depth gradient + graticule (`MAP_GRID_PITCH`, `CHART_GRID`).
- `node_mark` / `Node_Mark` (`:143,156`) → **split `Diamond`** into the four revealed `Stage_Kind` doodles;
  `node_appearance` (`:110`) → re-ink to the Idiom-A doodle set + strong-sepia/faded-ink weights.
- Reachable ring styling (`:304-313`) → **steel → Sea-deep `#1786BC`** dashed ring; keep `draw_danger_tick`.
- Route drawing (`:257-264`) → three states in sepia, hand-wavy bezier; visited-recession.
- Current-node amber ring+dot (`:319-321`) → **replace** with the resting **ship sprite**.
- Add: the sailing sprite render + wake-fills-solid + spume + arrival ink bloom.

### `cmd/game/build_surface.odin` — screen model + sail phase (§1, §5)
- `home_loop` (`:742`), chart overlay locals (`:752-755`), `chart_settle` (`:705`), `chart_offset` (`:722`),
  tab rect (`:730`), toggle points (`:779-781`, `:832`), input-swallowed continue (`:789-792`).
- Add **click-outside-on-Build-margin → `chart_target = 0`**.
- Replace **one-shot selection** (`:769-783`, returns `Command_Travel_To` same frame) with the **sail-then-
  leave sub-state**: stash pending dest + progress in `Game_State`, swallow input, tween the sprite, return
  the command on arrival/skip.
- Remove the `draw_vignette` call on this surface (`:364`); the torn edge is the new framing signal.

### `cmd/game/art.odin` — assets (§9)
- Add `#load` embeds + a loader/unloader for the parchment page, torn edge, and 8-dir ship frames, mirroring
  `menu_art_load`/`menu_art_unload` (`:32,40`), POINT filter, unload on shutdown.

### `cmd/game/main.odin` — state + dispatch (unchanged model)
- Add `sail_pending`/`sail_progress` to `Game_State` (near `visited`/`positions`/`voyage_map`, `:96-98`).
- `visited` dispatch on `Event_Arrived_At_Node` (`:221`) is unchanged.
- **Refit is untouched:** `build_surface_loop` for `.Awaiting_Refit` (`:182-183`) is a separate phase/surface.

### `core/sim/sim.odin` — unchanged
- `Phase` (`:36`), `Command_Travel_To{node_id}` (`:144`), `Event_Arrived_At_Node{node}` (`:277`), the
  encounter mask (`voyage_encounter_reveals`, `:502`). The sail phase is **client-side** in `home_loop`; the
  Sim still receives the same `Command_Travel_To` it does today, just later in the frame sequence.

---

## 11. Ordered build sequence

Each step is independently verifiable in the running game (`run-game` skill).

1. **Zero-crossing generator** (`generation.odin`, §4). Land the constraint; verify against the research
   prototype's crossing count (expect 0). Pure model change — the old chart renders it fine, routes just
   stop crossing. *Ship this first: it's isolated and de-risks the layout the ship animation depends on.*
2. **Parchment page** (§2, §9): source + embed the page + torn-edge textures; replace `draw_map_water` and
   remove `draw_vignette`. Verify the warm page fills the window with the torn rim, no navy vignette.
3. **Ink language** (§3): re-ink nodes to the Idiom-A doodle set (split `Diamond` by `Stage_Kind`), strong-
   sepia/faded-ink weights, Sea-deep reachable rings, three route states, hand-wavy curve. Verify each node
   type + state reads correctly (no amber). Includes the visited recession (§7).
4. **Ship sprite at rest** (§5, §9): source + embed the 8-dir sprite; replace the amber current-node marker
   with the resting sprite on a faint chip. Verify it sits on the current node facing a default heading.
5. **Sail-then-leave** (§1, §5): add `Game_State` sail fields, convert one-shot selection into the input-
   swallowed sail sub-state, ride the bezier, 8-way heading snap, 0.5s ease, wake-fills-solid, skippable.
   Verify a click sails the ship along the route then travels; Space/click skips.
6. **Screen-model polish** (§1): click-outside-Build-margin dismiss; confirm the tab toggle + rolled-down
   default still read.
7. **Travel juice** (§6): foam + sepia stipple spume, bob + heel (sailing and idle), arrival ink bloom. Tune
   the build-time dials by eye. No sound.
8. **Pass** against this spec + the approved prototypes; tune recession strength, spume density, and rock
   amplitude by eye per the style guide.

---

## Out of scope

- **Final asset production** — generating the shipping parchment page, torn edge, and 8-direction ship sprite.
  This spec fixes the *approach* (PixelLab, embed idiom) and points at approved mockups; producing the assets
  is a build step (use `create-assets` / PixelLab MCP).
- **Sound** — deferred entirely to the build (§6).
- **Any change to the refit / `Awaiting_Refit` surface or the Sim's travel contract** — untouched here.

### Build-time dials (by-eye, not open decisions)

Recession strength (§7) · spume density (§6) · bob/heel amplitude (§6) · rolled-down-vs-unfurled default on
arriving Home (§1) · optional Haven X-glint (§6).
