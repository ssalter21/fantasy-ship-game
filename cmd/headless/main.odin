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
// own rawptr. dispatch records what kind of decision is coming next;
// get_captain_choice reads that back to decide what Command to return.
Headless_State :: struct {
	events:          [dynamic]sim.Event,
	// next_point is the auto-player's travel plan: every point id in
	// ascending order (every port and every encounter, then Goal) — the
	// same "same content, runnable headless" full-map coverage the issue's
	// playtest goal asks for.
	next_point:      int,
	in_battle:       bool,
	upgrade_pending: bool,
}

// get_captain_choice is the headless Input_Source: no real player, so it
// always resolves the current decision deterministically — Hold every
// battle round, always pick upgrade option 0, otherwise travel to the next
// point in ascending id order.
get_captain_choice :: proc(data: rawptr) -> sim.Command {
	state := cast(^Headless_State)data

	if state.in_battle {
		return sim.Command(sim.Command_Battle_Choice{combat_command = combat.Command_Hold{}})
	}
	if state.upgrade_pending {
		return sim.Command(sim.Command_Pick_Upgrade{option_index = 0})
	}

	point_id := state.next_point
	state.next_point += 1
	return sim.Command(sim.Command_Travel_To{point_id = point_id})
}

// dispatch is the headless Event_Sink: log-record every event (instead of
// animating it) and track just enough context for get_captain_choice above.
// Frees Event_Encounter_Resolved.snapshot.ship.layout once logged, per that
// type's caller-owns-it contract (core/sim/sim.odin).
dispatch :: proc(data: rawptr, event: sim.Event) {
	state := cast(^Headless_State)data
	append(&state.events, event)
	fmt.printfln("%v", event)

	switch e in event {
	case sim.Event_Run_Started:
	case sim.Event_Arrived_At_Point:
	case sim.Event_Ship_Battle_Sighted:
		state.in_battle = true
	case sim.Event_Battle_Menu:
	case sim.Event_Battle_Event:
		if _, ended := e.inner.(combat.Event_Battle_Ended); ended {
			state.in_battle = false
		}
	case sim.Event_Ship_Updated:
	case sim.Event_Upgrade_Offer_Presented:
		state.upgrade_pending = true
	case sim.Event_Upgrade_Applied:
		state.upgrade_pending = false
	case sim.Event_Encounter_Resolved:
		delete(e.snapshot.ship.layout)
	case sim.Event_Run_Ended:
	}
}
