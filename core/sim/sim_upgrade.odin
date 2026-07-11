package sim

import "../ship"

// sim_process_upgrade_choice applies a submitted Command_Pick_Upgrade
// (issue #24): replaces the current fitting of the picked option's own
// Category with the offered upgraded fitting, then returns Sim to awaiting
// a travel choice.
sim_process_upgrade_choice :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	assert(has_pending, "sim_process_upgrade_choice called without a pending command")
	cmd, ok := pending.(Command_Pick_Upgrade)
	assert(ok, "sim_process_upgrade_choice called without a pending Command_Pick_Upgrade")
	sim.pending_command = nil
	assert(cmd.option_index >= 0 && cmd.option_index < len(sim.upgrade_options), "Command_Pick_Upgrade option_index out of range")

	fitting := sim.upgrade_options[cmd.option_index]

	slot := ship.ship_slot_by_category(&sim.player, fitting.category)
	assert(slot != nil, "no slot found holding the picked upgrade's base category")
	replaced := ship.ship_replace_fitting(slot, fitting)
	assert(replaced, "upgrade fitting failed to replace the slot's existing fitting")

	append(events, Event(Event_Upgrade_Applied{fitting = fitting}))
	append(events, Event(Event_Ship_Updated{ship = sim.player}))

	sim.resolved[sim.current] = true
	sim.phase = .Awaiting_Travel_Choice
}
