package run

import "../combat"
import "../ship"
import "../testutil"
import "core:math/rand"
import "core:slice"
import "core:testing"

// only_stage_kind returns the primitive of e's single stage, asserting that e
// has exactly one — for the assertions that are *about* a one-stage encounter and
// would be saying something else entirely if handed a longer one.
//
// It was written as a guard: while the whole catalog was one-stage ports of the
// retired kinds, several assertions talked about "this node's kind" through the
// stage list, and this made them fail loudly rather than silently read stage 0
// once #138 authored multi-stage recipes. It did its job — #138 tripped it — and
// what is left is the honest use, the Port, which is one stage by its bucket's
// exemption rather than by the catalog's not having grown up yet.
only_stage_kind :: proc(e: Encounter) -> Stage_Kind {
	assert(e.count == 1, "only_stage_kind on a multi-stage encounter — this assertion predates the multi-stage catalog (#138)")
	return voyage_stage_kind(e.stages[0])
}

// only_stage returns e's single stage as T, or ok=false if e's one stage is a
// different primitive. The Encounter-shaped counterpart of a plain type
// assertion, for assertions that need the stage's baked content and not just its
// kind.
only_stage :: proc(e: Encounter, $T: typeid) -> (stage: T, ok: bool) {
	if e.count != 1 {
		return {}, false
	}
	return e.stages[0].(T)
}

// node_shop returns the first Shop stage p's encounter holds, or ok=false for a
// node that holds no encounter or no Shop within it. A shop's stock is a stage
// rather than a field on the Node (#134), so "does this node carry a shop" is a
// question asked of its stage list — which is what the assertions below check.
//
// First match wins: no authored recipe carries two Shops, and a recipe that did
// would be two shops at one node, which is a content question and not this
// helper's to answer. The scan lives here rather than in the package because the
// generic walk (#131) reaches each stage through the cursor and asks nothing of
// the ones it isn't on — leaving these assertions its only caller.
node_shop :: proc(p: Node) -> (shop: Stage_Shop, ok: bool) {
	encounter, has_encounter := p.encounter.?
	if !has_encounter {
		return {}, false
	}
	for i in 0 ..< encounter.count {
		if s, is_shop := encounter.stages[i].(Stage_Shop); is_shop {
			return s, true
		}
	}
	return {}, false
}

// node_port_shop returns the Shop stage p holds **if p is a Port**, or ok=false
// otherwise — including for a merchant vessel, which carries a Shop but is not one.
//
// A port is identified by its encounter **opening** on a Shop. That is a narrowing
// of what node_shop used to mean here: #137 retired Node_Kind.Port, leaving "holds a
// Shop" as the definition of a port, and it was a sound one for exactly as long as
// the Port was the only recipe carrying a Shop at all. #138 authored the merchant
// vessels, so the old question now answers yes for a Press Gang and a Smuggler's
// Cove, and every assertion below about *ports* would have quietly started making
// claims about merchants — that a Press Gang stocks the Chandlery's 12 cards, that
// there are two of them per zone.
//
// Opening on a Shop is exact rather than a heuristic, and it is the same fact the
// map reads: only_the_port_bucket_opens_on_a_shop pins it in the catalog, precisely
// because view.odin labels a revealed encounter by its first stage and so a
// Shop-opening merchant would draw a Port's marker. The two are one rule — what
// makes a port findable here is what makes it findable on the map.
node_port_shop :: proc(p: Node) -> (shop: Stage_Shop, ok: bool) {
	encounter, has_encounter := p.encounter.?
	if !has_encounter || encounter.count == 0 {
		return {}, false
	}
	s := encounter.stages[0].(Stage_Shop) or_return
	return s, true
}

// --- Stakes formulas: zone tier x depth ------------------------------------

expect_rises_by_zone_and_depth :: proc(t: ^testing.T, f: proc(Scaling_Site) -> int) {
	// A deeper zone at the same depth stakes more...
	testing.expect(t, f(Scaling_Site{zone = .Deep, depth = 0}) > f(Scaling_Site{zone = .Coastal, depth = 0}))
	// ...and within a zone, a deeper node outscales a shallow one.
	testing.expect(t, f(Scaling_Site{zone = .Open_Sea, depth = DEPTH_STEPS}) > f(Scaling_Site{zone = .Open_Sea, depth = 0}))
}

@(test)
fight_opponent_hp_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, voyage_fight_opponent_hp)
}

@(test)
fight_opponent_durability_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, voyage_fight_opponent_durability)
}

@(test)
fight_opponent_offense_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, voyage_fight_opponent_power)
}

@(test)
offer_item_quality_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, voyage_offer_item_quality)
}

// The Trade primitive's reading is keyed by stat rather than by side (issue
// #136), so it can't go through expect_rises_by_zone_and_depth's
// proc(Scaling_Site) shape — and since #146 it reads no depth at all, so half of
// what that helper checks is not Trade's to answer for. Every stat must still
// scale by zone: a roster entry can put any stat on either side, so a stat whose
// swing ignored the gradient would be a trade with a stakes-blind half.
@(test)
trade_swing_rises_by_zone_for_every_stat :: proc(t: ^testing.T) {
	for stat in Trade_Stat {
		testing.expectf(
			t,
			voyage_trade_swing(.Deep, stat) > voyage_trade_swing(.Open_Sea, stat) &&
			voyage_trade_swing(.Open_Sea, stat) > voyage_trade_swing(.Coastal, stat),
			"%v's swing must rise with zone tier",
			stat,
		)
	}
}

// The exchange rate's defining property (#146): **one rate, not twelve.** Every
// row is `tier x rate`, so the ratio between any two stats' swings is the same in
// every zone — sell a swing of Speed for a swing of Max HP and you get the same
// bargain wherever you strike it. This is what the depth axis broke and what
// dropping it repaired: with per-tier and per-depth as independent knobs, the same
// named entry was fair at the top of a zone and a 1.75x gift at the bottom.
//
// Stated as a cross-multiply against Coastal to keep it in integers — a / b == c /
// d as a*d == c*b — so it asserts the ratios rather than any particular number,
// and no retune of a single row can satisfy it alone.
@(test)
the_swing_table_quotes_one_rate_in_every_zone :: proc(t: ^testing.T) {
	for x in Trade_Stat {
		for y in Trade_Stat {
			for zone in Zone {
				testing.expectf(
					t,
					voyage_trade_swing(zone, x) * voyage_trade_swing(.Coastal, y) ==
					voyage_trade_swing(zone, y) * voyage_trade_swing(.Coastal, x),
					"%v buys a different amount of %v in %v than it does at Coastal",
					x,
					y,
					zone,
				)
			}
		}
	}
}

@(test)
reward_treasure_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	// #133's acceptance in one line: a Deep reward outweighs a Coastal one.
	expect_rises_by_zone_and_depth(t, voyage_reward_treasure)
}

@(test)
a_reward_outpays_selling_a_stat_at_the_same_site :: proc(t: ^testing.T) {
	// The placeholder's one authored relationship (#132): a Reward pays more than a
	// Trade's Treasure swing, because a swing is what a stat fetches when sold and a
	// Reward is earned by the stage in front of it. If this inverts, [Fight, Reward] is
	// a worse Bargain — risk the run, or sell some Speed for more. Asserted at every
	// site rather than one, since the two read the same gradient through different
	// constants and could cross over at depth.
	for zone in Zone {
		for depth in 0 ..= DEPTH_STEPS {
			site := Scaling_Site{zone = zone, depth = depth}
			testing.expectf(
				t,
				voyage_reward_treasure(site) > voyage_trade_swing(site.zone, .Treasure),
				"a reward at %v must outpay selling a stat there",
				site,
			)
		}
	}
}

@(test)
voyage_make_opponent_ship_sets_both_hp_and_durability_from_zone_and_depth :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Deep, depth = 2}
	opponent := voyage_make_opponent_ship(site)

	testing.expect_value(t, opponent.hp, voyage_fight_opponent_hp(site))
	testing.expect_value(t, opponent.durability, voyage_fight_opponent_durability(site))
}

// The primitives all read one gradient, so their readings must stay
// distinguishable — otherwise a shared table would be indistinguishable from
// each primitive owning its own constants.
@(test)
the_primitives_readings_of_one_site_land_on_distinguishable_magnitudes :: proc(t: ^testing.T) {
	coastal := Scaling_Site{zone = .Coastal, depth = 0}
	testing.expect(t, voyage_fight_opponent_hp(coastal) != voyage_offer_item_quality(coastal))
	testing.expect(t, voyage_fight_opponent_hp(coastal) != voyage_trade_swing(coastal.zone, .Durability))
	testing.expect(t, voyage_offer_item_quality(coastal) != voyage_trade_swing(coastal.zone, .Durability))
}

