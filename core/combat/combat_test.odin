package combat

import "../ship"
import "../testutil"
import "core:testing"

@(test)
round_with_no_fittings_and_no_commands_deals_no_damage :: proc(t: ^testing.T) {
	a := ship.Ship{hp = 20, durability = 0, speed = 5}
	b := ship.Ship{hp = 20, durability = 0, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, battle.round, 1)
	testing.expect_value(t, a.hp, 20)
	testing.expect_value(t, b.hp, 20)
	testing.expect_value(t, len(events), 0)
	testing.expect(t, !battle.ended)
}

@(test)
offensive_fitting_deals_damage_reduced_by_target_durability :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 10}}
	a := ship.Ship{
		hp = 20, durability = 3, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hp = 20, durability = 3, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, b.hp, 20 - (10 - 3))
	testing.expect_value(t, a.hp, 20)
	testing.expect_value(t, len(events), 1)
	dealt, ok := events[0].(Event_Damage_Dealt)
	testing.expect(t, ok)
	testing.expect_value(t, dealt.target, Side.B)
	testing.expect_value(t, dealt.raw_damage, 10)
	testing.expect_value(t, dealt.final_damage, 7)
}

@(test)
damage_is_floored_at_zero_when_durability_exceeds_raw_damage :: proc(t: ^testing.T) {
	dagger := ship.Fitting{name = "Dagger", category = .Offensive, active = ship.Effect{magnitude = 2}}
	a := ship.Ship{
		hp = 20, durability = 10, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = dagger}},
	}
	b := ship.Ship{hp = 20, durability = 10, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, b.hp, 20)
	testing.expect_value(t, len(events), 0)
}

@(test)
defensive_fitting_adds_a_temporary_damage_reduction_stacking_with_durability :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 10}}
	shield := ship.Fitting{name = "Shield Charm", category = .Defensive, active = ship.Effect{magnitude = 4}}
	a := ship.Ship{
		hp = 20, durability = 0, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{
		hp = 20, durability = 1, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = shield}},
	}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	// 10 raw, minus durability(1) + this-round defense bonus(4) = 5 final.
	testing.expect_value(t, b.hp, 15)
}

@(test)
buff_output_adds_into_the_same_rounds_defensive_and_offensive_totals :: proc(t: ^testing.T) {
	warcry := ship.Fitting{name = "War Cry", category = .Buff, active = ship.Effect{magnitude = 3}}
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 10}}
	a := ship.Ship{
		hp = 20, durability = 0, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = warcry},
			{slot = ship.Slot{size = .Large}, fitting = cannon},
		},
	}
	b := ship.Ship{hp = 20, durability = 0, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	// Offensive output = cannon(10) + buff(3) = 13 raw damage.
	testing.expect_value(t, b.hp, 20-13)
}

// The inverse of the pre-#151 test of the same shape, which pinned buff folding
// into its own side's Defensive total. It no longer does: soak is subtracted from
// raw, so soak's vocabulary has to stay small, and Buff's does not (Admiral's
// Guard is +3 per Crew aboard). See combat_resolve_round's band note.
@(test)
buff_output_does_not_reduce_incoming_damage :: proc(t: ^testing.T) {
	warcry := ship.Fitting{name = "War Cry", category = .Buff, active = ship.Effect{magnitude = 3}}
	shield := ship.Fitting{name = "Shield Charm", category = .Defensive, active = ship.Effect{magnitude = 4}}
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 20}}
	a := ship.Ship{
		hp = 20, durability = 1, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = warcry},
			{slot = ship.Slot{size = .Small}, fitting = shield},
		},
	}
	b := ship.Ship{
		hp = 20, durability = 0, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	// A's soak = durability(1) + defensive(4) = 5 — the War Cry's 3 is *not* in it.
	// B's raw damage = 20, so final = 20 - 5 = 15. (Pre-#151 this was 20 - 8 = 12.)
	testing.expect_value(t, a.hp, 20-15)
}

// The same magnitude on a Buff fitting reaches Offensive and nothing else: the
// half of "buff feeds Offensive only" that says it still feeds Offensive.
@(test)
buff_output_still_raises_the_same_sides_offensive_total :: proc(t: ^testing.T) {
	warcry := ship.Fitting{name = "War Cry", category = .Buff, active = ship.Effect{magnitude = 3}}
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 5}}
	a := ship.Ship{
		hp = 20, durability = 0, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = warcry},
			{slot = ship.Slot{size = .Large}, fitting = cannon},
		},
	}
	b := ship.Ship{hp = 20, durability = 0, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, b.hp, 20-(5+3))
}

