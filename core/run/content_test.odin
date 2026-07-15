package run

import "../ship"
import "core:math/rand"
import "core:testing"

@(test)
run_pve_opponent_fills_every_slot_of_the_one_ship_template :: proc(t: ^testing.T) {
	opponent := run_pve_opponent(Scaling_Site{zone = .Coastal, depth = 3})
	defer delete(opponent.layout)

	testing.expect_value(t, len(opponent.layout), 8)
	for layout_slot in opponent.layout {
		_, has_fitting := layout_slot.fitting.?
		testing.expect(t, has_fitting)
	}
}

@(test)
run_pve_opponent_stats_reuse_the_existing_zone_and_depth_scaled_fight_formulas :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Deep, depth = 2}
	opponent := run_pve_opponent(site)
	defer delete(opponent.layout)

	testing.expect_value(t, opponent.hp, run_fight_opponent_hp(site))
	testing.expect_value(t, opponent.durability, run_fight_opponent_durability(site))
}

@(test)
run_pve_opponent_carries_no_captain :: proc(t: ^testing.T) {
	opponent := run_pve_opponent(Scaling_Site{zone = .Coastal, depth = 3})
	defer delete(opponent.layout)

	_, has_captain := opponent.captain.?
	testing.expect(t, !has_captain)
}

@(test)
a_deeper_ship_battle_node_gives_the_opponent_a_harder_hitting_gun_deck :: proc(t: ^testing.T) {
	coastal := run_pve_opponent(Scaling_Site{zone = .Coastal, depth = 0})
	defer delete(coastal.layout)
	deep := run_pve_opponent(Scaling_Site{zone = .Deep, depth = 0})
	defer delete(deep.layout)

	coastal_gun_deck, _ := coastal.layout[2].fitting.?
	deep_gun_deck, _ := deep.layout[2].fitting.?
	coastal_active, _ := coastal_gun_deck.active.?
	deep_active, _ := deep_gun_deck.active.?

	testing.expect(t, deep_active.magnitude > coastal_active.magnitude)
}

@(test)
run_map_create_wires_the_hand_authored_pve_opponent_content_into_fight_stages :: proc(t: ^testing.T) {
	m := run_map_create(0)
	defer run_map_destroy(&m)

	found_a_fight := false
	for node in m.nodes {
		encounter, has_encounter := node.encounter.?
		if !has_encounter {
			continue
		}
		fight, is_fight := only_stage(encounter, Stage_Fight)
		if !is_fight {
			continue
		}
		found_a_fight = true
		testing.expect_value(t, len(fight.opponent.layout), 8)
	}
	testing.expect(t, found_a_fight)
}

@(test)
run_item_offer_options_presents_distinct_roster_items :: proc(t: ^testing.T) {
	state := rand.create(0)
	gen := rand.default_random_generator(&state)
	options := run_item_offer_options(Scaling_Site{zone = .Coastal, depth = 0}, gen)

	// Every offered option is a distinct roster item (no repeats), and each is a
	// real fitting the player could place — not a cargo filler.
	testing.expect_value(t, len(options), ITEM_OFFER_OPTION_COUNT)
	for a, i in options {
		testing.expect(t, !a.is_cargo)
		testing.expect(t, len(a.name) > 0)
		for b, j in options {
			if i != j {
				testing.expect(t, a.name != b.name)
			}
		}
	}
}

@(test)
run_item_offer_options_scale_up_with_a_deeper_node :: proc(t: ^testing.T) {
	// A deeper node's quality bonus lifts the offered items' magnitudes. Drawing
	// both offers from the same seed makes them sample the same items in the same
	// order, so the only difference is the zone/depth scaling.
	low_state := rand.create(7)
	high_state := rand.create(7)
	low := run_item_offer_options(Scaling_Site{zone = .Coastal, depth = 0}, rand.default_random_generator(&low_state))
	high := run_item_offer_options(Scaling_Site{zone = .Deep, depth = 3}, rand.default_random_generator(&high_state))

	found_scaled := false
	for i in 0 ..< ITEM_OFFER_OPTION_COUNT {
		testing.expect_value(t, low[i].name, high[i].name) // same items, same order
		if effect_strength(high[i]) > effect_strength(low[i]) {
			found_scaled = true
		}
	}
	testing.expect(t, found_scaled)
}

// effect_strength reads the magnitude of whichever effect a roster item carries,
// so a test can assert the quality scaling lifted it without caring which slot
// (passive/active) the item's one effect sits in.
effect_strength :: proc(f: ship.Fitting) -> int {
	if active, ok := f.active.?; ok {
		return int(active.magnitude)
	}
	if passive, ok := f.passive.?; ok {
		return int(passive.magnitude)
	}
	return 0
}
