package run

import "../combat"
import "../ship"
import "core:slice"
import "core:testing"

// encounter_kind_of classifies e as its Encounter_Kind so the assertions
// below don't each repeat a type-switch over Encounter's variants. Kept
// local to tests rather than exported from run.odin: nothing in production
// code needs the reverse Encounter -> Encounter_Kind mapping.
encounter_kind_of :: proc(e: Encounter) -> Encounter_Kind {
	switch _ in e {
	case Encounter_Ship_Battle:
		return .Ship_Battle
	case Encounter_Item_Offer:
		return .Item_Offer
	case Encounter_Stat_Trade:
		return .Stat_Trade
	}
	unreachable()
}

// --- Gradient formulas: zone tier x depth ----------------------------------

expect_rises_by_zone_and_depth :: proc(t: ^testing.T, f: proc(Scaling_Site) -> int) {
	// A deeper zone at the same depth is harder/more rewarding...
	testing.expect(t, f(Scaling_Site{zone = .Deep, depth = 0}) > f(Scaling_Site{zone = .Coastal, depth = 0}))
	// ...and within a zone, a deeper node outscales a shallow one.
	testing.expect(t, f(Scaling_Site{zone = .Open_Sea, depth = DEPTH_STEPS}) > f(Scaling_Site{zone = .Open_Sea, depth = 0}))
}

@(test)
ship_battle_difficulty_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, run_ship_battle_difficulty)
}

@(test)
ship_battle_opponent_durability_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, run_ship_battle_opponent_durability)
}

@(test)
item_offer_quality_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, run_item_offer_quality)
}

@(test)
stat_trade_gain_durability_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, run_stat_trade_gain_durability)
}

@(test)
stat_trade_cost_speed_rises_by_zone_and_depth :: proc(t: ^testing.T) {
	expect_rises_by_zone_and_depth(t, run_stat_trade_cost_speed)
}

@(test)
run_make_opponent_ship_sets_both_hp_and_durability_from_zone_and_depth :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Deep, depth = 2}
	opponent := run_make_opponent_ship(site)

	testing.expect_value(t, opponent.hp, run_ship_battle_difficulty(site))
	testing.expect_value(t, opponent.durability, run_ship_battle_opponent_durability(site))
}

@(test)
the_three_zone_scaled_encounter_kinds_land_on_distinguishable_magnitudes :: proc(t: ^testing.T) {
	coastal := Scaling_Site{zone = .Coastal, depth = 0}
	testing.expect(t, run_ship_battle_difficulty(coastal) != run_item_offer_quality(coastal))
	testing.expect(t, run_ship_battle_difficulty(coastal) != run_stat_trade_gain_durability(coastal))
	testing.expect(t, run_item_offer_quality(coastal) != run_stat_trade_gain_durability(coastal))
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
	// #123, ADR-0013: every .Port node bakes a Shop whose deck is the *full*
	// roster — a permutation, so every roster item appears exactly once — each
	// card priced at its tier; non-port nodes carry no shop.
	roster := ship.ship_item_roster()
	for seed in TEST_SEEDS {
		m := run_map_create(seed)
		defer run_map_destroy(&m)

		for p in m.nodes {
			shop, has_shop := p.shop.?
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
		sa, is_port := pa.shop.?
		if !is_port {
			continue
		}
		sb := b.nodes[i].shop.?
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
				a := m.nodes[port_ids[i]].shop.?
				b := m.nodes[port_ids[j]].shop.?
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
encounter_kind_counts_per_zone_are_as_even_as_a_three_way_split_allows :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		m := run_map_create(seed)
		defer run_map_destroy(&m)

		for zone in Zone {
			counts: [Encounter_Kind]int
			for p in m.nodes {
				pz, in_zone := p.zone.?
				if !in_zone || pz != zone {
					continue
				}
				if enc, ok := p.encounter.?; ok {
					counts[encounter_kind_of(enc)] += 1
				}
			}
			lo := min(counts[.Ship_Battle], counts[.Item_Offer], counts[.Stat_Trade])
			hi := max(counts[.Ship_Battle], counts[.Item_Offer], counts[.Stat_Trade])
			testing.expectf(t, hi - lo <= 1, "seed %d: zone %v kind spread %d..%d not even", seed, zone, lo, hi)
		}
	}
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
			testing.expect_value(t, encounter_kind_of(ea), encounter_kind_of(eb))
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
				if _, is_battle := enc.(Encounter_Ship_Battle); !is_battle {
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
				sb := m.nodes[shallow].encounter.?.(Encounter_Ship_Battle)
				db := m.nodes[deep].encounter.?.(Encounter_Ship_Battle)
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
run_start_battle_hands_off_to_combat_with_the_ship_and_the_encounters_opponent :: proc(t: ^testing.T) {
	player := ship.Ship{hp = 20, speed = 5}
	encounter := Encounter_Ship_Battle{opponent = ship.Ship{hp = 10, speed = 3}}

	battle := run_start_battle(&player, &encounter)

	testing.expect_value(t, battle.ships[.A], &player)
	testing.expect_value(t, battle.ships[.B], &encounter.opponent)

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

	run_apply_stat_trade(&s, trade, .Coastal, 0)

	testing.expect_value(t, s.durability, 5)
	testing.expect_value(t, s.speed, 4)
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
