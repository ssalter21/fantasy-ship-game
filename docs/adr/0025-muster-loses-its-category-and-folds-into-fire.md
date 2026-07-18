# ADR-0025: Muster loses its category and folds into Fire

## Status

Accepted — amends ADR-0006 (combat resolution) and ADR-0017 (the buff/boost repair). Does not supersede either: the phase order (for the phases that remain), simultaneous resolution, Speed-gated escape, permadeath, and determinism all stand unchanged. It removes one of the three phases those ADRs assumed.

(ADR-0006/0017 predate the ADR-0021 rename and say *Buff*/*Offensive*/*Defensive*/*Boost*; read those as **Muster**/**Fire**/**Brace**/**Press** throughout.)

## Context

ADR-0017 un-nested the two Presses so Press Fire no longer strictly dominated Press Muster, and closed with an explicit open question: *"whether Buff still [earns its category], now that it differs from Offensive only by which Boost reaches it, is left open, not decided here."* Issue #314 is that question, forced.

Post-#151, a point of Muster output and a point of Fire output are the **same number** in the damage formula. From `core/combat/combat.odin`, `raw_damage` was `pressed(Fire) + muster_output`, where `muster_output` was Muster's phase total folded in 1:1. Both land in `raw`, both are reduced by the same bulwark, neither touches defense. Exactly two things distinguished a Muster fitting from a Fire fitting:

1. **Which Press doubles it** — Press Muster the Muster pile, Press Fire the Fire pile.
2. **Muster resolved first**, its output visible before Fire — but nothing read `muster_output` except the fold into Fire. The ordering was a hook nobody had plugged into; mechanically inert.

That is not a category. The Press choice ADR-0017 defends as "press the guns, or press the crew" collapsed too: both Presses fed the same `raw` and nothing else, and the opponent's Brace reduced Press Fire and Press Muster **equally**, so there was no asymmetric counterplay and no read to make. Optimal play was always "press whichever pile is bigger" — a computation, not a decision. Un-nesting stopped Fire from *dominating* Muster but left the two **symmetric**, which is a different failure.

Four directions were grilled (the issue lists them): cash in the resolve-first ordering with Fire/Brace synergies that *read* Muster; give Muster a consumer that isn't raw damage (speed, boarding, a resource); make some Brace asymmetric so it soaks Fire but not Muster; or collapse the category. The first three all **prop the category up with a differentiation hook** while the core combat model is still placeholder (ADR-0006, ADR-0012) — inventing a second damage axis before the first one is settled.

## Decision

**Muster does not earn its own category, and is removed.** `ship.Category` becomes `{Brace, Fire}`; the round resolves **Brace → Fire** instead of Muster → Brace → Fire. We pull Muster out now and revisit a real second axis when the core mechanics are settled, rather than fabricate one under a placeholder model.

**Every fitting categorized `.Muster` becomes `.Fire`** — one rule, no exceptions, covering both the active damage-crew fittings and the passive `Modify_Speed` fittings that rode the phase. This is **damage-neutral on `raw`**: `muster_output` was already folded into `raw` at 1:1, so a former crew fitting deals exactly what it did. It is the most reversible choice — when a real second axis returns, the ex-Muster items get re-sorted then — and the least ambiguous to implement. `combat_test.odin`'s `a_former_crew_fitting_and_a_gun_of_equal_magnitude_contribute_to_raw_identically` pins the neutrality as the property the issue noted could not exist while the two were distinct.

**Master Gunner counts more, on purpose.** Master Gunner is the only fitting that selects by category (`Selector(Category.Fire)`, +2 per Fire fitting). After the collapse it counts the former-crew fittings too, so its synergy rises for crew-heavy builds. This is **intended and left as-is** — squarely placeholder balance (ADR-0012), not a bug, and no carve-out is added to preserve its old count.

**Press keeps its shape, and is now degenerate.** `Command_Press` still carries `phase: ship.Category` and can target Brace or Fire — no new single-target "press the guns" command. With Muster gone, Press Fire (doubles damage) is real and Press Brace doubles a bulwark total the roster barely fills (only Boarding Nets and Barricades carry an active Brace effect), so Press has effectively decayed to **"Press Fire, or waste it."** We keep the `{phase}` structure so a future real second axis needs no re-plumbing, and record the degeneracy here rather than silently shipping a choice that no longer exists.

**The "crew vs guns" flavor re-enters through Tags, not a phase.** The surviving `Crew` / `Weapon` Tag families carry the distinction now; no new mechanism replaces it.

**Magnitudes stay placeholders** (ADR-0006, ADR-0012). This is a structural removal, not a rebalance.

## Consequences

- **The combat model is two phases.** `Round_State` loses its `muster_output` field; `combat_resolve_round` drops the Muster pass and resolves Brace then Fire. `raw_damage` is simply a side's pressed Fire output — which already includes the ex-Muster fittings — so total damage for any given build is unchanged (bar the Master Gunner count-synergy shift above).
- **Press is a live degeneracy, documented not fixed.** Until a second damage axis exists, a rational captain always presses Fire. The command and its UI survive against that future; the `{phase}` field is dead weight the day it is fixed cheaply.
- **Brace is left alone, and its category question stays open.** Unlike Muster, Brace is not a *duplicate* of another channel — it is the sole active lever on the *subtracted* side of `final = max(0, raw − bulwark)`. ADR-0017 raised the same "does it earn its category?" doubt about it (only two of ~50 items carry an active Brace effect), and #314 explicitly does **not** answer it: collapsing Brace too would leave a single-phase combat model, which is the larger "is the phase system real?" reckoning we are deferring to when the core mechanics settle. Brace is now the last thin phase standing; its doubt is carried forward, not resolved.
- **The retired vocabulary is recorded, never un-said.** ADR-0006/0017 still describe a three-phase round; read Muster as a phase that existed and was folded into Fire here. CONTEXT.md moves to the two-phase vocabulary and files `Muster` under an `_Avoid_` note (ADR-0021's convention). Earlier ADR prose is not edited.
- Every magnitude here remains a placeholder. This removes a category; it is not final balance.

See GitHub issue [#314](https://github.com/ssalter21/fantasy-ship-game/issues/314) for the grilling of all four directions and the reasoning, and ADR-0017 for the open question this closes.
