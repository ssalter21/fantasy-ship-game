package main

import sim "../../core/sim"
import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(800, 450, "Fantasy Ship Game")
	defer rl.CloseWindow()

	s := sim.sim_create(0)
	input := sim.Input_Source{data = nil, get_captain_choice = rendered_captain_choice}
	sink := sim.Event_Sink{data = nil, dispatch = rendered_dispatch}
	sim.run_session(&s, input, sink)
}

// rendered_captain_choice is the game Input_Source: it draws a placeholder
// frame before returning a fixed choice, so run_session (the outermost
// driver loop per ADR-0002) ends up wrapping rendering rather than
// preceding it. A raylib-backed decision menu that blocks across many
// frames replaces the frame body once UI decision rendering lands.
rendered_captain_choice :: proc(data: rawptr) -> sim.Command {
	draw_placeholder_frame()
	return sim.Command(sim.Command_Submit_Captain_Choice{choice = 0})
}

// rendered_dispatch is the game Event_Sink: it draws a placeholder frame per
// event. Animated event playback replaces the frame body once UI playback
// lands.
rendered_dispatch :: proc(data: rawptr, event: sim.Event) {
	draw_placeholder_frame()
}

// draw_placeholder_frame is the render-loop body rendered_captain_choice and
// rendered_dispatch nest (ADR-0002): draw one static frame. A no-op outside
// a live window (e.g. under `odin test`), since raylib's draw calls require
// InitWindow to have run first.
draw_placeholder_frame :: proc() {
	if !rl.IsWindowReady() {
		return
	}

	rl.BeginDrawing()
	rl.ClearBackground(rl.RAYWHITE)
	rl.DrawText("Fantasy Ship Game", 190, 200, 20, rl.DARKGRAY)
	rl.EndDrawing()
}
