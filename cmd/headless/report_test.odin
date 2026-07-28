package main

import "core:strings"
import "core:testing"
import combat "../../core/combat"
import ship "../../core/ship"
import voyage "../../core/voyage"

// The balance report: what a Fight row folds into a tally, and what the page a reader reads
// says. Nothing here asserts a figure the game produces is in any band — the report is an
// instrument, and a test that pinned an observed rate would make it the gate the glossary
// rules out.

@(test)
a_fight_row_lands_in_the_stakes_cell_it_was_fought_at :: proc(t: ^testing.T) {
	// The stakes buckets are the two axes of a Scaling_Site, so a row must count once in its
	// own cell and once in the whole, and nowhere else.
	tally: Balance_Tally
	balance_tally_add(&tally, report_test_row(voyage.Zone.Open_Sea, 2))
	balance_tally_add(&tally, report_test_row(voyage.Zone.Deep, 0))

	testing.expect_value(t, tally.all.fights, 2)
	testing.expect_value(t, tally.stakes[.Open_Sea][2].fights, 1)
	testing.expect_value(t, tally.stakes[.Deep][0].fights, 1)
	testing.expect_value(t, tally.stakes[.Open_Sea][0].fights, 0)
	testing.expect_value(t, tally.stakes[.Coastal][2].fights, 0)
}

@(test)
the_tally_sums_the_swing_each_side_took_and_the_rounds_it_took_them_over :: proc(t: ^testing.T) {
	// The per-round figures are ratios of these two sums, so what the report divides is what
	// the rows said and not a mean of means.
	tally: Balance_Tally
	first := report_test_row(voyage.Zone.Coastal, 1)
	first.rounds, first.player_hull_end, first.hostile_hull_end = 4, 80, 60
	second := report_test_row(voyage.Zone.Coastal, 1)
	second.rounds, second.player_hull_end, second.hostile_hull_end = 6, 50, 0

	balance_tally_add(&tally, first)
	balance_tally_add(&tally, second)

	testing.expect_value(t, tally.all.rounds, 10)
	testing.expect_value(t, tally.all.player_swing, (100 - 80) + (100 - 50))
	testing.expect_value(t, tally.all.hostile_swing, (100 - 60) + (100 - 0))
	testing.expect_value(t, report_mean(tally.all.player_swing, tally.all.rounds), 7.0)
}

@(test)
a_battle_the_player_did_not_come_out_of_pays_no_wreck :: proc(t: ^testing.T) {
	// Survival is read off the Hull the battle left the player on, not off the winner: the
	// round cap awards one on Hull alone, and a hostile that broke off leaves nobody a winner.
	tally: Balance_Tally

	won := report_test_row(voyage.Zone.Deep, 3)
	won.ending, won.winner, won.hostile_hull_end, won.payout = .Destroyed, combat.Side.A, 0, 40
	balance_tally_add(&tally, won)

	sank := report_test_row(voyage.Zone.Deep, 3)
	sank.ending, sank.winner, sank.player_hull_end, sank.payout = .Destroyed, combat.Side.B, 0, 0
	balance_tally_add(&tally, sank)

	testing.expect_value(t, tally.all.destroyed, 2)
	testing.expect_value(t, tally.all.survived, 1)
	testing.expect_value(t, tally.all.wrecks, 1)
	testing.expect_value(t, tally.all.payout, 40)
	testing.expect_value(t, span_text(tally.all.payout_span), "40..40")
	// The comparison the section is for: what a Reward at those same stakes would have paid,
	// summed only over the battles that took a wreck.
	testing.expect_value(t, tally.all.reward, voyage.voyage_reward_cargo(voyage.Scaling_Site{zone = .Deep, depth = 3}))
}

@(test)
the_tally_counts_commit_by_the_battles_that_took_it_and_the_rounds_they_took :: proc(t: ^testing.T) {
	tally: Balance_Tally

	committed := report_test_row(voyage.Zone.Open_Sea, 0)
	committed.commit_rounds, committed.press = 3, ship.Phase.Fire
	balance_tally_add(&tally, committed)

	held := report_test_row(voyage.Zone.Open_Sea, 0)
	held.player_hull_end = 0
	balance_tally_add(&tally, held)

	testing.expect_value(t, tally.all.commit_fights, 1)
	testing.expect_value(t, tally.all.commit_rounds, 3)
	testing.expect_value(t, tally.all.commit_survived, 1)
	testing.expect_value(t, tally.all.press[.Fire], 1)
	testing.expect_value(t, tally.all.press[.Brace], 0)
}

