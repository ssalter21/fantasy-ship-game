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
// before ticking again. The tick's own Event buffer, and the combat/run
// scratch buffers sim_tick allocates along the way, all live on
// context.temp_allocator (issue #53) — freed in one free_all per iteration
// below, the same per-frame-scratch discipline the UI already applies to its
// own draw calls. Nothing a sink retains past its own dispatch call may live
// there: Event's payloads are plain values copied into dispatch, and the one
// exception with its own owned memory (Event_Encounter_Resolved's
// Ghost_Snapshot) is allocated from the Sim's own run arena instead (issue
// #52), not this temp buffer.
run_session :: proc(sim: ^Sim, input: Input_Source, sink: Event_Sink) {
	for {
		defer free_all(context.temp_allocator)

		events := make([dynamic]Event, 0, 0, context.temp_allocator)
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