@(test)
boost_offensive_multiplies_only_the_submitters_offensive_output :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 10}}
	a := ship.Ship{
		hp = 20, durability = 0, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{
		hp = 20, durability = 0, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Boost{phase = .Offensive})
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, b.hp, 20-10*BOOST_MULTIPLIER)
	testing.expect_value(t, a.hp, 20-10)
}

// Inverted by #151: a Boost multiplies its own phase's fittings, which is what
// ADR-0006 says ("multiplies that phase's fitting output"). Boosting the combined
// total instead made Boost Offensive strictly dominate Boost Buff — 2(O+B) always
// beats O+2B — so one of the captain's five Commands was never the right answer.
@(test)
boost_offensive_multiplies_the_offensive_fittings_but_not_the_folded_buff :: proc(t: ^testing.T) {
	warcry := ship.Fitting{name = "War Cry", category = .Buff, active = ship.Effect{magnitude = 2}}
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 5}}
	a := ship.Ship{
		hp = 20, durability = 0, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = warcry},
			{slot = ship.Slot{size = .Large}, fitting = cannon},
		},
	}
	b := ship.Ship{hp = 20, durability = 0, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Boost{phase = .Offensive})
	combat_resolve_round(&battle, cmds, &events)

	// cannon(5)*BOOST_MULTIPLIER + buff(2) = 12. (Pre-#151: (5+2)*2 = 14.)
	testing.expect_value(t, b.hp, 20-(5*BOOST_MULTIPLIER+2))
}

// The other half of the same rule, and the reason it is worth having: Boost Buff
// presses the crew rather than the guns, so the two Boosts answer a real question
// instead of one dominating the other.
@(test)
boost_buff_multiplies_the_buff_fittings_before_they_reach_offensive :: proc(t: ^testing.T) {
	warcry := ship.Fitting{name = "War Cry", category = .Buff, active = ship.Effect{magnitude = 2}}
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 5}}
	a := ship.Ship{
		hp = 20, durability = 0, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = warcry},
			{slot = ship.Slot{size = .Large}, fitting = cannon},
		},
	}
	b := ship.Ship{hp = 20, durability = 0, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Boost{phase = .Buff})
	combat_resolve_round(&battle, cmds, &events)

	// cannon(5) + buff(2)*BOOST_MULTIPLIER = 9. Worth less than Boost Offensive's
	// 12 for *this* build, and worth more for a build whose crew outweighs its guns.
	testing.expect_value(t, b.hp, 20-(5+2*BOOST_MULTIPLIER))
}

// Also inverted by #151: Boost Defensive doubles the Defensive fittings alone,
// since buff no longer reaches soak at all.
@(test)
boost_defensive_multiplies_only_the_defensive_fittings :: proc(t: ^testing.T) {
	warcry := ship.Fitting{name = "War Cry", category = .Buff, active = ship.Effect{magnitude = 3}}
	shield := ship.Fitting{name = "Shield Charm", category = .Defensive, active = ship.Effect{magnitude = 4}}
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 20}}
	a := ship.Ship{
		hp = 20, durability = 0, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = warcry},
			{slot = ship.Slot{size = .Small}, fitting = shield},
		},
	}
	b := ship.Ship{
		hp = 20, durability = 0, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Boost{phase = .Defensive})
	combat_resolve_round(&battle, cmds, &events)

	// A's boosted soak = shield(4) * BOOST_MULTIPLIER = 8, the War Cry's 3 excluded;
	// B's raw damage = 20, so final = 20 - 8 = 12. (Pre-#151: (4+3)*2 = 14, so 6.)
	testing.expect_value(t, a.hp, 20-12)
}

@(test)
a_durability_stat_modifier_fitting_measurably_reduces_damage_taken :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", size = .Large, category = .Offensive, active = ship.Effect{magnitude = 10}}
	reinforced := ship.Fitting{
		name = "Reinforced Hull", size = .Small,
		passive = ship.Effect{kind = .Modify_Durability, magnitude = 4},
	}

	// Same attack against the same base ship, with and without the +Durability
	// fitting installed on the target.
	fire_once :: proc(target_layout: []ship.Layout_Slot, attacker: ship.Fitting) -> int {
		a := ship.Ship{
			hp = 20, durability = 0, speed = 5,
			layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = attacker}},
		}
		b := ship.Ship{hp = 20, durability = 1, speed = 5, layout = target_layout}
		battle := combat_battle_create(&a, &b)
		events: [dynamic]Event
		defer delete(events)
		cmds: [Side]Maybe(Command)
		combat_resolve_round(&battle, cmds, &events)
		return b.hp
	}

	bare_hp := fire_once(nil, cannon)
	reinforced_hp := fire_once([]ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = reinforced}}, cannon)

	// Bare: 10 raw - durability(1) = 9 -> hp 11. Reinforced: 10 - (1+4) = 5 -> hp 15.
	testing.expect_value(t, bare_hp, 20 - 9)
	testing.expect_value(t, reinforced_hp, 20 - 5)
	testing.expect(t, reinforced_hp > bare_hp) // the +Durability fitting measurably reduced damage
}

