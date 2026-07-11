package run

import "../combat"
import "../ship"
import "core:testing"

// encounter_kind_of classifies e as its Encounter_Kind so the assertions
// below don't each repeat a type-switch over Encounter's variants. Kept
// local to tests rather than exported from run.odin: nothing in production
// code needs the reverse Encounter -> Encounter_Kind mapping yet (run_map_create
// only ever builds Encounter values forward from a known Encounter_Kind).
encounter_kind_of :: proc(e: Encounter) -> Encounter_Kind {
	switch _ in e {
	case Encounter_Ship_Battle:
		return .Ship_Battle
	case Encounter_Upgrade_Offer:
		return .Upgrade_Offer
	case Encounter_Stat_Trade:
		return .Stat_Trade
	}
	unreachable()
}

// expect_harder_in_deeper_zone and expect_harder_nearer_port share the
// assertion body behind every "rises with zone/port_closeness" test below,
// which otherwise differ only in which zone-scaled proc is under test.
expect_harder_in_deeper_zone :: proc(t: ^testing.T, f: proc(Zone, int) -> int) {
	testing.expect(t, f(.Deep, 0) > f(.Coastal, 0))
}

expect_harder_nearer_port :: proc(t: ^testing.T, f: proc(Zone, int) -> int) {
	testing.expect(t, f(.Open_Sea, 3) > f(.Open_Sea, 0))
}

expect_rises_by_zone :: proc(t: ^testing.T, f: proc(Zone) -> int) {
	testing.expect(t, f(.Open_Sea) > f(.Coastal))
	testing.expect(t, f(.Deep) > f(.Open_Sea))
}

@(test)
same_port_closeness_is_harder_in_a_deeper_zone :: proc(t: ^testing.T) {
	expect_harder_in_deeper_zone(t, run_ship_battle_difficulty)
}

@(test)
a_ship_battle_point_nearer_its_zones_port_is_harder_than_one_farther_away :: proc(t: ^testing.T) {
	expect_harder_nearer_port(t, run_ship_battle_difficulty)
}

@(test)
opponent_durability_is_higher_in_a_deeper_zone_at_the_same_port_closeness :: proc(t: ^testing.T) {
	expect_harder_in_deeper_zone(t, run_ship_battle_opponent_durability)
}

@(test)
opponent_durability_is_higher_nearer_the_zones_port :: proc(t: ^testing.T) {
	expect_harder_nearer_port(t, run_ship_battle_opponent_durability)
}

@(test)
run_make_opponent_ship_sets_both_hp_and_durability_from_zone_and_port_closeness :: proc(t: ^testing.T) {
	opponent := run_make_opponent_ship(.Deep, 2)

	testing.expect_value(t, opponent.hp, run_ship_battle_difficulty(.Deep, 2))
	testing.expect_value(t, opponent.durability, run_ship_battle_opponent_durability(.Deep, 2))
}

@(test)
upgrade_offer_quality_rises_by_zone :: proc(t: ^testing.T) {
	expect_rises_by_zone(t, run_upgrade_offer_quality)
}

@(test)
stat_trade_gain_durability_rises_by_zone :: proc(t: ^testing.T) {
	expect_rises_by_zone(t, run_stat_trade_gain_durability)
}

@(test)
stat_trade_cost_speed_rises_by_zone :: proc(t: ^testing.T) {
	expect_rises_by_zone(t, run_stat_trade_cost_speed)
}

@(test)
the_three_zone_scaled_encounter_kinds_land_on_distinguishable_magnitudes :: proc(t: ^testing.T) {
	testing.expect(t, run_ship_battle_difficulty(.Coastal, 0) != run_upgrade_offer_quality(.Coastal))
	testing.expect(t, run_ship_battle_difficulty(.Coastal, 0) != run_stat_trade_gain_durability(.Coastal))
	testing.expect(t, run_upgrade_offer_quality(.Coastal) != run_stat_trade_gain_durability(.Coastal))
}

@(test)
run_point_is_port_is_true_for_start_and_zone_ports_but_not_encounter_or_goal :: proc(t: ^testing.T) {
	testing.expect(t, run_point_is_port(Point{kind = .Start}))
	testing.expect(t, run_point_is_port(Point{kind = .Port}))
	testing.expect(t, !run_point_is_port(Point{kind = .Encounter}))
	testing.expect(t, !run_point_is_port(Point{kind = .Goal}))
}

@(test)
run_map_create_has_start_three_zones_of_a_port_and_four_encounters_and_a_goal :: proc(t: ^testing.T) {
	m := run_map_create()
	defer run_map_destroy(&m)

	// 1 Start + 3 zones * (1 Port + 4 Encounter) + 1 Goal = 17.
	testing.expect_value(t, len(m.points), 17)
}

@(test)
run_map_create_splits_the_twelve_encounter_points_evenly_across_the_three_kinds :: proc(t: ^testing.T) {
	m := run_map_create()
	defer run_map_destroy(&m)

	counts: [Encounter_Kind]int
	for point in m.points {
		encounter, has_encounter := point.encounter.?
		if !has_encounter {
			continue
		}
		counts[encounter_kind_of(encounter)] += 1
	}

	testing.expect_value(t, counts[.Ship_Battle], 4)
	testing.expect_value(t, counts[.Upgrade_Offer], 4)
	testing.expect_value(t, counts[.Stat_Trade], 4)
}

