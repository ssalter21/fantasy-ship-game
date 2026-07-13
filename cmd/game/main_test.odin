package main

import "core:testing"
import combat "../../core/combat"
import run "../../core/run"
import ship "../../core/ship"
import sim "../../core/sim"

// These smoke tests call the Input_Source/Event_Sink procs directly rather
// than through a live window: rl.IsWindowReady() is false under `odin
// test`, so every blocking menu_loop/play_beat call returns its harmless
// default immediately instead of entering a render loop (see
// get_captain_choice's and play_beat's IsWindowReady guards).

@(test)
get_captain_choice_returns_a_default_travel_choice_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}
	cmd := get_captain_choice(&state, .Awaiting_Travel_Choice)

	_, ok := cmd.(sim.Command_Travel_To)
	testing.expect(t, ok)
}

@(test)
dispatch_does_not_crash_on_any_event_variant_without_a_live_window :: proc(t: ^testing.T) {
	run_map := run.run_map_create(0)
	defer run.run_map_destroy(&run_map)

	state := Game_State{}
	defer delete(state.visited)
	defer delete(state.positions)
	defer delete(state.run_map.nodes) // dispatch clones the map's nodes into UI-owned storage

	dispatch(&state, sim.Event(sim.Event_Run_Started{run_map = run_map, ship = state.player}))
	dispatch(&state, sim.Event(sim.Event_Travel_Options{options = []sim.Node_ID{1, 2}}))
	dispatch(&state, sim.Event(sim.Event_Arrived_At_Node{node = run_map.nodes[0]}))
	dispatch(&state, sim.Event(sim.Event_Ship_Battle_Sighted{opponent = state.player}))
	dispatch(&state, sim.Event(sim.Event_Battle_Menu{may_leave = true}))
	dispatch(&state, sim.Event(sim.Event_Battle_Event{inner = combat.Event(combat.Event_Battle_Ended{reason = .Destroyed})}))
	dispatch(&state, sim.Event(sim.Event_Ship_Updated{ship = state.player}))
	dispatch(&state, sim.Event(sim.Event_Item_Offer_Presented{}))
	dispatch(&state, sim.Event(sim.Event_Refit_Started{incoming = ship.ship_fitting_gun_deck()}))
	dispatch(&state, sim.Event(sim.Event_Fitting_Installed{slot = 0, fitting = ship.ship_fitting_gun_deck()}))
	dispatch(&state, sim.Event(sim.Event_Refit_Finished{}))
	dispatch(&state, sim.Event(sim.Event_Run_Ended{status = .Won}))
}

@(test)
dispatch_does_not_crash_on_an_encounter_resolved_event_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}
	defer delete(state.visited)
	defer delete(state.positions)

	// The snapshot's layout is arena-owned by the Sim (issue #52) — dispatch
	// takes no ownership of it, so this just confirms handling the variant
	// doesn't crash.
	dispatch(&state, sim.Event(sim.Event_Encounter_Resolved{snapshot = run.Ghost_Snapshot{}}))
}

@(test)
battle_menu_loop_falls_back_to_hold_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}

	cmd := battle_menu_loop(&state)

	choice, ok := cmd.(sim.Command_Battle_Choice)
	testing.expect(t, ok)
	_, is_hold := choice.combat_command.(combat.Command_Hold)
	testing.expect(t, is_hold)
}

@(test)
item_offer_menu_loop_falls_back_to_skip_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}

	cmd := item_offer_menu_loop(&state)

	pick, ok := cmd.(sim.Command_Pick_Item)
	testing.expect(t, ok)
	_, has_selection := pick.selection.?
	testing.expect(t, !has_selection) // nil selection == skip
}

@(test)
refit_menu_loop_falls_back_to_finish_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}

	cmd := refit_menu_loop(&state)

	refit, ok := cmd.(sim.Command_Refit)
	testing.expect(t, ok)
	_, is_finish := refit.command.(sim.Refit_Finish)
	testing.expect(t, is_finish)
}

