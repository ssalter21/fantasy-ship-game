package combat

import "../ship"

// Placeholder constants (ADR-0006): implementation defaults expected to move
// during playtesting, not final balance.
BASELINE_ROUND_COUNT :: 5
HARD_ROUND_CAP :: 20
PRESS_MULTIPLIER :: 3
COMMIT_MULTIPLIER :: 2

// Side identifies one of the two ships in a Battle.
Side :: enum {
	A,
	B,
}

// Command is the captain's one decision per round (ADR-0006), an open union of
// the action variants.
Command :: union {
	Command_Press,
	Command_Commit,
	Command_Jettison_Cargo,
	Command_Break_Off,
	Command_Hold,
}

// Command_Press multiplies the named phase's total output for the submitter's own
// ship, this round only, and is available at most once per battle (combat_may_press,
// ADR-0028).
Command_Press :: struct {
	phase: ship.Category,
}

// Command_Commit multiplies the submitter's Brace total by COMMIT_MULTIPLIER and
// zeroes its Fire total, for the round it is taken; unrationed. There is no mirrored
// form (ADR-0028) — the direction is the whole of what the order costs.
Command_Commit :: struct {}

// Command_Jettison_Cargo empties the cargo fitting at slot_index, shedding its
// weight — the ship is faster because it is lighter (ADR-0020), not by any
// granted bonus. The heaved cargo is destroyed, never settled.
Command_Jettison_Cargo :: struct {
	slot_index: ship.Slot_Index,
}

// Command_Break_Off ends the battle immediately for both ships. Only
// valid once the submitting side is escape-eligible (combat_may_break_off).
Command_Break_Off :: struct {}

// Command_Hold is the stance of taking no other order: a formal no-op that resolves
// nothing. It is a named variant, not a nil Command — a nil says the driver submitted
// nothing, which is a different fact (ADR-0028). A scripted (non-player-controlled)
// ship submits it every round it isn't taking Break Off (ADR-0008).
Command_Hold :: struct {}

// Battle is a single encounter's transient state: the two ships being
// fought (their voyage-persistent Hull/Speed live on *ship.Ship and
// are mutated in place) plus this-battle-only bookkeeping.
Battle :: struct {
	ships:   [Side]^ship.Ship,
	round:   int,
	// which side(s) have spent their one Press this battle (combat_may_press)
	pressed: bit_set[Side],
	// which side(s) have taken Command_Break_Off this battle
	escaped: bit_set[Side],
	// damage_taken_last_round is what each side's hull lost in the round before the one
	// being resolved — a Quantity an item may read (ship.Quantity.Damage_Taken_Last_Round),
	// so "the round after you were hit hard" is authorable. Battle-scoped and zeroed by the
	// zero Battle, which is what keeps it out of the Ghost_Snapshot: no voyage-scoped
	// counter exists to snapshot.
	damage_taken_last_round: [Side]int,
	// timing is each side's per-effect timing bookkeeping, indexed by slot and effect
	// (ship.Effect_Counters): what a Once_Per_Battle remembers and what a Charge has
	// banked. Zeroed by the zero Battle, so every counter starts a battle empty and no
	// timing policy has any voyage-scoped state to leak into a Ghost_Snapshot.
	timing:  [Side]ship.Effect_Counters,
	ended:   bool,
	// reason/winner mirror the Event_Battle_Ended, so a caller holding only the
	// Battle can read *how* it ended without replaying the event stream. Meaningful
	// only once `ended`: on an unended battle `reason` reads as its zero value
	// (.Destroyed) and must not be consulted.
	reason:  End_Reason,
	winner:  Maybe(Side),
}

// End_Reason is why a Battle ended.
End_Reason :: enum {
	Destroyed,
	Broke_Off,
	Round_Cap,
}

// Round_State is the per-side working state threaded through one call to
// combat_resolve_round: the round's Press choice and whether it committed, the
// round's damage output, and whether the side was sunk this round.
Round_State :: struct {
	press_phase: Maybe(ship.Category),
	commit:      bool,
	damage:      int,
	sunk:        bool,
}

// Event is the only way a caller learns what happened inside a resolved
// round (mirrors ADR-0001's Command/Event boundary for the Sim).
Event :: union {
	Event_Hull_Repaired,
	Event_Damage_Dealt,
	Event_Ship_Sunk,
	Event_Cargo_Jettisoned,
	Event_Battle_Ended,
}

