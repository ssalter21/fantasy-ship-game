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
// before ticking again. The per-tick Event buffer (and the combat/run
// scratch buffers sim_tick's callees fill along the way) come from
// context.temp_allocator (issue #53).
run_session :: proc(sim: ^Sim, input: Input_Source, sink: Event_Sink) {
	for {
		events := make([dynamic]Event, context.temp_allocator)
		sim_tick(sim, &events)

		// events itself can't be dispatched from directly: the UI Event_Sink's
		// blocking play beats free_all(context.temp_allocator) once per
		// rendered frame (see cmd/game/menu.odin's play_beat), which would
		// invalidate this tick's not-yet-dispatched events mid-loop, since
		// they'd share the same arena — a real hazard, given one battle-round
		// tick commonly batches several Event_Battle_Events together. So this
		// one small heap copy (unlike the buffers above, its delete can't
		// collapse into free_all) is what actually crosses the dispatch loop;
		// free_all reclaims events and every scratch buffer sim_tick's
		// callees filled along the way in one shot, right after the copy and
		// before any dispatch can touch the temp allocator again.
		to_dispatch := make([]Event, len(events))
		copy(to_dispatch, events[:])
		free_all(context.temp_allocator)
		defer delete(to_dispatch)

		run_ended := false
		for event in to_dispatch {
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
