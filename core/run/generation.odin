package run

import "core:math/rand"

// Procedural map generation: builds the run's connected node graph (ADR-0009)
// from a seed, and tears it down again. This is the content-producing half of
// the module — it materializes the Nodes, scatters ports, assigns encounter
// kinds, and wires edges — sitting behind the navigation seam
// (navigation.odin), which only reads the finished graph. Difficulty/reward
// magnitudes come from the scaling group in run.odin; the per-encounter
// content itself is built in content.odin.

// --- Generation constants (all tuning knobs live here, near the generator;
// no config file, no settings UI) -------------------------------------------

// nodes_per_zone is each zone's total *node* budget (50 total across the
// three zones, plus Start and Goal). A port consumes a slot rather than
// adding on top, so real encounter counts are these minus PORTS_PER_ZONE
// (15 / 15 / 14 = 44 encounters).
nodes_per_zone := [Zone]int{.Coastal = 17, .Open_Sea = 17, .Deep = 16}

// PORTS_PER_ZONE scattered ports per zone (6 total, plus the Start home
// port), each placed in a uniformly random layer within its zone's phase but
// never on the zone's entrance layer.
PORTS_PER_ZONE :: 2

// LAYER_WIDTH_MIN/MAX bound how many nodes sit in one layer of the forward
// graph (locked by #60 as the tunable starting point).
LAYER_WIDTH_MIN :: 4
LAYER_WIDTH_MAX :: 6

// OUT_DEGREE_MAX bounds a regular node's forward out-edges (#60 locked 1..4);
// every non-Goal node gets at least one forward edge by construction, so the
// effective range is 1..OUT_DEGREE_MAX. The Start node is exempt: it is the
// sole source for the whole first layer, so it fans out to all of it.
OUT_DEGREE_MAX :: 4

// LATERAL_EDGE_CHANCE is the per-pair probability of a same-layer (lateral)
// edge — a bonus route legal to traverse either direction, never load-bearing
// for reachability.
LATERAL_EDGE_CHANCE :: 0.15

