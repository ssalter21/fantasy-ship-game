package main

import "core:fmt"
import "core:os"
import "core:slice"
import combat "../../core/combat"
import voyage "../../core/voyage"
import ship "../../core/ship"
import sim "../../core/sim"
import rl "vendor:raylib"

WINDOW_WIDTH :: 1024
WINDOW_HEIGHT :: 700

// VERSION is the build's git-SHA stamp, drawn in a window corner so playtest
// feedback can be tied to an exact commit. Set with `-define:GIT_SHA=…`.
VERSION :: #config(GIT_SHA, "dev")

// VOYAGE_SEED is what every voyage is dealt from. Fixed, so every launch deals the
// identical map; the outer loop makes that more visible (two voyages back-to-back,
// identical) without making it new. Choosing a seeding policy is ADR-0022's explicit
// non-decision — note that --capture and cmd/headless both depend on a fixed seed for
// their scripted walks.
VOYAGE_SEED :: 0

// window_quit_if_closed ends the process if the player has closed the window. Every
// blocking render loop calls it once per frame; it is the only thing that answers a
// close, and it is why no loop needs a close-fallback of its own (ADR-0023).
//
// It exits rather than reporting, because presentation has no way to end a voyage: the
// Command/Event boundary (ADR-0001) gives it five Commands and none of them stops a
// voyage, which ends only at Haven or a sinking. A loop that answered a close by
// returning a *legal move* would hand the Sim the next decision instead of winding
// down — travel's move sails to the next node, the Sim asks where to sail again, and
// the game spins there forever. Exiting is the only thing that actually stops.
//
// The IsWindowReady guard is load-bearing, not defensive: rl.WindowShouldClose() returns
// true when there is no window, so without it `odin test` would exit(0) mid-run and
// report success.
window_quit_if_closed :: proc() {
	if rl.IsWindowReady() && rl.WindowShouldClose() {
		os.exit(0)
	}
}

// main owns the loop above run_session: a session is N voyages through one window
// (ADR-0022). run_session stays the voyage's single driver loop, called once per
// voyage; the Chart Table sits above it, over no Sim at all.
main :: proc() {
	if capture_requested() {
		capture_main()
		return
	}

	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Fantasy Ship Game")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	ui_fonts_load()
	defer ui_fonts_unload()
	menu_art_load()
	defer menu_art_unload()
	parchment_art_load()
	defer parchment_art_unload()
	ship_art_load()
	defer ship_art_unload()

	for chart_table_loop() == .Begin {
		run_voyage()
	}
}

// run_voyage is one voyage, boot to ending: its own Sim, its own Game_State, one
// run_session. Both die with the proc, so the next voyage starts from nothing — which
// is safe precisely because #278 made the Chart Table stateless, so nothing is meant to
// survive a voyage. It is a proc rather than a loop body so these defers are per-voyage
// rather than per-process.
run_voyage :: proc() {
	s := sim.sim_create(VOYAGE_SEED)
	defer sim.sim_destroy(&s)

	state := Game_State{}
	defer delete(state.visited)
	defer delete(state.positions)
	defer delete(state.voyage_map.nodes) // UI-owned clone of the masked map (edges are borrowed)

	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}
	sink := sim.Event_Sink{data = &state, dispatch = dispatch}

	sim.run_session(&s, input, sink)
}

