package sim

import "../combat"
import "../run"
import "../ship"

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

	// combat_events is per-tick scratch (issue #53): context.temp_allocator, freed
	// by run_session via free_all(context.temp_allocator) once per driver
	// iteration. A round no longer allocates anything run-lifetime — jettison now
	// destroys the heaved cargo rather than recording it (ADR-0020, #159), so the
	// run-scoped arena block that used to wrap this call (issue #52) is gone.
	combat_events := make([dynamic]combat.Event, 0, 0, context.temp_allocator)
	combat.combat_resolve_round(&sim.battle, cmds, &combat_events)

	for e in combat_events {
		append(events, Event(Event_Battle_Event{inner = e}))
	}
	append(events, Event(Event_Ship_Updated{ship = sim.player}))

	if !sim.battle.ended {
		append(events, Event(Event_Battle_Menu{may_leave = combat.combat_may_leave(&sim.battle, .A)}))
		return
	}

	// Sinking is **neither** outcome (ADR-0014): the run is over by permadeath
	// (ADR-0006), so the walk stops dead rather than completing the Fight and applying
	// whatever came after it to a sunk ship — a [Fight, Reward] must not pay out to a
	// captain who went down with it. The node is never resolved, so it emits no
	// Ghost_Snapshot either (issue #162) — the one encounter in a run that leaves no
	// ghost, and Event_Run_Ended is what marks it. sim_tick's status check ends the run
	// on the way out of this tick, and it is deliberately not consulted here: the walk
	// stopping and the run ending are separate facts, and only one of them is this
	// proc's.
	//
	// Checked **before** run_finish_ship_battle so the wreck payout only ever runs for
	// a captain who survived: a Destroyed ending reaching run_finish is then always the
	// player's kill (#159), never a mutual kill or the player's own sinking.
	if !run.run_can_travel(&sim.player) {
		return
	}

	// Only a wreck pays (#159): a sunk opponent's hold is stowed into the player's
	// hold here. Event_Ship_Updated is how presentation learns the cargo moved
	// (ADR-0001), the same event a Reward payout owes — emitted only when a payout
	// actually landed, since a fled opponent or a stalemate pays nothing.
	//
	// `payout` is the wreck's *gross* hold; the player keeps only what fit, the rest
	// lost above capacity (#157) — the mainline case (#176/#196). We measure the spill
	// off the player's own cargo across the payout — run_finish stows into
	// battle.ships[.A], which aliases sim.player (run_start_battle) — so `gained` is the
	// real delta and `spilled` the remainder, and Event_Wreck_Looted carries both so
	// presentation can name the haul and any overboard loss rather than let it vanish
	// silently (issue #201).
	cargo_before := ship.ship_cargo(sim.player)
	outcome, payout := run.run_finish_ship_battle(&sim.battle)
	if payout > 0 {
		spilled := payout - (ship.ship_cargo(sim.player) - cargo_before)
		append(events, Event(Event_Ship_Updated{ship = sim.player}))
		append(events, Event(Event_Wreck_Looted{gross = payout, spilled = spilled}))
	}

	sim_advance_stage(sim, outcome, events)
	sim_walk_encounter(sim, events)
}
