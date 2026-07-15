# ADR-0017: Buff feeds Offensive only, and a Boost multiplies its own phase

## Status

Accepted — amends ADR-0006 (combat resolution). Does not supersede it: the phase order, simultaneous resolution, Speed-gated escape, permadeath and determinism all stand unchanged.

## Context

Issue #151 asked whether the Fight "band" should widen. The band is the range of hostile builds a starting ship can meet and have a real fight with, and issue #135 had found it about two points wide: authoring the hostile roster discovered that **an archetype could afford roughly two Offensive fittings**, that the roster's own headline weapon-synergy build (Broadside Company) could not carry the third gun its name promises, and that any `Selector`-based item — most of what ADR-0012's roster is *for* — was unusable on a hostile, because Admiral's Guard (+3 per Crew aboard) on a four-Crew build read +12 **defence** and made the fight arithmetically unwinnable.

Measuring the band as it actually resolved turned up something the ticket had not asked about, and it reframed the question:

- **Every Coastal fight ended in 2-3 rounds**, against an escape gate (`BASELINE_ROUND_COUNT`) of 5. Across 189 fights driven over 30 seeds and three travel policies, `Leave Combat` fired **zero times**. ADR-0006 calls Leave Combat "the primary tool for avoiding a run-ending mistake"; it was unreachable in every fight in the game.
- **A starting ship could not sink its own mirror.** Two starting ships dealt each other 1 damage a round and ground to the 20-round hard cap. Raw was 8 (Gun Deck 5 + Top Crew 3) against a soak of 7 (Durability 2 + Captain's Quarters 2 + Top Crew's buff 3) — soak was ~90% of raw, so damage was the small difference of two nearly equal numbers.
- **The roster fits in neither.** The item vocabulary spans magnitudes of 1..12, and a Selector buff reaches +12 on its own. A 12 cannot land in a 2-point band.

The two facts have one cause. `defense_bonus` was `Defensive phase output + buff output`, and **buff was the dominant term**: of ~50 roster items only two carry an active Defensive effect at all (Boarding Nets 1, Barricades 2) — every other Defensive item is a passive stat-modifier that never enters a phase total. So a ship's soak was, in practice, its own buff. That made Buff the one category worth **twice** its own number (raise your damage, lower your opponent's), welded the band's two walls together (a single buff item pushed toward the burst wall *and* the invulnerability wall at once), and fabricated soak out of nothing — a ship carrying no Defensive fitting still soaked its buff.

## Decision

**Buff feeds the Offensive phase only.** A side's `defense_bonus` is its own Defensive fittings' output; soak is `effective_durability + defense_bonus` and the buff output is not in it.

The reason is structural rather than numeric, and it is the one line worth keeping: **soak is subtracted from raw, so soak's vocabulary must stay small, and Buff's is not small.** Raw damage can absorb a 12 — that is what raw is for. Soak cannot: raw is 8 at the start of a run and ~20-30 by The Deep, so any soak term that reaches 12 is not a hard fight but a `max(0, ...)` floor, forever, at every magnitude. No tuning fixes a category that scales without bound on the subtracted side of a difference. This is what bars `Selector` items from hostiles, and it is why the fold had to go rather than shrink.

**A Boost multiplies its own phase's fittings, and nothing else.** Buff output is boosted by Boost Buff, then added to a separately-boosted Offensive total: `raw = boosted(Offensive) + boosted(Buff)`, rather than the previous `boosted(Offensive + Buff)`.

This is a consequence of the first decision and a repair of a second, quieter defect. With buff no longer in soak, nesting the totals would make Boost Offensive **strictly dominate** Boost Buff — `2(O+B)` beats `O+2B` for any `O > 0` — turning one of the captain's five Commands into a choice that is never correct. Un-nested, the two Boosts ask a real question: press the guns, or press the crew. It is also what ADR-0006 already said — "multiplies that phase's **fitting output**" — so the nesting was a misreading, not a decision.

**HP is a scale, and it was too small to express a survivable fight.** `STARTING_HP` 20 → 100, and `FIGHT_OPPONENT_HP_PER_TIER` / `_PER_DEPTH` 10/3 → 40/12.

Also arithmetic rather than taste. A fight lasts `R` rounds and should cost the player a fraction `f` of a health pool that persists all run with no healing; a run meets ~5 fights, so `f` must be ~0.2. At `R = 6` that is `hostile damage = f x HP / R = 0.67` damage per round — **below 1, the smallest number the model has.** HP 20 could not express "a fight you win and sail away from" at all; the only expressible outcomes were a 2-round burst and the round cap. Everything denominated in HP scales with it (see Consequences); Durability deliberately does **not**, because Durability is denominated in *raw damage*, which did not move.

## Consequences

- **The mirror resolves and the band holds a build.** Soak drops from ~90% of raw to ~50%, so a starting ship's mirror goes from a 20-round 1-damage stalemate to 4 damage a round. Coastal fights run 6-10 rounds instead of 2-3, and mean fight length across a run's battles goes 1.5-2.1 rounds → 4.8-7.3.
- **Leave Combat exists.** Measured over the same 30 seeds x 3 policies: 0 escapes in 189 fights → 21 in 177. This is the change that matters most; the mechanic was dead code.
- **A `Selector` item can sit on a hostile.** Admiral's Guard on a four-Crew build is now +12 *output* — a hard hitter rather than an invulnerable one. The problem becomes a **magnitude** question (tunable by the entry, the site, or the item) instead of a **category** one (untunable). Broadside Company carries its third gun.
- **Boost Defensive is weak, and that exposes a roster gap.** With buff out of soak, Boost Defensive doubles a Defensive total that the roster caps at ~2-4, because only two of ~50 items carry an active Defensive effect. The buff fold had been a prosthetic standing in for an almost-empty Defensive phase. Whether Defensive earns its category — and whether Buff still does, now that it differs from Offensive only by which Boost reaches it — is left open, not decided here.
- **HP-denominated content follows the HP scale**, on ADR-0012's own rule that an item's magnitude is read against the stat it modifies: the four `Modify_Max_HP` items scale x4 (Salt Provisions 2→8, Ship's Surgeon 4→16, Treasure Vault 6→24, Titan's Heart 8→32), and with them Trade's two HP-denominated swing rows (`TRADE_SWING_HP_PER_TIER` 4→16, `TRADE_SWING_MAX_HP_PER_TIER` 2→8). Those two rows are **derived, not chosen**: #146 fixed the swing table as the item roster's price list read off — one swing at zone tier N is one tier-N stat fitting — and the scaled items keep satisfying it (8/16/24 against Salt Provisions, Ship's Surgeon, Treasure Vault). Durability's, Speed's and Treasure's rows are untouched — they are not denominated in HP.
- **#146's prediction did not land, and its test survives.** #146 expected #151 to widen the band by giving *Durability* a range, which would have given the Trade table a resolution finer than a zone and reopened its deleted depth axis. The band widened through the buff fold and HP instead, so `STARTING_DURABILITY` is unchanged at 2, the Trade depth axis stays closed, and `the_deep_asks_one_point_of_armour_before_it_will_buy_a_ships_armour` still passes rather than failing as #146 invited.
- Every magnitude here remains a placeholder (ADR-0006, ADR-0012). This widens a band; it is not final balance. The run's *survivability* is not fixed by it — see the issue for the measured win rates and the archetype-weight finding handed on.

See GitHub issue #151 for the measurements and the full discussion.