@(test)
the_median_is_the_round_the_middle_battle_resolved_on :: proc(t: ^testing.T) {
	// The median beside the mean, because the hard cap is a long tail a handful of battles
	// reach and a mean carries that tail into every reading.
	tally: Balance_Tally
	for rounds in ([]int{2, 4, 4, 5, combat.HARD_ROUND_CAP}) {
		row := report_test_row(voyage.Zone.Coastal, 0)
		row.rounds = rounds
		balance_tally_add(&tally, row)
	}

	testing.expect_value(t, report_median_round(tally), 4)
}

@(test)
the_escape_gate_is_the_round_after_the_baseline_not_the_baseline :: proc(t: ^testing.T) {
	// combat_may_break_off refuses while `battle.round < BASELINE_ROUND_COUNT`, and that round
	// counts what has already resolved — so a battle that ended on the baseline round never had
	// an escape to reach, and only a longer one did.
	tally: Balance_Tally
	for rounds in ([]int{combat.BASELINE_ROUND_COUNT, combat.BASELINE_ROUND_COUNT + 1}) {
		row := report_test_row(voyage.Zone.Open_Sea, 0)
		row.rounds = rounds
		balance_tally_add(&tally, row)
	}

	text := headless_report(tally, Run_Request{seed = 1, runs = 2})

	testing.expect(t, strings.contains(text, "escape gate (round 6): 1 (50.0%)"))
}

@(test)
a_report_over_battles_that_took_no_wreck_prints_no_range_at_all :: proc(t: ^testing.T) {
	// A payout of 0 is a wreck that held nothing, which is not the same fact as no wreck — so
	// the low end of the span stays unset rather than reading as a payout of none.
	tally: Balance_Tally
	balance_tally_add(&tally, report_test_row(voyage.Zone.Coastal, 0)) // ends in a Break Off

	testing.expect_value(t, span_text(tally.all.payout_span), "")
	testing.expect(t, strings.contains(headless_report(tally, Run_Request{seed = 1, runs = 1}), "no wreck was taken"))
}

@(test)
the_report_prints_the_observed_swing_beside_the_budgets_own_anchor :: proc(t: ^testing.T) {
	// The whole point of the page: a divergence from the published rate is readable without
	// the reader doing arithmetic, so the anchor and the observed figures share it.
	tally: Balance_Tally
	row := report_test_row(voyage.Zone.Open_Sea, 1)
	row.rounds, row.player_hull_end = 5, 60
	balance_tally_add(&tally, row)

	text := headless_report(tally, Run_Request{seed = 4, runs = 2})

	testing.expect(t, strings.contains(text, "seeds 4..5"))
	testing.expect(t, strings.contains(text, "1 point = 1 magnitude of Fire = 5 hull of swing"))
	testing.expect(t, strings.contains(text, "hull/rd"))
	// 40 hull of swing over 5 rounds, printed as the mean and the rate off the same sums.
	testing.expect(t, strings.contains(text, "40.0"))
	testing.expect(t, strings.contains(text, "8.0"))
}

@(test)
the_report_answers_each_question_the_rows_were_collected_for :: proc(t: ^testing.T) {
	// One battle of each ending, so every section has something to say and none of them is
	// dividing by nothing.
	tally: Balance_Tally

	sunk := report_test_row(voyage.Zone.Coastal, 0)
	sunk.ending, sunk.winner, sunk.hostile_hull_end, sunk.payout = .Destroyed, combat.Side.A, 0, 25
	balance_tally_add(&tally, sunk)

	fled := report_test_row(voyage.Zone.Open_Sea, 1)
	fled.ending, fled.escaped, fled.commit_rounds = .Broke_Off, combat.Side.B, 2
	balance_tally_add(&tally, fled)

	stalled := report_test_row(voyage.Zone.Deep, 2)
	stalled.ending, stalled.rounds, stalled.press = .Round_Cap, combat.HARD_ROUND_CAP, ship.Phase.Brace
	balance_tally_add(&tally, stalled)

	text := headless_report(tally, Run_Request{seed = 1, runs = 3})

	testing.expect(t, strings.contains(text, "Fight length"))
	testing.expect(t, strings.contains(text, "Break Off"))
	testing.expect(t, strings.contains(text, "hostile 1, player 0"))
	testing.expect(t, strings.contains(text, "Press spent: 1"))
	testing.expect(t, strings.contains(text, "Commit taken in 1"))
	testing.expect(t, strings.contains(text, "Wrecks"))
	testing.expect(t, strings.contains(text, "range 25..25"))
}

