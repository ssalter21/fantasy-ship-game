package main

import "core:testing"
import sim "../../core/sim"

// The scripted player's per-decision behavior is tested where it lives, in
// core/sim (scripted_player_test.odin). This covers the wiring that is this
// package's own: dispatch tracking the voyage state get_captain_choice feeds
// the shared player.

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