@(test)
a_speed_stat_modifier_fitting_raises_effective_speed_for_escape_eligibility :: proc(t: ^testing.T) {
	fast_sails := ship.Fitting{
		name = "Fast Sails", size = .Small,
		passive = ship.Effect{kind = .Modify_Speed, magnitude = 3},
	}
	// Equal base Speed (5), but A carries a +3 Speed fitting: past the baseline
	// round count only the strictly-faster side may leave, so A is eligible.
	a := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = fast_sails}},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT

	testing.expect_value(t, combat_effective_speed(&battle, .A), 5 + 3)
	testing.expect(t, combat_may_leave(&battle, .A))
	testing.expect(t, !combat_may_leave(&battle, .B))
}

@(test)
the_three_starting_fittings_phase_output_matches_their_magnitude_constants :: proc(t: ^testing.T) {
	// Regression anchor for the Effect port (issue #92): the ported flat/constant
	// starting fittings must produce byte-identical phase output to before —
	// exactly their magnitude constants, one per phase.
	s := ship.ship_starting_ship()
	defer delete(s.layout)
	opponent := ship.Ship{}
	battle := combat_battle_create(&s, &opponent)

	testing.expect_value(t, combat_phase_output(&battle, .A, .Buff), ship.TOP_CREW_BUFF_MAGNITUDE)
	testing.expect_value(t, combat_phase_output(&battle, .A, .Defensive), ship.CAPTAINS_QUARTERS_DEFENSE_MAGNITUDE)
	testing.expect_value(t, combat_phase_output(&battle, .A, .Offensive), ship.GUN_DECK_OFFENSE_MAGNITUDE)
}

@(test)
hold_is_a_no_op_identical_to_submitting_no_command :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 10}}
	a := ship.Ship{
		hp = 20, durability = 0, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hp = 20, durability = 0, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Hold{})
	combat_resolve_round(&battle, cmds, &events)

	// Same outcome as the no-command baseline round (cannon(10) unboosted,
	// no Man the Sails/Jettison/Leave side effects): Hold contributes nothing.
	testing.expect_value(t, b.hp, 20-10)
	testing.expect_value(t, a.hp, 20)
	testing.expect_value(t, combat_effective_speed(&battle, .A), 5)
	testing.expect(t, !battle.ended)
}

@(test)
man_the_sails_grants_a_speed_boost_for_this_round_only :: proc(t: ^testing.T) {
	a := ship.Ship{hp = 20, speed = 5}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Man_The_Sails{})
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, combat_effective_speed(&battle, .A), 5+MAN_THE_SAILS_SPEED_BONUS)

	next_cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, next_cmds, &events)

	testing.expect_value(t, combat_effective_speed(&battle, .A), 5)
}

@(test)
jettison_cargo_empties_the_slot_and_speeds_the_ship_up_by_shedding_weight :: proc(t: ^testing.T) {
	// A full Small hold weighs 10 (ADR-0020), so it costs its ship 1 Speed
	// (weight/10). Heaving it makes the ship read 1 faster — emergent from the
	// lighter hull, not a granted bonus (JETTISON_SPEED_BONUS is retired, #158).
	cargo := ship.Fitting{name = "Rations", size = .Small, is_cargo = true, stack_count = 10}
	a := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = cargo}},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	testing.expect_value(t, combat_effective_speed(&battle, .A), 4) // laden: 5 − 10/10

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 0})
	combat_resolve_round(&battle, cmds, &events)

	_, still_occupied := a.layout[0].fitting.?
	testing.expect(t, !still_occupied)
	testing.expect_value(t, combat_effective_speed(&battle, .A), 5) // lighter by the hold

	jettison_event_found := false
	for event in events {
		if dropped, ok := event.(Event_Cargo_Jettisoned); ok {
			jettison_event_found = true
			testing.expect_value(t, dropped.side, Side.A)
			testing.expect_value(t, dropped.fitting.name, "Rations")
		}
	}
	testing.expect(t, jettison_event_found)

	// The gain persists — the hold is gone for good, so the next round still reads
	// the lighter ship (nothing settles or restores the heaved cargo).
	next_cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, next_cmds, &events)
	testing.expect_value(t, combat_effective_speed(&battle, .A), 5)
}

