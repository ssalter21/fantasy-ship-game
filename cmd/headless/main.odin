package main

import "core:fmt"
import combat "../../core/combat"
import voyage "../../core/voyage"
import sim "../../core/sim"

main :: proc() {
	s := sim.sim_create(0)
	defer sim.sim_destroy(&s)

	state := Headless_State{}
	defer delete(state.events)
	sink := sim.Event_Sink{data = &state, dispatch = dispatch}
	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}

	sim.run_session(&s, input, sink)

	fmt.printfln("run_session ended after %d event(s)", len(state.events))
}

// Headless_State is the shared context the Input_Source and Event_Sink halves of
// the auto-player cooperate through — each callback receives only its own rawptr,
// so shared state has nowhere else to live. voyage_map/current exist only to prefer
// a forward (deeper-layer) move among the Sim's emitted travel options, not to
// derive legality.
Headless_State :: struct {
	events:         [dynamic]sim.Event,
	voyage_map:        voyage.Map, // borrowed from Event_Voyage_Started
	current:        sim.Node_ID,
	travel_options: []sim.Node_ID, // borrowed from the latest Event_Travel_Options
}

// get_captain_choice is the headless Input_Source: with no real player it resolves
// every decision deterministically. Node kinds are hidden, so the plan depends only
// on the graph shape, never on what an unvisited node holds.
get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Headless_State)data

	switch awaiting {
	case .Awaiting_Battle_Command:
		return sim.Command(sim.Command_Battle_Choice{combat_command = combat.Command_Hold{}})
	case .Awaiting_Option_Choice:
		// Decline every option list: a nil selection takes nothing and opens no refit,
		// so the auto-player never spends cargo or edits a loadout — it just walks through.
		return sim.Command(sim.Command_Choose_Option{selection = nil})
	case .Awaiting_Trade_Choice:
		// Reject every Trade: accepting would swap a stat on the route's bargains, so
		// rejecting keeps the voyage a pure function of the graph.
		return sim.Command(sim.Command_Trade_Choice{accept = false})
	case .Awaiting_Travel_Choice:
		return sim.Command(sim.Command_Travel_To{node_id = headless_next_node(state)})
	case .Awaiting_Refit:
		// The auto-player declines every option list, so a refit never opens; if one did,
		// this just finishes it rather than editing the loadout.
		return sim.Command(sim.Command_Refit{command = sim.Refit_Finish{}})
	case .Ended:
		panic("get_captain_choice called while the sim isn't awaiting a decision")
	}
	panic("unreachable")
}

// headless_next_node picks the next travel destination from the Sim's emitted legal
// options: a forward neighbour (deeper layer) if one is offered, else the first option.
headless_next_node :: proc(state: ^Headless_State) -> sim.Node_ID {
	options := state.travel_options
	assert(len(options) > 0, "no legal travel option from the current node")

	for dest in options {
		if state.voyage_map.nodes[dest].layer > state.voyage_map.nodes[state.current].layer {
			return dest
		}
	}
	return options[0]
}

// dispatch is the headless Event_Sink: record every event and track the current node
// plus the Sim's latest travel options that get_captain_choice plans from.
// Event_Encounter_Resolved.snapshot needs no cleanup here — it lives in the Sim's
// run-scoped arena and is freed wholesale by sim_destroy, not owned per-recipient.
dispatch :: proc(data: rawptr, event: sim.Event) {
	state := cast(^Headless_State)data
	append(&state.events, event)
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
