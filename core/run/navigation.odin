package run

// Travel legality: the rules deciding which of a Node's edges a ship may
// actually traverse from where it stands, given where it has already been.
// This is the voyage's navigation seam — the single legal-move authority shared
// by the Sim's travel gate, the UI's reachable-next affordance, and tests —
// kept separate from how the Map is generated (generation.odin) and from what
// happens on arrival (encounter.odin).

// voyage_neighbor_is_legal reports whether travel from current to neighbor is
// allowed (assuming they share an edge): a forward or lateral neighbor (same
// or higher layer) is always legal; a backward neighbor (lower layer) is
// legal only by retrace to an already-visited node.
voyage_neighbor_is_legal :: proc(m: Map, current, neighbor: Node_ID, visited: []bool) -> bool {
	if m.nodes[neighbor].layer >= m.nodes[current].layer {
		return true
	}
	return visited[neighbor]
}

// voyage_travel_options is the single seam every legal-move consumer shares (the
// Sim's travel gate, the UI's reachable-next affordance, and tests): the ids
// legally reachable from current given visited — forward and lateral
// neighbors always, backward neighbors only if already visited. The returned
// slice is Tick-lifetime scratch from context.temp_allocator (ADR-0010),
// reclaimed at the caller's free_all boundary — never hand-freed.
voyage_travel_options :: proc(m: Map, current: Node_ID, visited: []bool) -> []Node_ID {
	options := make([dynamic]Node_ID, context.temp_allocator)
	for neighbor in m.edges[current] {
		if voyage_neighbor_is_legal(m, current, neighbor, visited) {
			append(&options, neighbor)
		}
	}
	return options[:]
}

// voyage_can_travel_to is the allocation-free predicate form of
// voyage_travel_options for a single destination — dest must both share an edge
// with current and satisfy the legality rule. The Sim's travel gate uses this
// to assert against illegal (non-neighbor or backward-unvisited) destinations.
voyage_can_travel_to :: proc(m: Map, current: Node_ID, visited: []bool, dest: Node_ID) -> bool {
	for neighbor in m.edges[current] {
		if neighbor == dest {
			return voyage_neighbor_is_legal(m, current, dest, visited)
		}
	}
	return false
}