@(test)
refit_click_maps_clicks_to_loadout_operations :: proc(t: ^testing.T) {
	// The place/swap/move/finish interaction is pure state logic, testable
	// without a live window (issue #96).
	s := ship.ship_starting_ship()
	defer delete(s.layout)
	state := Game_State{player = s}
	finish := len(s.layout)
	// Starting slots: 0 top deck (M) Captain's Quarters, 2 gun deck (L) Gun Deck,
	// 4 hold 1 (M) Cargo. Place a Medium item so the swap/move slots line up.

	// Finish box commits a Refit_Finish.
	cmd, ready := refit_click(&state, finish, finish)
	testing.expect(t, ready)
	refit, _ := cmd.(sim.Command_Refit)
	_, is_finish := refit.command.(sim.Refit_Finish)
	testing.expect(t, is_finish)

	// Placing a Medium item: clicking any filled slot emits Refit_Replace and lets
	// the Sim decide the fit — the menu no longer predicts the size match (issue
	// #111). Slot 0 holds Captain's Quarters (Medium).
	state.refit_incoming = ship.ship_fitting_top_crew() // Medium
	cmd, ready = refit_click(&state, 0, finish)
	testing.expect(t, ready)
	refit, _ = cmd.(sim.Command_Refit)
	replace, is_replace := refit.command.(sim.Refit_Replace)
	testing.expect(t, is_replace)
	testing.expect_value(t, replace.slot, ship.Slot_Index(0))

	// A filled slot of a different size (2 is a Large Gun Deck) is no longer
	// ignored: the menu emits the same Refit_Replace and the Sim rejects the size
	// mismatch (Event_Refit_Rejected), rather than the menu re-checking the rule.
	cmd, ready = refit_click(&state, 2, finish)
	testing.expect(t, ready)
	refit, _ = cmd.(sim.Command_Refit)
	replace, is_replace = refit.command.(sim.Refit_Replace)
	testing.expect(t, is_replace)
	testing.expect_value(t, replace.slot, ship.Slot_Index(2))

	// An empty same-size slot installs the pending item.
	state.player.layout[4].fitting = nil // hold 1, Medium
	cmd, ready = refit_click(&state, 4, finish)
	testing.expect(t, ready)
	refit, _ = cmd.(sim.Command_Refit)
	install, is_install := refit.command.(sim.Refit_Install)
	testing.expect(t, is_install)
	testing.expect_value(t, install.slot, ship.Slot_Index(4))

	// Rearranging (no pending item): select a filled source, then move it to the
	// empty slot 4.
	state.refit_incoming = nil
	state.refit_move_from = nil
	_, ready = refit_click(&state, 0, finish)
	testing.expect(t, !ready) // selecting, not committing
	from, selecting := state.refit_move_from.?
	testing.expect(t, selecting)
	testing.expect_value(t, from, ship.Slot_Index(0))
	cmd, ready = refit_click(&state, 4, finish)
	testing.expect(t, ready)
	refit, _ = cmd.(sim.Command_Refit)
	move, is_move := refit.command.(sim.Refit_Move)
	testing.expect(t, is_move)
	testing.expect_value(t, move.from, ship.Slot_Index(0))
	testing.expect_value(t, move.to, ship.Slot_Index(4))
	_, still_selecting := state.refit_move_from.?
	testing.expect(t, !still_selecting) // move committed, selection cleared

	// Clicking the selected source again cancels the move.
	_, _ = refit_click(&state, 0, finish)
	_, ready = refit_click(&state, 0, finish)
	testing.expect(t, !ready)
	_, still_selecting = state.refit_move_from.?
	testing.expect(t, !still_selecting)
}

@(test)
fitting_effect_intent_describes_each_effect_kind :: proc(t: ^testing.T) {
	flat := ship.Fitting{category = .Offensive, active = ship.Effect{magnitude = 5}}
	testing.expect_value(t, fitting_effect_intent(flat), "+5 Offense")

	dur := ship.Fitting{category = .Defensive, passive = ship.Effect{kind = .Modify_Durability, magnitude = 2}}
	testing.expect_value(t, fitting_effect_intent(dur), "+2 Durability")

	synergy := ship.Fitting{category = .Buff, active = ship.Effect{magnitude = 2, synergy = ship.Selector(ship.Tag.Weapon)}}
	testing.expect_value(t, fitting_effect_intent(synergy), "+2 Buff per Weapon")

	conditional := ship.Fitting{category = .Offensive, active = ship.Effect{magnitude = 8, conditional = ship.Condition_HP_Below{percent = 50}}}
	testing.expect_value(t, fitting_effect_intent(conditional), "+8 Offense below 50% HP")

	cargo := ship.ship_fitting_cargo("Cargo", .Small)
	testing.expect_value(t, fitting_effect_intent(cargo), "no effect")
}

@(test)
fitting_tags_label_lists_every_family :: proc(t: ^testing.T) {
	multi := ship.Fitting{tags = {.Crew, .Weapon}}
	testing.expect_value(t, fitting_tags_label(multi.tags), "Crew, Weapon")

	none := ship.Fitting{}
	testing.expect_value(t, fitting_tags_label(none.tags), "—")
}

@(test)
version_defaults_to_dev_without_the_git_sha_define :: proc(t: ^testing.T) {
	// Built under `odin test` (no -define:GIT_SHA), the compile-time stamp
	// falls back to its #config default. A build passing -define:GIT_SHA=...
	// overrides this; issue #44.
	testing.expect_value(t, VERSION, "dev")
}

@(test)
draw_version_stamp_does_not_crash_without_a_live_window :: proc(t: ^testing.T) {
	// Respects the same IsWindowReady() guard as the rest of the render
	// layer (ADR-0003): a no-op under `odin test` rather than a raylib call
	// with no live window.
	draw_version_stamp()
}
