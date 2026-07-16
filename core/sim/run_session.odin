package sim

// Input_Source is the pluggable source run_session asks for a captain's decision.
// Odin has no interfaces, so it's a proc-pointer-table struct (ADR-0002): headless
// supplies a scripted implementation, UI one that blocks on a rendered decision menu.
// get_captain_choice is handed the Sim's current Phase so it knows which kind of
// decision to make.
Input_Source :: struct {
	data:                rawptr,
	get_captain_choice: proc(data: rawptr, awaiting: Phase) -> Command,
}

// Event_Sink is the pluggable destination run_session dispatches a Tick's Events to
// (ADR-0002): headless logs/records them, UI plays them back with animation.
Event_Sink :: struct {
	data:     rawptr,
	dispatch: proc(data: rawptr, event: Event),
}

// run_session is the single driver loop shared by headless and UI modes (ADR-0002):
// tick, dispatch that round's events to the sink, and if the Sim is awaiting a captain
// decision, ask the input source and submit it before ticking again.
//
// The scratch buffers sim_tick allocates live on context.temp_allocator, freed by the
// one free_all per iteration below; they're fully drained into events before sim_tick
// returns, so nothing about them survives into the dispatch loop.
//
// events itself stays off context.temp_allocator deliberately: it must survive across
// every sink.dispatch call below, and a UI sink's dispatch can itself trigger a nested
// free_all(context.temp_allocator) (play_beat's per-frame render loop) that would zero
// out events still waiting to be dispatched. It lives on the heap (delete above)
// instead. Event_Encounter_Resolved's owned Ghost_Snapshot rides the Sim's run arena,
// so it's unaffected either way.
run_session :: proc(sim: ^Sim, input: Input_Source, sink: Event_Sink) {
	events: [dynamic]Event
	defer delete(events)

	for {
		defer free_all(context.temp_allocator)

		clear(&events)
		sim_tick(sim, &events)

		voyage_ended := false
		for event in events {
			sink.dispatch(sink.data, event)
			if _, ok := event.(Event_Voyage_Ended); ok {
				voyage_ended = true
			}
		}

		if voyage_ended {
			return
		}

		if sim.awaiting_decision {
			cmd := input.get_captain_choice(input.data, sim.phase)
			sim_submit_captain_choice(sim, cmd)
		}
	}
}
