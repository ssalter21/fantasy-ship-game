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
// An unvisited Encounter is a generic zone-tinted marker with no label — its
// content is hidden until arrival (the Sim's hiding contract). Once visited, an
// Encounter shows its revealed first stage's colour and label; landmarks
// (Start/Port/Goal) are always fully labelled.
//
// Labelling by the first stage is what today's one-stage recipes allow
// (catalog.odin); rendering an arbitrary stage sequence — including a halt read
// as a consequence rather than a bug — is issue #139.
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
			// Content hidden: generic zone-tinted marker, no label.
			return zone_tint(p.zone), ""
		}
		encounter, _ := p.encounter.?
		stage, has_stage := run.run_encounter_current(encounter)
		if !has_stage {
			return rl.GRAY, ""
		}
		switch _ in stage {
		case run.Stage_Fight:
			return rl.Fade(rl.MAROON, 0.7), "Battle"
		case run.Stage_Offer:
			return rl.Fade(rl.LIME, 0.7), "Items"
		case run.Stage_Trade:
			return rl.Fade(rl.ORANGE, 0.7), "Trade"
		case run.Stage_Shop:
			return rl.SKYBLUE, "Shop"
		case run.Stage_Reward:
			return rl.Fade(rl.GOLD, 0.7), "Loot"
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

	// Rendering path (issue #83): draw_map recomputes the reachable set from the
	// same predicate + visited the Sim uses, rather than borrowing the emitted
	// state.travel_options. The two agree at a travel decision, but this map is
	// also drawn mid-encounter (behind the upgrade menu, the end-of-run beat)
	// when no travel options are current — the fresh recompute rings the nodes
	// reachable from wherever the ship *is*. The decision path (travel_menu_loop)
	// is what consumes the Sim's emitted options.
	// options is run_travel_options' temp_allocator scratch (see its contract),
	// reclaimed by the per-frame free_all in draw_scene — no hand-free here.
	options := run.run_travel_options(state.run_map, state.current_node_id, state.visited)

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

// fitting_tags_label renders a fitting's tag families as a comma-separated list
// ("Crew, Weapon"), or "—" when it carries none. Used by the Item Offer and
// Refit screens (issue #96) to show which families an item belongs to.
fitting_tags_label :: proc(tags: bit_set[ship.Tag]) -> string {
	label := ""
	for tag in ship.Tag {
		if tag not_in tags {
			continue
		}
		if len(label) == 0 {
			label = fmt.tprintf("%v", tag)
		} else {
			label = fmt.tprintf("%s, %v", label, tag)
		}
	}
	return len(label) > 0 ? label : "—"
}

// fitting_effect_intent renders a one-line, human-readable summary of what a
// fitting's effect does (issue #96's "effect intent"): the magnitude and what it
// feeds — a combat phase (its Category), or a ship stat for a stat-modifier —
// with the synergy/conditional context spelled out ("+2 Buff per Weapon",
// "+8 Offense below 50% HP"). Reads whichever of active/passive carries the one
// effect a roster item has; returns "no effect" for a cargo filler.
fitting_effect_intent :: proc(f: ship.Fitting) -> string {
	effect: ship.Effect
	if active, ok := f.active.?; ok {
		effect = active
	} else if passive, ok := f.passive.?; ok {
		effect = passive
	} else {
		return "no effect"
	}

	target: string
	switch effect.kind {
	case .Phase_Contribution:
		switch f.category {
		case .Buff:
			target = "Buff"
		case .Defensive:
			target = "Defense"
		case .Offensive:
			target = "Offense"
		}
	case .Modify_Durability:
		target = "Durability"
	case .Modify_Speed:
		target = "Speed"
	case .Modify_Max_HP:
		target = "Max HP"
	}

	intent := fmt.tprintf("+%d %s", int(effect.magnitude), target)
	if selector, ok := effect.synergy.?; ok {
		intent = fmt.tprintf("%s per %v", intent, selector)
	}
	if condition, ok := effect.conditional.?; ok {
		intent = fmt.tprintf("%s %s", intent, condition_intent(condition))
	}
	return intent
}

// condition_intent renders a conditional effect's trigger as a short clause the
// Item Offer / Refit UI appends to the effect intent (issue #96).
condition_intent :: proc(condition: ship.Condition) -> string {
	switch c in condition {
	case ship.Condition_HP_Below:
		return fmt.tprintf("below %d%% HP", c.percent)
	case ship.Condition_Round_At_Least:
		return fmt.tprintf("from round %d", c.round)
	case ship.Condition_Self_Visibility:
		return fmt.tprintf("while %v", c.visibility)
	case ship.Condition_Opponent_Faster:
		return "vs a faster foe"
	case ship.Condition_Opponent_Slower:
		return "vs a slower foe"
	}
	return ""
}

// fitting_summary_lines renders the two detail lines the Item Offer and Refit
// screens show under an item's name (issue #96's tags / phase / size / effect
// intent): the first its size, phase (Category), and tag families; the second
// its effect intent.
fitting_summary_lines :: proc(f: ship.Fitting) -> (string, string) {
	spec := fmt.tprintf("%v · %v · %s", f.size, f.category, fitting_tags_label(f.tags))
	return spec, fitting_effect_intent(f)
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
