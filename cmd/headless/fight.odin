package main

import "core:fmt"
import combat "../../core/combat"
import ship "../../core/ship"
import voyage "../../core/voyage"

// What a sweep records about the battles inside a voyage (CONTEXT.md: Fight row) — the row
// format, and the collector that fills one off the Event stream.

// HEADLESS_FIGHT_HEADER names the columns in the order headless_fight_line writes them, the
// same one-format-stated-twice arrangement as HEADLESS_ROW_HEADER, held in step by the test
// that reads a row of known fields back against this line.
HEADLESS_FIGHT_HEADER :: "seed,fight,zone,depth,archetype,rounds,ending,winner,escaped,player_hull_start,player_hull_swing,hostile_hull_start,hostile_hull_swing,press,commit_rounds,payout"

// Fight_Row is one resolved battle as a sweep records it. Every field is a plain value or an
// authored static string, so a row outlives the Sim that produced it — nothing here borrows
// from the run-scoped arena (ADR-0010).
//
// `seed` and `fight` together key a row: `seed` joins it to the voyage row of the same sweep,
// and `fight` numbers the battles of that voyage from 1 in the order they were fought, so a
// voyage that fought three of them is three rows rather than one row three times.
//
// The hulls are kept as start-and-end and written as start-and-swing: the swing is what the
// budget is argued in, and the pool it came out of is what says whether the fight was close.
// A swing is signed — a battle spent bracing can end with more Hull than it opened with.
Fight_Row :: struct {
	seed:               u64,
	fight:              int,
	// The stakes the battle was fought at: the node's zone tier and its depth within it.
	zone:               voyage.Zone,
	depth:              int,
	archetype:          string, // the roster entry the hostile was built from
	// rounds is combat's own count at the battle's end, so a round spent breaking off counts
	// as the round it was.
	rounds:             int,
	// How the battle ended, nil for a battle that never did — a row closed by the voyage ending
	// mid-fight rather than by Event_Battle_Ended. Nil rather than a zero value, because the
	// zero End_Reason is Destroyed and an unfought battle must not read as a sinking.
	ending:             Maybe(combat.End_Reason),
	// winner at the round cap is combat's hull tiebreak rather than a kill, which is why the
	// two are separate columns: `ending` is what stops a stalemate reading as a win.
	winner:             Maybe(combat.Side),
	// The side that broke off, nil for a battle that ended any other way. Break Off ends the
	// battle for both ships and Event_Battle_Ended names no side, so this is the player's own
	// order where there was one and the hostile by elimination where there was not — which is
	// what makes the escape gate readable as a straddle rather than as a count.
	escaped:            Maybe(combat.Side),
	player_hull_start:  int,
	player_hull_end:    int,
	hostile_hull_start: int,
	hostile_hull_end:   int,
	// The phase this battle's one Press was spent on, nil if it was never spent, and the
	// number of rounds the player took Commit.
	press:              Maybe(ship.Phase),
	commit_rounds:      int,
	// What the wreck paid, gross. 0 is a battle that took no wreck *or* one whose wreck held
	// nothing — the Sim announces a payout only when there is one to announce.
	payout:             int,
}

// headless_fight_line is one row in HEADLESS_FIGHT_HEADER's column order. Every field is a
// number or a name from the tables below except `archetype`, which is authored content — the
// test that no roster name carries a comma is what lets the line go unquoted.
// The string is temp_allocator scratch, consumed by the write that follows it.
headless_fight_line :: proc(row: Fight_Row) -> string {
	return fmt.tprintf(
		"%d,%d,%s,%d,%s,%d,%s,%s,%s,%d,%d,%d,%d,%s,%d,%d",
		row.seed,
		row.fight,
		headless_zone_name(row.zone),
		row.depth,
		row.archetype,
		row.rounds,
		headless_ending_name(row.ending),
		headless_side_name(row.winner),
		headless_side_name(row.escaped),
		row.player_hull_start,
		row.player_hull_start - row.player_hull_end,
		row.hostile_hull_start,
		row.hostile_hull_start - row.hostile_hull_end,
		headless_press_name(row.press),
		row.commit_rounds,
		row.payout,
	)
}

// headless_ending_name spells how the battle ended, on the same rule as the voyage row's own
// names: written out rather than printed off the enum, so renaming an End_Reason inside
// core/combat cannot silently rename a column's values, and exhaustive, so a fourth way for a
// battle to end is a compile error here rather than a blank cell. "none" is the battle that
// never ended, which is a row to discard rather than a fourth ending to read.
headless_ending_name :: proc(reason_of: Maybe(combat.End_Reason)) -> string {
	reason, ended := reason_of.?
	if !ended {
		return "none"
	}
	switch reason {
	case .Destroyed:
		return "destroyed"
	case .Broke_Off:
		return "broke_off"
	case .Round_Cap:
		return "round_cap"
	}
	unreachable()
}

// headless_side_name names a side by which ship it is rather than which slot of the Battle:
// the player is always Side.A (voyage_start_battle). "none" is the absent side — a mutual
// sinking the speed tiebreak could not separate, or a battle nobody broke off from.
headless_side_name :: proc(side_of: Maybe(combat.Side)) -> string {
	side, decided := side_of.?
	if !decided {
		return "none"
	}
	switch side {
	case .A:
		return "player"
	case .B:
		return "hostile"
	}
	unreachable()
}