@(test)
the_report_surfaces_both_recorded_count_peak_distortions :: proc(t: ^testing.T) {
	// The glossary records the two rather than fixing them, so the page has to say them out
	// loud: the structural tag peak the budget prices at, and the hostile's exposed slots an
	// opponent Count actually reads.
	tally: Balance_Tally
	balance_tally_add(&tally, report_test_row(voyage.Zone.Coastal, 0))

	text := headless_report(tally, Run_Request{seed = 1, runs = 1})
	peaks := ship.ship_count_peaks()
	structural_tag, structural := report_peak_tag(peaks)

	testing.expect(t, strings.contains(text, "Count peaks"))
	// Every tag prices at the whole layout, which is what "structural" means here.
	testing.expect_value(t, structural, ship.SHIP_MAX_SLOTS)
	testing.expect_value(t, peaks.tag[structural_tag], peaks.tag[.Cargo])
	// And what a real ship holds of one tag, and what a hostile shows of one, are both under it.
	_, held, _ := report_hostile_peak(nil)
	_, seen, _ := report_hostile_peak(ship.Visibility.Exposed)
	testing.expect(t, held < structural)
	testing.expect(t, seen <= peaks.visibility[.Exposed])
	testing.expect(t, strings.contains(text, "the hostiles that can be met"))
	testing.expect(t, strings.contains(text, "the hostiles that can be seen"))
}

@(test)
a_report_over_no_battles_says_so_rather_than_dividing_by_none :: proc(t: ^testing.T) {
	tally: Balance_Tally
	text := headless_report(tally, Run_Request{seed = 0, runs = 1})

	testing.expect(t, strings.contains(text, "0 fights"))
	testing.expect(t, strings.contains(text, "nothing to read"))
}

@(test)
a_sweep_tallies_every_fight_row_it_wrote :: proc(t: ^testing.T) {
	// The tally and the Fight file are two readings of one stream, so a report can be trusted
	// to be about the rows somebody else can open.
	rows, fights, tally, ok := sweep_test_texts(Run_Request{seed = 1, runs = 8}, "sweep-report.csv")
	if !testing.expect(t, ok, "the sweep could not be written and read back") {
		return
	}
	defer delete(rows)
	defer delete(fights)

	written := strings.count(strings.trim_right(fights, "\n"), "\n") // the header is not a row
	testing.expect_value(t, tally.all.fights, written)
	testing.expect(t, written > 0)
}

@(test)
a_report_is_refused_unless_the_rows_name_a_file_of_their_own :: proc(t: ^testing.T) {
	// The report takes stdout, so the voyage rows cannot still be sitting there.
	_, bare := headless_request({"--runs", "10", "--report"})
	testing.expect(t, !bare)

	_, valued := headless_request({"--out", "rows.csv", "--report=yes"}) // not this flag
	testing.expect(t, !valued)

	req, ok := headless_request({"--runs", "10", "--out", "rows.csv", "--report"})
	testing.expect(t, ok)
	testing.expect(t, req.report)
	testing.expect_value(t, req.runs, 10)

	quiet, quiet_ok := headless_request({"--runs", "10", "--out", "rows.csv"})
	testing.expect(t, quiet_ok)
	testing.expect(t, !quiet.report)
}

// report_test_row is a Fight row with every field a section reads set to something ordinary —
// a battle the player won on Hull and walked away from — so each test can move the one field
// it is about and leave the rest standing.
report_test_row :: proc(zone: voyage.Zone, depth: int) -> Fight_Row {
	return Fight_Row {
		seed = 1,
		fight = 1,
		zone = zone,
		depth = depth,
		archetype = "Reef Skimmer",
		rounds = 5,
		ending = .Broke_Off,
		player_hull_start = 100,
		player_hull_end = 100,
		hostile_hull_start = 100,
		hostile_hull_end = 100,
	}
}
