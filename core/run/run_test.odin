package run

import "../combat"
import "../ship"
import "../testutil"
import "core:slice"
import "core:testing"

// only_stage_kind returns the primitive of e's single stage, asserting that e
// has exactly one. Every recipe in today's catalog is a one-stage port of a
// retired encounter kind (catalog.odin), so the generator assertions below can
// still talk about "this node's kind" — but they say so through the stage list
// rather than a kind tag, and they fail loudly rather than silently reading
// stage 0 once #138 authors multi-stage recipes.
only_stage_kind :: proc(e: Encounter) -> Stage_Kind {
	assert(e.count == 1, "only_stage_kind on a multi-stage encounter — this assertion predates the multi-stage catalog (#138)")
	return run_stage_kind(e.stages[0])
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

// node_shop returns the Shop stage p's encounter holds, or ok=false for a node
// that holds no encounter or no Shop within it. A Port's stock is a stage rather
// than a field on the Node (#134), so "does this node carry a shop" is now a
// question asked of its stage list — which is what the assertions below check.
//
// First match wins: no authored recipe carries two Shops, and a recipe that did
// would be two shops at one node, which is a content question (#138) and not this
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

// --- Stakes formulas: zone tier x depth ------------------------------------

expect_rises_by_zone_and_depth :: proc(t: ^testing.T, f: proc(Scaling_Site) -> int) {
	// A deeper zone at the same depth stakes more...
	testing.expect(t, f(Scaling_Site{zone = .Deep, depth = 0}) > f(Scaling_Site{zone = .Coastal, depth = 0}))
	// ...and within a zone, a deeper node outscales a shallow one.
	testing.expect(t, f(Scaling_Site{zone = .Open_Sea, depth = DEPTH_STEPS}) > f(Scaling_Site{zone = .Open_Sea, depth = 0}))
}

@(test)
fight_opponent_hp_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, run_fight_opponent_hp)
}

@(test)
fight_opponent_durability_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, run_fight_opponent_durability)
}

@(test)
fight_opponent_offense_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, run_fight_opponent_offense)
}

@(test)
offer_item_quality_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, run_offer_item_quality)
}

// The Trade primitive's reading is keyed by stat rather than by side (issue
// #136), so it can't go through expect_rises_by_zone_and_depth's
// proc(Scaling_Site) shape. Every stat must scale, not just the two the welded
// axis happened to name: a roster entry can put any stat on either side, so a
// stat whose swing ignored the site would be a trade with a stakes-blind half.
@(test)
trade_swing_rises_by_zone_and_depth_for_every_stat :: proc(t: ^testing.T) {
	for stat in Trade_Stat {
		testing.expectf(
			t,
			run_trade_swing(Scaling_Site{zone = .Deep, depth = 0}, stat) >
			run_trade_swing(Scaling_Site{zone = .Coastal, depth = 0}, stat),
			"%v's swing must rise with zone tier",
			stat,
		)
		testing.expectf(
			t,
			run_trade_swing(Scaling_Site{zone = .Open_Sea, depth = DEPTH_STEPS}, stat) >
			run_trade_swing(Scaling_Site{zone = .Open_Sea, depth = 0}, stat),
			"%v's swing must rise with depth-within-zone",
			stat,
		)
	}
}

@(test)
reward_treasure_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	// #133's acceptance in one line: a Deep reward outweighs a Coastal one.
	expect_rises_by_zone_and_depth(t, run_reward_treasure)
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
				run_reward_treasure(site) > run_trade_swing(site, .Treasure),
				"a reward at %v must outpay selling a stat there",
				site,
			)
		}
	}
}

@(test)
run_make_opponent_ship_sets_both_hp_and_durability_from_zone_and_depth :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Deep, depth = 2}
	opponent := run_make_opponent_ship(site)

	testing.expect_value(t, opponent.hp, run_fight_opponent_hp(site))
	testing.expect_value(t, opponent.durability, run_fight_opponent_durability(site))
}

