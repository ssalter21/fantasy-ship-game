package main

import "core:fmt"
import "core:strings"
import combat "../../core/combat"
import ship "../../core/ship"
import voyage "../../core/voyage"

// The balance report (CONTEXT.md: Balance report) — the swept Fight rows read back against
// the power budget's own anchor, so an authored rate can be checked against what battles
// actually do.
//
// **An instrument, not a gate.** Nothing here decides anything: it prints, it never fails a
// run, and no test in this package asserts a figure it produces is in any band. The budget's
// rates are authoring's to set and distinctness is judgement (CONTEXT.md, `roster_check`);
// what this adds is numbers to argue from.

// REPORT_HULL_PER_POINT is the budget's numeraire read as hull: one point is one magnitude of
// Fire is five hull of swing over the reference fight (ship.POINT). The reference fight is
// combat.BASELINE_ROUND_COUNT rounds at ship.STARTING_HULL, so one point is also one hull of
// swing per round — which is what lets an observed hull/round column be read as points.
REPORT_HULL_PER_POINT :: 5

// Fight_Tally is the sums a report is printed from, over whatever set of Fight rows was
// added to it. Sums rather than kept rows: a sweep of any length tallies in constant space,
// the same one-voyage-at-a-time discipline the sweep itself holds to, and every figure
// printed is a ratio of two of these.
//
// The swings are signed, because a Fight row's swing is (a battle spent bracing can end with
// more Hull than it opened with), and summing is what averages them honestly.
Fight_Tally :: struct {
	fights:          int,
	rounds:          int,
	player_swing:    int,
	hostile_swing:   int,
	// How the battles ended, and the side that broke off where one did.
	destroyed:       int,
	broke_off:       int,
	round_cap:       int,
	escaped:         [combat.Side]int,
	// What the captain spent: the Press by the phase it went on, and Commit as the battles
	// that took it at all beside the rounds they took it for.
	press:           [ship.Phase]int,
	commit_fights:   int,
	commit_rounds:   int,
	// Battles the player came out of alive, and how many of those had taken Commit.
	survived:        int,
	commit_survived: int,
	// The wrecks taken and what they paid, against what a Reward at the same stakes pays —
	// `reward` sums only over the battles that took a wreck, so the two are comparable.
	wrecks:          int,
	payout:          int,
	payout_low:      int,
	payout_high:     int,
	reward:          int,
}

// Balance_Tally is a whole sweep's battles: every one of them together, the same bucketed by
// the stakes it was fought at, and the lengths they ran to. Zone and depth are the two axes
// of a Scaling_Site, so the buckets are the stakes gradient itself rather than a grouping
// invented here.
Balance_Tally :: struct {
	all:       Fight_Tally,
	stakes:    [voyage.Zone][voyage.DEPTH_STEPS + 1]Fight_Tally,
	// Battles by the round they resolved on, which is what a median is read off. Indexed by
	// round, so index 0 is unused and combat's hard cap is the last entry a battle can land in.
	rounds_at: [combat.HARD_ROUND_CAP + 1]int,
}

// balance_tally_add folds one Fight row into the whole-sweep sums and into its stakes cell.
// A depth outside the normalized range (voyage_normalize_depth) is clamped rather than
// dropped: a row is evidence wherever it came from, and losing one silently is the one thing
// a report must not do.
balance_tally_add :: proc(tally: ^Balance_Tally, row: Fight_Row) {
	fight_tally_add(&tally.all, row)
	fight_tally_add(&tally.stakes[row.zone][clamp(row.depth, 0, voyage.DEPTH_STEPS)], row)
	tally.rounds_at[clamp(row.rounds, 0, combat.HARD_ROUND_CAP)] += 1
}

// fight_tally_add folds one Fight row into one set of sums. Survival is read off the Hull the
// battle left the player on rather than off the winner, because the round cap awards a winner
// on Hull alone and a hostile that broke off leaves nobody a winner at all.
fight_tally_add :: proc(tally: ^Fight_Tally, row: Fight_Row) {
	tally.fights += 1
	tally.rounds += row.rounds
	tally.player_swing += row.player_hull_start - row.player_hull_end
	tally.hostile_swing += row.hostile_hull_start - row.hostile_hull_end

	switch row.ending {
	case .Destroyed:
		tally.destroyed += 1
	case .Broke_Off:
		tally.broke_off += 1
	case .Round_Cap:
		tally.round_cap += 1
	}
	if side, ran := row.escaped.?; ran {
		tally.escaped[side] += 1
	}

	if phase, spent := row.press.?; spent {
		tally.press[phase] += 1
	}
	if row.commit_rounds > 0 {
		tally.commit_fights += 1
		tally.commit_rounds += row.commit_rounds
	}

	survived := row.player_hull_end > 0
	if survived {
		tally.survived += 1
		if row.commit_rounds > 0 {
			tally.commit_survived += 1
		}
	}

	// A payout arrives only where a wreck was taken, and a wreck that held nothing pays 0 —
	// so the wreck count is the battles the player won by sinking its opponent, not the
	// battles that paid.
	if row.ending == .Destroyed && survived {
		tally.wrecks += 1
		tally.payout += row.payout
		tally.payout_low = tally.wrecks == 1 ? row.payout : min(tally.payout_low, row.payout)
		tally.payout_high = max(tally.payout_high, row.payout)
		tally.reward += voyage.voyage_reward_cargo(voyage.Scaling_Site{zone = row.zone, depth = row.depth})
	}
}

