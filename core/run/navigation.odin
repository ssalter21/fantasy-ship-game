package run

// Travel legality: the rules deciding which of a Node's edges a ship may
// actually traverse from where it stands, given where it has already been.
// This is the run's navigation seam — the single legal-move authority shared
// by the Sim's travel gate, the UI's reachable-next affordance, and tests —
// kept separate from how the Map is generated (generation.odin) and from what
// happens on arrival (encounter.odin).

// run_neighbor_is_legal reports whether travel from current to neighbor is
// allowed (assuming they share an edge): a forward or lateral neighbor (same
// or higher layer) is always legal; a backward neighbor (lower layer) is
// legal only by retrace to an already-visited node.
run_neighbor_is_legal :: proc(m: Map, current, neighbor: int, visited: []bool) -> bool {
	if m.nodes[neighbor].layer >= m.nodes[current].layer {
		return true
	}
	return visited[neighbor]
}

// run_travel_options is the single seam every legal-move consumer shares (the
// Sim's travel gate, the UI's reachable-next affordance, and tests): the ids
// legally reachable from current given visited — forward and lateral
// neighbors always, backward neighbors only if already visited. Caller owns
// the returned slice.
run_travel_options :: proc(m: Map, current: int, visited: []bool) -> []int {
	options: [dynamic]int
	for neighbor in m.edges[current] {
		if run_neighbor_is_legal(m, current, neighbor, visited) {
			append(&options, neighbor)
		}
	}
	return options[:]
}

// run_can_travel_to is the allocation-free predicate form of
// run_travel_options for a single destination — dest must both share an edge
// with current and satisfy the legality rule. The Sim's travel gate uses this
// to assert against illegal (non-neighbor or backward-unvisited) destinations.
run_can_travel_to :: proc(m: Map, current: int, visited: []bool, dest: int) -> bool {
	for neighbor in m.edges[current] {
		if neighbor == dest {
			return run_neighbor_is_legal(m, current, dest, visited)
		}
	}
	return false
}
