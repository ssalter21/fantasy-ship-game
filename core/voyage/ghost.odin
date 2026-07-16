package voyage

import "../ship"

// Ghost_Snapshot is a captured, decoupled copy of a ship's state plus its run
// progress (ADR-0008): the single opponent-ship representation for both authored
// PvE opponents and player-sourced ghosts.
Ghost_Snapshot :: struct {
	ship:     ship.Ship,
	progress: Ghost_Progress,
}

// Ghost_Progress is a snapshot's run-progress half (ADR-0008). Not read by
// combat resolution — captured wholesale for future analytics/ghost-selection.
//
// site is the node's stakes: where it sat on the gradient (ADR-0014). The
// snapshot carries the whole Scaling_Site rather than a single reading, so any
// reading stays recoverable (voyage_fight_opponent_hull(site) and friends).
Ghost_Progress :: struct {
	steps: int,
	site:  Scaling_Site,
}

// voyage_ghost_snapshot_of assembles a Ghost_Snapshot describing ship s at the
// given run progress without cloning: hull is reset to s's effective max Hull
// (ADR-0008: a ghost starts at full health; effective so a +Max_Hull fitting
// counts), but the snapshot's layout *aliases* s.layout rather than owning a
// copy. It is a borrowed description valid only as long as s and its layout are;
// a caller that must hand it out past s's lifetime (core/sim, via
// Event_Encounter_Resolved) owns it with voyage_ghost_snapshot_capture.
//
// A ghost is captured once per encounter, at the end of the node's walk — no
// stage-apply proc returns a snapshot (ADR-0008 as amended; see encounter.odin).
voyage_ghost_snapshot_of :: proc(s: ^ship.Ship, steps: int, site: Scaling_Site) -> Ghost_Snapshot {
	snap_ship := s^
	snap_ship.hull = ship.ship_effective_max_hull(s)

	return Ghost_Snapshot{
		ship = snap_ship,
		progress = Ghost_Progress{steps = steps, site = site},
	}
}

// voyage_ghost_snapshot_capture turns a borrowed-layout snapshot (from
// voyage_ghost_snapshot_of) into a decoupled, owned one (ADR-0008): it clones the
// layout via context.allocator so later mutation of the source ship (e.g.
// Jettison Cargo) can't leak into the snapshot. core/sim calls this with its
// run-scoped arena active, so the layout lives as long as the Sim and is
// reclaimed by sim_destroy; any other caller owns it under whatever
// context.allocator was active at the call site.
voyage_ghost_snapshot_capture :: proc(snap: Ghost_Snapshot) -> Ghost_Snapshot {
	layout := make([]ship.Layout_Slot, len(snap.ship.layout))
	copy(layout, snap.ship.layout)

	owned := snap
	owned.ship.layout = layout
	return owned
}
