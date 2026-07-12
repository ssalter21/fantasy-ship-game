package run

import "../ship"

// Ghost_Snapshot is a captured, decoupled copy of a ship's current state
// plus its run progress (ADR-0008): the single opponent-ship representation
// for both this slice's hand-authored PvE opponents and future real
// player-sourced ghosts. Additive — new fields can be added later without a
// model rework.
Ghost_Snapshot :: struct {
	ship:     ship.Ship,
	progress: Ghost_Progress,
}

// Ghost_Progress is a snapshot's run-progress half (ADR-0008). Not read by
// combat resolution — captured wholesale for future analytics/ghost-selection.
Ghost_Progress :: struct {
	steps:             int,
	zone:              Zone,
	difficulty_rating: int,
}

// run_ghost_snapshot_of assembles a Ghost_Snapshot describing ship s at the
// given run progress, without cloning: hp is reset to s.max_hp (ADR-0008: a
// ghost always starts at full health), but the returned snapshot's layout
// *aliases* s.layout rather than owning a copy. It is a borrowed description
// valid only as long as s and its layout are — a caller that must hand the
// snapshot out past s's lifetime (core/sim, via Event_Encounter_Resolved)
// deep-copies it onto its own allocator with run_ghost_snapshot_capture. The
// encounter-resolution procs return one of these so the Sim owns the single
// arena-backed capture (issue #82).
run_ghost_snapshot_of :: proc(s: ^ship.Ship, steps: int, zone: Zone, difficulty_rating: int) -> Ghost_Snapshot {
	snap_ship := s^
	snap_ship.hp = s.max_hp

	return Ghost_Snapshot{
		ship = snap_ship,
		progress = Ghost_Progress{steps = steps, zone = zone, difficulty_rating = difficulty_rating},
	}
}

// run_ghost_snapshot_capture builds a decoupled, owned Ghost_Snapshot from a
// real, in-progress ship (ADR-0008): like run_ghost_snapshot_of it resets hp
// to s.max_hp, but it also clones the layout (via context.allocator) so later
// mutation to the source ship (e.g. Jettison Cargo) can't leak into the
// snapshot. core/sim's Sim calls this with its own run-scoped arena active
// (issue #52), so the returned snapshot's layout lives as long as the Sim and
// is reclaimed wholesale by sim_destroy — a caller outside that context gets a
// snapshot allocated from whatever context.allocator is active at the call
// site, and owns it as normal.
run_ghost_snapshot_capture :: proc(s: ^ship.Ship, steps: int, zone: Zone, difficulty_rating: int) -> Ghost_Snapshot {
	snap := run_ghost_snapshot_of(s, steps, zone, difficulty_rating)

	layout := make([]ship.Layout_Slot, len(s.layout))
	copy(layout, s.layout)
	snap.ship.layout = layout

	return snap
}
