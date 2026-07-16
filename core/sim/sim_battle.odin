package sim

import "../combat"
import "../voyage"
import "../ship"

// sim_process_battle_round takes Side.A's submitted command, pairs it with the
// scripted opponent's (ADR-0008), and resolves one round via core/combat. When the
// battle ends it asks voyage_finish_ship_battle what that means to the Fight stage
// and hands the outcome back to the walk.
sim_process_battle_round :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	assert(has_pending, "sim_process_battle_round called without a pending command")
	cmd, ok := pending.(Command_Battle_Choice)
	assert(ok, "sim_process_battle_round called without a pending Command_Battle_Choice")
	sim.pending_command = nil

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
		append(events, Event(Event_Battle_Menu{may_break_off = combat.combat_may_break_off(&sim.battle, .A)}))
		return
	}

	// Sinking is neither outcome (ADR-0014): permadeath ends the voyage (ADR-0006), so
	// the walk stops dead rather than completing the Fight — a [Fight, Reward] must not
	// pay out to a captain who went down with it. Ending the voyage is sim_tick's job on
	// the way out of this tick, deliberately not this proc's: the walk stopping and the
	// voyage ending are separate facts.
	//
	// Checked before voyage_finish_ship_battle so the payout runs only for a survivor:
	// a Destroyed ending reaching voyage_finish is then always the player's kill, never
	// a mutual kill or the player's own sinking.
	if !voyage.voyage_can_travel(&sim.player) {
		return
	}

	// Only a wreck pays: a sunk opponent's hold is stowed into the player's here.
	// Event_Ship_Updated (ADR-0001) is emitted only when a payout actually landed — a
	// fled opponent or a stalemate pays nothing.
	//
	// payout is the wreck's gross hold; the player keeps only what fits, the rest lost
	// above capacity. voyage_finish stows into battle.ships[.A], which aliases sim.player
	// (voyage_start_battle), so measuring cargo before and after yields the real gained
	// delta and spilled is the remainder — Event_Wreck_Looted carries both so an
	// overboard loss isn't dropped silently.
	cargo_before := ship.ship_cargo(sim.player)
	outcome, payout := voyage.voyage_finish_ship_battle(&sim.battle)
	if payout > 0 {
		spilled := payout - (ship.ship_cargo(sim.player) - cargo_before)
		append(events, Event(Event_Ship_Updated{ship = sim.player}))
		append(events, Event(Event_Wreck_Looted{gross = payout, spilled = spilled}))
	}

	sim_advance_stage(sim, outcome, events)
	sim_walk_encounter(sim, events)
}
