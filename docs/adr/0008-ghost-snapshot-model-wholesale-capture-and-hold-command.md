# ADR-0008: Ghost snapshot model — wholesale per-encounter capture, and a deterministic scripted opponent

## Status

Accepted

## Context

Issue #8 asked for the ghost-snapshot data model (what state gets captured from a run to be fought later) and a determinism/RNG-seeding strategy for headless simulation and ghost-battle resolution.

Combat resolution (ADR-0006) already settled the RNG question for battle itself: combat uses no randomness anywhere, and this "sidesteps any seed-sharing design for ghost battles." Random seeding does have a real use in this project, but for procedurally placing encounters on a future map (the current map is hand-placed, ADR-0007) — a different subsystem, out of scope here. What ADR-0006 left open is what a scripted (non-player-controlled) ship decides on rounds other than escape — it only defined the Leave Combat rule.

Separately, the map/run-structure design (ADR-0007) established that Ship Battle encounters fight a "game-configured opponent ship" for this slice, but the combat resolver "doesn't care who or what configured the opponent," and wiring in real player-sourced snapshots later should be a data-source change, not a new encounter kind. The eventual product goal is a multiplayer lobby where players fight other lobby members' *current, in-progress* state as they each move across the map — not only their finished runs — so capture can't wait for a run to end.

## Decision

**One struct, two producers.** `Ghost_Snapshot` is the single opponent-ship representation used for both this slice's hand-authored PvE opponents and future real player-sourced ghosts. There is no separate "PvE opponent config" type.

**Shape.** A `Ghost_Snapshot` has two parts:

- **Ship** — HP (an explicit, overridable field — see below), Durability, Speed, cargo capacity, starting treasure, captain id, and the full layout (every slot's occupying fitting, including cargo/loot — cargo needs no special handling since it's just a fitting per ADR-0004).
- **Progress** — steps taken (count of encounter points resolved so far this run), zone (the encounter's zone, per ADR-0007's Coastal / Open Sea / The Deep), and difficulty_rating (the specific encounter point's tuned difficulty number, capturing ADR-0007's port-proximity nuance that zone alone would lose).

`Progress` and `starting treasure` are not read by combat resolution (ADR-0006) — they exist for future analytics and ghost-selection/matchmaking. The struct is treated as additive: new fields can be added later without a model rework.

**Capture cadence.** The Sim emits an `EncounterResolved` event carrying a fresh `Ghost_Snapshot` of the ship's current state after *every* encounter point resolves (Ship Battle, Upgrade Offer, or Stat Trade — the three kinds from ADR-0007), not just at run end. Port visits don't trigger it, since they don't change ship state. Following ADR-0001, the Sim only exposes this via an Event; what happens to the payload (store it, eventually sync it to a lobby) is entirely the driver's concern.

**HP always resets to max on capture.** A `Ghost_Snapshot`'s HP field is always set to the ship's max/base HP at the moment of capture, regardless of the real ship's current run-persistent HP (ADR-0006). This is deliberate, not a simplification to revisit: a ghost is a decoupled copy that may be fought independently by multiple different opponents, while the real player's own ship keeps degrading normally on their own run. Carrying real HP into the snapshot would make a ghost's difficulty an accident of when it was captured rather than a property of its build, and would make "fighting the same ghost twice" behave inconsistently. Hand-authored PvE opponents may still set HP to any explicit value as a difficulty knob — only *captured-from-a-real-run* snapshots are constrained to always-max.

**Scripted opponent decision policy.** A new `Hold` `Command` variant is added (extending ADR-0006's Command enum) — a formal no-op. Any non-player-controlled ship (a hand-authored PvE opponent or a fought ghost) submits `Hold` every round except when Leave Combat becomes available, which it still takes automatically per ADR-0006's already-deterministic escape rule. It never chooses Boost Buff/Defensive/Offensive, Man the Sails, or Jettison Cargo in this slice — it only fights passively through its fittings' base effects.

**Out of scope.** This ADR does not build: durable snapshot storage, the multiplayer lobby/matchmaking sync layer, or map-generation RNG seeding. The driver receiving `EncounterResolved` may log it or hold the latest snapshot in memory for now.

## Consequences

- `Ghost_Snapshot` doubles as a run-telemetry checkpoint (steps/zone/difficulty/treasure) beyond its role as battle input — combat resolution only ever reads its Ship part.
- ADR-0006's `Command` enum gains a `Hold` variant; a scripted opponent's `Input_Source` is now fully specified (always `Hold`, except automatic Leave Combat once eligible).
- Because capture happens every encounter rather than once at run end, it's a frequent, cheap Event emission, not a heavy end-of-run operation.
- No RNG is introduced by this ADR; ghost-battle reproducibility rests entirely on ADR-0006's zero-randomness combat plus this ADR's deterministic scripted-opponent policy.
- Durable persistence and live cross-player lobby sync remain explicit, undesigned gaps for a future ticket — this ADR only shapes the data and its emission.

See GitHub issue #8 for the full design discussion.
