package run

import "../combat"
import "../ship"
import "core:math/rand"
import "core:strings"
import "core:testing"

// test_opponent builds an opponent the way run_bake_stage does, off a fresh
// generator for `seed`, so a test can talk about "the hostile seed 3 deals" without
// standing up a whole map.
test_opponent :: proc(site: Scaling_Site, seed: u64) -> ship.Ship {
	state := rand.create(seed)
	return run_pve_opponent(site, rand.default_random_generator(&state))
}

// test_hostile builds one *named* archetype at a site, bypassing the draw — the
// per-archetype tests need to say which build they mean rather than fish for it
// across seeds.
test_hostile :: proc(archetype: Hostile_Archetype, site: Scaling_Site) -> ship.Ship {
	s := run_make_opponent_ship(site)
	s.speed = archetype.speed
	layout := ship.ship_template_layout()
	assert(run_fit_hostile_loadout(layout, archetype, run_fight_opponent_offense(site)))
	s.layout = layout
	return s
}

@(test)
run_pve_opponent_fills_every_slot_of_the_one_ship_template :: proc(t: ^testing.T) {
	opponent := test_opponent(Scaling_Site{zone = .Coastal, depth = 3}, 0)
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
	opponent := test_opponent(site, 0)
	defer delete(opponent.layout)

	testing.expect_value(t, opponent.hp, run_fight_opponent_hp(site))
	testing.expect_value(t, opponent.durability, run_fight_opponent_durability(site))
}

@(test)
run_pve_opponent_carries_no_captain :: proc(t: ^testing.T) {
	opponent := test_opponent(Scaling_Site{zone = .Coastal, depth = 3}, 0)
	defer delete(opponent.layout)

	_, has_captain := opponent.captain.?
	testing.expect(t, !has_captain)
}

// --- Hostile roster (issue #135) --------------------------------------------

// The point of the ticket. Every battle in the game used to be the same ship with
// bigger numbers — a hostile *template*, not a roster. If the draw only ever yields
// one build, nothing was retired.
@(test)
run_pve_opponent_draws_more_than_one_distinct_archetype_across_seeds :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Open_Sea, depth = 1}
	seen: map[string]bool
	defer delete(seen)

	for seed in u64(0) ..< 50 {
		opponent := test_opponent(site, seed)
		defer delete(opponent.layout)
		// An archetype has no name on the built Ship, so identify the build by the
		// loadout it produced — which is the thing the player actually meets.
		seen[loadout_signature(opponent)] = true
	}

	testing.expect(t, len(seen) > 1)
}

// Baked at generation off the map generator's RNG, so the same seed must yield the
// same hostile — the no-runtime-RNG property (ADR-0013) covers which opponent a
// node holds, like every other stage's content.
@(test)
run_pve_opponent_is_reproducible_per_seed :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Deep, depth = 2}
	a := test_opponent(site, 11)
	defer delete(a.layout)
	b := test_opponent(site, 11)
	defer delete(b.layout)

	testing.expect_value(t, loadout_signature(a), loadout_signature(b))
	testing.expect_value(t, a.speed, b.speed)
}

// An archetype names its items instead of restating their magnitudes, so a typo is
// caught here rather than by an assert at map generation. Also the template-drift
// check: an entry asking for more Larges than the template has cannot fit.
@(test)
every_hostile_archetype_is_built_from_real_roster_items :: proc(t: ^testing.T) {
	for archetype in run_hostile_roster() {
		testing.expect(t, len(archetype.name) > 0)
		testing.expectf(t, len(archetype.items) > 0, "%v carries no items", archetype.name)
		testing.expectf(t, archetype.speed > 0, "%v has no speed", archetype.name)

		for name in archetype.items {
			_, found := ship.ship_item_by_name(name)
			testing.expectf(t, found, "%v names %q, which is not a roster item", archetype.name, name)
		}

		layout := ship.ship_template_layout()
		defer delete(layout)
		testing.expectf(
			t,
			run_fit_hostile_loadout(layout, archetype, 0),
			"%v's items do not fit the one ship template",
			archetype.name,
		)
	}
}

