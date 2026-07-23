package presentation

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import cutaway "./cutaway"
import ship "../core/ship"
import sim "../core/sim"
import rl "vendor:raylib"

// Capture mode is the third Input_Source/Event_Sink pair (ADR-0002), beside the
// game's blocking menus and headless's instant scripts: it renders a real frame,
// screenshots it, and returns a *scripted* command so the session walks itself.
// That is the whole idea — no player, but a real window and the real render code.
//
// It lives beside the render code it photographs — draw_scene, Game_State and
// dispatch are package-private, so capture sees exactly the screens the game
// draws. Capture renders, so ADR-0003's reason for splitting headless out (never
// link the renderer) does not argue for a capture executable of its own.

@(private)
CAPTURE_DIR :: "docs/ui/shots"

// Capture_State drives the scripted walk and numbers the shots. The Game_State it
// wraps is handed to the *real* dispatch untouched, so capture sees exactly the
// screens the game draws rather than a second, drifting copy: the two halves take
// separate rawptrs, so capture's Input_Source and the game's Event_Sink can read
// different structs without either knowing about the other.
@(private)
Capture_State :: struct {
	game:  Game_State,
	shots: int,
}

// capture_main is the scripted session, entered from main when --capture is passed.
// It builds the same window and Sim the real game does; only the Input_Source
// differs.
capture_main :: proc() {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Fantasy Ship Game (capture)")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	ui_fonts_load()
	defer ui_fonts_unload()
	art_load()
	defer art_unload()

	if !os.exists(CAPTURE_DIR) {
		if err := os.make_directory(CAPTURE_DIR); err != nil {
			// Not fatal: raylib reports its own failure per shot, and a capture run that
			// writes nothing is still worth watching walk the route.
			fmt.eprintfln("capture: could not create %s (%v)", CAPTURE_DIR, err)
		}
	}

	state := Capture_State{}
	defer delete(state.game.visited)
	defer delete(state.game.positions)
	defer delete(state.game.voyage_map.nodes)

	capture_shot_chart_table(&state)
	capture_shot_home(&state)
	capture_shot_build_surface(&state)
	capture_shot_encounter_frame(&state)
	capture_shot_offer_shop(&state)
	capture_shot_fight(&state)

	s := sim.sim_create(VOYAGE_SEED)
	defer sim.sim_destroy(&s)

	// The two halves take separate rawptrs: the sink gets the plain Game_State the
	// real dispatch expects, the input gets the Capture_State that also holds the
	// shot counter.
	input := sim.Input_Source{data = &state, get_captain_choice = capture_get_captain_choice}
	sink := sim.Event_Sink{data = &state.game, dispatch = dispatch}

	sim.run_session(&s, input, sink)

	fmt.printfln("capture: wrote %d shot(s) to %s", state.shots, CAPTURE_DIR)
}

// capture_get_captain_choice is the capture Input_Source: draw the decision screen
// the player would have been shown, screenshot it, then answer the decision from
// the shared scripted player (sim.scripted_player_command) instead of from a click —
// fed the voyage state the real dispatch tracked into Game_State. Unlike the
// game's menu loops it blocks on nothing, and unlike headless's it draws — which
// is the whole point of the third Input_Source.
@(private)
capture_get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Capture_State)data

	capture_shot(state, awaiting, capture_phase_slug(awaiting))
	return sim.scripted_player_command(
		state.game.voyage_map,
		state.game.current_node_id,
		state.game.travel_options,
		awaiting,
	)
}

// capture_shot renders one frame of the current decision screen and writes it out.
@(private)
capture_shot :: proc(state: ^Capture_State, awaiting: sim.Phase, label: string) {
	if !rl.IsWindowReady() {
		return
	}

	capture_draw_screen(state, awaiting, label)
	capture_draw_screen(state, awaiting, label)
	capture_write(state, label)
}

