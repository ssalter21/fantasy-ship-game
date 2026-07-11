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

@(test)
buff_output_reduces_incoming_damage_via_the_same_sides_defensive_total :: proc(t: ^testing.T) {
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

	// A's own defense total = durability(1) + defensive(4) + buff(3) = 8;
	// B's raw damage = 20, so final = 20 - 8 = 12. Confirms a side's own
	// buff output folds into its own Defensive total, not just Offensive.
	testing.expect_value(t, a.hp, 20-12)
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

@(test)
boost_offensive_amplifies_the_phase_output_and_this_rounds_buff_output_together :: proc(t: ^testing.T) {
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

	// Boost multiplies (cannon(5) + buff(2)) as one combined total, not
	// just the cannon's own phase output: (5+2)*BOOST_MULTIPLIER = 14.
	// (A bug that boosted only the cannon would instead give 5*2+2 = 12.)
	testing.expect_value(t, b.hp, 20-(5+2)*BOOST_MULTIPLIER)
}

@(test)
boost_defensive_amplifies_the_phase_output_and_this_rounds_buff_output_together :: proc(t: ^testing.T) {
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

	// A's boosted defense total = (shield(4) + buff(3)) * BOOST_MULTIPLIER = 14;
	// B's raw damage = 20, so final = 20 - 14 = 6.
	testing.expect_value(t, a.hp, 20-6)
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
jettison_cargo_empties_the_slot_and_grants_a_permanent_speed_boost :: proc(t: ^testing.T) {
	cargo := ship.Fitting{name = "Rations", is_cargo = true, stack_count = 3}
	a := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = cargo}},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	defer delete(battle.jettisoned[.A])
	defer delete(battle.jettisoned[.B])

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 0})
	combat_resolve_round(&battle, cmds, &events)

	_, still_occupied := a.layout[0].fitting.?
	testing.expect(t, !still_occupied)
	testing.expect_value(t, combat_effective_speed(&battle, .A), 5+JETTISON_SPEED_BONUS)
	testing.expect_value(t, len(battle.jettisoned[.A]), 1)
	testing.expect_value(t, battle.jettisoned[.A][0].name, "Rations")

	jettison_event_found := false
	for event in events {
		if dropped, ok := event.(Event_Cargo_Jettisoned); ok {
			jettison_event_found = true
			testing.expect_value(t, dropped.side, Side.A)
			testing.expect_value(t, dropped.fitting.name, "Rations")
		}
	}
	testing.expect(t, jettison_event_found)

	// The boost persists into the next round too (permanent, not temporary).
	next_cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, next_cmds, &events)
	testing.expect_value(t, combat_effective_speed(&battle, .A), 5+JETTISON_SPEED_BONUS)
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

@(test)
jettisoned_cargo_is_lost_when_the_jettisoning_side_escapes :: proc(t: ^testing.T) {
	cargo := ship.Fitting{name = "Rations", is_cargo = true, stack_count = 1}
	a := ship.Ship{
		hp = 20, speed = 10,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = cargo}},
	}
	b := ship.Ship{hp = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	defer delete(battle.jettisoned[.A])
	battle.round = BASELINE_ROUND_COUNT

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 0})
	combat_resolve_round(&battle, cmds, &events)

	next_cmds: [Side]Maybe(Command)
	next_cmds[.A] = Command(Command_Leave_Combat{})
	combat_resolve_round(&battle, next_cmds, &events)

	spoils, lost := combat_settle_jettisoned_cargo(&battle, .A)
	testing.expect(t, lost)
	testing.expect_value(t, len(spoils), 0)
}

@(test)
jettisoned_cargo_is_claimed_by_the_opponent_when_the_ship_is_destroyed :: proc(t: ^testing.T) {
	cargo := ship.Fitting{name = "Rations", is_cargo = true, stack_count = 1}
	cannon := ship.Fitting{name = "Cannon", category = .Offensive, active = ship.Effect{magnitude = 25}}
	a := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = cargo}},
	}
	b := ship.Ship{
		hp = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	battle := combat_battle_create(&a, &b)
	defer delete(battle.jettisoned[.A])

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 0})
	combat_resolve_round(&battle, cmds, &events)

	testing.expect(t, battle.ended)
	spoils, lost := combat_settle_jettisoned_cargo(&battle, .A)
	testing.expect(t, !lost)
	testing.expect_value(t, len(spoils), 1)
	testing.expect_value(t, spoils[0].name, "Rations")
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
