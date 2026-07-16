package main

import "core:fmt"
import "core:slice"
import combat "../../core/combat"
import voyage "../../core/voyage"
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
	defer delete(state.voyage_map.nodes) // UI-owned clone of the masked map (edges are borrowed)

	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}
	sink := sim.Event_Sink{data = &state, dispatch = dispatch}

	sim.run_session(&s, input, sink)
}

// Game_State is the shared context both the Input_Source and Event_Sink
// halves of the UI read/write (issue #24 — the same rawptr-sharing trick as
// cmd/headless's Headless_State, since Odin gives each callback only its own
// rawptr): dispatch records what the last event told us (current ship
// state, sighted opponent, items on offer, an open refit, map layout) and every
// blocking decision loop in menu.odin renders from this same state.
// get_captain_choice's awaiting parameter (issue #39) — not any field here
// — is what decides which decision menu to render.
Game_State :: struct {
	voyage_map:          voyage.Map,
	positions:        []rl.Vector2, // parallel to voyage_map.nodes; screen position
	visited:          []bool, // parallel to voyage_map.nodes; kept for rendering (revealing kinds, colouring nodes)
	travel_options:   []sim.Node_ID, // borrowed from the latest Event_Travel_Options; the Sim's legal moves for the decision path
	current_node_id:  sim.Node_ID,
	player:           ship.Ship,
	in_battle:        bool,
	sighted_opponent: Maybe(ship.Ship),
	may_break_off:        bool,
	// stage_options is the option list the current stage is presenting (issue #131),
	// copied from Event_Options_Presented; option_menu_loop renders each filled
	// position and offers a take-or-decline choice. One field, not the offer/shelf
	// pair it replaces: an Item Offer's items and a shop's shelf cards are one list,
	// differing only in whether an option carries a price. A nil position holds no
	// option (a shelf slot past the deck's tail, or a slot past a narrower stage's
	// count). Affordability is read live off the player's hold (ship.ship_cargo,
	// kept current by Event_Ship_Updated), so no separate cargo field is tracked here.
	stage_options:    [sim.STAGE_OPTION_MAX]Maybe(sim.Stage_Option),
	// stage_progress is where the current encounter's walk is — the last
	// Event_Stage_Entered, or nil between encounters (issue #139). It is the **only**
	// thing presentation knows about the cursor: the encounter's shape comes from the
	// node handed over on arrival, whose own cursor is a frozen copy, so the walk's
	// position has to be told rather than read. draw_encounter_strip renders it on every
	// screen an encounter can be on; a halt's beat reads it to name what was forfeited.
	stage_progress:   Maybe(sim.Event_Stage_Entered),
	// active_trade is the bargain the current Trade stage is offering (issue #136),
	// copied from Event_Trade_Presented; trade_menu_loop renders its two sides and
	// offers accept-or-reject. trade_can_accept is whether the ship can pay the
	// cost — taken from the same event rather than re-derived here, since it turns
	// on the ship's *effective* stats, which state.player's base fields don't give
	// (the Sim owns that rule, exactly as it owns option affordability).
	active_trade:     voyage.Stage_Trade,
	trade_can_accept: bool,
	// refit_incoming is the item an open Refit is placing (issue #96), tracked
	// from Event_Refit_Started and cleared once installed or the refit finishes,
	// so refit_menu_loop knows whether it is placing an item or just rearranging.
	refit_incoming:   Maybe(ship.Fitting),
	// refit_move_from is the slot a two-click Refit move has selected as its
	// source, or nil when no move is in progress (issue #96).
	refit_move_from:  Maybe(ship.Slot_Index),
	status:           voyage.Voyage_Status,
}

// get_captain_choice is the game Input_Source: it picks which blocking
// decision menu to render (ADR-0002 — each menu_loop runs its own nested
// render+poll loop and blocks until the player picks) based on awaiting,
// Sim's current Phase.
get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Game_State)data
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): return a placeholder instead
		// of entering a render loop that can never draw. This path only fires
		// when there's no window to drive a real gated session, so the specific
		// id isn't submitted to the Sim's travel gate.
		return sim.Command(sim.Command_Travel_To{node_id = 0})
	}

	switch awaiting {
	case .Awaiting_Option_Choice:
		return option_menu_loop(state)
	case .Awaiting_Trade_Choice:
		return trade_menu_loop(state)
	case .Awaiting_Battle_Command:
		return battle_menu_loop(state)
	case .Awaiting_Travel_Choice:
		return travel_menu_loop(state)
	case .Awaiting_Refit:
		return refit_menu_loop(state)
	case .Ended:
		panic("get_captain_choice called while the sim isn't awaiting a decision")
	}
	panic("unreachable")
}

