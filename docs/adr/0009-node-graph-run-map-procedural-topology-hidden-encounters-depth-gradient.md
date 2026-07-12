# ADR-0009: Node-graph run map — procedural connected topology, hidden encounters, and depth gradient

## Status

Accepted. Supersedes ADR-0007's **Topology**, **Layout**, **Ports**, and **Danger and reward gradient** sections. ADR-0007's surviving decisions — three zones (Coastal → Open Sea → The Deep), the three encounter kinds (Ship Battle / Upgrade Offer / Stat Trade), win-on-reaching-Goal-with-HP>0, and permadeath-only loss — carry forward unchanged. Encounter-on-arrival survives but is refined (see below).

## Context

ADR-0007 gave the vertical slice a small, hand-placed, *open* map: ~12 points on a 2D canvas with no edges, travel-anywhere from any visited point, every point (and its encounter kind) visible from the start — no fog of war. That was deliberately the non-procedural, non-graph shape the PRD scoped for the slice.

Map effort #59 (a wayfinder chartering session, with design tickets #60–#63) supersedes that topology. The run map becomes a **procedurally-generated connected node graph**, regenerated fresh each run, scaled up from 12 to ~50 points, with each node's encounter kind hidden until the player arrives. Zones, encounter kinds, and the danger/reward-rises-with-progress concept survive from ADR-0007, adapted to the new scale and graph shape. This ADR records the decisions those tickets resolved. It produces the design; implementation is regular dev work afterward.

All map-generation parameters are code-level named constants (node counts, zone boundaries, encounter-kind mix, port count, lane width, etc.) — no config file and no player-facing settings UI.

## Decision

### Topology — procedural connected graph (was: open, travel-anywhere; #60)

The map is a **layered forward-directed acyclic graph**, generated fresh per run and reproducible from a seed (`core:math/rand`). Nodes are arranged in layers (4–6 wide); edges only ever run from layer *i* to layer *i+1*. A three-pass edge-wiring algorithm guarantees, **by construction**, that every node is on some Start→Goal path and that there are zero dead ends. On top of that guaranteed spine, each node gets 0–3 extra random forward edges (out-degree 1–4) to produce **real branching** — multiple viable Start→Goal routes, not one critical path threaded with cosmetic detours.

Zone is assigned by **three sequential generation phases** — grow Coastal, then continue Open Sea from it, then The Deep into Goal — not by a post-hoc graph-distance calculation.

### Movement — bidirectional along edges, encounters fire once (was: implied travel-anywhere; refined by #62)

Travel follows edges (no more travel-to-any-point). Movement is **not** forward-only: the player may travel *back* along an edge to any already-visited node, as well as forward into new territory. The generated graph is unaffected — edges are still only ever *created* forward; what this adds is that walking an existing edge in reverse is legal at runtime.

Revisiting a node **never re-triggers its encounter**. An encounter fires exactly once, on first arrival, with no option to decline (as in ADR-0007); the only way to avoid one entirely is to route around its node. Landmarks (Start, Port, Goal) carry no encounter and never trigger one.

### Ports — procedural, consume node slots (was: fixed 4, one per zone; #61)

`PORTS_PER_ZONE = 2` → **6 ports** across the three zones, plus the Start/home port (7 port-like locations total). Each port is placed in a random layer *within its zone's phase* (not pinned to the zone entrance), and is wired as an ordinary graph node with no special-casing — reachable or avoidable by route choice like any other node, gone-once-passed by the forward DAG's construction. Two ports landing in the same layer within a zone is allowed.

A port **consumes** one of its zone's node slots (converts an Encounter node into a Port) rather than adding on top. So a zone's `nodes_per_zone` budget (**17 / 17 / 16**, ~50 total) is its total *point* budget — encounters **plus** ports — and the real encounter count is **44** (15 / 15 / 14), not 50. (The #59 charter's "50 encounter points" figure predates this; 50 is the point budget, 44 is the encounter count.)

### Encounter kind assignment — per-zone shuffled bag (was: hand-authored even split; #63)

Kind assignment is a **per-zone shuffled bag**: for each zone, a bag sized to that zone's actual encounter count (15 / 15 / 14) is filled with the three kinds split as evenly as a three-way split allows, shuffled, and dealt to the zone's encounter nodes. This guarantees an even kind mix across each zone's pool without tracking or balancing individual routes.

### Difficulty / reward gradient — depth-within-zone (was: port-proximity "contested waters"; #63)

ADR-0007's port-proximity effect ("contested waters" — Ship Battles near a port tuned harder) is **retired**. It is replaced by **depth-within-zone**: a node's layer index within its zone's phase, normalized to a fixed range so the spread is consistent regardless of how many layers a given seed rolled. Difficulty and reward both **rise with depth**, stacking on top of the existing per-zone `zone_tier` ladder. Unlike ADR-0007's port-proximity effect (which applied to Ship Battle only), depth scaling applies to **all three** encounter kinds — harder battles, bigger stat trades, and better upgrade offers the deeper into a zone a node sits.

### Presentation — full graph, kind hidden per node (was: everything visible, no fog; #62)

Of three prototyped fog models — (A) full graph with kind hidden, (B) fog by graph-distance horizon, (C) no graph, per-zone progress + local choice fan — **Variant A** is chosen. The whole graph's shape (node positions and edges) is always drawn. An **unvisited** encounter node shows only a generic zone-tinted marker with its **kind hidden**; the kind reveals permanently on arrival and stays shown as route history. **Landmarks** (Start / Port / Goal) are always fully visible, including far-off ports, since they carry no hidden kind. Reachable next nodes get a highlight; travel options are color-coded by whether walking there fires an encounter.

A and B/C trade off route-planning: the map's charter demands "real branching route choice," which is only meaningful if the player can see enough of the graph to plan a route across it — B hides everything past the horizon and C never shows the graph, both undercutting the reason to generate a connected graph at all. A is also the smallest delta from today's `cmd/game/view.odin` renderer. The exact on-screen coordinate layout (lane assignment, edge routing at ~50-node density on the current window) is an implementation concern left to the build, not locked here.

## Consequences

- The map now needs a procedural generator (seeded, layered forward-DAG with guaranteed reachability and no dead ends), replacing ADR-0007's hand-authored point set. Nodes gain coordinates and edges — the old "points carry no adjacency" model is gone.
- `core/run`'s `Point` model gains edges/adjacency and a per-node hidden/revealed state; `cmd/game/view.odin`'s `draw_map` / `point_marker` change to draw edges, hide unvisited encounter kinds, and mark reachable-next nodes (per Variant A).
- Whether a Ship Battle's opponent-scaling formulas (`run_ship_battle_difficulty`, `run_ship_battle_opponent_durability`, the retired port-closeness bonus) need rework for the new depth-within-zone model is **left to implementation** — the port-closeness bonus in particular no longer has a source concept and must be removed or repointed at depth.
- Whether a generated map/seed must be persisted for save/resume rides on the still-open save/resume + meta-progression gap from ADR-0007; this effort does not reopen it. Storing the seed rather than the expanded graph is the natural option if it ever is.
- All generation parameters are named code constants — tunable by a developer without a config file or settings UI, matching ADR-0006/0007's placeholder-constant convention.

See GitHub issue #59 (and design tickets #60, #61, #62, #63) for the full design discussion.
