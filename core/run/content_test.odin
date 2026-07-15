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

// --- Trade roster (issue #136) ----------------------------------------------

// The point of the ticket: the trade axis is no longer one welded point. If the
// roster only ever yields one distinct bargain, nothing was unwelded.
@(test)
run_make_trade_draws_more_than_one_distinct_axis_across_seeds :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Open_Sea, depth = 1}
	seen: map[string]bool
	defer delete(seen)

	for seed in u64(0) ..< 50 {
		state := rand.create(seed)
		trade := run_make_trade(site, rand.default_random_generator(&state))
		seen[trade.name] = true
	}

	testing.expect(t, len(seen) > 1)
}

// Baked at generation off the map generator's RNG, so the same seed must yield
// the same bargain — the no-runtime-RNG property (ADR-0013) applies to a Trade's
// content like every other stage's.
@(test)
run_make_trade_is_reproducible_per_seed :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Deep, depth = 2}

	a_state := rand.create(11)
	b_state := rand.create(11)
	a := run_make_trade(site, rand.default_random_generator(&a_state))
	b := run_make_trade(site, rand.default_random_generator(&b_state))

	testing.expect_value(t, a, b)
}

// Both sides read the same Scaling_Site, so stakes move the whole trade — not
// just the half that used to own a constant.
@(test)
run_make_trade_scales_both_sides_with_the_site :: proc(t: ^testing.T) {
	shallow_state := rand.create(3)
	deep_state := rand.create(3)
	shallow := run_make_trade(Scaling_Site{zone = .Coastal, depth = 0}, rand.default_random_generator(&shallow_state))
	deep := run_make_trade(Scaling_Site{zone = .Deep, depth = DEPTH_STEPS}, rand.default_random_generator(&deep_state))

	testing.expect_value(t, shallow.name, deep.name) // same seed, same axis drawn
	testing.expect(t, deep.gain.amount > shallow.gain.amount)
	testing.expect(t, deep.cost.amount > shallow.cost.amount)
}

// A baked trade's magnitudes are exactly its two stats' swings at that site —
// the roster entry contributes the stats, the site contributes the numbers.
@(test)
run_make_trade_reads_each_side_as_that_stats_swing :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Open_Sea, depth = 2}
	state := rand.create(5)
	trade := run_make_trade(site, rand.default_random_generator(&state))

	testing.expect_value(t, trade.gain.amount, run_trade_swing(site, trade.gain.stat))
	testing.expect_value(t, trade.cost.amount, run_trade_swing(site, trade.cost.stat))
}

// Every entry is a real swap: a trade that gains and costs the same stat is a
// no-op dressed as a decision.
@(test)
every_trade_roster_entry_swaps_two_different_stats_and_is_named :: proc(t: ^testing.T) {
	for axis in run_trade_roster() {
		testing.expect(t, len(axis.name) > 0)
		testing.expectf(t, axis.gain != axis.cost, "%v gains and costs the same stat", axis.name)
	}
}

// The roster's coverage rule (content.odin): every stat is gained by some entry,
// and every stat except HP is spent by some entry. HP is gain-only on purpose —
// nothing else in the game heals, and a trade that damages you is a Fight
// without the fight.
@(test)
the_trade_roster_gains_every_stat_and_costs_every_stat_but_hp :: proc(t: ^testing.T) {
	gained: bit_set[Trade_Stat]
	cost: bit_set[Trade_Stat]
	for axis in run_trade_roster() {
		gained += {axis.gain}
		cost += {axis.cost}
	}

	for stat in Trade_Stat {
		testing.expectf(t, stat in gained, "no roster entry gains %v", stat)
	}
	testing.expect_value(t, cost, bit_set[Trade_Stat]{.Max_HP, .Durability, .Speed, .Treasure})
}

// The pre-#136 Bargain was +Durability for -Speed, scaled by
// TRADE_GAIN_DURABILITY_* / TRADE_COST_SPEED_*. Those constants became the
// Durability and Speed rows of the swing table unchanged, so the Braced Bulkheads
// entry must still produce the old numbers exactly — the roster is new content,
// not a retune of the content that was already there.
@(test)
the_braced_bulkheads_entry_reproduces_the_pre_136_bargain_numbers :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Open_Sea, depth = 2}

	// The old formulas, inlined: zone_tier * per_tier + depth * per_depth.
	old_gain_durability := zone_tier[site.zone] * 8 + site.depth * 2
	old_cost_speed := zone_tier[site.zone] * 1 + site.depth * 1

	testing.expect_value(t, run_trade_swing(site, .Durability), old_gain_durability)
	testing.expect_value(t, run_trade_swing(site, .Speed), old_cost_speed)

	braced := run_trade_roster()[0]
	testing.expect_value(t, braced.name, "Braced Bulkheads")
	testing.expect_value(t, braced.gain, Trade_Stat.Durability)
	testing.expect_value(t, braced.cost, Trade_Stat.Speed)
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
