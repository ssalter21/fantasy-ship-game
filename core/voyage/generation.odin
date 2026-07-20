package voyage

import "core:math/rand"
import "core:slice"

// Procedural map generation: builds the voyage's connected node graph (ADR-0009)
// from a seed, and tears it down again. The content-producing half of the module —
// it materializes the Nodes, scatters ports, deals each zone's encounters from a
// shuffled recipe bag, and wires edges — sitting behind the navigation seam
// (navigation.odin), which only reads the finished graph. Stakes magnitudes come
// from the scaling group in voyage.odin, the encounters from the catalog
// (catalog.odin), and the per-stage content from content.odin.

// --- Generation constants: all tuning knobs live here, near the generator. -----

// nodes_per_zone is each zone's total *node* budget. A port consumes a slot rather
// than adding on top, so a zone's encounter count is its budget minus PORTS_PER_ZONE.
nodes_per_zone := [Zone]int{.Coastal = 17, .Open_Sea = 17, .Deep = 16}

// PORTS_PER_ZONE ports scattered per zone, each in a uniformly random layer within
// its zone's phase but never the zone's entrance layer (see the placement loop).
PORTS_PER_ZONE :: 2

// zone_stage_count is ADR-0014's mapping from zone to encounter length. It is the
// *only* filter on which recipes a zone may draw — the zone's bucket is every
// catalog recipe of that stage count — so encounters lengthen as the voyage sails
// out. Pacing holds because layers are LAYER_WIDTH_MIN..MAX wide and a route
// therefore crosses only ~3-4 of a zone's nodes, and the player can still route
// shallow deliberately.
//
// The bespoke placements are exempt: a Port is [Shop] even in The Deep
// (voyage_port_bucket), and Start/Haven carry no encounter at all.
zone_stage_count := [Zone]int{.Coastal = 1, .Open_Sea = 2, .Deep = 3}

// LAYER_WIDTH_MIN/MAX bound how many nodes sit in one layer of the forward graph.
LAYER_WIDTH_MIN :: 4
LAYER_WIDTH_MAX :: 6

// OUT_DEGREE_MAX bounds a regular node's forward out-edges; every non-Haven node
// gets at least one by construction, so the effective range is 1..OUT_DEGREE_MAX.
// The Start node is exempt: it is the sole source for the whole first layer, so it
// fans out to all of it.
OUT_DEGREE_MAX :: 4

// LATERAL_EDGE_CHANCE is the per-pair probability of a same-layer (lateral) edge —
// a bonus route legal to traverse either direction, never load-bearing for
// reachability.
LATERAL_EDGE_CHANCE :: 0.15

