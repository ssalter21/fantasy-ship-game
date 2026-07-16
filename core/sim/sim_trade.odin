package sim

import "../voyage"

// sim_process_trade_choice resolves the Trade stage under the cursor from a
// submitted Command_Trade_Choice.
//
// Accepting applies the swap (voyage_apply_trade), emits the updated ship, and
// completes the stage. Rejecting changes nothing, reports nothing, and halts the
// encounter — so a rejected [Trade, Reward] never pays out the Reward.
//
// Neither branch emits a Ghost_Snapshot or writes `resolved`: the node's ghost is
// captured once where its walk ends, and sim_walk_encounter is the sole writer of
// `resolved`.
sim_process_trade_choice :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	assert(has_pending, "sim_process_trade_choice called without a pending command")
	cmd, ok := pending.(Command_Trade_Choice)
	assert(ok, "sim_process_trade_choice called without a pending Command_Trade_Choice")
	sim.pending_command = nil

	if !cmd.accept {
		sim_advance_stage(sim, .Halted, events)
		sim_walk_encounter(sim, events)
		return
	}

	assert(
		voyage.voyage_trade_can_accept(&sim.player, sim.active_trade),
		"Command_Trade_Choice accepted a trade the ship cannot pay for",
	)
	voyage.voyage_apply_trade(&sim.player, sim.active_trade)
	append(events, Event(Event_Ship_Updated{ship = sim.player}))

	sim_advance_stage(sim, .Completed, events)
	sim_walk_encounter(sim, events)
}
