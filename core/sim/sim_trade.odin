package sim

import "../run"

// sim_process_trade_choice applies a submitted Command_Trade_Choice (issue #136,
// ADR-0014), resolving the Trade the ship arrived at. Arriving already triggered
// the encounter (no decline), so making the choice — accept or reject — *is* the
// resolution: the node is marked resolved either way, so re-arriving after a
// retrace never re-offers the bargain.
//
// Accepting applies the swap permanently (run_apply_trade) and emits the
// resolved encounter's Ghost_Snapshot plus the updated ship. Rejecting changes
// nothing and emits neither: there is no post-trade ship to report and no
// resolution to snapshot, because nothing was traded.
//
// This replaces the arrival-time apply that used to sit inline in
// sim_process_travel. A Trade was the one encounter that mutated the ship without
// ever asking — "a single fixed trade-off rather than a choice among options", so
// it applied itself and returned straight to travel. Now it asks first, which is
// what makes accept/reject the stage's complete-or-halt outcome rather than a
// distinction with nothing behind it.
//
// **Complete-or-halt is not yet threaded through the cursor.** Accept means
// Completed and reject means Halted (ADR-0014), but the Sim still fires only a
// node's first stage — the generic stage walk is issue #131 — and every catalog
// recipe is one stage long, so both outcomes end the encounter here and the
// distinction is invisible. It starts mattering the moment a recipe puts a stage
// *after* a Trade: a rejected [Trade, Reward] must not pay out the Reward.
sim_process_trade_choice :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	assert(has_pending, "sim_process_trade_choice called without a pending command")
	cmd, ok := pending.(Command_Trade_Choice)
	assert(ok, "sim_process_trade_choice called without a pending Command_Trade_Choice")
	sim.pending_command = nil

	sim.resolved[sim.current] = true
	sim.phase = .Awaiting_Travel_Choice

	if !cmd.accept {
		return
	}

	assert(
		run.run_trade_can_accept(&sim.player, sim.active_trade),
		"Command_Trade_Choice accepted a trade the ship cannot pay for",
	)
	snap := run.run_apply_trade(&sim.player, sim.active_trade, sim.active_trade_site, sim.steps)
	sim_emit_encounter_resolved(sim, snap, events)
	append(events, Event(Event_Ship_Updated{ship = sim.player}))
}