// --- Depth normalization: stable endpoints regardless of layer count -------

@(test)
depth_normalization_maps_shallow_and_deep_to_stable_endpoints :: proc(t: ^testing.T) {
	// The shallowest layer always normalizes to 0 and the deepest to
	// DEPTH_STEPS, whether the zone rolled 3 layers or 5.
	testing.expect_value(t, voyage_normalize_depth(0, 3), 0)
	testing.expect_value(t, voyage_normalize_depth(2, 3), DEPTH_STEPS)
	testing.expect_value(t, voyage_normalize_depth(0, 5), 0)
	testing.expect_value(t, voyage_normalize_depth(4, 5), DEPTH_STEPS)
	// A single-layer zone collapses to 0 (no division by zero).
	testing.expect_value(t, voyage_normalize_depth(0, 1), 0)
}

@(test)
node_kind_says_only_where_a_node_sits_never_what_it_holds :: proc(t: ^testing.T) {
	// The end state ADR-0014 named and #137 reached: Start | Encounter | Goal. Start
	// and Goal are landmarks by graph *position*, which no stage list can express;
	// everything else is an Encounter, and what it holds is asked of its stages.
	//
	// This replaces voyage_node_is_port_is_true_for_start_and_zone_ports_but_not_encounter_or_goal.
	// That proc — and the .Port value it read — had no caller outside its own test by
	// the time #137 arrived: #131 took the Sim's last read of the kind, and #134 made a
	// port's shop its [Shop] stage. This asserts the enum stays shut, so a future
	// content-bearing kind has to argue with a failing test first.
	testing.expect_value(t, len(Node_Kind), 3)
	testing.expect_value(t, max(Node_Kind), Node_Kind.Goal)
}

@(test)
every_stock_pool_is_authored_against_the_real_roster :: proc(t: ^testing.T) {
	// The stock-pool table is authored data (#137), so its invariants are checked here
	// rather than by the compiler — the same treatment
	// every_hostile_archetype_is_built_from_real_roster_items gives the hostile roster.
	//
	// A pool that asked for more cards than its families can supply would silently
	// stock less than it claims (voyage_bake_shop clamps to the candidate count), and a
	// pool deeper than SHOP_STOCK_MAX would not fit a Stage_Shop at all.
	for pool in Stock_Pool {
		stock := voyage_stock_pool(pool)
		testing.expectf(t, stock.name != "", "stock pool %v has no name", pool)
		testing.expectf(t, stock.depth > 0, "stock pool %v stocks nothing", pool)
		testing.expectf(
			t,
			stock.depth <= SHOP_STOCK_MAX,
			"stock pool %v is %d cards deep, past the SHOP_STOCK_MAX of %d a Stage_Shop can hold",
			pool, stock.depth, SHOP_STOCK_MAX,
		)

		_, n := voyage_stock_candidates(stock)
		testing.expectf(
			t,
			n >= stock.depth,
			"stock pool %v wants %d cards but its families supply only %d",
			pool, stock.depth, n,
		)
	}

	// The Chandlery is the general store: no filter at all, so its candidates are the
	// whole roster. Authoring it as "every family" instead would pass every assertion
	// above and still quietly drop a sixth Tag the day one is added.
	chandlery := voyage_stock_pool(.Chandlery)
	_, families_filtered := chandlery.families.?
	testing.expect(t, !families_filtered)
	_, chandlery_candidates := voyage_stock_candidates(chandlery)
	testing.expect_value(t, chandlery_candidates, ship.ITEM_ROSTER_SIZE)
}

@(test)
a_specialist_pool_stocks_only_its_own_families :: proc(t: ^testing.T) {
	// The filter is the whole mechanism (#137) and **nothing else exercises it**: the
	// Chandlery applies no filter, and it is the only pool a recipe names until #138
	// authors the merchant vessels. So bake each pool directly rather than through a
	// generated map, or the specialist holds would ship untested.
	state := rand.create(7)
	gen := rand.default_random_generator(&state)

	for pool in Stock_Pool {
		stock := voyage_stock_pool(pool)
		families, filtered := stock.families.?
		if !filtered {
			continue // the Chandlery, checked by every_stock_pool_is_authored_against_the_real_roster
		}

		shop := voyage_bake_shop(pool, gen)
		testing.expectf(t, shop.count == stock.depth, "%v stocked %d cards, want %d", pool, shop.count, stock.depth)
		for i in 0 ..< shop.count {
			card := shop.stock[i]
			testing.expectf(
				t,
				card.fitting.tags & families != {},
				"%v stocks %q, which carries %v and none of the pool's %v",
				pool, card.fitting.name, card.fitting.tags, families,
			)
		}
	}
}

@(test)
a_pool_stocks_a_multi_tag_item_under_each_of_its_families :: proc(t: ^testing.T) {
	// A multi-tag item belongs to *both* its families (ADR-0012 — selector_matches
	// counts it under each), so an Ordnance Hoy and a Press Gang can both stock the
	// Crew+Weapon items. That is a deliberate consequence of "keep it if it carries
	// **any** of the pool's families" and it is what keeps the specialist pools from
	// carving the roster into disjoint slices with the cross-family items falling
	// between them.
	weapon, weapon_n := voyage_stock_candidates(voyage_stock_pool(.Ordnance_Hoy))
	crew, crew_n := voyage_stock_candidates(voyage_stock_pool(.Press_Gang))

	shared := 0
	for i in 0 ..< weapon_n {
		for j in 0 ..< crew_n {
			if weapon[i] == crew[j] {
				shared += 1
			}
		}
	}
	testing.expectf(t, shared > 0, "no roster item is both Crew and Weapon, so this test no longer proves anything")
}

@(test)
every_stage_spec_authors_a_pool_iff_it_is_a_shop :: proc(t: ^testing.T) {
	// Stage_Spec.stock is a Maybe so that a pool is explicitly absent on a non-Shop
	// rather than accidentally the zero pool (#137), and voyage_bake_stage asserts both
	// directions. This checks every authored recipe already satisfies it, so the assert
	// is a statement about the catalog rather than a trap waiting for a real seed.
	named: bit_set[Stock_Pool]
	for r in ([]([]Recipe){voyage_recipe_catalog(), voyage_port_bucket()}) {
		for recipe in r {
			for spec in recipe.stages {
				pool, authored := spec.stock.?
				testing.expectf(
					t,
					authored == (spec.kind == .Shop),
					"recipe %q authors a %v stage with stock = %v; only a Shop draws from a pool",
					recipe.name, spec.kind, spec.stock,
				)
				if authored {
					named += {pool}
				}
			}
		}
	}
	// Every authored hold is reachable. This used to read `pools == 1` — the Port's
	// Chandlery and nothing else — because #137 authored the four specialist pools
	// while the catalog still held a single [Fight] and could not name them. #138
	// authored the merchant vessels, so the wait is over and the property inverts:
	// a pool no recipe names is content that cannot be reached on any seed, which
	// is a mistake rather than a stage of the effort.
	for pool in Stock_Pool {
		testing.expectf(t, pool in named, "no recipe names the %v pool, so no seed can ever stock it", pool)
	}
}

@(test)
only_the_port_bucket_opens_on_a_shop :: proc(t: ^testing.T) {
	// #138's authoring discovery, and the reason there is no one-stage merchant.
	//
	// Shop is the revealing primitive, and view.odin's node_appearance labels a
	// revealed encounter by its **first stage**. So any recipe opening on a Shop
	// draws the same "Shop" marker a Port draws, and the captain cannot tell the
	// Chandlery's 12 general cards from a specialist's 6 until the voyage there is
	// already spent. The Port bucket's guaranteed placement is a promise that a Shop
	// marker is a general market (Stock_Pool); a counterfeit Port breaks it.
	//
	// A merchant vessel therefore earns its Shop by putting a stage in front of it —
	// which is its bucket restated: a Port is guaranteed and general, a merchant is a
	// windfall you sail into rather than one you can see and route to.
	//
	// **ADR-0016 gave this rule a second job, and made it permanent.** An encounter
	// reveals iff its first stage reveals, so "opens on a Shop" ≡ "reveals" ≡ "is a
	// Port": the same convention that keeps a counterfeit Port off the map is also
	// what keeps every merchant hidden. It therefore cannot be traded away for a
	// better marker — #139 naming revealed encounters would once have dissolved the
	// counterfeit argument, but a `[Shop]` merchant is *visible*, so it is plannable,
	// and a merchant is not something you plan a route to. Naming cannot fix that,
	// because the objection is no longer about what the marker says.
	for recipe in voyage_recipe_catalog() {
		testing.expectf(
			t,
			recipe.stages[0].kind != .Shop,
			"%q opens on a Shop, so the map draws it as a Port that isn't one",
			recipe.name,
		)
	}
	for recipe in voyage_port_bucket() {
		testing.expectf(t, recipe.stages[0].kind == .Shop, "%q is in the Port bucket but does not open on a Shop", recipe.name)
	}
}

