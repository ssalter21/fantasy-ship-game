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
	defer delete(state.fights.rows) // headless_voyage's caller owns these; here the test does
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
	row, fights := headless_voyage(0, quiet = true)
	defer delete(fights)

	testing.expect(t, row.events > 0)
	testing.expect(t, row.status != .In_Progress)
	testing.expect_value(t, row.seed, u64(0))
}

@(test)
a_voyage_row_records_the_walk_the_events_described :: proc(t: ^testing.T) {
	// The row's counts come off the Event stream, so each must square with the outcome the
	// same stream reported: a voyage that went anywhere walked nodes and reached a zone, and
	// one that reached Haven is one that did not sink.
	row, fights := headless_voyage(0, quiet = true)
	defer delete(fights)

	testing.expect(t, row.nodes > 0)
	testing.expect(t, row.encounters <= row.nodes)
	testing.expect(t, row.cargo >= 0)
	_, reached := row.zone.?
	testing.expect(t, reached)
	if row.status == .Won {
		testing.expect(t, row.hull > 0)
	} else {
		testing.expect(t, row.hull <= 0)
	}
}

@(test)
a_sweep_of_seeds_runs_each_voyage_against_its_own_sim :: proc(t: ^testing.T) {
	// Each voyage builds and tears down a Sim of its own, so a second pass over the
	// same seeds must answer exactly what the first did — a Sim (or its run-scoped
	// arena) carried across runs is what this would catch.
	first: [4]Voyage_Row
	for seed in 0 ..< 4 {
		fights: [dynamic]Fight_Row
		first[seed], fights = headless_voyage(u64(seed), quiet = true)
		delete(fights)
	}

	for seed in 0 ..< 4 {
		row, fights := headless_voyage(u64(seed), quiet = true)
		defer delete(fights)
		testing.expect_value(t, row, first[seed])
	}
}

@(test)
a_bare_command_line_asks_for_one_voyage_from_seed_zero_written_to_stdout :: proc(t: ^testing.T) {
	req, ok := headless_request({})

	testing.expect(t, ok)
	testing.expect_value(t, req.seed, u64(0))
	testing.expect_value(t, req.runs, 1)
	_, named := req.out.?
	testing.expect(t, !named)
}

@(test)
seed_runs_and_out_are_read_in_either_spelling :: proc(t: ^testing.T) {
	spaced, spaced_ok := headless_request({"--seed", "7", "--runs", "1000", "--out", "sweep.csv"})
	testing.expect(t, spaced_ok)
	testing.expect_value(t, spaced.seed, u64(7))
	testing.expect_value(t, spaced.runs, 1000)
	testing.expect_value(t, spaced.out.? or_else "", "sweep.csv")

	joined, joined_ok := headless_request({"--seed=7", "--runs=1000", "--out=sweep.csv"})
	testing.expect(t, joined_ok)
	testing.expect_value(t, joined.seed, u64(7))
	testing.expect_value(t, joined.runs, 1000)
	testing.expect_value(t, joined.out.? or_else "", "sweep.csv")
}

@(test)
the_fight_rows_go_to_a_named_file_or_nowhere :: proc(t: ^testing.T) {
	// There is no stdout fallback for this one: two CSVs of different shapes cannot share a
	// destination, which is also why naming the same file twice is refused.
	bare, bare_ok := headless_request({"--runs", "3"})
	testing.expect(t, bare_ok)
	_, named := bare.fights.?
	testing.expect(t, !named)

	req, ok := headless_request({"--out", "sweep.csv", "--fights=battles.csv"})
	testing.expect(t, ok)
	testing.expect_value(t, req.fights.? or_else "", "battles.csv")
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
		{"--out"}, // named no path
		{"--out="}, // named an empty one
		{"--out", "--runs", "3"}, // a path is any string, so the next flag is caught first
		{"--fights"}, // named no path
		{"--fights="}, // named an empty one
		{"--out", "sweep.csv", "--fights", "sweep.csv"}, // two formats into one file
	}

	for args in cases {
		_, ok := headless_request(args)
		testing.expectf(t, !ok, "expected %v to be rejected", args)
	}
}
