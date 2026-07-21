# ADR-0031: Depth scales the opposition, never the player's items

## Status

Accepted — **amends ADR-0012** (the Item Offer) and **stands beside ADR-0019** (Fight stakes is a multiplier). An item's numbers are authored and are never scaled at runtime. Depth applies to the opposition and to the purse; the additive Offer bonus that applied it to the player's items is deleted.

## Context

Issue [#409](https://github.com/ssalter21/fantasy-ship-game/issues/409), under the item-authoring effort ([#363](https://github.com/ssalter21/fantasy-ship-game/issues/363)).

An Offer used to read its node's stakes as a flat magnitude bonus and add it to every option (`ship_fitting_scaled`, `effect_with_bonus`, `expr_with_bonus`). A Deep node handed out the same fifty items with bigger numbers on them.

Three things were wrong with that.

**It made the roster's numbers untrue.** The power budget ([#408](https://github.com/ssalter21/fantasy-ship-game/issues/408)) prices each of the fifty items against what it is authored to do. A bonus applied on the way into the player's hands means the priced line and the received item are different items, and the budget's claim holds only on paper.

**It made the pickup meaningless.** "Swivel Guns +3" is not a discovery; it is the same Swivel Guns with an invisible tax rebate. What a captain going deeper should be offered is a *better item* — something with a name, a tier and a place in the roster — so that what they pick up corresponds to something real.

**It fought its own gates.** A bonus had to be routed down a Gate's open branch so a conditional item that pays nothing while its condition is unmet did not quietly become unconditional — a whole recursive tree rewrite (`expr_with_bonus`) existing only to keep the bonus from changing what an item *means*.

## Decision

**The additive bonus and its scaling procs are deleted.** `ship_fitting_scaled`, `effect_with_bonus` and `expr_with_bonus` go, along with the three `ship_fitting_upgraded_*` variants built on them.

**An Item Offer hands over the roster line unmodified.** `voyage_item_offer_options` copies `Roster_Item.fitting` and touches nothing.

**Offer quality at depth is a depth-gated tier band.** `voyage_offer_tier_band` reads the same `Scaling_Site` gradient every primitive reads and returns the tiers a node may draw from: the top tier its quality reading has reached, plus the one below it. The floor rises with the ceiling — a band that only opened the tier above would leave a Deep node still dealing Splash items most of the time, and depth would read as a lottery rather than as a gradient. Two shelves wide is what keeps a draw varied while the site still decides what class of item is on the table.

**The two thresholds sit between the zone tiers' own readings, not on them.** At 25 and 40 against a reading of `zone_tier x 15 + depth x 5`, the band steps up *inside* Coastal and inside Open Sea (at depth 2 of each) as well as between zones. Thresholds landing on a zone's own reading would have made the band a function of zone alone and depth-within-zone worth nothing to an Offer, which is the one thing this ADR set out to give it.

**Depth's remaining lever on combat is the hostile**, and it is the multiplier ADR-0019 already chose. `site_scale` is **baked at hostile construction** (`voyage_fit_hostile_loadout` → `ship_fitting_output_scaled`) and applied to what the evaluator returns — beside the tree, never as a node, so no authored number is rewritten and no gate's threshold is scaled by accident.

**The scaling guard is on the verb, not on any category.** Only `Phase_Contribution` effects move: Repair is exempt because a hostile repair reaching the player's per-round Fire output is an unkillable hostile (ADR-0027), and `Modify_Speed` is excluded by the same construction rather than by a second rule — Speed is the archetype's own axis. A verb guard is exact where a category guard was not: the retired `Category` axis filed damage fittings and every `Modify_Speed` item together under `.Fire`, so a caller scaling a whole category could not be trusted to have meant the speed items.

**`site_scale` rounds half-up once per effect.** With `hits` deleted ([#410](https://github.com/ssalter21/fantasy-ship-game/issues/410)) multiplicity is `effects: [3]Effect`, so there is one rounding per effect and the multi-hit penalty that motivated [#386](https://github.com/ssalter21/fantasy-ship-game/issues/386)'s finding does not survive to be accepted. What remains is the ordinary integer-granularity flatness of any magnitude-1 effect — 1 stays 1 until 150% — which no multiplier design avoids and which shrinks as magnitudes grow. It is **accepted, not deferred**: the fix is authoring guidance, never a cleverer multiplier and never finer units. #386's standing rule that pricing fractions never touch the sim is untouched.

## Consequences

- **The roster's authored numbers are the numbers the player gets**, everywhere: an Offer, a shop and a hostile's own copy all start from the same line, and only the hostile's is scaled.
- **Depth is expressed twice, and both readings are honest**: as which shelf an Offer draws from, and as how hard a hostile hits. Neither pretends to be the other.
- **The band takes three values across the whole map, and The Deep sees only one of them.** `{Splash}` at Coastal depths 0–1, `{Splash, Shallow}` from Coastal depth 2 through Open Sea depth 1, `{Shallow, Deep}` from Open Sea depth 2 onward — so every node in The Deep draws the same band. With a three-rung tier ladder and a two-shelf window there is nowhere above the top band to climb. Authoring a fourth tier is what would change that; the alternative — a one-shelf band — buys the in-zone gradient by making every deep Offer three near-identical cards.
- **Seed-pinned scenarios re-pin.** The offer draw shuffles a band-filtered candidate list rather than the whole roster, so every seed's generator stream shifts — and shifts again whenever a threshold moves, since the band decides how long the shuffled list is. The three `core/sim` route scenarios moved from seed 17 to seed 12; this is the same re-pinning any change at or above map generation forces.
- **`Tier` earns a runtime consumer.** It was authoring grade plus a shop price; it is now also what an Offer selects on. It stays off `Fitting` — the band reads `Roster_Item`, and a Ghost_Snapshot still carries no tier.

See GitHub issue [#409](https://github.com/ssalter21/fantasy-ship-game/issues/409) for the ticket, ADR-0019 for the hostile multiplier this leaves standing, and ADR-0012 for the Offer it amends.