// --- Generation structural invariants (swept over several seeds) -----------

// TEST_SEEDS is a spread of seeds the structural-invariant tests sweep, so a
// single lucky/unlucky seed can't mask a generation bug.
TEST_SEEDS := []u64{0, 1, 2, 7, 42, 1000, 123456}

goal_id :: proc(m: Map) -> Node_ID {
	for p in m.nodes {
		if p.kind == .Goal {
			return p.id
		}
	}
	return -1
}

// forward_reaches_goal reports whether start can reach goal following only
// forward edges (strictly-higher layer), verifying the forward DAG.
forward_reaches_goal :: proc(m: Map, start, goal: Node_ID) -> bool {
	visited := make([]bool, len(m.nodes))
	defer delete(visited)
	stack: [dynamic]Node_ID
	defer delete(stack)
	append(&stack, start)
	visited[start] = true
	for len(stack) > 0 {
		u := pop(&stack)
		if u == goal {
			return true
		}
		for v in m.edges[u] {
			if m.nodes[v].layer > m.nodes[u].layer && !visited[v] {
				visited[v] = true
				append(&stack, v)
			}
		}
	}
	return false
}

@(test)
every_non_goal_node_has_a_forward_path_to_goal_and_no_dead_ends :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		goal := goal_id(m)
		for p in m.nodes {
			if p.kind == .Goal {
				continue
			}
			// No dead ends: at least one forward (higher-layer) edge.
			has_forward := false
			for v in m.edges[p.id] {
				if m.nodes[v].layer > p.layer {
					has_forward = true
					break
				}
			}
			testing.expectf(t, has_forward, "seed %d: node %d is a dead end", seed, p.id)
			// Reachability: a forward path to Goal exists.
			testing.expectf(t, forward_reaches_goal(m, p.id, goal), "seed %d: node %d cannot reach Goal", seed, p.id)
		}
	}
}

@(test)
every_node_is_reachable_from_start :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		// BFS forward from Start (id 0) must cover every node.
		reached := make([]bool, len(m.nodes))
		defer delete(reached)
		stack: [dynamic]Node_ID
		defer delete(stack)
		append(&stack, 0)
		reached[0] = true
		for len(stack) > 0 {
			u := pop(&stack)
			for v in m.edges[u] {
				if m.nodes[v].layer > m.nodes[u].layer && !reached[v] {
					reached[v] = true
					append(&stack, v)
				}
			}
		}
		for r, i in reached {
			testing.expectf(t, r, "seed %d: node %d unreachable from Start", seed, i)
		}
	}
}

@(test)
voyage_map_create_has_fifty_nodes_plus_start_and_goal :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		// 1 Start + 50 zone nodes + 1 Goal = 52.
		testing.expectf(t, len(m.nodes) == 52, "seed %d: expected 52 nodes, got %d", seed, len(m.nodes))
	}
}

@(test)
per_zone_node_counts_are_17_17_16 :: proc(t: ^testing.T) {
	expected := [Zone]int{.Coastal = 17, .Open_Sea = 17, .Deep = 16}
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		counts: [Zone]int
		for p in m.nodes {
			if zone, ok := p.zone.?; ok {
				counts[zone] += 1
			}
		}
		for zone in Zone {
			testing.expectf(t, counts[zone] == expected[zone], "seed %d: zone %v had %d nodes, want %d", seed, zone, counts[zone], expected[zone])
		}
	}
}

// --- Recipe buckets: derived membership, zone hard-map (#134) ---------------

@(test)
recipe_bucket_membership_is_derived_from_stage_count :: proc(t: ^testing.T) {
	// #134's headline property: a recipe lands in a bucket by being N stages long,
	// with nothing authored to say so and nowhere to say it wrong. Checked against a
	// synthetic catalog rather than the real one, because the real one is still
	// one-stage-only (#138) and would leave the 2- and 3-stage cases untested.
	one := [?]Stage_Spec{{kind = .Fight}}
	two := [?]Stage_Spec{{kind = .Fight}, {kind = .Reward}}
	three := [?]Stage_Spec{{kind = .Offer}, {kind = .Fight}, {kind = .Reward}}
	catalog := [?]Recipe {
		{name = "one-a", stages = one[:]},
		{name = "three", stages = three[:]},
		{name = "two", stages = two[:]},
		{name = "one-b", stages = one[:]},
	}

	cases := [?]struct {
		stage_count: int,
		want:        int,
	}{{1, 2}, {2, 1}, {3, 1}}
	for c in cases {
		bucket := voyage_recipe_bucket(catalog[:], c.stage_count)
		defer delete(bucket)
		testing.expectf(t, len(bucket) == c.want, "the %d-stage bucket holds %d recipes, want %d", c.stage_count, len(bucket), c.want)
		for r in bucket {
			testing.expectf(t, len(r.stages) == c.stage_count, "recipe %q (%d stages) landed in the %d-stage bucket", r.name, len(r.stages), c.stage_count)
		}
	}

	// A bucket no recipe qualifies for is empty, not a fallback: the fallback is
	// voyage_zone_recipe_pool's transitional choice, not the derivation's.
	empty := voyage_recipe_bucket(catalog[:], ENCOUNTER_MAX_STAGES + 1)
	defer delete(empty)
	testing.expect(t, len(empty) == 0, "a stage count no recipe has should derive an empty bucket")
}

@(test)
each_zone_deals_only_its_own_stage_count_bucket :: proc(t: ^testing.T) {
	// ADR-0014's hard mapping (Coastal 1 -> Open_Sea 2 -> Deep 3), asserted where it
	// actually has to hold: on generated maps.
	//
	// **Ports are skipped, and skipping them needs saying out loud now.** The Port
	// bucket is exempt from the mapping — a Port is one stage even in The Deep — and
	// this test used to exclude them with `p.kind != .Encounter`, back when
	// Node_Kind.Port existed to say so. #137 retired that value, and the test kept
	// passing only because every zone's bucket was empty of multi-stage recipes and
	// the `len(bucket) == 0` skip below took the whole zone out. #138 filled the
	// buckets, so the skip is gone and the exemption has to be stated the way
	// everything else asks it: of the stage list (node_port_shop).
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		for p in m.nodes {
			zone, in_zone := p.zone.?
			if !in_zone || p.kind != .Encounter {
				continue // Start/Goal hold nothing.
			}
			if _, is_port := node_port_shop(p); is_port {
				continue // Bespoke-placed and exempt from the zone's stage count.
			}

			encounter, has_encounter := p.encounter.?
			testing.expectf(t, has_encounter, "seed %d: %v node %d holds no encounter", seed, zone, p.id)
			testing.expectf(
				t,
				encounter.count == zone_stage_count[zone],
				"seed %d: %v node %d holds a %d-stage encounter, want %d",
				seed, zone, p.id, encounter.count, zone_stage_count[zone],
			)
		}
	}
}

@(test)
every_zone_has_a_bucket_to_deal_from :: proc(t: ^testing.T) {
	// This replaces multi_stage_buckets_are_empty_until_the_catalog_is_authored,
	// the tripwire that guarded voyage_zone_recipe_pool's 1-stage fallback while the
	// catalog held only the three retired encounter kinds. #138 authored the
	// multi-stage recipes, so both the tripwire and the fallback are gone and the
	// property inverts: every zone's stage-count bucket must now be *non*-empty.
	//
	// voyage_zone_recipe_pool asserts on an empty bucket, so this is what turns
	// emptying a bucket in catalog.odin from a crash on some seed into a named
	// test failure.
	catalog := voyage_recipe_catalog()
	for zone in Zone {
		bucket := voyage_recipe_bucket(catalog, zone_stage_count[zone])
		defer delete(bucket)
		testing.expectf(
			t,
			len(bucket) > 0,
			"%v deals %d-stage encounters but the catalog authors none of that length",
			zone, zone_stage_count[zone],
		)
	}
}

