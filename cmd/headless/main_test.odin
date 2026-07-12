package main

import "core:testing"
import combat "../../core/combat"
import run "../../core/run"
import sim "../../core/sim"

@(test)
get_captain_choice_travels_to_a_legal_forward_neighbor_of_the_current_node :: proc(t: ^testing.T) {
	m := run.run_map_create(0)
	defer run.run_map_destroy(&m)

	state := Headless_State{run_map = m, current = 0}
	state.visited = make([]bool, len(m.points))
	defer delete(state.visited)
	state.visited[0] = true

	cmd := get_captain_choice(&state, .Awaiting_Travel_Choice)

	travel, ok := cmd.(sim.Command_Travel_To)
	testing.expect(t, ok)
	// The chosen destination must be a real neighbour of Start and a forward
	// step (a deeper layer) — progress toward Goal, never an illegal jump.
	testing.expect(t, run.run_can_travel_to(m, 0, state.visited, int(travel.point_id)))
	testing.expect(t, m.points[travel.point_id].layer > m.points[0].layer)
}

@(test)
get_captain_choice_holds_when_awaiting_a_battle_command :: proc(t: ^testing.T) {
	state := Headless_State{}
	defer delete(state.events)

	cmd := get_captain_choice(&state, .Awaiting_Battle_Command)

	choice, ok := cmd.(sim.Command_Battle_Choice)
	testing.expect(t, ok)
	_, is_hold := choice.combat_command.(combat.Command_Hold)
	testing.expect(t, is_hold)
}

@(test)
get_captain_choice_picks_upgrade_option_zero_when_awaiting_an_upgrade_choice :: proc(t: ^testing.T) {
	state := Headless_State{}
	defer delete(state.events)

	cmd := get_captain_choice(&state, .Awaiting_Upgrade_Choice)

	pick, ok := cmd.(sim.Command_Pick_Upgrade)
	testing.expect(t, ok)
	testing.expect_value(t, pick.option_index, 0)
}

@(test)
the_auto_player_reaches_a_run_ended_event_navigating_the_graph :: proc(t: ^testing.T) {
	s := sim.sim_create(0)
	defer sim.sim_destroy(&s)

	state := Headless_State{}
	defer delete(state.events)
	defer delete(state.visited)
	sink := sim.Event_Sink{data = &state, dispatch = dispatch}
	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}

	sim.run_session(&s, input, sink)

	last := state.events[len(state.events)-1]
	_, ok := last.(sim.Event_Run_Ended)
	testing.expect(t, ok)
}
