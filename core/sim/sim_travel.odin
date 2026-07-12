package sim

import "../combat"
import "../run"

// sim_process_travel applies a submitted Command_Travel_To (issue #24):
// arrives at the target point, and if it's an as-yet-unresolved Encounter,
// triggers that encounter ("auto-triggers, no decline"). The very first call
// — before any travel choice has been submitted — has nothing to apply yet
// and just announces the run's starting state, broadcasting the masked
// public map (graph shape + landmarks, encounter kinds withheld — the hiding
// contract) rather than the private run_map.
//
// Travel is gated by run_travel_options' legality rule (forward and lateral
// neighbors always, backward neighbors only by retrace to an already-visited
// node): an illegal destination is a driver bug and asserts, matching the
// assert-on-driver-bug style of the phase checks. An Encounter point's effect
// still fires only once — resolved[] tracks that, so re-arriving after a
// retrace is a no-op, like a Port. Start/Port points have no shop system yet,
// so they're pure pass-through waypoints in this slice's UI.
sim_process_travel :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	if !has_pending {
		public_map := run.Map{points = sim.public_points, edges = sim.run_map.edges}
		append(events, Event(Event_Run_Started{run_map = public_map, ship = sim.player}))
		return
	}
	cmd, has_cmd := pending.(Command_Travel_To)
	assert(has_cmd, "sim_process_travel called without a pending Command_Travel_To")
	sim.pending_command = nil

	assert(run.run_can_travel(&sim.player), "Command_Travel_To submitted while the ship could no longer travel")
	assert(
		run.run_can_travel_to(sim.run_map, int(sim.current), sim.visited, int(cmd.point_id)),
		"Command_Travel_To to a point that is not a legal neighbor of the current position",
	)

	already_resolved := sim.resolved[cmd.point_id]
	point := sim.run_map.points[cmd.point_id]

	sim.current = cmd.point_id
	sim.visited[cmd.point_id] = true
	sim.steps += 1
	append(events, Event(Event_Arrived_At_Point{point = point}))
	append(events, Event(Event_Ship_Updated{ship = sim.player}))

	if already_resolved || point.kind != .Encounter {
		return
	}

	encounter, _ := point.encounter.?
	switch enc in encounter {
	case run.Encounter_Ship_Battle:
		sim.active_encounter = enc
		sim.battle = run.run_start_battle(&sim.player, &sim.active_encounter)
		append(events, Event(Event_Ship_Battle_Sighted{opponent = sim.active_encounter.opponent}))
		append(events, Event(Event_Battle_Menu{may_leave = combat.combat_may_leave(&sim.battle, .A)}))
		sim.phase = .Awaiting_Battle_Command

	case run.Encounter_Upgrade_Offer:
		sim.upgrade_options = run.run_upgrade_offer_options(enc)
		append(events, Event(Event_Upgrade_Offer_Presented{options = sim.upgrade_options}))
		sim.phase = .Awaiting_Upgrade_Choice

	case run.Encounter_Stat_Trade:
		zone, has_zone := point.zone.?
		assert(has_zone, "an Encounter point must have a zone")
		// run_events is per-tick scratch (issue #53): explicitly locked to
		// context.temp_allocator regardless of the arena-scoped block below,
		// needed for the Ghost_Snapshot run_apply_stat_trade captures (issue
		// #52) — run_session frees it via free_all(context.temp_allocator)
		// once per driver iteration.
		run_events := make([dynamic]run.Event, 0, 0, context.temp_allocator)
		{
			// The captured Ghost_Snapshot's layout must outlive this call
			// (issue #52: it escapes via Event_Encounter_Resolved), so it's
			// allocated from the Sim's own run-scoped arena rather than
			// whatever transient allocator the caller happens to be using.
			context.allocator = sim_arena_allocator(sim)
			run.run_apply_stat_trade(&sim.player, enc, zone, sim.steps, &run_events)
		}
		sim_forward_encounter_resolved(run_events, events)
		append(events, Event(Event_Ship_Updated{ship = sim.player}))
		sim.resolved[cmd.point_id] = true
	}
}
