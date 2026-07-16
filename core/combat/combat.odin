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
	Command_Reallocate,
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

// Command_Reallocate moves treasure between two of the submitter's own cargo
// slots, pouring the cargo fitting at `from` into `to` up to `to`'s remaining
// capacity. It shifts **no weight** — the treasure stays aboard — so it changes
// no Speed the round it is issued (ADR-0020, #157); what it buys is *jettison
// granularity*, letting a later Jettison shed a finer amount than the current
// hold allows (split a full Large into a Small and the next heave sheds exactly
// 10, one Speed, instead of a forced 40). Reallocation is free outside battle (a
// Refit move); inside battle it costs the round like any command — that tempo is
// the price of the precision.
Command_Reallocate :: struct {
	from: ship.Slot_Index,
	to:   ship.Slot_Index,
}

// Command_Leave_Combat ends the battle immediately for both ships. Only
// valid once the submitting side is escape-eligible (combat_may_leave).
Command_Leave_Combat :: struct {}

// Command_Hold is a formal no-op (ADR-0008): a scripted (non-player-
// controlled) ship's decision every round it isn't automatically taking
// Leave Combat. Contributes no Boost/Man the Sails/Jettison side effect.
Command_Hold :: struct {}

// Battle is a single encounter's transient state: the two ships being
// fought (their run-persistent Hull/Durability/Speed live on *ship.Ship and
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
	// reason/winner mirror the Event_Battle_Ended emitted the moment the battle
	// ends, so a caller holding only the Battle — run_finish_ship_battle, which must
	// pay the wreck's hold to a captain who sank it (#159) — can read *how* it ended
	// without replaying the event stream. Meaningful only once `ended`: on an unended
	// battle `reason` reads as its zero value (.Destroyed) and must not be consulted.
	reason:     End_Reason,
	winner:     Maybe(Side),
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
	muster_output:   int,
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
	Event_Cargo_Reallocated,
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

// Event_Cargo_Reallocated reports a Command_Reallocate: `amount` treasure moved
// from slot `from` to slot `to` on `side`'s ship. It shifts no weight, so a caller
// rendering it must not imply a Speed change — the round was spent, the number did
// not move (that is the tell that it bought precision, not Speed).
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

// combat_apply_reallocate moves treasure between two of side's own cargo slots,
// shifting **no weight** (ADR-0020, #157): it pours as much of the cargo fitting at
// `from` into `to` as `to` can still hold, so the total treasure aboard — and thus
// the ship's weight and its Speed — is unchanged this round. What it buys is
// *jettison granularity*: the destination slot's size is the denomination the move
// rounds to (#156), so splitting a full Large into an empty Small lets the next
// Jettison shed exactly that Small (10 -> 1 Speed) rather than being forced to heave
// the whole 40. The asserts are what the battle menu's legal-picks-only offering
// guarantees, mirroring combat_apply_jettison: `from` holds cargo with treasure, `to`
// is a distinct cargo-capable slot with room, and the move is non-empty.
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
	assert(moved > 0, "Command_Reallocate moves no treasure (source empty or destination full)")

	// Drain the source, nulling it if emptied — a zero-count cargo fitting is not a
	// thing (#157, ship_fitting_fits), an empty hold is an empty slot.
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
// chooses Boost, Man the Sails, or Jettison Cargo in this slice — nor Reallocate,
// which is deliberately player-only (#200): it buys precision for a *subsequent*
// jettison, and a scripted ship never jettisons, so a reallocation policy would be
// AI for a capability it has no use for. It returns here when a hostile that
// jettisons exists.
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
		case Command_Reallocate:
			combat_apply_reallocate(battle, side, c.from, c.to, events)
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
		battle.reason = .Left_Combat
		battle.winner = nil
		append(events, Event(Event_Battle_Ended{round = battle.round, reason = battle.reason, winner = battle.winner}))
		return
	}

	boosted :: proc(total: int, phase: ship.Category, boost_phase: Maybe(ship.Category)) -> int {
		if p, ok := boost_phase.?; ok && p == phase {
			return total * BOOST_MULTIPLIER
		}
		return total
	}

	// Muster resolves first so its output is available to this same round's
	// Fire total below (ADR-0006, as amended by issue #151).
	for side in Side {
		round_state[side].muster_output = boosted(combat_phase_output(battle, side, .Muster), .Muster, round_state[side].boost_phase)
	}

	// Brace and Fire resolve together: each is its own fittings'
	// output, boosted, and Fire alone takes this round's muster.
	//
	// **Muster feeds Fire only** (#151). It used to feed `defense_bonus` too,
	// which made it the one category worth twice its own number: a magnitude spent
	// on Muster raised your damage *and* lowered your opponent's, so a single item
	// pushed both walls of the band at once and there was no direction left to tune
	// it in. It also fabricated soak out of nothing — a ship with no Brace
	// fitting still soaked its own muster — which is what pinned soak at ~90% of raw
	// and made a starting ship unable to sink its own mirror (20 rounds, 1 damage a
	// round). Decisively: soak is *subtracted* from raw, so soak's vocabulary has to
	// stay small, and Muster's does not — Admiral's Guard is +3 per Crew aboard, so a
	// Crew build folded +12 into its own defence and became unbeatable by any
	// starting ship. Raw can absorb a 12; soak cannot. See the band note on
	// core/run's hostile_roster.
	//
	// **A Boost multiplies its own phase's fittings, and nothing else** — the
	// muster_output above is already boosted by Boost Muster, so it is added *after*
	// Boost Fire rather than inside it. Nesting them (the pre-#151 shape,
	// `boosted(fire + muster, .Fire)`) made Boost Fire strictly
	// dominate Boost Muster at 2(F+M) against F+2M, which is a captain's Command that
	// is never the right answer. Boosting a phase's own fittings is also what
	// ADR-0006 actually says ("multiplies that phase's fitting output"), so the two
	// Boosts now answer a real question: press the guns, or press the crew.
	for side in Side {
		boost_phase := round_state[side].boost_phase
		round_state[side].defense_bonus = boosted(combat_phase_output(battle, side, .Brace), .Brace, boost_phase)
		round_state[side].raw_damage = boosted(combat_phase_output(battle, side, .Fire), .Fire, boost_phase) + round_state[side].muster_output
	}

	for side in Side {
		target := combat_opposite_side(side)
		target_ship := battle.ships[target]
		// Effective Durability (issue #92): base plus any Stat_Modifier
		// fittings, so a +Durability fitting measurably reduces damage taken.
		final := max(0, round_state[side].raw_damage-(ship.ship_effective_durability(target_ship) + round_state[target].defense_bonus))
		if final > 0 {
			target_ship.hull = max(0, target_ship.hull-final)
			append(events, Event(Event_Damage_Dealt{round = battle.round, target = target, raw_damage = round_state[side].raw_damage, final_damage = final}))
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