// Event_Hull_Repaired reports the Hull a side's Brace phase restored this round:
// `amount` is what actually landed after the max-Hull cap, so a repair into a full
// hull emits nothing at all rather than an amount of 0.
Event_Hull_Repaired :: struct {
	round:  int,
	side:   Side,
	amount: int,
}

// Damage is one number, not a raw/final pair: ADR-0026 deleted the subtraction
// between them, so a side's Fire total *is* what the target's hull loses.
Event_Damage_Dealt :: struct {
	round:  int,
	target: Side,
	damage: int,
}

Event_Ship_Sunk :: struct {
	round: int,
	side:  Side,
}

Event_Cargo_Jettisoned :: struct {
	round:   int,
	side:    Side,
	fitting: ship.Fitting,
}

Event_Battle_Ended :: struct {
	round:  int,
	reason: End_Reason,
	winner: Maybe(Side),
}

combat_battle_create :: proc(a, b: ^ship.Ship) -> Battle {
	battle: Battle
	battle.ships[.A] = a
	battle.ships[.B] = b
	return battle
}

combat_opposite_side :: proc(side: Side) -> Side {
	return .B if side == .A else .A
}

// combat_round_facts flattens the battle into the plain data an expression may read for
// `side` this round (ship.Round_Facts): the round number, the side's own order, the damage
// it took last round, and the opponent as a **scouting report** — a counter block filtered
// to what concealment leaves visible, so no tree is ever handed the other ship.
//
// It is the input to both passes of the round's context build, and carries no speed: the
// speeds are computed *from* it.
combat_round_facts :: proc(battle: ^Battle, side: Side, order: ship.Captains_Order) -> ship.Round_Facts {
	return ship.Round_Facts {
		round                   = battle.round,
		captains_order          = order,
		damage_taken_last_round = battle.damage_taken_last_round[side],
		opponent                = ship.ship_scouting_report(battle.ships[combat_opposite_side(side)]),
	}
}

// combat_captains_order names a round's submitted order as an item reads it
// (ship.Captains_Order).
// Only the orders that shape a round's output have a reading: a round spent on Jettison or
// Break Off reads as Hold, which is exactly what it was to the phases — the ruling that
// keeps a once-a-voyage panic from being a thing an item rewards (CONTEXT.md).
combat_captains_order :: proc(submitted: Round_State) -> ship.Captains_Order {
	if submitted.commit {
		return .Commit
	}
	if phase, pressed := submitted.press_phase.?; pressed {
		return phase == .Brace ? .Press_Brace : .Press_Fire
	}
	return .Hold
}

// combat_effective_speed is a side's Speed for escape/tiebreak purposes. Nothing in a
// battle grants Speed: it is emergent from weight (ADR-0020), so a jettisoned hold
// reads faster only because ship_effective_speed weighs less.
//
// It reads the ship **against the round it is standing in**, so a speed modifier gated on
// the round number or on the damage it took last round is live for escape and tie-break
// too. The order it passes is Hold: an escape check is asked before the round's orders
// are given, so there is no order yet to read.
combat_effective_speed :: proc(battle: ^Battle, side: Side) -> int {
	return ship.ship_effective_speed(battle.ships[side], combat_round_facts(battle, side, .Hold))
}

// combat_may_press reports whether side still holds its one Press this battle: the
// ration is per *fight*, not per round, so a spent Press never comes back.
combat_may_press :: proc(battle: ^Battle, side: Side) -> bool {
	return side not_in battle.pressed
}

// combat_apply_jettison heaves the cargo out of the fitting at slot_index on side's
// ship (ship_jettison_cargo — the fitting stays installed, the remainder re-stows) and
// announces what went over the side. The freed weight makes the ship faster through
// ship_effective_speed on its own; the heaved cargo is destroyed, not settled.
//
// The refusal ship_jettison_cargo returns for a fitting carrying nothing is a driver
// bug in here, not a runtime rejection: the fight menu offers only laden berths, so a
// heave of nothing means presentation named a slot it should never have offered.
combat_apply_jettison :: proc(battle: ^Battle, side: Side, slot_index: ship.Slot_Index, events: ^[dynamic]Event) {
	s := battle.ships[side]
	assert(slot_index >= 0 && int(slot_index) < len(s.layout), "Command_Jettison_Cargo slot_index out of range")
	heaved, ok := ship.ship_jettison_cargo(s.layout, slot_index)
	assert(ok, "Command_Jettison_Cargo slot_index holds no cargo")

	append(events, Event(Event_Cargo_Jettisoned{round = battle.round, side = side, fitting = heaved}))
}