// capture_shot_chart_table photographs the Chart Table at frame 0 — no voyage, no
// script, and none of the un-photographable beats a scripted walk pays for its screens.
// It is the one screen capture can shoot without a Sim at all, because #278 made the
// Chart Table stateless and made it precede any voyage.
@(private)
capture_shot_chart_table :: proc(state: ^Capture_State) {
	if !rl.IsWindowReady() {
		return
	}

	// -1: no button is hovered. Capture has no mouse, and the screen must photograph in
	// its resting state rather than in whatever state the pointer happens to leave it.
	draw_chart_table(-1)
	draw_chart_table(-1)
	capture_write(state, "chart-table")
}

// capture_shot_home photographs Home (#317) — the persistent between-encounters Build surface
// and the chart raised over it. Home reads the same map, positions and travel options a real
// voyage's first tick emits, so a throwaway Sim ticked once and dispatched into a fresh
// Game_State populates both states without a scripted walk — which has no mouse to raise the
// tab. The first tick emits only Event_Voyage_Started and Event_Travel_Options, neither of which
// plays a beat, so dispatching them here is safe.
@(private)
capture_shot_home :: proc(state: ^Capture_State) {
	if !rl.IsWindowReady() {
		return
	}

	s := sim.sim_create(VOYAGE_SEED)
	defer sim.sim_destroy(&s)

	game := Game_State{}
	defer delete(game.visited)
	defer delete(game.positions)
	defer delete(game.voyage_map.nodes)

	events: [dynamic]sim.Event
	defer delete(events)
	sim.sim_tick(&s, &events)
	for e in events {
		dispatch(&game, e)
	}

	// home_loop asserts the full-width chart page every frame; capture bypasses the loop,
	// so assert it here or the raised chart shoots at the voyage width the live game
	// never shows on this screen.
	map_width_set(&game, MAP_HOME_W)

	// At anchor: the ship in refit as the resting home, no granted item, no amber.
	draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0)
	draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0)
	capture_write(state, "home")

	// Mid-flip: the chart half-raised, sliding up over a partly-dimmed surface. draw_home
	// composes any elevation, so the click flip (#329) is photographable at rest — the split #277
	// asks for. This frame is only reachable through the fixed raise, never a poll.
	draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0.5)
	draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0.5)
	capture_write(state, "home-chart-rising")

	// The chart raised over the surface: the sailable overlay, the between-encounters travel view.
	draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 1)
	draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 1)
	capture_write(state, "home-chart")
}

// capture_room_centre is where a cursor has to be to point into a berth: the middle of that
// slot's projected opening. NO_MOUSE (over nothing) when the slot placed no room.
@(private)
capture_room_centre :: proc(
	rooms: [cutaway.MAX_SLOTS]cutaway.Room,
	n: int,
	slot: ship.Slot_Index,
) -> (
	rl.Vector2,
	bool,
) {
	room, placed := cutaway.galleon_room_for_slot(rooms, n, slot)
	if !placed {
		return NO_MOUSE, false
	}
	return cutaway.galleon_face_centre(cutaway.galleon_room_face(room, cutaway.galleon_view(WINDOW_WIDTH, WINDOW_HEIGHT))),
		true
}

