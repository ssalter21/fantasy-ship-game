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
	defer delete(state.run_map.points) // dispatch clones the map's points into UI-owned storage

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
upgrade_menu_loop_falls_back_to_option_zero_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{upgrade_options = [3]ship.Fitting{}}

	cmd := upgrade_menu_loop(&state)

	pick, ok := cmd.(sim.Command_Pick_Upgrade)
	testing.expect(t, ok)
	testing.expect_value(t, pick.option_index, 0)
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
