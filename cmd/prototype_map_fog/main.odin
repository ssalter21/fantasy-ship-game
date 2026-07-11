package prototype_map_fog

// PROTOTYPE shell for issue #62 -- see graph.odin/variants.odin for the
// question this answers. Run with: odin run cmd/prototype_map_fog
//
// Left/Right arrows switch between three variants of "what does the player
// see" for the map's node-hiding mechanism. Press 1-4 to travel: forward
// options are new territory, back options retrace an edge to an
// already-visited node (movement is no longer forward-only -- reversed
// from map #59's original chartering, see NOTES.md). Revisiting a node
// never re-triggers its encounter. R resets the walk; G rolls a new graph.
// Delete this whole directory (or fold the validated approach into
// cmd/game/view.odin) once #62 closes.

import "core:fmt"
import rl "vendor:raylib"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 700

variant_names := [3]string{"A -- Full graph, kind hidden", "B -- Fog by distance (horizon)", "C -- Zone progress + choice fan"}

Proto_State :: struct {
	g:             Graph,
	visited:       []bool,
	current_id:    int,
	variant:       int,
	seed:          u64,
	just_triggered: bool, // did the most recent step fire a fresh encounter?
}

state_reset_walk :: proc(s: ^Proto_State) {
	delete(s.visited)
	s.visited = make([]bool, len(s.g.nodes))
	s.visited[s.g.start_id] = true
	s.current_id = s.g.start_id
	s.just_triggered = false
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

		all_options := travel_options(state.g, state.current_id, state.visited)
		// Only 4 number keys exist -- cap what's drawn/selectable to match,
		// so a numbered node on screen is always actually travelable
		// (the generator keeps real degree well under this in practice).
		options := all_options[:min(len(all_options), 4)]

		for key, i in ([4]rl.KeyboardKey{.ONE, .TWO, .THREE, .FOUR}) {
			if rl.IsKeyPressed(key) && i < len(options) {
				dest := options[i]
				state.just_triggered = will_trigger(state.g, dest, state.visited)
				state.current_id = dest
				state.visited[dest] = true
			}
		}

		camera := follow_camera(state.g, state.current_id)

		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)

		rl.DrawText("PROTOTYPE issue #62 -- map hiding mechanism", 20, 16, 20, rl.DARKGRAY)
		rl.DrawText(fmt.ctprintf("seed %d", state.seed), WINDOW_WIDTH - 100, 16, 16, rl.GRAY)

		switch state.variant {
		case 0:
			rl.BeginMode2D(camera)
			draw_variant_a(state.g, state.visited, state.current_id, options)
			rl.EndMode2D()
		case 1:
			rl.BeginMode2D(camera)
			draw_variant_b(state.g, state.visited, state.current_id, options)
			rl.EndMode2D()
			rl.DrawText("Fog: unrevealed graph beyond the horizon is not drawn at all", 20, 40, 14, rl.DARKGRAY)
		case 2:
			draw_variant_c(state.g, state.visited, state.current_id, options)
		}

		draw_switcher_hint(options)
		draw_switcher_bar(state.variant)
		draw_status_line(state)

		rl.EndDrawing()
		delete(all_options)
	}
}

// follow_camera scrolls the view horizontally to keep the current node
// roughly centered, like Slay the Spire's vertical map scroll -- the graph's
// world is now much wider than any window (issue #62: "much wider"), so
// there's no fixed layout that fits the whole thing on screen at once.
// Vertical position is left alone (target/offset.y stay 0) since lanes
// already fit within the window. Clamped so the camera never shows past
// either world edge, or shrinks to fit if the whole world happens to be
// narrower than the window.
follow_camera :: proc(g: Graph, current_id: int) -> rl.Camera2D {
	half_w := f32(WINDOW_WIDTH) / 2
	world_left := f32(MAP_LEFT) - 60
	world_right := g.world_right + 60

	target_x := g.nodes[current_id].pos.x
	if world_right-world_left <= f32(WINDOW_WIDTH) {
		target_x = (world_left + world_right) / 2
	} else {
		min_x := world_left + half_w
		max_x := world_right - half_w
		target_x = clamp(target_x, min_x, max_x)
	}

	return rl.Camera2D{target = rl.Vector2{target_x, 0}, offset = rl.Vector2{half_w, 0}, zoom = 1}
}

draw_status_line :: proc(state: Proto_State) {
	msg: cstring
	color := rl.DARKGRAY
	switch {
	case is_landmark(state.g.nodes[state.current_id]):
		msg = "At a landmark -- no encounter here"
	case state.just_triggered:
		msg = "Encounter triggers!"
		color = rl.MAROON
	case:
		msg = "Revisiting -- encounter does not re-trigger"
		color = rl.DARKBLUE
	}
	rl.DrawText(msg, WINDOW_WIDTH / 2 - 140, WINDOW_HEIGHT - 90, 18, color)
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
