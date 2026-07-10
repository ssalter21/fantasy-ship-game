package main

import sim "../../core/sim"
import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(800, 450, "Fantasy Ship Game")
	defer rl.CloseWindow()

	s := sim.sim_create(0)
	input := sim.Input_Source{data = nil, get_captain_choice = stub_captain_choice}
	sink := sim.Event_Sink{data = nil, dispatch = stub_dispatch}
	sim.run_session(&s, input, sink)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)
		rl.DrawText("Fantasy Ship Game", 190, 200, 20, rl.DARKGRAY)
		rl.EndDrawing()
	}
}

// stub_captain_choice is a placeholder Input_Source: it returns a fixed
// choice without blocking. A raylib-backed decision menu replaces this once
// UI decision rendering lands.
stub_captain_choice :: proc(data: rawptr) -> sim.Command {
	return sim.Command(sim.Command_Submit_Captain_Choice{choice = 0})
}

// stub_dispatch is a placeholder Event_Sink: it does nothing. Animated event
// playback replaces this once UI playback lands.
stub_dispatch :: proc(data: rawptr, event: sim.Event) {
}
