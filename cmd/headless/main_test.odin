package main

import "core:testing"
import combat "../../core/combat"
import voyage "../../core/voyage"
import sim "../../core/sim"

@(test)
get_captain_choice_travels_to_a_legal_forward_neighbor_of_the_current_node :: proc(t: ^testing.T) {
	m := voyage.voyage_map_create(0)
	defer voyage.voyage_map_destroy(&m)

	// Stand in for the Sim's Event_Travel_Options broadcast: the legal moves
	// from Start (issue #83). get_captain_choice plans from these, not from a
	// shadow visited set of its own.
	visited := make([]bool, len(m.nodes))
	defer delete(visited)
	visited[0] = true
	options := voyage.voyage_travel_options(m, 0, visited)
	travel_options := make([]sim.Node_ID, len(options))
	defer delete(travel_options)
	for id, i in options {
		travel_options[i] = id
	}

	state := Headless_State{voyage_map = m, current = 0, travel_options = travel_options}

	cmd := get_captain_choice(&state, .Awaiting_Travel_Choice)

	travel, ok := cmd.(sim.Command_Travel_To)
	testing.expect(t, ok)
	// The chosen destination must be one of the emitted options and a forward
	// step (a deeper layer) — progress toward Haven, never an illegal jump.
	testing.expect(t, voyage.voyage_can_travel_to(m, 0, visited, travel.node_id))
	testing.expect(t, m.nodes[travel.node_id].layer > m.nodes[0].layer)
}

@(test)
get_captain_choice_holds_when_awaiting_a_battle_command :: proc(t: ^testing.T) {
	state := Headless_State{}

	cmd := get_captain_choice(&state, .Awaiting_Battle_Command)

	choice, ok := cmd.(sim.Command_Battle_Choice)
	testing.expect(t, ok)
	_, is_hold := choice.combat_command.(combat.Command_Hold)
	testing.expect(t, is_hold)
}

@(test)
get_captain_choice_declines_when_awaiting_an_option_choice :: proc(t: ^testing.T) {
	state := Headless_State{}

	cmd := get_captain_choice(&state, .Awaiting_Option_Choice)

	choice, ok := cmd.(sim.Command_Choose_Option)
	testing.expect(t, ok)
	_, has_selection := choice.selection.?
	testing.expect(t, !has_selection) // nil selection == decline: skip an Offer, leave a Shop
}

@(test)
the_auto_player_reaches_a_voyage_ended_event_navigating_the_graph :: proc(t: ^testing.T) {
	s := sim.sim_create(0)
	defer sim.sim_destroy(&s)

	state := Headless_State{}
	sink := sim.Event_Sink{data = &state, dispatch = dispatch}
	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}

	sim.run_session(&s, input, sink)

	_, ok := state.last_event.(sim.Event_Voyage_Ended)
	testing.expect(t, ok)
}
