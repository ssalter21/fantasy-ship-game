# ADR-0027: Brace is repair, resolving ahead of Fire

## Status

Accepted — **completes ADR-0026**, which deleted the subtracted side of the damage exchange and left Brace a phase with no consumer. The rest of ADR-0006 stands: phased rounds, simultaneous resolution, the one captain decision per round, Speed-gated escape, the hard round cap, permadeath, determinism. ADR-0012's stat-modifier effects lose one of their two targets (see below).

## Context

Issue [#397](https://github.com/ssalter21/fantasy-ship-game/issues/397), under the item-authoring effort ([#363](https://github.com/ssalter21/fantasy-ship-game/issues/363)). ADR-0026 ruled that damage lands whole and recorded the one-ticket gap it opened: `Command_Press{phase}` still accepted Brace, `combat_phase_output` still answered for it, eleven roster items still declared it — and nothing read the number. Press had decayed to *"Press Fire, or waste it."*

The replacement has to be a defensive verb that is not a subtraction. Two things fall out of that:

- **A subtracting term cannot be scaled by the site** (ADR-0019), which is what made bulwark decay from ~47% absorption at Coastal to ~15% in The Deep and left a defensive slot worth about a quarter of an offensive one.
- **A ceiling nothing can fill is worth nothing.** Max Hull was raisable by five roster items and by a Trade axis, but no mechanic ever refilled Hull inside a voyage, so raising the ceiling bought headroom the captain could not occupy.

## Decision

**Brace repairs.** `Effect_Kind` gains `Repair`, whose resolved magnitude restores the owning ship's Hull, and `ship_phase_verb` names the pairing once: Fire fittings carry `Phase_Contribution`, Brace fittings carry `Repair`. `combat_phase_output` sums a phase through its own verb, so an effect authored onto the wrong phase resolves through nothing — a roster test rejects it rather than letting it ship inert.

**Repair resolves inside Brace, strictly ahead of Fire.** Both sides repair before either fires, so the phase stays simultaneous, and the ordering is consumed by exactly one thing: the death check. **A repair can save a captain on the round they would otherwise have sunk.** That, and not the arithmetic, is what earns Brace a phase rather than a summing pass.

**Both phases are totalled before either writes to a hull**, and only then applied in phase order. Otherwise the ordering would be consumed by a second thing nobody authored: a `Condition_Hull_Below` Fire fitting reading the hull its own carpenters had just patched, so that repairing switched off the desperate ship's own guns mid-round. A Hull-gated fitting reads the hull its captain saw when they gave the order.

**Repair never heals past maximum Hull.** `combat_apply_repair` restores the *gap*, so a repair into a full hull is a no-op that emits nothing — the same shape as a zero-damage hit going unsaid. `Event_Hull_Repaired` carries what actually landed, never what was offered. This is what gives the Max Hull ceiling a value raising it never had on its own.

**`Modify_Max_Hull` is deleted with `Modify_Durability` before it.** `Effect_Kind` is `{Phase_Contribution, Modify_Speed, Repair}`. No fitting moves the Hull ceiling any more: repair fills it instead, and the one thing that still raises it is a Trade axis. `ship_effective_max_hull` goes with the verb, and with only Speed left to modify, the shared `ship_effective_stat` shape folds into `ship_effective_speed`. `Ship.max_hull` is read directly everywhere.

**The eleven Brace roster items are re-authored as repair items**, keeping their size, weight, tags and tier — the roster's shape, and every test standing on it, does not move. Where a name promised prevention it is renamed, because the game no longer has prevention to promise: Iron Plating → **Oakum & Pitch**, Ballast Stones → **Spare Timbers**, Boarding Nets → **Carpenter's Mate**, Barricades → **Deck Pumps**, Reinforced Hull → **Shipwright's Kit**, Adamant Bulwark → **Adamant Sigil**, Treasure Vault → **Shipwright's Stores**. Salt Provisions, Ship's Surgeon, Dragon Turtle and Titan's Heart keep theirs. The starting Captain's Quarters repairs too, so every ship in the game brings some Brace to the phase.

**The site does not scale repair.** `voyage_stakes_scales_category` still exempts Brace, on a new reason: a hostile's repair is subtracted from the player's damage in all but name, and a repair that reaches the player's per-round Fire output is an unkillable hostile — ADR-0019's zero-damage floor, arrived at from the other direction. A hostile's staying power grows with the site through its Hull pool, which has no such ceiling. (ADR-0026 left this open as this ticket's call.)

**Magnitudes remain placeholders** (ADR-0006, ADR-0012). Repair is authored against the Fire ladder cell for cell — a point restored is worth about a point denied — which is a starting position, not a balance claim.

## Consequences

- **Press is a choice again.** Press Brace doubles the Hull a round restores, Press Fire the damage it deals, and the `{phase}` shape ADR-0025 kept against exactly this now has two live arms.
- **A fight can be survived rather than merely won.** The captain who is one round from sinking has a build-assembled answer, so Hull stops being a strictly-decreasing voyage resource.
- **Fights are longer where repair is carried**, on both sides — a hostile drawing a repair item mends between exchanges. The hostile band tests are the tripwire if that pushes a Coastal fight past the escape gate.
- **A category and a verb can now disagree**, which is a new way to author a dead item. `ship_phase_verb` plus the roster test is the whole of the guard; nothing in the type system stops it.
- **Max Hull is a Trade axis and nothing else.** Its swing row keeps the meaning ADR-0026's re-anchoring gave it, and repair is what makes buying it worth doing.
- **A ghost snapshot is unchanged** — one enum member renamed, no new state (ADR-0008).
- **The UI plays repair as its own beat** ahead of the round's exchange, mirroring the resolution order.

See GitHub issue [#397](https://github.com/ssalter21/fantasy-ship-game/issues/397) for the ticket, and ADR-0026 for the deletion this completes.
