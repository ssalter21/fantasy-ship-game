package prototype_map_fog

// PROTOTYPE -- throwaway code answering issue #62 (wayfinder ticket, part of
// map #59 "Node-graph run map: connected topology, hidden encounters, scale
// to 50"). Question: what does the player actually see on the map before
// and after arrival, given hidden/randomized encounter kinds and a
// connected ~50-node graph?
//
// This file fabricates a plausible layered node graph with screen
// coordinates -- close enough to issue #60's generator shape (Node/Edge/
// Zone/layers) to look real, but it's a standalone copy, not a dependency:
// #60's actual generator hasn't landed in core/run yet (map #59's Notes:
// "implementation happens afterward as regular dev work"). Delete this
// whole directory once #62 closes and its answer is written up.

import "base:runtime"
import "core:math/rand"
import rl "vendor:raylib"

Zone :: enum {
	Coastal,
	Open_Sea,
	Deep,
}

zone_color := [Zone]rl.Color {
	.Coastal  = rl.Color{120, 180, 220, 255},
	.Open_Sea = rl.Color{90, 130, 200, 255},
	.Deep     = rl.Color{60, 70, 140, 255},
}

Kind :: enum {
	Ship_Battle,
	Upgrade_Offer,
	Stat_Trade,
}

kind_color := [Kind]rl.Color {
	.Ship_Battle   = rl.MAROON,
	.Upgrade_Offer = rl.LIME,
	.Stat_Trade    = rl.ORANGE,
}

kind_label := [Kind]string {
	.Ship_Battle   = "Battle",
	.Upgrade_Offer = "Upgrade",
	.Stat_Trade    = "Trade",
}

Node :: struct {
	id:      int,
	zone:    Zone, // Start borrows Coastal, Goal borrows Deep -- neither is a real encounter
	layer:   int,
	lane:    int, // 0..LANES-1, roughly-preserved vertical lane -- keeps edges short/local (issue #62 feedback: "stepping stones", not a dense mesh)
	kind:    Kind, // meaningless for is_start/is_port/is_goal nodes
	is_start: bool,
	is_port:  bool,
	is_goal:  bool,
	pos:     rl.Vector2, // prototype-only screen position; real Point carries no coords (issue #24)
}

Edge :: struct {
	from, to: int, // for a forward edge (lateral == false): always *created* lower layer -> higher layer -- generation is still forward-only; travel_options may walk one in reverse to retrace a visited node (issue #62 reversed the traversal rule, not the generation shape)
	lateral:  bool, // same-layer, adjacent-lane -- undirected in effect: travel_options offers both ends regardless of visited state, since neither side is "ahead" of the other (issue #62 feedback: "sideways connections should also be possible")
}

Graph :: struct {
	nodes:    []Node,
	edges:    []Edge,
	layers:   [][]int, // node ids grouped by layer, in layer order
	start_id: int,
	goal_id:  int,
}

Gen_Config :: struct {
	nodes_per_zone:  int,
	layers_per_zone: int,
	layer_width_min: int,
	layer_width_max: int,
}

// LANES caps both layer width and per-node degree: every node connects
// only to an adjacent lane (±1) one layer over, which is what keeps edges
// short and mostly non-crossing -- "stepping stones", not a dense mesh
// (issue #62 feedback). layer_width is clamped to LANES. This is charting a
// ship's course, not a dungeon crawl the player discovers room by room --
// per later issue #62 feedback the *whole* map should be visible at once
// (no camera/scroll), and it read as too thin/sparse at LANES=5 with only
// 3-4 nodes occupying it per layer. Widened to 9 lanes with a wider 5-7
// layer_width below so more of the vertical band actually has nodes in it.
LANES :: 9

default_gen_config := Gen_Config {
	nodes_per_zone  = 17, // Coastal/Open_Sea/Deep * 17 ~= 50, matching #60's locked constant
	layers_per_zone = 6,
	layer_width_min = 5,
	layer_width_max = 7,
}

// The whole graph must fit inside the window (no camera/pan -- issue #62
// feedback: charting a course means seeing the whole space at once), so
// x/y positions are ratios of the fixed MAP_LEFT/RIGHT/TOP/BOTTOM box, not
// fixed per-layer/per-lane steps -- layout() divides the box by however
// many layers/lanes this particular generated graph actually used.
MAP_LEFT :: 70
MAP_RIGHT :: WINDOW_WIDTH - 70
MAP_TOP :: 90
MAP_BOTTOM :: 680

