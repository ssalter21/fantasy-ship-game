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
	cmd := get_captain_choice(&state)

	_, ok := cmd.(sim.Command_Travel_To)
	testing.expect(t, ok)
}

@(test)
dispatch_does_not_crash_on_any_event_variant_without_a_live_window :: proc(t: ^testing.T) {
	run_map := run.run_map_create()
	defer run.run_map_destroy(&run_map)

	state := Game_State{}
	defer delete(state.visited)
	defer delete(state.positions)

	dispatch(&state, sim.Event(sim.Event_Run_Started{run_map = run_map, ship = state.player}))
	dispatch(&state, sim.Event(sim.Event_Arrived_At_Point{point = run_map.points[0]}))
	dispatch(&state, sim.Event(sim.Event_Ship_Battle_Sighted{opponent = state.player}))
	dispatch(&state, sim.Event(sim.Event_Battle_Menu{may_leave = true}))
	dispatch(&state, sim.Event(sim.Event_Battle_Event{inner = combat.Event(combat.Event_Battle_Ended{reason = .Destroyed})}))
	dispatch(&state, sim.Event(sim.Event_Ship_Updated{ship = state.player}))
	dispatch(&state, sim.Event(sim.Event_Upgrade_Offer_Presented{}))
	dispatch(&state, sim.Event(sim.Event_Upgrade_Applied{}))
	dispatch(&state, sim.Event(sim.Event_Run_Ended{status = .Won}))
}

@(test)
dispatch_frees_the_encounter_resolved_snapshots_owned_layout :: proc(t: ^testing.T) {
	state := Game_State{}
	defer delete(state.visited)
	defer delete(state.positions)

	dispatch(&state, sim.Event(sim.Event_Encounter_Resolved{snapshot = run.Ghost_Snapshot{}}))
}

@(test)
battle_menu_loop_falls_back_to_hold_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}

	cmd := battle_menu_loop(&state)

	action, ok := cmd.(sim.Command_Battle_Action)
	testing.expect(t, ok)
	_, is_hold := action.action.(combat.Command_Hold)
	testing.expect(t, is_hold)
}

@(test)
upgrade_menu_loop_falls_back_to_option_zero_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{upgrade_options = [3]ship.Fitting{}}

	cmd := upgrade_menu_loop(&state)

	pick, ok := cmd.(sim.Command_Pick_Upgrade)
	testing.expect(t, ok)
	testing.expect_value(t, pick.option_index, 0)
}
