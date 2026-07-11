package prototype_map_fog

// PROTOTYPE -- three structurally different answers to issue #62's question,
// switchable at runtime (Left/Right arrows) so they can be judged side by
// side against the same generated graph and walk. See main.odin for the
// switcher and graph.odin for the fabricated graph and travel_options.

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

draw_switcher_hint :: proc(options: []int) {
	x := i32(MAP_LEFT)
	y := i32(MAP_BOTTOM) + 30
	rl.DrawText("1-6: travel (forward = new, back = retrace)   R: reset walk   G: new graph", x, y, 16, rl.DARKGRAY)
}

// draw_option_rings numbers every travel option 1..n, ringed yellow if
// stepping there fires a fresh encounter and skyblue if it's a landmark or
// an already-visited revisit that won't re-trigger one.
draw_option_rings :: proc(g: Graph, visited: []bool, options: []int) {
	for id, i in options {
		n := g.nodes[id]
		ring_color := rl.YELLOW if will_trigger(g, id, visited) else rl.SKYBLUE
		rl.DrawCircleLinesV(n.pos, NODE_RADIUS + 6, ring_color)
		rl.DrawText(fmt.ctprintf("%d", i + 1), i32(n.pos.x - 4), i32(n.pos.y - 26), 18, rl.BLACK)
	}
}

// draw_zone_gradient_h paints a left(Coastal)->mid(Open_Sea)->right(Deep)
// background across a rectangle, matching Start-at-left/Goal-at-right node
// layout (issue #62 follow-up: visualize zone progression as background
// color, not just per-node color).
draw_zone_gradient_h :: proc(left, top, right, bottom: i32) {
	mid := (left + right) / 2
	c1 := rl.Fade(zone_color[.Coastal], 0.28)
	c2 := rl.Fade(zone_color[.Open_Sea], 0.28)
	c3 := rl.Fade(zone_color[.Deep], 0.28)
	rl.DrawRectangleGradientH(left, top, mid - left, bottom - top, c1, c2)
	rl.DrawRectangleGradientH(mid, top, right - mid, bottom - top, c2, c3)
}

// draw_zone_gradient_v is the same idea, top(Coastal)->bottom(Deep), for
// Variant C's vertically-stacked zone rows.
draw_zone_gradient_v :: proc(left, top, right, bottom: i32) {
	mid := (top + bottom) / 2
	c1 := rl.Fade(zone_color[.Coastal], 0.28)
	c2 := rl.Fade(zone_color[.Open_Sea], 0.28)
	c3 := rl.Fade(zone_color[.Deep], 0.28)
	rl.DrawRectangleGradientV(left, top, right - left, mid - top, c1, c2)
	rl.DrawRectangleGradientV(left, mid, right - left, bottom - mid, c2, c3)
}

// ===================== Variant A: full graph, kind hidden =====================
// Every node/edge position is visible from the start. Unvisited encounters
// show only a small zone-tinted dot -- no kind color, no label. Visited
// nodes flip to full kind color+label permanently (route history). Travel
// options (forward into new territory, or back along an edge to an
// already-visited node) get a numbered ring; yellow if stepping there
// fires a fresh encounter, skyblue if it won't (revisit or landmark).
// Start/Port/Goal are landmarks, not encounters -- always shown with their
// full label, visited or not.

draw_variant_a :: proc(g: Graph, visited: []bool, current_id: int, options: []int) {
	draw_zone_gradient_h(i32(MAP_LEFT) - 10, i32(MAP_TOP) - 10, i32(MAP_RIGHT) + 10, i32(MAP_BOTTOM) + 10)

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

	draw_option_rings(g, visited, options)
}

// ===================== Variant B: fog by graph-distance (horizon) =====================
// Only visited nodes, the current node, and its direct neighbors are fully
// drawn and connected by edges. One more hop out ("the horizon") is shown as
// faint unconnected dots -- enough to hint the graph continues, not enough
// to reveal its shape. Anything further isn't drawn at all. Start/Port/Goal
// are landmarks, not encounters -- they're always revealed regardless of
// distance, though an edge to one still only draws once both its ends are
// revealed, so a far-off port's *position* is visible before the path to
// it is.