// generate builds one candidate ~50-node graph, laid out left (Start) to
// right (Goal), grouped into per-zone layers -- same seed always produces
// the same graph.
generate_graph :: proc(seed: u64) -> Graph {
	rstate := rand.create_u64(seed)
	gen := runtime.default_random_generator(&rstate)

	nodes := make([dynamic]Node)
	layer_ids := make([dynamic][dynamic]int)

	mid_lane := LANES / 2
	start_id := 0
	append(&nodes, Node{id = start_id, zone = .Coastal, layer = 0, lane = mid_lane, is_start = true})
	l0 := make([dynamic]int)
	append(&l0, start_id)
	append(&layer_ids, l0)

	zones := [3]Zone{.Coastal, .Open_Sea, .Deep}
	kinds_cycle := [3]Kind{.Ship_Battle, .Upgrade_Offer, .Stat_Trade}
	kind_i := 0

	add_layer :: proc(nodes: ^[dynamic]Node, layer_ids: ^[dynamic][dynamic]int, zone: Zone, width: int, kind_i: ^int, kinds_cycle: [3]Kind, prev_lo, prev_width: ^int, gen: runtime.Random_Generator) {
		lo := next_lane_lo(prev_lo^, prev_width^, width, gen)
		layer := make([dynamic]int)
		for i in 0 ..< width {
			id := len(nodes)
			kind := kinds_cycle[kind_i^ % len(kinds_cycle)]
			kind_i^ += 1
			append(nodes, Node{id = id, zone = zone, layer = len(layer_ids), lane = lo + i, kind = kind})
			append(&layer, id)
		}
		append(layer_ids, layer)
		prev_lo^ = lo
		prev_width^ = width
	}

	prev_lo := mid_lane
	prev_width := 1
	for zone in zones {
		remaining := default_gen_config.nodes_per_zone
		for li in 0 ..< default_gen_config.layers_per_zone {
			if remaining <= 0 {
				break
			}
			width := default_gen_config.layer_width_min + rand.int_max(default_gen_config.layer_width_max - default_gen_config.layer_width_min + 1, gen)
			width = min(width, remaining, LANES)
			remaining -= width
			add_layer(&nodes, &layer_ids, zone, width, &kind_i, kinds_cycle, &prev_lo, &prev_width, gen)
		}
		// leftover nodes (nodes_per_zone bigger than layers_per_zone*LANES
		// can fit) land in extra top-up layers -- rough-mock only, not the
		// real generator's guarantee logic.
		for remaining > 0 {
			width := min(remaining, LANES)
			remaining -= width
			add_layer(&nodes, &layer_ids, zone, width, &kind_i, kinds_cycle, &prev_lo, &prev_width, gen)
		}
	}

	goal_id := len(nodes)
	append(&nodes, Node{id = goal_id, zone = .Deep, layer = len(layer_ids), lane = mid_lane, is_goal = true})
	lg := make([dynamic]int)
	append(&lg, goal_id)
	append(&layer_ids, lg)

	edges := make([dynamic]Edge)
	for li in 0 ..< len(layer_ids) - 1 {
		connect_stepping(nodes[:], layer_ids[li][:], layer_ids[li + 1][:], &edges, gen)
	}
	for li in 0 ..< len(layer_ids) {
		connect_lateral(nodes[:], layer_ids[li][:], &edges, gen)
	}

	// mark two nodes per zone as ports -- never hidden (no encounter kind),
	// just a flavor overlay; not this ticket's concern, included for
	// realism. Picked uniformly at random from anywhere in the zone (partial
	// Fisher-Yates over that zone's candidate ids) rather than "the first
	// two encountered" -- iteration order is node-id order, which is
	// generation order, so the old approach always landed both ports in the
	// zone's earliest layer, clustered together every single run (issue #62
	// feedback: "something strange about port placement... needs to be
	// random within the zone").
	for zone in zones {
		candidates := make([dynamic]int)
		for n in nodes {
			if n.zone == zone && !n.is_start && !n.is_goal {
				append(&candidates, n.id)
			}
		}
		port_count := min(2, len(candidates))
		for i in 0 ..< port_count {
			j := i + rand.int_max(len(candidates) - i, gen)
			candidates[i], candidates[j] = candidates[j], candidates[i]
			nodes[candidates[i]].is_port = true
		}
		delete(candidates)
	}

	layout(nodes[:], layer_ids[:])

	layers := make([][]int, len(layer_ids))
	for layer, i in layer_ids {
		layers[i] = layer[:]
	}

	return Graph{nodes = nodes[:], edges = edges[:], layers = layers, start_id = start_id, goal_id = goal_id}
}