// voyage_map_create builds the voyage's node graph from seed: a layered forward
// graph grown zone-by-zone (Coastal -> Open_Sea -> Deep, into Haven), with
// reachability and zero dead ends guaranteed by construction and extra edges for
// real branching. Same seed => identical map. Caller owns the returned Map and
// must free it with voyage_map_destroy.
voyage_map_create :: proc(seed: u64) -> Map {
	state := rand.create_u64(seed)
	gen := rand.default_random_generator(&state)

	// --- 1. Lay out the layers: Start (1) -> each zone's layers -> Haven (1).
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
		widths := voyage_partition_layers(nodes_per_zone[zone], gen)
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
				kind = .Haven
			}

			depth := 0
			if zone, ok := zone_m.?; ok {
				raw_depth := l - zone_first_layer[zone]
				depth = voyage_normalize_depth(raw_depth, zone_layer_count[zone])
			}

			append(&nodes, Node{id = Node_ID(len(nodes)), zone = zone_m, kind = kind, layer = l, lane = lane, depth = depth})
		}
	}
	n := len(nodes)

	// --- 3. Place the Port bucket: PORTS_PER_ZONE per zone, each in a uniformly
	// random layer within that zone's phase but never its entrance layer (reaching a
	// port is a routing choice, not a guaranteed first stop). Two ports may share a
	// layer. A port consumes an Encounter slot rather than adding a node.
	//
	// A bucket like any other — a pool plus a placement rule (ADR-0014) — the rule
	// being the only bespoke thing. A Port is the [Shop] recipe, exempt from the
	// zone's stage-count mapping, and its stock is baked here with its recipe like
	// any other node's content. Start is excluded: a .Start node draws no recipe,
	// and a shop there would be unreachable.
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

			if slice.contains(placed[:count], id) {
				continue
			}
			placed[count] = id
			count += 1
		}

		// Deal these ports their recipes and bake them, the same way step 4 deals the
		// zone's encounters: one path puts content on a node
		// (voyage_encounter_from_recipe), whichever bucket the node was placed from.
		bag := voyage_make_recipe_bag(PORTS_PER_ZONE, voyage_port_bucket(), gen)
		for id, i in placed {
			nodes[id].encounter = voyage_encounter_from_recipe(bag[i], Scaling_Site{zone = zone, depth = nodes[id].depth}, gen)
		}
		delete(bag)
	}

	// --- 4. Deal each zone's encounters from a per-zone shuffled recipe bag over
	// that zone's stage-count bucket, split as evenly across the bucket as the
	// division allows, then bake each picked recipe's stages into that node's
	// stakes-scaled content. Generation picks whole authored recipes — it never
	// composes a stage list (ADR-0014).
	for zone in Zone {
		// enc_ids collects the plain int indices of this zone's still-empty nodes; the
		// generator works in raw indices internally and only Node.id is the distinct
		// Node_ID, so convert here rather than threading Node_ID through the index
		// arithmetic (ADR-0011 boundary). "Still empty" skips the ports step 3 just
		// dealt: a node is dealt a recipe because it holds no content, not because of
		// how it was placed. Start and Haven are excluded by having no zone.
		enc_ids: [dynamic]int
		for p in nodes {
			pz, in_zone := p.zone.?
			_, has_encounter := p.encounter.?
			if in_zone && pz == zone && !has_encounter {
				append(&enc_ids, int(p.id))
			}
		}
		pool := voyage_zone_recipe_pool(zone, voyage_recipe_catalog())
		bag := voyage_make_recipe_bag(len(enc_ids), pool, gen)
		for id, i in enc_ids {
			nodes[id].encounter = voyage_encounter_from_recipe(bag[i], Scaling_Site{zone = zone, depth = nodes[id].depth}, gen)
		}
		delete(bag)
		delete(pool)
		delete(enc_ids)
	}

	// --- 5. Wire edges, planar by construction (#338). Symmetric adjacency;
	// forward edges connect consecutive layers, laterals connect same-layer nodes.
	// Both are constrained so no two routes ever cross when drawn straight over the
	// x=layer, y=lane positions (view.odin's compute_node_positions), rather than
	// relying on render-time cleanup that can only reduce crossings, never rule
	// them out (an adjacent-layer K₂,₂ crosses for every lane ordering).
	adj := make([][dynamic]int, n)

	for l in 0 ..< n_layers - 1 {
		a0 := layer_start_id[l]
		wl := layer_width[l]
		b0 := layer_start_id[l + 1]
		wl1 := layer_width[l + 1]

		// A single-node source (the Start layer) fans out to the whole next layer:
		// it is the sole route into it, so every child is reachable and no lane
		// ordering can cross a fan from one point. Exempt from OUT_DEGREE_MAX, like
		// the old wiring, because it must reach all of layer 1.
		if wl == 1 {
			for c in 0 ..< wl1 {
				voyage_add_edge(adj, a0, b0 + c)
			}
			continue
		}

		// Monotone block tiling: parent p owns a contiguous child block
		// [start[p], start[p+1]] (inclusive), the blocks ordered along the lane
		// axis and adjacent blocks sharing their boundary child. Ordered blocks ⇒
		// for any p1 < p2 every child of p1 has lane ≤ every child of p2 ⇒ no lane
		// inversion ⇒ zero forward crossings. Blocks tile [0, wl1-1] so every child
		// is covered (in-guarantee), and each parent owns ≥1 child (out-guarantee,
		// no dead ends) — both fall out of the tiling instead of needing a repair
		// pass. Block widths are the branching, and bounding them at OUT_DEGREE_MAX
		// keeps forward out-degree in range without a cap check.
		//
		// widths sum to wl1-1+wl: wl blocks of width ≥1 covering wl1 children while
		// each interior boundary child is shared by two blocks. Start every block at
		// the minimum width 1, then scatter the wl1-1 surplus (each block taking up
		// to OUT_DEGREE_MAX-1 extra), the same shape voyage_partition_layers uses.
		widths := make([]int, wl)
		defer delete(widths)
		slice.fill(widths, 1)
		voyage_scatter_surplus(widths, OUT_DEGREE_MAX, wl1 - 1, gen)

		start := 0
		for p in 0 ..< wl {
			for c in start ..< start + widths[p] {
				voyage_add_edge(adj, a0 + p, b0 + c)
			}
			start += widths[p] - 1 // next block shares this one's boundary child
		}
	}

	// Lateral edges, restricted to adjacent lanes (i ↔ i+1) so the straight
	// same-layer segment has no node between its endpoints to pass through — a
	// wider lateral would cut through every lane it spans. Skip the single-node
	// Start/Haven layers.
	for l in 1 ..< n_layers - 1 {
		a0 := layer_start_id[l]
		w := layer_width[l]
		for i in 0 ..< w - 1 {
			if rand.float64(gen) < LATERAL_EDGE_CHANCE {
				voyage_add_edge(adj, a0 + i, a0 + i + 1)
			}
		}
	}

	// Materialize the finished adjacency as Node_ID edges. The generator built
	// adjacency in plain int (all the layer/lane index arithmetic above is int), so
	// this is the single boundary where a node id becomes a distinct Node_ID for the
	// returned Map (ADR-0011). Fresh Node_ID slices are copied out and the
	// [dynamic]int backings freed here, since a [dynamic]int backing can't be handed
	// to a [][]Node_ID directly; voyage_map_destroy frees the Node_ID slices in turn.
	edges := make([][]Node_ID, n)
	for i in 0 ..< n {
		edges[i] = make([]Node_ID, len(adj[i]))
		for id, j in adj[i] {
			edges[i][j] = Node_ID(id)
		}
		delete(adj[i])
	}
	delete(adj)

	return Map{nodes = nodes[:], edges = edges}
}