@(test)
jettison_cargo_on_a_non_cargo_slot_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	cannon := ship.Fitting{name = "Cannon", category = .Offensive}
	a := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 0})

	testing.expect_assert(t, "Command_Jettison_Cargo slot_index does not hold a cargo fitting")
	combat_resolve_round(&battle, cmds, &events)
}

@(test)
reallocate_moves_treasure_between_holds_without_changing_weight_or_speed :: proc(t: ^testing.T) {
	// Reallocation pours treasure from one hold into another, conserving the total
	// aboard (ADR-0020, #157): weight is unchanged, so Speed does not move the round it
	// is issued — what it buys is jettison granularity, not Speed. A full Large (40)
	// pours into an empty Small, capped at the Small's 10 capacity (the destination
	// slot's size is the denomination, #156).
	large_cargo := ship.Fitting{name = "Cargo", size = .Large, is_cargo = true, stack_count = 40}
	a := ship.Ship{
		hp = 20, speed = 10,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Large}, fitting = large_cargo},
			{slot = ship.Slot{size = .Small}},
		},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	before := combat_effective_speed(&battle, .A) // 10 − 40/10 = 6
	testing.expect_value(t, before, 6)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	combat_resolve_round(&battle, cmds, &events)

	src, ok0 := a.layout[0].fitting.?
	testing.expect(t, ok0)
	testing.expect_value(t, src.stack_count, 30) // gave up the Small's 10
	dst, ok1 := a.layout[1].fitting.?
	testing.expect(t, ok1)
	testing.expect_value(t, dst.stack_count, 10) // a new Small hold, full
	testing.expect_value(t, ship.ship_treasure(a), 40) // conserved
	testing.expect_value(t, combat_effective_speed(&battle, .A), before) // no weight shifted

	found := false
	for event in events {
		if moved, ok := event.(Event_Cargo_Reallocated); ok {
			found = true
			testing.expect_value(t, moved.side, Side.A)
			testing.expect_value(t, moved.from, ship.Slot_Index(0))
			testing.expect_value(t, moved.to, ship.Slot_Index(1))
			testing.expect_value(t, moved.amount, 10)
		}
	}
	testing.expect(t, found)
}

@(test)
reallocate_buys_a_finer_jettison_than_the_hold_allowed :: proc(t: ^testing.T) {
	// The precision reallocation buys (#157): with a single full Large as its only
	// cargo, the cheapest heave is the whole 40 (4 Speed). Splitting 10 into an empty
	// Small first lets the next Jettison shed exactly 10 (1 Speed) — a finer amount
	// than was reachable before the reallocation, paid for with the round it cost.
	large_cargo := ship.Fitting{name = "Cargo", size = .Large, is_cargo = true, stack_count = 40}
	a := ship.Ship{
		hp = 20, speed = 10,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Large}, fitting = large_cargo},
			{slot = ship.Slot{size = .Small}},
		},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	laden := combat_effective_speed(&battle, .A) // 10 − 40/10 = 6

	events: [dynamic]Event
	defer delete(events)

	// Round 1: reallocate 10 into the Small. Weight unchanged, so Speed unchanged.
	realloc_cmds: [Side]Maybe(Command)
	realloc_cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	combat_resolve_round(&battle, realloc_cmds, &events)
	testing.expect_value(t, combat_effective_speed(&battle, .A), laden)

	// Round 2: jettison the freshly-split Small — sheds exactly 10, one Speed, a finer
	// heave than the 40 the hold allowed before.
	jettison_cmds: [Side]Maybe(Command)
	jettison_cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 1})
	combat_resolve_round(&battle, jettison_cmds, &events)
	testing.expect_value(t, combat_effective_speed(&battle, .A), laden + 1)
}

@(test)
reallocate_into_a_partial_hold_grows_it_up_to_capacity :: proc(t: ^testing.T) {
	// Pouring into a partly-full cargo fitting grows it, capped at min(source, room)
	// (#156): a Medium holding 5 has room for 15 more, so a Large of 40 gives up
	// exactly 15 and keeps 25 — nothing overflows or is lost.
	large_cargo := ship.Fitting{name = "Cargo", size = .Large, is_cargo = true, stack_count = 40}
	medium_cargo := ship.Fitting{name = "Cargo", size = .Medium, is_cargo = true, stack_count = 5}
	a := ship.Ship{
		hp = 20, speed = 10,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Large}, fitting = large_cargo},
			{slot = ship.Slot{size = .Medium}, fitting = medium_cargo},
		},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	combat_resolve_round(&battle, cmds, &events)

	src, ok0 := a.layout[0].fitting.?
	testing.expect(t, ok0)
	testing.expect_value(t, src.stack_count, 25)
	dst, ok1 := a.layout[1].fitting.?
	testing.expect(t, ok1)
	testing.expect_value(t, dst.stack_count, 20) // 5 + 15, a full Medium
	testing.expect_value(t, ship.ship_treasure(a), 45)
}

