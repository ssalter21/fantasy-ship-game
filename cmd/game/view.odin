package main

import "core:fmt"
import run "../../core/run"
import ship "../../core/ship"
import rl "vendor:raylib"

MAP_AREA := rl.Rectangle{x = 20, y = 20, width = 620, height = 640}
SHIP_PANEL_X :: 670
NODE_RADIUS :: 12
MAP_PAD :: 34

// compute_node_positions places each node from the generator's layer/lane
// metadata (issue #71): layer is the column (Start at the left, Goal at the
// right), lane the row within that column, evenly spread and centered so the
// whole graph is visible at once with no camera or panning. Nodes still carry
// no screen coordinates — that stays a presentation concern. Caller owns the
// returned slice.
compute_node_positions :: proc(run_map: run.Map) -> []rl.Vector2 {
	positions := make([]rl.Vector2, len(run_map.nodes))

	max_layer := 0
	layer_counts: map[int]int
	defer delete(layer_counts)
	for p in run_map.nodes {
		max_layer = max(max_layer, p.layer)
		layer_counts[p.layer] += 1
	}

	usable_w := MAP_AREA.width - 2 * MAP_PAD
	usable_h := MAP_AREA.height - 2 * MAP_PAD
	for p in run_map.nodes {
		fx := max_layer > 0 ? f32(p.layer) / f32(max_layer) : 0
		w := layer_counts[p.layer]
		fy := f32(p.lane + 1) / f32(w + 1)
		positions[p.id] = rl.Vector2{
			MAP_AREA.x + MAP_PAD + fx * usable_w,
			MAP_AREA.y + MAP_PAD + fy * usable_h,
		}
	}
	return positions
}

// zone_tint is the ambient colour of a zone, used both for the background
// gradient band and for an unvisited encounter's generic marker (issue #71) —
// the colour a player reads as "how deep into the run this is".
zone_tint :: proc(zone: Maybe(run.Zone)) -> rl.Color {
	z, ok := zone.?
	if !ok {
		return rl.Color{90, 100, 120, 255}
	}
	switch z {
	case .Coastal:
		return rl.Color{95, 170, 160, 255}
	case .Open_Sea:
		return rl.Color{70, 120, 190, 255}
	case .Deep:
		return rl.Color{55, 60, 110, 255}
	}
	return rl.Color{90, 100, 120, 255}
}

// node_appearance picks the marker colour and label for a node (issue #71).
// An unvisited Encounter is a generic zone-tinted marker with no kind label —
// its kind is hidden until arrival (the Sim's hiding contract). Once visited,
// an Encounter shows its revealed kind's colour and label; landmarks
// (Start/Port/Goal) are always fully labelled.
node_appearance :: proc(p: run.Node, visited: bool) -> (color: rl.Color, label: string) {
	switch p.kind {
	case .Start:
		return rl.SKYBLUE, "Start"
	case .Port:
		return rl.SKYBLUE, "Port"
	case .Goal:
		return rl.GOLD, "Goal"
	case .Encounter:
		if !visited {
			// Kind hidden: generic zone-tinted marker, no kind label.
			return zone_tint(p.zone), ""
		}
		encounter, _ := p.encounter.?
		switch enc in encounter {
		case run.Encounter_Ship_Battle:
			return rl.Fade(rl.MAROON, 0.7), "Battle"
		case run.Encounter_Upgrade_Offer:
			return rl.Fade(rl.LIME, 0.7), "Upgrade"
		case run.Encounter_Stat_Trade:
			return rl.Fade(rl.ORANGE, 0.7), "Trade"
		}
	}
	return rl.GRAY, ""
}

// move_fires reports whether traveling to node p would trigger a fresh
// encounter: only an unvisited Encounter fires (a landmark never does, a
// revisit never does). The UI uses this to colour-code offered moves without
// needing to know the still-hidden kind (issue #71).
move_fires :: proc(p: run.Node, visited: bool) -> bool {
	return p.kind == .Encounter && !visited
}

// draw_zone_background paints a Coastal -> Open_Sea -> Deep band behind the
// graph as an ambient depth cue (issue #71): each zone's faint tint spans the
// x-range of the columns belonging to it.
draw_zone_background :: proc(state: ^Game_State) {
	for zone in run.Zone {
		lo, hi: f32 = 1e9, -1e9
		found := false
		for p, i in state.run_map.nodes {
			pz, ok := p.zone.?
			if !ok || pz != zone {
				continue
			}
			found = true
			lo = min(lo, state.positions[i].x)
			hi = max(hi, state.positions[i].x)
		}
		if !found {
			continue
		}
		band := rl.Rectangle{
			x      = lo - MAP_PAD,
			y      = MAP_AREA.y,
			width  = (hi - lo) + 2 * MAP_PAD,
			height = MAP_AREA.height,
		}
		rl.DrawRectangleRec(band, rl.Fade(zone_tint(zone), 0.18))
	}
}

