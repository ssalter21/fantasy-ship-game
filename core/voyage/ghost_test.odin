package voyage

import "../ship"
import "core:testing"

@(test)
capture_resets_hull_to_max_hull_regardless_of_current_hull :: proc(t: ^testing.T) {
	s := ship.Ship{hull = 3, max_hull = 20}

	snap := voyage_ghost_snapshot_capture(voyage_ghost_snapshot_of(&s, 0, Scaling_Site{zone = .Coastal, depth = 0}))
	defer delete(snap.ship.layout)

	testing.expect_value(t, snap.ship.hull, 20)
}

@(test)
capture_resets_hull_to_effective_max_hull_including_a_max_hull_fitting :: proc(t: ^testing.T) {
	ballast := ship.Fitting{
		name = "Ballast Tanks", size = .Small,
		passive = ship.Effect{kind = .Modify_Max_Hull, magnitude = 10},
	}
	s := ship.Ship{
		hull = 3, max_hull = 20,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = ballast}},
	}

	snap := voyage_ghost_snapshot_capture(voyage_ghost_snapshot_of(&s, 0, Scaling_Site{zone = .Coastal, depth = 0}))
	defer delete(snap.ship.layout)

	// Effective max Hull = raw 20 + the +Max_Hull fitting's 10 (issue #92).
	testing.expect_value(t, snap.ship.hull, 30)
}

@(test)
capture_clones_the_layout_so_later_mutation_to_the_source_ship_does_not_leak_into_the_snapshot :: proc(t: ^testing.T) {
	cargo := ship.Fitting{name = "Rations", is_cargo = true, stack_count = 1}
	s := ship.Ship{
		hull = 20, max_hull = 20,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = cargo}},
	}

	snap := voyage_ghost_snapshot_capture(voyage_ghost_snapshot_of(&s, 0, Scaling_Site{zone = .Coastal, depth = 0}))
	defer delete(snap.ship.layout)

	// Jettison Cargo empties the source ship's slot after capture (ADR-0006).
	s.layout[0].fitting = nil

	_, snapshot_still_has_fitting := snap.ship.layout[0].fitting.?
	testing.expect(t, snapshot_still_has_fitting)
}

@(test)
capture_carries_the_given_progress_fields_through_unchanged :: proc(t: ^testing.T) {
	s := ship.Ship{hull = 20, max_hull = 20}

	site := Scaling_Site{zone = .Open_Sea, depth = 2}
	snap := voyage_ghost_snapshot_capture(voyage_ghost_snapshot_of(&s, 7, site))
	defer delete(snap.ship.layout)

	testing.expect_value(t, snap.progress.steps, 7)
	testing.expect_value(t, snap.progress.site, site)
}

@(test)
capture_carries_the_ships_other_top_level_stats_through_unchanged :: proc(t: ^testing.T) {
	captain := ship.Captain{name = "Blackheart"}
	s := ship.Ship{
		hull = 5, max_hull = 20, speed = 7,
		captain = captain,
	}

	snap := voyage_ghost_snapshot_capture(voyage_ghost_snapshot_of(&s, 0, Scaling_Site{zone = .Coastal, depth = 0}))
	defer delete(snap.ship.layout)

	// A ship's cargo is no longer a scalar field (ADR-0020) — it rides in the
	// cloned layout, covered by the cargo-clone test above; the scalars that carry
	// through are max_hull, speed, and the captain.
	testing.expect_value(t, snap.ship.max_hull, 20)
	testing.expect_value(t, snap.ship.speed, 7)
	testing.expect_value(t, snap.ship.captain, Maybe(ship.Captain)(captain))
}

// No test here drives a stage's apply proc to get a snapshot out of it, because
// none of them return one any more (issue #162). A ghost is captured once per
// encounter, at the end of the node's walk, so "what does a resolved encounter's
// snapshot say" is core/sim's question and is asked there — this file is left with
// the capture itself: what voyage_ghost_snapshot_of describes and what
// voyage_ghost_snapshot_capture owns.