// capture_shot_build_surface photographs the Cutaway Build surface on the real starting
// ship (#302), the states capture can reach without a mouse: at rest, hovering a berth, with a
// granted item on the shelf, mid-drag with the ghost over a legal berth, and the burn's two
// frames. Like the Chart Table it needs no Sim — the surface reads only the ship — so it is
// shot standalone here rather than from the scripted walk, which never opens a Refit. The
// cursor and drag states are hard-coded, the same trick the run-game skill uses to photograph
// what capture otherwise can't see.
@(private)
capture_shot_build_surface :: proc(state: ^Capture_State) {
	if !rl.IsWindowReady() {
		return
	}

	game := Game_State{player = ship.ship_starting_ship()}
	defer delete(game.player.layout)

	// At rest: the ship in refit, no granted item, no amber.
	draw_build_surface(&game, Build_Drag{}, nil, NO_MOUSE)
	draw_build_surface(&game, Build_Drag{}, nil, NO_MOUSE)
	capture_write(state, "build")

	// Hovering a berth: its opening lit, and its description card thrown clear of the hull on a
	// leader line. Capture has no mouse, so the cursor is placed on the sterncastle's opening —
	// the same point a real hover lands on, and the only way this state is photographable.
	rooms, n := cutaway.galleon_rooms(game.player.layout)
	if over, aimed := capture_room_centre(rooms, n, 0); aimed {
		draw_build_surface(&game, Build_Drag{}, nil, over)
		draw_build_surface(&game, Build_Drag{}, nil, over)
		capture_write(state, "build-hover")
	}

	// A granted Large item waiting on the shelf — the surface's one amber.
	granted, ok := ship.ship_item_by_name("Long Nines")
	if !ok {
		return
	}
	game.refit_incoming = granted.fitting
	draw_build_surface(&game, Build_Drag{}, nil, NO_MOUSE)
	draw_build_surface(&game, Build_Drag{}, nil, NO_MOUSE)
	capture_write(state, "build-shelf")

	// Mid-drag: the granted item lifted, its ghost over the empty Large forecastle, legal
	// berths lit and the rest dimmed. The forecastle is the fourth deck slot.
	drag := Build_Drag{active = true, from_slot = nil, fitting = granted.fitting}
	over, _ := capture_room_centre(rooms, n, 3)
	draw_build_surface(&game, drag, nil, over)
	draw_build_surface(&game, drag, nil, over)
	capture_write(state, "build-placing")

	// The out-of-combat burn (#401): a laden berth dragged onto the hold ledger, which arms
	// as the burn target, and the confirm the drop opens.
	game.refit_incoming = nil
	first_laden_slot :: proc(layout: []ship.Layout_Slot) -> Maybe(ship.Slot_Index) {
		for layout_slot, i in layout {
			if fitting, filled := layout_slot.fitting.?; filled && fitting.cargo_held > 0 {
				return ship.Slot_Index(i)
			}
		}
		return nil
	}
	laden_slot, any_laden := first_laden_slot(game.player.layout).?
	if !any_laden {
		return
	}
	laden, _ := game.player.layout[laden_slot].fitting.?
	burn_drag := Build_Drag{active = true, from_slot = laden_slot, fitting = laden}
	ledger := build_ledger_rect()
	on_ledger := rl.Vector2{ledger.x + ledger.width / 2, ledger.y + ledger.height / 2}
	draw_build_surface(&game, burn_drag, nil, on_ledger)
	draw_build_surface(&game, burn_drag, nil, on_ledger)
	capture_write(state, "build-burning")

	burn := Build_Confirm{slot = laden_slot, burn = true}
	draw_build_surface(&game, Build_Drag{}, burn, NO_MOUSE)
	draw_build_surface(&game, Build_Drag{}, burn, NO_MOUSE)
	capture_write(state, "build-burn-confirm")
}

// capture_shot_encounter_frame photographs the shared encounter frame (#304) — the constant
// furniture the per-stage builds fill in. Like the Chart Table and Build surface it reads
// only the ship, so it is shot standalone here rather than from the scripted walk (which
// declines every stage and lingers on none). Two shots: the bare frame on a representative
// stage — header naming it in its category colour, the top-right stat line, the view-only
// chart tab, the vignette — and the playback layer over it, the Reward beat that is only
// this overlay.
@(private)
capture_shot_encounter_frame :: proc(state: ^Capture_State) {
	if !rl.IsWindowReady() {
		return
	}

	game := Game_State{player = ship.ship_starting_ship()}
	defer delete(game.player.layout)

	draw_encounter_frame(&game, .Shop, "")
	draw_encounter_frame(&game, .Shop, "")
	capture_write(state, "encounter-frame")

	draw_encounter_frame(&game, .Reward, "Salvage! You haul aboard 4 cargo.")
	draw_encounter_frame(&game, .Reward, "Salvage! You haul aboard 4 cargo.")
	capture_write(state, "encounter-playback")
}