// draw_map draws the whole graph at once (issue #71): the zone-gradient
// background, every edge, every node's marker (unvisited encounters hidden as
// generic zone dots), the player's current location, and a numbered highlight
// on each directly-reachable node — colour-coded for whether stepping there
// fires a fresh encounter (red) or is safe (green: a revisit or a landmark).
draw_map :: proc(state: ^Game_State) {
	draw_zone_background(state)
	rl.DrawRectangleLinesEx(MAP_AREA, 2, rl.GRAY)

	// Edges (drawn under the nodes; each undirected pair once).
	for p in state.run_map.nodes {
		for v in state.run_map.edges[p.id] {
			if v <= p.id {
				continue
			}
			rl.DrawLineV(state.positions[p.id], state.positions[v], rl.Fade(rl.GRAY, 0.5))
		}
	}

	options := run.run_travel_options(state.run_map, state.current_node_id, state.visited)
	defer delete(options)

	for p, i in state.run_map.nodes {
		pos := state.positions[i]
		color, label := node_appearance(p, state.visited[i])
		rl.DrawCircleV(pos, NODE_RADIUS, color)
		if len(label) > 0 {
			rl.DrawText(fmt.ctprintf("%s", label), i32(pos.x - 18), i32(pos.y + NODE_RADIUS + 2), 12, rl.BLACK)
		}
	}

	// Reachable-next highlights, numbered, over the base markers.
	for dest, n in options {
		pos := state.positions[dest]
		ring := move_fires(state.run_map.nodes[dest], state.visited[dest]) ? rl.RED : rl.GREEN
		rl.DrawCircleLinesV(pos, NODE_RADIUS + 4, ring)
		rl.DrawText(fmt.ctprintf("%d", n + 1), i32(pos.x - 4), i32(pos.y - 7), 14, rl.WHITE)
	}

	// Current location outline, drawn last so it reads on top.
	cur := state.positions[state.current_node_id]
	rl.DrawCircleLinesV(cur, NODE_RADIUS + 7, rl.BLACK)
}

// draw_ship_panel renders a 6-slot ship readout at origin. When
// gate_visibility is true (rendering an opponent being scouted before a
// Ship Battle), a concealed slot's fitting is hidden per ADR-0005 — the
// player's own ship is always rendered ungated.
draw_ship_panel :: proc(s: ^ship.Ship, origin: rl.Vector2, title: string, gate_visibility: bool) {
	x := i32(origin.x)
	y := i32(origin.y)
	rl.DrawText(fmt.ctprintf("%s", title), x, y, 20, rl.DARKGRAY)
	rl.DrawText(fmt.ctprintf("HP %d/%d   DUR %d   SPD %d", s.hp, s.max_hp, s.durability, s.speed), x, y + 26, 16, rl.BLACK)

	for layout_slot, i in s.layout {
		row_y := y + 56 + i32(i) * 24
		fitting, has_fitting := layout_slot.fitting.?

		label: string
		switch {
		case !has_fitting:
			label = fmt.tprintf("%s: (empty)", layout_slot.slot.name)
		case gate_visibility && ship.ship_effective_visibility(layout_slot) == .Concealed:
			label = fmt.tprintf("%s: ???", layout_slot.slot.name)
		case:
			magnitude := 0
			if active, has_active := fitting.active.?; has_active {
				magnitude = int(active.magnitude)
			}
			label = fmt.tprintf("%s: %s (%d)", layout_slot.slot.name, fitting.name, magnitude)
		}
		rl.DrawText(fmt.ctprintf("%s", label), x, row_y, 14, rl.BLACK)
	}
}

// draw_scene_contents draws whichever screen is currently relevant (battle
// or map), the player's own ship panel, and an optional overlay banner.
// Does not Begin/EndDrawing itself — callers that need to draw more on top
// (menu.odin's button lists) share one Begin/End pair by calling this
// in between; draw_scene below is the standalone wrapper for callers with
// nothing further to draw.
draw_scene_contents :: proc(state: ^Game_State, overlay: string) {
	rl.ClearBackground(rl.RAYWHITE)

	if state.in_battle {
		if opponent, ok := state.sighted_opponent.?; ok {
			draw_ship_panel(&opponent, rl.Vector2{SHIP_PANEL_X, 20}, "Opponent", true)
		}
		draw_ship_panel(&state.player, rl.Vector2{SHIP_PANEL_X, 220}, "Your Ship", false)
	} else {
		draw_map(state)
		draw_ship_panel(&state.player, rl.Vector2{SHIP_PANEL_X, 20}, "Your Ship", false)
	}

	if len(overlay) > 0 {
		rl.DrawRectangle(0, WINDOW_HEIGHT - 60, WINDOW_WIDTH, 60, rl.Fade(rl.BLACK, 0.75))
		rl.DrawText(fmt.ctprintf("%s", overlay), 20, WINDOW_HEIGHT - 44, 20, rl.RAYWHITE)
	}

	draw_version_stamp()
}

// draw_version_stamp draws the build's VERSION (issue #44) in the top-right
// corner of every scene, right-aligned so a short "dev" and a full git SHA
// both sit flush to the edge. Guards on IsWindowReady() like the rest of the
// render layer (ADR-0003) so it's a no-op under `odin test`.
draw_version_stamp :: proc() {
	if !rl.IsWindowReady() {
		return
	}

	FONT_SIZE :: 12
	MARGIN :: 6
	text := fmt.ctprintf("%s", VERSION)
	width := rl.MeasureText(text, FONT_SIZE)
	rl.DrawText(text, WINDOW_WIDTH - width - MARGIN, MARGIN, FONT_SIZE, rl.GRAY)
}

// draw_scene is draw_scene_contents wrapped in its own Begin/EndDrawing pair
// (used by the blocking event-playback beats in menu.odin, which have
// nothing further to draw on top).
draw_scene :: proc(state: ^Game_State, overlay: string) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	draw_scene_contents(state, overlay)
}
