package voyage

import "core:slice"

// Travel legality: which of a Node's edges a ship may traverse from where it
// stands, given where it has already been. The voyage's single legal-move
// authority — shared by the Sim's travel gate, the UI's reachable-next
// affordance, and tests — separate from Map generation (generation.odin) and
// arrival (encounter.odin).

// voyage_neighbor_is_legal reports whether travel from current to neighbor is
// allowed, assuming they share an edge: forward or lateral (same-or-higher
// layer) is always legal; backward (lower layer) only to an already-visited node.
voyage_neighbor_is_legal :: proc(m: Map, current, neighbor: Node_ID, visited: []bool) -> bool {
	if m.nodes[neighbor].layer >= m.nodes[current].layer {
		return true
	}
	return visited[neighbor]
}

// voyage_travel_options returns the ids legally reachable from current given
// visited (see voyage_neighbor_is_legal). The returned slice is Tick-lifetime
// scratch from context.temp_allocator (ADR-0010), reclaimed at the caller's
// free_all boundary — never hand-freed.
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
// voyage_travel_options for a single destination: dest must share an edge with
// current and pass voyage_neighbor_is_legal.
voyage_can_travel_to :: proc(m: Map, current: Node_ID, visited: []bool, dest: Node_ID) -> bool {
	return(
		slice.contains(m.edges[current], dest) &&
		voyage_neighbor_is_legal(m, current, dest, visited) \
	)
}

// voyage_forward_option picks a deeper-layer neighbour out of `options` — already-legal
// destinations the Sim emitted — falling back to the first. It is how a driver with no
// player (headless's auto-player, capture's scripted walk) heads for the Haven instead of
// wandering the graph. It decides nothing about legality: that is voyage_travel_options'
// answer, and this only chooses among it.
voyage_forward_option :: proc(m: Map, current: Node_ID, options: []Node_ID) -> Node_ID {
	assert(len(options) > 0, "no legal travel option from the current node")
	for dest in options {
		if m.nodes[dest].layer > m.nodes[current].layer {
			return dest
		}
	}
	return options[0]
}
