# ADR-0007: Map and run structure — linear zones, ports, and mixed encounter kinds

## Status

Accepted, partially superseded by ADR-0009. The **Topology**, **Layout**, **Ports**, and **Danger and reward gradient** sections below are superseded — the map is now a procedurally-generated connected node graph (not an open travel-anywhere point set), with hidden encounter kinds, 6 procedural ports, ~50 points / 44 encounters, and a depth-within-zone gradient. The zones, the three encounter kinds, the win/loss conditions, and encounter-on-arrival survive (the last refined: revisiting never re-triggers). See ADR-0009.

## Context

Issue #7 asked for the vertical slice's run structure: the shape of the small hand-placed open map, what the danger gradient concretely looks like, and the run's win/loss conditions. The PRD (#2) scopes this as "a small, hand-placed, open (non-node-graph) spatial map with a danger gradient — not procedurally generated." Combat resolution (ADR-0006) already establishes that combat is a deterministic ship-vs-ship phased-round battle, that HP persists across the whole run (no per-encounter reset), and that permadeath at 0 HP ends the run — so this ticket needed to decide what surrounds combat: what the map looks like, what other kinds of encounters exist besides battles, and how a run starts, escalates, and ends.

## Decision

**Topology.** The map is a small set of hand-placed points on an open 2D canvas, not a node graph — no fixed edges/adjacency between points. From any visited point, the player may choose any other point as their next destination; travel between points is abstracted (not physically simulated steering). All points are visible from the start of the run; there is no fog of war.

**Layout.** The map is linear/directional: a Start point (which doubles as the home port) leads through three difficulty zones in a fixed order — Coastal, Open Sea, The Deep — to a Goal point. Each zone contains one port and 4 encounter points (12 encounter points total across the three zones). The Goal point is a plain destination with no port and no encounter of its own.

**Ports.** A port is a safe, no-battle location where the player spends treasure (the ship's starting-capital stat, per CONTEXT.md). There are 4 ports total: the Start/home port, plus one per zone.

**Encounter kinds.** Every one of the 12 encounter points is assigned exactly one of three kinds:

- **Ship Battle** — the player's ship fights a game-configured opponent ship, resolved via the phased-round combat system (ADR-0006). This is mechanically identical to a future real ghost-PvP battle — the combat resolver doesn't care who or what configured the opponent — but this slice's opponent ships are not sourced from real players' stored snapshots. Wiring in real snapshots is a separate, later ticket and needs no map rework when it lands.
- **Upgrade Offer** — the player chooses one of a few options to upgrade one of the ship's three starting fittings, consistent with the vertical slice's upgrade-only findable-content scope.
- **Stat Trade** — a permanent stat-for-stat or stat-for-cargo trade-off (e.g. +Durability for −Speed).

The 12 points split evenly, 4 of each kind, hand-placed so every zone gets a mix of kinds rather than one kind dominating a zone.

**Danger and reward gradient.** Difficulty and reward quality both rise by zone, together: Coastal is easiest/weakest, Open Sea is moderate, The Deep is hardest/strongest — applied across all three kinds (harder battles, bigger stat trades, better upgrade offers, the deeper the zone). Within a zone, Ship Battle points nearer that zone's port are additionally tuned to a harder opponent-ship configuration than points farther from it, reflecting more contested waters immediately around a port. This port-proximity effect applies to Ship Battle difficulty only, not to Upgrade Offer or Stat Trade quality.

**Encounter triggering.** An encounter point triggers automatically when the ship arrives there as part of the player's chosen route — there is no option to decline once arrived. The only way to avoid an encounter is to route around its point entirely.

**Win condition.** The run is won by reaching the Goal point with HP > 0.

**Loss condition.** The run is lost only by reaching 0 HP (permadeath, per ADR-0006). There is no turn/resource limit and no mechanic to retreat home and bank partial progress — retreat/banking overlaps with meta-progression and save/resume, both already flagged "not yet specified" in the PRD (#2).

## Consequences

- The map needs no procedural generation, pathfinding, or physics/steering system — just a fixed small set of points, a "reachable from anywhere" travel model, and per-point kind/difficulty/reward data to hand-author.
- Ship Battle points already fit the ghost-PvP shape the PRD anticipates; wiring in real stored snapshots later is a data-source change to this same encounter kind, not a new one.
- Upgrade Offer and Stat Trade encounters need their own small resolution UI/flow, distinct from the battle Sim loop — not designed here, left to implementation.
- Zone- and port-based tuning (difficulty, reward quality) uses placeholder values, matching ADR-0006's own placeholder constants — expected to move during playtesting without reopening this ADR.
- No fog-of-war/discovery system, ghost-PvP snapshot sourcing, turn-limit resource system, or retreat/banking mechanic is built for this slice; all four are explicit gaps left for future tickets if wanted.

See GitHub issue #7 for the full design discussion.
