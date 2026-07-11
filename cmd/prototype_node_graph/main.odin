package prototype_node_graph

// PROTOTYPE shell for issue #60 -- see generator.odin for the question this
// answers. Run with: odin run cmd/prototype_node_graph -- [seed ...]
// No args prints three default sample seeds; pass your own to explore more.

import "core:fmt"
import "core:os"
import "core:strconv"

main :: proc() {
	seeds := parse_seeds(os.args[1:])
	defer delete(seeds)

	fmt.println("PROTOTYPE for issue #60 -- node graph generation algorithm.")
	fmt.println("Run again with different seeds to see more samples, e.g.:")
	fmt.println("  odin run cmd/prototype_node_graph -- 7 8 9")
	fmt.println()

	for seed, i in seeds {
		if i > 0 {
			fmt.println()
		}
		render_sample(seed, default_config)
	}
}

parse_seeds :: proc(args: []string) -> []u64 {
	if len(args) == 0 {
		defaults := make([]u64, 3)
		defaults[0], defaults[1], defaults[2] = 1, 2, 3
		return defaults
	}
	seeds := make([]u64, len(args))
	for arg, i in args {
		n, ok := strconv.parse_u64(arg)
		if !ok {
			fmt.eprintfln("not a valid seed: %q", arg)
			os.exit(1)
		}
		seeds[i] = n
	}
	return seeds
}

render_sample :: proc(seed: u64, cfg: Config) {
	g := generate(seed, cfg)
	defer graph_destroy(&g)
	a := analyze(g)
	defer analysis_destroy(&a)

	adj := make(map[int][dynamic]int)
	defer {
		for _, v in adj {
			delete(v)
		}
		delete(adj)
	}
	for edge in g.edges {
		neighbors := adj[edge.from]
		append(&neighbors, edge.to)
		adj[edge.from] = neighbors
	}

	fmt.printfln(
		"====== seed %d  (nodes_per_zone=%d layer_width=%d..%d extra_branch_max=%d) ======",
		seed, cfg.nodes_per_zone, cfg.layer_width_min, cfg.layer_width_max, cfg.extra_branch_max,
	)

	for layer, li in g.layers {
		fmt.printf("L%d %-9s", li, layer_label(g, layer, li))
		for id in layer {
			fmt.printf("  %d->%v", id, adj[id][:])
		}
		fmt.println()
	}

	fmt.println()
	fmt.printfln("nodes: %d   reachable from Start: %d/%d", len(g.nodes), a.reachable_from_start, len(g.nodes))
	if len(a.unreachable) > 0 {
		fmt.printfln("  UNREACHABLE: %v", a.unreachable)
	}
	if len(a.dead_ends) > 0 {
		fmt.printfln("  DEAD ENDS: %v", a.dead_ends)
	} else {
		fmt.println("  dead ends: none")
	}
	fmt.printfln("out-degree (non-Goal): min %d max %d", a.min_out_degree, a.max_out_degree)
	fmt.printfln("in-degree  (non-Start): min %d max %d", a.min_in_degree, a.max_in_degree)
	fmt.printfln("distinct Start->Goal paths: %d", a.paths_start_to_goal)
}

layer_label :: proc(g: Graph, layer: []int, li: int) -> string {
	if li == 0 {
		return "Start"
	}
	if li == len(g.layers) - 1 {
		return "Goal"
	}
	for node in g.nodes {
		if node.id != layer[0] {
			continue
		}
		switch node.zone {
		case .Coastal:
			return "Coastal"
		case .Open_Sea:
			return "OpenSea"
		case .Deep:
			return "Deep"
		}
	}
	return "?"
}
