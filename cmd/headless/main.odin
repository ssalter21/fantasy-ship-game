package main

import "core:fmt"
import combat "../../core/combat"
import sim "../../core/sim"

main :: proc() {
	s := sim.sim_create(0)
	defer sim.sim_destroy(&s)

	state := Headless_State{next_point = 1}
	defer delete(state.events)
	sink := sim.Event_Sink{data = &state, dispatch = dispatch}
	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}

	sim.run_session(&s, input, sink)

	fmt.printfln("run_session ended after %d event(s)", len(state.events))
}

// Headless_State is the shared context both the Input_Source and Event_Sink
// halves of the headless auto-player read/write (issue #24): Odin has no
// other way for the two callbacks to cooperate, since each only receives its
// own rawptr. get_captain_choice's awaiting parameter (issue #39) tells it
// what kind of decision is coming next, so this state only needs to track
// the auto-player's own travel plan.
Headless_State :: struct {
	events:     [dynamic]sim.Event,
	// next_point is the auto-player's travel plan: every point id in
	// ascending order (every port and every encounter, then Goal) — the
	// same "same content, runnable headless" full-map coverage the issue's
	// playtest goal asks for.
	next_point: int,
}

// get_captain_choice is the headless Input_Source: no real player, so it
// always resolves the current decision deterministically — Hold every
// battle round, always pick upgrade option 0, otherwise travel to the next
// point in ascending id order.
get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Headless_State)data

	switch awaiting {
	case .Awaiting_Battle_Command:
		return sim.Command(sim.Command_Battle_Choice{combat_command = combat.Command_Hold{}})
	case .Awaiting_Upgrade_Choice:
		return sim.Command(sim.Command_Pick_Upgrade{option_index = 0})
	case .Awaiting_Travel_Choice:
		point_id := state.next_point
		state.next_point += 1
		return sim.Command(sim.Command_Travel_To{point_id = point_id})
	case .Ended:
		panic("get_captain_choice called while the sim isn't awaiting a decision")
	}
	panic("unreachable")
}

// dispatch is the headless Event_Sink: log-record every event (instead of
// animating it) and track just enough context for get_captain_choice above.
// Event_Encounter_Resolved.snapshot needs no destroy call here (issue #52):
// it's valid for the Sim's own lifetime, which outlives this dispatch.
dispatch :: proc(data: rawptr, event: sim.Event) {
	state := cast(^Headless_State)data
	append(&state.events, event)
	fmt.printfln("%v", event)
}