@(test)
each_zone_has_exactly_one_port_and_a_mix_of_encounter_kinds_not_one_kind_dominating :: proc(t: ^testing.T) {
	m := run_map_create()
	defer run_map_destroy(&m)

	for zone in Zone {
		port_count := 0
		// kinds_seen is a genuine set-of-enum over Encounter_Kind (issue #54):
		// bit_set instead of a map[Encounter_Kind]bool, so there's no
		// allocation to defer-delete either.
		kinds_seen: bit_set[Encounter_Kind]

		for point in m.points {
			point_zone, in_a_zone := point.zone.?
			if !in_a_zone || point_zone != zone {
				continue
			}
			if point.kind == .Port {
				port_count += 1
			}
			if encounter, has_encounter := point.encounter.?; has_encounter {
				kinds_seen += {encounter_kind_of(encounter)}
			}
		}

		testing.expect_value(t, port_count, 1)
		testing.expect(t, card(kinds_seen) > 1)
	}
}

@(test)
in_the_map_the_ship_battle_point_nearer_its_zones_port_has_the_harder_opponent :: proc(t: ^testing.T) {
	m := run_map_create()
	defer run_map_destroy(&m)

	// Coastal is hand-placed with two Ship Battle points (zone_encounter_kinds);
	// they appear in map order nearest-port-first, so the earlier one should
	// be tuned harder.
	battles: [dynamic]Encounter_Ship_Battle
	defer delete(battles)
	for point in m.points {
		zone, in_a_zone := point.zone.?
		if !in_a_zone || zone != .Coastal {
			continue
		}
		if encounter, has_encounter := point.encounter.?; has_encounter {
			if battle, ok := encounter.(Encounter_Ship_Battle); ok {
				append(&battles, battle)
			}
		}
	}

	testing.expect_value(t, len(battles), 2)
	testing.expect(t, battles[0].opponent.hp > battles[1].opponent.hp)
}

@(test)
run_map_create_has_exactly_one_start_and_one_goal_neither_belonging_to_a_zone :: proc(t: ^testing.T) {
	m := run_map_create()
	defer run_map_destroy(&m)

	start_count, goal_count := 0, 0
	for point in m.points {
		if point.kind == .Start {
			start_count += 1
			_, has_zone := point.zone.?
			testing.expect(t, !has_zone)
		}
		if point.kind == .Goal {
			goal_count += 1
			_, has_zone := point.zone.?
			testing.expect(t, !has_zone)
		}
	}

	testing.expect_value(t, start_count, 1)
	testing.expect_value(t, goal_count, 1)
}

@(test)
run_start_battle_hands_off_to_combat_with_the_ship_and_the_encounters_opponent :: proc(t: ^testing.T) {
	player := ship.Ship{hp = 20, speed = 5}
	encounter := Encounter_Ship_Battle{opponent = ship.Ship{hp = 10, speed = 3}}

	battle := run_start_battle(&player, &encounter)

	testing.expect_value(t, battle.ships[.A], &player)
	testing.expect_value(t, battle.ships[.B], &encounter.opponent)

	// Confirm the returned Battle is a real, playable combat.Battle by
	// resolving a round through core/combat's own resolver.
	events: [dynamic]combat.Event
	defer delete(events)
	cmds: [combat.Side]Maybe(combat.Command)
	combat.combat_resolve_round(&battle, cmds, &events)
	testing.expect_value(t, battle.round, 1)
}

@(test)
run_apply_stat_trade_permanently_gains_durability_and_costs_speed :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20, durability = 2, speed = 5}
	trade := Encounter_Stat_Trade{gain_durability = 3, cost_speed = 1}

	events: [dynamic]Event
	defer delete(events)
	run_apply_stat_trade(&s, trade, .Coastal, 0, &events)
	defer delete(events[0].(Event_Encounter_Resolved).snapshot.ship.layout)

	testing.expect_value(t, s.durability, 5)
	testing.expect_value(t, s.speed, 4)
}

@(test)
run_status_is_won_when_the_ship_reaches_goal_with_positive_hp :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 1}
	goal := Point{kind = .Goal}

	testing.expect_value(t, run_status(&s, goal), Run_Status.Won)
}

@(test)
run_status_is_lost_when_hp_reaches_zero_even_at_the_goal :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 0}
	goal := Point{kind = .Goal}

	testing.expect_value(t, run_status(&s, goal), Run_Status.Lost)
}

@(test)
run_status_is_in_progress_away_from_goal_with_positive_hp :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20}
	encounter_point := Point{kind = .Encounter}

	testing.expect_value(t, run_status(&s, encounter_point), Run_Status.In_Progress)
}

@(test)
run_can_travel_is_false_once_hp_reaches_zero :: proc(t: ^testing.T) {
	sunk := ship.Ship{hp = 0}
	afloat := ship.Ship{hp = 1}

	testing.expect(t, !run_can_travel(&sunk))
	testing.expect(t, run_can_travel(&afloat))
}
