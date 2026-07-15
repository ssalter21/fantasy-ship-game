package run

import "../ship"
import "../testutil"
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

@(test)
applying_a_stat_trade_returns_a_post_trade_snapshot :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20, max_hp = 20, durability = 2, speed = 5}
	trade := Encounter_Stat_Trade{gain_durability = 3, cost_speed = 1}
	site := Scaling_Site{zone = .Open_Sea, depth = 1}

	snapshot := run_apply_stat_trade(&s, trade, site, 4)

	testing.expect_value(t, snapshot.ship.durability, 5) // post-trade, not pre-trade
	testing.expect_value(t, snapshot.ship.hp, 20)
	testing.expect_value(t, snapshot.progress.steps, 4)
	// The node's own stakes, not the trade's gain_durability wearing a
	// difficulty's name (ADR-0014): a Trade's swing size is one reading of this
	// site, and the snapshot records the site it was read from.
	testing.expect_value(t, snapshot.progress.site, site)
}

@(test)
finishing_a_ship_battle_returns_a_snapshot_of_the_players_ship :: proc(t: ^testing.T) {
	player := ship.Ship{hp = 20, max_hp = 20, speed = 5}
	encounter := Encounter_Ship_Battle{depth = 2, opponent = ship.Ship{hp = 10, speed = 3}}
	battle := run_start_battle(&player, &encounter)
	battle.ended = true // stand in for a battle actually resolving to completion

	snapshot := run_finish_ship_battle(&battle, &player, &encounter, .Deep, 8)

	testing.expect_value(t, snapshot.ship.hp, 20) // player's own max_hp, not the opponent's
	testing.expect_value(t, snapshot.progress.steps, 8)
	// Stakes come from the node's own zone/depth, not off the battle-worn
	// opponent — the encounter's retained depth is what makes that possible.
	testing.expect_value(t, snapshot.progress.site, Scaling_Site{zone = .Deep, depth = 2})
}

@(test)
finishing_a_ship_battle_that_has_not_ended_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	player := ship.Ship{hp = 20, max_hp = 20, speed = 5}
	encounter := Encounter_Ship_Battle{opponent = ship.Ship{hp = 10, speed = 3}}
	battle := run_start_battle(&player, &encounter)

	testing.expect_assert(t, "run_finish_ship_battle called before the battle ended")
	run_finish_ship_battle(&battle, &player, &encounter, .Coastal, 0)
}