@(test)
costs_precede_boons_in_every_authored_recipe :: proc(t: ^testing.T) {
	// ADR-0014's authoring convention, checked against the table rather than
	// enforced by the type system (#127 chose that deliberately: the gate field can
	// widen later, and a Stage_Spec that could not express `[Offer, Fight]` could
	// not express a future recipe that wants it either).
	//
	// The reason it matters is that a halt is an **exit**. Fight and Trade are the
	// two stages that both cost something and can be declined — Leave Combat halts
	// a Fight, rejecting halts a Trade — so either one sitting *behind* a boon is a
	// free escape from the price of that boon. `[Offer, Fight]` is the canonical
	// mistake: skip an item you never had and the fight is dodged for nothing.
	//
	// Shop is a boon despite spending treasure: it never halts, so it is not an
	// exit, and a captain who buys nothing has lost nothing.
	is_cost :: proc(kind: Stage_Kind) -> bool {
		switch kind {
		case .Fight, .Trade:
			return true
		case .Offer, .Shop, .Reward:
			return false
		}
		unreachable()
	}

	for r in voyage_recipe_catalog() {
		seen_boon: Maybe(Stage_Kind)
		for spec in r.stages {
			if !is_cost(spec.kind) {
				seen_boon = spec.kind
				continue
			}
			boon, after_a_boon := seen_boon.?
			testing.expectf(
				t,
				!after_a_boon,
				"%q authors %v after %v: a declinable cost behind a boon is a free escape from paying for it",
				r.name, spec.kind, boon,
			)
		}
	}
}

@(test)
every_bucket_authors_one_recipe_per_shape :: proc(t: ^testing.T) {
	// Two recipes with the same stage list are the same encounter twice: all
	// variance below the stage list comes from each primitive's own content roster
	// (a Fight's archetype, a Trade's axis, an Offer's items), which is drawn per
	// node and pays no attention to the recipe carrying it. So a duplicate shape
	// would not be a second encounter — it would be a silent frequency weighting on
	// the first, since voyage_make_recipe_bag deals evenly across a pool.
	//
	// **Shape means the kind sequence, and a differing stock pool does not rescue a
	// collision** — which is stricter than it first looks, since a `[Fight, Shop:
	// Ordnance_Hoy]` and a `[Fight, Shop: Menagerie]` really would be two different
	// encounters to play. Nothing downstream can tell them apart: a baked Stage_Shop
	// carries its cards and its count but not the pool that dealt them, and an
	// Encounter does not carry its recipe's name at all, so the two would be one
	// indistinguishable node on the map, in a Ghost_Snapshot, and to recipe_name_of
	// below — which recovers a recipe by matching kinds and has nothing else to
	// match on.
	//
	// So this is a constraint the model imposes rather than one authoring wants, and
	// it is the same gap #139 named: the recipe's name is dropped at bake time. Give
	// an Encounter its name and pool-distinguished shapes become authorable — until
	// then, one recipe per kind sequence.
	catalog := voyage_recipe_catalog()
	for r, i in catalog {
		for other in catalog[i + 1:] {
			same := len(r.stages) == len(other.stages)
			if same {
				for spec, k in r.stages {
					if spec.kind != other.stages[k].kind {
						same = false
						break
					}
				}
			}
			testing.expectf(
				t,
				!same,
				"%q and %q author the same stage kinds: nothing downstream can tell them apart, so that is one encounter twice",
				r.name, other.name,
			)
		}
	}
}

@(test)
every_port_holds_the_one_stage_shop_recipe :: proc(t: ^testing.T) {
	// The Port bucket's bespoke placement (#134): a Port is [Shop] — one stage even
	// in The Deep, where the zone mapping would otherwise demand three — and it is
	// visible on the map because Shop reveals, not because its node kind exempts it.
	//
	// A port is found by **what it holds**, not by its kind: #137 retired Node_Kind.Port,
	// so "is this a port" is asked of the stage list, exactly as the Sim's mask and the
	// map view ask it. Since ADR-0016 that question is sharper than "holds a Shop
	// somewhere" — the merchants author Shops too, behind another stage; what only the
	// Port bucket does is **open** on one, which is the same fact as revealing.
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		for p in m.nodes {
			if _, is_port := node_port_shop(p); !is_port {
				continue
			}
			encounter, has_encounter := p.encounter.?
			testing.expectf(t, has_encounter, "seed %d: port %d holds no encounter", seed, p.id)
			testing.expectf(t, encounter.count == 1, "seed %d: port %d holds %d stages, want the one-stage [Shop]", seed, p.id, encounter.count)
			testing.expectf(t, only_stage_kind(encounter) == .Shop, "seed %d: port %d holds a %v stage, want Shop", seed, p.id, only_stage_kind(encounter))
			testing.expectf(t, voyage_encounter_reveals(encounter), "seed %d: port %d does not reveal itself on the map", seed, p.id)
		}
	}
}

@(test)
the_only_encounters_a_captain_can_see_coming_are_ports :: proc(t: ^testing.T) {
	// ADR-0016's headline consequence, on a real map: the converse of the test above.
	// Ports reveal — and *nothing else does*, so the map is uniformly dark, two known
	// markets per zone and every other node a surprise. Before ADR-0016 an encounter
	// revealed if it held a Shop anywhere, so The Deep (4 of its 5 recipes carry one)
	// showed most of itself and the map's legibility ran backwards: the deepest zone
	// was the best-known one.
	//
	// This is where the ADR's honest cost is observable. What survives the mask is
	// exactly the six Ports, which is Node_Kind.Port derived rather than stored — a
	// constant, but a constant contingent on only_the_port_bucket_opens_on_a_shop,
	// which is an authoring convention. Author one [Shop, Fight] and this test fails
	// rather than the model quietly bending: that failure *is* the contingency, and
	// whether it means fix the recipe or revisit ADR-0016 is the reader's call.
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		revealed := 0
		per_zone: [Zone]int
		for p in m.nodes {
			encounter, has_encounter := p.encounter.?
			if !has_encounter || !voyage_encounter_reveals(encounter) {
				continue
			}
			revealed += 1
			if zone, has_zone := p.zone.?; has_zone {
				per_zone[zone] += 1
			}
			_, is_port := node_port_shop(p)
			testing.expectf(
				t,
				is_port,
				"seed %d: node %d reveals itself but is no port — a merchant a captain can route to",
				seed,
				p.id,
			)
		}
		testing.expectf(t, revealed == PORTS_PER_ZONE * len(Zone), "seed %d: %d encounters revealed, want the ports alone", seed, revealed)
		for count, zone in per_zone {
			testing.expectf(t, count == PORTS_PER_ZONE, "seed %d: %v reveals %d encounters, want its %d ports", seed, zone, count, PORTS_PER_ZONE)
		}
	}
}

@(test)
each_zone_has_exactly_two_ports_within_its_own_phase :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		// A zone's entrance layer is the lowest layer index its nodes occupy.
		zone_entrance := [Zone]int{.Coastal = max(int), .Open_Sea = max(int), .Deep = max(int)}
		for p in m.nodes {
			if zone, ok := p.zone.?; ok {
				zone_entrance[zone] = min(zone_entrance[zone], p.layer)
			}
		}

		port_counts: [Zone]int
		for p in m.nodes {
			if _, is_port := node_port_shop(p); !is_port {
				continue
			}
			zone, ok := p.zone.?
			testing.expectf(t, ok, "seed %d: a port carries no zone", seed)
			if ok {
				port_counts[zone] += 1
				testing.expectf(
					t,
					p.layer != zone_entrance[zone],
					"seed %d: zone %v port at point %d sits on the entrance layer %d",
					seed,
					zone,
					p.id,
					zone_entrance[zone],
				)
			}
		}
		for zone in Zone {
			testing.expectf(t, port_counts[zone] == PORTS_PER_ZONE, "seed %d: zone %v had %d ports, want %d", seed, zone, port_counts[zone], PORTS_PER_ZONE)
		}
	}
}

