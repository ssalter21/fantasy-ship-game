package sim

import "../combat"
import "../voyage"

// sim_process_battle_round pairs Side.A's submitted command with the scripted
// opponent's (ADR-0008) and resolves one round via core/combat. On battle end it asks
// voyage_finish_ship_battle what that means to the Fight stage and hands the outcome back.
sim_process_battle_round :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	cmd := sim_take_pending(sim, Command_Battle_Choice)

	opponent_command := combat.combat_scripted_command(&sim.battle, .B)
	cmds := [combat.Side]Maybe(combat.Command){.A = cmd.combat_command, .B = opponent_command}

	// combat_events is per-tick scratch: temp_allocator, freed by run_session's
	// free_all once per driver iteration.
	combat_events := make([dynamic]combat.Event, 0, 0, context.temp_allocator)
	combat.combat_resolve_round(&sim.battle, cmds, &combat_events)

	for e in combat_events {
		append(events, Event(Event_Battle_Event{inner = e}))
	}
	append(events, Event(Event_Ship_Updated{ship = sim.player}))

	if !sim.battle.ended {
		append(events, Event(Event_Battle_Menu{may_break_off = combat.combat_may_break_off(&sim.battle, .A), round = sim.battle.round}))
		return
	}

	// Sinking is neither outcome (ADR-0014): permadeath ends the voyage (ADR-0006), so
	// the walk stops here rather than completing the Fight — a [Fight, Reward] must not
	// pay a captain who went down. Ending the voyage is sim_tick's job, not this proc's.
	// Returning before voyage_finish also keeps payout to survivors: a Destroyed ending
	// reaching voyage_finish is then always the player's kill, never a mutual sinking.
	if !voyage.voyage_can_travel(&sim.player) {
		return
	}

	// Only a wreck pays: the sunk opponent's hold is stowed into the player's, and the
	// stow reports the overflow lost above capacity (#157, #159) rather than this proc
	// recovering it from a before/after subtraction. Event_Ship_Updated (ADR-0001) fires
	// only when a payout landed.
	outcome, payout, spilled := voyage.voyage_finish_ship_battle(&sim.battle)
	if payout > 0 {
		append(events, Event(Event_Ship_Updated{ship = sim.player}))
		append(events, Event(Event_Wreck_Looted{gross = payout, spilled = spilled}))
	}

	sim_advance_stage(sim, outcome, events)
	sim_walk_encounter(sim, events)
}