// headless_press_name names the phase the battle's one Press was spent on, or "none" for a
// battle that ended with it still in hand.
headless_press_name :: proc(press: Maybe(ship.Phase)) -> string {
	phase, spent := press.?
	if !spent {
		return "none"
	}
	switch phase {
	case .Brace:
		return "brace"
	case .Fire:
		return "fire"
	}
	unreachable()
}

// Fight_Log collects one voyage's Fight rows off the Event stream, and off the orders the
// Input_Source submits — a round's Press and Commit are the captain's own decisions, which
// the Sim broadcasts no Event for, so the half of a row that is *what the player did* is
// filled where the decision is made rather than where its consequences arrive.
//
// A row is `open` from the moment the battle is sighted until the *next* one is, because the
// wreck's payout arrives after the battle has already ended. Only one battle can be in flight
// at a time — a Fight stage parks the walk until its battle resolves — so one open row is
// enough, and fight_log_close is what moves it into `rows`.
//
// `seed` is the voyage the whole log is of, held once here rather than passed at each
// sighting. `rows` is ordinary heap: it outlives the Sim's run arena by construction (it is
// read after sim_destroy) and cannot ride context.temp_allocator, which run_session drains on
// every driver iteration. It is the caller's to delete.
Fight_Log :: struct {
	seed: u64,
	open: Maybe(Fight_Row),
	rows: [dynamic]Fight_Row,
}

// fight_log_sighted starts the row for a battle just joined, closing whatever came before it —
// which is also what numbers this one, the closed rows being every battle fought before it.
// `player_hull` is the ship's Hull as the sink last saw it (Event_Ship_Updated) and
// `hostile_hull` the opponent's as it was sighted, which are the two pools the swings come out
// of.
fight_log_sighted :: proc(
	log: ^Fight_Log,
	site: voyage.Scaling_Site,
	archetype: string,
	player_hull: int,
	hostile_hull: int,
) {
	fight_log_close(log)
	log.open = Fight_Row {
		seed               = log.seed,
		fight              = len(log.rows) + 1,
		zone               = site.zone,
		depth              = site.depth,
		archetype          = archetype,
		player_hull_start  = player_hull,
		player_hull_end    = player_hull,
		hostile_hull_start = hostile_hull,
		hostile_hull_end   = hostile_hull,
	}
}

// fight_log_battle_event reads a round's combat Events for the facts a row carries. Both hulls
// are taken from Event_Round_Resolved, which states them outright, rather than replayed from
// the round's repairs and damage; a round that resolved no phases (a Break Off) emits none,
// which is why the hulls start at the battle's own and are only ever overwritten.
// The switch is exhaustive, so a new combat Event is a decision made here rather than one
// silently dropped.
fight_log_battle_event :: proc(log: ^Fight_Log, event: combat.Event) {
	row, fighting := &log.open.?
	if !fighting {
		return
	}

	switch e in event {
	case combat.Event_Round_Resolved:
		row.player_hull_end = e.hull[.A]
		row.hostile_hull_end = e.hull[.B]
	case combat.Event_Battle_Ended:
		row.rounds = e.round
		row.ending = e.reason
		row.winner = e.winner
		// A Break Off the player did not order is the hostile's: the order goes in before the
		// round resolves (fight_log_order), so the player's own is already recorded by now.
		if e.reason == .Broke_Off && row.escaped == nil {
			row.escaped = combat.Side.B
		}
	case combat.Event_Hull_Repaired:
	case combat.Event_Damage_Dealt:
	case combat.Event_Ship_Sunk:
	case combat.Event_Cargo_Jettisoned:
	}
}

// fight_log_order records what the captain ordered this round. Press names the phase it was
// spent on and lands at most once — the Battle rations it (combat_may_press) — so the field
// is the phase rather than a count; Commit is unrationed, so it is counted; Break Off is the
// one order whose consequence names no side, so the row takes the side from the order itself.
// The switch is exhaustive: an order with nothing to record says so by an empty arm.
fight_log_order :: proc(log: ^Fight_Log, order: combat.Command) {
	row, fighting := &log.open.?
	if !fighting {
		return
	}

	switch c in order {
	case combat.Command_Press:
		row.press = c.phase
	case combat.Command_Commit:
		row.commit_rounds += 1
	case combat.Command_Break_Off:
		row.escaped = combat.Side.A
	case combat.Command_Jettison_Cargo:
	case combat.Command_Hold:
	}
}

// fight_log_payout records what the wreck of the battle just won paid out, gross.
fight_log_payout :: proc(log: ^Fight_Log, gross: int) {
	if row, fighting := &log.open.?; fighting {
		row.payout = gross
	}
}

// fight_log_close moves the open row into the collected ones. Called as the next battle is
// sighted and once more when the voyage ends, so the last battle of a voyage is recorded like
// every other.
fight_log_close :: proc(log: ^Fight_Log) {
	if row, fighting := log.open.?; fighting {
		append(&log.rows, row)
		log.open = nil
	}
}
