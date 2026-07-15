package run

import "core:math/rand"

// Procedural map generation: builds the run's connected node graph (ADR-0009)
// from a seed, and tears it down again. This is the content-producing half of
// the module — it materializes the Nodes, scatters ports, deals each zone's
// encounters from a shuffled recipe bag, and wires edges — sitting behind the
// navigation seam (navigation.odin), which only reads the finished graph. Stakes
// magnitudes come from the scaling group in run.odin, the encounters it deals
// from the catalog (catalog.odin), and the per-stage content itself is built in
// content.odin.

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

	// --- 4. Deal each zone's encounters from a per-zone shuffled recipe bag,
	// split as evenly across the catalog as the division allows, then bake each
	// picked recipe's stages into that node's stakes-scaled content. Generation
	// picks whole authored recipes — it never composes a stage list (ADR-0014).
	// The bag is dealt from the whole catalog for now; drawing it from the zone's
	// stage-count bucket instead (Coastal 1 / Open Sea 2 / Deep 3) is issue #134.
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
		bag := run_make_recipe_bag(len(enc_ids), run_recipe_catalog(), gen)
		for id, i in enc_ids {
			nodes[id].encounter = run_encounter_from_recipe(bag[i], Scaling_Site{zone = zone, depth = nodes[id].depth}, gen)
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
	// from `gen` only at the tail and leaves the recipe-deal and edge streams
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

// run_make_recipe_bag deals count recipes from `pool`, split as evenly across
// the pool as the division allows (e.g. 15 from a 3-recipe pool -> 5/5/5, 14 ->
// 5/5/4), then shuffles them. This is ADR-0009's per-zone shuffled kind bag with
// its three-way hard-coding removed: the even split is now over whatever pool it
// is handed, so widening the catalog is a data change rather than an edit here.
// Guarantees the zone-wide deal is even; makes no attempt to balance recipes
// along any individual route. Caller owns the returned slice.
//
// The pool it *should* be handed is the zone's stage-count bucket (Coastal 1 /
// Open Sea 2 / The Deep 3) — that draw is issue #134, and until it lands
// run_map_create passes the whole catalog.
run_make_recipe_bag :: proc(count: int, pool: []Recipe, gen: rand.Generator) -> []Recipe {
	assert(len(pool) > 0, "cannot deal a recipe bag from an empty pool")

	bag := make([]Recipe, count)
	base := count / len(pool)
	rem := count % len(pool)

	i := 0
	for recipe, k in pool {
		c := base + (1 if k < rem else 0)
		for _ in 0 ..< c {
			bag[i] = recipe
			i += 1
		}
	}
	rand.shuffle(bag, gen)
	return bag
}

// run_bake_stage builds one stage's stakes-scaled content for the given
// primitive, at the node's Scaling_Site — the per-primitive half of
// run_encounter_from_recipe, which walks a recipe and calls this for each
// authored stage. Takes `gen` so the primitives that sample the roster (an
// Offer's items, a Shop's deck) draw reproducibly from the same map-generation
// RNG stream. Nothing rolls on arrival.
//
// This is where each primitive's content roster will hang: the hostile roster a
// Fight draws its opponent from (#135) and the axis roster a Trade draws its
// swap from (#136) replace the single hand-authored template each has today.
run_bake_stage :: proc(kind: Stage_Kind, site: Scaling_Site, gen: rand.Generator) -> Stage {
	switch kind {
	case .Fight:
		return Stage_Fight{depth = site.depth, opponent = run_pve_opponent(site)}
	case .Offer:
		return Stage_Offer{options = run_item_offer_options(site, gen)}
	case .Trade:
		return Stage_Trade{
			gain_durability = run_stat_trade_gain_durability(site),
			cost_speed      = run_stat_trade_cost_speed(site),
		}
	case .Shop:
		return run_port_shop(gen)
	case .Reward:
		// Reward grants nothing yet — what it grants is issue #132 and the
		// primitive that spends that answer is #133. Baking it is a no-op rather
		// than an error so the arm is reachable the moment a recipe authors it.
		return Stage_Reward{}
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
// the edges array, m.nodes itself, plus each Fight stage's opponent.layout slice
// (issue #23; run_pve_opponent allocates a fresh layout per stage). Callers of
// run_map_create must use this instead of a bare delete(m.nodes).
//
// An Encounter stores its stages inline (ADR-0014's fixed-size storage), so this
// walks the stage list rather than freeing an owned one: the opponent layout is
// the only heap a stage holds, and every other primitive's content is a
// fixed-size array that goes with m.nodes.
run_map_destroy :: proc(m: ^Map) {
	for node in m.nodes {
		encounter, has_encounter := node.encounter.?
		if !has_encounter {
			continue
		}
		for i in 0 ..< encounter.count {
			if fight, is_fight := encounter.stages[i].(Stage_Fight); is_fight {
				delete(fight.opponent.layout)
			}
		}
	}
	for adj in m.edges {
		delete(adj)
	}
	delete(m.edges)
	delete(m.nodes)
}