// headless_report is the whole report as one page of text, ready to be written in a single
// call. Assembled into a string rather than printed line by line so the same text a reader
// sees is the text a test reads, and so a report is one write rather than forty.
// The string is temp_allocator scratch, consumed by the write that follows it.
headless_report :: proc(tally: Balance_Tally, req: Run_Request) -> string {
	b := strings.builder_make(context.temp_allocator)

	fmt.sbprintfln(
		&b,
		"Balance report - %d fights over seeds %d..%d",
		tally.all.fights,
		req.seed,
		req.seed + u64(req.runs) - 1,
	)
	if tally.all.fights == 0 {
		fmt.sbprintln(&b, "No battle was fought, so there is nothing to read.")
		return strings.to_string(b)
	}

	report_anchor(&b)
	report_swing(&b, tally)
	report_length(&b, tally)
	report_break_off(&b, tally.all)
	report_orders(&b, tally.all)
	report_wrecks(&b, tally.all)
	report_count_peaks(&b)
	return strings.to_string(b)
}

// report_anchor states the rate every figure below is read against, so the divergences are
// readable off the page without arithmetic.
report_anchor :: proc(b: ^strings.Builder) {
	fmt.sbprintfln(
		b,
		"\nThe budget's anchor: 1 point = 1 magnitude of Fire = %d hull of swing over the\nreference fight (%s, %d rounds, %d hull). Over those rounds that is one\nhull of swing a round, so the hull/rd columns read off as points of Fire.",
		REPORT_HULL_PER_POINT,
		headless_zone_name(voyage.Zone.Open_Sea),
		combat.BASELINE_ROUND_COUNT,
		ship.STARTING_HULL,
	)
}

// report_swing is the observed Hull swing per round, per zone and per depth band within it —
// the two axes a Scaling_Site scales a hostile along, kept apart rather than averaged into
// one number, since a report that averaged them could not say where a rate diverges.
report_swing :: proc(b: ^strings.Builder, tally: Balance_Tally) {
	fmt.sbprintln(b, "\nHull swing, by the stakes it was fought at")
	// The spanner over the two swing pairs is the one line hand-aligned to the widths
	// report_swing_row holds every other line to.
	fmt.sbprintln(b, "                                   player swing     hostile swing")
	report_swing_row(b, "zone", "depth", "fights", "rounds", "hull", "hull/rd", "hull", "hull/rd")
	for zone in voyage.Zone {
		for depth in 0 ..= voyage.DEPTH_STEPS {
			cell := tally.stakes[zone][depth]
			if cell.fights == 0 {
				continue
			}
			report_swing_cell(b, headless_zone_name(zone), report_count(depth), cell)
		}
	}
	report_swing_cell(b, "all", "-", tally.all)
}

// report_swing_cell is one line of the swing table: the mean swing each side took over a
// battle, and that swing per round beside it. Per round is the length-normalized reading —
// a fight that ran twice as long should not read as twice the power — and the per-round
// figures are ratios of the sums rather than means of per-battle ratios, so a long battle
// weighs what it actually was.
report_swing_cell :: proc(b: ^strings.Builder, zone: string, depth: string, cell: Fight_Tally) {
	report_swing_row(
		b,
		zone,
		depth,
		report_count(cell.fights),
		report_figure(report_mean(cell.rounds, cell.fights)),
		report_figure(report_mean(cell.player_swing, cell.fights)),
		report_figure(report_mean(cell.player_swing, cell.rounds)),
		report_figure(report_mean(cell.hostile_swing, cell.fights)),
		report_figure(report_mean(cell.hostile_swing, cell.rounds)),
	)
}

