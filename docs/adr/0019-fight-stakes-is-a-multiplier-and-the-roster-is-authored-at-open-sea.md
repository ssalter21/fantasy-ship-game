# ADR-0019: Fight stakes is a multiplier, and the hostile roster is authored at Open Sea

## Status

Accepted — amends ADR-0014 (the stakes gradient, as it applies to the Fight primitive) and ADR-0012 (the hostile roster's authoring weight). Does not supersede either: one gradient read differently by each primitive, archetype-is-character/stakes-is-power, no runtime RNG, and content-as-plain-data all stand unchanged.

## Context

Issue #151 (ADR-0017) made fights *last*. It did not make them **fair**, and issue #165 asked why.

Every archetype in the roster out-damaged a starting player, at Coastal, on the first fight of the run. A starting ship's raw damage is **8** (Gun Deck 5 + Top Crew 3); the roster's archetypes arrived at **9-16** of resolved output, because #135 authored them from the whole ~50-item roster — Carronade 6, Long Nines 8, Naval Gun Crew 6 — while the starting loadout is one Splash-grade gun and the player's second Large slot is cargo. The player won a Coastal fight only because the hostile's HP pool was smaller, and paid **~50% of max HP** for it. With ~5 fights in a run and no healing, that is a run that dies at fight two.

The cause is that **the site's offense reading was additive**: `run_fight_opponent_offense` returned a flat bonus spread over the archetype's Offensive fittings. An addition can only ever add. So a Coastal hostile could never be rendered *weaker* than the loadout #135 happened to author — the gradient's floor was whatever the roster said, and since the draw reads no zone (any build may turn up anywhere), that floor was the **first** thing a starting ship met.

Measuring the additive model before replacing it turned up two things the ticket had not asked about:

- **The independence property #135 claimed was already false.** Its shared total (`run_offense_share`) existed to stop gun count multiplying the site's reading. But a share lands on an *authored magnitude*, upstream of `effect_magnitude`'s synergy seam, so a `Selector` multiplies the share by its match count: Deepwater Menagerie's Hunter's Pack (+3 per Beast, two Beasts aboard) turned a Deep reading of 9 into **14 points of output**, where every flat build got 9 — the site's reading worth **56% more** to a synergy build. Death Throes, whose guns are gated on its own HP, banked most of its share until it was dying. The machinery was defeated by exactly the mechanism it was built to prevent, one level down: not count-of-guns, but count-of-Beasts. Its test could not see this because it summed authored magnitudes rather than resolving output.
- **Half of #135's "only Offensive fittings take it" rule had lost its reason.** The stated reason was that scaling Buff or Defensive inflates `defense_bonus` and makes a deep hostile harder to *hurt*. ADR-0017 took Buff out of `defense_bonus` — `raw_damage = boosted(Offensive) + boosted(Buff)` — so that reason now covers Defensive alone. The rule outlived its justification for a whole ticket.

## Decision

**The Fight primitive's stakes reading is a percent, not a bonus.** `run_fight_opponent_power(site)` returns a factor; an archetype's output is scaled to it. It is the one reading in the stakes group that multiplies, and it is the only one that needs to: every other primitive's reading is a quantity the site *grants* (treasure, item quality, a swing), so zero is a coherent floor and adding is the whole of what it does. A hostile is not granted — it arrives already authored, and what the site decides is **how much of it lands here**.

This gives the gradient a way **down**, which is the thing that did not exist. It also **dissolves** #135's dilemma rather than moving it: a multiplier is scale-invariant, so three guns at 50% is the same proportion as one gun at 50%, the count cannot swamp what it no longer touches, and `run_offense_share` and its remainder handling are deleted. Crucially the invariance holds *through a selector* — `(m × pct) × count` is `pct × (m × count)` — so the multiplier is the first shape that actually delivers the property the shared total was built for.

**The rule is restated on its surviving reason: stakes scales what a hostile *deals*, never what it *soaks*.** Offensive and Buff are scaled (both feed `raw_damage`, ADR-0017); Defensive is not (soak is subtracted from raw, so scaling it walls the player at any magnitude). Under an additive bonus, Buff's exclusion was a rounding error; under a multiplier it would be a **floor the site cannot lower**, which is the same defect this ADR exists to remove.

**Only an active `Phase_Contribution` effect is scaled** (`ship_fitting_output_scaled`). Category is a combat *phase*, not a clean deals/soaks axis: `.Buff` also holds every `Modify_Speed` item in the roster (Spare Rigging, Copper Sheathing, Outriggers, Enchanted Keel), and a hostile's Speed is its **archetype's** axis, explicitly not a stakes reading (#135). Scaling by category alone would have let a Deep node hand Reef Skimmer more Speed than a Coastal one, quietly deciding who is allowed to leave the fight.

**`zone_tier`'s 1/2/3 puts 100% at Open Sea, and that is read off rather than chosen.** A multiplier is proportional to tier, so `PER_TIER` *is* the Coastal factor and the middle zone lands on exactly twice it. At 50, the roster is therefore authored at **Open Sea weight**: an archetype meets a captain as its entry describes it in the middle zone, at half that in the Coastal shallows, and at half again on top in The Deep. This keeps the stakes group's two-constant idiom and gives the roster an anchor to be read against — the same move #146 made for the Trade swing table.

**The hostile roster is re-authored up to that weight, and this was forced rather than chosen.** `max(0, raw − soak)` has a floor as well as a ceiling. A starting ship soaks **4**, so an entry authored to deal less than ~10 keeps half of it at Coastal and **cannot scratch the player at all** — a ten-round grind with no risk in it, which is the same dead node ADR-0017 found at the other wall, arrived at from underneath. Six of the eight entries failed that on the day the factor landed. Every entry had been written to be survivable by a *starting ship at Coastal*, because that was the only test the roster had, so the table was authored at **Coastal weight** while the model now reads it as Open Sea weight. A multiplier needs headroom above soak before it has anywhere to scale down *to*.

The band therefore has a second wall, enforced by test rather than by eye: `a_starting_player_takes_real_damage_from_every_archetype_at_coastal` bounds the floor as `a_starting_player_can_fight_every_archetype_at_coastal` bounds the ceiling.

## Consequences

**A Coastal fight costs a starting ship ~28% of its HP instead of ~50%**, measured across all eight archetypes at Coastal depth 0: the player retains 60-88% (mean ~72%), against 28-72% before. The hardest fight is now the Ironclad Hulk — and it is the archetype a starting ship can most easily walk away from (Speed 2 against 4), which is the intended shape rather than an accident: the fight you are least able to win is the one you are most free to decline.

**The margin is stated, not fallen into**: the bar is that a starting ship survives the first fight of a run with enough left to reach a Port, and that no archetype is a formality in either direction. Runs won over 30 seeds × 3 travel policies, against #151's table (a captain who Holds every round and buys nothing — a floor, not a forecast): battle-free routes 7 → 8, first-battle-then-avoid **3 → 5**, seek-battles 0 → 0. Battles won 40% → 43%; mean fight length 6.1 → 7.1 rounds; escapes stay reachable (10/62 → 12/65).

**The ceiling moved, so builds that were too heavy now fit** — this is what the way down buys, and three entries demonstrate it. Boarding Party finally carries **Admiral's Guard**, the roster's longest-running argument: #135 barred it as a *category* (buff was soak, so +9 was arithmetically unwinnable), #151 reduced that to a *magnitude* (a Selector became a hard hitter rather than an invulnerable one), and #165 reduces it to a *zone* (+4 at Coastal, +15 in The Deep). Smuggler's Run takes the **Ghost Lantern** its own comment had been asking for across two tickets, and Deepwater Menagerie takes the third Beast its synergy wanted.

**Maps do not move.** No generation-time draw changed — the archetype draw is one `rand.int_max` either way — so every seed's map is byte-identical (seed 0's `Event_Run_Started` hashes the same, and its route is unchanged), and #136's standing warning about seed-pinned scenarios re-pointing did not bite. What changed is what the hostiles hit for: seed 0's first battle opens on raw 9 where it opened on 12.

**The honest costs.**

- **Scale-invariance is a property of output, not of damage.** Soak is subtracted *after* the factor, so `max(0, k·A − s)` is not proportional to `A`. Near the floor, small differences in authored output become large differences in damage taken. That is why the floor wall has to be a test rather than a guideline, and why the roster's re-authoring was not optional.
- **An armoured archetype's damage is amplified by its own armour**, because armour lengthens the fight: the Hulk's 10 rounds against a typical 6 means equal per-round damage costs the player ~67% more. Authoring to a comparable *output* band therefore does not produce a comparable *fight*. The Hulk is the entry that shows it, and the roster has no vocabulary for the difference.
- **The span from Coastal to The Deep is now ~3×** (50% → 165%) where the additive bonus spanned ~1.4×. This is in line with the Fight primitive's other two readings rather than out of step with them — HP already spans 40 → 156 (3.9×) and durability 1 → 6 — but it means a Deep hostile is genuinely out of reach for a ship that has bought nothing, which the 0/30 seek-battles row reflects.
- **Rounding is per fitting, half-up.** A magnitude of 1 at 50% stays 1, so a scale-down cannot silently disarm the roster's smallest fittings; the cost is that a build's scaled output can sit a point or two off the exact proportion, which the independence test allows for explicitly.
