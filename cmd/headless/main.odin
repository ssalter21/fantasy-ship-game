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
	defer delete(state.visited)
	sink := sim.Event_Sink{data = &state, dispatch = dispatch}
	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}

	sim.run_session(&s, input, sink)

	fmt.printfln("run_session ended after %d event(s)", len(state.events))
}

// Headless_State is the shared context both the Input_Source and Event_Sink
// halves of the headless auto-player read/write (issue #24): Odin has no
// other way for the two callbacks to cooperate, since each only receives its
// own rawptr. It tracks just enough of the map from the event stream — the
// graph (from Event_Run_Started), the current node and which nodes have been
// visited (from arrivals) — for get_captain_choice to pick a *legal* next
// move, since travel is now gated by adjacency (the ascending-id plan no
// longer works against a generated graph).
Headless_State :: struct {
	events:  [dynamic]sim.Event,
	run_map: run.Map, // borrowed from Event_Run_Started (the masked public map)
	visited: []bool,
	current: int,
}

// get_captain_choice is the headless Input_Source: no real player, so it
// always resolves the current decision deterministically — Hold every battle
// round, always pick upgrade option 0, and for travel pick a legal move that
// makes forward progress toward Goal (any forward neighbour; the first
// legal option otherwise). Kinds are hidden in the tracked map, so the plan
// never depends on what an unvisited node holds — only on the graph shape.
get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Headless_State)data

	switch awaiting {
	case .Awaiting_Battle_Command:
		return sim.Command(sim.Command_Battle_Choice{combat_command = combat.Command_Hold{}})
	case .Awaiting_Upgrade_Choice:
		return sim.Command(sim.Command_Pick_Upgrade{option_index = 0})
	case .Awaiting_Travel_Choice:
		return sim.Command(sim.Command_Travel_To{point_id = sim.Point_ID(headless_next_point(state))})
	case .Ended:
		panic("get_captain_choice called while the sim isn't awaiting a decision")
	}
	panic("unreachable")
}

// headless_next_point picks the auto-player's next travel destination: a
// forward neighbour (deeper layer) if one is legally reachable, else the first
// legal option — always making progress toward Goal without depending on any
// hidden encounter kind.
headless_next_point :: proc(state: ^Headless_State) -> int {
	options := run.run_travel_options(state.run_map, state.current, state.visited)
	defer delete(options)
	assert(len(options) > 0, "no legal travel option from the current node")

	for dest in options {
		if state.run_map.points[dest].layer > state.run_map.points[state.current].layer {
			return dest
		}
	}
	return options[0]
}

// dispatch is the headless Event_Sink: log-record every event, and track the
// map/visited state get_captain_choice needs to plan legal moves.
// Event_Encounter_Resolved.snapshot needs no cleanup here — it lives in the
// Sim's own run-scoped arena and is reclaimed wholesale by sim_destroy (issue
// #52), not owned per-recipient.
dispatch :: proc(data: rawptr, event: sim.Event) {
	state := cast(^Headless_State)data
	append(&state.events, event)
	fmt.printfln("%v", event)

	switch e in event {
	case sim.Event_Run_Started:
		state.run_map = e.run_map
		state.visited = make([]bool, len(e.run_map.points))
		state.visited[0] = true // the ship starts at Start (id 0)
	case sim.Event_Arrived_At_Point:
		state.current = e.point.id
		state.visited[e.point.id] = true
	case sim.Event_Ship_Battle_Sighted:
	case sim.Event_Battle_Menu:
	case sim.Event_Battle_Event:
	case sim.Event_Ship_Updated:
	case sim.Event_Upgrade_Offer_Presented:
	case sim.Event_Upgrade_Applied:
	case sim.Event_Encounter_Resolved:
	case sim.Event_Run_Ended:
	}
}