// run_map_create builds the run's procedurally-generated node graph from
// seed: a layered forward graph grown zone-by-zone (Coastal -> Open_Sea ->
// Deep, into Goal), with reachability and zero dead ends guaranteed by
// construction and extra edges for real branching. Same seed => identical
// map. Caller owns the returned Map and must free it with run_map_destroy.
run_map_create :: proc(seed: u64) -> Map {
	state := rand.create_u64(seed)
	gen := rand.default_random_generator(&state)

	// --- 1. Lay out the layers: Start (1) -> each zone's layers -> Goal (1).
	layer_zone: [dynamic]Maybe(Zone)
	layer_width: [dynamic]int
	defer delete(layer_zone)
	defer delete(layer_width)

	append(&layer_zone, nil)
	append(&layer_width, 1)

	zone_first_layer: [Zone]int
	zone_layer_count: [Zone]int
	for zone in Zone {
		zone_first_layer[zone] = len(layer_width)
		widths := run_partition_layers(nodes_per_zone[zone], gen)
		zone_layer_count[zone] = len(widths)
		for w in widths {
			append(&layer_zone, Maybe(Zone)(zone))
			append(&layer_width, w)
		}
		delete(widths)
	}

	append(&layer_zone, nil)
	append(&layer_width, 1)

	n_layers := len(layer_width)

	// --- 2. Materialize the nodes layer by layer (ids run in layer order).
	nodes: [dynamic]Node
	layer_start_id := make([]int, n_layers)
	defer delete(layer_start_id)

	for l in 0 ..< n_layers {
		layer_start_id[l] = len(nodes)
		zone_m := layer_zone[l]
		for lane in 0 ..< layer_width[l] {
			kind := Node_Kind.Encounter
			if l == 0 {
				kind = .Start
			} else if l == n_layers - 1 {
				kind = .Goal
			}

			depth := 0
			if zone, ok := zone_m.?; ok {
				raw_depth := l - zone_first_layer[zone]
				depth = run_normalize_depth(raw_depth, zone_layer_count[zone])
			}

			append(&nodes, Node{id = Node_ID(len(nodes)), zone = zone_m, kind = kind, layer = l, lane = lane, depth = depth})
		}
	}
	n := len(nodes)

	// --- 3. Place ports: PORTS_PER_ZONE per zone, each in a uniformly random
	// layer within that zone's phase but never its entrance layer (reaching a
	// port is a routing choice, not a guaranteed first stop). Two ports may
	// share a layer. A port consumes an Encounter slot rather than adding a
	// node.
	for zone in Zone {
		zl0 := zone_first_layer[zone]
		zl1 := zl0 + zone_layer_count[zone]
		// Draw from [port_l0, zl1), excluding the entrance layer zl0. Fall back
		// to the entrance only for a single-layer zone (never at the real node
		// budget), where it is the sole option.
		port_l0 := zl0 + 1
		placed: [PORTS_PER_ZONE]int
		count := 0
		for count < PORTS_PER_ZONE {
			l := zl0 if port_l0 >= zl1 else rand.int_range(port_l0, zl1, gen)
			lane := rand.int_max(layer_width[l], gen)
			id := layer_start_id[l] + lane

			taken := false
			for k in 0 ..< count {
				if placed[k] == id {
					taken = true
					break
				}
			}
			if taken {
				continue
			}
			placed[count] = id
			count += 1
			nodes[id].kind = .Port
		}
	}

	// --- 4. Assign encounter kinds from a per-zone shuffled bag, split as
	// evenly across the three kinds as a three-way division allows, then build
	// each encounter's zone-and-depth-scaled content.
	for zone in Zone {
		// enc_ids collects the plain int indices of this zone's encounter nodes;
		// the generator works in raw indices internally and only Node.id is the
		// distinct Node_ID, so convert here rather than threading Node_ID through
		// the index arithmetic (ADR-0011 boundary note, issue #112).
		enc_ids: [dynamic]int
		for p in nodes {
			pz, in_zone := p.zone.?
			if in_zone && pz == zone && p.kind == .Encounter {
				append(&enc_ids, int(p.id))
			}
		}
		bag := run_make_kind_bag(len(enc_ids), gen)
		for id, i in enc_ids {
			nodes[id].encounter = run_make_encounter(bag[i], Scaling_Site{zone = zone, depth = nodes[id].depth}, gen)
		}
		delete(bag)
		delete(enc_ids)
	}

	// --- 5. Wire edges. Symmetric adjacency; forward edges connect
	// consecutive layers, laterals connect same-layer nodes.
	adj := make([][dynamic]int, n)
	forward_out := make([]int, n)
	defer delete(forward_out)

	for l in 0 ..< n_layers - 1 {
		a0 := layer_start_id[l]
		a1 := a0 + layer_width[l]
		b0 := layer_start_id[l + 1]
		b1 := b0 + layer_width[l + 1]

		// Out guarantee: every node in layer l gets at least one forward edge
		// into layer l+1 — no dead ends, and every non-Goal node can always
		// step forward toward Goal.
		for u in a0 ..< a1 {
			v := b0 + rand.int_max(b1 - b0, gen)
			run_add_edge(adj, u, v)
			forward_out[u] += 1
		}

		// In guarantee: every node in layer l+1 that still has no incoming
		// edge gets one from a layer-l source with spare out-degree — so no
		// node is unreachable from Start.
		for v in b0 ..< b1 {
			if run_has_incoming(adj[:], v, a0, a1) {
				continue
			}
			u := run_pick_source_with_capacity(a0, a1, forward_out, gen)
			run_add_edge(adj, u, v)
			forward_out[u] += 1
		}

		// Extra edges: real branching, capped at OUT_DEGREE_MAX forward edges
		// per node (Start exempt — it must fan out to the whole first layer).
		for u in a0 ..< a1 {
			extra := rand.int_max(OUT_DEGREE_MAX, gen)
			for _ in 0 ..< extra {
				if l != 0 && forward_out[u] >= OUT_DEGREE_MAX {
					break
				}
				v := b0 + rand.int_max(b1 - b0, gen)
				if !run_contains(adj[u][:], v) {
					run_add_edge(adj, u, v)
					forward_out[u] += 1
				}
			}
		}
	}

	// Lateral edges within a layer (skip the single-node Start/Goal layers).
	for l in 1 ..< n_layers - 1 {
		a0 := layer_start_id[l]
		w := layer_width[l]
		for i in 0 ..< w {
			for j in i + 1 ..< w {
				if rand.float64(gen) < LATERAL_EDGE_CHANCE {
					run_add_edge(adj, a0 + i, a0 + j)
				}
			}
		}
	}

	// Materialize the finished adjacency as Node_ID edges. The generator built
	// adjacency in plain int — the whole layer/lane index arithmetic above is int
	// — so this is the single boundary where a node id becomes a distinct Node_ID
	// for the returned Map (ADR-0011, issue #112). Fresh Node_ID slices are copied
	// out and the [dynamic]int backings freed here, since a [dynamic]int backing
	// can't be handed to a [][]Node_ID directly; run_map_destroy frees the Node_ID
	// slices in turn.
	edges := make([][]Node_ID, n)
	for i in 0 ..< n {
		edges[i] = make([]Node_ID, len(adj[i]))
		for id, j in adj[i] {
			edges[i][j] = Node_ID(id)
		}
		delete(adj[i])
	}
	delete(adj)

	// --- 6. Stock the shops. Every .Port node gets a purchasable stock drawn
	// from the roster pool (#98). Done last, after kinds and edges, so it draws
	// from `gen` only at the tail and leaves the encounter-kind and edge streams
	// above byte-identical to a pre-shop map. Start (the home port) is a .Start
	// node, not .Port, and stays a pure waypoint in this slice — you never arrive
	// at it by travel, so a shop there would be unreachable.
	for &node in nodes {
		if node.kind == .Port {
			node.shop = run_port_shop(gen)
		}
	}

	return Map{nodes = nodes[:], edges = edges}
}

