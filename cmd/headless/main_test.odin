package main

import "core:testing"
import combat "../../core/combat"
import sim "../../core/sim"

@(test)
get_captain_choice_travels_to_the_next_point_when_awaiting_a_travel_choice :: proc(t: ^testing.T) {
	state := Headless_State{next_point = 1}
	defer delete(state.events)

	cmd := get_captain_choice(&state, .Awaiting_Travel_Choice)

	travel, ok := cmd.(sim.Command_Travel_To)
	testing.expect(t, ok)
	testing.expect_value(t, travel.point_id, 1)
}

@(test)
get_captain_choice_advances_to_the_next_point_on_each_successive_call :: proc(t: ^testing.T) {
	state := Headless_State{next_point = 1}
	defer delete(state.events)

	first := get_captain_choice(&state, .Awaiting_Travel_Choice)
	second := get_captain_choice(&state, .Awaiting_Travel_Choice)

	first_travel, _ := first.(sim.Command_Travel_To)
	second_travel, _ := second.(sim.Command_Travel_To)
	testing.expect_value(t, first_travel.point_id, 1)
	testing.expect_value(t, second_travel.point_id, 2)
}

@(test)
get_captain_choice_holds_when_awaiting_a_battle_command :: proc(t: ^testing.T) {
	state := Headless_State{next_point = 1}
	defer delete(state.events)

	cmd := get_captain_choice(&state, .Awaiting_Battle_Command)

	choice, ok := cmd.(sim.Command_Battle_Choice)
	testing.expect(t, ok)
	_, is_hold := choice.combat_command.(combat.Command_Hold)
	testing.expect(t, is_hold)
}

@(test)
get_captain_choice_picks_upgrade_option_zero_when_awaiting_an_upgrade_choice :: proc(t: ^testing.T) {
	state := Headless_State{next_point = 1}
	defer delete(state.events)

	cmd := get_captain_choice(&state, .Awaiting_Upgrade_Choice)

	pick, ok := cmd.(sim.Command_Pick_Upgrade)
	testing.expect(t, ok)
	testing.expect_value(t, pick.option_index, 0)
}

@(test)
the_auto_player_reaches_a_run_ended_event_traveling_the_whole_map :: proc(t: ^testing.T) {
	s := sim.sim_create(0)
	defer sim.sim_destroy(&s)

	state := Headless_State{next_point = 1}
	defer delete(state.events)
	sink := sim.Event_Sink{data = &state, dispatch = dispatch}
	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}

	sim.run_session(&s, input, sink)

	last := state.events[len(state.events)-1]
	_, ok := last.(sim.Event_Run_Ended)
	testing.expect(t, ok)
}
