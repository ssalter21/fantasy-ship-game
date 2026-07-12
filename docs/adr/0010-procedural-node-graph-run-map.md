# ADR-0010: Procedural node-graph run map — generated topology, retrace-legal traversal, hidden encounter kinds, and a depth×zone gradient

## Status

Accepted.

Supersedes the **Topology** and **fog-of-war** decisions of [ADR-0007](0007-map-and-run-structure-zones-ports-and-encounter-kinds.md) only. ADR-0007's zones, encounter kinds, win/loss conditions, and the danger/reward-gradient *concept* survive — adapted here to graph scale. See GitHub issue #67 (synthesizing map tickets #59–#63) for the full design trail.

## Context

ADR-0007 built the vertical slice's map as a small, hand-authored set of 17 fixed points (Start, 3 ports, 12 encounters, Goal) with **no edges** — from any visited point the player could travel to any other — and **no fog of war** (every encounter's kind visible from the first frame). That shape gave every run an identical layout, made "routing" a matter of picking points off a flat list with nothing structural to plan around, exposed each encounter's kind before arrival, and expressed the danger gradient only as a coarse three-zone band plus a Ship-Battle-only "contested waters near the port" wrinkle that lost its meaning once ports could move.

The slice wanted a run that reads like charting a course across a real sea chart: a connected map with genuine branching route choices, a scale large enough that no two runs play the same, and encounters whose nature is a surprise you sail into rather than a label you read in advance — while keeping ADR-0007's zones, encounter kinds, and win/loss rules intact.

## Decision

**Topology — procedurally-generated, seeded, connected node graph.** The map is a graph of ~50 nodes joined by edges, regenerated fresh from the Sim's seed each run (same seed ⇒ identical map, per ADR-0001's determinism contract). It is grown as a **layered forward DAG, zone-by-zone**: a single Start node, then Coastal, then Open Sea, then The Deep (each zone a run of layers of 4–6 nodes), into a single Goal node. Zone is assigned by construction (which phase grew a layer), not by post-hoc graph distance. Nodes carry per-node **layer/lane** metadata (their column/row in the forward graph) so presentation can position them; Points still carry no *screen* coordinates.

- **Reachability and zero dead ends are guaranteed by construction.** A three-pass edge-wiring scheme gives every non-Goal node at least one forward edge into the next layer (no dead ends; every node can step forward toward Goal), every non-Start node at least one incoming forward edge (nothing is unreachable from Start), and then extra random forward edges for real branching. Forward out-degree per regular node is bounded 1–4 (Start is exempt — it fans out to the whole first layer). Optional **lateral** (same-layer) edges add bonus cross-routes; they are never load-bearing for reachability.
- **Ports are procedurally scattered.** Two ports per zone (6 total, plus the Start home port), each placed in a uniformly random layer within its zone's phase — an ordinary node with no special-casing, reachable or avoidable by route choice. A port **consumes** an encounter slot rather than adding a node, so the 17/17/16 per-zone point budget yields 15/15/14 = **44 encounters**.
- **Encounter kinds are drawn from a per-zone shuffled bag** sized to the zone's encounter count and split as evenly across the three kinds as a three-way division allows, so each zone's pool stays mixed.

**Traversal — retrace-legal, no longer forward-only.** Movement is constrained to a node's legal neighbors, computed by one pure seam, `run_travel_options(map, current, visited)`, that the Sim's travel gate, the UI's reachable-next affordance, and tests all share. Legal destinations from the current node are: forward out-edges (deeper layer), lateral edges (either direction), **plus** retrace along an edge to an already-**visited** node. Only the *first* arrival at an encounter fires it; revisiting is a free routing tool and never re-triggers. Landmarks (Start/Port/Goal) never fire an encounter. The Sim asserts on any submitted travel that is not a legal neighbor, matching its assert-on-driver-bug style.

**Fog-of-war — Sim-enforced hiding of encounter kind until arrival.** The whole graph and its edges are visible at once (it is a course to chart, not a dungeon to explore room-by-room), but each unvisited encounter node shows only a generic zone-tinted marker — its **kind is withheld**. This is a data contract at the Sim's event boundary, not a presentation courtesy: the run-start broadcast carries graph shape (nodes, edges, zones, layout) and the always-visible landmarks, but masks every unvisited encounter's kind. Arriving at an encounter reveals its kind (in the arrival event) and resolves it permanently; the resolved kind then stays visible as route history.

**Gradient — depth-within-zone × zone-tier, applied to all three kinds.** Difficulty and reward scale two ways that stack: the existing per-zone tier ladder, plus a new **depth-within-zone** axis — how deep into a zone's phase a node sits, normalized to a fixed range so the spread is stable regardless of how many layers a seed rolled. Depth now feeds the Ship Battle, Upgrade Offer, and Stat Trade formulas alike. This retires ADR-0007's Ship-Battle-only port-proximity rule (`port_closeness` / "contested waters" / `CONTESTED_BONUS_PER_STEP`) cleanly in favor of one coherent zone-tier × depth system.

**Tuning.** Every generation and tuning knob (node budget, port count, layer widths, out-degree bound, lateral-edge chance, kind mix, gradient per-tier/per-depth magnitudes) is a clearly-named code-level constant near the generator — no config file, no settings UI.

## Consequences

- The map now needs a seeded procedural generator and a single legality seam (`run_travel_options`); "reachable from anywhere" is gone. The generator's structural invariants (reachability, no dead ends, per-zone counts, port placement, kind-mix evenness, forward-only edges, out-degree bounds, determinism) are unit-testable at the pure `run_map_create(seed)` seam without rendering or a running session.
- The Sim tracks a **visited** set distinct from **resolved** (landmarks are visited but never resolved) and threads its seed into generation. Its run-start `Event_Run_Started` broadcasts a masked public map rather than the private one — a reversal of ADR-0007's "no fog of war."
- Encounter difficulty/reward is now a function of `(zone_tier, normalized_depth)`; the retired `port_closeness` input and its naming are gone, and `Encounter_Ship_Battle` carries a `depth` instead.
- Win = reach Goal with HP > 0; loss = 0 HP permadeath — **unchanged** (ADR-0006/0007). Encounter resolution flows (`run_start_battle`, `run_apply_upgrade_offer`, `run_apply_stat_trade`, `Event_Encounter_Resolved` / Ghost_Snapshot) are untouched except for the depth-vs-`port_closeness` input swap.
- Presentation (Variant A) draws the whole graph and its edges at once with no camera/pan, positions nodes from the layer/lane metadata, renders unvisited encounters as generic zone dots (revealing kind on visit), highlights the legal next moves (numbered, color-coded fires-vs-won't), and paints a Coastal→Open Sea→Deep background gradient. The render layer stays unit-untested (ADR-0003).
- Save/resume and meta-progression between runs remain unspecified (still an ADR-0007 gap); whether a generated map/seed is persisted for resume rides on that gap and is out of scope here. Player-facing config UI is explicitly ruled out in favor of code-level constants.
