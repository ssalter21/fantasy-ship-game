package main

import "core:testing"
import sim "../../core/sim"
import voyage "../../core/voyage"

// The scripted player's per-decision behavior is tested where it lives, in
// core/sim (scripted_player_test.odin). This covers the wiring that is this
// package's own: dispatch tracking the voyage state get_captain_choice feeds
// the shared player, the command line the run is asked for, and the two sinks.

@(test)
the_auto_player_reaches_a_voyage_ended_event_navigating_the_graph :: proc(t: ^testing.T) {
	s := sim.sim_create(0)
	defer sim.sim_destroy(&s)

	state := Headless_State{}
	sink := sim.Event_Sink{data = &state, dispatch = headless_print}
	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}

	sim.run_session(&s, input, sink)

	_, ok := state.last_event.(sim.Event_Voyage_Ended)
	testing.expect(t, ok)
}

@(test)
the_quiet_sink_tracks_everything_the_printing_one_does :: proc(t: ^testing.T) {
	// The two sinks differ by the printed line and nothing else, so a sweep's state must
	// come out of headless_track exactly as a single run's comes out of headless_print.
	quiet, printing := Headless_State{}, Headless_State{}
	events := []sim.Event {
		sim.Event_Arrived_At_Node{node = voyage.Node{id = 3}},
		sim.Event_Voyage_Ended{status = .Won},
	}

	for event in events {
		headless_track(&quiet, event)
		headless_print(&printing, event)
	}

	testing.expect_value(t, quiet.event_count, 2)
	testing.expect_value(t, quiet.view.current, sim.Node_ID(3))
	testing.expect_value(t, quiet.status, voyage.Voyage_Status.Won)
	testing.expect_value(t, printing.event_count, quiet.event_count)
	testing.expect_value(t, printing.view.current, quiet.view.current)
	testing.expect_value(t, printing.status, quiet.status)
}

@(test)
a_quiet_voyage_still_counts_its_events_and_lands_on_an_outcome :: proc(t: ^testing.T) {
	status, events := headless_voyage(0, quiet = true)

	testing.expect(t, events > 0)
	testing.expect(t, status != .In_Progress)
}

@(test)
a_sweep_of_seeds_runs_each_voyage_against_its_own_sim :: proc(t: ^testing.T) {
	// Each voyage builds and tears down a Sim of its own, so a second pass over the
	// same seeds must answer exactly what the first did — a Sim (or its run-scoped
	// arena) carried across runs is what this would catch.
	first: [4]voyage.Voyage_Status
	first_events: [4]int
	for seed in 0 ..< 4 {
		first[seed], first_events[seed] = headless_voyage(u64(seed), quiet = true)
	}

	for seed in 0 ..< 4 {
		status, events := headless_voyage(u64(seed), quiet = true)
		testing.expect_value(t, status, first[seed])
		testing.expect_value(t, events, first_events[seed])
	}
}

@(test)
a_bare_command_line_asks_for_one_voyage_from_seed_zero :: proc(t: ^testing.T) {
	req, ok := headless_request({})

	testing.expect(t, ok)
	testing.expect_value(t, req.seed, u64(0))
	testing.expect_value(t, req.runs, 1)
}

@(test)
seed_and_runs_are_read_in_either_spelling :: proc(t: ^testing.T) {
	spaced, spaced_ok := headless_request({"--seed", "7", "--runs", "1000"})
	testing.expect(t, spaced_ok)
	testing.expect_value(t, spaced.seed, u64(7))
	testing.expect_value(t, spaced.runs, 1000)

	joined, joined_ok := headless_request({"--seed=7", "--runs=1000"})
	testing.expect(t, joined_ok)
	testing.expect_value(t, joined.seed, u64(7))
	testing.expect_value(t, joined.runs, 1000)
}

@(test)
a_command_line_naming_no_runnable_voyage_is_rejected :: proc(t: ^testing.T) {
	cases := [][]string {
		{"--seed", "over-yonder"},
		{"--seed"}, // named nothing
		{"--seed", "--runs", "3"}, // the next flag is not this one's value
		{"--runs", "none"},
		{"--runs", "0"},
		{"--runs", "-1"},
		{"--seedd", "7"}, // a misspelling is not the flag it nearly is
		{"7", "1000"}, // bare words name no flag at all
	}

	for args in cases {
		_, ok := headless_request(args)
		testing.expectf(t, !ok, "expected %v to be rejected", args)
	}
}
