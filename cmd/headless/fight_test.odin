package main

import "core:strconv"
import "core:strings"
import "core:testing"
import combat "../../core/combat"
import ship "../../core/ship"
import voyage "../../core/voyage"

// What a sweep records about the battles inside a voyage: the row format, the names its three
// enum columns are spelled with, the collector that fills a row off the Event stream, and the
// rows a real sweep lands.

@(test)
a_fight_row_carries_one_field_per_header_column_in_that_order :: proc(t: ^testing.T) {
	// The header and headless_fight_line are one format stated twice; nothing but this holds
	// them in step. Every column gets a value of its own, so the line pins which field landed
	// where rather than only how many did.
	line := headless_fight_line(
		Fight_Row {
			seed = 12,
			fight = 2,
			zone = .Deep,
			depth = 3,
			archetype = "Ironclad Hulk",
			rounds = 4,
			ending = .Destroyed,
			winner = combat.Side.A,
			escaped = nil,
			player_hull_start = 90,
			player_hull_end = 65,
			hostile_hull_start = 120,
			hostile_hull_end = 0,
			press = ship.Phase.Fire,
			commit_rounds = 1,
			payout = 55,
		},
	)

	testing.expect_value(t, line, "12,2,deep,3,Ironclad Hulk,4,destroyed,player,none,90,25,120,120,fire,1,55")
	testing.expect_value(t, strings.count(line, ","), strings.count(HEADLESS_FIGHT_HEADER, ","))
}

@(test)
a_row_names_how_the_battle_ended_apart_from_who_it_went_to :: proc(t: ^testing.T) {
	// The two are separate columns because the round cap awards a winner on Hull alone: a
	// stalemate must be readable as a stalemate whatever the tiebreak said.
	testing.expect_value(t, headless_ending_name(.Destroyed), "destroyed")
	testing.expect_value(t, headless_ending_name(.Broke_Off), "broke_off")
	testing.expect_value(t, headless_ending_name(.Round_Cap), "round_cap")

	testing.expect_value(t, headless_side_name(combat.Side.A), "player")
	testing.expect_value(t, headless_side_name(combat.Side.B), "hostile")
	testing.expect_value(t, headless_side_name(nil), "none")
}

@(test)
a_row_names_the_side_that_broke_off_where_one_did :: proc(t: ^testing.T) {
	// Break Off ends the battle for both ships and Event_Battle_Ended names no side, so the
	// player's is taken off the order it gave and the hostile's by elimination — which is the
	// whole of what makes the escape gate readable as a straddle.
	player := Fight_Log{seed = 1}
	defer delete(player.rows)
	fight_log_sighted(&player, voyage.Scaling_Site{zone = .Deep, depth = 1}, "Reef Skimmer", 70, 90)
	fight_log_order(&player, combat.Command_Break_Off{})
	fight_log_battle_event(&player, combat.Event_Battle_Ended{round = 5, reason = .Broke_Off, winner = nil})
	fight_log_close(&player)

	hostile := Fight_Log{seed = 1}
	defer delete(hostile.rows)
	fight_log_sighted(&hostile, voyage.Scaling_Site{zone = .Deep, depth = 1}, "Reef Skimmer", 70, 90)
	fight_log_order(&hostile, combat.Command_Hold{})
	fight_log_battle_event(&hostile, combat.Event_Battle_Ended{round = 5, reason = .Broke_Off, winner = nil})
	fight_log_close(&hostile)

	fought_out := Fight_Log{seed = 1}
	defer delete(fought_out.rows)
	fight_log_sighted(&fought_out, voyage.Scaling_Site{zone = .Deep, depth = 1}, "Reef Skimmer", 70, 90)
	fight_log_battle_event(&fought_out, combat.Event_Battle_Ended{round = 5, reason = .Destroyed, winner = combat.Side.A})
	fight_log_close(&fought_out)

	testing.expect_value(t, player.rows[0].escaped, combat.Side.A)
	testing.expect_value(t, hostile.rows[0].escaped, combat.Side.B)
	testing.expect_value(t, fought_out.rows[0].escaped, nil)
}

@(test)
a_row_names_the_phase_a_press_was_spent_on_and_says_so_when_it_was_not :: proc(t: ^testing.T) {
	testing.expect_value(t, headless_press_name(ship.Phase.Fire), "fire")
	testing.expect_value(t, headless_press_name(ship.Phase.Brace), "brace")
	testing.expect_value(t, headless_press_name(nil), "none")
}

@(test)
no_hostile_archetype_name_carries_a_comma :: proc(t: ^testing.T) {
	// The archetype column is the one field of either row format that is authored content
	// rather than a number or a name from a table here, and the line is written unquoted.
	for archetype in voyage.voyage_hostile_roster() {
		testing.expectf(t, !strings.contains(archetype.name, ","), "%q would break the row", archetype.name)
	}
}

