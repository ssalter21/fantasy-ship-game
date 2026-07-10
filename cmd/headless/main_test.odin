package main

import "core:testing"
import sim "../../core/sim"

@(test)
instant_captain_choice_returns_the_stub_choice_without_blocking :: proc(t: ^testing.T) {
	cmd := instant_captain_choice(nil)
	testing.expect_value(t, cmd, sim.Command(sim.Command_Submit_Captain_Choice{choice = 0}))
}

@(test)
log_dispatch_records_every_event_it_receives :: proc(t: ^testing.T) {
	state := Log_Sink_State{}
	defer delete(state.events)

	log_dispatch(&state, sim.Event(sim.Event_Round_Resolved{round = 1}))
	log_dispatch(&state, sim.Event(sim.Event_Run_Ended{rounds = 1}))

	testing.expect_value(t, len(state.events), 2)
	testing.expect_value(t, state.events[0], sim.Event(sim.Event_Round_Resolved{round = 1}))
	testing.expect_value(t, state.events[1], sim.Event(sim.Event_Run_Ended{rounds = 1}))
}