@(test)
reallocate_that_empties_the_source_nulls_the_slot :: proc(t: ^testing.T) {
	// A source drained to nothing becomes an empty slot, not a zero-count cargo fitting
	// (#157, ship_fitting_fits): a Small of 10 poured into an empty Medium moves all 10
	// and leaves the Small slot empty.
	small_cargo := ship.Fitting{name = "Cargo", size = .Small, is_cargo = true, stack_count = 10}
	a := ship.Ship{
		hp = 20, speed = 10,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = small_cargo},
			{slot = ship.Slot{size = .Medium}},
		},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	combat_resolve_round(&battle, cmds, &events)

	_, still_occupied := a.layout[0].fitting.?
	testing.expect(t, !still_occupied)
	dst, ok1 := a.layout[1].fitting.?
	testing.expect(t, ok1)
	testing.expect_value(t, dst.stack_count, 10)
}

@(test)
reallocate_from_a_slot_to_itself_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}
	cargo := ship.Fitting{name = "Cargo", size = .Small, is_cargo = true, stack_count = 10}
	a := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = cargo}},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 0})
	testing.expect_assert(t, "Command_Reallocate from and to are the same slot")
	combat_resolve_round(&battle, cmds, &events)
}

@(test)
reallocate_from_a_non_cargo_slot_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}
	cannon := ship.Fitting{name = "Cannon", category = .Offensive}
	a := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Large}, fitting = cannon},
			{slot = ship.Slot{size = .Small}},
		},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	testing.expect_assert(t, "Command_Reallocate from does not hold a cargo fitting")
	combat_resolve_round(&battle, cmds, &events)
}

@(test)
reallocate_into_a_non_cargo_slot_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}
	cargo := ship.Fitting{name = "Cargo", size = .Small, is_cargo = true, stack_count = 10}
	cannon := ship.Fitting{name = "Cannon", category = .Offensive}
	a := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = cargo},
			{slot = ship.Slot{size = .Large}, fitting = cannon},
		},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	testing.expect_assert(t, "Command_Reallocate to holds a non-cargo fitting")
	combat_resolve_round(&battle, cmds, &events)
}

@(test)
reallocate_into_a_full_hold_moves_nothing_and_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}
	// A full destination has no room, so the move would shift 0 treasure — the menu
	// never offers it (battle_reallocate_can_receive), and the combat layer asserts,
	// exactly like jettisoning an empty slot buys nothing.
	from_cargo := ship.Fitting{name = "Cargo", size = .Small, is_cargo = true, stack_count = 10}
	full_small := ship.Fitting{name = "Cargo", size = .Small, is_cargo = true, stack_count = 10}
	a := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = from_cargo},
			{slot = ship.Slot{size = .Small}, fitting = full_small},
		},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	testing.expect_assert(t, "Command_Reallocate moves no treasure (source empty or destination full)")
	combat_resolve_round(&battle, cmds, &events)
}

@(test)
may_leave_is_false_before_the_baseline_round_count_even_if_faster :: proc(t: ^testing.T) {
	a := ship.Ship{hp = 20, speed = 10}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT - 1

	testing.expect(t, !combat_may_leave(&battle, .A))
}

@(test)
may_leave_is_false_after_baseline_when_not_the_faster_side :: proc(t: ^testing.T) {
	a := ship.Ship{hp = 20, speed = 5}
	b := ship.Ship{hp = 20, speed = 10}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT

	testing.expect(t, !combat_may_leave(&battle, .A))
}

@(test)
may_leave_is_true_after_baseline_for_the_strictly_faster_side :: proc(t: ^testing.T) {
	a := ship.Ship{hp = 20, speed = 10}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT

	testing.expect(t, combat_may_leave(&battle, .A))
}

@(test)
scripted_command_holds_when_not_escape_eligible :: proc(t: ^testing.T) {
	a := ship.Ship{hp = 20, speed = 10}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT - 1

	testing.expect_value(t, combat_scripted_command(&battle, .A), Command(Command_Hold{}))
}

@(test)
scripted_command_leaves_once_escape_eligible :: proc(t: ^testing.T) {
	a := ship.Ship{hp = 20, speed = 10}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT

	testing.expect_value(t, combat_scripted_command(&battle, .A), Command(Command_Leave_Combat{}))
}

