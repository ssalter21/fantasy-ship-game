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

// Event is the only way a caller learns a Ghost_Snapshot was captured
// (mirrors ADR-0001's Command/Event boundary and core/combat's own Event
// union). Shaped as an open union so a future kind can be added without
// restructuring callers.
Event :: union {
	Event_Encounter_Resolved,
}

// Event_Encounter_Resolved is emitted after an encounter point resolves
// (ADR-0008: Ship Battle, Upgrade Offer, or Stat Trade — not port visits,
// which don't change ship state), carrying a fresh Ghost_Snapshot of the
// ship's state at that point.
Event_Encounter_Resolved :: struct {
	snapshot: Ghost_Snapshot,
}

// run_ghost_snapshot_capture builds a decoupled Ghost_Snapshot from a real,
// in-progress ship (ADR-0008): hp is always reset to s.max_hp regardless of
// the ship's current run-persistent hp, and the layout is cloned (via
// context.allocator) so later mutation to the source ship (e.g. Jettison
// Cargo) can't leak into the snapshot. core/sim's Sim calls this with its own
// run-scoped arena active (issue #52), so the returned snapshot's layout
// lives as long as the Sim and is reclaimed wholesale by sim_destroy — a
// caller outside that context gets a snapshot allocated from whatever
// context.allocator is active at the call site, and owns it as normal.
run_ghost_snapshot_capture :: proc(s: ^ship.Ship, steps: int, zone: Zone, difficulty_rating: int) -> Ghost_Snapshot {
	layout := make([]ship.Layout_Slot, len(s.layout))
	copy(layout, s.layout)

	snap_ship := s^
	snap_ship.hp = s.max_hp
	snap_ship.layout = layout

	return Ghost_Snapshot{
		ship = snap_ship,
		progress = Ghost_Progress{steps = steps, zone = zone, difficulty_rating = difficulty_rating},
	}
}