// The primitives all read one gradient, so their readings must stay
// distinguishable — otherwise a shared table would be indistinguishable from
// each primitive owning its own constants.
@(test)
the_primitives_readings_of_one_site_land_on_distinguishable_magnitudes :: proc(t: ^testing.T) {
	coastal := Scaling_Site{zone = .Coastal, depth = 0}
	testing.expect(t, run_fight_opponent_hp(coastal) != run_offer_item_quality(coastal))
	testing.expect(t, run_fight_opponent_hp(coastal) != run_trade_swing(coastal, .Durability))
	testing.expect(t, run_offer_item_quality(coastal) != run_trade_swing(coastal, .Durability))
}

// --- Depth normalization: stable endpoints regardless of layer count -------

@(test)
depth_normalization_maps_shallow_and_deep_to_stable_endpoints :: proc(t: ^testing.T) {
	// The shallowest layer always normalizes to 0 and the deepest to
	// DEPTH_STEPS, whether the zone rolled 3 layers or 5.
	testing.expect_value(t, run_normalize_depth(0, 3), 0)
	testing.expect_value(t, run_normalize_depth(2, 3), DEPTH_STEPS)
	testing.expect_value(t, run_normalize_depth(0, 5), 0)
	testing.expect_value(t, run_normalize_depth(4, 5), DEPTH_STEPS)
	// A single-layer zone collapses to 0 (no division by zero).
	testing.expect_value(t, run_normalize_depth(0, 1), 0)
}

@(test)
run_node_is_port_is_true_for_start_and_zone_ports_but_not_encounter_or_goal :: proc(t: ^testing.T) {
	testing.expect(t, run_node_is_port(Node{kind = .Start}))
	testing.expect(t, run_node_is_port(Node{kind = .Port}))
	testing.expect(t, !run_node_is_port(Node{kind = .Encounter}))
	testing.expect(t, !run_node_is_port(Node{kind = .Goal}))
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
		m := run_map_create(seed)
		defer run_map_destroy(&m)

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
		m := run_map_create(seed)
		defer run_map_destroy(&m)

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
run_map_create_has_fifty_nodes_plus_start_and_goal :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		m := run_map_create(seed)
		defer run_map_destroy(&m)

		// 1 Start + 50 zone nodes + 1 Goal = 52.
		testing.expectf(t, len(m.nodes) == 52, "seed %d: expected 52 nodes, got %d", seed, len(m.nodes))
	}
}

@(test)
per_zone_node_counts_are_17_17_16 :: proc(t: ^testing.T) {
	expected := [Zone]int{.Coastal = 17, .Open_Sea = 17, .Deep = 16}
	for seed in TEST_SEEDS {
		m := run_map_create(seed)
		defer run_map_destroy(&m)

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
	one := [?]Stage_Kind{.Fight}
	two := [?]Stage_Kind{.Fight, .Reward}
	three := [?]Stage_Kind{.Offer, .Fight, .Reward}
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
		bucket := run_recipe_bucket(catalog[:], c.stage_count)
		defer delete(bucket)
		testing.expectf(t, len(bucket) == c.want, "the %d-stage bucket holds %d recipes, want %d", c.stage_count, len(bucket), c.want)
		for r in bucket {
			testing.expectf(t, len(r.stages) == c.stage_count, "recipe %q (%d stages) landed in the %d-stage bucket", r.name, len(r.stages), c.stage_count)
		}
	}

	// A bucket no recipe qualifies for is empty, not a fallback: the fallback is
	// run_zone_recipe_pool's transitional choice, not the derivation's.
	empty := run_recipe_bucket(catalog[:], ENCOUNTER_MAX_STAGES + 1)
	defer delete(empty)
	testing.expect(t, len(empty) == 0, "a stage count no recipe has should derive an empty bucket")
}