@(test)
leave_combat_ends_the_battle_immediately_with_no_phase_resolution :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 10}}
	a := ship.Ship{
		hp = 20, speed = 10,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Leave_Combat{})
	combat_resolve_round(&battle, cmds, &events)

	testing.expect(t, battle.ended)
	testing.expect_value(t, b.hp, 20) // no offensive phase resolved this round
	testing.expect_value(t, len(events), 1)
	ended, ok := events[0].(Event_Battle_Ended)
	testing.expect(t, ok)
	testing.expect_value(t, ended.reason, End_Reason.Left_Combat)
	_, has_winner := ended.winner.?
	testing.expect(t, !has_winner)

	// The Battle mirrors the ending it emitted, so a caller holding only the Battle —
	// voyage_finish_ship_battle, deciding the wreck payout (#159) — reads it without the
	// event stream.
	testing.expect_value(t, battle.reason, End_Reason.Left_Combat)
	_, battle_has_winner := battle.winner.?
	testing.expect(t, !battle_has_winner)
}

@(test)
an_escape_eligible_side_declining_to_leave_lets_combat_continue_normally :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 10}}
	a := ship.Ship{
		hp = 20, durability = 0, speed = 10,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hp = 20, durability = 0, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT

	events: [dynamic]Event
	defer delete(events)

	testing.expect(t, combat_may_leave(&battle, .A))

	// A is escape-eligible this round but submits no command (declines the
	// offer): the round resolves as normal instead of ending combat.
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect(t, !battle.ended)
	testing.expect_value(t, b.hp, 20-10)
}

@(test)
man_the_sails_speed_boost_can_swing_escape_eligibility_for_the_round_it_was_used :: proc(t: ^testing.T) {
	a := ship.Ship{hp = 20, speed = 5}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT - 1

	events: [dynamic]Event
	defer delete(events)

	// Tied base Speed: not escape-eligible on its own once baseline is reached.
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events) // battle.round == BASELINE_ROUND_COUNT
	testing.expect(t, !combat_may_leave(&battle, .A))

	// A plays Man the Sails this round, tipping it strictly faster. The
	// temp_speed bonus isn't reset until the *next* combat_resolve_round
	// call, so it's still in effect for the escape-eligibility check made
	// right after this round resolves (i.e. before next round's command).
	clear(&events)
	sails_cmds: [Side]Maybe(Command)
	sails_cmds[.A] = Command(Command_Man_The_Sails{})
	combat_resolve_round(&battle, sails_cmds, &events)

	testing.expect(t, combat_may_leave(&battle, .A))
}

@(test)
a_ship_reduced_to_zero_hp_is_sunk_and_the_opponent_wins :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 25}}
	a := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, b.hp, 0)
	testing.expect(t, battle.ended)

	// The Battle mirrors the emitted ending (#159): a kill is queryable off it.
	testing.expect_value(t, battle.reason, End_Reason.Destroyed)
	battle_winner, battle_has_winner := battle.winner.?
	testing.expect(t, battle_has_winner)
	testing.expect_value(t, battle_winner, Side.A)

	sunk_found, ended_found := false, false
	for event in events {
		if sunk, ok := event.(Event_Ship_Sunk); ok {
			sunk_found = true
			testing.expect_value(t, sunk.side, Side.B)
		}
		if ended, ok := event.(Event_Battle_Ended); ok {
			ended_found = true
			testing.expect_value(t, ended.reason, End_Reason.Destroyed)
			winner, has_winner := ended.winner.?
			testing.expect(t, has_winner)
			testing.expect_value(t, winner, Side.A)
		}
	}
	testing.expect(t, sunk_found)
	testing.expect(t, ended_found)
}

@(test)
a_mutual_kill_in_the_same_round_is_won_by_the_higher_speed_side :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 25}}
	a := ship.Ship{
		hp = 20, speed = 10,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, a.hp, 0)
	testing.expect_value(t, b.hp, 0)

	for event in events {
		if ended, ok := event.(Event_Battle_Ended); ok {
			winner, has_winner := ended.winner.?
			testing.expect(t, has_winner)
			testing.expect_value(t, winner, Side.A)
		}
	}
}

@(test)
a_mutual_kill_with_equal_speed_has_no_winner :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 25}}
	a := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	for event in events {
		if ended, ok := event.(Event_Battle_Ended); ok {
			_, has_winner := ended.winner.?
			testing.expect(t, !has_winner)
		}
	}
}

