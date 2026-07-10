package main

import "core:testing"
import sim "../../core/sim"

@(test)
rendered_captain_choice_returns_a_placeholder_choice_without_a_live_window :: proc(t: ^testing.T) {
	cmd := rendered_captain_choice(nil)
	testing.expect_value(t, cmd, sim.Command(sim.Command_Submit_Captain_Choice{choice = 0}))
}

@(test)
rendered_dispatch_does_not_crash_without_a_live_window :: proc(t: ^testing.T) {
	rendered_dispatch(nil, sim.Event(sim.Event_Round_Resolved{round = 1}))
}
