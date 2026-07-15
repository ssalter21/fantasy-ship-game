package sim

import "../combat"
import "../run"

// sim_process_travel applies a submitted Command_Travel_To (issue #24):
// arrives at the target node, and if it's an as-yet-unresolved Encounter,
// triggers that encounter ("auto-triggers, no decline"). The very first call
// — before any travel choice has been submitted — has nothing to apply yet
// and just announces the run's starting state, broadcasting the masked
// public map (graph shape + landmarks, non-revealing encounters' stages withheld
// — the hiding contract) rather than the private run_map.
//
// Travel is gated by run_travel_options' legality rule (forward and lateral
// neighbors always, backward neighbors only by retrace to an already-visited
// node): an illegal destination is a driver bug and asserts, matching the
// assert-on-driver-bug style of the phase checks. An Encounter node's effect
// still fires only once — resolved[] tracks that, so re-arriving after a
// retrace is a no-op. A .Port node instead opens its shop (issue #98) on every
// arrival, since a Port is a revisitable landmark whose stock never resolves;
// Start (the home port) carries no shop and stays a pure pass-through waypoint.
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
		run.run_can_travel_to(sim.run_map, sim.current, sim.visited, cmd.node_id),
		"Command_Travel_To to a node that is not a legal neighbor of the current position",
	)

	already_resolved := sim.resolved[cmd.node_id]
	node := sim.run_map.nodes[cmd.node_id]

	sim.current = cmd.node_id
	sim.visited[cmd.node_id] = true
	sim.steps += 1
	append(events, Event(Event_Arrived_At_Node{node = node}))
	append(events, Event(Event_Ship_Updated{ship = sim.player}))

	// A Port opens its shop every arrival (issue #98) — no resolved[] gate, since
	// a Port never resolves. sim_open_shop no-ops a shopless port (Start), leaving
	// the ship at a travel choice.
	if node.kind == .Port {
		sim_open_shop(sim, node, events)
		return
	}

	if already_resolved || node.kind != .Encounter {
		return
	}

	encounter, _ := node.encounter.?

	// An Encounter is an ordered stage list walked by a cursor (ADR-0014), but
	// this still fires only its first stage: the generic walk — advancing the
	// cursor on a completed stage, stopping on a halted one, and collapsing these
	// per-primitive phases into one path — is issue #131. Every recipe in today's
	// catalog is one stage long (catalog.odin), so first-stage-only and the real
	// walk agree exactly; the assert is what fails loudly if a multi-stage recipe
	// (#138) lands before the walk does.
	assert(encounter.count == 1, "sim fires only an encounter's first stage until the generic stage walk lands (#131)")
	stage, _ := run.run_encounter_current(encounter)

	switch s in stage {
	case run.Stage_Fight:
		sim.active_encounter = s
		sim.battle = run.run_start_battle(&sim.player, &sim.active_encounter)
		append(events, Event(Event_Ship_Battle_Sighted{opponent = sim.active_encounter.opponent}))
		append(events, Event(Event_Battle_Menu{may_leave = combat.combat_may_leave(&sim.battle, .A)}))
		sim.phase = .Awaiting_Battle_Command

	case run.Stage_Offer:
		sim.item_offer_options = s.options
		append(events, Event(Event_Item_Offer_Presented{options = sim.item_offer_options}))
		sim.phase = .Awaiting_Item_Choice

	case run.Stage_Trade:
		zone, has_zone := node.zone.?
		assert(has_zone, "an Encounter node must have a zone")
		snap := run.run_apply_stat_trade(&sim.player, s, zone, sim.steps)
		sim_emit_encounter_resolved(sim, snap, events)
		append(events, Event(Event_Ship_Updated{ship = sim.player}))
		sim.resolved[cmd.node_id] = true

	case run.Stage_Shop:
		// Unreachable until Ports are placed as the [Shop] recipe (#134) and the
		// Sim's per-Port shop state collapses into the stage (#137) — today a shop
		// hangs off a .Port node, handled above, and no catalog recipe authors a
		// Shop stage.
		assert(false, "a Shop stage on an Encounter node needs the Port bucket (#134) and the Shop stage's Sim path (#137)")

	case run.Stage_Reward:
		// Unreachable until Reward has a payload (#132) and a primitive to spend it
		// (#133); no catalog recipe authors one yet.
		assert(false, "a Reward stage needs its grant decided (#132) and its primitive built (#133)")
	}
}