// run_partition_layers splits a zone's node budget into a list of layer widths,
// each within [LAYER_WIDTH_MIN, LAYER_WIDTH_MAX], summing exactly to total.
// The layer count is chosen randomly among those that admit a valid split,
// then the surplus over the minimum is scattered across layers. Caller owns
// the returned slice.
run_partition_layers :: proc(total: int, gen: rand.Generator) -> []int {
	min_layers := (total + LAYER_WIDTH_MAX - 1) / LAYER_WIDTH_MAX
	max_layers := total / LAYER_WIDTH_MIN
	k := min_layers if max_layers <= min_layers else rand.int_range(min_layers, max_layers + 1, gen)

	widths := make([]int, k)
	for i in 0 ..< k {
		widths[i] = LAYER_WIDTH_MIN
	}
	surplus := total - k * LAYER_WIDTH_MIN
	for surplus > 0 {
		i := rand.int_max(k, gen)
		if widths[i] < LAYER_WIDTH_MAX {
			widths[i] += 1
			surplus -= 1
		}
	}
	return widths
}

// run_make_kind_bag builds count encounter kinds split as evenly across the three
// kinds as a three-way division allows (e.g. 15 -> 5/5/5, 14 -> 5/5/4), then
// shuffles them. Guarantees the zone-wide pool is even; makes no attempt to
// balance kinds along any individual route. Caller owns the returned slice.
run_make_kind_bag :: proc(count: int, gen: rand.Generator) -> []Encounter_Kind {
	bag := make([]Encounter_Kind, count)
	base := count / 3
	rem := count % 3

	i := 0
	for kind, k in ([3]Encounter_Kind{.Ship_Battle, .Item_Offer, .Stat_Trade}) {
		c := base + (1 if k < rem else 0)
		for _ in 0 ..< c {
			bag[i] = kind
			i += 1
		}
	}
	rand.shuffle(bag, gen)
	return bag
}

// run_make_encounter builds one Encounter's zone-and-depth-scaled content for
// the given kind, at the node's Scaling_Site. Split out so the generator's
// kind-assignment loop reads as data, not a switch. Takes `gen` so an Item Offer
// can sample its distinct roster items reproducibly from the same map-generation
// RNG stream.
run_make_encounter :: proc(kind: Encounter_Kind, site: Scaling_Site, gen: rand.Generator) -> Encounter {
	switch kind {
	case .Ship_Battle:
		return Encounter_Ship_Battle{depth = site.depth, opponent = run_pve_opponent(site)}
	case .Item_Offer:
		return Encounter_Item_Offer{options = run_item_offer_options(site, gen)}
	case .Stat_Trade:
		return Encounter_Stat_Trade{
			gain_durability = run_trade_gain_durability(site),
			cost_speed      = run_trade_cost_speed(site),
		}
	}
	unreachable()
}

// run_add_edge records a symmetric edge between u and v (each appears in the
// other's adjacency), skipping duplicates.
run_add_edge :: proc(adj: [][dynamic]int, u, v: int) {
	if run_contains(adj[u][:], v) {
		return
	}
	append(&adj[u], v)
	append(&adj[v], u)
}

// run_contains reports whether xs holds x — a linear scan, fine for the tiny
// per-node adjacency lists.
run_contains :: proc(xs: []int, x: int) -> bool {
	for e in xs {
		if e == x {
			return true
		}
	}
	return false
}

// run_has_incoming reports whether v already has an edge from any node in the
// layer spanning [a0, a1).
run_has_incoming :: proc(adj: [][dynamic]int, v, a0, a1: int) -> bool {
	for u in adj[v] {
		if u >= a0 && u < a1 {
			return true
		}
	}
	return false
}

// run_pick_source_with_capacity chooses a node in [a0, a1) whose forward
// out-degree is still below OUT_DEGREE_MAX; falls back to any node in range if
// somehow all are saturated (layer widths make that unreachable in practice).
run_pick_source_with_capacity :: proc(a0, a1: int, forward_out: []int, gen: rand.Generator) -> int {
	candidates: [dynamic]int
	defer delete(candidates)
	for u in a0 ..< a1 {
		if forward_out[u] < OUT_DEGREE_MAX {
			append(&candidates, u)
		}
	}
	if len(candidates) == 0 {
		return a0 + rand.int_max(a1 - a0, gen)
	}
	return candidates[rand.int_max(len(candidates), gen)]
}

// run_map_destroy frees a Map's owned memory: each node's adjacency slice and
// the edges array, m.nodes itself, plus each Ship Battle encounter's
// opponent.layout slice (issue #23; run_pve_opponent allocates a fresh layout
// per node). Callers of run_map_create must use this instead of a bare
// delete(m.nodes).
run_map_destroy :: proc(m: ^Map) {
	for node in m.nodes {
		encounter, has_encounter := node.encounter.?
		if !has_encounter {
			continue
		}
		if battle, is_battle := encounter.(Encounter_Ship_Battle); is_battle {
			delete(battle.opponent.layout)
		}
	}
	for adj in m.edges {
		delete(adj)
	}
	delete(m.edges)
	delete(m.nodes)
}