// combat_timings answers every effect on `side`'s ship for the round being resolved: the
// readings the phases resolve against, and that side's counters as the round leaves them.
//
// It **writes nothing back**. The caller resolving the round stores the counters; a caller
// only weighing a loadout drops them, so a peek can never spend a charge it never fired.
combat_timings :: proc(battle: ^Battle, side: Side) -> (timings: ship.Effect_Timings, counters: ship.Effect_Counters) {
	s := battle.ships[side]
	assert(len(s.layout) <= ship.SHIP_MAX_SLOTS, "a ship's layout is wider than the battle's timing table")
	counters = battle.timing[side]
	for layout_slot, slot_index in s.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting {
			continue
		}
		for effect_index in 0 ..< fitting.effect_count {
			timings[slot_index][effect_index], counters[slot_index][effect_index] = ship.effect_timing_advance(
				fitting.effects[effect_index].timing,
				battle.round,
				counters[slot_index][effect_index],
			)
		}
	}
	return timings, counters
}

// combat_phase_output sums the magnitude of every effect on `side`'s ship whose phase is
// `phase`, in fixed slot order and then in authored effect order (ADR-0006). Routing is on
// the **effect's own phase**, so one fitting may feed both phases and a Modify_Speed effect
// feeds neither — it acts through ship_effective_speed, above the phase totals.
//
// Takes the round's completed context — pass two, `round` plus both sides' `speeds` — so
// every quantity a magnitude tree may read is answered against live battle state, plus
// `timings`, the round's already-advanced timing readings: an effect that does not fire
// this round resolves to 0 (ship.effect_magnitude), and a ramp's growth arrives with it.
// self_slot is set per fitting so a tree reading its own visibility reads the slot the
// effect sits in.
combat_phase_output :: proc(
	battle: ^Battle,
	side: Side,
	phase: ship.Category,
	round: ship.Round_Facts,
	speeds: ship.Speeds,
	timings: ship.Effect_Timings,
) -> int {
	s := battle.ships[side]
	total := 0
	ctx := ship.ship_effect_context_in_battle(s, round, speeds)
	for layout_slot, slot_index in s.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting {
			continue
		}
		ctx.self_slot = layout_slot
		for effect_index in 0 ..< fitting.effect_count {
			effect := fitting.effects[effect_index]
			if effect_phase, feeds := effect.phase.?; !feeds || effect_phase != phase {
				continue
			}
			total += int(ship.effect_magnitude(effect, ctx, timings[slot_index][effect_index]))
		}
	}
	return total
}

// combat_phase_output_this_round is combat_phase_output for the round the battle is
// standing in, building the two-pass context itself: pass one's Round_Facts with **no
// order given**, then both sides' speeds off it. It answers "what is this side's phase
// worth right now" for a caller outside the round loop — the content and sim tests that
// weigh a loadout, where there is no order to name because none has been submitted.
//
// combat_resolve_round does not use it: a resolving round has orders, and it builds the
// two passes once for both phases rather than per phase.
//
// The timing readings it asks for are dropped rather than stored, so weighing a loadout
// costs the battle nothing — the reading is of the round as it stands, not of a round that
// happened.
combat_phase_output_this_round :: proc(battle: ^Battle, side: Side, phase: ship.Category) -> int {
	round := combat_round_facts(battle, side, .Hold)
	speeds := ship.Speeds {
		own      = combat_effective_speed(battle, side),
		opponent = combat_effective_speed(battle, combat_opposite_side(side)),
	}
	timings, _ := combat_timings(battle, side)
	return combat_phase_output(battle, side, phase, round, speeds, timings)
}

// combat_apply_repair restores `amount` Hull to side's ship, capped at its maximum
// (ADR-0027): repair fills the gap, never more, so a repair into a full hull is a
// no-op that emits nothing — the same shape as a zero-damage hit going unsaid. The
// event carries what was actually restored, not what was offered.
combat_apply_repair :: proc(battle: ^Battle, side: Side, amount: int, events: ^[dynamic]Event) {
	s := battle.ships[side]
	restored := min(amount, s.max_hull - s.hull)
	if restored <= 0 {
		return
	}
	s.hull += restored
	append(events, Event(Event_Hull_Repaired{round = battle.round, side = side, amount = restored}))
}

