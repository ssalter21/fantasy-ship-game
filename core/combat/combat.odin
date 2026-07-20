package combat

import "../ship"

// Placeholder constants (ADR-0006): implementation defaults expected to move
// during playtesting, not final balance.
BASELINE_ROUND_COUNT :: 5
HARD_ROUND_CAP :: 20
PRESS_MULTIPLIER :: 2
MAN_THE_SAILS_SPEED_BONUS :: 2

// Side identifies one of the two ships in a Battle.
Side :: enum {
	A,
	B,
}

// Command is the captain's one decision per round (ADR-0006), an open union of
// the action variants.
Command :: union {
	Command_Press,
	Command_Man_The_Sails,
	Command_Jettison_Cargo,
	Command_Reallocate,
	Command_Break_Off,
	Command_Hold,
}

// Command_Press multiplies the named phase's total output for the
// submitter's own ship, this round only.
Command_Press :: struct {
	phase: ship.Category,
}

// Command_Man_The_Sails grants a temporary Speed increase lasting this round only.
Command_Man_The_Sails :: struct {}

// Command_Jettison_Cargo empties the cargo fitting at slot_index, shedding its
// weight — the ship is faster because it is lighter (ADR-0020), not by any
// granted bonus. The heaved cargo is destroyed, never settled.
Command_Jettison_Cargo :: struct {
	slot_index: ship.Slot_Index,
}

// Command_Reallocate pours the cargo fitting at `from` into `to` up to `to`'s
// remaining capacity, both the submitter's own cargo slots. It shifts **no
// weight** — the cargo stays aboard — so it changes no Speed the round it is
// issued (ADR-0020). What it buys is *jettison granularity*: a later Jettison can
// shed the smaller `to` slot rather than the whole `from` hold. Free outside
// battle (a Refit move); inside battle it costs the round like any command.
Command_Reallocate :: struct {
	from: ship.Slot_Index,
	to:   ship.Slot_Index,
}

// Command_Break_Off ends the battle immediately for both ships. Only
// valid once the submitting side is escape-eligible (combat_may_break_off).
Command_Break_Off :: struct {}

// Command_Hold is a formal no-op (ADR-0008): a scripted (non-player-controlled)
// ship's decision every round it isn't taking Break Off.
Command_Hold :: struct {}

// Battle is a single encounter's transient state: the two ships being
// fought (their voyage-persistent Hull/Speed live on *ship.Ship and
// are mutated in place) plus this-battle-only bookkeeping.
Battle :: struct {
	ships:      [Side]^ship.Ship,
	round:      int,
	temp_speed: [Side]int,
	// which side(s) have taken Command_Break_Off this battle
	escaped:    bit_set[Side],
	ended:      bool,
	// reason/winner mirror the Event_Battle_Ended, so a caller holding only the
	// Battle can read *how* it ended without replaying the event stream. Meaningful
	// only once `ended`: on an unended battle `reason` reads as its zero value
	// (.Destroyed) and must not be consulted.
	reason:     End_Reason,
	winner:     Maybe(Side),
}

// End_Reason is why a Battle ended.
End_Reason :: enum {
	Destroyed,
	Broke_Off,
	Round_Cap,
}