// voyage_partition_layers splits a zone's node budget into a list of layer widths,
// each within [LAYER_WIDTH_MIN, LAYER_WIDTH_MAX], summing exactly to total.
// The layer count is chosen randomly among those that admit a valid split,
// then the surplus over the minimum is scattered across layers. Caller owns
// the returned slice.
voyage_partition_layers :: proc(total: int, gen: rand.Generator) -> []int {
	min_layers := (total + LAYER_WIDTH_MAX - 1) / LAYER_WIDTH_MAX
	max_layers := total / LAYER_WIDTH_MIN
	k := min_layers if max_layers <= min_layers else rand.int_range(min_layers, max_layers + 1, gen)

	widths := make([]int, k)
	slice.fill(widths, LAYER_WIDTH_MIN)
	voyage_scatter_surplus(widths, LAYER_WIDTH_MAX, total - k * LAYER_WIDTH_MIN, gen)
	return widths
}

// voyage_scatter_surplus hands out `surplus` extra units across `widths`, one at a
// time to a uniformly-drawn entry, skipping any already at `cap`. Draws until the
// surplus is spent, so the caller must leave room for it (sum of caps ≥ the total).
voyage_scatter_surplus :: proc(widths: []int, cap, surplus: int, gen: rand.Generator) {
	surplus := surplus
	for surplus > 0 {
		i := rand.int_max(len(widths), gen)
		if widths[i] < cap {
			widths[i] += 1
			surplus -= 1
		}
	}
}