// combat_may_break_off reports whether side is escape-eligible for the round
// about to be resolved (ADR-0006): no breaking off before the baseline round
// count, and only the strictly-faster side after that.
combat_may_break_off :: proc(battle: ^Battle, side: Side) -> bool {
	if battle.round < BASELINE_ROUND_COUNT {
		return false
	}
	return combat_effective_speed(battle, side) > combat_effective_speed(battle, combat_opposite_side(side))
}

// combat_scripted_command decides a non-player-controlled side's Command for the
// round about to be resolved (ADR-0008): Break Off once escape-eligible
// (combat_may_break_off), Hold otherwise. A scripted ship never chooses Press,
// Commit, or Jettison Cargo.
combat_scripted_command :: proc(battle: ^Battle, side: Side) -> Command {
	if combat_may_break_off(battle, side) {
		return Command_Break_Off{}
	}
	return Command_Hold{}
}

combat_resolve_round :: proc(battle: ^Battle, cmds: [Side]Maybe(Command), events: ^[dynamic]Event) {
	assert(!battle.ended, "combat_resolve_round called after the battle already ended")
	battle.round += 1

	// round_state carries every per-side value threaded through the rest of this
	// round together.
	round_state: [Side]Round_State
	for side in Side {
		cmd, has_cmd := cmds[side].?
		if !has_cmd {
			continue
		}
		switch c in cmd {
		case Command_Press:
			assert(combat_may_press(battle, side), "Command_Press submitted after this battle's Press was spent")
			battle.pressed += {side}
			round_state[side].press_phase = c.phase
		case Command_Commit:
			round_state[side].commit = true
		case Command_Jettison_Cargo:
			combat_apply_jettison(battle, side, c.slot_index, events)
		case Command_Break_Off:
			assert(combat_may_break_off(battle, side), "Command_Break_Off submitted while not escape-eligible")
			battle.escaped += {side}
		case Command_Hold:
		// no-op (ADR-0008)
		}
	}

	// Break Off ends the encounter immediately for both ships (ADR-0006):
	// no phase resolves the round a ship breaks off.
	if battle.escaped != {} {
		battle.ended = true
		battle.reason = .Broke_Off
		battle.winner = nil
		append(events, Event(Event_Battle_Ended{round = battle.round, reason = battle.reason, winner = battle.winner}))
		return
	}

	// scaled applies the round's order to one phase's total. A Press multiplies its own
	// named phase and nothing else (ADR-0006); a Commit multiplies Brace and zeroes Fire.
	// One proc rather than two because a round carries one order: the two scalings are
	// alternatives, and composing them is not a case that exists.
	scaled :: proc(total: int, phase: ship.Category, order: Round_State) -> int {
		if order.commit {
			return total * COMMIT_MULTIPLIER if phase == .Brace else 0
		}
		if p, ok := order.press_phase.?; ok && p == phase {
			return total * PRESS_MULTIPLIER
		}
		return total
	}

	// Both phases are **totalled off the hull the round opened with**, before either
	// writes to it, so with both feeding a consumer either Press reads: Fire multiplies
	// the damage dealt, Brace the Hull restored.
	//
	// Summing here rather than at each phase's write is what keeps repair's ordering
	// consumed by the death check alone (ADR-0027): a Hull-gated fitting reads the hull
	// its captain saw when they gave the order, so patching a hull cannot switch off the
	// desperate ship's own guns mid-round.

	// The round's context is built in **two passes**, and the order is forced by the
	// layering rule rather than chosen: a tree may read any quantity computed strictly
	// below its own layer, and Speed is the one stat with a modifier layer. So pass one
	// resolves every Modify_Speed effect against the round's facts *with no speeds in the
	// context at all* (ship_effect_context_pre_speed), and pass two resolves the phases
	// against those speeds. Authoring is what guarantees pass one can be answered — a
	// Modify_Speed tree reading a speed is rejected at authoring time (effect_modify_speed).
	//
	// Pass one takes the round's facts rather than nothing at all, which is what makes a
	// speed modifier gated on the round number, the captain's own order or the damage taken
	// last round a live item: without them there is no reading for its gate to open on.
	round_facts: [Side]ship.Round_Facts
	for side in Side {
		round_facts[side] = combat_round_facts(battle, side, combat_captains_order(round_state[side]))
	}

	speed: [Side]int
	for side in Side {
		speed[side] = ship.ship_effective_speed(battle.ships[side], round_facts[side])
	}

	speeds: [Side]ship.Speeds
	for side in Side {
		speeds[side] = ship.Speeds{own = speed[side], opponent = speed[combat_opposite_side(side)]}
	}

	// Timings are advanced once per side for the whole round, ahead of both phases, and the
	// counters stored — so an effect fires at most once a round however many phases read the
	// table, and a round that ended in a Break Off above spent nothing.
	timings: [Side]ship.Effect_Timings
	for side in Side {
		timings[side], battle.timing[side] = combat_timings(battle, side)
	}

	repair: [Side]int
	for side in Side {
		repair[side] = scaled(
			combat_phase_output(battle, side, .Brace, round_facts[side], speeds[side], timings[side]),
			.Brace,
			round_state[side],
		)
		round_state[side].damage = scaled(
			combat_phase_output(battle, side, .Fire, round_facts[side], speeds[side], timings[side]),
			.Fire,
			round_state[side],
		)
	}

	// Brace lands first — ahead of the damage below and the death check under it — which
	// is what the ordering is *for*: a repair can save a captain on the round they would
	// otherwise have sunk. Both sides repair before either fires, so the phase stays
	// simultaneous.
	for side in Side {
		combat_apply_repair(battle, side, repair[side], events)
	}

	for side in Side {
		target := combat_opposite_side(side)
		target_ship := battle.ships[target]
		// Damage lands whole (ADR-0026): nothing is subtracted from a side's Fire total
		// on its way to the target's hull — a Brace phase adds to its own hull instead.
		damage := round_state[side].damage
		// What the target's hull actually lost, which is what it will read next round as
		// Damage_Taken_Last_Round: overkill against a hull already at 0 is not damage taken.
		battle.damage_taken_last_round[target] = min(damage, target_ship.hull)
		if damage > 0 {
			target_ship.hull = max(0, target_ship.hull-damage)
			append(events, Event(Event_Damage_Dealt{round = battle.round, target = target, damage = damage}))
		}
	}

	for side in Side {
		if battle.ships[side].hull <= 0 {
			round_state[side].sunk = true
			append(events, Event(Event_Ship_Sunk{round = battle.round, side = side}))
		}
	}

	if round_state[.A].sunk || round_state[.B].sunk {
		battle.ended = true
		battle.reason = .Destroyed
		switch {
		case round_state[.A].sunk && round_state[.B].sunk:
			battle.winner = combat_speed_tiebreak(battle)
		case round_state[.A].sunk:
			battle.winner = Side.B
		case round_state[.B].sunk:
			battle.winner = Side.A
		}
		append(events, Event(Event_Battle_Ended{round = battle.round, reason = battle.reason, winner = battle.winner}))
		return
	}

	if battle.round >= HARD_ROUND_CAP {
		battle.ended = true
		battle.reason = .Round_Cap
		battle.winner = combat_hull_tiebreak(battle)
		append(events, Event(Event_Battle_Ended{round = battle.round, reason = battle.reason, winner = battle.winner}))
	}
}

// combat_speed_tiebreak resolves a same-round mutual kill by higher
// effective Speed (ADR-0006); no winner if Speed is exactly equal.
combat_speed_tiebreak :: proc(battle: ^Battle) -> Maybe(Side) {
	speed_a := combat_effective_speed(battle, .A)
	speed_b := combat_effective_speed(battle, .B)
	switch {
	case speed_a > speed_b:
		return Side.A
	case speed_b > speed_a:
		return Side.B
	case:
		return nil
	}
}

// combat_hull_tiebreak resolves a hard-round-cap stalemate by higher Hull,
// falling back to combat_speed_tiebreak on an exact Hull tie (ADR-0006).
combat_hull_tiebreak :: proc(battle: ^Battle) -> Maybe(Side) {
	hull_a := battle.ships[.A].hull
	hull_b := battle.ships[.B].hull
	switch {
	case hull_a > hull_b:
		return Side.A
	case hull_b > hull_a:
		return Side.B
	case:
		return combat_speed_tiebreak(battle)
	}
}
