package combat

import "../ship"

// Placeholder constants (ADR-0006): implementation defaults expected to move
// during playtesting, not final balance.
BASELINE_ROUND_COUNT :: 5
HARD_ROUND_CAP :: 20
BOOST_MULTIPLIER :: 2
MAN_THE_SAILS_SPEED_BONUS :: 2
JETTISON_SPEED_BONUS :: 1

// Side identifies one of the two ships in a Battle.
Side :: enum {
	A,
	B,
}

// Command is the captain's one decision per round (ADR-0006), shaped as an
// open union so future captains can expose different action sets by adding
// variants rather than restructuring the round loop.
Command :: union {
	Command_Boost,
	Command_Man_The_Sails,
	Command_Jettison_Cargo,
	Command_Leave_Combat,
	Command_Hold,
}

// Command_Boost multiplies the named phase's total output for the
// submitter's own ship, this round only.
Command_Boost :: struct {
	phase: ship.Category,
}

// Command_Man_The_Sails grants a temporary Speed boost lasting this round only.
Command_Man_The_Sails :: struct {}

// Command_Jettison_Cargo empties the cargo fitting at slot_index for a
// permanent (rest-of-battle) Speed boost, tracked for post-battle settlement.
Command_Jettison_Cargo :: struct {
	slot_index: ship.Slot_Index,
}

// Command_Leave_Combat ends the battle immediately for both ships. Only
// valid once the submitting side is escape-eligible (combat_may_leave).
Command_Leave_Combat :: struct {}

// Command_Hold is a formal no-op (ADR-0008): a scripted (non-player-
// controlled) ship's decision every round it isn't automatically taking
// Leave Combat. Contributes no Boost/Man the Sails/Jettison side effect.
Command_Hold :: struct {}

// Battle is a single encounter's transient state: the two ships being
// fought (their run-persistent HP/Durability/Speed live on *ship.Ship and
// are mutated in place) plus this-battle-only bookkeeping.
Battle :: struct {
	ships:      [Side]^ship.Ship,
	round:      int,
	temp_speed: [Side]int,
	perm_speed: [Side]int,
	jettisoned: [Side][dynamic]ship.Fitting,
	// escaped is which side(s) have taken Command_Leave_Combat this battle
	// (issue #54: a genuine set-of-enum over Side, so bit_set replaces the
	// [Side]bool membership array).
	escaped:    bit_set[Side],
	ended:      bool,
}

// End_Reason is why a Battle ended.
End_Reason :: enum {
	Destroyed,
	Left_Combat,
	Round_Cap,
}

// Round_State is the per-side working state threaded through one call to
// combat_resolve_round: the round's Boost choice, each phase's resolved
// output, and whether the side was sunk this round.
Round_State :: struct {
	boost_phase:   Maybe(ship.Category),
	buff_output:   int,
	defense_bonus: int,
	raw_damage:    int,
	sunk:          bool,
}

// Event is the only way a caller learns what happened inside a resolved
// round (mirrors ADR-0001's Command/Event boundary for the Sim).
Event :: union {
	Event_Damage_Dealt,
	Event_Ship_Sunk,
	Event_Cargo_Jettisoned,
	Event_Battle_Ended,
}

Event_Damage_Dealt :: struct {
	round:        int,
	target:       Side,
	raw_damage:   int,
	final_damage: int,
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

// combat_effective_speed is a side's Speed for escape/tiebreak purposes:
// base ship Speed plus this-round Man the Sails and any permanent
// Jettison Cargo bonuses accumulated so far.
combat_effective_speed :: proc(battle: ^Battle, side: Side) -> int {
	return battle.ships[side].speed + battle.temp_speed[side] + battle.perm_speed[side]
}

// combat_apply_jettison empties the cargo fitting at slot_index on side's
// ship for a permanent Speed boost, recording the fitting for post-battle
// settlement (ADR-0006).
combat_apply_jettison :: proc(battle: ^Battle, side: Side, slot_index: ship.Slot_Index, events: ^[dynamic]Event) {
	s := battle.ships[side]
	assert(slot_index >= 0 && int(slot_index) < len(s.layout), "Command_Jettison_Cargo slot_index out of range")
	layout_slot := &s.layout[slot_index]
	fitting, has_fitting := layout_slot.fitting.?
	assert(has_fitting && fitting.is_cargo, "Command_Jettison_Cargo slot_index does not hold a cargo fitting")
	layout_slot.fitting = nil
	battle.perm_speed[side] += JETTISON_SPEED_BONUS
	append(&battle.jettisoned[side], fitting)
	append(events, Event(Event_Cargo_Jettisoned{round = battle.round, side = side, fitting = fitting}))
}

// combat_phase_output sums the active-effect magnitude of every fitting of
// `phase`'s Category in s's fixed slot order (ADR-0006): every fitting with
// an active effect triggers exactly once per round, no per-fitting cooldown.
combat_phase_output :: proc(s: ^ship.Ship, phase: ship.Category) -> int {
	total := 0
	for layout_slot in s.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting || fitting.category != phase {
			continue
		}
		active, has_active := fitting.active.?
		if !has_active {
			continue
		}
		total += int(active.magnitude)
	}
	return total
}

// combat_may_leave reports whether side is escape-eligible for the round
// about to be resolved (ADR-0006): no leaving before the baseline round
// count, and only the strictly-faster side after that.
combat_may_leave :: proc(battle: ^Battle, side: Side) -> bool {
	if battle.round < BASELINE_ROUND_COUNT {
		return false
	}
	return combat_effective_speed(battle, side) > combat_effective_speed(battle, combat_opposite_side(side))
}