// Round_State is the per-side working state threaded through one call to
// combat_resolve_round: the round's Press choice, the round's damage output,
// and whether the side was sunk this round.
Round_State :: struct {
	press_phase: Maybe(ship.Category),
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
	Event_Cargo_Reallocated,
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

// Event_Cargo_Reallocated reports a Command_Reallocate: `amount` cargo moved
// from slot `from` to slot `to` on `side`'s ship. It shifts no weight, so a caller
// rendering it must not imply a Speed change.
Event_Cargo_Reallocated :: struct {
	round:  int,
	side:   Side,
	from:   ship.Slot_Index,
	to:     ship.Slot_Index,
	amount: int,
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

// combat_effective_speed is a side's Speed for escape/tiebreak purposes: the
// ship's effective Speed (ship_effective_speed) plus this-round Man the Sails.
// Speed is emergent from weight, not granted (ADR-0020): a jettisoned hold reads
// faster only because ship_effective_speed weighs less, with no bonus added here.
combat_effective_speed :: proc(battle: ^Battle, side: Side) -> int {
	return ship.ship_effective_speed(battle.ships[side]) + battle.temp_speed[side]
}

// combat_apply_jettison empties the cargo fitting at slot_index on side's ship,
// shedding its weight (ADR-0020): null the slot and emit the event. The freed
// weight makes the ship faster through ship_effective_speed on its own; the heaved
// cargo is destroyed, not settled. The cargo-fitting assert keeps an empty hold —
// which weighs nothing — from being heaved for free Speed.
combat_apply_jettison :: proc(battle: ^Battle, side: Side, slot_index: ship.Slot_Index, events: ^[dynamic]Event) {
	s := battle.ships[side]
	assert(slot_index >= 0 && int(slot_index) < len(s.layout), "Command_Jettison_Cargo slot_index out of range")
	layout_slot := &s.layout[slot_index]
	fitting, has_fitting := layout_slot.fitting.?
	assert(has_fitting && fitting.is_cargo, "Command_Jettison_Cargo slot_index does not hold a cargo fitting")
	layout_slot.fitting = nil
	append(events, Event(Event_Cargo_Jettisoned{round = battle.round, side = side, fitting = fitting}))
}

// combat_apply_reallocate pours as much of the cargo fitting at `from` into `to`
// as `to` can still hold, shifting **no weight** (ADR-0020): the total cargo
// aboard — and thus the ship's weight and Speed — is unchanged this round. What it
// buys is *jettison granularity*: `to`'s slot size is the denomination the move
// rounds to. The asserts mirror combat_apply_jettison and encode what the battle
// menu's legal-picks-only offering guarantees: `from` holds cargo, `to` is a
// distinct cargo-capable slot with room, and the move is non-empty.
combat_apply_reallocate :: proc(battle: ^Battle, side: Side, from, to: ship.Slot_Index, events: ^[dynamic]Event) {
	s := battle.ships[side]
	assert(from != to, "Command_Reallocate from and to are the same slot")
	assert(from >= 0 && int(from) < len(s.layout), "Command_Reallocate from slot_index out of range")
	assert(to >= 0 && int(to) < len(s.layout), "Command_Reallocate to slot_index out of range")

	from_slot := &s.layout[from]
	src, has_src := from_slot.fitting.?
	assert(has_src && src.is_cargo, "Command_Reallocate from does not hold a cargo fitting")

	to_slot := &s.layout[to]
	dest_fill := 0
	if dest, has_dest := to_slot.fitting.?; has_dest {
		assert(dest.is_cargo, "Command_Reallocate to holds a non-cargo fitting")
		dest_fill = dest.stack_count
	}
	room := ship.ship_cargo_slot_contribution(to_slot.slot.size) - dest_fill
	moved := min(src.stack_count, room)
	assert(moved > 0, "Command_Reallocate moves no cargo (source empty or destination full)")

	// Drain the source, nulling it if emptied: a zero-count cargo fitting is not a
	// thing (ship_fitting_fits), an empty hold is an empty slot.
	if moved == src.stack_count {
		from_slot.fitting = nil
	} else {
		src.stack_count -= moved
		from_slot.fitting = src
	}

	// Land it: grow the destination's cargo fitting, or create one sized to the slot
	// (ship_fitting_cargo) when the slot was empty.
	if dest, has_dest := to_slot.fitting.?; has_dest {
		dest.stack_count += moved
		to_slot.fitting = dest
	} else {
		to_slot.fitting = ship.ship_fitting_cargo("Cargo", to_slot.slot.size, moved)
	}

	append(events, Event(Event_Cargo_Reallocated{round = battle.round, side = side, from = from, to = to, amount = moved}))
}

// combat_phase_output sums the active-effect magnitude of every fitting of
// `phase`'s Category on `side`'s ship in fixed slot order (ADR-0006): each fitting
// whose active effect carries that phase's verb (ship_phase_verb — damage for Fire,
// repair for Brace) triggers once per round, no cooldown. Modify_Speed never
// contributes here — it acts through ship_effective_speed, not the phase totals.
// Takes the whole battle, not a bare ship, so a conditional effect resolves against
// live battle state: the round and both sides' effective speeds go into the context,
// and self_slot is set per fitting so an own-concealment trigger reads the slot the
// effect sits in.
combat_phase_output :: proc(battle: ^Battle, side: Side, phase: ship.Category) -> int {
	s := battle.ships[side]
	verb := ship.ship_phase_verb(phase)
	total := 0
	ctx := ship.ship_effect_context_in_battle(s, ship.Battle_State{
		round          = battle.round,
		own_speed      = combat_effective_speed(battle, side),
		opponent_speed = combat_effective_speed(battle, combat_opposite_side(side)),
	})
	for layout_slot in s.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting || fitting.category != phase {
			continue
		}
		active, has_active := fitting.active.?
		if !has_active || active.kind != verb {
			continue
		}
		ctx.self_slot = layout_slot
		total += int(ship.effect_magnitude(active, ctx))
	}
	return total
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
// (combat_may_break_off), Hold otherwise. A scripted ship never chooses Press, Man
// the Sails, or Jettison Cargo; nor Reallocate, which is player-only because it
// buys precision for a later jettison a scripted ship never makes.
combat_scripted_command :: proc(battle: ^Battle, side: Side) -> Command {
	if combat_may_break_off(battle, side) {
		return Command_Break_Off{}
	}
	return Command_Hold{}
}

combat_resolve_round :: proc(battle: ^Battle, cmds: [Side]Maybe(Command), events: ^[dynamic]Event) {
	assert(!battle.ended, "combat_resolve_round called after the battle already ended")
	battle.round += 1

	// Man the Sails is this-round-only: reset before applying this round's commands.
	for side in Side {
		battle.temp_speed[side] = 0
	}

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
			round_state[side].press_phase = c.phase
		case Command_Man_The_Sails:
			battle.temp_speed[side] = MAN_THE_SAILS_SPEED_BONUS
		case Command_Jettison_Cargo:
			combat_apply_jettison(battle, side, c.slot_index, events)
		case Command_Reallocate:
			combat_apply_reallocate(battle, side, c.from, c.to, events)
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

	pressed :: proc(total: int, phase: ship.Category, press_phase: Maybe(ship.Category)) -> int {
		if p, ok := press_phase.?; ok && p == phase {
			return total * PRESS_MULTIPLIER
		}
		return total
	}

	// Both phases are **totalled off the hull the round opened with**, before either
	// writes to it. A Press multiplies its own phase's fittings and nothing else
	// (ADR-0006), so with both phases feeding a consumer either Press reads: Fire
	// doubles the damage dealt, Brace the Hull restored.
	//
	// Summing here rather than at each phase's write is what keeps repair's ordering
	// consumed by the death check alone (ADR-0027): a Hull-gated fitting reads the hull
	// its captain saw when they gave the order, so patching a hull cannot switch off the
	// desperate ship's own guns mid-round.
	repair: [Side]int
	for side in Side {
		repair[side] = pressed(combat_phase_output(battle, side, .Brace), .Brace, round_state[side].press_phase)
		round_state[side].damage = pressed(combat_phase_output(battle, side, .Fire), .Fire, round_state[side].press_phase)
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
