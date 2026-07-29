package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import voyage "../../core/voyage"

// What a sweep writes: the row format, the names its two enum columns are spelled with, and
// the whole path from a seed range through the driver to a file that can be opened again.

@(test)
a_row_carries_one_field_per_header_column_in_that_order :: proc(t: ^testing.T) {
	// The header and headless_row_line are one format stated twice; nothing but this holds
	// them in step. Every column gets a value of its own, so the line pins which field landed
	// where rather than only how many did. No field may carry a comma either, which the count
	// against the header says.
	line := headless_row_line(
		Voyage_Row {
			seed = 12,
			status = .Won,
			zone = voyage.Zone.Deep,
			nodes = 1,
			hull = 2,
			cargo = 3,
			encounters = 4,
			events = 5,
		},
	)

	testing.expect_value(t, line, "12,haven,deep,1,2,3,4,5")
	testing.expect_value(t, strings.count(line, ","), strings.count(HEADLESS_ROW_HEADER, ","))
	testing.expect_value(t, HEADLESS_ROW_HEADER, "seed,outcome,zone,nodes,hull,cargo,encounters,events")
}

@(test)
a_row_names_reaching_haven_apart_from_going_down :: proc(t: ^testing.T) {
	testing.expect_value(t, headless_outcome_name(.Won), "haven")
	testing.expect_value(t, headless_outcome_name(.Lost), "sank")
}

@(test)
a_row_names_the_zone_reached_and_says_so_when_none_was :: proc(t: ^testing.T) {
	testing.expect_value(t, headless_zone_name(voyage.Zone.Coastal), "coastal")
	testing.expect_value(t, headless_zone_name(voyage.Zone.Open_Sea), "open_sea")
	testing.expect_value(t, headless_zone_name(voyage.Zone.Deep), "deep")
	testing.expect_value(t, headless_zone_name(nil), "none")
}

@(test)
a_sweep_writes_a_header_and_one_row_per_seed_in_seed_order :: proc(t: ^testing.T) {
	text, fights, _, ok := sweep_test_texts(Run_Request{seed = 3, runs = 3}, "sweep-order.csv")
	if !testing.expect(t, ok, "the sweep could not be written and read back") {
		return
	}
	defer delete(text)
	defer delete(fights)

	lines := strings.split_lines(strings.trim_right(text, "\n"), context.allocator)
	defer delete(lines)

	testing.expect_value(t, len(lines), 4)
	testing.expect_value(t, lines[0], HEADLESS_ROW_HEADER)
	for row, i in lines[1:] {
		testing.expectf(t, strings.has_prefix(row, fmt.tprintf("%d,", 3 + i)), "row out of seed order: %s", row)
	}
}

@(test)
the_same_seed_range_writes_the_same_rows_every_time :: proc(t: ^testing.T) {
	// The whole point of a sweep is that its numbers can be compared against the next one,
	// which holds only if a seed range is a fixed question.
	req := Run_Request{seed = 11, runs = 3}

	first, first_fights, _, first_ok := sweep_test_texts(req, "sweep-repeat-a.csv")
	second, second_fights, _, second_ok := sweep_test_texts(req, "sweep-repeat-b.csv")
	if !testing.expect(t, first_ok && second_ok, "the sweeps could not be written and read back") {
		return
	}
	defer delete(first)
	defer delete(second)
	defer delete(first_fights)
	defer delete(second_fights)

	testing.expect_value(t, first, second)
	// The Fight rows are the same question asked of a longer stream — the orders the player
	// gave, round by round — so they are pinned alongside.
	testing.expect(t, strings.count(first_fights, "\n") > 1) // a header alone proves nothing
	testing.expect_value(t, first_fights, second_fights)
}

@(test)
a_destination_that_cannot_be_opened_is_refused_and_none_named_is_stdout :: proc(t: ^testing.T) {
	_, ok := headless_open_destination("no-such-directory-for-a-sweep/rows.csv")
	testing.expect(t, !ok)

	out, stdout_ok := headless_open_destination(nil)
	testing.expect(t, stdout_ok)
	testing.expect(t, out == os.stdout)
}

// sweep_test_texts runs `req` into two files of its own under the temp directory — the voyage
// rows and the Fight rows — and reads the whole of both back, removing them behind itself,
// along with the balance tally the same sweep kept. Both texts are the caller's to delete.
//
// Every allocation here is on the ordinary allocator: headless_sweep drains
// context.temp_allocator between voyages, so a path held there would not survive its sweep.
// `name` is per-test because the test runner is threaded, and two sweeps sharing a file would
// be one sweep's rows read by the other.
sweep_test_texts :: proc(
	req: Run_Request,
	name: string,
) -> (
	rows: string,
	fights: string,
	tally: Balance_Tally,
	ok: bool,
) {
	dir, dir_err := os.temp_directory(context.allocator)
	if dir_err != nil {
		return "", "", tally, false
	}
	defer delete(dir)

	rows_path := fmt.aprintf("%s%s%s", dir, os.Path_Separator_String, name)
	defer delete(rows_path)
	defer os.remove(rows_path)
	fights_path := fmt.aprintf("%s.fights", rows_path)
	defer delete(fights_path)
	defer os.remove(fights_path)

	sweep := req
	sweep.out = rows_path
	sweep.fights = fights_path

	out, opened := headless_open_destination(sweep.out)
	if !opened {
		return "", "", tally, false
	}
	fights_out, fights_opened := headless_open_destination(sweep.fights)
	if !fights_opened {
		os.close(out)
		return "", "", tally, false
	}

	swept, wrote := headless_sweep(sweep, out, fights_out)
	closed := os.close(out) == nil && os.close(fights_out) == nil
	if !wrote || !closed {
		return "", "", tally, false
	}

	rows_data, rows_err := os.read_entire_file_from_path(rows_path, context.allocator)
	if rows_err != nil {
		return "", "", tally, false
	}
	fights_data, fights_err := os.read_entire_file_from_path(fights_path, context.allocator)
	if fights_err != nil {
		delete(rows_data)
		return "", "", tally, false
	}
	return string(rows_data), string(fights_data), swept, true
}