// report_swing_row lays the swing table's columns out, and is where the header and every
// figure line agree on their widths by going through the same format. Every column is taken
// as text: `fmt` pads a number to a width with zeros rather than spaces, so a table's figures
// are formatted first and aligned as the strings they have become.
report_swing_row :: proc(b: ^strings.Builder, zone, depth, fights, rounds, player, player_rate, hostile, hostile_rate: string) {
	fmt.sbprintfln(
		b,
		"  %-9s %5s %7s %7s   %7s %8s   %7s %8s",
		zone,
		depth,
		fights,
		rounds,
		player,
		player_rate,
		hostile,
		hostile_rate,
	)
}

// report_length is how long battles actually run against the baseline the budget prices
// against — the same round count that opens the escape gate (combat_may_break_off), so
// reaching it is both "the reference fight's length" and "the round a straddle can be read".
report_length :: proc(b: ^strings.Builder, tally: Balance_Tally) {
	all := tally.all
	reached_gate := 0
	for count, round in tally.rounds_at {
		if round >= combat.BASELINE_ROUND_COUNT {
			reached_gate += count
		}
	}

	fmt.sbprintfln(b, "\nFight length - the reference fight is %d rounds", combat.BASELINE_ROUND_COUNT)
	fmt.sbprintfln(
		b,
		"  median %d   mean %s   reached the escape gate (round %d): %s",
		report_median_round(tally),
		report_figure(report_mean(all.rounds, all.fights)),
		combat.BASELINE_ROUND_COUNT,
		report_share(reached_gate, all.fights),
	)
	fmt.sbprintfln(b, "  ran to the hard cap of %d rounds: %s", combat.HARD_ROUND_CAP, report_share(all.round_cap, all.fights))
}

// report_break_off is the straddle in practice: how often a battle was left rather than
// fought out, and by whom. Only the strictly faster ship may break off, and the player's
// Speed is read off a hold that fills and empties all voyage — so which side reaches the gate
// is the joint (roster, cargo) property the pinned straddle test can only assert at a point.
report_break_off :: proc(b: ^strings.Builder, all: Fight_Tally) {
	fmt.sbprintln(b, "\nBreak Off - the straddle in practice, at every cargo a voyage passes through")
	fmt.sbprintfln(
		b,
		"  broke off: %s - hostile %d, player %d",
		report_share(all.broke_off, all.fights),
		all.escaped[.B],
		all.escaped[.A],
	)
	fmt.sbprintfln(b, "  fought to a sinking: %s   stalemated at the cap: %s", report_share(all.destroyed, all.fights), report_share(all.round_cap, all.fights))
}

// report_orders is what the captain spent: the Press, rationed one to a battle, and Commit,
// which is unrationed and forfeits the round's Fire. The survival lines are the question
// Commit exists to answer — whether the round it buys is a round the ship lives through —
// put beside the rate across every battle so the two can be read against each other.
report_orders :: proc(b: ^strings.Builder, all: Fight_Tally) {
	press := all.press[.Fire] + all.press[.Brace]

	fmt.sbprintln(b, "\nOrders")
	fmt.sbprintfln(b, "  Press spent: %s - fire %d, brace %d", report_share(press, all.fights), all.press[.Fire], all.press[.Brace])
	fmt.sbprintfln(
		b,
		"  Commit taken in %s, for %s rounds where it was taken at all",
		report_share(all.commit_fights, all.fights),
		report_figure(report_mean(all.commit_rounds, all.commit_fights)),
	)
	fmt.sbprintfln(b, "  the player survived %s of all battles", report_share(all.survived, all.fights))
	fmt.sbprintfln(b, "  and %s of the battles that took Commit", report_share(all.commit_survived, all.commit_fights))
}

// report_wrecks is what a won battle pays, against the Reward primitive's payout at the same
// stakes — the comparison the two constants were authored to make: a Reward is usually earned
// by a risking stage, and a Fight risks the whole voyage.
report_wrecks :: proc(b: ^strings.Builder, all: Fight_Tally) {
	fmt.sbprintln(b, "\nWrecks - against a Reward at the same stakes")
	fmt.sbprintfln(
		b,
		"  wrecks taken: %s   mean %s   range %d..%d",
		report_share(all.wrecks, all.fights),
		report_figure(report_mean(all.payout, all.wrecks)),
		all.payout_low,
		all.payout_high,
	)
	fmt.sbprintfln(b, "  a Reward at those same stakes pays a mean of %s", report_figure(report_mean(all.reward, all.wrecks)))
}