// Game_State is the shared context both the Input_Source and Event_Sink halves
// of the UI read/write — the same rawptr-sharing trick as cmd/headless's
// Headless_State, since Odin gives each callback only its own rawptr. dispatch
// records what the last event told us; every blocking decision loop in menu.odin
// renders from this same state. Which decision menu renders is decided by
// get_captain_choice's awaiting parameter, not by any field here.
Game_State :: struct {
	voyage_map:          voyage.Map,
	positions:        []rl.Vector2, // parallel to voyage_map.nodes; screen position of each
	visited:          []bool, // parallel to voyage_map.nodes; kept for rendering
	travel_options:   []sim.Node_ID, // borrowed from the latest Event_Travel_Options; the Sim's legal moves
	current_node_id:  sim.Node_ID,
	// sail_pending is the destination a click on the raised chart has chosen but not yet
	// committed: while it is set the ship is under way and home_loop is in its input-swallowed
	// sailing sub-state, holding Command_Travel_To back until the sprite lands. sail_progress is
	// that voyage's raw 0..1 tween. Both live here rather than in home_loop because the sail
	// spans frames while the chart overlay's own state re-tweens from zero each one.
	sail_pending:     Maybe(sim.Node_ID),
	sail_progress:    f32,
	// arrival_bloom is the landing the ship has just made and when, driving the sepia ink ripple
	// that blooms out of an arrival (spec §6). It lives beside the sail fields and for the same
	// reason — the bloom outlasts the frame that set it — and doubles as home_loop's record that
	// the sail under way has landed and is holding while its ink sets. Set on touchdown, cleared
	// when the next leg begins; the ripple itself expires on its own age, so a bloom still set
	// from a landing long past simply draws nothing.
	arrival_bloom:    Maybe(Ink_Bloom),
	player:           ship.Ship,
	in_battle:        bool,
	sighted_opponent: Maybe(ship.Ship),
	may_break_off:        bool,
	// battle_round is the combat.Battle's round counter, carried on Event_Battle_Menu:
	// the number of rounds already resolved, so the round about to be fought is
	// battle_round + 1. The Fight screen's rounds-left / escape-window readout (#315)
	// reads it — the UI can't recompute it, since a round that lands no damage emits no
	// combat event to count.
	battle_round:     int,
	// pending_exchange accumulates a single round's damage per side so the Fight can play
	// **one** beat for the whole exchange (#315): both hulls drain and both damage numbers
	// float together, one click to the next round (ADR-0006's simultaneous resolution),
	// rather than a beat per hit. Damage is drained from each struck hull as it lands (the
	// opponent's, which no Event_Ship_Updated carries, and the player's, kept in step with
	// the Sim's authoritative copy); the beat is flushed at the round boundary — the trailing
	// Event_Ship_Updated for a continuing round, or a Ship_Sunk / Battle_Ended that gets its
	// own beat after. exchange_active gates the flush so a round with no damage plays nothing.
	pending_exchange: [combat.Side]int,
	exchange_active:  bool,
	// stage_options is the option list the current stage is presenting, copied from
	// Event_Options_Presented; offer_shop_loop renders each filled position as a shelf
	// card to drag onto the ship. A nil position holds no option (a shelf slot past the
	// deck's tail, or a slot past a narrower stage's count). Affordability is read live
	// off the player's hold (ship.ship_cargo, kept current by Event_Ship_Updated), so no
	// separate cargo field is tracked here.
	stage_options:    [sim.STAGE_OPTION_MAX]Maybe(sim.Stage_Option),
	// stage_progress is where the current encounter's walk is — the last
	// Event_Stage_Entered, or nil between encounters. It is the **only** thing
	// presentation knows about the cursor: the encounter's shape comes from the node
	// handed over on arrival, whose own cursor is a frozen copy, so the walk's
	// position has to be told rather than read. draw_encounter_strip renders it;
	// a halt's beat reads it to name what was forfeited.
	stage_progress:   Maybe(sim.Event_Stage_Entered),
	// active_trade is the bargain the current Trade stage is offering, copied from
	// Event_Trade_Presented; trade_menu_loop renders its two cards and offers
	// accept-or-decline. trade_can_accept comes from the same event rather than being
	// re-derived here, since it turns on the ship's *effective* stats, which
	// state.player's base fields don't give (the Sim owns that rule). trade_cost_read /
	// trade_gain_read are the give and get cards' before→after readings, likewise off the
	// event so the view projects the swap without recomputing the ship (#318).
	active_trade:     voyage.Stage_Trade,
	trade_can_accept: bool,
	trade_cost_read:  voyage.Trade_Reading,
	trade_gain_read:  voyage.Trade_Reading,
	// refit_incoming is the item an open Refit is placing, tracked from
	// Event_Refit_Started and cleared once installed or the refit finishes, so the Build
	// surface knows whether there is a granted item on the shelf to place or the ship is
	// just being rearranged. The drag-in-progress itself is a build_surface_loop local, not
	// a Game_State field: a whole press-drag-release completes inside one loop call.
	refit_incoming:   Maybe(ship.Fitting),
	// pending_shelf_install is the berth an Offer/Shop shelf drag dropped on (#312): the
	// slot the shelf card landed in, set as the drop commits its Command_Choose_Option, so
	// the Refit that choice opens installs there and finishes on its own — the two sim
	// phases (choose, then refit) collapsed into one drag in presentation. build_surface_loop
	// reads and clears it; nil the rest of the time (a Home refit, or any other refit).
	pending_shelf_install: Maybe(ship.Slot_Index),
	status:           voyage.Voyage_Status,
}

