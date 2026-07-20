# ADR-0006: Combat resolution — phased rounds, deterministic damage, and Speed-gated escape

## Status

Accepted. **Superseded in part by ADR-0026** on damage composition: Durability and Bulwark are deleted and `final_damage = raw_damage`, so this ADR's flat-reduction formula below is retired. **Amended by ADR-0027** on what the Defensive (Brace) phase does: it resolves **repair** — Hull restored to its own ship, capped at Max Hull, ahead of any Fire output — rather than feeding the subtraction ADR-0026 deleted. **Amended by ADR-0020** (the weight economy) on two points. **Speed becomes a *derived* stat** — `base + modifiers − weight/10`, still an `int` — so this ADR's Speed-gated escape, its Speed tie-breaks, and its `Man the Sails` boost all read a Speed that varies with what the ship is carrying rather than a fixed field; **`JETTISON_SPEED_BONUS` retires**, because a jettisoned hold makes the ship *lighter* and therefore faster for free, so "Jettison Cargo" no longer grants a bonus — it nulls the cargo slot and the weight drop does the rest. And this ADR's **"jettisoned cargo settlement"** below is retired: jettisoned cargo is **always destroyed**, never claimed by the opponent as spoils (the claim was never observable and, read literally, made jettison free on a win); the per-battle tracking list, its settlement proc, and issue #52's run-scoped arena block are deleted, while *sinking* a ship now pays the winner that wreck's hold. See ADR-0020.

## Context

Issue #6 asked for the encounter-resolution system: how the auto-battler core works (what triggers, in what order, over what timeline) and what the one captain decision per round is. It must run identically in PvE, ghost-based async PvP, and headless simulation (ADR-0001/0002), which rules out any resolution order or randomness that isn't fully reproducible from the two ships' builds and the captain's choices.

The ship/crew model (ADR-0004) gives ships HP, Durability, Speed, and a fixed layout of fittings, but fittings carry no HP or state of their own — only a size, an effective visibility, a name, and a passive and/or active effect. Combat resolution had to work within that: it cannot target individual fittings for damage, only the ship as a whole.

## Decision

**Fitting categories and round phases.** Every fitting is tagged with one of three categories — **Buff**, **Defensive**, or **Offensive** — extending the fitting model from ADR-0004. A round resolves in three fixed phases, always in the order **Buff → Defensive → Offensive**: buffs land first so they can affect that same round's defense and offense; defensive effects land next so they're active before damage is calculated; offense resolves last. Both ships resolve each phase together, off shared state — this is simultaneous resolution, not sequential-by-Speed, so a ship that's about to lose a round still gets its Offensive phase that round. Within one ship's own fittings in the same phase, they trigger in fixed slot order. Every fitting with an active effect triggers exactly once per round; there is no per-fitting cooldown.

**Damage and targeting.** An Offensive effect always targets the enemy ship's HP pool as a whole — never an individual fitting, since fittings have no HP of their own. Durability applies as a flat reduction: `final_damage = max(0, raw_damage − Durability)`. Exact numeric tuning (multiplier sizes, Durability values) is out of scope for this decision, consistent with the vertical-slice PRD deferring stat-balancing specifics. **Retired by ADR-0026** — Durability is deleted and damage lands whole: `final_damage = raw_damage`.

**The captain's one decision per round.** Each round, the Sim asks the driver's `Input_Source` for exactly one captain decision — a `Command`, per ADR-0001 — chosen from:

- Boost Buff / Boost Defensive / Boost Offensive — multiplies that phase's fitting output for this round only
- Man the Sails — a temporary Speed boost, this round only
- Jettison Cargo — empties a cargo-filled slot for a *permanent* (rest-of-battle) Speed boost; the jettisoned cargo is tracked in a per-battle list, not transferred immediately
- Leave Combat — only offered once the ship is escape-eligible (see below)

This is a generic decision shape, not hardcoded to these five options — this vertical slice's one captain happens to offer them; a future captain can expose a different action set through the same Command interface without reworking the round loop.

**Escape.** No ship may leave combat before a fixed baseline round count (placeholder constant: 5 rounds) — combat is guaranteed to run at least that long. After the baseline, a ship whose current Speed exceeds its opponent's gets "Leave Combat" as an available choice that round. A scripted/ghost opponent's `Input_Source` always takes it once offered (deterministic policy); a human player may decline it to keep pressing an advantage — e.g. to keep damaging a slower opponent and pressure them into jettisoning more cargo. The instant either ship leaves, the encounter ends immediately for both ships.

**Termination guarantee.** A separate, larger hard round cap (placeholder constant: 20 rounds) forces resolution if, by then, neither ship has been destroyed nor left. At the cap, the ship with more HP remaining wins; an exact HP tie is broken by higher Speed. The same Speed tiebreak resolves a same-round mutual kill (both ships reach 0 HP in the same Offensive phase).

**HP persistence and loss.** A ship's HP persists across an entire run — it is not reset between encounters. Reaching 0 HP sinks the ship and ends the run (permadeath), making "Leave Combat" the primary tool for avoiding a run-ending mistake rather than a full-HP reset.

**Jettisoned cargo settlement.** Jettisoned cargo is never transferred mid-battle. It's settled once, at battle end: if the jettisoning ship escaped, that cargo is simply lost to both sides; if the ship was destroyed or otherwise failed to escape, the opponent claims the jettisoned cargo as spoils.

**Determinism.** Combat resolution uses no randomness anywhere — same two ship builds and the same sequence of captain choices always produce the exact same battle, every phase, every round. All apparent variance comes from build and decision-making, not chance. This sidesteps any seed-sharing design for ghost battles and keeps headless simulation trivial to reason about and replay.

## Consequences

- ADR-0004's fitting model gains a required category field (Buff / Defensive / Offensive); existing ADR-0004 text doesn't mention it and should be read alongside this ADR.
- The captain's per-round `Command` is a small closed enum for this vertical slice's one captain; adding future captains means adding new Command variants, not restructuring the round loop.
- No loot/reward economy beyond jettisoned-cargo spoils is defined here — a broader post-battle rewards system (e.g. for a ship that's destroyed outright) is out of scope and left to a future ticket.
- Because HP persists across a run, later systems (meta-progression, healing between encounters, run economy) need to account for combat as a real, cumulative resource drain — not a per-encounter reset.
- Placeholder constants (5-round baseline, 20-round cap, phase multipliers, Durability values) are implementation defaults, not final balance — expected to move during playtesting without needing this ADR reopened.

See GitHub issue #6 for the full design discussion.