@(test)
each_zone_deals_only_its_own_stage_count_bucket :: proc(t: ^testing.T) {
	// ADR-0014's hard mapping (Coastal 1 -> Open_Sea 2 -> Deep 3), asserted where it
	// actually has to hold: on generated maps. A zone whose bucket is still empty
	// deals the 1-stage fallback (run_zone_recipe_pool) and is skipped here — the
	// tripwire below is what makes that skip temporary.
	catalog := run_recipe_catalog()
	for seed in TEST_SEEDS {
		m := run_map_create(seed)
		defer run_map_destroy(&m)

		for p in m.nodes {
			zone, in_zone := p.zone.?
			if !in_zone || p.kind != .Encounter {
				continue // Start/Goal hold nothing; a .Port is bespoke-placed and exempt.
			}
			bucket := run_recipe_bucket(catalog, zone_stage_count[zone])
			defer delete(bucket)
			if len(bucket) == 0 {
				continue
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
multi_stage_buckets_are_empty_until_the_catalog_is_authored :: proc(t: ^testing.T) {
	// A tripwire, not a property: the catalog is still the three one-stage recipes
	// ADR-0014 retired the encounter kinds into, so Open_Sea and The Deep deal
	// run_zone_recipe_pool's 1-stage fallback rather than their own buckets.
	//
	// **When #138 authors the multi-stage recipes, this test fails — that is its
	// whole job.** Delete it, and delete the fallback in run_zone_recipe_pool with
	// it: an empty bucket is a content bug from that point on, and it should assert
	// rather than quietly deal Coastal's encounters in The Deep.
	catalog := run_recipe_catalog()
	for stage_count in 2 ..= ENCOUNTER_MAX_STAGES {
		bucket := run_recipe_bucket(catalog, stage_count)
		defer delete(bucket)
		testing.expectf(
			t,
			len(bucket) == 0,
			"the %d-stage bucket now holds %d recipes — #138 has landed, so delete this test and run_zone_recipe_pool's fallback",
			stage_count, len(bucket),
		)
	}
}

@(test)
every_port_holds_the_one_stage_shop_recipe :: proc(t: ^testing.T) {
	// The Port bucket's bespoke placement (#134): a Port is [Shop] — one stage even
	// in The Deep, where the zone mapping would otherwise demand three — and it is
	// visible on the map because Shop reveals, not because its node kind exempts it.
	for seed in TEST_SEEDS {
		m := run_map_create(seed)
		defer run_map_destroy(&m)

		for p in m.nodes {
			if p.kind != .Port {
				continue
			}
			encounter, has_encounter := p.encounter.?
			testing.expectf(t, has_encounter, "seed %d: port %d holds no encounter", seed, p.id)
			testing.expectf(t, encounter.count == 1, "seed %d: port %d holds %d stages, want the one-stage [Shop]", seed, p.id, encounter.count)
			testing.expectf(t, only_stage_kind(encounter) == .Shop, "seed %d: port %d holds a %v stage, want Shop", seed, p.id, only_stage_kind(encounter))
			testing.expectf(t, run_encounter_reveals(encounter), "seed %d: port %d does not reveal itself on the map", seed, p.id)
		}
	}
}

@(test)
each_zone_has_exactly_two_ports_within_its_own_phase :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		m := run_map_create(seed)
		defer run_map_destroy(&m)

		// A zone's entrance layer is the lowest layer index its nodes occupy.
		zone_entrance := [Zone]int{.Coastal = max(int), .Open_Sea = max(int), .Deep = max(int)}
		for p in m.nodes {
			if zone, ok := p.zone.?; ok {
				zone_entrance[zone] = min(zone_entrance[zone], p.layer)
			}
		}

		port_counts: [Zone]int
		for p in m.nodes {
			if p.kind != .Port {
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
every_port_bakes_a_full_roster_deck_priced_by_tier :: proc(t: ^testing.T) {
	// #123, ADR-0013: every port bakes a Shop whose deck is the *full* roster — a
	// permutation, so every roster item appears exactly once — each card priced at
	// its tier; no other node carries a shop. Unchanged by #134 except in where the
	// deck lives: it is the port's [Shop] stage's baked content now, dealt with its
	// recipe, so this asserts the fold from the old step-6 stocking pass preserved
	// the deck's shape.
	roster := ship.ship_item_roster()
	for seed in TEST_SEEDS {
		m := run_map_create(seed)
		defer run_map_destroy(&m)

		for p in m.nodes {
			shop, has_shop := node_shop(p)
			if p.kind != .Port {
				testing.expectf(t, !has_shop, "seed %d: a %v node carries a shop", seed, p.kind)
				continue
			}
			testing.expectf(t, has_shop, "seed %d: port %d carries no shop", seed, p.id)
			testing.expectf(
				t,
				len(shop.deck) == ship.ITEM_ROSTER_SIZE,
				"seed %d: port %d deck has %d cards, want the full roster of %d",
				seed, p.id, len(shop.deck), ship.ITEM_ROSTER_SIZE,
			)

			// The deck is a permutation of the roster: every roster item is present
			// exactly once, and each card is priced at its own tier.
			for r in roster {
				seen := 0
				for card in shop.deck {
					if card.fitting.name != r.fitting.name {
						continue
					}
					seen += 1
					testing.expectf(
						t,
						card.cost == ship.ship_item_cost(r.tier),
						"seed %d: port %d card %s priced %d, want %d for tier %v",
						seed, p.id, card.fitting.name, card.cost, ship.ship_item_cost(r.tier), r.tier,
					)
				}
				testing.expectf(t, seen == 1, "seed %d: port %d holds %s %d times, want exactly once", seed, p.id, r.fitting.name, seen)
			}
		}
	}
}

@(test)
a_ports_deck_is_deterministic_per_seed :: proc(t: ^testing.T) {
	// #123, ADR-0013: a deck is a pure function of the run seed (no runtime RNG), so
	// the same seed reproduces every Port's deck card-for-card — a seed's shops are
	// fully determined before play, like the rest of map generation.
	a := run_map_create(42)
	defer run_map_destroy(&a)
	b := run_map_create(42)
	defer run_map_destroy(&b)

	for pa, i in a.nodes {
		sa, is_port := node_shop(pa)
		if !is_port {
			continue
		}
		sb, _ := node_shop(b.nodes[i])
		for pos in 0 ..< len(sa.deck) {
			testing.expectf(
				t,
				sa.deck[pos].fitting.name == sb.deck[pos].fitting.name && sa.deck[pos].cost == sb.deck[pos].cost,
				"port %d deck position %d differs between two builds of seed 42", pa.id, pos,
			)
		}
	}
}

@(test)
distinct_ports_bake_distinct_decks :: proc(t: ^testing.T) {
	// #123, ADR-0013: each Port owns a distinct deck — run variety comes from
	// checking Port against Port — so two Ports' decks must not be identically
	// ordered. Decks are independent shuffles of the same roster (a permutation
	// collision is a ~1/ITEM_ROSTER_SIZE! event, i.e. never), so any two differ.
	for seed in TEST_SEEDS {
		m := run_map_create(seed)
		defer run_map_destroy(&m)

		port_ids: [dynamic]Node_ID
		defer delete(port_ids)
		for p in m.nodes {
			if p.kind == .Port {
				append(&port_ids, p.id)
			}
		}

		for i in 0 ..< len(port_ids) {
			for j in i + 1 ..< len(port_ids) {
				a, _ := node_shop(m.nodes[port_ids[i]])
				b, _ := node_shop(m.nodes[port_ids[j]])
				identical := true
				for pos in 0 ..< len(a.deck) {
					if a.deck[pos].fitting.name != b.deck[pos].fitting.name {
						identical = false
						break
					}
				}
				testing.expectf(t, !identical, "seed %d: ports %d and %d bake identical decks", seed, port_ids[i], port_ids[j])
			}
		}
	}
}

@(test)
recipe_counts_per_zone_are_as_even_as_the_catalog_split_allows :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		m := run_map_create(seed)
		defer run_map_destroy(&m)

		for zone in Zone {
			counts: map[string]int
			defer delete(counts)
			for p in m.nodes {
				pz, in_zone := p.zone.?
				if !in_zone || pz != zone {
					continue
				}
				if enc, ok := p.encounter.?; ok {
					counts[recipe_name_of(enc)] += 1
				}
			}
			lo, hi := max(int), 0
			for r in run_recipe_catalog() {
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
	for r in run_recipe_catalog() {
		if len(r.stages) != e.count {
			continue
		}
		matched := true
		for kind, i in r.stages {
			if run_stage_kind(e.stages[i]) != kind {
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
		m := run_map_create(seed)
		defer run_map_destroy(&m)

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
		m := run_map_create(seed)
		defer run_map_destroy(&m)

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
run_map_create_has_exactly_one_start_and_one_goal_neither_belonging_to_a_zone :: proc(t: ^testing.T) {
	m := run_map_create(0)
	defer run_map_destroy(&m)

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
	a := run_map_create(42)
	defer run_map_destroy(&a)
	b := run_map_create(42)
	defer run_map_destroy(&b)

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
			testing.expect_value(t, only_stage_kind(ea), only_stage_kind(eb))
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
		m := run_map_create(seed)
		defer run_map_destroy(&m)

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

// --- Traversal legality (run_travel_options) --------------------------------

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
// run_contains, used to assert membership in a run_travel_options result now
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
	opts := run_travel_options(m, 1, visited)
	testing.expect(t, set_eq(opts, []Node_ID{0, 2, 3}))
}

@(test)
travel_options_excludes_an_unvisited_backward_neighbor :: proc(t: ^testing.T) {
	m := legality_fixture()
	visited := []bool{false, true, false, false} // Start not yet visited.

	// From node 1: node 0 is backward and unvisited -> excluded; node 2
	// (lateral) and node 3 (forward) remain.
	opts := run_travel_options(m, 1, visited)
	testing.expect(t, set_eq(opts, []Node_ID{2, 3}))
}

@(test)
travel_options_offers_a_lateral_edge_in_both_directions :: proc(t: ^testing.T) {
	m := legality_fixture()
	visited := []bool{false, false, false, false}

	from1 := run_travel_options(m, 1, visited)
	testing.expect(t, contains_id(from1, 2)) // 1 -> 2 lateral

	from2 := run_travel_options(m, 2, visited)
	testing.expect(t, contains_id(from2, 1)) // 2 -> 1 lateral
}

@(test)
can_travel_to_rejects_a_non_adjacent_destination :: proc(t: ^testing.T) {
	m := legality_fixture()
	visited := []bool{true, false, false, false}

	// From Start (0) node 3 is not a neighbor -> never legal, whatever visited.
	testing.expect(t, !run_can_travel_to(m, 0, visited, 3))
	// A real neighbor is legal.
	testing.expect(t, run_can_travel_to(m, 0, visited, 1))
}

// --- Encounter resolution + status (unchanged contracts) --------------------

@(test)
run_start_battle_hands_off_to_combat_with_the_ship_and_the_fight_stages_opponent :: proc(t: ^testing.T) {
	player := ship.Ship{hp = 20, speed = 5}
	fight := Stage_Fight{opponent = ship.Ship{hp = 10, speed = 3}}

	battle := run_start_battle(&player, &fight)

	testing.expect_value(t, battle.ships[.A], &player)
	testing.expect_value(t, battle.ships[.B], &fight.opponent)

	events: [dynamic]combat.Event
	defer delete(events)
	cmds: [combat.Side]Maybe(combat.Command)
	combat.combat_resolve_round(&battle, cmds, &events)
	testing.expect_value(t, battle.round, 1)
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
run_apply_trade_permanently_swaps_the_cost_stat_for_the_gain_stat :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20, max_hp = 20, durability = 2, speed = 5}

	run_apply_trade(&s, trade_of(.Durability, 3, .Speed, 1), Scaling_Site{zone = .Coastal, depth = 0}, 0)

	testing.expect_value(t, s.durability, 5)
	testing.expect_value(t, s.speed, 4)
}

// The axis is data now, so the *inverse* trade must work as well as the original
// — that's the whole of what unwelding bought.
@(test)
run_apply_trade_runs_an_axis_in_either_direction :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20, max_hp = 20, durability = 5, speed = 4}

	run_apply_trade(&s, trade_of(.Speed, 2, .Durability, 3), Scaling_Site{zone = .Coastal, depth = 0}, 0)

	testing.expect_value(t, s.speed, 6)
	testing.expect_value(t, s.durability, 2)
}

@(test)
run_apply_trade_moves_treasure :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20, max_hp = 20, durability = 4, starting_treasure = 50}

	run_apply_trade(&s, trade_of(.Treasure, 15, .Durability, 2), Scaling_Site{zone = .Coastal, depth = 0}, 0)

	testing.expect_value(t, s.starting_treasure, 65)
	testing.expect_value(t, s.durability, 2)
}

// Cannibalized Timbers (+HP for -Max HP) is why the pay-then-grant order is
// load-bearing: selling the ceiling first means the repair caps against the
// ceiling you just sold. 12 HP of a 20 ceiling, sell 6 of the ceiling, then
// repair 8 — the repair stops at the new ceiling of 14, not the old 20.
@(test)
run_apply_trade_pays_before_granting_so_a_repair_caps_against_the_sold_ceiling :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 12, max_hp = 20}

	run_apply_trade(&s, trade_of(.HP, 8, .Max_HP, 6), Scaling_Site{zone = .Coastal, depth = 0}, 0)

	testing.expect_value(t, s.max_hp, 14)
	testing.expect_value(t, s.hp, 14)
}

@(test)
run_apply_trade_never_overheals :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 18, max_hp = 20, durability = 4}

	run_apply_trade(&s, trade_of(.HP, 10, .Durability, 1), Scaling_Site{zone = .Coastal, depth = 0}, 0)

	testing.expect_value(t, s.hp, 20)
}

// Gaining Max HP is headroom, not a repair — the two stats stay distinct
// precisely so an entry can trade one for the other.
@(test)
run_apply_trade_gaining_max_hp_raises_the_ceiling_without_filling_it :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 12, max_hp = 20, starting_treasure = 50}

	run_apply_trade(&s, trade_of(.Max_HP, 5, .Treasure, 15), Scaling_Site{zone = .Coastal, depth = 0}, 0)

	testing.expect_value(t, s.max_hp, 25)
	testing.expect_value(t, s.hp, 12)
	testing.expect_value(t, s.starting_treasure, 35)
}

