package sim

import "../voyage"

// sim_process_travel applies a submitted Command_Travel_To (issue #24):
// arrives at the target node, and if it holds an as-yet-unresolved Encounter,
// hands off to the stage walk that fires it ("auto-triggers, no decline"). The
// very first call — before any travel choice has been submitted — has nothing to
// apply yet and just announces the voyage's starting state, broadcasting the masked
// public map (graph shape + landmarks, hidden encounters' stages withheld
// — the hiding contract) rather than the private voyage_map.
//
// Travel is gated by voyage_travel_options' legality rule (forward and lateral
// neighbors always, backward neighbors only by retrace to an already-visited
// node): an illegal destination is a driver bug and asserts, matching the
// assert-on-driver-bug style of the phase checks. An encounter fires only once —
// resolved[] tracks that, so re-arriving after a retrace is a no-op.
//
// **Every** encounter, Port included (issue #131). Ports used to re-open their shop
// on each arrival, exempt from resolved[] as revisitable landmarks; ADR-0014 drops
// that, so a Port is walked and resolved like anything else and its stock is not
// something to come back to. Start and Haven are still pass-through waypoints, but by
// carrying no encounter rather than by being asked what kind they are.
sim_process_travel :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	if !has_pending {
		public_map := voyage.Map{nodes = sim.public_nodes, edges = sim.voyage_map.edges}
		append(events, Event(Event_Voyage_Started{voyage_map = public_map, ship = sim.player}))
		return
	}
	cmd, has_cmd := pending.(Command_Travel_To)
	assert(has_cmd, "sim_process_travel called without a pending Command_Travel_To")
	sim.pending_command = nil

	assert(voyage.voyage_can_travel(&sim.player), "Command_Travel_To submitted while the ship could no longer travel")
	assert(
		voyage.voyage_can_travel_to(sim.voyage_map, sim.current, sim.visited, cmd.node_id),
		"Command_Travel_To to a node that is not a legal neighbor of the current position",
	)

	already_resolved := sim.resolved[cmd.node_id]
	node := sim.voyage_map.nodes[cmd.node_id]

	sim.current = cmd.node_id
	sim.visited[cmd.node_id] = true
	sim.steps += 1
	append(events, Event(Event_Arrived_At_Node{node = node}))
	append(events, Event(Event_Ship_Updated{ship = sim.player}))

	// An arrival hands off to the generic stage walk and asks nothing about what
	// kind of node this is (issue #131): the walk finds no encounter at a landmark
	// and leaves the ship at a travel choice, so Start and Haven need no branch of
	// their own — and neither does a Port, which generation bakes as a node
	// carrying the [Shop] recipe (issue #134).
	if already_resolved {
		return
	}
	sim_walk_encounter(sim, events)
}
