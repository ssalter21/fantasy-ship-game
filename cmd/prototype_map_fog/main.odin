package prototype_map_fog

// PROTOTYPE shell for issue #62 -- see graph.odin/variants.odin for the
// question this answers. Run with: odin run cmd/prototype_map_fog
//
// Left/Right arrows switch between three variants of "what does the player
// see" for the map's node-hiding mechanism. Press 1-4 to travel to a
// numbered reachable node and watch it resolve; R resets the walk; G rolls
// a new graph. Delete this whole directory (or fold the validated approach
// into cmd/game/view.odin) once #62 closes.

import "core:fmt"
import rl "vendor:raylib"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 700

variant_names := [3]string{"A -- Full graph, kind hidden", "B -- Fog by distance (horizon)", "C -- Zone progress + choice fan"}

Proto_State :: struct {
	g:          Graph,
	visited:    []bool,
	current_id: int,
	variant:    int,
	seed:       u64,
}

state_reset_walk :: proc(s: ^Proto_State) {
	delete(s.visited)
	s.visited = make([]bool, len(s.g.nodes))
	s.visited[s.g.start_id] = true
	s.current_id = s.g.start_id
}

state_regenerate :: proc(s: ^Proto_State, seed: u64) {
	graph_destroy(&s.g)
	s.seed = seed
	s.g = generate_graph(seed)
	state_reset_walk(s)
}

main :: proc() {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "PROTOTYPE issue #62 -- map fog-of-war")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	state := Proto_State{}
	state.g = generate_graph(1)
	defer graph_destroy(&state.g)
	state_reset_walk(&state)
	defer delete(state.visited)

	for !rl.WindowShouldClose() {
		if rl.IsKeyPressed(.RIGHT) {
			state.variant = (state.variant + 1) % 3
		}
		if rl.IsKeyPressed(.LEFT) {
			state.variant = (state.variant + 3 - 1) % 3
		}
		if rl.IsKeyPressed(.R) {
			state_reset_walk(&state)
		}
		if rl.IsKeyPressed(.G) {
			state_regenerate(&state, state.seed + 1)
		}

		reachable := reachable_next(state.g, state.current_id)

		for key, i in ([4]rl.KeyboardKey{.ONE, .TWO, .THREE, .FOUR}) {
			if rl.IsKeyPressed(key) && i < len(reachable) {
				state.current_id = reachable[i]
				state.visited[state.current_id] = true
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)

		rl.DrawText("PROTOTYPE issue #62 -- map hiding mechanism", 20, 16, 20, rl.DARKGRAY)
		rl.DrawText(fmt.ctprintf("seed %d", state.seed), WINDOW_WIDTH - 100, 16, 16, rl.GRAY)

		switch state.variant {
		case 0:
			draw_variant_a(state.g, state.visited, state.current_id, reachable[:])
		case 1:
			draw_variant_b(state.g, state.visited, state.current_id, reachable[:])
		case 2:
			draw_variant_c(state.g, state.visited, state.current_id, reachable[:])
		}

		draw_switcher_bar(state.variant)

		if len(reachable) == 0 {
			rl.DrawText("Run complete -- press R to walk again.", WINDOW_WIDTH / 2 - 140, WINDOW_HEIGHT - 90, 18, rl.MAROON)
		}

		rl.EndDrawing()
		delete(reachable)
	}
}

draw_switcher_bar :: proc(variant: int) {
	bar_w: i32 = 560
	bar_h: i32 = 40
	x: i32 = WINDOW_WIDTH / 2 - bar_w / 2
	y: i32 = WINDOW_HEIGHT - 40
	rl.DrawRectangle(x, y, bar_w, bar_h, rl.Fade(rl.BLACK, 0.85))
	rl.DrawText("<", x + 14, y + 10, 20, rl.RAYWHITE)
	rl.DrawText(">", x + bar_w - 24, y + 10, 20, rl.RAYWHITE)
	label := fmt.ctprintf("%s", variant_names[variant])
	rl.DrawText(label, x + 40, y + 10, 18, rl.RAYWHITE)
}
