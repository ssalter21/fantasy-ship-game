package sim

import "../voyage"

// The Sim's fixture seam: bringing a Sim into existence seated at a chosen point of a voyage,
// rather than at its start. sim_create deals a whole random map and parks the ship at Start —
// the only shape production ever needs — so a caller that wants a ship standing in front of one
// specific stage has, without this, no way to ask for it through the interface.
//
// Each entry names *what* it wants to face — a stage list, a generated stage kind, a bare
// waypoint — and finds a node fit to face it on itself, so no scenario carries a node index.

// sim_seat_at_stage seats the ship in front of `stages`, planted at a fresh node the seating
// picks itself, leaving `events` holding exactly the batch the arrival emitted and the Sim
// awaiting the decision the opening stage asks for. The caller names the exact recipe it means
// to face — including a multi-stage one no catalog entry authors — instead of hunting a seed
// whose generated map happens to deal one.
//
// The seated state is reached the way a sailed-to one is: the walk decides the phase, and
// sim_settle raises awaiting_decision. So a seated Sim answers Commands exactly as one that
// travelled here does, and the seating never has to restate the tick's tail.
sim_seat_at_stage :: proc(sim: ^Sim, events: ^[dynamic]Event, stages: ..voyage.Stage) {
	assert(len(stages) > 0, "seated no stages — seat at a generated node or a waypoint instead")
	id := sim_seatable_node(sim)
	sim_plant_encounter(sim, id, stages)
	sim_seat(sim, id, events)
}

// sim_seat_at_generated seats the ship in front of a node whose *generated* content opens with
// primitive `kind`, leaving that content in place — for the scenarios about what generation
// dealt rather than what a test authored. The node is found by what it opens with, the same
// question the walk, the Sim's mask and the map view all ask of a node.
sim_seat_at_generated :: proc(sim: ^Sim, kind: voyage.Stage_Kind, events: ^[dynamic]Event) {
	for node in sim.voyage_map.nodes {
		if sim.visited[node.id] {
			continue
		}
		encounter, has_encounter := node.encounter.?
		if !has_encounter {
			continue
		}
		opening, walking := voyage.voyage_encounter_current(encounter)
		if walking && voyage.voyage_stage_kind(opening) == kind {
			sim_seat(sim, node.id, events)
			return
		}
	}
	panic("this map generated no unvisited node opening with the requested stage kind")
}

// sim_seat_at_waypoint seats the ship at a node holding no encounter — a pure landmark
// (ADR-0014: Start and Haven hold none) — so a scenario can watch the walk find nothing.
// Visited nodes are not skipped: the first encounter-less node is Start, and seating there
// must stay legal even though the ship has been there since sim_create.
sim_seat_at_waypoint :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	for node in sim.voyage_map.nodes {
		if _, has_encounter := node.encounter.?; !has_encounter {
			sim_seat(sim, node.id, events)
			return
		}
	}
	panic("every node on this map holds an encounter — no waypoint to seat at")
}

// sim_seatable_node picks the node a planted seating lands on: the lowest-id unvisited node
// bearing a zone. A zone is required because a planted stage is scaled by the stakes of the
// node it sits on; unvisited, so consecutive seatings face fresh nodes rather than re-planting
// one. Lowest-id keeps the choice deterministic — the first zoned node sits on the first
// zone's entrance layer at depth 0, so planted content scales identically on every seed.
sim_seatable_node :: proc(sim: ^Sim) -> Node_ID {
	for node in sim.voyage_map.nodes {
		if _, zoned := node.zone.?; zoned && !sim.visited[node.id] {
			return node.id
		}
	}
	panic("no unvisited zoned node left to seat at")
}

// sim_seat places the ship at node `id` outright and hands everything downstream of an
// arrival to the real machinery. Seating is not travel — no legal route is required, so a
// fixture can seat in front of a node anywhere on the map; what it shares with travel is
// the walk and the settle.
sim_seat :: proc(sim: ^Sim, id: Node_ID, events: ^[dynamic]Event) {
	sim.current = id
	sim.visited[id] = true

	clear(events)
	sim_walk_encounter(sim, events)
	sim_settle(sim, events)
}

// sim_plant_encounter makes `stages` the unresolved encounter at node `id` and re-masks the
// node's public view, so the hiding contract (ADR-0009) keeps describing what the node now
// holds rather than what generation dealt it.
//
// A stage is scaled by the stakes of the node it sits on (sim_current_site), so a node with no
// zone is one no stage list can be planted on — asserted here, where the node was chosen,
// rather than deep inside whichever primitive reads the zone first.
sim_plant_encounter :: proc(sim: ^Sim, id: Node_ID, stages: []voyage.Stage) {
	assert(len(stages) <= voyage.ENCOUNTER_MAX_STAGES, "seated a stage list longer than an Encounter can hold")
	_, zoned := sim.voyage_map.nodes[id].zone.?
	assert(zoned, "seated an encounter on a node with no zone to scale it by")

	encounter := voyage.Encounter{count = len(stages)}
	for stage, i in stages {
		encounter.stages[i] = stage
	}

	sim.voyage_map.nodes[id].kind = .Encounter
	sim.voyage_map.nodes[id].encounter = encounter
	sim.resolved[id] = false
	sim.public_nodes[id] = sim_masked_node(sim.voyage_map.nodes[id])
}
