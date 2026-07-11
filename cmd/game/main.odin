package main

import "core:fmt"
import combat "../../core/combat"
import run "../../core/run"
import ship "../../core/ship"
import sim "../../core/sim"
import rl "vendor:raylib"

WINDOW_WIDTH :: 1024
WINDOW_HEIGHT :: 700

// VERSION is the build's git-SHA stamp, drawn in a window corner so playtest
// feedback can be tied to an exact commit (issue #44). `odin build cmd/game
// -define:GIT_SHA=abc1234` stamps abc1234; building without the define falls
// back to "dev".
VERSION :: #config(GIT_SHA, "dev")

main :: proc() {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Fantasy Ship Game")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	s := sim.sim_create(0)
	defer sim.sim_destroy(&s)

	state := Game_State{}
	defer delete(state.visited)
	defer delete(state.positions)

	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}
	sink := sim.Event_Sink{data = &state, dispatch = dispatch}

	sim.run_session(&s, input, sink)
}

// Game_State is the shared context both the Input_Source and Event_Sink
// halves of the UI read/write (issue #24 — the same rawptr-sharing trick as
// cmd/headless's Headless_State, since Odin gives each callback only its own
// rawptr): dispatch records what the last event told us (current ship
// state, sighted opponent, upgrade options on offer, map layout) and every
// blocking decision loop in menu.odin renders from this same state.
// get_captain_choice's awaiting parameter (issue #39) — not any field here
// — is what decides which decision menu to render.
Game_State :: struct {
	run_map:          run.Map,
	positions:        []rl.Vector2, // parallel to run_map.points; screen position
	visited:          []bool, // parallel to run_map.points
	current_point_id: int,
	player:           ship.Ship,
	in_battle:        bool,
	sighted_opponent: Maybe(ship.Ship),
	may_leave:        bool,
	upgrade_options:  [3]ship.Fitting,
	status:           run.Run_Status,
}

// get_captain_choice is the game Input_Source: it picks which blocking
// decision menu to render (ADR-0002 — each menu_loop runs its own nested
// render+poll loop and blocks until the player picks) based on awaiting,
// Sim's current Phase.
get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Game_State)data
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): return a harmless
		// default instead of entering a render loop that can never draw.
		return sim.Command(sim.Command_Travel_To{point_id = 0})
	}

	switch awaiting {
	case .Awaiting_Upgrade_Choice:
		return upgrade_menu_loop(state)
	case .Awaiting_Battle_Command:
		return battle_menu_loop(state)
	case .Awaiting_Travel_Choice:
		return travel_menu_loop(state)
	case .Ended:
		panic("get_captain_choice called while the sim isn't awaiting a decision")
	}
	panic("unreachable")
}

// dispatch is the game Event_Sink: updates Game_State from every event and,
// for the events that warrant it (a sighted opponent, a battle round, an
// applied upgrade, the run ending), plays a blocking beat via play_beat/
// play_battle_event_beat before returning control to run_session.
dispatch :: proc(data: rawptr, event: sim.Event) {
	state := cast(^Game_State)data

	switch e in event {
	case sim.Event_Run_Started:
		state.run_map = e.run_map
		state.player = e.ship
		state.visited = make([]bool, len(e.run_map.points))
		state.positions = compute_point_positions(e.run_map)

	case sim.Event_Arrived_At_Point:
		state.current_point_id = e.point.id
		state.visited[e.point.id] = true

	case sim.Event_Ship_Battle_Sighted:
		state.in_battle = true
		state.sighted_opponent = e.opponent
		play_beat(state, fmt.tprintf("A ship approaches! (HP %d)", e.opponent.hp))

	case sim.Event_Battle_Menu:
		state.may_leave = e.may_leave

	case sim.Event_Battle_Event:
		play_battle_event_beat(state, e.inner)

	case sim.Event_Ship_Updated:
		state.player = e.ship

	case sim.Event_Upgrade_Offer_Presented:
		state.upgrade_options = e.options

	case sim.Event_Upgrade_Applied:
		play_beat(state, fmt.tprintf("Installed %s!", e.fitting.name))

	case sim.Event_Encounter_Resolved:
		// snapshot needs no destroy call here (issue #52): it's valid for the
		// Sim's own lifetime, which outlives this dispatch, and the UI has no
		// use for a ghost snapshot beyond it anyway.

	case sim.Event_Run_Ended:
		state.status = e.status
		message := "Your ship has been lost."
		if e.status == .Won {
			message = "Victory! You reached the Goal."
		}
		play_beat(state, message)
	}
}
