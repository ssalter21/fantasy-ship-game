package main

import "core:fmt"
import "core:strings"
import "core:testing"
import ship "../../core/ship"
import sim "../../core/sim"

// The Offer/Shop screen's drag mapping and its refit bridge, tested as pure functions the way
// build_drop_command is — no window, so `odin test` exercises the gesture's decisions without
// a render loop.

@(test)
offer_shop_kind_reads_the_stage_entered_event :: proc(t: ^testing.T) {
	state: Game_State

	// A costless Shop still presents as a Shop: the kind is the Event's, not a price scan.
	state.stage_progress = sim.Event_Stage_Entered{kind = .Shop, index = 0, count = 1}
	state.stage_options[0] = sim.Stage_Option{} // no cost
	testing.expect(t, offer_shop_kind(&state) == .Shop)

	// And an Offer never presents as one, whatever its options carry.
	state.stage_progress = sim.Event_Stage_Entered{kind = .Offer, index = 0, count = 1}
	state.stage_options[0] = sim.Stage_Option{cost = 3}
	testing.expect(t, offer_shop_kind(&state) == .Offer)
}

@(test)
offer_shop_drop_onto_a_same_size_berth_takes_that_option :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	// Slot 2 (gun deck) is a Large berth; a Large card dropped on it is a legal landing.
	drag := Shelf_Drag{active = true, option_index = sim.Option_Index(1), fitting = ship.Fitting{size = .Large}}
	cmd, ready, install := offer_shop_drop_command(&state, drag, ship.Slot_Index(2))

	testing.expect(t, ready)
	choice, ok := cmd.(sim.Command_Choose_Option)
	testing.expect(t, ok)
	selection, took := choice.selection.?
	testing.expect(t, took && selection == sim.Option_Index(1))
	slot, has := install.?
	testing.expect(t, has && slot == ship.Slot_Index(2))
}

@(test)
offer_shop_drop_onto_a_wrong_size_berth_takes_nothing :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	// Slot 5 (hold 2) is a Small berth; a Large card cannot land there, so nothing commits.
	drag := Shelf_Drag{active = true, option_index = sim.Option_Index(0), fitting = ship.Fitting{size = .Large}}
	_, ready, install := offer_shop_drop_command(&state, drag, ship.Slot_Index(5))

	testing.expect(t, !ready)
	_, has := install.?
	testing.expect(t, !has)
}

@(test)
offer_shop_drop_in_open_water_takes_nothing :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	drag := Shelf_Drag{active = true, option_index = sim.Option_Index(0), fitting = ship.Fitting{size = .Large}}
	_, ready, _ := offer_shop_drop_command(&state, drag, nil)

	testing.expect(t, !ready)
}

@(test)
offer_shop_cargo_preview_projects_the_post_buy_hold :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	cargo := ship.ship_cargo(state.player)
	capacity := ship.ship_cargo_capacity(state.player)
	text := offer_shop_cargo_preview_text(&state.player, 18)

	// The cargo term reads current -> post-buy against an unchanged capacity, so the cost of
	// a buy shows before it lands.
	projection := fmt.tprintf("Cargo %d/%d -> %d/%d", cargo, capacity, cargo - 18, capacity)
	testing.expect(t, strings.contains(text, projection))
}

@(test)
build_shelf_bridge_installs_then_finishes_a_shelf_drop :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	granted := ship.Fitting{name = "test cannon", size = .Large}
	state.refit_incoming = granted
	state.pending_shelf_install = ship.Slot_Index(3) // the Large forecastle's bare hold

	// While the item is in hand it lands in the remembered berth. The bridge re-reads
	// occupancy, so a berth carrying a backfilled hold takes a Replace, not an Install.
	cmd, bridging := build_shelf_bridge_command(&state)
	testing.expect(t, bridging)
	refit, ok := cmd.(sim.Command_Refit)
	testing.expect(t, ok)
	replace, is_replace := refit.command.(sim.Refit_Replace)
	testing.expect(t, is_replace && replace.slot == ship.Slot_Index(3))

	// Once the Sim reports it installed (refit_incoming cleared), the bridge finishes and
	// releases the berth.
	state.refit_incoming = nil
	cmd, bridging = build_shelf_bridge_command(&state)
	testing.expect(t, bridging)
	refit, ok = cmd.(sim.Command_Refit)
	testing.expect(t, ok)
	_, is_finish := refit.command.(sim.Refit_Finish)
	testing.expect(t, is_finish)
	_, still_pending := state.pending_shelf_install.?
	testing.expect(t, !still_pending)
}

@(test)
build_shelf_bridge_swaps_into_an_occupied_berth :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	// Slot 2 (gun deck) starts filled by the starting loadout; a Large grant dropped on it
	// swaps rather than installs.
	granted := ship.Fitting{name = "test cannon", size = .Large}
	state.refit_incoming = granted
	state.pending_shelf_install = ship.Slot_Index(2)

	cmd, bridging := build_shelf_bridge_command(&state)
	testing.expect(t, bridging)
	refit, ok := cmd.(sim.Command_Refit)
	testing.expect(t, ok)
	replace, is_replace := refit.command.(sim.Refit_Replace)
	testing.expect(t, is_replace && replace.slot == ship.Slot_Index(2))
}

@(test)
build_shelf_bridge_is_dormant_without_a_pending_drop :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	_, bridging := build_shelf_bridge_command(&state)
	testing.expect(t, !bridging) // a Home refit is driven by hand, not the bridge
}