// Spending Max HP below current HP can't leave the ship holding more HP than it
// can now hold.
@(test)
run_apply_trade_paying_max_hp_pulls_current_hp_down_to_the_new_ceiling :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20, max_hp = 20, speed = 4}

	run_apply_trade(&s, trade_of(.Speed, 2, .Max_HP, 8), Scaling_Site{zone = .Coastal, depth = 0}, 0)

	testing.expect_value(t, s.max_hp, 12)
	testing.expect_value(t, s.hp, 12)
}

// --- Trade: affordability (issue #136) --------------------------------------

@(test)
run_trade_can_accept_refuses_a_cost_that_would_break_the_floor :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20, max_hp = 20, durability = 2, speed = 4}

	// Speed floors at 0, so spending exactly all of it is still a trade...
	testing.expect(t, run_trade_can_accept(&s, trade_of(.Durability, 8, .Speed, 4)))
	// ...but one more than the ship has is not.
	testing.expect(t, !run_trade_can_accept(&s, trade_of(.Durability, 8, .Speed, 5)))
}

// HP and Max HP floor at 1: a trade is a bargain on a menu and must not be able
// to sink the ship there.
@(test)
run_trade_can_accept_never_lets_a_trade_sink_the_ship :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 10, max_hp = 10, speed = 4}

	testing.expect(t, run_trade_can_accept(&s, trade_of(.Speed, 1, .HP, 9)))
	testing.expect(t, !run_trade_can_accept(&s, trade_of(.Speed, 1, .HP, 10)))
	testing.expect(t, run_trade_can_accept(&s, trade_of(.Speed, 1, .Max_HP, 9)))
	testing.expect(t, !run_trade_can_accept(&s, trade_of(.Speed, 1, .Max_HP, 10)))
}

