# ADR-0018: Ghost capture is once per encounter, at the end of the node's walk

## Status

Accepted — amends ADR-0008 (ghost snapshot model). Does not supersede it: one-struct-two-producers, the snapshot's shape, HP-always-resets-to-max, and the scripted opponent's `Hold` policy all stand unchanged. This ADR restates one paragraph — **Capture cadence** — in the stage model's terms, and strikes its Port exception.

## Context

Issue #155 asked whether a `Ghost_Snapshot` should be captured once per encounter or once per resolving stage. The code answered neither.

`Event_Encounter_Resolved` fired from exactly three sites — battle end, an accepted Trade, and a Reward payout — and those were not a cadence anyone chose. They were **the three run-side procs that happened to return a `Ghost_Snapshot`**. The set is a fossil of ADR-0007's three encounter kinds (Ship Battle / Upgrade Offer / Stat Trade), which ADR-0014 dissolved into stage primitives. Its consequences:

- **Offer and Shop never emitted at all.** A captain takes a gun aboard at a Derelict, or buys three fittings at a Port, and *no ghost records it* — while a Reward that moves only the purse emits faithfully. A ghost is a **build**; the cadence missed every build change in the game and captured the one thing combat never reads.
- **A `[Fight, Reward]` emitted twice.** The two snapshots have byte-identical `progress` (`steps` is per-travel, `site` is per-node) and identical layouts. They differ in exactly one field — `starting_treasure` — which ADR-0008 says combat does not read.
- **The event fired when the node was not resolved.** All three sites ran while `sim.resolved[node]` was still false.

ADR-0008 already specified once-per-encounter: *"after every encounter **point** resolves (Ship Battle, Upgrade Offer, or Stat Trade — the three kinds from ADR-0007)"*. An encounter point is a **node**; the three kinds were a parenthetical example, not the rule. When ADR-0014 dissolved kinds into stages, "encounter point" was quietly reread as "stage" — because those three kinds were exactly the three snapshot-returning procs. **Nobody decided the per-stage cadence.** It survived issue #131's generic walk because one-stage recipes made both readings identical, and only issue #138's catalog — which puts `[Fight, Reward]` on every seed's Open Sea — made them differ.

So the drift is not the whole of what needed deciding, which is why this is an ADR and not errata. ADR-0008 could not have said what a **halt** or a **sinking** does, because complete-or-halt did not exist yet; and its Port exception has since become false.

## Decision

**Capture once per encounter, at the end of the node's walk** — `sim_walk_encounter`'s exit branch, the single place a walk ends and the same place that sets `sim.resolved[node]`. The event's "Resolved" and the Sim's `resolved` are now one fact.

A ghost is an **opponent** — a build a lobby serves to other players (ADR-0008's leading job) — not a telemetry timeline. The snapshot is the ship the captain **leaves the node with**, whatever the whole stage list made of it. A struct whose HP field resets to max on purpose is a poor timeline record anyway, and `Event_Ship_Updated` already carries honest per-change ship state for a driver that wants one.

- **A halt emits.** A halted stage jumps the cursor to the end (ADR-0014), so a fled `[Fight, Reward]` exits through the same branch. The fled ship is a real ship; the lobby can serve it.
- **A sinking does not.** The walk stops dead, the node is never resolved, and this is the one encounter in a run that leaves no ghost. Nothing of value is lost: the build is unchanged from the previous node's snapshot unless the captain jettisoned mid-battle, and `Event_Run_Ended` already lets a driver pair "last snapshot" with "died here". One emit site, no exception.
- **Landmarks emit nothing.** Start and Goal hold no encounter (ADR-0014), so the walk returns before the loop.
- **Once per node, across the run.** An encounter is walked once and marked resolved, so a retrace to a resolved node re-emits nothing.

**ADR-0008's Port exception is struck.** *"Port visits don't trigger it, since they don't change ship state"* was true only while a Port was a landmark with its own lifecycle. A Port is a `[Shop]` recipe (ADR-0014, issue #134), and its multi-buy loop is the single largest build change in the game.

**Timing needs no rule of its own.** A Refit's finish routes back *through* the walk, so the capture is post-install and post-multi-buy by construction: an Offer's pick advances the cursor and then opens its Refit; a Shop's buy keeps the cursor and re-enters. Both end at the same branch with everything aboard.

## Consequences

- **The run-side stage-apply procs stop returning snapshots.** `run_finish_ship_battle`, `run_apply_trade` and `run_apply_reward` return their own outcome and nothing else; `run_finish_ship_battle` now reads an ended `Battle` as a `Stage_Outcome`, which is what a Fight actually has to say for itself. `run_ghost_snapshot_of` drops to **one** call site, so issue #82's borrowed-vs-owned capture dance happens in one place.
- **Two fields die.** `Stage_Fight.depth` and `sim.active_trade_site` existed for one reason each: so a late-resolving stage could carry a copy of the node's site to stamp on a snapshot of its own. At the walk's end the node the ship is standing at *is* the node being snapshotted, so three reconstructions of one site collapse into one `sim_current_site` call.
- **Snapshot count per run is the number of encounter nodes resolved** — it drops on multi-stage encounters, and rises from zero on Offers and Shops. This is a behavior change to a live event, taken deliberately.
- **`Ghost_Progress` cannot express a stage.** It holds `steps` (per travel) and `site` (per node), so a per-stage capture emits records its own progress half cannot tell apart. Any future argument for per-stage capture must first give `Ghost_Progress` a cursor, and then say what a lobby consumer would do with "which *part* of a node this ghost came from".
- **This rests on stated intent, not a live reader.** Both drivers handle `Event_Encounter_Resolved` with an empty case today — the snapshot has no consumer yet. Worth knowing if the lobby ever contradicts it.

See GitHub issues #155 (the decision) and #162 (the change).