// capture_shot_offer_shop photographs the Shop stage (#312) — the two states the scripted
// walk can't reach: a Shop's priced shelf (the walk only meets free Offers, since a Shop
// lives at a Port), and a buy mid-drag with the cargo preview. Like the Build surface it
// reads only the ship plus a synthesized shelf, so it is shot standalone here rather than
// from the walk; the drag state is hard-coded, the same trick capture_shot_build_surface
// uses. Two shots: the shelf at rest — priced cards, one dearer than the hold can pay so its
// dimmed, undraggable read shows — and a buy in flight, the amber ghost over the empty Large
// forecastle with the stat line ghosting the post-buy cargo (`Cargo 80/90 → 62/90`).
@(private)
capture_shot_offer_shop :: proc(state: ^Capture_State) {
	if !rl.IsWindowReady() {
		return
	}

	game := Game_State{player = ship.ship_starting_ship()}
	defer delete(game.player.layout)
	// The screen reads its kind off the stage-entered Event (#430), so the synthesized
	// stop announces itself a Shop the way a real walk would.
	game.stage_progress = sim.Event_Stage_Entered{kind = .Shop, index = 0, count = 1}
	names := [?]string{"Long Nines", "Chain & Bar Shot", "Titan's Heart", "Outriggers"}
	costs := [?]int{18, 34, 120, 26} // the 120 sits above the starting hold, so it dims
	for name, i in names {
		if item, ok := ship.ship_item_by_name(name); ok {
			game.stage_options[i] = sim.Stage_Option{fitting = item.fitting, cost = costs[i]}
		}
	}

	draw_offer_shop(&game, Shelf_Drag{}, NO_MOUSE)
	draw_offer_shop(&game, Shelf_Drag{}, NO_MOUSE)
	capture_write(state, "shop")

	item, ok := ship.ship_item_by_name("Long Nines") // Large, so the empty Large forecastle lights
	if !ok {
		return
	}
	drag := Shelf_Drag{active = true, option_index = sim.Option_Index(0), fitting = item.fitting, cost = 18}
	rects, n := cutaway.cutaway_slot_rects(game.player.layout, offer_shop_ship_region())
	over := NO_MOUSE
	if n > 3 {
		over = rl.Vector2{rects[3].x + rects[3].width / 2, rects[3].y + rects[3].height / 2}
	}
	draw_offer_shop(&game, drag, over)
	draw_offer_shop(&game, drag, over)
	capture_write(state, "shop-buying")
}

// capture_shot_fight photographs the Fight stage (#315) — the facing cutaways the scripted
// walk can't linger on (it Holds every round and the battle blurs past in beats). Like the
// other stage shots it reads only two ships, so it is synthesized here: the starting ship as
// the player, a second one as a mid-fight opponent (Hull dropped, so a scouted, damaged foe
// reads) whose concealed holds render "???". Three shots: the fight at rest — both cutaways, the
// per-slot visibility badges, the round / stage readouts, the no-amber action row — the
// round-exchange beat, both damage numbers floating over their hulls under the shared scrim,
// and Jettison's target step.
@(private)
capture_shot_fight :: proc(state: ^Capture_State) {
	if !rl.IsWindowReady() {
		return
	}

	game := Game_State{player = ship.ship_starting_ship()}
	defer delete(game.player.layout)
	opponent := ship.ship_starting_ship()
	defer delete(opponent.layout)
	opponent.hull = 58 // a foe already worn down, so the opponent stat block reads a real fight

	game.sighted_opponent = opponent
	game.in_battle = true
	game.battle_round = 3 // "Round 4", escape still a couple of rounds off
	game.may_press = true // the fight's one Press still in hand, so the row shows it takeable
	game.stage_progress = sim.Event_Stage_Entered{kind = .Fight, index = 0, count = 2}
	draw_fight(&game, NO_MOUSE)
	draw_fight(&game, NO_MOUSE)
	capture_write(state, "fight")

	draw_fight_exchange(&game, 9, 14)
	draw_fight_exchange(&game, 9, 14)
	capture_write(state, "fight-exchange")

	// Jettison's target step: the same row, showing what the ship is carrying rather than the
	// captain's orders. Shot here because a player reaches it with a click and capture has no
	// mouse — without this the second step goes unphotographed.
	game.jettison_targeting = true
	draw_fight(&game, NO_MOUSE)
	draw_fight(&game, NO_MOUSE)
	capture_write(state, "fight-jettison")
}