// dispatch is the game Event_Sink: updates Game_State from every event and,
// for the events that warrant it (a sighted opponent, a battle round, an
// applied upgrade, the voyage ending), plays a blocking beat via play_beat/
// play_battle_event_beat before returning control to run_session.
dispatch :: proc(data: rawptr, event: sim.Event) {
	state := cast(^Game_State)data

	switch e in event {
	case sim.Event_Voyage_Started:
		// e.voyage_map is the Sim's masked public map (unvisited encounters' stages
		// hidden). Its nodes are cloned into UI-owned storage so arrivals can
		// reveal kinds into it (state.voyage_map.nodes[id] = revealed node); the
		// edges/adjacency are borrowed (they never change). Start (id 0) counts
		// as visited from the outset, matching the Sim's own visited set.
		state.voyage_map.nodes = slice.clone(e.voyage_map.nodes)
		state.voyage_map.edges = e.voyage_map.edges
		state.player = e.ship
		state.visited = make([]bool, len(e.voyage_map.nodes))
		state.visited[0] = true
		state.positions = compute_node_positions(e.voyage_map)

	case sim.Event_Travel_Options:
		// The Sim's legal moves for the upcoming travel decision (issue #83);
		// travel_menu_loop offers exactly these instead of re-deriving them.
		state.travel_options = e.options
		// Being asked where to sail *is* the signal that the walk is over — the Sim emits
		// this only from Awaiting_Travel_Choice, so it cannot land mid-encounter. So the
		// strip clears here rather than needing an end-of-walk event of its own (issue
		// #139).
		state.stage_progress = nil

	case sim.Event_Arrived_At_Node:
		state.current_node_id = e.node.id
		state.visited[e.node.id] = true
		state.voyage_map.nodes[e.node.id] = e.node // reveal this node's now-known kind

	case sim.Event_Ship_Battle_Sighted:
		state.in_battle = true
		state.sighted_opponent = e.opponent
		play_beat(state, fmt.tprintf("A ship approaches! (Hull %d)", e.opponent.hull))

	case sim.Event_Battle_Menu:
		state.may_break_off = e.may_break_off

	case sim.Event_Battle_Event:
		play_battle_event_beat(state, e.inner)

	case sim.Event_Ship_Updated:
		state.player = e.ship

	case sim.Event_Wreck_Looted:
		// A won Fight's payout has no screen of its own (unlike a Reward, which gets
		// play_stage_entry_beat), so it is said out loud here — the haul, and any of it
		// spilled overboard because the hold was full (issue #201, #196).
		play_beat(state, wreck_loot_beat_text(e.gross, e.spilled))

	case sim.Event_Stage_Entered:
		// The cursor moved: remember it so draw_encounter_strip can show the sequence and
		// where in it the captain is (issue #139).
		state.stage_progress = e
		play_stage_entry_beat(state, e)

	case sim.Event_Encounter_Halted:
		// A halt is the one outcome with nothing to show for itself, so it is said out
		// loud (issue #139) — see halt_beat_text.
		play_beat(state, halt_beat_text(state, e))

	case sim.Event_Options_Presented:
		// A stage that presents an option list was entered, or re-entered from a buy's
		// refit (issue #131): remember its list so option_menu_loop can render it
		// (refilled, after a buy). The cargo it renders comes from the player's hold
		// (ship.ship_cargo, kept current by Event_Ship_Updated).
		state.stage_options = e.options

	case sim.Event_Trade_Presented:
		// A Trade stage was entered (issue #136): remember the bargain and whether the
		// ship can pay for it, so trade_menu_loop can render both sides and grey out an
		// accept the ship can't afford.
		state.active_trade = e.trade
		state.trade_can_accept = e.can_accept

	case sim.Event_Purchase_Rejected:
		play_beat(state, fmt.tprintf("You can't afford %s.", e.option.fitting.name))

	case sim.Event_Refit_Started:
		// Opening a Refit (issue #96): remember the item being placed (nil for a
		// rearrange-only refit) and clear any half-built move, so refit_menu_loop
		// starts from a clean state.
		state.refit_incoming = e.incoming
		state.refit_move_from = nil

	case sim.Event_Fitting_Installed:
		// The incoming item just landed in a slot — it is no longer pending, so the
		// refit is now a rearrange until it finishes.
		state.refit_incoming = nil

	case sim.Event_Fitting_Moved, sim.Event_Fitting_Removed:
		// The ship panel re-renders from Event_Ship_Updated, so a move/remove needs
		// no extra UI state here; the change is visible on the next refit frame.

	case sim.Event_Refit_Rejected:
		play_beat(state, "That can't go there.")

	case sim.Event_Refit_Finished:
		state.refit_incoming = nil
		state.refit_move_from = nil

	case sim.Event_Encounter_Resolved:
		// No cleanup needed: the snapshot lives in the Sim's own run-scoped
		// arena and is reclaimed wholesale by sim_destroy (issue #52), and
		// the UI has no use for a ghost snapshot beyond this dispatch.

	case sim.Event_Voyage_Ended:
		state.status = e.status
		message := "Your ship has been lost."
		if e.status == .Won {
			message = "Victory! You reached Haven."
		}
		play_beat(state, message)
	}
}