// Stakes is the power axis: a deeper node's hostile hits harder, whichever build it
// happens to be. Drawing both from the same seed makes them the same archetype, so
// the only difference is the site.
@(test)
a_deeper_node_gives_the_opponent_harder_hitting_offensive_fittings :: proc(t: ^testing.T) {
	coastal := test_opponent(Scaling_Site{zone = .Coastal, depth = 0}, 4)
	defer delete(coastal.layout)
	deep := test_opponent(Scaling_Site{zone = .Deep, depth = 3}, 4)
	defer delete(deep.layout)

	testing.expect_value(t, loadout_signature(coastal), loadout_signature(deep)) // same build
	testing.expect(t, phase_magnitude(deep, .Offensive) > phase_magnitude(coastal, .Offensive))
	testing.expect(t, deep.hp > coastal.hp)
	testing.expect(t, deep.durability > coastal.durability)
}

// The stakes bonus lands on Offensive fittings only (run_fit_hostile_loadout).
// Scaling Buff or Defensive fittings would raise the hostile's `defense_bonus`,
// which is subtracted from the *player's* damage — so a deeper node would make a
// hostile harder to hurt rather than harder to fight.
@(test)
the_stakes_bonus_scales_offensive_fittings_only :: proc(t: ^testing.T) {
	for archetype in run_hostile_roster() {
		shallow := test_hostile(archetype, Scaling_Site{zone = .Coastal, depth = 0})
		defer delete(shallow.layout)
		deep := test_hostile(archetype, Scaling_Site{zone = .Deep, depth = 3})
		defer delete(deep.layout)

		testing.expectf(
			t,
			phase_magnitude(deep, .Buff) == phase_magnitude(shallow, .Buff),
			"%v's buff output moved with the site",
			archetype.name,
		)
		testing.expectf(
			t,
			phase_magnitude(deep, .Defensive) == phase_magnitude(shallow, .Defensive),
			"%v's defensive output moved with the site",
			archetype.name,
		)
	}
}

// **The independence property.** The site's offense reading is a total shared across
// an archetype's guns (run_fit_hostile_loadout), so stakes must be worth the same
// uplift to every build — a three-gun archetype must not collect three times what a
// one-gun archetype does. This is the test that would fail if the bonus were ever
// quietly made per-fitting, which is the natural-looking thing to write.
@(test)
the_stakes_uplift_is_the_same_total_for_every_archetype :: proc(t: ^testing.T) {
	shallow_site := Scaling_Site{zone = .Coastal, depth = 0}
	deep_site := Scaling_Site{zone = .Deep, depth = DEPTH_STEPS}
	expected := run_fight_opponent_offense(deep_site) - run_fight_opponent_offense(shallow_site)

	for archetype in run_hostile_roster() {
		shallow := test_hostile(archetype, shallow_site)
		defer delete(shallow.layout)
		deep := test_hostile(archetype, deep_site)
		defer delete(deep.layout)

		testing.expectf(
			t,
			phase_magnitude(deep, .Offensive) - phase_magnitude(shallow, .Offensive) == expected,
			"%v gained %d offense between Coastal and The Deep; every archetype must gain %d",
			archetype.name,
			phase_magnitude(deep, .Offensive) - phase_magnitude(shallow, .Offensive),
			expected,
		)
	}
}

// Speed is the archetype's axis, not the site's — the whole reason the flat
// FIGHT_OPPONENT_SPEED was retired. The roster must actually *use* the axis in both
// directions against a starting player's 4: something slower (so Leave Combat is a
// real option) and something faster (so a hostile can leave first).
@(test)
the_hostile_roster_spans_speeds_either_side_of_a_starting_ship :: proc(t: ^testing.T) {
	player := ship.ship_starting_ship()
	defer delete(player.layout)
	base := ship.ship_effective_speed(&player)

	slower, faster := false, false
	for archetype in run_hostile_roster() {
		hostile := test_hostile(archetype, Scaling_Site{zone = .Coastal, depth = 0})
		defer delete(hostile.layout)

		switch {
		case ship.ship_effective_speed(&hostile) < base:
			slower = true
		case ship.ship_effective_speed(&hostile) > base:
			faster = true
		}
	}

	testing.expect(t, slower) // a hostile the player may walk away from
	testing.expect(t, faster) // a hostile that will walk away from the player
}