@(test)
the_log_fills_a_row_from_the_battle_it_watched :: proc(t: ^testing.T) {
	// A battle as the sink and the input source between them see it: sighted, two rounds
	// fought under a Press and a Commit, the hostile sunk, the wreck paid out.
	log := Fight_Log{seed = 7}
	defer delete(log.rows)

	fight_log_sighted(&log, voyage.Scaling_Site{zone = .Open_Sea, depth = 2}, "Reef Skimmer", 80, 100)
	fight_log_order(&log, combat.Command_Press{phase = .Fire})
	fight_log_battle_event(&log, combat.Event_Round_Resolved{round = 1, hull = {.A = 74, .B = 40}})
	fight_log_order(&log, combat.Command_Commit{})
	fight_log_battle_event(&log, combat.Event_Round_Resolved{round = 2, hull = {.A = 74, .B = 0}})
	fight_log_battle_event(&log, combat.Event_Ship_Sunk{round = 2, side = .B})
	fight_log_battle_event(
		&log,
		combat.Event_Battle_Ended{round = 2, reason = .Destroyed, winner = combat.Side.A},
	)
	fight_log_payout(&log, 30)
	fight_log_close(&log)

	if !testing.expect_value(t, len(log.rows), 1) {
		return
	}
	testing.expect_value(
		t,
		log.rows[0],
		Fight_Row {
			seed = 7,
			fight = 1,
			zone = .Open_Sea,
			depth = 2,
			archetype = "Reef Skimmer",
			rounds = 2,
			ending = .Destroyed,
			winner = combat.Side.A,
			player_hull_start = 80,
			player_hull_end = 74,
			hostile_hull_start = 100,
			hostile_hull_end = 0,
			press = ship.Phase.Fire,
			commit_rounds = 1,
			payout = 30,
		},
	)
}

@(test)
a_battle_that_resolved_no_round_keeps_the_hulls_it_opened_with :: proc(t: ^testing.T) {
	// A round ended by Break Off resolves no phases and emits no Event_Round_Resolved, so
	// nothing overwrites the opening hulls — the swing is 0, not the whole pool.
	log := Fight_Log{seed = 1}
	defer delete(log.rows)

	fight_log_sighted(&log, voyage.Scaling_Site{zone = .Coastal, depth = 0}, "Death Throes", 60, 40)
	fight_log_battle_event(&log, combat.Event_Battle_Ended{round = 1, reason = .Broke_Off, winner = nil})
	fight_log_close(&log)

	if !testing.expect_value(t, len(log.rows), 1) {
		return
	}
	row := log.rows[0]
	testing.expect_value(t, row.player_hull_start, row.player_hull_end)
	testing.expect_value(t, row.hostile_hull_start, row.hostile_hull_end)
	testing.expect_value(t, row.ending, combat.End_Reason.Broke_Off)
}

@(test)
each_battle_of_a_voyage_gets_a_row_numbered_in_the_order_it_was_fought :: proc(t: ^testing.T) {
	// A row stays open past the battle's end so it can collect the wreck's payout, which
	// arrives afterwards; the next sighting is what closes it, and the voyage's end closes
	// the last one.
	log := Fight_Log{seed = 1}
	defer delete(log.rows)

	site := voyage.Scaling_Site{zone = .Coastal, depth = 0}
	fight_log_sighted(&log, site, "Boarding Party", 100, 40)
	fight_log_battle_event(&log, combat.Event_Battle_Ended{round = 3, reason = .Destroyed, winner = combat.Side.A})
	fight_log_payout(&log, 12)
	fight_log_sighted(&log, site, "Ironclad Hulk", 80, 40)
	fight_log_battle_event(&log, combat.Event_Battle_Ended{round = 20, reason = .Round_Cap, winner = combat.Side.B})
	fight_log_close(&log)

	if !testing.expect_value(t, len(log.rows), 2) {
		return
	}
	testing.expect_value(t, log.rows[0].fight, 1)
	testing.expect_value(t, log.rows[0].payout, 12)
	testing.expect_value(t, log.rows[1].fight, 2)
	// The payout belongs to the battle that earned it, not to whatever came next.
	testing.expect_value(t, log.rows[1].payout, 0)
}

@(test)
a_sweep_writes_the_fight_rows_of_the_voyages_it_ran :: proc(t: ^testing.T) {
	rows, fights, _, ok := sweep_test_texts(Run_Request{seed = 1, runs = 6}, "sweep-fights.csv")
	if !testing.expect(t, ok, "the sweep could not be written and read back") {
		return
	}
	defer delete(rows)
	defer delete(fights)

	lines := strings.split_lines(strings.trim_right(fights, "\n"), context.allocator)
	defer delete(lines)

	testing.expect_value(t, lines[0], HEADLESS_FIGHT_HEADER)
	if !testing.expect(t, len(lines) > 1, "the sweep fought no battles at all") {
		return
	}

	// Every row joins back to a voyage the same sweep ran, its columns line up with the
	// header, and it names the stakes and the hostile it was fought against.
	seeds := swept_seeds(rows)
	defer delete(seeds)

	for line in lines[1:] {
		fields := strings.split(line, ",", context.allocator)
		defer delete(fields)

		testing.expectf(t, len(fields) == strings.count(HEADLESS_FIGHT_HEADER, ",") + 1, "ragged row: %s", line)
		testing.expectf(t, fields[0] in seeds, "row names a seed the sweep never ran: %s", line)
		testing.expectf(t, fields[2] != "none", "a battle was fought at no zone: %s", line)
		testing.expectf(t, fields[4] != "", "a battle named no archetype: %s", line)
		rounds, is_number := strconv.parse_int(fields[5])
		testing.expectf(t, is_number && rounds > 0, "a battle resolved in no rounds: %s", line)
	}
}

// swept_seeds is the set of seeds a voyage-row file reports on, read off the first column, so
// a Fight row's seed can be checked against the voyages the same sweep actually ran.
swept_seeds :: proc(rows: string) -> map[string]bool {
	seeds: map[string]bool
	lines := strings.split_lines(strings.trim_right(rows, "\n"), context.allocator)
	defer delete(lines)

	for line in lines[1:] {
		seeds[line[:strings.index_byte(line, ',')]] = true
	}
	return seeds
}