// capture_write writes the presented frame to CAPTURE_DIR, numbered in walk order so a
// session reading the shots back can see the route.
//
// Callers draw their frame twice before calling: rl.TakeScreenshot reads back the
// framebuffer that EndDrawing just presented, so a single draw would screenshot
// whatever was on screen *before* this one. Drawing the same scene into both buffers
// makes the read-back land on this frame regardless of which buffer is read.
@(private)
capture_write :: proc(state: ^Capture_State, label: string) {
	// rl.TakeScreenshot runs the filename through GetFileName() and writes into the
	// process's working directory, so a path prefix here is silently dropped — the shot
	// always lands beside the exe's cwd. Each one is moved into CAPTURE_DIR immediately
	// rather than left to litter the repo root; capture does not get to choose where
	// raylib writes, only where the file ends up.
	name := fmt.tprintf("%02d-%s.png", state.shots, label)
	rl.TakeScreenshot(strings.clone_to_cstring(name, context.temp_allocator))

	dest := fmt.tprintf("%s/%s", CAPTURE_DIR, name)
	if err := os.rename(name, dest); err != nil {
		fmt.eprintfln("capture: could not move %s into %s (%v)", name, CAPTURE_DIR, err)
	}
	state.shots += 1
}

// capture_draw_screen draws the frame a player would be looking at for this decision. The
// travel screen (Home, #317), the option screen (Offer/Shop, #312), the Trade stage (#318) and
// the Fight (#315) are all fully drawable surfaces split from their loops, so the scripted walk
// photographs each as the player would see it — at rest, with no drag. Refit still falls back to
// draw_scene, which renders the scene *without* that screen's chrome — its controls are still
// welded inside its blocking menu loop. The remaining gap is the finding, not an oversight: see
// issue #277.
@(private)
capture_draw_screen :: proc(state: ^Capture_State, awaiting: sim.Phase, label: string) {
	#partial switch awaiting {
	case .Awaiting_Travel_Choice:
		// home_loop asserts the full-width chart page every frame; capture bypasses the
		// loop, so assert it here to shoot what the player would see.
		map_width_set(&state.game, MAP_HOME_W)
		draw_home(&state.game, Build_Drag{}, nil, NO_MOUSE, 0)
	case .Awaiting_Option_Choice:
		draw_offer_shop(&state.game, Shelf_Drag{}, NO_MOUSE)
	case .Awaiting_Trade_Choice:
		draw_trade(&state.game, NO_MOUSE)
	case .Awaiting_Battle_Command:
		draw_fight(&state.game, NO_MOUSE)
	case:
		draw_scene(&state.game, fmt.tprintf("[capture] %s", label), NO_MOUSE)
	}
}

// capture_phase_slug names a decision screen for its filename. The Phase is the only
// thing distinguishing one screen from another here, which is itself a limit worth
// naming: capture can ask for "the trade screen", not for "the trade screen at the
// third Deep node".
@(private)
capture_phase_slug :: proc(awaiting: sim.Phase) -> string {
	switch awaiting {
	case .Awaiting_Travel_Choice:
		return "travel"
	case .Awaiting_Battle_Command:
		return "battle"
	case .Awaiting_Option_Choice:
		return "options"
	case .Awaiting_Trade_Choice:
		return "trade"
	case .Awaiting_Refit:
		return "refit"
	case .Ended:
		return "ended"
	}
	return "unknown"
}

// capture_requested reports whether the process was started as a capture run.
capture_requested :: proc() -> bool {
	return slice.contains(os.args[1:], "--capture")
}