// next_lane_lo picks the starting lane of a `width`-wide contiguous block of
// lanes, drifting by at most one lane from the previous layer's block so
// consecutive layers' blocks always overlap (or sit flush adjacent) -- every
// node ends up with a same-or-adjacent-lane neighbor next door in the next
// layer. That's what lets connect_stepping keep every edge within one lane
// step, never a long diagonal fallback -- issue #62 feedback: "edges should
// all be very similar lengths," which the old independent-random-lane-
// subset-per-layer approach didn't guarantee.
next_lane_lo :: proc(prev_lo, prev_width, width: int, gen: runtime.Random_Generator) -> int {
	max_lo := LANES - width
	prev_hi := prev_lo + prev_width - 1

	lo_min := max(prev_lo - 1, 0)
	lo_min = min(lo_min, max_lo)

	lo_max := min(prev_hi, max_lo)
	lo_max = max(lo_max, lo_min)

	return lo_min + rand.int_max(lo_max - lo_min + 1, gen)
}

abs_int :: proc(x: int) -> int {
	return -x if x < 0 else x
}

// BRANCH_CHANCE is the odds that any given adjacent-lane (from, to) pair
// gets wired. Independent per-pair coin flips (rather than "exactly one
// incoming edge per to-node") is what produces real convergence (a to-node
// picked by more than one from-node) and divergence (a from-node picked for
// more than one to-node) -- issue #62 feedback: "paths too linear...need
// more convergence and divergence." Bounded by lane-adjacency (never more
// than 3 candidates either direction: same lane, ±1) so it stays short of
// the dense-mesh look an earlier round of feedback rejected.
//
// Lowered from 0.55 when LATERAL_CHANCE (below) was introduced -- issue #62
// feedback: "sideways connections should also be possible, keep the same
// number of connections per node." Adding a whole new candidate pool
// (same-layer neighbors) without giving something back would have made
// every node's total degree bigger than before, not just differently
// shaped; this and LATERAL_CHANCE split the same per-node connection
// budget between forward and sideways instead of adding sideways on top.
BRANCH_CHANCE :: 0.35

// LATERAL_CHANCE is the odds that two same-layer, adjacent-lane nodes get a
// sideways edge (connect_lateral) -- see BRANCH_CHANCE's comment for why
// it's split from, not additional to, the forward connection budget.
LATERAL_CHANCE :: 0.35

// connect_stepping wires from_layer -> to_layer, restricted to adjacent
// lanes (|lane delta| <= 1, guaranteed non-empty by next_lane_lo's overlap
// invariant) so edges stay short and lengths similar. Every candidate pair
// gets an independent BRANCH_CHANCE coin flip; a repair pass then gives any
// node left with zero edges (rare, given the adjacency guarantee) a forced
// nearest-lane edge so nothing dead-ends or goes unreachable.
connect_stepping :: proc(nodes: []Node, from_layer, to_layer: []int, edges: ^[dynamic]Edge, gen: runtime.Random_Generator) {
	out_count := make(map[int]int)
	defer delete(out_count)
	in_count := make(map[int]int)
	defer delete(in_count)

	for from_id in from_layer {
		from_lane := nodes[from_id].lane
		for to_id in to_layer {
			if abs_int(nodes[to_id].lane - from_lane) > 1 {
				continue
			}
			if rand.float32(gen) < BRANCH_CHANCE {
				append(edges, Edge{from = from_id, to = to_id})
				out_count[from_id] += 1
				in_count[to_id] += 1
			}
		}
	}

	for to_id in to_layer {
		if in_count[to_id] > 0 {
			continue
		}
		to_lane := nodes[to_id].lane
		best := from_layer[0]
		best_dist := abs_int(nodes[best].lane - to_lane)
		for from_id in from_layer[1:] {
			d := abs_int(nodes[from_id].lane - to_lane)
			if d < best_dist {
				best_dist = d
				best = from_id
			}
		}
		append(edges, Edge{from = best, to = to_id})
		out_count[best] += 1
		in_count[to_id] += 1
	}

	for from_id in from_layer {
		if out_count[from_id] > 0 {
			continue
		}
		from_lane := nodes[from_id].lane
		best := to_layer[0]
		best_dist := abs_int(nodes[best].lane - from_lane)
		for to_id in to_layer[1:] {
			d := abs_int(nodes[to_id].lane - from_lane)
			if d < best_dist {
				best_dist = d
				best = to_id
			}
		}
		append(edges, Edge{from = from_id, to = best})
		out_count[from_id] += 1
		in_count[best] += 1
	}
}