// The ADR-0012 constraint the ticket names: a trade reads the **effective** stat,
// never the raw base field. A fitting granting +3 Durability makes a cost of 5
// affordable on a base of 2 — and paying it out of the base leaves that base
// negative, which is fine, because effective (0) is the number combat resolves
// against and it is still at the floor.
@(test)
run_trade_measures_the_cost_against_the_effective_stat_not_the_base_field :: proc(t: ^testing.T) {
	plating := ship.Fitting{
		name    = "Test Plating",
		size    = .Small,
		passive = ship.Effect{kind = .Modify_Durability, magnitude = 3},
	}
	s := ship.Ship{
		hp = 20, max_hp = 20, durability = 2, speed = 4,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = plating}},
	}
	testing.expect_value(t, ship.ship_effective_durability(&s), 5)

	// The base alone (2) could never pay 5; the fitting's contribution is what
	// makes it affordable.
	testing.expect(t, run_trade_can_accept(&s, trade_of(.Speed, 1, .Durability, 5)))
	run_apply_trade(&s, trade_of(.Speed, 1, .Durability, 5), Scaling_Site{zone = .Coastal, depth = 0}, 0)

	testing.expect_value(t, s.durability, -3) // the base field went negative...
	testing.expect_value(t, ship.ship_effective_durability(&s), 0) // ...and effective landed on the floor.
	testing.expect_value(t, s.speed, 5)
}

