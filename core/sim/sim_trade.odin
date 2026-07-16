package sim

import "../run"

// sim_process_trade_choice applies a submitted Command_Trade_Choice (issue #136,
// ADR-0014), resolving the Trade stage under the cursor.
//
// Accepting applies the swap permanently (voyage_apply_trade), emits the updated
// ship, and **completes** the stage. Rejecting changes nothing and so reports
// nothing — there is no post-trade ship to report, because nothing was traded —
// and **halts** the encounter.
//
// Neither emits a Ghost_Snapshot: the node's ghost is captured once, where its walk
// ends (issue #162), so an accepted Trade mid-recipe no longer emits one of its own
// and a rejected one is snapshotted all the same — the halt lands in that same
// branch, and a captain who walked away from a bargain is still a ship.
//
// That outcome pair is now threaded through the cursor rather than described and
// dropped. #136 could only say what accept and reject meant: it predated the generic
// walk (issue #131), so it marked the node resolved itself and every catalog recipe
// was one stage long, which made the distinction invisible. It is visible now — a
// rejected [Trade, Reward] halts and never pays out the Reward, with no authored gate
// saying so — and neither outcome touches `resolved` here, because sim_walk_encounter
// is the only writer of it.
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
		run.voyage_trade_can_accept(&sim.player, sim.active_trade),
		"Command_Trade_Choice accepted a trade the ship cannot pay for",
	)
	run.voyage_apply_trade(&sim.player, sim.active_trade)
	append(events, Event(Event_Ship_Updated{ship = sim.player}))

	sim_advance_stage(sim, .Completed, events)
	sim_walk_encounter(sim, events)
}
