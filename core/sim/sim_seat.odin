package sim

import "../voyage"

// The Sim's fixture seam: bringing a Sim into existence seated at a chosen point of a voyage,
// rather than at its start. sim_create deals a whole random map and parks the ship at Start —
// the only shape production ever needs — so a caller that wants a ship standing in front of one
// specific stage has, without this, no way to ask for it through the interface.

// sim_seat_at_stage seats the ship at node `id` in front of whatever that node opens with,
// leaving `events` holding exactly the batch the arrival emitted and the Sim awaiting the
// decision that stage asks for. Passing `stages` plants them at the node first, so a caller
// names the exact recipe it means to face — including a multi-stage one no catalog entry
// authors — instead of hunting a seed whose generated map happens to deal one. Passing none
// seats the ship in front of the content generation already put there.
//
// The seated state is reached the way a sailed-to one is: the walk decides the phase, and
// sim_settle raises awaiting_decision. So a seated Sim answers Commands exactly as one that
// travelled here does, and the seating never has to restate the tick's tail.
//
// Seating is not travel — it places the ship at `id` outright, with no legal route required, so
// a fixture can seat in front of a node anywhere on the map. What it shares with travel is
// everything downstream of the arrival.
sim_seat_at_stage :: proc(sim: ^Sim, id: Node_ID, events: ^[dynamic]Event, stages: ..voyage.Stage) {
	if len(stages) > 0 {
		sim_plant_encounter(sim, id, stages)
	}

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
// zone is one no stage list can be planted on — asserted here, where the caller named the node,
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
