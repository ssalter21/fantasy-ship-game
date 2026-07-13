package run

import "core:testing"

@(test)
run_pve_opponent_fills_every_slot_of_the_one_ship_template :: proc(t: ^testing.T) {
	opponent := run_pve_opponent(.Coastal, 3)
	defer delete(opponent.layout)

	testing.expect_value(t, len(opponent.layout), 8)
	for layout_slot in opponent.layout {
		_, has_fitting := layout_slot.fitting.?
		testing.expect(t, has_fitting)
	}
}

@(test)
run_pve_opponent_stats_reuse_the_existing_zone_and_depth_scaled_ship_battle_formulas :: proc(t: ^testing.T) {
	opponent := run_pve_opponent(.Deep, 2)
	defer delete(opponent.layout)

	testing.expect_value(t, opponent.hp, run_ship_battle_difficulty(.Deep, 2))
	testing.expect_value(t, opponent.durability, run_ship_battle_opponent_durability(.Deep, 2))
}

@(test)
run_pve_opponent_carries_no_captain :: proc(t: ^testing.T) {
	opponent := run_pve_opponent(.Coastal, 3)
	defer delete(opponent.layout)

	_, has_captain := opponent.captain.?
	testing.expect(t, !has_captain)
}

@(test)
a_deeper_ship_battle_node_gives_the_opponent_a_harder_hitting_gun_deck :: proc(t: ^testing.T) {
	coastal := run_pve_opponent(.Coastal, 0)
	defer delete(coastal.layout)
	deep := run_pve_opponent(.Deep, 0)
	defer delete(deep.layout)

	coastal_gun_deck, _ := coastal.layout[2].fitting.?
	deep_gun_deck, _ := deep.layout[2].fitting.?
	coastal_active, _ := coastal_gun_deck.active.?
	deep_active, _ := deep_gun_deck.active.?

	testing.expect(t, deep_active.magnitude > coastal_active.magnitude)
}

@(test)
run_map_create_wires_the_hand_authored_pve_opponent_content_into_ship_battle_nodes :: proc(t: ^testing.T) {
	m := run_map_create(0)
	defer run_map_destroy(&m)

	found_a_ship_battle := false
	for node in m.nodes {
		encounter, has_encounter := node.encounter.?
		if !has_encounter {
			continue
		}
		battle, is_battle := encounter.(Encounter_Ship_Battle)
		if !is_battle {
			continue
		}
		found_a_ship_battle = true
		testing.expect_value(t, len(battle.opponent.layout), 8)
	}
	testing.expect(t, found_a_ship_battle)
}

@(test)
run_upgrade_offer_options_returns_the_three_upgraded_starting_fittings :: proc(t: ^testing.T) {
	options := run_upgrade_offer_options(Encounter_Upgrade_Offer{quality = 15})

	testing.expect_value(t, options[0].name, "Upgraded Top Crew")
	testing.expect_value(t, options[1].name, "Upgraded Captain's Quarters")
	testing.expect_value(t, options[2].name, "Upgraded Gun Deck")
}

@(test)
run_upgrade_offer_options_scale_up_with_a_higher_quality_offer :: proc(t: ^testing.T) {
	low := run_upgrade_offer_options(Encounter_Upgrade_Offer{quality = 5})
	high := run_upgrade_offer_options(Encounter_Upgrade_Offer{quality = 50})

	low_active, _ := low[2].active.?
	high_active, _ := high[2].active.?
	testing.expect(t, high_active.magnitude > low_active.magnitude)
}
