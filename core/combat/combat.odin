package combat

import "../ship"

// Placeholder constants (ADR-0006): implementation defaults expected to move
// during playtesting, not final balance.
BASELINE_ROUND_COUNT :: 5
HARD_ROUND_CAP :: 20
BOOST_MULTIPLIER :: 2
MAN_THE_SAILS_SPEED_BONUS :: 2

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

// Command_Jettison_Cargo empties the cargo fitting at slot_index, shedding its
// weight — which makes the ship faster because it is lighter (ADR-0020), not by
// any granted bonus. The heaved treasure is destroyed, never settled: nothing is
// tracked past the emptying.
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

// combat_effective_speed is a side's Speed for escape/tiebreak purposes: the
// ship's effective Speed (ship_effective_speed — base plus Modify_Speed fittings,
// minus weight/10, so a heavier hold is a slower ship) plus this-round Man the
// Sails. Jettison no longer adds a bonus here — dropping a hold lowers the ship's
// weight, so the faster reading comes straight out of ship_effective_speed
// (ADR-0020, #158): Speed is emergent, not granted.
combat_effective_speed :: proc(battle: ^Battle, side: Side) -> int {
	return ship.ship_effective_speed(battle.ships[side]) + battle.temp_speed[side]
}

// combat_apply_jettison empties the cargo fitting at slot_index on side's ship,
// shedding its weight (ADR-0020, #159): null the slot and emit the event, nothing
// more. The freed weight makes the ship faster through ship_effective_speed on its
// own, and the heaved treasure is destroyed rather than settled. The assert that
// the slot holds a cargo fitting is what keeps an empty hold from being heaved for
// free Speed — an empty hold weighs nothing, so there is no Speed in it to buy
// (no new rule).
combat_apply_jettison :: proc(battle: ^Battle, side: Side, slot_index: ship.Slot_Index, events: ^[dynamic]Event) {
	s := battle.ships[side]
	assert(slot_index >= 0 && int(slot_index) < len(s.layout), "Command_Jettison_Cargo slot_index out of range")
	layout_slot := &s.layout[slot_index]
	fitting, has_fitting := layout_slot.fitting.?
	assert(has_fitting && fitting.is_cargo, "Command_Jettison_Cargo slot_index does not hold a cargo fitting")
	layout_slot.fitting = nil
	append(events, Event(Event_Cargo_Jettisoned{round = battle.round, side = side, fitting = fitting}))
}

// combat_phase_output sums the active-effect magnitude of every fitting of
// `phase`'s Category on `side`'s ship in fixed slot order (ADR-0006): every
// fitting with an active Phase_Contribution effect triggers exactly once per
// round, no per-fitting cooldown. Active effects of a Modify_* kind (stat
// modifiers, issue #92) never contribute here — they act through the effective-
// stat readers, not the phase totals. Takes the whole battle rather than a bare
// ship (issue #94) so a conditional effect resolves against live battle state:
// the round and both sides' live effective speeds are captured into the context
// once, and self_slot is set per fitting so an own-concealment trigger reads the
// slot the effect actually sits in.
combat_phase_output :: proc(battle: ^Battle, side: Side, phase: ship.Category) -> int {
	s := battle.ships[side]
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
		if !has_active || active.kind != .Phase_Contribution {
			continue
		}
		ctx.self_slot = layout_slot
		total += int(ship.effect_magnitude(active, ctx))
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

	// Buff resolves first so its output is available to this same round's
	// Offensive total below (ADR-0006, as amended by issue #151).
	for side in Side {
		round_state[side].buff_output = boosted(combat_phase_output(battle, side, .Buff), .Buff, round_state[side].boost_phase)
	}

	// Defensive and Offensive resolve together: each is its own fittings'
	// output, boosted, and Offensive alone takes this round's buff.
	//
	// **Buff feeds Offensive only** (#151). It used to feed `defense_bonus` too,
	// which made it the one category worth twice its own number: a magnitude spent
	// on Buff raised your damage *and* lowered your opponent's, so a single item
	// pushed both walls of the band at once and there was no direction left to tune
	// it in. It also fabricated soak out of nothing — a ship with no Defensive
	// fitting still soaked its own buff — which is what pinned soak at ~90% of raw
	// and made a starting ship unable to sink its own mirror (20 rounds, 1 damage a
	// round). Decisively: soak is *subtracted* from raw, so soak's vocabulary has to
	// stay small, and Buff's does not — Admiral's Guard is +3 per Crew aboard, so a
	// Crew build folded +12 into its own defence and became unbeatable by any
	// starting ship. Raw can absorb a 12; soak cannot. See the band note on
	// core/run's hostile_roster.
	//
	// **A Boost multiplies its own phase's fittings, and nothing else** — the
	// buff_output above is already boosted by Boost Buff, so it is added *after*
	// Boost Offensive rather than inside it. Nesting them (the pre-#151 shape,
	// `boosted(offensive + buff, .Offensive)`) made Boost Offensive strictly
	// dominate Boost Buff at 2(O+B) against O+2B, which is a captain's Command that
	// is never the right answer. Boosting a phase's own fittings is also what
	// ADR-0006 actually says ("multiplies that phase's fitting output"), so the two
	// Boosts now answer a real question: press the guns, or press the crew.
	for side in Side {
		boost_phase := round_state[side].boost_phase
		round_state[side].defense_bonus = boosted(combat_phase_output(battle, side, .Defensive), .Defensive, boost_phase)
		round_state[side].raw_damage = boosted(combat_phase_output(battle, side, .Offensive), .Offensive, boost_phase) + round_state[side].buff_output
	}

	for side in Side {
		target := combat_opposite_side(side)
		target_ship := battle.ships[target]
		// Effective Durability (issue #92): base plus any Stat_Modifier
		// fittings, so a +Durability fitting measurably reduces damage taken.
		final := max(0, round_state[side].raw_damage-(ship.ship_effective_durability(target_ship) + round_state[target].defense_bonus))
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