@(test)
every_port_stocks_its_chandlery_pool_priced_by_tier :: proc(t: ^testing.T) {
	// #137: a port's shop stocks the **Chandlery** pool — the one pool with no family
	// filter, so its candidates are the whole roster — cut to that pool's authored
	// depth, each card priced at its tier and every card distinct.
	//
	// This replaces the pre-#137 assertion that a port's deck *was* the full roster (a
	// permutation of all ITEM_ROSTER_SIZE items). That deck existed because ADR-0013's
	// draw-down persisted across every visit in the run; walked-once encounters (#131)
	// left ~37 of its 50 cards unreachable on every shop of every map. What survives is
	// the property that actually mattered: distinct cards, tier prices, and a shuffle
	// that is a pure function of the seed.
	chandlery := voyage_stock_pool(.Chandlery)
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		for p in m.nodes {
			shop, has_shop := node_port_shop(p)
			if !has_shop {
				continue
			}
			testing.expectf(
				t,
				shop.count == chandlery.depth,
				"seed %d: port %d stocks %d cards, want the Chandlery's %d",
				seed, p.id, shop.count, chandlery.depth,
			)

			// Every card is a real roster item at its own tier's price, and no card
			// repeats — the stock is a sample of a permutation, so a shelf drawn off it
			// never offers the same item twice in one visit.
			for i in 0 ..< shop.count {
				card := shop.stock[i]
				item, found := ship.ship_item_by_name(card.fitting.name)
				testing.expectf(t, found, "seed %d: port %d stocks %q, which is not a roster item", seed, p.id, card.fitting.name)
				testing.expectf(
					t,
					card.cost == ship.ship_item_cost(item.tier),
					"seed %d: port %d card %s priced %d, want %d for tier %v",
					seed, p.id, card.fitting.name, card.cost, ship.ship_item_cost(item.tier), item.tier,
				)
				for j in i + 1 ..< shop.count {
					testing.expectf(
						t,
						card.fitting.name != shop.stock[j].fitting.name,
						"seed %d: port %d stocks %s at both position %d and %d",
						seed, p.id, card.fitting.name, i, j,
					)
				}
			}
		}
	}
}

@(test)
a_chandlery_can_stock_any_roster_item :: proc(t: ^testing.T) {
	// The Chandlery is the *general* store, which is the promise the Port bucket's
	// guaranteed placement makes (#137). "No filter" has to mean the whole roster is
	// reachable, not merely that a lot of it is — so sweep the seeds and check every
	// roster item turns up in some port's stock.
	//
	// This is the assertion that would fail if the Chandlery were authored as "every
	// Tag family" instead of as nil: a sixth Tag, or a tagless item, would silently
	// drop out of the general store and only this sweep would notice.
	seen: map[string]bool
	defer delete(seen)

	for seed in 0 ..< 60 {
		m := voyage_map_create(u64(seed))
		defer voyage_map_destroy(&m)
		for p in m.nodes {
			shop, has_shop := node_port_shop(p)
			if !has_shop {
				continue
			}
			for i in 0 ..< shop.count {
				seen[shop.stock[i].fitting.name] = true
			}
		}
	}

	for r in ship.ship_item_roster() {
		testing.expectf(t, seen[r.fitting.name], "no port in 60 seeds ever stocked %q, which a chandlery should be able to carry", r.fitting.name)
	}
}

@(test)
a_ports_stock_is_deterministic_per_seed :: proc(t: ^testing.T) {
	// #123, ADR-0013: a shop's stock is a pure function of the run seed (no runtime
	// RNG), so the same seed reproduces every Port's stock card-for-card — a seed's
	// shops are fully determined before play, like the rest of map generation. #137
	// shrank the stock to its pool's depth without touching that property.
	a := voyage_map_create(42)
	defer voyage_map_destroy(&a)
	b := voyage_map_create(42)
	defer voyage_map_destroy(&b)

	for pa, i in a.nodes {
		sa, is_port := node_shop(pa)
		if !is_port {
			continue
		}
		sb, _ := node_shop(b.nodes[i])
		testing.expect_value(t, sa.count, sb.count)
		for pos in 0 ..< sa.count {
			testing.expectf(
				t,
				sa.stock[pos].fitting.name == sb.stock[pos].fitting.name && sa.stock[pos].cost == sb.stock[pos].cost,
				"port %d stock position %d differs between two builds of seed 42", pa.id, pos,
			)
		}
	}
}

@(test)
distinct_ports_bake_distinct_stock :: proc(t: ^testing.T) {
	// #123, ADR-0013: each Port owns distinct stock — run variety comes from checking
	// Port against Port — so two Ports must not stock the same cards in the same
	// order. Each is an independent shuffle of the same candidate pool, so a
	// collision across a Chandlery's 12 positions is a ~1/(50·49·…·39) event, i.e.
	// never. This is the property #137's shrink most had to preserve: the Ports of one
	// run are still worth comparing, even though each now holds a twelfth of what it
	// used to.
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		port_ids: [dynamic]Node_ID
		defer delete(port_ids)
		for p in m.nodes {
			if _, is_port := node_port_shop(p); is_port {
				append(&port_ids, p.id)
			}
		}

		for i in 0 ..< len(port_ids) {
			for j in i + 1 ..< len(port_ids) {
				a, _ := node_port_shop(m.nodes[port_ids[i]])
				b, _ := node_port_shop(m.nodes[port_ids[j]])
				identical := true
				for pos in 0 ..< a.count {
					if a.stock[pos].fitting.name != b.stock[pos].fitting.name {
						identical = false
						break
					}
				}
				testing.expectf(t, !identical, "seed %d: ports %d and %d bake identical stock", seed, port_ids[i], port_ids[j])
			}
		}
	}
}

@(test)
recipe_counts_per_zone_are_as_even_as_the_catalog_split_allows :: proc(t: ^testing.T) {
	// voyage_make_recipe_bag deals evenly, so a zone's encounters spread across **its
	// own bucket** to within one.
	//
	// The evenness is measured over the bucket rather than the whole catalog, which
	// is the correction #138 forces: while every recipe was one stage long and the
	// buckets were empty, voyage_zone_recipe_pool's fallback dealt the 1-stage bucket in
	// every zone, so every recipe was expected in every zone and the catalog was the
	// right thing to sweep. Now a recipe lives in exactly one zone — a Sea Battle is
	// Open Sea's and can never be Coastal's — so sweeping the catalog would read
	// every other bucket's recipes as a zone that deals none of them, which is the
	// hard mapping working rather than an uneven deal.
	//
	// Ports are excluded: they are dealt from their own bucket by their own
	// placement, so they are not part of the zone's spread.
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		for zone in Zone {
			counts: map[string]int
			defer delete(counts)
			for p in m.nodes {
				pz, in_zone := p.zone.?
				if !in_zone || pz != zone {
					continue
				}
				if _, is_port := node_port_shop(p); is_port {
					continue
				}
				if enc, ok := p.encounter.?; ok {
					counts[recipe_name_of(enc)] += 1
				}
			}

			bucket := voyage_recipe_bucket(voyage_recipe_catalog(), zone_stage_count[zone])
			defer delete(bucket)
			lo, hi := max(int), 0
			for r in bucket {
				lo = min(lo, counts[r.name])
				hi = max(hi, counts[r.name])
			}
			testing.expectf(t, hi - lo <= 1, "seed %d: zone %v recipe spread %d..%d not even", seed, zone, lo, hi)
		}
	}
}

// recipe_name_of names the catalog recipe a generated encounter was baked from,
// by matching its stage list against each authored entry. A generated Encounter
// doesn't carry its recipe's name — generation bakes the stages and drops the
// authoring label — so the deal-evenness assertion recovers it here rather than
// widening the production type for a test's benefit.
recipe_name_of :: proc(e: Encounter) -> string {
	for r in voyage_recipe_catalog() {
		if len(r.stages) != e.count {
			continue
		}
		matched := true
		for spec, i in r.stages {
			if voyage_stage_kind(e.stages[i]) != spec.kind {
				matched = false
				break
			}
		}
		if matched {
			return r.name
		}
	}
	return ""
}

@(test)
edges_only_connect_the_same_or_an_adjacent_layer :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		for p in m.nodes {
			for v in m.edges[p.id] {
				diff := m.nodes[v].layer - p.layer
				if diff < 0 {
					diff = -diff
				}
				testing.expectf(t, diff <= 1, "seed %d: edge %d-%d spans %d layers", seed, p.id, v, diff)
			}
		}
	}
}

@(test)
forward_out_degree_stays_within_bounds_for_non_start_nodes :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		for p in m.nodes {
			if p.kind == .Start || p.kind == .Goal {
				continue // Start fans out to the whole first layer; Goal has none.
			}
			forward := 0
			for v in m.edges[p.id] {
				if m.nodes[v].layer > p.layer {
					forward += 1
				}
			}
			testing.expectf(t, forward >= 1 && forward <= OUT_DEGREE_MAX, "seed %d: node %d forward out-degree %d out of bounds", seed, p.id, forward)
		}
	}
}

