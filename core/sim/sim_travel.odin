package sim

import "../voyage"

// sim_process_travel applies a submitted Command_Travel_To: it arrives at the target
// node and, if the node holds an unresolved encounter, hands off to the stage walk that
// fires it (auto-triggers, no decline). The very first call — before any travel choice
// has been submitted — has nothing to apply and just announces the voyage's starting
// state, broadcasting the masked public map (graph shape + landmarks, hidden encounters'
// stages withheld) rather than the private voyage_map.
//
// An illegal destination is a driver bug and asserts (voyage_can_travel_to's legality
// rule), matching the phase checks. An encounter fires only once — resolved[] tracks
// that, so re-arriving after a retrace is a no-op. Every node is walked and resolved the
// same way, Port included (ADR-0014); Start and Haven are pass-through by carrying no
// encounter, not by being special-cased.
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

	// The stage walk asks nothing about what kind of node this is — a landmark simply
	// has no encounter to find — so Start, Haven, and Port need no branch of their own.
	if already_resolved {
		return
	}
	sim_walk_encounter(sim, events)
}
