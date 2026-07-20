# ADR-0028: The captain's order set is Press / Commit / Jettison / Break Off / Hold

## Status

Accepted — **supersedes ADR-0017's second decision** (a Press multiplies its own phase's total and nothing else, because nesting the totals would make one Press strictly dominate the other) and amends ADR-0006's captain-decision set. The rest of ADR-0006 stands: phased rounds, simultaneous resolution, one decision per round, Speed-gated escape, the hard round cap, permadeath, determinism. ADR-0017's *first* decision died with the phase it named (ADR-0025 folded Muster into Fire).

## Context

Issue [#398](https://github.com/ssalter21/fantasy-ship-game/issues/398), under the item-authoring effort ([#363](https://github.com/ssalter21/fantasy-ship-game/issues/363)). ADR-0027 gave Press a second live arm and made the round's decision worth making — which exposed that the rest of the menu was not.

Of the five orders a captain could give, three were decoration:

- **Press** was free and unlimited, so it asked no question. A captain pressed every round of every fight; the only decision was *which phase*, and after ADR-0027 that decision reduces to "am I about to sink". A multiplier available on every round is not a tactic, it is a coefficient on the fight.
- **Man the Sails** granted a temporary Speed increase — on a stat ADR-0020 had already made emergent from a ship's weight, with the granted term surviving only as a `Battle.temp_speed` field nothing else fed. It was also **live-broken**: the bonus was reset at the top of the following round, *before* `Command_Break_Off`'s escape-eligibility assert ran, so manning the sails could never enable the escape it existed for, and a captain who tried to take that escape tripped an assert.
- **Reallocate** poured cargo between two of the ship's own fittings to buy a finer later jettison. #305 removed its UI and no release has offered it since; #399 then made jettison granularity a property of **how a build authors bulk across its layout**, which is where the decision belongs — in the refit, not in the round.

That left a round in which the captain's real choice was Press-or-jettison, and Press was always available.

## Decision

**The order set is exactly five: Press, Commit, Jettison, Break Off, Hold.**

**Press is rationed to once per battle**, at `PRESS_MULTIPLIER :: 3`. Free-and-unlimited was the defect, not the parameter: rationed, *when* a captain spends it becomes the question rather than *whether*. The multiplier rises because a smaller bump does not repay the timing — an order held for the right round has to be worth having held. Availability is a single flag on the `Battle` (`pressed: bit_set[Side]`, read through `combat_may_press`); the menu is told what is left on `Event_Battle_Menu.may_press`, and a second Press submitted in the same fight is a driver bug the combat layer asserts on, exactly as an ineligible Break Off is.

**Commit is Press's every-round sibling that pays for itself: x2 Brace, Fire to zero**, at `COMMIT_MULTIPLIER :: 2`.

It is **one-directional by construction**. The mirrored form (x2 Fire, Brace to zero) would be strictly dominant — a captain who is winning the exchange gives up nothing by taking it — so only the defensive direction is offered. The sacrifice is what buys its unrationed availability: because a committing captain deals **zero** damage that round, **Commit can never win a fight, only survive one**, so a captain who takes it every round loses. Press is Commit without the sacrifice, and that is precisely what is rationed.

This is what supersedes ADR-0017. That ADR pinned a Press to its own phase's total because two nested multipliers would have made one dominate the other; Commit is a second phase-total multiplier, so the question is settled differently now: **one order per round means Press and Commit can never compose**, and the two are un-nestable by the shape of the decision rather than by a rule about where the multiplication sits.

**Man the Sails is deleted**, taking `Battle.temp_speed` and the assert bug with it. Nothing in a battle grants Speed any more: a side's effective Speed is what its weight says it is (ADR-0020), so the escape gate, both tiebreaks and the effect context all read one number, and the failure mode is gone **by construction** rather than by a fix.

**Reallocate is deleted** — the command, its apply proc, and `Event_Cargo_Reallocated`.

**Hold is promoted to a real, named, player-facing order.** It is behaviourally neutral, but it is a stance a captain *takes* rather than the absence of a decision, it sits on the fight menu beside the other four, and it is a fact an item can gate on. It stays a named `Command` variant rather than a nil command because nil encodes "the driver submitted nothing" — a different fact, and one the scripted-opponent path (ADR-0008) still needs to be able to distinguish.

**Every order stays plain data, and the set costs a ghost snapshot nothing** (ADR-0008): the only battle-scoped state added is Press's spent flag, which lives on the `Battle` and not on the ship.

**Magnitudes remain placeholders** (ADR-0006, ADR-0012). 3 and 2 are a starting position for playtesting, not a balance claim.

## Consequences

- **The round is a decision.** A captain choosing between a tripled phase they get once, a doubled repair that costs them the exchange, weight over the side, an escape, and holding is answering a question every round; before this, four of the five answers were dominated or absent.
- **Press has a timing cost.** Spending it on round two to close out a Coastal skirmish means not having it on round nine of a Deep fight. This is the first order in the game whose value depends on the state of a fight rather than on the build.
- **Commit is the answer to a losing exchange that a build cannot pre-buy.** A ship carrying repair can trade a round of damage for twice the mending; a ship carrying none gets nothing from it, which is what keeps it from being a universal panic button.
- **A hostile can take none of this.** Scripted ships still Hold and Break Off only (ADR-0008), so every one of these orders is asymmetric in the player's favour until ghost-PvP makes the opponent a captured captain.
- **The fight menu shows a spent Press rather than hiding it.** The order set is fixed, so an order that vanished would read as one the game forgot; a rationed order that is dimmed reads as one already spent.
- **The escape window is read off Speed alone.** With no in-battle Speed grant, "will I be able to run" is answerable from the two ships' stat blocks at any point in the fight.
- **The combat Event vocabulary shrinks by one and gains none.** `Event_Cargo_Reallocated` goes; Press, Commit and Hold each act through a phase total, so what a captain ordered is already visible in the damage and repair beats presentation plays.

See GitHub issue [#398](https://github.com/ssalter21/fantasy-ship-game/issues/398) for the ticket, and ADR-0027 for the repair verb that made Brace worth pressing.
