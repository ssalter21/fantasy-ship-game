package main

import "core:fmt"
import combat "../../core/combat"
import run "../../core/run"
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

// Headless_State is the shared context both the Input_Source and Event_Sink
// halves of the headless auto-player read/write (issue #24): Odin has no
// other way for the two callbacks to cooperate, since each only receives its
// own rawptr. It no longer maintains a shadow visited set to recompute travel
// legality — the Sim now emits the legal moves on Event_Travel_Options (issue
// #83), which dispatch records into travel_options. run_map/current are kept
// only to prefer a *forward* (deeper-layer) move among those emitted options,
// not to derive legality.
Headless_State :: struct {
	events:         [dynamic]sim.Event,
	run_map:        run.Map, // borrowed from Event_Run_Started (the masked public map)
	current:        sim.Node_ID,
	travel_options: []sim.Node_ID, // borrowed from the latest Event_Travel_Options
}

// get_captain_choice is the headless Input_Source: no real player, so it
// always resolves the current decision deterministically — Hold every battle
// round, skip every Item Offer, and for travel pick a legal move that makes
// forward progress toward Goal (any forward neighbour; the first emitted option
// otherwise). The travel options come from the Sim (issue #83), and kinds are
// hidden, so the plan never depends on what an unvisited node holds — only on
// the graph shape.
get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Headless_State)data

	switch awaiting {
	case .Awaiting_Battle_Command:
		return sim.Command(sim.Command_Battle_Choice{combat_command = combat.Command_Hold{}})
	case .Awaiting_Item_Choice:
		// Skip the Item Offer (issue #96): a nil selection takes no item and opens
		// no refit, so the auto-player never has to drive a loadout edit.
		return sim.Command(sim.Command_Pick_Item{selection = nil})
	case .Awaiting_Travel_Choice:
		return sim.Command(sim.Command_Travel_To{node_id = headless_next_node(state)})
	case .Awaiting_Refit:
		// A skipped Item Offer never opens a refit; if some other channel (#98 Port
		// shop) ever does, this scripted driver just finishes it rather than
		// editing the loadout.
		return sim.Command(sim.Command_Refit{command = sim.Refit_Finish{}})
	case .Ended:
		panic("get_captain_choice called while the sim isn't awaiting a decision")
	}
	panic("unreachable")
}

// headless_next_node picks the auto-player's next travel destination from the
// Sim's emitted legal options (issue #83): a forward neighbour (deeper layer)
// if one is offered, else the first emitted option — always making progress
// toward Goal without depending on any hidden encounter kind.
headless_next_node :: proc(state: ^Headless_State) -> sim.Node_ID {
	options := state.travel_options
	assert(len(options) > 0, "no legal travel option from the current node")

	for dest in options {
		if state.run_map.nodes[dest].layer > state.run_map.nodes[state.current].layer {
			return dest
		}
	}
	return options[0]
}

// dispatch is the headless Event_Sink: log-record every event, and track the
// current node plus the Sim's latest emitted travel options that
// get_captain_choice plans from. Event_Encounter_Resolved.snapshot needs no
// cleanup here — it lives in the Sim's own run-scoped arena and is reclaimed
// wholesale by sim_destroy (issue #52), not owned per-recipient.
dispatch :: proc(data: rawptr, event: sim.Event) {
	state := cast(^Headless_State)data
	append(&state.events, event)
	fmt.printfln("%v", event)

	switch e in event {
	case sim.Event_Run_Started:
		state.run_map = e.run_map
	case sim.Event_Travel_Options:
		state.travel_options = e.options
	case sim.Event_Arrived_At_Node:
		state.current = e.node.id
	case sim.Event_Ship_Battle_Sighted:
	case sim.Event_Battle_Menu:
	case sim.Event_Battle_Event:
	case sim.Event_Ship_Updated:
	case sim.Event_Item_Offer_Presented:
	case sim.Event_Refit_Started:
	case sim.Event_Fitting_Installed:
	case sim.Event_Fitting_Moved:
	case sim.Event_Fitting_Removed:
	case sim.Event_Refit_Rejected:
	case sim.Event_Refit_Finished:
	case sim.Event_Encounter_Resolved:
	case sim.Event_Run_Ended:
	}
}