@(test)
hard_round_cap_forces_resolution_by_higher_hp :: proc(t: ^testing.T) {
	a := ship.Ship{hp = 15, speed = 5}
	b := ship.Ship{hp = 10, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	for i in 0 ..< HARD_ROUND_CAP - 1 {
		clear(&events)
		combat_resolve_round(&battle, cmds, &events)
		testing.expect(t, !battle.ended)
	}

	clear(&events)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect(t, battle.ended)
	testing.expect_value(t, battle.round, HARD_ROUND_CAP)
	ended, ok := find_battle_ended(events[:])
	testing.expect(t, ok)
	testing.expect_value(t, ended.reason, End_Reason.Round_Cap)
	winner, has_winner := ended.winner.?
	testing.expect(t, has_winner)
	testing.expect_value(t, winner, Side.A)

	// The Battle mirrors the emitted ending (#159): a stalemate is Round_Cap on it,
	// which is how voyage_finish_ship_battle tells a draw (pays nothing) from a kill.
	testing.expect_value(t, battle.reason, End_Reason.Round_Cap)
	battle_winner, battle_has_winner := battle.winner.?
	testing.expect(t, battle_has_winner)
	testing.expect_value(t, battle_winner, Side.A)
}

@(test)
hard_round_cap_tie_break_falls_back_to_speed_when_hp_is_tied :: proc(t: ^testing.T) {
	a := ship.Ship{hp = 10, speed = 8}
	b := ship.Ship{hp = 10, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = HARD_ROUND_CAP - 1

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	ended, ok := find_battle_ended(events[:])
	testing.expect(t, ok)
	winner, has_winner := ended.winner.?
	testing.expect(t, has_winner)
	testing.expect_value(t, winner, Side.A)
}

@(test)
hard_round_cap_tie_break_has_no_winner_when_hp_and_speed_are_both_tied :: proc(t: ^testing.T) {
	a := ship.Ship{hp = 10, speed = 5}
	b := ship.Ship{hp = 10, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = HARD_ROUND_CAP - 1

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	ended, ok := find_battle_ended(events[:])
	testing.expect(t, ok)
	_, has_winner := ended.winner.?
	testing.expect(t, !has_winner)
}

find_battle_ended :: proc(events: []Event) -> (Event_Battle_Ended, bool) {
	for event in events {
		if ended, ok := event.(Event_Battle_Ended); ok {
			return ended, true
		}
	}
	return {}, false
}

// Heaved cargo is destroyed, never settled (ADR-0020, #159): there is no
// post-battle settlement to hand it back, so the ship's purse just falls by the
// hold and stays fallen — win or lose. The literal "claimed by the opponent"
// reading was retired because it would make jettison free whenever you win.
@(test)
jettisoned_cargo_is_destroyed_with_nothing_to_settle :: proc(t: ^testing.T) {
	cargo := ship.Fitting{name = "Rations", size = .Small, is_cargo = true, stack_count = 10}
	a := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = cargo}},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	testing.expect_value(t, ship.ship_treasure(a), 10)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 0})
	combat_resolve_round(&battle, cmds, &events)

	// The purse is lighter, and there is no settlement path to give it back.
	testing.expect_value(t, ship.ship_treasure(a), 0)
}

@(test)
identical_ships_and_commands_produce_identical_results_every_time :: proc(t: ^testing.T) {
	make_ships :: proc() -> (ship.Ship, ship.Ship) {
		cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 7}}
		a := ship.Ship{
			hp = 30, durability = 1, speed = 5,
			layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
		}
		b := ship.Ship{
			hp = 30, durability = 2, speed = 6,
			layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
		}
		return a, b
	}

	run_five_rounds :: proc() -> (int, int) {
		a, b := make_ships()
		battle := combat_battle_create(&a, &b)
		events: [dynamic]Event
		defer delete(events)
		cmds: [Side]Maybe(Command)
		for i in 0 ..< 5 {
			clear(&events)
			combat_resolve_round(&battle, cmds, &events)
		}
		return a.hp, b.hp
	}

	a_hp_1, b_hp_1 := run_five_rounds()
	a_hp_2, b_hp_2 := run_five_rounds()

	testing.expect_value(t, a_hp_1, a_hp_2)
	testing.expect_value(t, b_hp_1, b_hp_2)
}

