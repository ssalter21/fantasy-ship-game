package prototype_node_graph

// PROTOTYPE -- throwaway code answering issue #60 (wayfinder ticket, part of
// map #59 "Node-graph run map: connected topology, hidden encounters, scale
// to 50"). Question: what algorithm procedurally generates ~50 encounter
// nodes connected by edges, grown across three sequential zone phases
// (Coastal -> Open_Sea -> Deep), guaranteeing Start->Goal reachability and
// real forward-only branching with no dead ends?
//
// This file is the pure generator + analysis: no I/O, portable enough to
// lift into core/run once #60 is resolved. main.odin is the throwaway CLI
// shell around it. Delete this whole directory (or fold the validated pieces
// into core/run) once the ticket closes.

import "base:runtime"
import "core:math/rand"

Zone :: enum {
	Coastal,
	Open_Sea,
	Deep,
}

// Config is every tunable constant the algorithm exposes (issue #60's "what
// are the tunable constants" question) -- named so the real implementation
// can lift these directly into core/run's existing named-constant style
// (SHIP_BATTLE_HP_PER_TIER and friends in run.odin).
Config :: struct {
	nodes_per_zone:   int, // encounter nodes per zone; 3 zones * this ~= issue #60's "~50 nodes"
	layer_width_min:  int, // fewest nodes in one generation layer
	layer_width_max:  int, // most nodes in one generation layer
	extra_branch_max: int, // 0..this many *additional* random forward edges per node, beyond the one guaranteed edge -- this is what produces real branching choice
}

default_config := Config {
	nodes_per_zone   = 17,
	layer_width_min  = 3,
	layer_width_max  = 5,
	extra_branch_max = 2,
}

Node :: struct {
	id:    int,
	zone:  Zone, // Start borrows Coastal's zone, Goal borrows Deep's -- neither is a real encounter
	layer: int, // 0 at Start, increases by one per generation layer, highest at Goal
}

Edge :: struct {
	from, to: int, // node ids; always from a lower layer to a higher one -- forward-only, no backtracking (map #59's Notes)
}

Graph :: struct {
	nodes:    []Node,
	edges:    []Edge,
	start_id: int,
	goal_id:  int,
	layers:   [][]int, // node ids grouped by layer, in layer order
}

graph_destroy :: proc(g: ^Graph) {
	delete(g.nodes)
	delete(g.edges)
	for layer in g.layers {
		delete(layer)
	}
	delete(g.layers)
}

// generate builds one candidate node graph from seed -- same seed always
// produces the same graph (issue #60's reproducibility question).
generate :: proc(seed: u64, cfg: Config) -> Graph {
	state := rand.create_u64(seed)
	gen := runtime.default_random_generator(&state)

	nodes := make([dynamic]Node)
	layers := make([dynamic][dynamic]int)

	start_id := 0
	append(&nodes, Node{id = start_id, zone = .Coastal, layer = 0})
	append(&layers, make([dynamic]int))
	append(&layers[0], start_id)

	// Three sequential phases (map #59's Notes): grow Coastal, then
	// Open_Sea continuing from Coastal's last layer, then Deep into Goal.
	next_id := 1
	for zone in Zone {
		budget := cfg.nodes_per_zone
		for budget > 0 {
			width := min(budget, cfg.layer_width_min + rand.int_max(cfg.layer_width_max - cfg.layer_width_min + 1, gen))
			layer_idx := len(layers)
			layer := make([dynamic]int)
			for _ in 0 ..< width {
				append(&nodes, Node{id = next_id, zone = zone, layer = layer_idx})
				append(&layer, next_id)
				next_id += 1
			}
			append(&layers, layer)
			budget -= width
		}
	}

	goal_id := next_id
	append(&nodes, Node{id = goal_id, zone = .Deep, layer = len(layers)})
	append(&layers, make([dynamic]int))
	append(&layers[len(layers) - 1], goal_id)

	edges := make([dynamic]Edge)
	for i in 0 ..< len(layers) - 1 {
		connect_layers(layers[i][:], layers[i + 1][:], cfg, gen, &edges)
	}

	out_layers := make([][]int, len(layers))
	for layer, i in layers {
		out_layers[i] = layer[:]
	}

	return Graph{nodes = nodes[:], edges = edges[:], start_id = start_id, goal_id = goal_id, layers = out_layers}
}

