package sim

// sim_process_item_choice applies a submitted Command_Pick_Item (issue #96,
// ADR-0012), resolving the Item Offer the ship arrived at. Arriving already
// triggered the encounter (no decline), so making the choice — pick or skip —
// *is* the resolution: the node is marked resolved either way, so re-arriving
// after a retrace never re-offers it. A skip returns straight to a travel
// choice with no loadout change; a pick opens a Refit (sim_open_refit) staged
// with the chosen item, and the manual-loadout commands place or swap it. The
// old same-category auto-replace path (sim_process_upgrade_choice) is retired:
// resolution no longer touches the layout itself — the Refit owns every loadout
// change. Resolving here (not on the Refit's finish) keeps the Refit a pure,
// reusable sub-mode; the acquisition channel that opened it owns marking the
// encounter done.
sim_process_item_choice :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	assert(has_pending, "sim_process_item_choice called without a pending command")
	cmd, ok := pending.(Command_Pick_Item)
	assert(ok, "sim_process_item_choice called without a pending Command_Pick_Item")
	sim.pending_command = nil

	sim.resolved[sim.current] = true

	selection, picked := cmd.selection.?
	if !picked {
		sim.phase = .Awaiting_Travel_Choice
		return
	}

	assert(selection >= 0 && int(selection) < len(sim.item_offer_options), "Command_Pick_Item selection out of range")
	sim_open_refit(sim, sim.item_offer_options[selection], events)
}
