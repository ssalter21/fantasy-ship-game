package prototype_map_fog

// PROTOTYPE -- three structurally different answers to issue #62's question,
// switchable at runtime (Left/Right arrows) so they can be judged side by
// side against the same generated graph and walk. See main.odin for the
// switcher and graph.odin for the fabricated graph.

import "core:fmt"
import rl "vendor:raylib"

NODE_RADIUS :: 9
CURRENT_RADIUS :: 13

node_label :: proc(n: Node) -> string {
	if n.is_start {
		return "Start"
	}
	if n.is_goal {
		return "Goal"
	}
	if n.is_port {
		return "Port"
	}
	return kind_label[n.kind]
}

node_resolved_color :: proc(n: Node) -> rl.Color {
	if n.is_start || n.is_goal || n.is_port {
		return rl.SKYBLUE if !n.is_goal else rl.GOLD
	}
	return kind_color[n.kind]
}

is_in :: proc(id: int, ids: []int) -> bool {
	for x in ids {
		if x == id {
			return true
		}
	}
	return false
}

draw_switcher_hint :: proc(reachable: []int) {
	x := i32(MAP_LEFT)
	y := i32(MAP_BOTTOM) + 30
	rl.DrawText("1-4: travel to a reachable node   R: reset walk   G: new graph", x, y, 16, rl.DARKGRAY)
}

// ===================== Variant A: full graph, kind hidden =====================
// Every node/edge position is visible from the start. Unvisited encounters
// show only a small zone-tinted dot -- no kind color, no label. Visited
// nodes flip to full kind color+label permanently (route history). Directly
// reachable nodes get a numbered highlight ring regardless of visited state.

draw_variant_a :: proc(g: Graph, visited: []bool, current_id: int, reachable: []int) {
	for e in g.edges {
		from := g.nodes[e.from].pos
		to := g.nodes[e.to].pos
		rl.DrawLineV(from, to, rl.Fade(rl.GRAY, 0.35))
	}

	for n in g.nodes {
		color: rl.Color
		label: string
		if n.is_start || n.is_port || n.is_goal || visited[n.id] {
			color = node_resolved_color(n)
			label = node_label(n)
			if visited[n.id] && !n.is_start && !n.is_goal && !n.is_port {
				color = rl.Fade(color, 0.55) // resolved-but-passed, per today's dimming
			}
		} else {
			color = rl.Fade(zone_color[n.zone], 0.5)
			label = ""
		}
		radius: f32 = CURRENT_RADIUS if n.id == current_id else NODE_RADIUS
		rl.DrawCircleV(n.pos, radius, color)
		if n.id == current_id {
			rl.DrawCircleLinesV(n.pos, radius + 4, rl.BLACK)
		}
		if label != "" {
			rl.DrawText(fmt.ctprintf("%s", label), i32(n.pos.x - 18), i32(n.pos.y + radius + 2), 11, rl.BLACK)
		}
	}

	for id, i in reachable {
		n := g.nodes[id]
		rl.DrawCircleLinesV(n.pos, NODE_RADIUS + 6, rl.YELLOW)
		rl.DrawText(fmt.ctprintf("%d", i + 1), i32(n.pos.x - 4), i32(n.pos.y - 26), 18, rl.BLACK)
	}

	draw_switcher_hint(reachable)
}

// ===================== Variant B: fog by graph-distance (horizon) =====================
// Only visited nodes, the current node, and its direct neighbors are fully
// drawn and connected by edges. One more hop out ("the horizon") is shown as
// faint unconnected dots -- enough to hint the graph continues, not enough
// to reveal its shape. Anything further isn't drawn at all.

draw_variant_b :: proc(g: Graph, visited: []bool, current_id: int, reachable: []int) {
	revealed := make([dynamic]int)
	defer delete(revealed)
	horizon := make([dynamic]int)
	defer delete(horizon)

	for n in g.nodes {
		if visited[n.id] || n.id == current_id || is_in(n.id, reachable) {
			append(&revealed, n.id)
		}
	}
	for id in reachable {
		next := reachable_next(g, id)
		defer delete(next)
		for h in next {
			if !is_in(h, revealed[:]) && !is_in(h, horizon[:]) {
				append(&horizon, h)
			}
		}
	}

	for e in g.edges {
		if is_in(e.from, revealed[:]) && is_in(e.to, revealed[:]) {
			rl.DrawLineV(g.nodes[e.from].pos, g.nodes[e.to].pos, rl.Fade(rl.GRAY, 0.45))
		}
	}

	for id in horizon {
		n := g.nodes[id]
		rl.DrawCircleV(n.pos, NODE_RADIUS - 3, rl.Fade(rl.LIGHTGRAY, 0.35))
	}

	for id in revealed {
		n := g.nodes[id]
		color: rl.Color
		label: string
		if n.is_start || n.is_port || n.is_goal || visited[n.id] {
			color = node_resolved_color(n)
			label = node_label(n)
			if visited[n.id] && !n.is_start && !n.is_goal && !n.is_port {
				color = rl.Fade(color, 0.55)
			}
		} else {
			color = zone_color[n.zone]
			label = ""
		}
		radius: f32 = CURRENT_RADIUS if n.id == current_id else NODE_RADIUS
		rl.DrawCircleV(n.pos, radius, color)
		if n.id == current_id {
			rl.DrawCircleLinesV(n.pos, radius + 4, rl.BLACK)
		}
		if label != "" {
			rl.DrawText(fmt.ctprintf("%s", label), i32(n.pos.x - 18), i32(n.pos.y + radius + 2), 11, rl.BLACK)
		}
	}

	for id, i in reachable {
		n := g.nodes[id]
		rl.DrawCircleLinesV(n.pos, NODE_RADIUS + 6, rl.YELLOW)
		rl.DrawText(fmt.ctprintf("%d", i + 1), i32(n.pos.x - 4), i32(n.pos.y - 26), 18, rl.BLACK)
	}

	rl.DrawText("Fog: unrevealed graph beyond the horizon is not drawn at all", i32(MAP_LEFT), i32(MAP_TOP) - 24, 14, rl.DARKGRAY)
	draw_switcher_hint(reachable)
}

