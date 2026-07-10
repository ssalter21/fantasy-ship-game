package main

import "core:fmt"
import sim "../../core/sim"

main :: proc() {
	s := sim.sim_create(0)

	sink_state := Log_Sink_State{}
	defer delete(sink_state.events)
	sink := sim.Event_Sink{data = &sink_state, dispatch = log_dispatch}

	input := sim.Input_Source{data = nil, get_captain_choice = instant_captain_choice}

	sim.run_session(&s, input, sink)

	fmt.printfln("run_session ended after %d event(s)", len(sink_state.events))
}

// instant_captain_choice is the headless Input_Source: it returns a stub
// choice immediately rather than blocking on real player input.
instant_captain_choice :: proc(data: rawptr) -> sim.Command {
	return sim.Command(sim.Command_Submit_Captain_Choice{choice = 0})
}

Log_Sink_State :: struct {
	events: [dynamic]sim.Event,
}

// log_dispatch is the headless Event_Sink: log-record every event instead of
// animating it.
log_dispatch :: proc(data: rawptr, event: sim.Event) {
	state := cast(^Log_Sink_State)data
	append(&state.events, event)
	fmt.printfln("%v", event)
}
