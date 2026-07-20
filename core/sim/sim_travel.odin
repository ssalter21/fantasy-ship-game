package sim

import "../voyage"

// sim_process_at_anchor is the between-encounters tick. The at-anchor decision admits two
// command variants over the one Awaiting_Travel_Choice phase (ADR-0020's "free reallocation
// outside battle"): sail with a Command_Travel_To, or refit in place with a free Command_Refit.
// It routes on the *pending* variant — peeked here rather than unwrapped by sim_take_pending's
// exact-variant assert — which is what lets one phase serve both without a phase per command
// (see the Phase doc comment; it mirrors Awaiting_Battle_Command's inner combat.Command). The
// first tick carries no pending command and falls through to travel, announcing the voyage's
// start.
sim_process_at_anchor :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	if pending, has_pending := sim.pending_command.?; has_pending {
		if _, is_refit := pending.(Command_Refit); is_refit {
			sim_process_anchor_refit(sim, events)
			return
		}
	}
	sim_process_travel(sim, events)
}

// sim_process_anchor_refit applies a free loadout edit made at anchor. There is no pending
// incoming item — that is a stage's grant (ADR-0012), and none is open between encounters — so
// only Move, Remove and Jettison_Cargo can land; an Install or Replace with nothing to place is refused
// (Event_Refit_Rejected) through the very sim_refit_* helpers a granted Refit uses, so the fit
// rule (ADR-0004) and cargo re-stow (ADR-0020) hold in one place. The phase never leaves
// Awaiting_Travel_Choice, so sim_settle re-emits the legal destinations and the surface stays
// live — the edit applies and *stays* at anchor. Refit_Finish is a no-op here: there is no refit
// sub-mode to close and no stage walk to resume (that is sim_process_refit's Finish), and the UI
// leaves the Build surface by sailing, not by finishing.
sim_process_anchor_refit :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	cmd := sim_take_pending(sim, Command_Refit)
	sim_refit_apply(sim, cmd.command, events)
}

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
	if _, has_pending := sim.pending_command.?; !has_pending {
		public_map := voyage.Map{nodes = sim.public_nodes, edges = sim.voyage_map.edges}
		append(events, Event(Event_Voyage_Started{voyage_map = public_map, ship = sim.player}))
		return
	}
	cmd := sim_take_pending(sim, Command_Travel_To)

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
