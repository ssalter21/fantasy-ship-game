package voyage

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
//
// site is the node's stakes: where it sat on the gradient (ADR-0014). It
// replaces ADR-0008's difficulty_rating, which was a misnomer — a Stat Trade has
// no difficulty, so voyage_apply_stat_trade had to shove its gain_durability into
// the field to have anything to say. Stakes is the concept that survives, and
// Scaling_Site is what expresses it, so the snapshot carries the site itself
// rather than one primitive's reading of it: the reading is recoverable
// (voyage_fight_opponent_hull(site) and friends), a bare int isn't, and no primitive
// has to lie about which number it owns. Scaling_Site carries the zone, so the
// old separate zone field is subsumed rather than duplicated.
Ghost_Progress :: struct {
	steps: int,
	site:  Scaling_Site,
}

// voyage_ghost_snapshot_of assembles a Ghost_Snapshot describing ship s at the
// given run progress, without cloning: hull is reset to s's effective max Hull
// (ADR-0008: a ghost always starts at full health; issue #92: effective, so a
// +Max_Hull fitting counts), but the returned snapshot's layout
// *aliases* s.layout rather than owning a copy. It is a borrowed description
// valid only as long as s and its layout are — a caller that must hand the
// snapshot out past s's lifetime (core/sim, via Event_Encounter_Resolved)
// owns it with voyage_ghost_snapshot_capture.
//
// One caller: core/sim's sim_emit_encounter_resolved, which pairs it with the
// capture immediately (issue #82's borrowed-vs-owned handoff, now in one place).
// No stage-apply proc in this package returns a snapshot — a ghost is captured
// once per encounter, at the end of the node's walk, not per stage that changes
// the ship (issue #162, ADR-0008 as amended; see encounter.odin's header).
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
// layout via context.allocator so later mutation to the source ship (e.g.
// Jettison Cargo) can't leak into the snapshot. core/sim's Sim calls this with
// its own run-scoped arena active (issue #52), so the returned snapshot's
// layout lives as long as the Sim and is reclaimed wholesale by sim_destroy — a
// caller outside that context gets a snapshot allocated from whatever
// context.allocator is active at the call site, and owns it as normal.
voyage_ghost_snapshot_capture :: proc(snap: Ghost_Snapshot) -> Ghost_Snapshot {
	layout := make([]ship.Layout_Slot, len(snap.ship.layout))
	copy(layout, snap.ship.layout)

	owned := snap
	owned.ship.layout = layout
	return owned
}
