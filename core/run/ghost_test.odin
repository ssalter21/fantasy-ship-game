package run

import "../ship"
import "core:testing"

@(test)
capture_resets_hp_to_max_hp_regardless_of_current_hp :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 3, max_hp = 20}

	snap := run_ghost_snapshot_capture(run_ghost_snapshot_of(&s, 0, Scaling_Site{zone = .Coastal, depth = 0}))
	defer delete(snap.ship.layout)

	testing.expect_value(t, snap.ship.hp, 20)
}

@(test)
capture_resets_hp_to_effective_max_hp_including_a_max_hp_fitting :: proc(t: ^testing.T) {
	ballast := ship.Fitting{
		name = "Ballast Tanks", size = .Small,
		passive = ship.Effect{kind = .Modify_Max_HP, magnitude = 10},
	}
	s := ship.Ship{
		hp = 3, max_hp = 20,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = ballast}},
	}

	snap := run_ghost_snapshot_capture(run_ghost_snapshot_of(&s, 0, Scaling_Site{zone = .Coastal, depth = 0}))
	defer delete(snap.ship.layout)

	// Effective max HP = raw 20 + the +Max_HP fitting's 10 (issue #92).
	testing.expect_value(t, snap.ship.hp, 30)
}

@(test)
capture_clones_the_layout_so_later_mutation_to_the_source_ship_does_not_leak_into_the_snapshot :: proc(t: ^testing.T) {
	cargo := ship.Fitting{name = "Rations", is_cargo = true, stack_count = 1}
	s := ship.Ship{
		hp = 20, max_hp = 20,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = cargo}},
	}

	snap := run_ghost_snapshot_capture(run_ghost_snapshot_of(&s, 0, Scaling_Site{zone = .Coastal, depth = 0}))
	defer delete(snap.ship.layout)

	// Jettison Cargo empties the source ship's slot after capture (ADR-0006).
	s.layout[0].fitting = nil

	_, snapshot_still_has_fitting := snap.ship.layout[0].fitting.?
	testing.expect(t, snapshot_still_has_fitting)
}

@(test)
capture_carries_the_given_progress_fields_through_unchanged :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20, max_hp = 20}

	site := Scaling_Site{zone = .Open_Sea, depth = 2}
	snap := run_ghost_snapshot_capture(run_ghost_snapshot_of(&s, 7, site))
	defer delete(snap.ship.layout)

	testing.expect_value(t, snap.progress.steps, 7)
	testing.expect_value(t, snap.progress.site, site)
}

@(test)
capture_carries_the_ships_other_top_level_stats_through_unchanged :: proc(t: ^testing.T) {
	captain := ship.Captain{name = "Blackheart"}
	s := ship.Ship{
		hp = 5, max_hp = 20, durability = 3, speed = 7,
		starting_treasure = 100, base_cargo_capacity = 4, captain = captain,
	}

	snap := run_ghost_snapshot_capture(run_ghost_snapshot_of(&s, 0, Scaling_Site{zone = .Coastal, depth = 0}))
	defer delete(snap.ship.layout)

	testing.expect_value(t, snap.ship.durability, 3)
	testing.expect_value(t, snap.ship.speed, 7)
	testing.expect_value(t, snap.ship.starting_treasure, 100)
	testing.expect_value(t, snap.ship.base_cargo_capacity, 4)
	testing.expect_value(t, snap.ship.captain, Maybe(ship.Captain)(captain))
}

// No test here drives a stage's apply proc to get a snapshot out of it, because
// none of them return one any more (issue #162). A ghost is captured once per
// encounter, at the end of the node's walk, so "what does a resolved encounter's
// snapshot say" is core/sim's question and is asked there — this file is left with
// the capture itself: what run_ghost_snapshot_of describes and what
// run_ghost_snapshot_capture owns.
