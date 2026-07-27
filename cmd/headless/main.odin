package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import voyage "../../core/voyage"
import sim "../../core/sim"

main :: proc() {
	req, ok := headless_request(os.args[1:])
	if !ok {
		fmt.eprintln("headless: usage: headless [--seed <n>] [--runs <n>]")
		os.exit(1)
	}

	// A sweep runs quiet, because a thousand printed voyages is a million lines; one voyage
	// prints its events, which is what watching a single run go by means.
	quiet := req.runs > 1
	events := 0
	for i in 0 ..< req.runs {
		_, voyage_events := headless_voyage(req.seed + u64(i), quiet)
		events += voyage_events
	}

	if quiet {
		fmt.printfln("%d voyages ended after %d event(s)", req.runs, events)
	} else {
		fmt.printfln("run_session ended after %d event(s)", events)
	}
}

// Run_Request is the run a command line asked for: `runs` voyages from consecutive seeds
// starting at `seed`, so repeating the pair repeats the whole sweep. Its zero value is a
// run of no voyages, which is nothing — headless_request starts from the one-voyage
// default instead (a deliberate break with the zero-value-is-meaningful rule).
Run_Request :: struct {
	seed: u64,
	runs: int,
}

// headless_request reads the run out of a command line, in either `--flag <value>` or
// `--flag=<value>` spelling. Absent flags give one voyage from seed 0.
//
// Anything it cannot read as a runnable request is rejected: an unknown flag, a bare word,
// a non-number, a run of none, a flag whose value is the next flag. A sweep script that
// misspells `--seed` gets an error rather than a thousand voyages from the wrong seed.
headless_request :: proc(args: []string) -> (req: Run_Request, ok: bool) {
	req = Run_Request{seed = 0, runs = 1}

	for i := 0; i < len(args); {
		flag, value := args[i], ""
		if eq := strings.index_byte(flag, '='); eq >= 0 {
			flag, value = flag[:eq], flag[eq + 1:]
			i += 1
		} else if i + 1 < len(args) {
			value = args[i + 1]
			i += 2
		} else {
			return req, false // a flag at the tail naming nothing
		}

		switch flag {
		case "--seed":
			req.seed = strconv.parse_u64(value) or_return
		case "--runs":
			req.runs = strconv.parse_int(value) or_return
			if req.runs < 1 {
				return req, false
			}
		case:
			return req, false
		}
	}
	return req, true
}

// headless_voyage runs one scripted voyage from a seed and reports how it ended.
//
// The Sim is built and destroyed here, so a sweep holds one voyage's run-scoped arena at a
// time (ADR-0010) rather than a thousand. Only values cross back out: everything the sink
// tracked by reference — the Event it last saw, the Map, the travel options — borrows from
// that arena and is gone by the time this returns.
headless_voyage :: proc(seed: u64, quiet: bool) -> (status: voyage.Voyage_Status, events: int) {
	s := sim.sim_create(seed)
	defer sim.sim_destroy(&s)

	state := Headless_State{}
	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}
	sink := sim.Event_Sink{data = &state, dispatch = quiet ? headless_track : headless_print}

	sim.run_session(&s, input, sink)

	return state.status, state.event_count
}

// Headless_State is the shared context the Input_Source and Event_Sink halves of
// the auto-player cooperate through — each callback receives only its own rawptr,
// so shared state has nowhere else to live.
//
// It counts events rather than keeping them: an Event borrows from the Sim's run arena,
// so a kept copy is only valid as long as the Sim is. status is what both sinks leave
// behind for a caller that outlives the Sim — a plain value, and the voyage's whole
// outcome. `view` is the scripted player's own input, filled by the sink from the same
// stream: the map, ship and stage state it decides from all borrow from the Sim's arena
// too, and are read only while it lives.
Headless_State :: struct {
	event_count: int,
	last_event:  sim.Event, // borrowed from the Sim's run arena; valid only while it lives
	status:      voyage.Voyage_Status,
	view:        sim.Scripted_View,
}

// get_captain_choice is the headless Input_Source: it hands the shared scripted
// player (sim.scripted_player_command) the voyage state the sink tracked.
get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Headless_State)data
	return sim.scripted_player_command(state.view, awaiting)
}

// headless_print is the printing sink: format the event, then track it like the quiet one
// does. The line is the whole difference between the two.
headless_print :: proc(data: rawptr, event: sim.Event) {
	fmt.printfln("%v", event)
	headless_track(data, event)
}

// headless_track is the quiet sink: count every event, keep the voyage's outcome, and
// keep the scripted player's view of the voyage current — all of it without formatting a
// thing. The view's fields are the facts the player decides from, each taken from the one
// Event that carries it (sim.Scripted_View).
// Event_Encounter_Resolved.snapshot needs no cleanup here — it lives in the Sim's
// run-scoped arena and is freed wholesale by sim_destroy, not owned per-recipient.
headless_track :: proc(data: rawptr, event: sim.Event) {
	state := cast(^Headless_State)data
	state.event_count += 1
	state.last_event = event

	switch e in event {
	case sim.Event_Voyage_Started:
		state.view.voyage_map = e.voyage_map
		state.view.player = e.ship
	case sim.Event_Travel_Options:
		state.view.travel_options = e.options
	case sim.Event_Arrived_At_Node:
		state.view.current = e.node.id
	case sim.Event_Voyage_Ended:
		state.status = e.status
	case sim.Event_Battle_Menu:
		state.view.may_press = e.may_press
	case sim.Event_Ship_Updated:
		state.view.player = e.ship
	case sim.Event_Options_Presented:
		state.view.stage_options = e.options
	case sim.Event_Trade_Presented:
		state.view.trade = e.trade
		state.view.trade_can_accept = e.can_accept
	case sim.Event_Refit_Started:
		state.view.refit_incoming = e.incoming
	case sim.Event_Fitting_Installed:
		// The incoming item has landed, so the refit has nothing left to place.
		state.view.refit_incoming = nil
	case sim.Event_Refit_Finished:
		state.view.refit_incoming = nil
	case sim.Event_Ship_Battle_Sighted:
	case sim.Event_Battle_Event:
	case sim.Event_Wreck_Looted:
	case sim.Event_Reward_Paid:
	case sim.Event_Stage_Entered:
	case sim.Event_Encounter_Halted:
	case sim.Event_Purchase_Rejected:
	case sim.Event_Fitting_Moved:
	case sim.Event_Fitting_Removed:
	case sim.Event_Cargo_Jettisoned:
	case sim.Event_Refit_Rejected:
	case sim.Event_Encounter_Resolved:
	}
}
