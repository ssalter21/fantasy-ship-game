package main

import "core:fmt"
import "core:os"
import "core:strings"
import combat "../../core/combat"
import ship "../../core/ship"
import sim "../../core/sim"
import rl "vendor:raylib"

// Capture mode is the third Input_Source/Event_Sink pair (ADR-0002), beside the
// game's blocking menus and headless's instant scripts: it renders a real frame,
// screenshots it, and returns a *scripted* command so the session walks itself.
// That is the whole idea — no player, but a real window and the real render code.
//
// It lives in cmd/game rather than a cmd/capture of its own, and that is a finding
// rather than a preference: draw_scene, Game_State and dispatch are all `package
// main` here, and Odin rejects a second main package importing this one
// ("Duplicate declaration of 'package main'"). A sibling executable could only
// reuse the render code if it were first extracted into a library package.
// Capture renders, so ADR-0003's reason for splitting headless out (never link the
// renderer) does not argue for splitting capture out.

CAPTURE_DIR :: "docs/ui/shots"

// Capture_State drives the scripted walk and numbers the shots. The Game_State it
// wraps is handed to the *real* dispatch untouched, so capture sees exactly the
// screens the game draws rather than a second, drifting copy: the two halves take
// separate rawptrs, so capture's Input_Source and the game's Event_Sink can read
// different structs without either knowing about the other.
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
	capture_shot_build_surface(&state)

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
// the player would have been shown, screenshot it, then answer the decision from a
// script instead of from a click. Unlike the game's menu loops it blocks on
// nothing, and unlike headless's it draws — which is the whole point of the third
// implementation.
capture_get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Capture_State)data

	capture_shot(state, awaiting, capture_phase_slug(awaiting))
	return capture_scripted_command(state, awaiting)
}

// capture_shot renders one frame of the current decision screen and writes it out.
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

// capture_shot_build_surface photographs the Cutaway Build surface on the real starting
// ship (#302), the three states capture can reach without a mouse: at rest, with a granted
// item on the shelf, and mid-drag with the ghost over a legal berth. Like the Chart Table
// it needs no Sim — the surface reads only the ship — so it is shot standalone here rather
// than from the scripted walk, which never opens a Refit. The drag state is hard-coded, the
// same trick the run-game skill uses to photograph a hover capture otherwise can't see.
capture_shot_build_surface :: proc(state: ^Capture_State) {
	if !rl.IsWindowReady() {
		return
	}

	game := Game_State{player = ship.ship_starting_ship()}
	defer delete(game.player.layout)
	no_mouse := rl.Vector2{-1, -1}

	// At rest: the ship in refit, no granted item, no amber.
	draw_build_surface(&game, Build_Drag{}, nil, no_mouse)
	draw_build_surface(&game, Build_Drag{}, nil, no_mouse)
	capture_write(state, "build")

	// A granted Large item waiting on the shelf — the surface's one amber.
	granted, ok := ship.ship_item_by_name("Long Nines")
	if !ok {
		return
	}
	game.refit_incoming = granted.fitting
	draw_build_surface(&game, Build_Drag{}, nil, no_mouse)
	draw_build_surface(&game, Build_Drag{}, nil, no_mouse)
	capture_write(state, "build-shelf")

	// Mid-drag: the granted item lifted, its ghost over the empty Large forecastle, legal
	// berths lit and the rest dimmed. The forecastle is the fourth deck slot.
	rects, n := build_slot_rects(game.player.layout)
	drag := Build_Drag{active = true, from_slot = nil, fitting = granted.fitting}
	over := no_mouse
	if n > 3 {
		over = rl.Vector2{rects[3].x + rects[3].width / 2, rects[3].y + rects[3].height / 2}
	}
	draw_build_surface(&game, drag, nil, over)
	draw_build_surface(&game, drag, nil, over)
	capture_write(state, "build-placing")
}

// capture_write writes the presented frame to CAPTURE_DIR, numbered in walk order so a
// session reading the shots back can see the route.
//
// Callers draw their frame twice before calling: rl.TakeScreenshot reads back the
// framebuffer that EndDrawing just presented, so a single draw would screenshot
// whatever was on screen *before* this one. Drawing the same scene into both buffers
// makes the read-back land on this frame regardless of which buffer is read.
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

// capture_draw_screen draws the frame a player would be looking at for this decision.
// Only the option screen is split into a drawable proc so far (draw_option_screen);
// every other phase falls back to draw_scene, which renders the scene *without* that
// screen's chrome — its buttons are still welded inside its blocking menu loop. The
// gap is the finding, not an oversight: see issue #277.
capture_draw_screen :: proc(state: ^Capture_State, awaiting: sim.Phase, label: string) {
	#partial switch awaiting {
	case .Awaiting_Option_Choice:
		draw_option_screen(&state.game)
	case:
		draw_scene(&state.game, fmt.tprintf("[capture] %s", label), rl.Vector2{-1, -1})
	}
}

// capture_phase_slug names a decision screen for its filename. The Phase is the only
// thing distinguishing one screen from another here, which is itself a limit worth
// naming: capture can ask for "the trade screen", not for "the trade screen at the
// third Deep node".
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

// capture_scripted_command answers every decision without a player, mirroring
// cmd/headless's auto-player: sail forward, hold in a battle, decline every offer.
// It is a re-implementation rather than a reuse for the same reason capture lives
// here at all — cmd/headless is also `package main`, so its auto-player cannot be
// imported either.
capture_scripted_command :: proc(state: ^Capture_State, awaiting: sim.Phase) -> sim.Command {
	switch awaiting {
	case .Awaiting_Travel_Choice:
		return sim.Command(sim.Command_Travel_To{node_id = capture_next_node(state)})
	case .Awaiting_Battle_Command:
		return sim.Command(sim.Command_Battle_Choice{combat_command = combat.Command_Hold{}})
	case .Awaiting_Option_Choice:
		return sim.Command(sim.Command_Choose_Option{selection = nil})
	case .Awaiting_Trade_Choice:
		return sim.Command(sim.Command_Trade_Choice{accept = false})
	case .Awaiting_Refit:
		return sim.Command(sim.Command_Refit{command = sim.Refit_Finish{}})
	case .Ended:
		panic("capture_scripted_command called while the sim isn't awaiting a decision")
	}
	panic("unreachable")
}

// capture_next_node prefers a deeper-layer neighbour among the Sim's emitted travel
// options, so the scripted walk drives toward Haven instead of wandering.
capture_next_node :: proc(state: ^Capture_State) -> sim.Node_ID {
	options := state.game.travel_options
	assert(len(options) > 0, "capture reached a travel decision with no emitted options")

	nodes := state.game.voyage_map.nodes
	for dest in options {
		if nodes[dest].layer > nodes[state.game.current_node_id].layer {
			return dest
		}
	}
	return options[0]
}

// capture_requested reports whether the process was started as a capture run.
capture_requested :: proc() -> bool {
	for arg in os.args[1:] {
		if arg == "--capture" {
			return true
		}
	}
	return false
}