@(test)
voyage_map_create_has_exactly_one_start_and_one_goal_neither_belonging_to_a_zone :: proc(t: ^testing.T) {
	m := voyage_map_create(0)
	defer voyage_map_destroy(&m)

	start_count, goal_count := 0, 0
	for node in m.nodes {
		if node.kind == .Start {
			start_count += 1
			_, has_zone := node.zone.?
			testing.expect(t, !has_zone)
		}
		if node.kind == .Goal {
			goal_count += 1
			_, has_zone := node.zone.?
			testing.expect(t, !has_zone)
		}
	}

	testing.expect_value(t, start_count, 1)
	testing.expect_value(t, goal_count, 1)
}

@(test)
the_same_seed_reproduces_an_identical_map :: proc(t: ^testing.T) {
	a := voyage_map_create(42)
	defer voyage_map_destroy(&a)
	b := voyage_map_create(42)
	defer voyage_map_destroy(&b)

	testing.expect_value(t, len(a.nodes), len(b.nodes))
	for pa, i in a.nodes {
		pb := b.nodes[i]
		testing.expect_value(t, pa.id, pb.id)
		testing.expect_value(t, pa.kind, pb.kind)
		testing.expect_value(t, pa.layer, pb.layer)
		testing.expect_value(t, pa.lane, pb.lane)
		testing.expect_value(t, pa.depth, pb.depth)
		testing.expect_value(t, pa.zone, pb.zone)
		ea, has_a := pa.encounter.?
		eb, has_b := pb.encounter.?
		testing.expect_value(t, has_a, has_b)
		if has_a && has_b {
			testing.expect_value(t, ea.count, eb.count)
			// Every stage, not just the first: this read only_stage_kind while the
			// catalog was one-stage throughout, and #138's multi-stage recipes are
			// what its assert was placed to catch.
			for k in 0 ..< min(ea.count, eb.count) {
				testing.expectf(
					t,
					voyage_stage_kind(ea.stages[k]) == voyage_stage_kind(eb.stages[k]),
					"node %d stage %d differs between two builds of seed 42",
					pa.id, k,
				)
			}
		}
		testing.expect(t, slice.equal(a.edges[i], b.edges[i]))
	}
}

@(test)
a_deeper_ship_battle_in_the_map_is_harder_than_a_shallower_one_in_the_same_zone :: proc(t: ^testing.T) {
	// Sweep seeds until we find a zone holding two Ship Battles at different
	// depths, then confirm the deeper one has the tougher opponent — the
	// spatial danger gradient the depth axis expresses.
	found := false
	for seed in TEST_SEEDS {
		m := voyage_map_create(seed)
		defer voyage_map_destroy(&m)

		for zone in Zone {
			shallow, deep := Node_ID(-1), Node_ID(-1)
			for p in m.nodes {
				pz, in_zone := p.zone.?
				if !in_zone || pz != zone {
					continue
				}
				enc, ok := p.encounter.?
				if !ok {
					continue
				}
				if _, is_fight := only_stage(enc, Stage_Fight); !is_fight {
					continue
				}
				if shallow < 0 || p.depth < m.nodes[shallow].depth {
					shallow = p.id
				}
				if deep < 0 || p.depth > m.nodes[deep].depth {
					deep = p.id
				}
			}
			if shallow >= 0 && deep >= 0 && m.nodes[shallow].depth != m.nodes[deep].depth {
				sb, _ := only_stage(m.nodes[shallow].encounter.?, Stage_Fight)
				db, _ := only_stage(m.nodes[deep].encounter.?, Stage_Fight)
				testing.expect(t, db.opponent.hp > sb.opponent.hp)
				found = true
			}
		}
	}
	testing.expect(t, found)
}

// --- Traversal legality (voyage_travel_options) --------------------------------

// legality_fixture is a tiny hand-wired graph the legality assertions can
// reason about exactly, independent of the generator's randomness:
//   layer 0: 0 (Start)
//   layer 1: 1, 2   (1-2 is a lateral edge)
//   layer 2: 3 (Goal)
// Edges: 0-1, 0-2, 1-2 (lateral), 1-3, 2-3. Its nodes/edges are
// package-level so their backing arrays outlive any single test call (a Map
// returned from a proc with local composite-literal slices would dangle).
legality_nodes := []Node{
	{id = 0, kind = .Start, layer = 0, lane = 0},
	{id = 1, kind = .Encounter, layer = 1, lane = 0},
	{id = 2, kind = .Encounter, layer = 1, lane = 1},
	{id = 3, kind = .Goal, layer = 2, lane = 0},
}
legality_edges := [][]Node_ID{{1, 2}, {0, 2, 3}, {0, 1, 3}, {1, 2}}

legality_fixture :: proc() -> Map {
	return Map{nodes = legality_nodes, edges = legality_edges}
}

// contains_id is the Node_ID counterpart of the generator's int-based
// voyage_contains, used to assert membership in a voyage_travel_options result now
// that those results are []Node_ID (issue #112).
contains_id :: proc(xs: []Node_ID, x: Node_ID) -> bool {
	for e in xs {
		if e == x {
			return true
		}
	}
	return false
}

set_eq :: proc(got: []Node_ID, want: []Node_ID) -> bool {
	if len(got) != len(want) {
		return false
	}
	for w in want {
		if !contains_id(got, w) {
			return false
		}
	}
	return true
}

@(test)
travel_options_offers_forward_and_lateral_always_and_visited_backward :: proc(t: ^testing.T) {
	m := legality_fixture()
	visited := []bool{true, true, false, false} // Start and node 1 visited.

	// From node 1: node 0 (backward, visited) retrace-legal, node 2 (lateral)
	// legal, node 3 (forward) legal.
	opts := voyage_travel_options(m, 1, visited)
	testing.expect(t, set_eq(opts, []Node_ID{0, 2, 3}))
}

@(test)
travel_options_excludes_an_unvisited_backward_neighbor :: proc(t: ^testing.T) {
	m := legality_fixture()
	visited := []bool{false, true, false, false} // Start not yet visited.

	// From node 1: node 0 is backward and unvisited -> excluded; node 2
	// (lateral) and node 3 (forward) remain.
	opts := voyage_travel_options(m, 1, visited)
	testing.expect(t, set_eq(opts, []Node_ID{2, 3}))
}

@(test)
travel_options_offers_a_lateral_edge_in_both_directions :: proc(t: ^testing.T) {
	m := legality_fixture()
	visited := []bool{false, false, false, false}

	from1 := voyage_travel_options(m, 1, visited)
	testing.expect(t, contains_id(from1, 2)) // 1 -> 2 lateral

	from2 := voyage_travel_options(m, 2, visited)
	testing.expect(t, contains_id(from2, 1)) // 2 -> 1 lateral
}

@(test)
can_travel_to_rejects_a_non_adjacent_destination :: proc(t: ^testing.T) {
	m := legality_fixture()
	visited := []bool{true, false, false, false}

	// From Start (0) node 3 is not a neighbor -> never legal, whatever visited.
	testing.expect(t, !voyage_can_travel_to(m, 0, visited, 3))
	// A real neighbor is legal.
	testing.expect(t, voyage_can_travel_to(m, 0, visited, 1))
}

// --- Encounter resolution + status (unchanged contracts) --------------------

@(test)
voyage_start_battle_hands_off_to_combat_with_the_ship_and_the_fight_stages_opponent :: proc(t: ^testing.T) {
	player := ship.Ship{hp = 20, speed = 5}
	fight := Stage_Fight{opponent = ship.Ship{hp = 10, speed = 3}}

	battle := voyage_start_battle(&player, &fight)

	testing.expect_value(t, battle.ships[.A], &player)
	testing.expect_value(t, battle.ships[.B], &fight.opponent)

	events: [dynamic]combat.Event
	defer delete(events)
	cmds: [combat.Side]Maybe(combat.Command)
	combat.combat_resolve_round(&battle, cmds, &events)
	testing.expect_value(t, battle.round, 1)
}

