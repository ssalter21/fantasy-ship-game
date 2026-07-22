package main

import "core:fmt"
import voyage "../../core/voyage"
import sim "../../core/sim"

main :: proc() {
	s := sim.sim_create(0)
	defer sim.sim_destroy(&s)

	state := Headless_State{}
	sink := sim.Event_Sink{data = &state, dispatch = dispatch}
	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}

	sim.run_session(&s, input, sink)

	fmt.printfln("run_session ended after %d event(s)", state.event_count)
}

// Headless_State is the shared context the Input_Source and Event_Sink halves of
// the auto-player cooperate through — each callback receives only its own rawptr,
// so shared state has nowhere else to live.
//
// It counts events rather than keeping them: an Event borrows from the Sim's run arena,
// so a kept copy is only valid as long as the Sim is.
Headless_State :: struct {
	event_count:    int,
	last_event:     sim.Event, // borrowed from the Sim's run arena; valid only while it lives
	voyage_map:     voyage.Map, // borrowed from Event_Voyage_Started
	current:        sim.Node_ID,
	travel_options: []sim.Node_ID, // borrowed from the latest Event_Travel_Options
}

// get_captain_choice is the headless Input_Source: it hands the shared scripted
// player (sim.scripted_command) the voyage state dispatch tracked.
get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Headless_State)data
	return sim.scripted_command(state.voyage_map, state.current, state.travel_options, awaiting)
}

// dispatch is the headless Event_Sink: print and count every event, and track the current node
// plus the Sim's latest travel options that get_captain_choice plans from.
// Event_Encounter_Resolved.snapshot needs no cleanup here — it lives in the Sim's
// run-scoped arena and is freed wholesale by sim_destroy, not owned per-recipient.
dispatch :: proc(data: rawptr, event: sim.Event) {
	state := cast(^Headless_State)data
	state.event_count += 1
	state.last_event = event
	fmt.printfln("%v", event)

	switch e in event {
	case sim.Event_Voyage_Started:
		state.voyage_map = e.voyage_map
	case sim.Event_Travel_Options:
		state.travel_options = e.options
	case sim.Event_Arrived_At_Node:
		state.current = e.node.id
	case sim.Event_Ship_Battle_Sighted:
	case sim.Event_Battle_Menu:
	case sim.Event_Battle_Event:
	case sim.Event_Ship_Updated:
	case sim.Event_Wreck_Looted:
	case sim.Event_Reward_Paid:
	case sim.Event_Stage_Entered:
	case sim.Event_Encounter_Halted:
	case sim.Event_Options_Presented:
	case sim.Event_Trade_Presented:
	case sim.Event_Purchase_Rejected:
	case sim.Event_Refit_Started:
	case sim.Event_Fitting_Installed:
	case sim.Event_Fitting_Moved:
	case sim.Event_Fitting_Removed:
	case sim.Event_Cargo_Jettisoned:
	case sim.Event_Refit_Rejected:
	case sim.Event_Refit_Finished:
	case sim.Event_Encounter_Resolved:
	case sim.Event_Voyage_Ended:
	}
}
