# ADR-0029: An effect carries its own phase and its own timing

## Status

Accepted — **amends ADR-0006 and ADR-0025**, which put the round phase on the *fitting* (`Fitting.category`), and **restates ADR-0027's verb/phase pairing** in the direction the effect now reads it (`ship_verb_phase`). Everything else in ADR-0006 stands: phased rounds, simultaneous resolution, one captain decision per round, Speed-gated escape, the hard round cap. ADR-0008's ghost model is untouched, which is a load-bearing part of this decision rather than a happy accident.

## Context

Issue [#405](https://github.com/ssalter21/fantasy-ship-game/issues/405), under the item-authoring effort ([#363](https://github.com/ssalter21/fantasy-ship-game/issues/363)), as amended by [#394](https://github.com/ssalter21/fantasy-ship-game/issues/394) (the buff verbs are deleted) and [#410](https://github.com/ssalter21/fantasy-ship-game/issues/410) (`hits` is deleted).

A Fitting carried **one** effect — passive XOR active — and the phase it resolved in sat on the *fitting*, one field over. Two consequences followed. Same-cell items were near-clones by construction: one effect is one verb, one magnitude, one condition, so the only axes left to distinguish two Medium Shallow items were the number and the tag. And `Fitting.category` had a **zero value that lied** — it defaulted to Brace, so every hold and every effect-less fitting was a Brace item as far as any code counting by category was concerned.

The remaining axis for "when" was nothing at all: an effect fired every round of every battle, which is why the defensive roster could not be priced (a repair worth taking every round is a turtle; one worth taking once is a save).

## Decision

**A Fitting carries `effects: [FITTING_MAX_EFFECTS]Effect` plus `effect_count`, and the cap is in the type.** Three, because raising the cap later is free and lowering it is not. `passive`/`active` are deleted. `ship_fitting_with_effects` writes the array and the count together, so the two cannot disagree — a count short of what was written silently disarms an effect, and one past it resolves a zero `Effect` as a live one.

**Phase rides on the Effect, not on the Fitting**, as `phase: Maybe(Category)` — absent for the one verb that feeds no phase. `combat_phase_output` routes on it, so **one item may feed both phases in a round**, which is the whole reason a fitting carries a list. `Fitting.category` is deleted: it routes nothing, and a field that only lies is not worth keeping for a ticket.

**Nothing authors the verb/phase pair by hand.** The `effect_*` helpers set `phase` from `ship_verb_phase` (Phase_Contribution → Fire, Repair → Brace, Modify_Speed → neither), which is ADR-0027's pairing stated in the direction the effect reads. A roster test is the guard that a hand-built literal has not slipped past them.

**Timing is a closed union of exactly five** — `Always | Once_Per_Battle | Every_N{n} | Ramp{per_round, cap} | Charge{cost, per_round}` — declared `#no_nil` so `Timing_Always` is the zero value. An incoherent setting is unrepresentable rather than rejected at runtime, and pricing faces five shapes rather than a knob space. `effect_timing_advance` answers a timing as **pure arithmetic over `(timing, round, counter)`**, so a timing is tested as the sequence it produces, with no Battle and no Ship in reach.

**The battle is the hard ceiling for every timing.** What a timing remembers is one int per `(side, slot, effect)`, held on `Battle.timing` and zeroed by the zero Battle. **The Ghost_Snapshot gains no new state**, and out-of-combat timing is killed by construction rather than by a rule: there is nowhere else for a counter to live.

**Counters are advanced once per round, for the whole round, after the escape check.** `combat_timings` returns the readings *and* the counters as the round would leave them, and writes nothing back — the caller resolving the round stores them, the caller only weighing a loadout drops them. So an effect fires at most once a round however many phases read the table, a peek can never spend a charge, and a round that ends in a Break Off spends nothing.

**A `Modify_Speed` effect may not carry a timing**, asserted at authoring time beside the existing rejection of a speed-reading tree. Its consumer, `ship_effective_speed`, is read off the battlefield too — the refit screen, the escape check taken before a round's orders — where no Battle holds a counter. A timing there would read one number in the fight and another in the hold.

**A ramp's growth rides beside the tree, exactly as `site_scale` does**, added to what the evaluator returns rather than spliced into the tree: a growth node at the root would tax every tree, and growing a constant leaf would grow a gate's threshold with it.

## Consequences

- **Same-cell items stop being clones.** Three effects, each with its own verb, phase, timing and tree, is the axis the power budget ([#408](https://github.com/ssalter21/fantasy-ship-game/issues/408)) prices distinctness along.
- **Repair can be priced at two rates.** Sustained (`Always`) and burst are opposite demands on one number; the timing axis is what reconciles them, which a price could not.
- **`Timing` is in the type but not yet in the roster.** No authored item leaves `Timing_Always` until the roster rewrite ([#406](https://github.com/ssalter21/fantasy-ship-game/issues/406)) and the budget ([#408](https://github.com/ssalter21/fantasy-ship-game/issues/408)) land, so the resolver is exercised by tests rather than by content.
- **A Fitting is a third bigger** — three 12-node trees rather than two. `Node`'s fields are reordered widest-first to claw a quarter of that back; the events that carry a shop's shelf by value are the size ceiling worth watching, and one presentation test had to stop stacking fourteen of them in a frame.
- **The Fight site's scaling guard moves from the category to the verb.** `voyage_stakes_scales_category` is deleted: with no category to ask about, every hostile fitting goes through `ship_fitting_output_scaled`, which moves `Phase_Contribution` effects and leaves Repair and `Modify_Speed` where they were. ADR-0027's "the site does not scale repair" holds unchanged, now by construction rather than by a caller remembering to ask.
- **`SHIP_MAX_SLOTS` is now a real bound**, since the per-battle timing table is indexed by slot. The one ship template is sized from it.
- **Presentation reads a phase *set*.** An item's chip says "Brace/Fire" where it feeds both, and "no phase" for a hold or a pure speed item.
