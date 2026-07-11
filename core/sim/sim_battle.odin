package sim

import "../combat"
import "../run"
import "core:mem/virtual"

// sim_process_battle_round applies a submitted Command_Battle_Choice as the
// player's (Side.A's) command for the current round, computes the scripted
// opponent's (Side.B's) command (ADR-0008), and resolves the round via
// core/combat. If the battle ends, hands off to run.run_finish_ship_battle
// and returns Sim to awaiting a travel choice.
sim_process_battle_round :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	assert(has_pending, "sim_process_battle_round called without a pending command")
	cmd, ok := pending.(Command_Battle_Choice)
	assert(ok, "sim_process_battle_round called without a pending Command_Battle_Choice")
	sim.pending_command = nil

	opponent_command := combat.combat_scripted_command(&sim.battle, .B)
	cmds := [combat.Side]Maybe(combat.Command){.A = cmd.combat_command, .B = opponent_command}

	// combat_events is per-tick scratch (issue #53): explicitly locked to
	// context.temp_allocator so the arena swap below (needed for
	// battle.jettisoned, issue #52) can't reach it — run_session frees it via
	// free_all(context.temp_allocator) once per driver iteration.
	combat_events := make([dynamic]combat.Event, 0, 0, context.temp_allocator)
	context.allocator = virtual.arena_allocator(&sim.arena)
	combat.combat_resolve_round(&sim.battle, cmds, &combat_events)

	for e in combat_events {
		append(events, Event(Event_Battle_Event{inner = e}))
	}
	append(events, Event(Event_Ship_Updated{ship = sim.player}))

	if !sim.battle.ended {
		append(events, Event(Event_Battle_Menu{may_leave = combat.combat_may_leave(&sim.battle, .A)}))
		return
	}

	zone, has_zone := sim.run_map.points[sim.current].zone.?
	assert(has_zone, "a Ship Battle point must have a zone")
	run_events := make([dynamic]run.Event, 0, 0, context.temp_allocator)
	run.run_finish_ship_battle(&sim.battle, &sim.player, &sim.active_encounter, zone, sim.steps, &run_events)
	sim_forward_encounter_resolved(run_events, events)

	sim.resolved[sim.current] = true
	sim.phase = .Awaiting_Travel_Choice
}