// battle_ended_with is an ended Battle whose escape record is stated outright, so
// the outcome tests below read as "this ending means that outcome" without
// resolving real rounds to arrange one. The ships are incidental — the *outcome* is
// read off `escaped` alone.
//
// A stated ending needs a stated reason now that voyage_finish_ship_battle reads it to
// decide the wreck payout (#159): an escape is Left_Combat, and a no-escape
// completion is modelled as a round-cap stalemate. Neither pays out — which is
// exactly what these escape→outcome tests want; the paying case (a kill) is set up
// by battle_destroyed_won_by_the_player below.
battle_ended_with :: proc(escaped: bit_set[combat.Side], player: ^ship.Ship, fight: ^Stage_Fight) -> combat.Battle {
	battle := voyage_start_battle(player, fight)
	battle.ended = true
	battle.escaped = escaped
	battle.reason = .Left_Combat if escaped != {} else .Round_Cap
	return battle
}

// battle_destroyed_won_by_the_player is an ended Battle the player sank the
// opponent in (#159's paying case): reason Destroyed, winner .A. The ships are *not*
// incidental here — the payout reads the opponent's hold, so the caller stocks it.
battle_destroyed_won_by_the_player :: proc(player: ^ship.Ship, fight: ^Stage_Fight) -> combat.Battle {
	battle := voyage_start_battle(player, fight)
	battle.ended = true
	battle.reason = .Destroyed
	battle.winner = combat.Side.A
	return battle
}

@(test)
voyage_finish_ship_battle_completes_the_fight_when_nobody_escaped :: proc(t: ^testing.T) {
	player := ship.Ship{hp = 20, max_hp = 20, speed = 5}
	fight := Stage_Fight{opponent = ship.Ship{hp = 10, speed = 3}}
	battle := battle_ended_with({}, &player, &fight)

	// A round-cap stalemate: the fight is over, and it pays nothing (#159 — only a
	// wreck pays; a draw leaves no wreck).
	outcome, payout := voyage_finish_ship_battle(&battle)
	testing.expect_value(t, outcome, Stage_Outcome.Completed)
	testing.expect_value(t, payout, 0)
}

@(test)
voyage_finish_ship_battle_halts_the_encounter_when_the_captain_took_leave_combat :: proc(t: ^testing.T) {
	player := ship.Ship{hp = 20, max_hp = 20, speed = 5}
	fight := Stage_Fight{opponent = ship.Ship{hp = 10, speed = 3}}
	battle := battle_ended_with({.A}, &player, &fight)

	// Fight's halt condition (ADR-0014): flee a [Fight, Reward] and the loot stage
	// downstream of the Fight is never reached, with no authored gate saying so.
	outcome, _ := voyage_finish_ship_battle(&battle)
	testing.expect_value(t, outcome, Stage_Outcome.Halted)
}

@(test)
voyage_finish_ship_battle_completes_the_fight_when_the_opponent_escaped :: proc(t: ^testing.T) {
	player := ship.Ship{hp = 20, max_hp = 20, speed = 5}
	// The opponent has a laden hold, but flees rather than sinking — so it is not a
	// wreck, and pays nothing (#159: you loot a wreck, not a winner nor a runner).
	fight := Stage_Fight{opponent = ship.Ship{hp = 10, speed = 3, layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Medium}}}}}
	ship.ship_stow_treasure(fight.opponent.layout, 15)
	battle := battle_ended_with({.B}, &player, &fight)

	// Side.B fleeing is not the captain declining the fight, so it reads as the fight
	// being over rather than as a halt — the asymmetry that makes the halt *the
	// captain's* choice, and the reason this is read off `escaped` per side rather
	// than off "did anyone escape".
	outcome, payout := voyage_finish_ship_battle(&battle)
	testing.expect_value(t, outcome, Stage_Outcome.Completed)
	testing.expect_value(t, payout, 0)
}

@(test)
voyage_finish_ship_battle_on_a_battle_that_has_not_ended_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	player := ship.Ship{hp = 20, max_hp = 20, speed = 5}
	fight := Stage_Fight{opponent = ship.Ship{hp = 10, speed = 3}}
	battle := voyage_start_battle(&player, &fight)

	testing.expect_assert(t, "voyage_finish_ship_battle called before the battle ended")
	voyage_finish_ship_battle(&battle)
}

@(test)
voyage_finish_ship_battle_pays_the_sunk_opponents_hold_into_the_player :: proc(t: ^testing.T) {
	// A wreck pays its hold as it stands (#159): the player receives exactly the
	// treasure still stowed in the sunk opponent's cargo slots.
	player := ship.Ship {
		hp = 20, max_hp = 20,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}}, {slot = ship.Slot{size = .Small}}},
	}
	ship.ship_stow_treasure(player.layout, 10) // room for 50 (Large 40 + Small 10), 10 aboard
	fight := Stage_Fight {
		opponent = ship.Ship{layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Medium}}, {slot = ship.Slot{size = .Small}}}},
	}
	ship.ship_stow_treasure(fight.opponent.layout, 30)
	battle := battle_destroyed_won_by_the_player(&player, &fight)

	outcome, payout := voyage_finish_ship_battle(&battle)

	testing.expect_value(t, outcome, Stage_Outcome.Completed)
	testing.expect_value(t, payout, 30) // the whole wreck's hold
	testing.expect_value(t, ship.ship_treasure(player), 40) // 10 aboard + 30 looted, within capacity
	testing.expect_value(t, ship.ship_treasure(fight.opponent), 30) // the wreck's hold is read, never emptied
}

@(test)
voyage_finish_ship_battle_payout_above_capacity_falls_overboard :: proc(t: ^testing.T) {
	// The mainline case (#157, #176): a near-full player wins a Fight, and the part of
	// the payout that will not fit in the holds is lost, not banked. payout is the
	// gross hold looted; what the player keeps is capped at capacity.
	player := ship.Ship {
		hp = 20, max_hp = 20,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}}, {slot = ship.Slot{size = .Small}}},
	}
	ship.ship_stow_treasure(player.layout, 45) // capacity 50, only 5 of room left
	fight := Stage_Fight {
		opponent = ship.Ship{layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Medium}}, {slot = ship.Slot{size = .Small}}}},
	}
	ship.ship_stow_treasure(fight.opponent.layout, 30)
	battle := battle_destroyed_won_by_the_player(&player, &fight)

	outcome, payout := voyage_finish_ship_battle(&battle)

	testing.expect_value(t, outcome, Stage_Outcome.Completed)
	testing.expect_value(t, payout, 30) // the gross hold looted, before the ship's capacity clips it
	testing.expect_value(t, ship.ship_treasure(player), 50) // clamped to capacity — the other 25 went overboard
}

@(test)
voyage_finish_ship_battle_a_kill_of_a_broke_opponent_pays_nothing :: proc(t: ^testing.T) {
	// A wreck with an empty hold pays 0, and that is not a special case — a sinking
	// pays whatever is aboard, which may be nothing.
	player := ship.Ship {
		hp = 20, max_hp = 20,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}}},
	}
	fight := Stage_Fight{opponent = ship.Ship{layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}}}}}
	battle := battle_destroyed_won_by_the_player(&player, &fight)

	outcome, payout := voyage_finish_ship_battle(&battle)

	testing.expect_value(t, outcome, Stage_Outcome.Completed)
	testing.expect_value(t, payout, 0)
	testing.expect_value(t, ship.ship_treasure(player), 0)
}

// --- Trade: applying an accepted swap (issue #136) --------------------------

// trade_of is a baked Stage_Trade with the magnitudes stated outright, so the
// apply tests below read as "this much for that much" without a Scaling_Site
// standing between the test and the numbers it asserts.
trade_of :: proc(gain: Trade_Stat, gain_amount: int, cost: Trade_Stat, cost_amount: int) -> Stage_Trade {
	return Stage_Trade{
		name = "Test Bargain",
		gain = Trade_Term{stat = gain, amount = gain_amount},
		cost = Trade_Term{stat = cost, amount = cost_amount},
	}
}

@(test)
voyage_apply_trade_permanently_swaps_the_cost_stat_for_the_gain_stat :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20, max_hp = 20, durability = 2}

	voyage_apply_trade(&s, trade_of(.Durability, 3, .Max_HP, 1))

	testing.expect_value(t, s.durability, 5)
	testing.expect_value(t, s.max_hp, 19)
}

// The axis is data now, so the *inverse* trade must work as well as the original
// — that's the whole of what unwelding bought.
@(test)
voyage_apply_trade_runs_an_axis_in_either_direction :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20, max_hp = 20, durability = 5}

	voyage_apply_trade(&s, trade_of(.Max_HP, 2, .Durability, 3))

	testing.expect_value(t, s.max_hp, 22)
	testing.expect_value(t, s.durability, 2)
}