// **The roster's authoring rule, made checkable**: an archetype is character, stakes
// is power, so every build must be a real fight for a *starting* ship at Coastal —
// the state the player is actually in when they meet their first hostile, and (since
// the draw reads no zone) any archetype can be that first hostile.
//
// Both failure directions are one-line mistakes in the table, and the margins are
// single digits: damage is `raw - (effective_durability + defense_bonus)`, and a
// starting player's raw of 8 already spends 6 of it on the template's own soak. A
// few points of stacked +Durability — or of *buff*, which folds into the defender's
// defense_bonus too — makes a hostile undentable. Overshoot the other way and it
// one-shots a 20-HP ship. This test is what keeps the eight entries in the band the
// retired template sat in.
@(test)
a_starting_player_can_fight_every_archetype_at_coastal :: proc(t: ^testing.T) {
	// A Coastal hostile has 10 HP, so a fight that runs this long is not a fight.
	ROUND_CAP :: 30
	// The player must still be afloat this far in: fewer rounds than this and the
	// hostile is a coin-flip the captain never gets to play.
	MIN_PLAYER_ROUNDS :: 4

	for archetype in run_hostile_roster() {
		player := ship.ship_starting_ship()
		defer delete(player.layout)
		hostile := test_hostile(archetype, Scaling_Site{zone = .Coastal, depth = 0})
		defer delete(hostile.layout)

		battle := combat.combat_battle_create(&player, &hostile)
		events: [dynamic]combat.Event
		defer delete(events)

		// Both sides Hold: this is about the damage band the loadouts produce, not
		// about escape, so the fight is fought out rather than scripted.
		hold := [combat.Side]Maybe(combat.Command) {
			.A = combat.Command(combat.Command_Hold{}),
			.B = combat.Command(combat.Command_Hold{}),
		}
		for !battle.ended && battle.round < ROUND_CAP {
			combat.combat_resolve_round(&battle, hold, &events)
			if player.hp <= 0 {
				testing.expectf(
					t,
					battle.round >= MIN_PLAYER_ROUNDS,
					"%v sinks a starting ship in %d round(s) at Coastal — the archetype is carrying stakes' job",
					archetype.name,
					battle.round,
				)
			}
		}

		// Not a wall: the player's damage got through at all.
		testing.expectf(
			t,
			hostile.hp < hostile.max_hp,
			"a starting player cannot scratch %v at Coastal (durability %d) — see the both-walls note on hostile_roster",
			archetype.name,
			ship.ship_effective_durability(&hostile),
		)
		// And the fight actually ends, rather than grinding on the damage floor.
		testing.expectf(t, battle.ended, "%v and a starting player cannot finish a fight at Coastal", archetype.name)
	}
}

// loadout_signature names the build a Ship is carrying, in slot order — enough to
// tell two archetypes apart (and to tell the same one drawn twice is the same one)
// without an archetype name riding along on the built Ship.
loadout_signature :: proc(s: ship.Ship) -> string {
	signature: strings.Builder
	strings.builder_init(&signature, context.temp_allocator)
	for layout_slot in s.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting {
			continue
		}
		strings.write_string(&signature, fitting.name)
		strings.write_byte(&signature, '|')
	}
	return strings.to_string(signature)
}

// phase_magnitude totals the authored magnitudes of a ship's fittings in one combat
// phase. Read off the fittings rather than through combat_phase_output so it needs
// no Battle — a synergy resolves against the ship alone here, which is all these
// tests compare.
phase_magnitude :: proc(s: ship.Ship, phase: ship.Category) -> int {
	total := 0
	for layout_slot in s.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting || fitting.category != phase {
			continue
		}
		if active, ok := fitting.active.?; ok {
			total += int(active.magnitude)
		}
	}
	return total
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