draw_variant_b :: proc(g: Graph, visited: []bool, current_id: int, options: []int) {
	draw_zone_gradient_h(i32(MAP_LEFT) - 10, i32(MAP_TOP) - 10, i32(MAP_RIGHT) + 10, i32(MAP_BOTTOM) + 10)

	revealed := make([dynamic]int)
	defer delete(revealed)
	horizon := make([dynamic]int)
	defer delete(horizon)

	for n in g.nodes {
		if visited[n.id] || n.id == current_id || is_in(n.id, options) || n.is_start || n.is_port || n.is_goal {
			append(&revealed, n.id)
		}
	}
	for id in options {
		next := travel_options(g, id, visited)
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

	draw_option_rings(g, visited, options)
}

// ===================== Variant C: zone progress + local choice fan =====================
// The full graph is never shown. A slim per-zone progress strip gives
// coarse "how far am I / what have I found" feedback, backed by a
// Coastal->Open_Sea->Deep vertical gradient matching the row order. The
// main area is a decision fan: only the current node and its direct travel
// options, rendered as picker cards -- structurally a menu, not a map.
// Start/Port/Goal are landmarks, not encounters, so a route spine above the
// progress bars always shows Start, every port, and Goal -- the only
// positions this variant ever draws outside the immediate choice fan.

draw_variant_c :: proc(g: Graph, visited: []bool, current_id: int, options: []int) {
	zones := [3]Zone{.Coastal, .Open_Sea, .Deep}
	zone_names := [Zone]string{.Coastal = "Coastal", .Open_Sea = "Open Sea", .Deep = "Deep"}

	spine_y := i32(MAP_TOP) - 34
	spine_left := i32(MAP_LEFT) + 90
	spine_right := spine_left + 500
	bar_y: i32 = i32(MAP_TOP)

	draw_zone_gradient_v(i32(MAP_LEFT) - 10, spine_y - 30, spine_right + 130, bar_y + 34 * 3 + 10)

	rl.DrawLineEx(rl.Vector2{f32(spine_left), f32(spine_y)}, rl.Vector2{f32(spine_right), f32(spine_y)}, 2, rl.Fade(rl.GRAY, 0.5))
	rl.DrawCircle(spine_left, spine_y, 7, rl.SKYBLUE)
	rl.DrawText("Start", spine_left - 14, spine_y + 10, 12, rl.DARKGRAY)
	rl.DrawCircle(spine_right, spine_y, 7, rl.GOLD)
	rl.DrawText("Goal", spine_right - 12, spine_y + 10, 12, rl.DARKGRAY)
	port_i := 0
	port_total := 0
	for n in g.nodes {
		if n.is_port {
			port_total += 1
		}
	}
	for n in g.nodes {
		if !n.is_port {
			continue
		}
		port_i += 1
		x := spine_left + i32(f32(spine_right - spine_left) * f32(port_i) / f32(port_total + 1))
		rl.DrawCircle(x, spine_y, 5, rl.SKYBLUE)
	}
	rl.DrawText("Start / Port / Goal positions are landmarks -- always visible, never fogged", spine_left, spine_y - 20, 12, rl.DARKGRAY)

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
	start_x := cx - spacing * i32(len(options) - 1) / 2
	card_y := cy + 130
	zone_names2 := [Zone]string{.Coastal = "Coastal", .Open_Sea = "Open Sea", .Deep = "Deep"}
	for id, i in options {
		n := g.nodes[id]
		x := start_x + i32(i) * spacing
		fires := will_trigger(g, id, visited)
		fill := rl.Fade(zone_color[n.zone], 0.85) if fires else rl.Fade(rl.SKYBLUE, 0.4)
		rl.DrawRectangle(x - 55, card_y - 40, 110, 90, fill)
		rl.DrawRectangleLines(x - 55, card_y - 40, 110, 90, rl.BLACK)
		rl.DrawText(fmt.ctprintf("%d", i + 1), x - 6, card_y - 34, 22, rl.BLACK)
		label := "Goal" if n.is_goal else ("Port" if n.is_port else zone_names2[n.zone])
		rl.DrawText(fmt.ctprintf("%s", label), x - 40, card_y, 13, rl.BLACK)
		detail := "kind unknown" if fires else "revisit -- no encounter"
		rl.DrawText(fmt.ctprintf("%s", detail), x - 46, card_y + 18, 11, rl.DARKGRAY)
		rl.DrawLineV(rl.Vector2{f32(cx), f32(cy) + 22}, rl.Vector2{f32(x), f32(card_y) - 40}, rl.Fade(rl.GRAY, 0.6))
	}

	rl.DrawText("No full map is ever shown -- only zone progress and your immediate options.", i32(MAP_LEFT), fan_top - 6, 14, rl.DARKGRAY)
}