@(test)
voyage_apply_trade_moves_treasure :: proc(t: ^testing.T) {
	// Treasure is the holds now (ADR-0020), so a treasure trade moves cargo — the
	// starting ship carries its 50 purse in real slots (capacity 90, room to gain).
	s := ship.ship_starting_ship()
	defer delete(s.layout)
	s.durability = 4
	testing.expect_value(t, ship.ship_treasure(s), 50)

	voyage_apply_trade(&s, trade_of(.Treasure, 15, .Durability, 2))

	testing.expect_value(t, ship.ship_treasure(s), 65)
	testing.expect_value(t, s.durability, 2)
}

// Scrapped Armour (gain .Treasure, cost .Durability) picked up two side effects
// when treasure became weight (ADR-0020, #199), and both are the honest, intended
// cost of the axis rather than a bug to guard:
//
//   - Its Treasure gain can **overflow the hold and be silently lost** — a Trade
//     that burns its own payout. That is #157's rule with no special case (treasure
//     lives only in finite slots; there is nowhere else to bank it), so the grant
//     path is left un-guarded on purpose (the cost side is gated by
//     voyage_trade_can_accept; the gain side is not).
//   - Because treasure *is* weight, gaining it **slows the ship** — the destination's
//     own thesis (getting rich makes you catchable), not an unadvertised penalty.
//
// A Trade is an accept/reject choice, so a full ship that burns the payout chose to;
// letting the player *read* that risk off the hold before accepting is the UI pass's
// job (#201/#202), not a model guard here.
@(test)
voyage_apply_trade_scrapped_armour_gain_above_capacity_is_lost :: proc(t: ^testing.T) {
	s := ship.ship_starting_ship() // capacity 90, purse 50, effective Speed 4
	defer delete(s.layout)
	s.durability = 4
	speed_before := ship.ship_effective_speed(&s)

	// Sell armour for 60 treasure against a 90 ceiling with only 40 of room: 20 of
	// the payout has no slot to land in and is dropped, not banked in a scalar.
	voyage_apply_trade(&s, trade_of(.Treasure, 60, .Durability, 2))

	testing.expect_value(t, ship.ship_treasure(s), 90) // capped at capacity, not the 110 gained
	testing.expect_value(t, s.durability, 2)            // yet the cost is still paid in full
	// The heavier hold is slower: the incidental Speed swing is intentional (ADR-0020).
	testing.expect(t, ship.ship_effective_speed(&s) < speed_before)
}

// Cannibalized Timbers (+HP for -Max HP) is why the pay-then-grant order is
// load-bearing: selling the ceiling first means the repair caps against the
// ceiling you just sold. 12 HP of a 20 ceiling, sell 6 of the ceiling, then
// repair 8 — the repair stops at the new ceiling of 14, not the old 20.
@(test)
voyage_apply_trade_pays_before_granting_so_a_repair_caps_against_the_sold_ceiling :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 12, max_hp = 20}

	voyage_apply_trade(&s, trade_of(.HP, 8, .Max_HP, 6))

	testing.expect_value(t, s.max_hp, 14)
	testing.expect_value(t, s.hp, 14)
}

@(test)
voyage_apply_trade_never_overheals :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 18, max_hp = 20, durability = 4}

	voyage_apply_trade(&s, trade_of(.HP, 10, .Durability, 1))

	testing.expect_value(t, s.hp, 20)
}

// Gaining Max HP is headroom, not a repair — the two stats stay distinct
// precisely so an entry can trade one for the other.
@(test)
voyage_apply_trade_gaining_max_hp_raises_the_ceiling_without_filling_it :: proc(t: ^testing.T) {
	s := ship.ship_starting_ship()
	defer delete(s.layout)
	s.hp = 12
	s.max_hp = 20

	voyage_apply_trade(&s, trade_of(.Max_HP, 5, .Treasure, 15))

	testing.expect_value(t, s.max_hp, 25)
	testing.expect_value(t, s.hp, 12)
	testing.expect_value(t, ship.ship_treasure(s), 35)
}

// Spending Max HP below current HP can't leave the ship holding more HP than it
// can now hold.
@(test)
voyage_apply_trade_paying_max_hp_pulls_current_hp_down_to_the_new_ceiling :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20, max_hp = 20, durability = 1}

	voyage_apply_trade(&s, trade_of(.Durability, 2, .Max_HP, 8))

	testing.expect_value(t, s.max_hp, 12)
	testing.expect_value(t, s.hp, 12)
}

// --- Trade: affordability (issue #136) --------------------------------------

@(test)
voyage_trade_can_accept_refuses_a_cost_that_would_break_the_floor :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20, max_hp = 20, durability = 4}

	// Durability floors at 0, so spending exactly all of it is still a trade...
	testing.expect(t, voyage_trade_can_accept(&s, trade_of(.Max_HP, 8, .Durability, 4)))
	// ...but one more than the ship has is not.
	testing.expect(t, !voyage_trade_can_accept(&s, trade_of(.Max_HP, 8, .Durability, 5)))
}

// HP and Max HP floor at 1: a trade is a bargain on a menu and must not be able
// to sink the ship there.
@(test)
voyage_trade_can_accept_never_lets_a_trade_sink_the_ship :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 10, max_hp = 10, durability = 1}

	testing.expect(t, voyage_trade_can_accept(&s, trade_of(.Durability, 1, .HP, 9)))
	testing.expect(t, !voyage_trade_can_accept(&s, trade_of(.Durability, 1, .HP, 10)))
	testing.expect(t, voyage_trade_can_accept(&s, trade_of(.Durability, 1, .Max_HP, 9)))
	testing.expect(t, !voyage_trade_can_accept(&s, trade_of(.Durability, 1, .Max_HP, 10)))
}

// The ADR-0012 constraint the ticket names: a trade reads the **effective** stat,
// never the raw base field. A fitting granting +3 Durability makes a cost of 5
// affordable on a base of 2 — and paying it out of the base leaves that base
// negative, which is fine, because effective (0) is the number combat resolves
// against and it is still at the floor.
@(test)
voyage_trade_measures_the_cost_against_the_effective_stat_not_the_base_field :: proc(t: ^testing.T) {
	plating := ship.Fitting{
		name    = "Test Plating",
		size    = .Small,
		passive = ship.Effect{kind = .Modify_Durability, magnitude = 3},
	}
	s := ship.Ship{
		hp = 20, max_hp = 20, durability = 2,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = plating}},
	}
	testing.expect_value(t, ship.ship_effective_durability(&s), 5)

	// The base alone (2) could never pay 5; the fitting's contribution is what
	// makes it affordable.
	testing.expect(t, voyage_trade_can_accept(&s, trade_of(.Max_HP, 1, .Durability, 5)))
	voyage_apply_trade(&s, trade_of(.Max_HP, 1, .Durability, 5))

	testing.expect_value(t, s.durability, -3) // the base field went negative...
	testing.expect_value(t, ship.ship_effective_durability(&s), 0) // ...and effective landed on the floor.
	testing.expect_value(t, s.max_hp, 21)
}

@(test)
voyage_apply_trade_asserts_on_a_trade_the_ship_cannot_pay_for :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}
	s := ship.Ship{hp = 20, max_hp = 20, durability = 2}

	voyage_apply_trade(&s, trade_of(.Max_HP, 8, .Durability, 5))

	testing.expect_assert(t, "voyage_apply_trade on a trade the ship cannot pay for")
}

@(test)
voyage_status_is_won_when_the_ship_reaches_goal_with_positive_hp :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 1}
	goal := Node{kind = .Goal}

	testing.expect_value(t, voyage_status(&s, goal), Voyage_Status.Won)
}

@(test)
voyage_status_is_lost_when_hp_reaches_zero_even_at_the_goal :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 0}
	goal := Node{kind = .Goal}

	testing.expect_value(t, voyage_status(&s, goal), Voyage_Status.Lost)
}

@(test)
voyage_status_is_in_progress_away_from_goal_with_positive_hp :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20}
	encounter_node := Node{kind = .Encounter}

	testing.expect_value(t, voyage_status(&s, encounter_node), Voyage_Status.In_Progress)
}

@(test)
voyage_can_travel_is_false_once_hp_reaches_zero :: proc(t: ^testing.T) {
	sunk := ship.Ship{hp = 0}
	afloat := ship.Ship{hp = 1}

	testing.expect(t, !voyage_can_travel(&sunk))
	testing.expect(t, voyage_can_travel(&afloat))
}