// connect_layers wires from -> to with three passes, in order:
//
//  1. every `to` node gets one incoming edge from a random `from` node --
//     guarantees Start->Goal reachability inductively (every node one layer
//     out is reachable the moment its own layer is).
//  2. every `from` node still at zero out-degree after (1) gets one forced
//     edge to a random `to` node -- guarantees no dead ends (every non-Goal
//     node has a way forward).
//  3. every `from` node gets 0..extra_branch_max additional random edges to
//     distinct `to` nodes -- this is what produces real branching choice
//     rather than one critical path with cosmetic stubs.
connect_layers :: proc(from, to: []int, cfg: Config, gen: runtime.Random_Generator, edges: ^[dynamic]Edge) {
	out_degree := make([]int, len(from))
	defer delete(out_degree)
	connected := make([]bool, len(from) * len(to)) // connected[fi*len(to)+ti]
	defer delete(connected)

	for ti in 0 ..< len(to) {
		fi := rand.int_max(len(from), gen)
		if !connected[fi * len(to) + ti] {
			connected[fi * len(to) + ti] = true
			out_degree[fi] += 1
			append(edges, Edge{from = from[fi], to = to[ti]})
		}
	}

	for fi in 0 ..< len(from) {
		if out_degree[fi] > 0 {
			continue
		}
		ti := rand.int_max(len(to), gen)
		connected[fi * len(to) + ti] = true
		out_degree[fi] += 1
		append(edges, Edge{from = from[fi], to = to[ti]})
	}

	for fi in 0 ..< len(from) {
		extra := rand.int_max(cfg.extra_branch_max + 1, gen)
		for _ in 0 ..< extra {
			if out_degree[fi] >= len(to) {
				break
			}
			ti := rand.int_max(len(to), gen)
			if connected[fi * len(to) + ti] {
				continue
			}
			connected[fi * len(to) + ti] = true
			out_degree[fi] += 1
			append(edges, Edge{from = from[fi], to = to[ti]})
		}
	}
}

// Analysis checks the properties issue #60 actually cares about: does this
// graph guarantee reachability and forward progress, and does it produce
// real branching rather than one critical path?
Analysis :: struct {
	reachable_from_start: int, // should equal len(graph.nodes)
	unreachable:          []int, // node ids not reachable from Start -- should be empty
	dead_ends:            []int, // non-Goal node ids with zero out-degree -- should be empty
	min_out_degree:       int, // over non-Goal nodes
	max_out_degree:       int,
	min_in_degree:        int, // over non-Start nodes
	max_in_degree:        int,
	paths_start_to_goal:  u64, // count of distinct forward paths -- >1 means real route choice
}

analyze :: proc(g: Graph) -> Analysis {
	out_degree := make(map[int]int)
	defer delete(out_degree)
	in_degree := make(map[int]int)
	defer delete(in_degree)
	adj := make(map[int][dynamic]int) // node id -> forward neighbor ids
	defer {
		for _, v in adj {
			delete(v)
		}
		delete(adj)
	}

	for node in g.nodes {
		out_degree[node.id] = 0
		in_degree[node.id] = 0
		adj[node.id] = make([dynamic]int)
	}
	for edge in g.edges {
		out_degree[edge.from] += 1
		in_degree[edge.to] += 1
		neighbors := adj[edge.from]
		append(&neighbors, edge.to)
		adj[edge.from] = neighbors
	}

	visited := make(map[int]bool)
	defer delete(visited)
	queue := make([dynamic]int)
	defer delete(queue)
	append(&queue, g.start_id)
	visited[g.start_id] = true
	head := 0
	for head < len(queue) {
		id := queue[head]
		head += 1
		for next in adj[id] {
			if !visited[next] {
				visited[next] = true
				append(&queue, next)
			}
		}
	}

	unreachable := make([dynamic]int)
	dead_ends := make([dynamic]int)
	for node in g.nodes {
		if !visited[node.id] {
			append(&unreachable, node.id)
		}
		if node.id != g.goal_id && out_degree[node.id] == 0 {
			append(&dead_ends, node.id)
		}
	}

	min_out, max_out := degree_range(g.nodes, out_degree, g.goal_id)
	min_in, max_in := degree_range(g.nodes, in_degree, g.start_id)

	// Path count via topological DP over layers: edges always go layer i ->
	// i+1, so processing layers back-to-front is already a valid
	// topological order.
	paths := make(map[int]u64)
	defer delete(paths)
	paths[g.goal_id] = 1
	for li := len(g.layers) - 2; li >= 0; li -= 1 {
		for id in g.layers[li] {
			total: u64 = 0
			for next in adj[id] {
				total += paths[next]
			}
			paths[id] = total
		}
	}

	return Analysis{
		reachable_from_start = len(visited),
		unreachable          = unreachable[:],
		dead_ends            = dead_ends[:],
		min_out_degree       = min_out,
		max_out_degree       = max_out,
		min_in_degree        = min_in,
		max_in_degree        = max_in,
		paths_start_to_goal  = paths[g.start_id],
	}
}

analysis_destroy :: proc(a: ^Analysis) {
	delete(a.unreachable)
	delete(a.dead_ends)
}

degree_range :: proc(nodes: []Node, degree: map[int]int, excluded_id: int) -> (lo, hi: int) {
	first := true
	for node in nodes {
		if node.id == excluded_id {
			continue
		}
		d := degree[node.id]
		if first {
			lo, hi = d, d
			first = false
		} else {
			lo = min(lo, d)
			hi = max(hi, d)
		}
	}
	return
}