// Demo (issue #93): a synergy fitting's combat output scales with the count of
// installed fittings matching its selector, resolved against the owning ship's
// current layout at combat-resolve time (combat_phase_output routes magnitude
// through ship.effect_magnitude). Here an Offensive "for each Weapon, +Offense"
// fitting's phase output rises as Weapon fittings are added and falls as they
// are removed. The synergy fitting is itself an Artifact, so it never counts
// toward its own selector — the output tracks the other Weapons only.
@(test)
synergy_offense_rises_and_falls_with_the_weapon_count_aboard :: proc(t: ^testing.T) {
	OFFENSE_PER_WEAPON :: 3
	synergy_gun := ship.Fitting{
		name     = "Runic Battery",
		size     = .Large,
		category = .Offensive,
		tags     = {.Artifact},
		active   = ship.Effect{magnitude = OFFENSE_PER_WEAPON, synergy = ship.Selector(ship.Tag.Weapon)},
	}
	cannon := ship.Fitting{name = "Cannon", size = .Large, tags = {.Weapon}}
	ballista := ship.Fitting{name = "Ballista", size = .Small, tags = {.Weapon}}

	s := ship.Ship{
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Large, base_visibility = .Exposed}, fitting = synergy_gun},
			{slot = ship.Slot{size = .Large, base_visibility = .Exposed}},
			{slot = ship.Slot{size = .Small, base_visibility = .Concealed}},
		},
	}
	// combat_phase_output resolves against a battle (issue #94); the synergy
	// count only depends on s's own layout, so the opponent is a bare ship.
	opponent := ship.Ship{}
	battle := combat_battle_create(&s, &opponent)

	// No Weapons aboard yet: for-each-Weapon output is zero.
	testing.expect_value(t, combat_phase_output(&battle, .A, .Offensive), 0)

	// Add one Weapon: output rises to one Weapon's worth.
	s.layout[1].fitting = cannon
	testing.expect_value(t, combat_phase_output(&battle, .A, .Offensive), OFFENSE_PER_WEAPON)

	// Add a second Weapon: output rises again.
	s.layout[2].fitting = ballista
	testing.expect_value(t, combat_phase_output(&battle, .A, .Offensive), 2 * OFFENSE_PER_WEAPON)

	// Remove a Weapon: output falls back.
	s.layout[1].fitting = nil
	testing.expect_value(t, combat_phase_output(&battle, .A, .Offensive), OFFENSE_PER_WEAPON)
}

@(test)
a_below_half_hp_conditional_offense_fitting_contributes_only_below_the_threshold :: proc(t: ^testing.T) {
	// Demo for issue #94: a "below half HP, +Offense" fitting resolves its
	// Offensive phase output through the conditional seam, so it adds nothing
	// while the ship is above half HP and its full magnitude once below.
	desperado := ship.Fitting{
		name = "Desperado Cannon", size = .Large, category = .Offensive,
		active = ship.Effect{magnitude = 10, conditional = ship.Condition_HP_Below{percent = 50}},
	}

	// Same fitting fired against the same bare target, differing only in the
	// attacker's current HP relative to its half-HP threshold.
	damage_dealt_at_hp :: proc(attacker: ship.Fitting, attacker_hp: int) -> int {
		a := ship.Ship{
			hp = attacker_hp, max_hp = 20, durability = 0, speed = 5,
			layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = attacker}},
		}
		b := ship.Ship{hp = 20, max_hp = 20, durability = 0, speed = 5}
		battle := combat_battle_create(&a, &b)
		events: [dynamic]Event
		defer delete(events)
		cmds: [Side]Maybe(Command)
		combat_resolve_round(&battle, cmds, &events)
		return 20 - b.hp
	}

	above := damage_dealt_at_hp(desperado, 20) // full HP: above the threshold
	below := damage_dealt_at_hp(desperado, 9) // below half of 20

	testing.expect_value(t, above, 0) // contributes nothing above the threshold
	testing.expect_value(t, below, 10) // its full bonus below it
	testing.expect(t, below > above)
}

@(test)
a_while_concealed_conditional_offense_fitting_reads_its_own_slot_visibility :: proc(t: ^testing.T) {
	// The own-concealment trigger resolves against the slot the fitting sits in
	// (combat_phase_output fills self_slot per fitting): the same fitting in a
	// concealed slot contributes, in an exposed slot does not.
	ambush := ship.Fitting{
		name = "Ambush Cannon", size = .Large, category = .Offensive,
		active = ship.Effect{magnitude = 8, conditional = ship.Condition_Self_Visibility{visibility = .Concealed}},
	}

	damage_from_slot :: proc(attacker: ship.Fitting, base_visibility: ship.Visibility) -> int {
		a := ship.Ship{
			hp = 20, max_hp = 20, durability = 0, speed = 5,
			layout = []ship.Layout_Slot{
				{slot = ship.Slot{size = .Large, base_visibility = base_visibility}, fitting = attacker},
			},
		}
		b := ship.Ship{hp = 20, max_hp = 20, durability = 0, speed = 5}
		battle := combat_battle_create(&a, &b)
		events: [dynamic]Event
		defer delete(events)
		cmds: [Side]Maybe(Command)
		combat_resolve_round(&battle, cmds, &events)
		return 20 - b.hp
	}

	testing.expect_value(t, damage_from_slot(ambush, .Exposed), 0)
	testing.expect_value(t, damage_from_slot(ambush, .Concealed), 8)
}
