package main

import "core:fmt"
import "core:os"
import voyage "../../core/voyage"

// What a sweep writes (CONTEXT.md: Sweep, Voyage row) — the row format and the path from a
// seed range to a file that can be opened again.

// HEADLESS_ROW_HEADER names the columns in the order headless_row_line writes them. The two
// are one file format stated twice, held together by the test that reads a row of known
// fields back against this line.
HEADLESS_ROW_HEADER :: "seed,outcome,zone,nodes,hull,cargo,encounters,events"

// Voyage_Row is one ended voyage as a sweep records it. Every field is a plain value the
// Event stream carried, so a row outlives the Sim that produced it — nothing here borrows
// from the run-scoped arena (ADR-0010).
Voyage_Row :: struct {
	seed:       u64,
	status:     voyage.Voyage_Status,
	// The deepest zone reached, nil if none was — a landmark carries no zone.
	zone:       Maybe(voyage.Zone),
	// nodes counts arrivals, so the Start a voyage begins on is not one of them; hull and
	// cargo are the ship as the voyage left it.
	nodes:      int,
	hull:       int,
	cargo:      int,
	encounters: int,
	events:     int,
}

// headless_row_line is one row in HEADLESS_ROW_HEADER's column order. Nothing it writes can
// contain a comma — every field is a number or a name from the two tables below — so the
// line needs no CSV quoting. The string is temp_allocator scratch, consumed by the write
// that follows it.
headless_row_line :: proc(row: Voyage_Row) -> string {
	return fmt.tprintf(
		"%d,%s,%s,%d,%d,%d,%d,%d",
		row.seed,
		headless_outcome_name(row.status),
		headless_zone_name(row.zone),
		row.nodes,
		row.hull,
		row.cargo,
		row.encounters,
		row.events,
	)
}

// headless_outcome_name is how a voyage's end is spelled in the file. The names are written
// out rather than printed off the enum, so renaming a status inside the Sim cannot silently
// rename a column's values; the switch is exhaustive, so a new status is a compile error here
// rather than a blank cell in the file.
headless_outcome_name :: proc(status: voyage.Voyage_Status) -> string {
	switch status {
	case .Won:
		return "haven"
	case .Lost:
		return "sank"
	case .In_Progress:
		return "in_progress"
	}
	unreachable()
}

// headless_zone_name spells the zone reached, on the same rule as the outcome names above,
// and "none" for a voyage that reached no zoned node at all.
headless_zone_name :: proc(zone: Maybe(voyage.Zone)) -> string {
	reached, ok := zone.?
	if !ok {
		return "none"
	}
	switch reached {
	case .Coastal:
		return "coastal"
	case .Open_Sea:
		return "open_sea"
	case .Deep:
		return "deep"
	}
	unreachable()
}

// headless_open_destination opens where a sweep's rows go: the named path, created or
// truncated, or stdout when the request named none. A path that cannot be opened comes back
// not-ok, and the caller stops before a voyage runs — a thousand-voyage sweep that discovers
// at the end that it had nowhere to write is a sweep thrown away.
headless_open_destination :: proc(path: Maybe(string)) -> (out: ^os.File, ok: bool) {
	named := path.? or_else ""
	if named == "" {
		return os.stdout, true
	}
	file, err := os.open(named, {.Write, .Create, .Trunc})
	if err != nil {
		return nil, false
	}
	return file, true
}

// headless_sweep runs the request's voyages — consecutive seeds from req.seed, in order —
// writing the header and then one row per voyage to `out`, and the battles fought inside those
// voyages to `fights` when one was named. It returns false on the first write that fails, so a
// run that cannot write its rows can say so and exit non-zero.
//
// A row is written as its voyage ends rather than collected: the file grows with the sweep,
// and a thousand voyages hold one voyage's Sim, and one voyage's rows, at a time. The two
// files are written in the same seed order, so `seed` joins a Fight row back to the voyage it
// was fought in.
headless_sweep :: proc(req: Run_Request, out: ^os.File, fights: Maybe(^os.File)) -> (ok: bool) {
	// A sweep runs quiet, because a thousand printed voyages is a million lines; one voyage
	// prints its events, which is what watching a single run go by means.
	quiet := req.runs > 1

	fights_out, writing_fights := fights.?

	headless_write_line(out, HEADLESS_ROW_HEADER) or_return
	if writing_fights {
		headless_write_line(fights_out, HEADLESS_FIGHT_HEADER) or_return
	}

	for i in 0 ..< req.runs {
		// The rows' own formatting scratch; the Sim's is reclaimed inside run_session.
		defer free_all(context.temp_allocator)

		row, voyage_fights := headless_voyage(req.seed + u64(i), quiet)
		defer delete(voyage_fights)

		headless_write_line(out, headless_row_line(row)) or_return
		if writing_fights {
			for fight in voyage_fights {
				headless_write_line(fights_out, headless_fight_line(fight)) or_return
			}
		}
	}
	return true
}

// headless_write_line writes one line plus its terminator and reports whether the whole of
// it landed — a short write is as much a failure as an error.
headless_write_line :: proc(out: ^os.File, line: string) -> bool {
	terminated := fmt.tprintf("%s\n", line)
	written, err := os.write_string(out, terminated)
	return err == nil && written == len(terminated)
}