// get_captain_choice is the game Input_Source: it picks which blocking decision
// menu to render, based on awaiting (the Sim's current Phase). Each menu_loop
// runs its own nested render+poll loop and blocks until the player picks (ADR-0002).
get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Game_State)data
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): return a placeholder instead of
		// entering a render loop that can never draw. Never fires in a real gated
		// session, so the specific id doesn't matter.
		return sim.Command(sim.Command_Travel_To{node_id = 0})
	}

	switch awaiting {
	case .Awaiting_Option_Choice:
		return offer_shop_loop(state)
	case .Awaiting_Trade_Choice:
		return trade_menu_loop(state)
	case .Awaiting_Battle_Command:
		return battle_menu_loop(state)
	case .Awaiting_Travel_Choice:
		return home_loop(state)
	case .Awaiting_Refit:
		return build_surface_loop(state)
	case .Ended:
		panic("get_captain_choice called while the sim isn't awaiting a decision")
	}
	panic("unreachable")
}

// dispatch is the game Event_Sink: updates Game_State from every event and, for
// the events that warrant it, plays a blocking beat via play_beat (or, for a combat
// round, dispatch_battle_event's per-round-exchange batching) before returning control
// to run_session.
dispatch :: proc(data: rawptr, event: sim.Event) {
	state := cast(^Game_State)data

	switch e in event {
	case sim.Event_Voyage_Started:
		// e.voyage_map is the Sim's masked public map (unvisited stages hidden). Its
		// nodes are cloned into UI-owned storage so arrivals can reveal kinds into it;
		// the edges/adjacency are borrowed (they never change). Start (id 0) counts as
		// visited from the outset, matching the Sim's own visited set.
		state.voyage_map.nodes = slice.clone(e.voyage_map.nodes)
		state.voyage_map.edges = e.voyage_map.edges
		state.player = e.ship
		state.visited = make([]bool, len(e.voyage_map.nodes))
		state.visited[0] = true
		state.positions = compute_node_positions(e.voyage_map)

	case sim.Event_Travel_Options:
		// The Sim's legal moves for the upcoming travel decision; home_loop's raised
		// chart offers exactly these instead of re-deriving them.
		state.travel_options = e.options
		// Being asked where to sail *is* the signal that the walk is over (the Sim emits
		// this only from Awaiting_Travel_Choice), so the strip clears here rather than
		// needing an end-of-walk event of its own.
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
		state.battle_round = e.round

	case sim.Event_Battle_Event:
		dispatch_battle_event(state, e.inner)

	case sim.Event_Ship_Updated:
		state.player = e.ship
		// The trailing Ship_Updated of a combat round is the round boundary for a
		// continuing round (nothing sank, so no Ship_Sunk/Battle_Ended closes it): flush
		// the exchange beat now the player's authoritative hull has landed. A no-op
		// outside a battle, or once a terminal beat has already flushed the round.
		if state.in_battle {
			fight_flush_exchange(state)
		}

	case sim.Event_Wreck_Looted:
		// A won Fight's payout has no screen of its own (unlike a Reward, which gets
		// play_stage_entry_beat), so it is said out loud here — the haul, and any of it
		// spilled overboard because the hold was full.
		play_beat(state, wreck_loot_beat_text(e.gross, e.spilled))

	case sim.Event_Stage_Entered:
		// The cursor moved: remember it so draw_encounter_strip can show the sequence
		// and where in it the captain is.
		state.stage_progress = e
		play_stage_entry_beat(state, e)

	case sim.Event_Encounter_Halted:
		// A halt is the one outcome with nothing to show for itself, so it is said out
		// loud — see halt_beat_text.
		play_beat(state, halt_beat_text(state, e))

	case sim.Event_Options_Presented:
		// A stage presenting an option list was entered, or re-entered from a buy's
		// refit: remember its list so offer_shop_loop can render its shelf (refilled
		// after a buy).
		state.stage_options = e.options

	case sim.Event_Trade_Presented:
		// A Trade stage was entered: remember the bargain, whether the ship can pay for
		// it, and the two cards' before→after readings, so trade_menu_loop can render
		// both projections and dim an unaffordable Accept.
		state.active_trade = e.trade
		state.trade_can_accept = e.can_accept
		state.trade_cost_read = e.cost_read
		state.trade_gain_read = e.gain_read

	case sim.Event_Purchase_Rejected:
		play_beat(state, fmt.tprintf("You can't afford %s.", e.option.fitting.name))

	case sim.Event_Refit_Started:
		// Opening a Refit: remember the item being placed (nil for a rearrange-only
		// refit), so the Build surface shows a granted item on the shelf.
		state.refit_incoming = e.incoming

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

	case sim.Event_Encounter_Resolved:
		// No cleanup needed: the snapshot lives in the Sim's own run-scoped arena and is
		// reclaimed wholesale by sim_destroy, and the UI has no use for a ghost snapshot
		// beyond this dispatch.

	case sim.Event_Voyage_Ended:
		state.status = e.status
		message := "Your ship has been lost."
		if e.status == .Won {
			message = "Victory! You reached Haven."
		}
		play_beat(state, message)
	}
}
