package sim

import "../combat"
import "../run"

// sim_process_travel applies a submitted Command_Travel_To (issue #24):
// arrives at the target node, and if it's an as-yet-unresolved Encounter,
// triggers that encounter ("auto-triggers, no decline"). The very first call
// — before any travel choice has been submitted — has nothing to apply yet
// and just announces the run's starting state, broadcasting the masked
// public map (graph shape + landmarks, encounter kinds withheld — the hiding
// contract) rather than the private run_map.
//
// Travel is gated by run_travel_options' legality rule (forward and lateral
// neighbors always, backward neighbors only by retrace to an already-visited
// node): an illegal destination is a driver bug and asserts, matching the
// assert-on-driver-bug style of the phase checks. An Encounter node's effect
// still fires only once — resolved[] tracks that, so re-arriving after a
// retrace is a no-op, like a Port. Start/Port nodes have no shop system yet,
// so they're pure pass-through waypoints in this slice's UI.
sim_process_travel :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	if !has_pending {
		public_map := run.Map{nodes = sim.public_nodes, edges = sim.run_map.edges}
		append(events, Event(Event_Run_Started{run_map = public_map, ship = sim.player}))
		return
	}
	cmd, has_cmd := pending.(Command_Travel_To)
	assert(has_cmd, "sim_process_travel called without a pending Command_Travel_To")
	sim.pending_command = nil

	assert(run.run_can_travel(&sim.player), "Command_Travel_To submitted while the ship could no longer travel")
	assert(
		run.run_can_travel_to(sim.run_map, int(sim.current), sim.visited, int(cmd.node_id)),
		"Command_Travel_To to a node that is not a legal neighbor of the current position",
	)

	already_resolved := sim.resolved[cmd.node_id]
	node := sim.run_map.nodes[cmd.node_id]

	sim.current = cmd.node_id
	sim.visited[cmd.node_id] = true
	sim.steps += 1
	append(events, Event(Event_Arrived_At_Node{node = node}))
	append(events, Event(Event_Ship_Updated{ship = sim.player}))

	if already_resolved || node.kind != .Encounter {
		return
	}

	encounter, _ := node.encounter.?
	switch enc in encounter {
	case run.Encounter_Ship_Battle:
		sim.active_encounter = enc
		sim.battle = run.run_start_battle(&sim.player, &sim.active_encounter)
		append(events, Event(Event_Ship_Battle_Sighted{opponent = sim.active_encounter.opponent}))
		append(events, Event(Event_Battle_Menu{may_leave = combat.combat_may_leave(&sim.battle, .A)}))
		sim.phase = .Awaiting_Battle_Command

	case run.Encounter_Item_Offer:
		sim.item_offer_options = enc.options
		append(events, Event(Event_Item_Offer_Presented{options = sim.item_offer_options}))
		sim.phase = .Awaiting_Item_Choice

	case run.Encounter_Stat_Trade:
		zone, has_zone := node.zone.?
		assert(has_zone, "an Encounter node must have a zone")
		snap := run.run_apply_stat_trade(&sim.player, enc, zone, sim.steps)
		sim_emit_encounter_resolved(sim, snap, events)
		append(events, Event(Event_Ship_Updated{ship = sim.player}))
		sim.resolved[cmd.node_id] = true
	}
}