// combat_scripted_command decides a non-player-controlled side's Command for
// the round about to be resolved (ADR-0008): Leave Combat once escape-
// eligible (combat_may_leave), Hold every other round. A scripted ship never
// chooses Boost, Man the Sails, or Jettison Cargo in this slice.
combat_scripted_command :: proc(battle: ^Battle, side: Side) -> Command {
	if combat_may_leave(battle, side) {
		return Command_Leave_Combat{}
	}
	return Command_Hold{}
}

// combat_settle_jettisoned_cargo resolves side's jettisoned cargo once the
// battle has ended (ADR-0006): lost if side is the one that left combat,
// otherwise claimed by the opponent as spoils (destroyed or round-cap
// stalemate — settlement doesn't distinguish between those two).
combat_settle_jettisoned_cargo :: proc(battle: ^Battle, side: Side) -> (spoils: []ship.Fitting, lost: bool) {
	assert(battle.ended, "combat_settle_jettisoned_cargo called before the battle ended")
	if side in battle.escaped {
		return nil, true
	}
	return battle.jettisoned[side][:], false
}

combat_resolve_round :: proc(battle: ^Battle, cmds: [Side]Maybe(Command), events: ^[dynamic]Event) {
	assert(!battle.ended, "combat_resolve_round called after the battle already ended")
	battle.round += 1

	// Man the Sails is this-round-only: reset before applying this round's commands.
	for side in Side {
		battle.temp_speed[side] = 0
	}

	// round_state carries every per-side value threaded through the rest of
	// this round together (Standards review: was five parallel [Side]T locals).
	round_state: [Side]Round_State
	for side in Side {
		cmd, has_cmd := cmds[side].?
		if !has_cmd {
			continue
		}
		switch c in cmd {
		case Command_Boost:
			round_state[side].boost_phase = c.phase
		case Command_Man_The_Sails:
			battle.temp_speed[side] = MAN_THE_SAILS_SPEED_BONUS
		case Command_Jettison_Cargo:
			combat_apply_jettison(battle, side, c.slot_index, events)
		case Command_Leave_Combat:
			assert(combat_may_leave(battle, side), "Command_Leave_Combat submitted while not escape-eligible")
			battle.escaped += {side}
		case Command_Hold:
		// no-op (ADR-0008): contributes no Boost/Man the Sails/Jettison side effect.
		}
	}

	// Leave Combat ends the encounter immediately for both ships (ADR-0006):
	// no phase resolves the round a ship leaves.
	if battle.escaped != {} {
		battle.ended = true
		append(events, Event(Event_Battle_Ended{round = battle.round, reason = .Left_Combat, winner = nil}))
		return
	}

	boosted :: proc(total: int, phase: ship.Category, boost_phase: Maybe(ship.Category)) -> int {
		if p, ok := boost_phase.?; ok && p == phase {
			return total * BOOST_MULTIPLIER
		}
		return total
	}

	// Buff resolves first so its output is available to fold into this same
	// round's Defensive and Offensive totals below (ADR-0006).
	for side in Side {
		round_state[side].buff_output = boosted(combat_phase_output(battle.ships[side], .Buff), .Buff, round_state[side].boost_phase)
	}

	// Defensive and Offensive share the same shape (phase output + this
	// round's buff output, then boosted), so they resolve in one loop.
	for side in Side {
		buff := round_state[side].buff_output
		boost_phase := round_state[side].boost_phase
		round_state[side].defense_bonus = boosted(combat_phase_output(battle.ships[side], .Defensive)+buff, .Defensive, boost_phase)
		round_state[side].raw_damage = boosted(combat_phase_output(battle.ships[side], .Offensive)+buff, .Offensive, boost_phase)
	}

	for side in Side {
		target := combat_opposite_side(side)
		target_ship := battle.ships[target]
		final := max(0, round_state[side].raw_damage-(target_ship.durability + round_state[target].defense_bonus))
		if final > 0 {
			target_ship.hp = max(0, target_ship.hp-final)
			append(events, Event(Event_Damage_Dealt{round = battle.round, target = target, raw_damage = round_state[side].raw_damage, final_damage = final}))
		}
	}

	for side in Side {
		if battle.ships[side].hp <= 0 {
			round_state[side].sunk = true
			append(events, Event(Event_Ship_Sunk{round = battle.round, side = side}))
		}
	}

	if round_state[.A].sunk || round_state[.B].sunk {
		battle.ended = true
		winner: Maybe(Side)
		switch {
		case round_state[.A].sunk && round_state[.B].sunk:
			winner = combat_speed_tiebreak(battle)
		case round_state[.A].sunk:
			winner = Side.B
		case round_state[.B].sunk:
			winner = Side.A
		}
		append(events, Event(Event_Battle_Ended{round = battle.round, reason = .Destroyed, winner = winner}))
		return
	}

	if battle.round >= HARD_ROUND_CAP {
		battle.ended = true
		append(events, Event(Event_Battle_Ended{round = battle.round, reason = .Round_Cap, winner = combat_hp_tiebreak(battle)}))
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

// combat_hp_tiebreak resolves a hard-round-cap stalemate by higher HP,
// falling back to combat_speed_tiebreak on an exact HP tie (ADR-0006).
combat_hp_tiebreak :: proc(battle: ^Battle) -> Maybe(Side) {
	hp_a := battle.ships[.A].hp
	hp_b := battle.ships[.B].hp
	switch {
	case hp_a > hp_b:
		return Side.A
	case hp_b > hp_a:
		return Side.B
	case:
		return combat_speed_tiebreak(battle)
	}
}
