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
	from, to: int, // always *created* lower layer -> higher layer -- generation is still forward-only; travel_options may walk one in reverse to retrace a visited node (issue #62 reversed the traversal rule, not the generation shape)
}

Graph :: struct {
	nodes:      []Node,
	edges:      []Edge,
	layers:     [][]int, // node ids grouped by layer, in layer order
	start_id:   int,
	goal_id:    int,
	world_right: f32, // rightmost node x -- world is much wider than any window, camera pans (main.odin)
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
// (issue #62 feedback). layer_width is clamped to LANES. Widening LANES
// (rather than shrinking nodes_per_zone) is how this stays at map #59's
// actual ~50-node scale without piling nodes into too few lanes.
LANES :: 5

default_gen_config := Gen_Config {
	nodes_per_zone  = 17, // Coastal/Open_Sea/Deep * 17 ~= 50, matching #60's locked constant
	layers_per_zone = 6,
	layer_width_min = 3,
	layer_width_max = 4,
}

// Fixed per-layer/per-lane world-space steps (not "total width / layer
// count") -- two things follow directly from this: (1) the world grows
// wider as more layers are generated instead of being squeezed into one
// screen, which is what "much wider, Slay-the-Spire-like" (issue #62
// feedback) needs -- main.odin pans a camera across it; (2) because
// LAYER_DX is large relative to LANE_DY, a same-lane edge (dx only) and an
// adjacent-lane edge (dx and one dy step) end up close in length instead of
// wildly different -- combined with next_lane_lo's overlap guarantee below
// (which keeps every edge within one lane step to begin with, never a long
// diagonal), this is what makes edges "very similar lengths" rather than
// variable.
LAYER_DX :: 170
LANE_DY :: 70

MAP_LEFT :: 60
MAP_TOP :: 140
MAP_BOTTOM :: MAP_TOP + (LANES - 1) * LANE_DY

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

	// mark two nodes per zone as ports -- never hidden (no encounter kind),
	// just a flavor overlay; not this ticket's concern, included for realism.
	for zone in zones {
		count := 0
		for &n in nodes {
			if n.zone == zone && !n.is_start && !n.is_goal && count < 2 {
				n.is_port = true
				count += 1
			}
		}
	}

	world_right := layout(nodes[:], layer_ids[:])

	layers := make([][]int, len(layer_ids))
	for layer, i in layer_ids {
		layers[i] = layer[:]
	}

	return Graph{nodes = nodes[:], edges = edges[:], layers = layers, start_id = start_id, goal_id = goal_id, world_right = world_right}
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

// connect_stepping wires from_layer -> to_layer with two passes, both
// restricted to adjacent lanes (|lane delta| <= 1) so edges stay short and
// mostly non-crossing -- "stepping stones", not a dense mesh (issue #62
// feedback: fewer, closer-together, non-overlapping connections):
//
//  1. every to-node gets one guaranteed incoming edge from whichever
//     adjacent-lane from-node currently has the fewest outgoing edges --
//     load-balances degree instead of piling edges onto one node.
//  2. any from-node still at zero outgoing after (1) gets one forced edge
//     to its nearest-lane to-node -- guarantees no dead ends. Typical
//     out-degree stays 1-2, occasionally producing real branching without
//     the wide fan-out the original random-target version had.
connect_stepping :: proc(nodes: []Node, from_layer, to_layer: []int, edges: ^[dynamic]Edge, gen: runtime.Random_Generator) {
	out_degree := make(map[int]int)
	defer delete(out_degree)

	for to_id in to_layer {
		to_lane := nodes[to_id].lane
		best := -1
		best_degree := 1_000_000
		for from_id in from_layer {
			if abs_int(nodes[from_id].lane - to_lane) > 1 {
				continue
			}
			deg := out_degree[from_id]
			if deg < best_degree {
				best_degree = deg
				best = from_id
			}
		}
		if best == -1 {
			// no adjacent-lane candidate -- next_lane_lo's overlap guarantee
			// should make this rare. Fall back to the nearest lane (degree
			// breaks ties) rather than pure least-loaded, so any edge that
			// must break the ±1 rule is still as short as possible instead
			// of an arbitrary long diagonal.
			best_dist := 1_000_000
			for from_id in from_layer {
				d := abs_int(nodes[from_id].lane - to_lane)
				deg := out_degree[from_id]
				if d < best_dist || (d == best_dist && deg < best_degree) {
					best_dist = d
					best_degree = deg
					best = from_id
				}
			}
		}
		append(edges, Edge{from = best, to = to_id})
		out_degree[best] += 1
	}

	for from_id in from_layer {
		if out_degree[from_id] > 0 {
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
		out_degree[from_id] += 1
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

// layout positions every node by (layer, lane): x from its layer index at a
// fixed LAYER_DX step, y from its lane at a fixed LANE_DY step -- fixed
// (not "total width / layer count") steps are what make the world grow
// wider as more layers are generated (issue #62: "much wider") instead of
// squeezing into one screen, and what keep a same-lane edge (dx only) and
// an adjacent-lane edge (dx + one dy step) close in length to each other
// (issue #62: "edges should all be very similar lengths"). Returns the
// rightmost node's x so callers (main.odin's camera, the zone-gradient
// background) know the world's actual extent.
layout :: proc(nodes: []Node, layer_ids: [][dynamic]int) -> f32 {
	for layer, li in layer_ids {
		x := MAP_LEFT + f32(li) * LAYER_DX
		for id in layer {
			lane := nodes[id].lane
			y := MAP_TOP + f32(lane) * LANE_DY
			nodes[id].pos = rl.Vector2{x, y}
		}
	}
	return MAP_LEFT + f32(len(layer_ids) - 1) * LAYER_DX
}

// travel_options returns every node the player may step to this turn:
// forward along any outgoing edge (new territory, or a re-converging
// already-visited node), or backward along an incoming edge to a node
// that's already been visited (retracing the graph -- not a teleport to
// any arbitrary visited node, just the ones directly connected). Movement
// is no longer forward-only (reversed from map #59's original chartering
// per issue #62's discussion); revisiting a node never re-triggers its
// encounter (is_landmark nodes never trigger one at all).
travel_options :: proc(g: Graph, current_id: int, visited: []bool) -> [dynamic]int {
	opts := make([dynamic]int)
	for e in g.edges {
		if e.from == current_id && !is_in(e.to, opts[:]) {
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
