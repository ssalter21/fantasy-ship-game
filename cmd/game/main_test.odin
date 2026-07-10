package main

import "core:testing"
import sim "../../core/sim"

@(test)
stub_captain_choice_returns_a_placeholder_choice_without_blocking :: proc(t: ^testing.T) {
	cmd := stub_captain_choice(nil)
	testing.expect_value(t, cmd, sim.Command(sim.Command_Submit_Captain_Choice{choice = 0}))
}

@(test)
stub_dispatch_is_a_no_op_that_never_touches_rendering :: proc(t: ^testing.T) {
	stub_dispatch(nil, sim.Event(sim.Event_Round_Resolved{round = 1}))
}
