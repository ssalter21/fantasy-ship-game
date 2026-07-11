package main

import "core:fmt"
import run "../../core/run"
import ship "../../core/ship"
import rl "vendor:raylib"

MAP_AREA := rl.Rectangle{x = 20, y = 20, width = 620, height = 640}
SHIP_PANEL_X :: 670
POINT_RADIUS :: 16

// point_column lays out Start/Goal at the outer columns and each zone in
// between (issue #24: Point/Map carry no coordinates — ADR-0007 — so this is
// a presentation-only concern).
point_column :: proc(p: run.Point) -> int {
	switch p.kind {
	case .Start:
		return 0
	case .Goal:
		return 4
	case .Port, .Encounter:
		zone, _ := p.zone.?
		switch zone {
		case .Coastal:
			return 1
		case .Open_Sea:
			return 2
		case .Deep:
			return 3
		}
	}
	return 0
}

// compute_point_positions assigns each point a screen position: one column
// per point_column, stacked top-to-bottom in map.points order within a
// column. Caller owns the returned slice.
compute_point_positions :: proc(run_map: run.Map) -> []rl.Vector2 {
	positions := make([]rl.Vector2, len(run_map.points))
	col_rows: [5]int
	for p in run_map.points {
		col := point_column(p)
		row := col_rows[col]
		col_rows[col] += 1
		positions[p.id] = rl.Vector2{
			MAP_AREA.x + f32(col) * (MAP_AREA.width / 4),
			MAP_AREA.y + 40 + f32(row) * 80,
		}
	}
	return positions
}

// point_marker picks a marker color and label by Point_Kind/Encounter_Kind
// in one pass, dimming the color once visited (issue #24). color and label
// are always consumed together at draw_map's single call site, so one
// switch replaces what was previously two parallel switches over the same
// Point_Kind/Encounter_Kind shape.
point_marker :: proc(p: run.Point, visited: bool) -> (color: rl.Color, label: string) {
	switch p.kind {
	case .Start:
		color, label = rl.SKYBLUE, "Start"
	case .Port:
		color, label = rl.SKYBLUE, "Port"
	case .Goal:
		color, label = rl.GOLD, "Goal"
	case .Encounter:
		encounter, _ := p.encounter.?
		switch enc in encounter {
		case run.Encounter_Ship_Battle:
			color, label = rl.MAROON, "Battle"
		case run.Encounter_Upgrade_Offer:
			color, label = rl.LIME, "Upgrade"
		case run.Encounter_Stat_Trade:
			color, label = rl.ORANGE, "Trade"
		}
	}
	if visited {
		color = rl.Fade(color, 0.4)
	}
	return
}

// draw_map draws every point at its cached position, highlighting the
// player's current location.
draw_map :: proc(state: ^Game_State) {
	rl.DrawRectangleLinesEx(MAP_AREA, 2, rl.GRAY)
	for p, i in state.run_map.points {
		pos := state.positions[i]
		color, label := point_marker(p, state.visited[i])
		rl.DrawCircleV(pos, POINT_RADIUS, color)
		if p.id == state.current_point_id {
			rl.DrawCircleLinesV(pos, POINT_RADIUS + 4, rl.BLACK)
		}
		rl.DrawText(fmt.ctprintf("%s", label), i32(pos.x - 20), i32(pos.y + POINT_RADIUS + 2), 12, rl.BLACK)
	}
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
				magnitude = active.magnitude
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