// connect_lateral wires same-layer, adjacent-lane node pairs -- issue #62
// feedback: "sideways connections should also be possible." `layer` is
// already in ascending-lane order (add_layer assigns lanes lo..lo+width-1
// in order), so each consecutive pair is exactly one lane apart; every pair
// gets one independent LATERAL_CHANCE coin flip. No repair pass: unlike
// connect_stepping's forward edges, lateral edges aren't load-bearing for
// start-to-goal reachability (that guarantee lives entirely in the forward
// graph), just an optional extra route sideways.
connect_lateral :: proc(nodes: []Node, layer: []int, edges: ^[dynamic]Edge, gen: runtime.Random_Generator) {
	for i in 0 ..< len(layer) - 1 {
		if rand.float32(gen) < LATERAL_CHANCE {
			append(edges, Edge{from = layer[i], to = layer[i + 1], lateral = true})
		}
	}
}

graph_destroy :: proc(g: ^Graph) {
	delete(g.nodes)
	delete(g.edges)
	for layer in g.layers {
		delete(layer)
	}
	delete(g.layers)
}

// layout positions every node by (layer, lane): x from its layer index, y
// from its lane -- both as a fraction of the fixed MAP_LEFT/RIGHT/TOP/BOTTOM
// box, so the whole graph always fits inside the window regardless of how
// many layers this particular seed generated (issue #62: the whole space
// should be visible at once, no camera/pan). A fixed lane keeps a node's
// vertical position stable relative to its neighbors layer to layer, and
// next_lane_lo's contiguous-range guarantee (below) keeps every edge within
// one lane step, which together are what keep edges close in length to
// each other despite the box being divided a different number of ways per
// generated graph.
layout :: proc(nodes: []Node, layer_ids: [][dynamic]int) {
	num_layers := len(layer_ids)
	for layer, li in layer_ids {
		x := MAP_LEFT + f32(li) * (MAP_RIGHT - MAP_LEFT) / f32(num_layers - 1)
		for id in layer {
			lane := nodes[id].lane
			y := MAP_TOP + f32(lane) * (MAP_BOTTOM - MAP_TOP) / f32(LANES - 1)
			nodes[id].pos = rl.Vector2{x, y}
		}
	}
}

// travel_options returns every node the player may step to this turn:
// forward along any outgoing edge (new territory, or a re-converging
// already-visited node), backward along an incoming edge to a node that's
// already been visited (retracing the graph -- not a teleport to any
// arbitrary visited node, just the ones directly connected), or sideways
// along a lateral edge in either direction regardless of visited state --
// neither end is "ahead" of the other, so there's no forward/retrace
// asymmetry to apply (issue #62 feedback: "sideways connections should
// also be possible"). Movement is no longer forward-only (reversed from
// map #59's original chartering per issue #62's discussion); revisiting a
// node never re-triggers its encounter (is_landmark nodes never trigger
// one at all).
travel_options :: proc(g: Graph, current_id: int, visited: []bool) -> [dynamic]int {
	opts := make([dynamic]int)
	for e in g.edges {
		if e.lateral {
			if e.from == current_id && !is_in(e.to, opts[:]) {
				append(&opts, e.to)
			} else if e.to == current_id && !is_in(e.from, opts[:]) {
				append(&opts, e.from)
			}
		} else if e.from == current_id && !is_in(e.to, opts[:]) {
			append(&opts, e.to)
		} else if e.to == current_id && visited[e.from] && !is_in(e.from, opts[:]) {
			append(&opts, e.from)
		}
	}
	return opts
}

is_landmark :: proc(n: Node) -> bool {
	return n.is_start || n.is_port || n.is_goal
}

// will_trigger reports whether stepping to id would fire a fresh encounter
// (never visited, and not a landmark, which carries no encounter kind).
will_trigger :: proc(g: Graph, id: int, visited: []bool) -> bool {
	return !is_landmark(g.nodes[id]) && !visited[id]
}