// voyage_make_recipe_bag deals count recipes from `pool`, split as evenly across
// the pool as the division allows, then shuffles them (ADR-0009's per-zone shuffled
// bag). The even split is over whatever pool it is handed — a zone's stage-count
// bucket for the zone deals, or the Port bucket for the port placements — so
// widening the catalog is a data change, not an edit here. Guarantees the zone-wide
// deal is even; makes no attempt to balance recipes along any individual route.
// Caller owns the returned slice.
voyage_make_recipe_bag :: proc(count: int, pool: []Recipe, gen: rand.Generator) -> []Recipe {
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

// voyage_recipe_bucket returns every recipe in pool whose stage list is exactly
// stage_count long — the bucket, *derived*. Membership is read off len(r.stages)
// and nothing else: a Recipe has no bucket field (stage.odin), so authoring a
// 3-stage recipe in catalog.odin files it into The Deep's bucket with no wiring
// here and no way to file it wrong. Caller owns the returned slice.
voyage_recipe_bucket :: proc(pool: []Recipe, stage_count: int) -> []Recipe {
	n := 0
	for r in pool {
		if len(r.stages) == stage_count {
			n += 1
		}
	}

	bucket := make([]Recipe, n)
	i := 0
	for r in pool {
		if len(r.stages) == stage_count {
			bucket[i] = r
			i += 1
		}
	}
	return bucket
}

// voyage_zone_recipe_pool returns the bucket a zone deals its encounters from: the
// catalog recipes whose stage count matches zone_stage_count[zone]. Caller owns
// the returned slice.
//
// An empty bucket is a **content bug** and asserts: it means someone emptied a
// bucket in catalog.odin, and silently dealing Coastal's encounters in The Deep
// would hide that behind a playable-looking map. The test
// every_zone_has_a_bucket_to_deal_from names the same fact, so the mistake is
// caught before the assert ever fires.
voyage_zone_recipe_pool :: proc(zone: Zone, catalog: []Recipe) -> []Recipe {
	bucket := voyage_recipe_bucket(catalog, zone_stage_count[zone])
	assert(len(bucket) > 0, "a zone's stage-count bucket is empty: the catalog has no recipe of that length")
	return bucket
}

// voyage_bake_stage builds one authored stage's content at the node's Scaling_Site —
// the per-primitive half of voyage_encounter_from_recipe, which walks a recipe and
// calls this for each of its Stage_Specs. Takes `gen` so the primitives that sample
// a pool (an Offer's items, a Shop's stock) draw reproducibly from the same
// map-generation RNG stream. Nothing rolls on arrival.
//
// Each arm draws its content and takes exactly the part of `site` it reads: Fight,
// Offer and Reward take the whole site, a Trade takes its **zone** alone (#146 — a
// swing is an exchange rate, with no room for a depth axis), and a Shop takes none
// of it. The Shop is the odd one out twice over — it alone ignores the site and it
// alone reads the spec — for the same reason: a shop is a fixed market whose
// character is authored and whose stakes are the captain's cargo, not the node's.
voyage_bake_stage :: proc(spec: Stage_Spec, site: Scaling_Site, gen: rand.Generator) -> Stage {
	pool, authored_pool := spec.stock.?
	assert(
		authored_pool == (spec.kind == .Shop),
		"a Stage_Spec authors a stock pool iff it is a Shop: no other primitive has one to draw from",
	)

	switch spec.kind {
	case .Fight:
		return Stage_Fight{opponent = voyage_pve_opponent(site, gen)}
	case .Offer:
		return Stage_Offer{options = voyage_item_offer_options(site, gen)}
	case .Trade:
		return voyage_make_trade(site.zone, gen)
	case .Shop:
		return voyage_bake_shop(pool, gen)
	case .Reward:
		// A Reward's payout is fixed here, at generation, from this node's own site —
		// content like an Offer's items, not a number rolled on arrival. It draws no
		// RNG, so a recipe carrying one leaves the generator's stream untouched.
		return Stage_Reward{cargo = voyage_reward_cargo(site)}
	}
	unreachable()
}

// voyage_add_edge records a symmetric edge between u and v (each appears in the
// other's adjacency), skipping duplicates.
voyage_add_edge :: proc(adj: [][dynamic]int, u, v: int) {
	if slice.contains(adj[u][:], v) {
		return
	}
	append(&adj[u], v)
	append(&adj[v], u)
}

// voyage_map_destroy frees a Map's owned memory: each node's adjacency slice and
// the edges array, m.nodes itself, plus each Fight stage's opponent.layout slice
// (voyage_pve_opponent allocates a fresh layout per stage). Callers of
// voyage_map_create must use this instead of a bare delete(m.nodes).
//
// An Encounter stores its stages inline (ADR-0014's fixed-size storage), so this
// walks the stage list rather than freeing an owned one: the opponent layout is
// the only heap a stage holds, and every other primitive's content is a
// fixed-size array that goes with m.nodes.
voyage_map_destroy :: proc(m: ^Map) {
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