// ===================== Variant C: zone progress + local choice fan =====================
// The full graph is never shown. A slim per-zone progress strip gives
// coarse "how far am I / what have I found" feedback. The main area is a
// decision fan: only the current node and its direct reachable options,
// rendered as picker cards -- structurally a menu, not a map.

draw_variant_c :: proc(g: Graph, visited: []bool, current_id: int, reachable: []int) {
	zones := [3]Zone{.Coastal, .Open_Sea, .Deep}
	zone_names := [Zone]string{.Coastal = "Coastal", .Open_Sea = "Open Sea", .Deep = "Deep"}
	bar_y: i32 = i32(MAP_TOP)
	for zone, zi in zones {
		total := 0
		visited_count := 0
		for n in g.nodes {
			if n.zone != zone || n.is_start || n.is_goal || n.is_port {
				continue
			}
			total += 1
			if visited[n.id] {
				visited_count += 1
			}
		}
		y := bar_y + i32(zi) * 34
		rl.DrawText(fmt.ctprintf("%s", zone_names[zone]), i32(MAP_LEFT), y, 14, rl.DARKGRAY)
		bx := i32(MAP_LEFT) + 90
		bw := i32(500)
		rl.DrawRectangle(bx, y, bw, 16, rl.Fade(zone_color[zone], 0.25))
		if total > 0 {
			fill := i32(f32(bw) * f32(visited_count) / f32(total))
			rl.DrawRectangle(bx, y, fill, 16, zone_color[zone])
		}
		rl.DrawText(fmt.ctprintf("%d/%d", visited_count, total), bx + bw + 10, y, 14, rl.DARKGRAY)
		if g.nodes[current_id].zone == zone && !g.nodes[current_id].is_goal {
			rl.DrawText("<- you are here", bx + bw + 60, y, 14, rl.MAROON)
		}
	}

	fan_top := i32(MAP_TOP) + 34 * 3 + 30
	cur := g.nodes[current_id]
	cx := i32(MAP_LEFT) + 560
	cy := fan_top + 60
	rl.DrawCircleV(rl.Vector2{f32(cx), f32(cy)}, 22, rl.SKYBLUE if !cur.is_goal else rl.GOLD)
	rl.DrawText(fmt.ctprintf("%s", node_label(cur)), cx - 22, cy + 28, 14, rl.BLACK)
	rl.DrawText("You are here", cx - 34, cy - 42, 12, rl.DARKGRAY)

	spacing := i32(160)
	start_x := cx - spacing * i32(len(reachable) - 1) / 2
	card_y := cy + 130
	for id, i in reachable {
		n := g.nodes[id]
		x := start_x + i32(i) * spacing
		rl.DrawRectangle(x - 55, card_y - 40, 110, 90, rl.Fade(zone_color[n.zone], 0.85))
		rl.DrawRectangleLines(x - 55, card_y - 40, 110, 90, rl.BLACK)
		rl.DrawText(fmt.ctprintf("%d", i + 1), x - 6, card_y - 34, 22, rl.BLACK)
		zone_names2 := [Zone]string{.Coastal = "Coastal", .Open_Sea = "Open Sea", .Deep = "Deep"}
		label := "Goal" if n.is_goal else ("Port" if n.is_port else zone_names2[n.zone])
		rl.DrawText(fmt.ctprintf("%s", label), x - 40, card_y, 13, rl.BLACK)
		rl.DrawText("kind unknown", x - 38, card_y + 18, 11, rl.DARKGRAY)
		rl.DrawLineV(rl.Vector2{f32(cx), f32(cy) + 22}, rl.Vector2{f32(x), f32(card_y) - 40}, rl.Fade(rl.GRAY, 0.6))
	}

	rl.DrawText("No full map is ever shown -- only zone progress and your immediate options.", i32(MAP_LEFT), fan_top - 6, 14, rl.DARKGRAY)
	draw_switcher_hint(reachable)
}