// report_count_peaks surfaces the two count-peak distortions the glossary records rather than
// letting the figures above stand as if counting items were priced against what a battle
// holds. Neither is corrected here: the report is an instrument, and both are decisions that
// belong to the budget.
//
// Read off the authored content rather than off the sweep, because the ceiling a Count is
// priced at is a property of the template and the roster: every archetype is drawn with no
// regard to zone, so every one of them is what any battle may meet.
report_count_peaks :: proc(b: ^strings.Builder) {
	priced := ship.ship_count_peaks()
	_, structural := report_peak_tag(priced)

	player := ship.ship_template_layout()
	defer delete(player)
	assert(
		ship.ship_fit_starting_loadout(player, ship.STARTING_CARGO + ship.CAPTAIN_STARTING_CARGO),
		"the starting loadout no longer fits the ship template",
	)
	player_tag, player_peak := report_peak_tag(ship.ship_count_table(player))
	held_tag, held_peak, held_by := report_hostile_peak(nil)
	seen_tag, seen_peak, seen_on := report_hostile_peak(ship.Visibility.Exposed)

	fmt.sbprintln(b, "\nCount peaks - two recorded distortions, surfaced and not corrected")
	fmt.sbprintfln(
		b,
		"  Every tag prices at the structural peak of %d: all %d slots carrying it at once.",
		structural,
		len(player),
	)
	fmt.sbprintfln(b, "    the player's starting loadout   %v %d", player_tag, player_peak)
	fmt.sbprintfln(b, "    the hostiles that can be met    %v %d (%s)", held_tag, held_peak, held_by)
	fmt.sbprintfln(
		b,
		"  An opponent Count prices at that same %d but reads a scouting report: %d slots.",
		structural,
		priced.visibility[.Exposed],
	)
	fmt.sbprintfln(b, "    the hostiles that can be seen   %v %d (%s)", seen_tag, seen_peak, seen_on)
}

// report_hostile_peak is the highest any one Tag reaches over the whole hostile roster, and
// the archetype that reaches it, counted the way a Count would count it: over the archetype's
// whole layout, or over its exposed slots alone when `seen_as` names the scouting report's
// filter.
report_hostile_peak :: proc(seen_as: Maybe(ship.Visibility)) -> (tag: ship.Tag, peak: int, archetype: string) {
	for entry in voyage.voyage_hostile_roster() {
		layout := report_hostile_layout(entry)
		defer delete(layout)

		if held, count := report_peak_tag(ship.ship_count_table(layout, seen_as)); count > peak {
			tag, peak, archetype = held, count, entry.name
		}
	}
	return tag, peak, archetype
}

// report_hostile_layout builds an archetype onto the ship template exactly as a Fight stages
// it. The site's power reading scales what a fitting outputs and never which slot it lands
// in, so the census is the same at every site and this passes the authored weight.
// Caller owns the returned slice.
report_hostile_layout :: proc(archetype: voyage.Hostile_Archetype) -> []ship.Layout_Slot {
	layout := ship.ship_template_layout()
	assert(
		voyage.voyage_fit_hostile_loadout(layout, archetype, 100),
		"a hostile archetype's loadout no longer fits the ship template",
	)
	return layout
}

// report_peak_tag is the most any one Tag reaches on a census, with the tag that reached it —
// the realistic peak a structural one is read against.
report_peak_tag :: proc(counts: ship.Count_Table) -> (tag: ship.Tag, peak: int) {
	for count, of in counts.tag {
		if count > peak {
			tag, peak = of, count
		}
	}
	return tag, peak
}

// report_median_round is the round the middle battle of the sweep resolved on, read off the
// length histogram. The median rather than the mean alone, because the round cap is a long
// tail a handful of battles reach and a mean carries that tail into every reading.
report_median_round :: proc(tally: Balance_Tally) -> int {
	seen := 0
	for count, round in tally.rounds_at {
		if seen += count; seen * 2 >= tally.all.fights {
			return round
		}
	}
	return 0
}

// report_mean is a sum over a count, and 0 over nothing — an empty cell prints a zero rather
// than dividing by one.
report_mean :: proc(sum: int, count: int) -> f64 {
	return count == 0 ? 0 : f64(sum) / f64(count)
}

// report_figure and report_count are the report's two number formats — a mean to one decimal,
// and a plain count. Both come back as text, because a column is aligned as a string here:
// given a width, `fmt` pads a number with zeros and a string with spaces.
// The strings are temp_allocator scratch, consumed by the line being built around them.
report_figure :: proc(value: f64) -> string {
	return fmt.tprintf("%.1f", value)
}

report_count :: proc(value: int) -> string {
	return fmt.tprintf("%d", value)
}

// report_share is a count printed beside what share of the whole it is, the shape every
// frequency in this report is read in. The string is temp_allocator scratch, consumed by the
// line being built around it.
report_share :: proc(part: int, whole: int) -> string {
	return fmt.tprintf("%d (%.1f%%)", part, whole == 0 ? 0 : 100 * f64(part) / f64(whole))
}
