package sim

import "../combat"
import "../run"

// sim_process_battle_round applies a submitted Command_Battle_Choice as the
// player's (Side.A's) command for the current round, computes the scripted
// opponent's (Side.B's) command (ADR-0008), and resolves the round via
// core/combat. If the battle ends, it asks run.run_finish_ship_battle what that
// ending means to the Fight stage and hands the outcome back to the walk.
sim_process_battle_round :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	assert(has_pending, "sim_process_battle_round called without a pending command")
	cmd, ok := pending.(Command_Battle_Choice)
	assert(ok, "sim_process_battle_round called without a pending Command_Battle_Choice")
	sim.pending_command = nil

	opponent_command := combat.combat_scripted_command(&sim.battle, .B)
	cmds := [combat.Side]Maybe(combat.Command){.A = cmd.combat_command, .B = opponent_command}

	// combat_events is per-tick scratch (issue #53): explicitly locked to
	// context.temp_allocator so the arena-scoped block below (needed for
	// battle.jettisoned, issue #52) can't reach it — run_session frees it via
	// free_all(context.temp_allocator) once per driver iteration.
	combat_events := make([dynamic]combat.Event, 0, 0, context.temp_allocator)
	{
		// A Jettison Cargo command records its fitting on sim.battle.jettisoned
		// (issue #52: run-lifetime, freed only by sim_destroy), so it must
		// allocate from the Sim's own run-scoped arena rather than whatever
		// transient allocator the caller happens to be using.
		context.allocator = sim_arena_allocator(sim)
		combat.combat_resolve_round(&sim.battle, cmds, &combat_events)
	}

	for e in combat_events {
		append(events, Event(Event_Battle_Event{inner = e}))
	}
	append(events, Event(Event_Ship_Updated{ship = sim.player}))

	if !sim.battle.ended {
		append(events, Event(Event_Battle_Menu{may_leave = combat.combat_may_leave(&sim.battle, .A)}))
		return
	}

	outcome := run.run_finish_ship_battle(&sim.battle)

	// Sinking is **neither** outcome (ADR-0014): the run is over by permadeath
	// (ADR-0006), so the walk stops dead rather than completing the Fight and applying
	// whatever came after it to a sunk ship — a [Fight, Reward] must not pay out to a
	// captain who went down with it. The node is never resolved, so it emits no
	// Ghost_Snapshot either (issue #162) — the one encounter in a run that leaves no
	// ghost, and Event_Run_Ended is what marks it. sim_tick's status check ends the run
	// on the way out of this tick, and it is deliberately not consulted here: the walk
	// stopping and the run ending are separate facts, and only one of them is this
	// proc's.
	if !run.run_can_travel(&sim.player) {
		return
	}

	sim_advance_stage(sim, outcome, events)
	sim_walk_encounter(sim, events)
}
