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
	kind:    Kind, // meaningless for is_start/is_port/is_goal nodes
	is_start: bool,
	is_port:  bool,
	is_goal:  bool,
	pos:     rl.Vector2, // prototype-only screen position; real Point carries no coords (issue #24)
}

Edge :: struct {
	from, to: int, // always lower layer -> higher layer: forward-only, no backtracking
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
	extra_edge_max:  int, // 0..this many extra forward edges per node beyond the guaranteed one
}

default_gen_config := Gen_Config {
	nodes_per_zone  = 17,
	layers_per_zone = 4,
	layer_width_min = 3,
	layer_width_max = 5,
	extra_edge_max  = 2,
}

MAP_LEFT :: 40
MAP_RIGHT :: 1180
MAP_TOP :: 90
MAP_BOTTOM :: 560

// generate builds one candidate ~50-node graph, laid out left (Start) to
// right (Goal), grouped into per-zone layers -- same seed always produces
// the same graph.
generate_graph :: proc(seed: u64) -> Graph {
	rstate := rand.create_u64(seed)
	gen := runtime.default_random_generator(&rstate)

	nodes := make([dynamic]Node)
	layer_ids := make([dynamic][dynamic]int)

	start_id := 0
	append(&nodes, Node{id = start_id, zone = .Coastal, layer = 0, is_start = true})
	l0 := make([dynamic]int)
	append(&l0, start_id)
	append(&layer_ids, l0)

	zones := [3]Zone{.Coastal, .Open_Sea, .Deep}
	kinds_cycle := [3]Kind{.Ship_Battle, .Upgrade_Offer, .Stat_Trade}
	kind_i := 0

	for zone in zones {
		remaining := default_gen_config.nodes_per_zone
		for li in 0 ..< default_gen_config.layers_per_zone {
			if remaining <= 0 {
				break
			}
			width := default_gen_config.layer_width_min + rand.int_max(default_gen_config.layer_width_max - default_gen_config.layer_width_min + 1, gen)
			width = min(width, remaining)
			remaining -= width

			layer := make([dynamic]int)
			for i in 0 ..< width {
				id := len(nodes)
				kind := kinds_cycle[kind_i % len(kinds_cycle)]
				kind_i += 1
				append(&nodes, Node{id = id, zone = zone, layer = len(layer_ids), kind = kind})
				append(&layer, id)
			}
			append(&layer_ids, layer)
		}
		// leftover nodes (width capped below remaining) land in one final
		// top-up layer so nodes_per_zone is always hit -- rough-mock only,
		// not the real generator's guarantee logic.
		if remaining > 0 {
			layer := make([dynamic]int)
			for i in 0 ..< remaining {
				id := len(nodes)
				kind := kinds_cycle[kind_i % len(kinds_cycle)]
				kind_i += 1
				append(&nodes, Node{id = id, zone = zone, layer = len(layer_ids), kind = kind})
				append(&layer, id)
			}
			append(&layer_ids, layer)
		}
	}

	goal_id := len(nodes)
	append(&nodes, Node{id = goal_id, zone = .Deep, layer = len(layer_ids), is_goal = true})
	lg := make([dynamic]int)
	append(&lg, goal_id)
	append(&layer_ids, lg)

	edges := make([dynamic]Edge)
	for li in 0 ..< len(layer_ids) - 1 {
		from_layer := layer_ids[li][:]
		to_layer := layer_ids[li + 1][:]

		// guarantee every node in from_layer has >=1 forward edge
		for from_id in from_layer {
			to_id := to_layer[rand.int_max(len(to_layer), gen)]
			append(&edges, Edge{from = from_id, to = to_id})
			extra := rand.int_max(default_gen_config.extra_edge_max + 1, gen)
			for i in 0 ..< extra {
				candidate := to_layer[rand.int_max(len(to_layer), gen)]
				if candidate != to_id {
					append(&edges, Edge{from = from_id, to = candidate})
				}
			}
		}
		// guarantee every node in to_layer has >=1 incoming edge
		for to_id in to_layer {
			has_incoming := false
			for e in edges {
				if e.to == to_id && is_in(e.from, from_layer) {
					has_incoming = true
					break
				}
			}
			if !has_incoming {
				from_id := from_layer[rand.int_max(len(from_layer), gen)]
				append(&edges, Edge{from = from_id, to = to_id})
			}
		}
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

	layout(nodes[:], layer_ids[:])

	layers := make([][]int, len(layer_ids))
	for layer, i in layer_ids {
		layers[i] = layer[:]
	}

	return Graph{nodes = nodes[:], edges = edges[:], layers = layers, start_id = start_id, goal_id = goal_id}
}

graph_destroy :: proc(g: ^Graph) {
	delete(g.nodes)
	delete(g.edges)
	for layer in g.layers {
		delete(layer)
	}
	delete(g.layers)
}

layout :: proc(nodes: []Node, layer_ids: [][dynamic]int) {
	num_layers := len(layer_ids)
	for layer, li in layer_ids {
		x := MAP_LEFT + f32(li) * (MAP_RIGHT - MAP_LEFT) / f32(num_layers - 1)
		count := len(layer)
		for id, row in layer {
			y: f32
			if count == 1 {
				y = (MAP_TOP + MAP_BOTTOM) / 2
			} else {
				y = MAP_TOP + f32(row) * (MAP_BOTTOM - MAP_TOP) / f32(count - 1)
			}
			nodes[id].pos = rl.Vector2{x, y}
		}
	}
}

reachable_next :: proc(g: Graph, from_id: int) -> [dynamic]int {
	next := make([dynamic]int)
	for e in g.edges {
		if e.from == from_id {
			append(&next, e.to)
		}
	}
	return next
}
