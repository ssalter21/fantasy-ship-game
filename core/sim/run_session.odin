package sim

// Input_Source is the pluggable source run_session asks for a captain's
// decision. Odin has no interfaces, so this is a proc-pointer-table struct
// (see ADR-0002): headless mode supplies a scripted/seeded implementation,
// UI mode supplies one that blocks on a rendered decision menu.
// get_captain_choice receives Sim's current Phase (issue #39) so the
// implementation can route to the right decision straight away instead of
// re-deriving "what kind of decision is this" from the Event stream itself.
Input_Source :: struct {
	data:                rawptr,
	get_captain_choice: proc(data: rawptr, awaiting: Phase) -> Command,
}

// Event_Sink is the pluggable destination run_session dispatches a Tick's
// Events to. Headless mode logs/records them; UI mode plays them back with
// animation (see ADR-0002).
Event_Sink :: struct {
	data:     rawptr,
	dispatch: proc(data: rawptr, event: Event),
}

// run_session is the single driver loop shared by headless and UI modes
// (see ADR-0002): tick, dispatch that round's events to the sink, and if the
// Sim is awaiting a captain decision, ask the input source and submit it
// before ticking again.
run_session :: proc(sim: ^Sim, input: Input_Source, sink: Event_Sink) {
	events: [dynamic]Event
	defer delete(events)

	for {
		clear(&events)
		sim_tick(sim, &events)

		run_ended := false
		for event in events {
			sink.dispatch(sink.data, event)
			if _, ok := event.(Event_Run_Ended); ok {
				run_ended = true
			}
		}

		if run_ended {
			return
		}

		if sim.awaiting_decision {
			cmd := input.get_captain_choice(input.data, sim.phase)
			sim_submit_captain_choice(sim, cmd)
		}
	}
}