@(test)
run_apply_trade_asserts_on_a_trade_the_ship_cannot_pay_for :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}
	s := ship.Ship{hp = 20, max_hp = 20, speed = 4}

	run_apply_trade(&s, trade_of(.Durability, 8, .Speed, 5), Scaling_Site{zone = .Coastal, depth = 0}, 0)

	testing.expect_assert(t, "run_apply_trade on a trade the ship cannot pay for")
}

@(test)
run_status_is_won_when_the_ship_reaches_goal_with_positive_hp :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 1}
	goal := Node{kind = .Goal}

	testing.expect_value(t, run_status(&s, goal), Run_Status.Won)
}

@(test)
run_status_is_lost_when_hp_reaches_zero_even_at_the_goal :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 0}
	goal := Node{kind = .Goal}

	testing.expect_value(t, run_status(&s, goal), Run_Status.Lost)
}

@(test)
run_status_is_in_progress_away_from_goal_with_positive_hp :: proc(t: ^testing.T) {
	s := ship.Ship{hp = 20}
	encounter_node := Node{kind = .Encounter}

	testing.expect_value(t, run_status(&s, encounter_node), Run_Status.In_Progress)
}

@(test)
run_can_travel_is_false_once_hp_reaches_zero :: proc(t: ^testing.T) {
	sunk := ship.Ship{hp = 0}
	afloat := ship.Ship{hp = 1}

	testing.expect(t, !run_can_travel(&sunk))
	testing.expect(t, run_can_travel(&afloat))
}
