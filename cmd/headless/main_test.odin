package main

import "core:testing"
import combat "../../core/combat"
import sim "../../core/sim"

@(test)
get_captain_choice_travels_to_the_next_point_when_no_battle_or_upgrade_is_pending :: proc(t: ^testing.T) {
	state := Headless_State{next_point = 1}
	defer delete(state.events)

	cmd := get_captain_choice(&state)

	travel, ok := cmd.(sim.Command_Travel_To)
	testing.expect(t, ok)
	testing.expect_value(t, travel.point_id, 1)
}

@(test)
get_captain_choice_advances_to_the_next_point_on_each_successive_call :: proc(t: ^testing.T) {
	state := Headless_State{next_point = 1}
	defer delete(state.events)

	first := get_captain_choice(&state)
	second := get_captain_choice(&state)

	first_travel, _ := first.(sim.Command_Travel_To)
	second_travel, _ := second.(sim.Command_Travel_To)
	testing.expect_value(t, first_travel.point_id, 1)
	testing.expect_value(t, second_travel.point_id, 2)
}

@(test)
get_captain_choice_holds_every_round_while_a_battle_is_in_progress :: proc(t: ^testing.T) {
	state := Headless_State{next_point = 1, in_battle = true}
	defer delete(state.events)

	cmd := get_captain_choice(&state)

	action, ok := cmd.(sim.Command_Battle_Action)
	testing.expect(t, ok)
	_, is_hold := action.action.(combat.Command_Hold)
	testing.expect(t, is_hold)
}

@(test)
get_captain_choice_picks_upgrade_option_zero_while_an_upgrade_is_pending :: proc(t: ^testing.T) {
	state := Headless_State{next_point = 1, upgrade_pending = true}
	defer delete(state.events)

	cmd := get_captain_choice(&state)

	pick, ok := cmd.(sim.Command_Pick_Upgrade)
	testing.expect(t, ok)
	testing.expect_value(t, pick.option_index, 0)
}

@(test)
dispatch_enters_battle_mode_on_sighting_and_leaves_it_when_the_battle_ends :: proc(t: ^testing.T) {
	state := Headless_State{next_point = 1}
	defer delete(state.events)

	dispatch(&state, sim.Event(sim.Event_Ship_Battle_Sighted{}))
	testing.expect(t, state.in_battle)

	dispatch(&state, sim.Event(sim.Event_Battle_Event{inner = combat.Event(combat.Event_Battle_Ended{reason = .Destroyed})}))
	testing.expect(t, !state.in_battle)
}

@(test)
dispatch_tracks_an_upgrade_offer_from_presentation_to_application :: proc(t: ^testing.T) {
	state := Headless_State{next_point = 1}
	defer delete(state.events)

	dispatch(&state, sim.Event(sim.Event_Upgrade_Offer_Presented{}))
	testing.expect(t, state.upgrade_pending)

	dispatch(&state, sim.Event(sim.Event_Upgrade_Applied{}))
	testing.expect(t, !state.upgrade_pending)
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
