package main

import "core:fmt"
import "core:math/linalg"
import voyage "../../core/voyage"
import ship "../../core/ship"
import rl "vendor:raylib"

MAP_AREA := rl.Rectangle{x = 20, y = 20, width = 620, height = 640}
SHIP_PANEL_X :: 670
NODE_RADIUS :: 12
MAP_PAD :: 34

// compute_node_positions places each node from the generator's layer/lane
// metadata: layer is the column (Start left, Haven right), lane the row within
// it, evenly spread and centered so the whole graph fits with no camera or
// panning. Caller owns the returned slice.
compute_node_positions :: proc(voyage_map: voyage.Map) -> []rl.Vector2 {
	positions := make([]rl.Vector2, len(voyage_map.nodes))

	max_layer := 0
	layer_counts: map[int]int
	defer delete(layer_counts)
	for p in voyage_map.nodes {
		max_layer = max(max_layer, p.layer)
		layer_counts[p.layer] += 1
	}

	usable_w := MAP_AREA.width - 2 * MAP_PAD
	usable_h := MAP_AREA.height - 2 * MAP_PAD
	for p in voyage_map.nodes {
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

// stage_kind_label is the one place a Stage_Kind becomes player-facing words,
// shared by the encounter strip, a halt's beat, and (via node_marker) the map. The
// enum spelling is authoring vocabulary, not the player's.
stage_kind_label :: proc(kind: voyage.Stage_Kind) -> string {
	switch kind {
	case .Fight:
		return "Battle"
	case .Offer:
		return "Items"
	case .Trade:
		return "Trade"
	case .Shop:
		return "Market"
	case .Reward:
		return "Loot"
	}
	return "?"
}

// stage_tint is a stage primitive's colour, shared by the map marker and the encounter
// strip so a Battle node and a Battle chip read as the same thing. These are the style
// guide's muted category tones ("category is hue, state is brightness"): each kind keeps a
// distinct hue but pulled into the palette's register and never at full saturation, so none
// competes with the reserved amber. Retires the rl.MAROON/LIME/ORANGE/SKYBLUE/GOLD rainbow
// the guide bans — two of whose five were amber-adjacent and broke the amber rule.
stage_tint :: proc(kind: voyage.Stage_Kind) -> rl.Color {
	switch kind {
	case .Fight:
		return rl.Color{166, 72, 90, 255} // muted maroon (#A6485A) — the one warm beside amber
	case .Offer:
		return rl.Color{110, 158, 90, 255} // muted lime (#6E9E5A)
	case .Trade:
		return rl.Color{180, 121, 74, 255} // muted orange (#B4794A)
	case .Shop:
		return rl.Color{78, 140, 184, 255} // muted sky (#4E8CB8)
	case .Reward:
		return rl.Color{192, 164, 94, 255} // muted gold (#C0A45E) — loses gold as identity, by design
	}
	return rl.Color{74, 85, 104, 255} // fallback (#4A5568)
}

// node_marker is the map's colour and label for an encounter, keyed on the stage it
// opens with. A Shop opening reads "Port" here, and only here — everywhere else a Shop
// stage is a "Market" (stage_kind_label) — because this names a *node*, and a node
// opening on a Shop is a Port (ADR-0016). That rests on the authoring convention that
// only the Port bucket opens on a Shop (catalog.odin): author one `[Shop, Fight]` and
// this label starts lying, which the_only_encounters_a_captain_can_see_coming_are_ports
// guards.
node_marker :: proc(opening: voyage.Stage_Kind) -> (color: rl.Color, label: string) {
	label = stage_kind_label(opening)
	if opening == .Shop {
		label = "Port"
	}
	return stage_tint(opening), label
}

// node_appearance picks the marker colour and label for a node. A hidden Encounter is a
// quiet recessive-blue buoy with no label (the Sim's hiding contract); a visited one, or
// one that reveals before arrival, shows its opening stage's muted category colour and
// label, faded when visited so the map keeps a memory of the route. Start is steel and
// Haven cream — landmarks, not stages, so off the category hues entirely, and the old
// stock SKYBLUE/GOLD/GRAY are retired (style guide bans them).
//
// The shape each node is drawn as (home-mark, dock, diamond, buoy, island) is node_mark's
// call, keyed on the same predicates; this proc owns only the colour and the label. It is
// still a place the reveal question is asked of the stage list, never the node kind
// (ADR-0014, voyage_encounter_reveals) — the same question the Sim's mask asks.
node_appearance :: proc(p: voyage.Node, visited: bool) -> (color: rl.Color, label: string) {
	switch p.kind {
	case .Start:
		return COLOUR_STEEL, "Start"
	case .Haven:
		return COLOUR_CREAM, "Haven"
	case .Encounter:
		// A masked node has no encounter to label; an unvisited one that doesn't reveal
		// keeps its content back until arrival. Both are the Sim's answer rendered, never
		// re-derived here (ADR-0009): a hidden encounter's stages aren't in presentation's
		// payload, so there's nothing to leak.
		encounter, has_encounter := p.encounter.?
		if !has_encounter || (!visited && !voyage.voyage_encounter_reveals(encounter)) {
			return COLOUR_BLUE_RECESSIVE, ""
		}
		opening, has_opening := voyage.voyage_encounter_opening(encounter)
		if !has_opening {
			return COLOUR_BLUE_RECESSIVE, ""
		}
		color, label = node_marker(voyage.voyage_stage_kind(opening))
		if visited {
			color = rl.Fade(color, 0.3)
		}
		return color, label
	}
	return COLOUR_BLUE_RECESSIVE, ""
}

// Node_Mark is the shape a node is drawn as on the chart: the Start home-mark, the Haven
// island, a Port's dock, a revealed encounter's category diamond, or an unrevealed
// encounter's ? buoy. Shape carries identity colour alone can't — a Port and a revealed
// Shop share the Shop hue, but only the Port is a routable landfall, so it takes the dock
// while every other revealed encounter takes a diamond.
Node_Mark :: enum {
	Home,
	Island,
	Dock,
	Diamond,
	Buoy,
}

// node_mark classifies a node into its chart shape. It re-asks the same reveal predicate
// node_appearance does (voyage_encounter_reveals) rather than share a computed value: the
// two answer different questions off one fact — what shape, what colour — and keeping them
// side by side is the file's own idiom (move_fires re-derived reveal the same way). A
// masked or opening-less encounter falls through to a buoy, the same "nothing to show yet".
node_mark :: proc(p: voyage.Node, visited: bool) -> Node_Mark {
	switch p.kind {
	case .Start:
		return .Home
	case .Haven:
		return .Island
	case .Encounter:
		encounter, has_encounter := p.encounter.?
		if !has_encounter || (!visited && !voyage.voyage_encounter_reveals(encounter)) {
			return .Buoy
		}
		opening, has_opening := voyage.voyage_encounter_opening(encounter)
		if !has_opening {
			return .Buoy
		}
		if voyage.voyage_stage_kind(opening) == .Shop {
			return .Dock
		}
		return .Diamond
	}
	return .Buoy
}

MAP_GRID_PITCH :: 64

// draw_map_water paints the chart's ground: a left→right depth gradient and a faint
// graticule inside MAP_AREA, framed by a recessive border. It replaces the three flat zone
// bands (#303). The zones already run Coastal→Open_Sea→Deep left-to-right — layer is the x
// axis (compute_node_positions) — so grading the water shallow→deep along x carries the
// same depth cue as one continuous sea rather than three stripes. The stops are the depth
// ramp itself (COLOUR_SHALLOW/MID/DEEP), drawn as two halves because raylib's horizontal
// gradient takes only two colours.
//
// The border is recessive blue, not a box that competes: the deep (right) end of the water
// is COLOUR_DEEP, the same as the canvas it sits on, so without an edge the panel would
// bleed into the ground. The grid is the quietest thing on the chart, faded like the Chart
// Table's own graticule (CHART_GRID at 0.22).
draw_map_water :: proc() {
	half := MAP_AREA.width / 2
	rl.DrawRectangleGradientH(
		i32(MAP_AREA.x),
		i32(MAP_AREA.y),
		i32(half),
		i32(MAP_AREA.height),
		COLOUR_SHALLOW,
		COLOUR_MID,
	)
	rl.DrawRectangleGradientH(
		i32(MAP_AREA.x + half),
		i32(MAP_AREA.y),
		i32(MAP_AREA.width - half),
		i32(MAP_AREA.height),
		COLOUR_MID,
		COLOUR_DEEP,
	)

	for x := MAP_AREA.x + MAP_GRID_PITCH; x < MAP_AREA.x + MAP_AREA.width; x += MAP_GRID_PITCH {
		rl.DrawLineV(
			rl.Vector2{x, MAP_AREA.y},
			rl.Vector2{x, MAP_AREA.y + MAP_AREA.height},
			rl.Fade(CHART_GRID, 0.22),
		)
	}
	for y := MAP_AREA.y + MAP_GRID_PITCH; y < MAP_AREA.y + MAP_AREA.height; y += MAP_GRID_PITCH {
		rl.DrawLineV(
			rl.Vector2{MAP_AREA.x, y},
			rl.Vector2{MAP_AREA.x + MAP_AREA.width, y},
			rl.Fade(CHART_GRID, 0.22),
		)
	}

	rl.DrawRectangleLinesEx(MAP_AREA, 2, COLOUR_BLUE_RECESSIVE)
}

// draw_map draws the whole chart at once: the depth-graded water, every route dashed in
// chart ink, every node as its mark (home / island / dock / diamond / buoy), the steel
// reachability rings with a danger tick on an unrevealed reachable node, the hover caret,
// and the ship you stand on as the screen's one amber. Composition only — `mouse` carries
// the hover so the loop can poll while capture passes a no-mouse sentinel and photographs
// the chart at rest (#277).
draw_map :: proc(state: ^Game_State, mouse: rl.Vector2) {
	draw_map_water()

	// The reachable set is recomputed here rather than borrowed from state.travel_options:
	// the map is also drawn mid-encounter (behind a beat) when no options are current, so a
	// fresh recompute rings the nodes reachable from wherever the ship is. options is
	// voyage_travel_options' temp_allocator scratch, reclaimed by draw_scene's per-frame
	// free_all — no hand-free here.
	options := voyage.voyage_travel_options(state.voyage_map, state.current_node_id, state.visited)

	// Routes, under the marks; each undirected pair once. A route reads in one of three
	// states: sailable now (from the ship to a reachable node) is steel dashes; already
	// sailed (both ends visited) is solid chart ink; everything else is faint dashes —
	// charted, not yet a choice. Sailable-now wins over sailed so a backtrack edge reads as
	// the option it is (ADR-0009). Replaces the old flat grey lines.
	for p in state.voyage_map.nodes {
		for v in state.voyage_map.edges[p.id] {
			if v <= p.id {
				continue
			}
			a, b := state.positions[p.id], state.positions[v]
			switch {
			case edge_is_sailable(state.current_node_id, p.id, v, options):
				draw_chart_dashes(a, b, 2, COLOUR_STEEL)
			case state.visited[p.id] && state.visited[v]:
				rl.DrawLineEx(a, b, 2, CHART_INK)
			case:
				draw_chart_dashes(a, b, 1, rl.Fade(CHART_INK, 0.4))
			}
		}
	}

	// Marks, over the routes. The shape is node_mark's call, the colour node_appearance's.
	for p, i in state.voyage_map.nodes {
		pos := state.positions[i]
		color, label := node_appearance(p, state.visited[i])
		mark := node_mark(p, state.visited[i])
		switch mark {
		case .Home:
			draw_home_mark(pos, color)
		case .Island:
			draw_haven_island(pos)
		case .Dock:
			draw_dock_mark(pos, color)
		case .Diamond:
			rl.DrawPoly(pos, 4, NODE_RADIUS, 0, color)
		case .Buoy:
			draw_buoy_mark(pos)
		}
		// Labels only on the landmarks and Ports — the marks whose identity a hue can't
		// carry (Start and Haven aren't stages; a Port is a routable waypoint, ADR-0016). A
		// revealed encounter's category rides its diamond's hue (node_appearance still names
		// it, for the tests and any future legend), so a text label under it would only crowd
		// the chart where nodes sit close. Buoys stay anonymous (the Sim's hiding contract).
		#partial switch mark {
		case .Home, .Island, .Dock:
			tone := p.kind == .Haven ? COLOUR_CREAM : COLOUR_STEEL
			if state.visited[i] {
				tone = rl.Fade(tone, 0.6)
			}
			draw_map_label(label, pos, tone)
		}
	}

	// Reachability, over the marks: a steel ring on each reachable node, cyan with a caret
	// under the pointer, and a muted-maroon danger tick on one whose encounter is still
	// unrevealed (a buoy — it might fire; a revealed node already carries its category so
	// its risk reads on its own). The keyboard-era numbers and the red/green rings retire.
	for dest in options {
		pos := state.positions[dest]
		hovered := rl.CheckCollisionPointCircle(mouse, pos, NODE_RADIUS)
		rl.DrawCircleLinesV(pos, NODE_RADIUS + 4, hovered ? COLOUR_CYAN : COLOUR_STEEL)
		if node_mark(state.voyage_map.nodes[dest], state.visited[dest]) == .Buoy {
			draw_danger_tick(pos)
		}
		if hovered {
			draw_caret(rl.Vector2{pos.x - NODE_RADIUS - 12, pos.y}, COLOUR_CYAN)
		}
	}

	// The ship you stand on: the screen's one amber (style guide — the node you stand on
	// takes #F7A72B). Drawn last so it reads on top of its own mark and any ring. Replaces
	// the WHITE "you are here" stopgap.
	cur := state.positions[state.current_node_id]
	rl.DrawCircleLinesV(cur, NODE_RADIUS + 7, COLOUR_AMBER)
	rl.DrawCircleV(cur, NODE_RADIUS * 0.5, COLOUR_AMBER)
}

// edge_is_sailable reports whether the undirected edge (a, b) is a move the ship can make
// right now: one end is the node it stands on and the other is in the emitted reachable
// set. That is exactly the set travel_menu_loop accepts a click on, so the steel dashes
// mark precisely the edges a click will sail.
edge_is_sailable :: proc(current, a, b: voyage.Node_ID, options: []voyage.Node_ID) -> bool {
	if a == current {
		return option_contains(options, b)
	}
	if b == current {
		return option_contains(options, a)
	}
	return false
}

option_contains :: proc(options: []voyage.Node_ID, id: voyage.Node_ID) -> bool {
	for o in options {
		if o == id {
			return true
		}
	}
	return false
}

// draw_chart_dashes strokes a dashed line from a to b, the Chart Table's route language
// (chart_table.odin) generalised so the map can reuse it at three weights. Dashes are drawn
// rather than stippled because raylib carries no dash pattern; a zero-length edge still
// draws one dash rather than dividing by zero.
draw_chart_dashes :: proc(a, b: rl.Vector2, thickness: f32, color: rl.Color) {
	DASH :: f32(9)
	span := rl.Vector2Distance(a, b)
	steps := max(int(span / DASH), 1)
	for s in 0 ..< steps {
		if s % 2 == 1 {
			continue
		}
		t0 := f32(s) / f32(steps)
		t1 := f32(s + 1) / f32(steps)
		rl.DrawLineEx(linalg.lerp(a, b, t0), linalg.lerp(a, b, t1), thickness, color)
	}
}

// draw_map_label centres a Pixelify label under a node, at the body size and a tone the
// caller picks from the hierarchy. Retires draw_map's 12px DARKGRAY DrawText stopgap.
draw_map_label :: proc(text: string, pos: rl.Vector2, tone: rl.Color) {
	label := fmt.ctprintf("%s", text)
	size := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1)
	rl.DrawTextEx(
		ui_font_body,
		label,
		rl.Vector2{pos.x - size.x / 2, pos.y + NODE_RADIUS + 2},
		UI_BODY_SIZE,
		1,
		tone,
	)
}

// draw_home_mark draws the Start as a little house: a flat-topped base with a pitched roof,
// distinct from the dock's plain berth and the encounter diamonds. The roof triangle is
// wound base-left, base-right, apex so it survives raylib's clockwise cull (style guide).
draw_home_mark :: proc(pos: rl.Vector2, color: rl.Color) {
	R :: f32(NODE_RADIUS)
	rl.DrawRectangleRec(rl.Rectangle{pos.x - R * 0.6, pos.y - R * 0.15, R * 1.2, R * 0.9}, color)
	rl.DrawTriangle(
		rl.Vector2{pos.x - R * 0.8, pos.y - R * 0.15},
		rl.Vector2{pos.x + R * 0.8, pos.y - R * 0.15},
		rl.Vector2{pos.x, pos.y - R * 0.95},
		color,
	)
}

// draw_dock_mark draws a Port as a berth with a short pier reaching out — a place ships put
// in. Shop-blue, always visible (ADR-0016), and shaped unlike the category diamonds so a
// routable landfall never reads as just another encounter that happens to be a Shop.
draw_dock_mark :: proc(pos: rl.Vector2, color: rl.Color) {
	R :: f32(NODE_RADIUS)
	rl.DrawRectangleRec(rl.Rectangle{pos.x - R * 0.7, pos.y - R * 0.5, R * 1.4, R}, color)
	rl.DrawLineEx(rl.Vector2{pos.x + R * 0.7, pos.y}, rl.Vector2{pos.x + R * 1.3, pos.y}, 3, color)
}

// draw_buoy_mark draws an unrevealed encounter as a quiet recessive-blue buoy: a ring with
// a "?" inside. Recessive blue is "present but never read first", which is exactly what an
// unknown node is — a marker on the water, not a destination the eye is pulled to.
draw_buoy_mark :: proc(pos: rl.Vector2) {
	R :: f32(NODE_RADIUS)
	rl.DrawCircleLinesV(pos, R * 0.75, COLOUR_BLUE_RECESSIVE)
	q := fmt.ctprint("?")
	size := rl.MeasureTextEx(ui_font_body, q, UI_BODY_SIZE, 1)
	rl.DrawTextEx(ui_font_body, q, rl.Vector2{pos.x - size.x / 2, pos.y - size.y / 2}, UI_BODY_SIZE, 1, COLOUR_BLUE_RECESSIVE)
}

// draw_haven_island draws the win condition — the one landfall that matters — as a small
// faceted khaki island in the Chart Table's own language (chart_table.odin: overlapping
// lobes, three passes so a halo isn't cut by a neighbour's sand), ringed in cream. Keeping
// it the only island holds "the world must never outshine the chrome": no khaki mass
// competes across the whole map, just this one goal.
draw_haven_island :: proc(pos: rl.Vector2) {
	R :: f32(NODE_RADIUS)
	lobes := [3]Chart_Lobe {
		{pos + rl.Vector2{-R * 0.4, 0}, R * 0.9, 7, 15, 0.5},
		{pos + rl.Vector2{R * 0.5, R * 0.2}, R * 0.7, 6, 40, 0.45},
		{pos + rl.Vector2{0, -R * 0.4}, R * 0.6, 6, 5, 0.0},
	}
	for l in lobes {
		rl.DrawPoly(l.centre, l.sides, l.radius + 4, l.rot, COLOUR_SHALLOW)
	}
	for l in lobes {
		rl.DrawPoly(l.centre, l.sides, l.radius + 2, l.rot, CHART_LAND_SHADE)
		rl.DrawPoly(l.centre, l.sides, l.radius, l.rot, CHART_LAND)
	}
	for l in lobes {
		if l.green <= 0 {
			continue
		}
		rl.DrawPoly(l.centre, l.sides, l.radius * l.green, l.rot + 20, CHART_LAND_GREEN)
	}
	rl.DrawCircleLinesV(pos, R + 6, COLOUR_CREAM)
}

// draw_danger_tick draws a short muted-maroon stroke at a reachable buoy's shoulder — "this
// might fire". Muted maroon (the Fight stage_tint's hue, the one warm the guide admits
// beside amber) spends neither stock red nor the reserved amber on a risk cue.
draw_danger_tick :: proc(pos: rl.Vector2) {
	R :: f32(NODE_RADIUS)
	rl.DrawLineEx(
		rl.Vector2{pos.x + R * 0.55, pos.y - R * 1.15},
		rl.Vector2{pos.x + R * 1.15, pos.y - R * 0.55},
		3,
		stage_tint(.Fight),
	)
}

// draw_ship_panel renders a ship readout at origin. When gate_visibility is true
// (an opponent scouted before a Ship Battle), a concealed slot's fitting is hidden
// per ADR-0005; the player's own ship is always rendered ungated.
draw_ship_panel :: proc(s: ^ship.Ship, origin: rl.Vector2, title: string, gate_visibility: bool) {
	x := i32(origin.x)
	y := i32(origin.y)
	rl.DrawText(fmt.ctprintf("%s", title), x, y, 20, rl.DARKGRAY)
	// SPD is the *effective* Speed (ADR-0020): s.speed is only the base term; a ship's
	// real Speed reads its weight via ship_effective_speed. Printing the raw base would
	// overstate a heavily-laden ship.
	//
	// DARKGRAY, not BLACK: the panel sits on the COLOUR_DEEP canvas now, where black text is
	// invisible. This matches the title/Hold lines already in this proc — a legibility stopgap
	// on the unstyled panel; its real restyle (Pixelify, the tone hierarchy) is the Build
	// screen's (#302).
	rl.DrawText(
		fmt.ctprintf("Hull %d/%d   DUR %d   SPD %d", s.hull, s.max_hull, s.durability, ship.ship_effective_speed(s)),
		x,
		y + 26,
		16,
		rl.DARKGRAY,
	)
	// Hold and Weight, drawn own-ship only: a scouted opponent's wealth stays behind the
	// concealment gate (ADR-0005), the same reason its fittings read "???" below. "Hold X/Y"
	// is cargo against hull capacity; Weight is the term ship_effective_speed reads down
	// from Speed.
	if !gate_visibility {
		rl.DrawText(
			fmt.ctprintf(
				"Hold %d/%d   Weight %d",
				ship.ship_cargo(s^),
				ship.ship_cargo_capacity(s^),
				ship.ship_weight(s^),
			),
			x,
			y + 46,
			14,
			rl.DARKGRAY,
		)
	}

	for layout_slot, i in s.layout {
		row_y := y + 62 + i32(i) * 24
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
		// DARKGRAY, not BLACK, for the same reason as the Hull line above: legible on the
		// COLOUR_DEEP canvas until the Build screen restyle (#302) gives the panel real type.
		rl.DrawText(fmt.ctprintf("%s", label), x, row_y, 14, rl.DARKGRAY)
	}
}

// fitting_tags_label renders a fitting's tag families as a comma-separated list
// ("Crew, Weapon"), or "none" when it carries none. Used by the Item Offer and Refit
// screens.
//
// "none" rather than an em-dash: rl.DrawText's built-in font only carries codepoints
// 32-255, so "—" (U+2014) rasterises as "?"; "·" (U+00B7) is inside that Latin-1 range
// and draws fine. Anything above U+00FF needs a real font loaded first.
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
	return len(label) > 0 ? label : "none"
}

// fitting_effect_intent renders a one-line summary of what a fitting's effect does:
// the magnitude and what it feeds — a combat phase (its Category) or a ship stat —
// with synergy/conditional context spelled out ("+2 Muster per Weapon", "+8 Offense
// below 50% Hull"). Reads whichever of active/passive carries the effect; "no effect"
// for a cargo filler.
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
		case .Muster:
			target = "Muster"
		case .Brace:
			target = "Defense"
		case .Fire:
			target = "Offense"
		}
	case .Modify_Durability:
		target = "Durability"
	case .Modify_Speed:
		target = "Speed"
	case .Modify_Max_Hull:
		target = "Max Hull"
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
// Item Offer / Refit UI appends to the effect intent.
condition_intent :: proc(condition: ship.Condition) -> string {
	switch c in condition {
	case ship.Condition_Hull_Below:
		return fmt.tprintf("below %d%% Hull", c.percent)
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

// fitting_summary_lines renders the two detail lines shown under an item's name on
// the Item Offer and Refit screens: the first its size, phase (Category), and tag
// families; the second its effect intent.
fitting_summary_lines :: proc(f: ship.Fitting) -> (string, string) {
	spec := fmt.tprintf("%v · %v · %s", f.size, f.category, fitting_tags_label(f.tags))
	return spec, fitting_effect_intent(f)
}

// ENCOUNTER_STRIP is the band the stage sequence is drawn in while an encounter is
// walked. It overlaps the map's top band on purpose: it is the one region free in both
// of draw_scene_contents' layouts (map and battle), so the strip stays put whichever
// screen the captain is on.
ENCOUNTER_STRIP := rl.Rectangle{x = 20, y = 20, width = 620, height = 54}
STAGE_CHIP_W :: 112
STAGE_CHIP_H :: 22

// current_encounter is the encounter at the node the ship is standing at, as handed to
// presentation on Event_Arrived_At_Node. Its cursor is frozen at the moment of arrival,
// so it answers what the encounter consists of, never where the walk is now (that's
// Event_Stage_Entered's job).
current_encounter :: proc(state: ^Game_State) -> (voyage.Encounter, bool) {
	if len(state.voyage_map.nodes) == 0 {
		return {}, false
	}
	return state.voyage_map.nodes[state.current_node_id].encounter.?
}

// encounter_stage is the stage at `index` of the current encounter, baked content and
// all — how presentation reads the shape of what it is walking. The shape comes from the
// arrival copy, not the walk's events (which carry only the cursor): arrival is where an
// encounter's content is handed over (ADR-0009).
encounter_stage :: proc(state: ^Game_State, index: int) -> (voyage.Stage, bool) {
	encounter, has_encounter := current_encounter(state)
	if !has_encounter || index < 0 || index >= encounter.count {
		return nil, false
	}
	return encounter.stages[index], true
}

// encounter_stage_kind names the primitive at `index` of the current encounter, for the
// callers that only need to know what step it is rather than what it holds.
encounter_stage_kind :: proc(state: ^Game_State, index: int) -> (voyage.Stage_Kind, bool) {
	stage, known := encounter_stage(state, index)
	if !known {
		return nil, false
	}
	return voyage.voyage_stage_kind(stage), true
}

// draw_encounter_strip draws the encounter's whole stage sequence with the current one
// picked out — "Stage 2 of 3" over chips reading Battle | Market | Loot. Drawn on every
// screen an encounter can be on, so a multi-stage encounter reads as one sequence rather
// than unrelated popups. Nothing is drawn between encounters: state.stage_progress is nil
// unless the walk is on a stage.
//
// The stages *ahead* are shown, not just the position: arrival already reveals the node
// (ADR-0009/ADR-0016), so there is nothing left to withhold, and seeing Battle | Loot is
// what lets a captain weigh Break Off before paying for it.
draw_encounter_strip :: proc(state: ^Game_State) {
	progress, walking := state.stage_progress.?
	if !walking {
		return
	}

	rl.DrawRectangleRec(ENCOUNTER_STRIP, rl.Fade(rl.BLACK, 0.85))
	rl.DrawRectangleLinesEx(ENCOUNTER_STRIP, 1, rl.DARKGRAY)
	rl.DrawText(
		fmt.ctprintf("Stage %d of %d", progress.index + 1, progress.count),
		i32(ENCOUNTER_STRIP.x + 8),
		i32(ENCOUNTER_STRIP.y + 5),
		14,
		rl.RAYWHITE,
	)

	for i in 0 ..< progress.count {
		chip := rl.Rectangle {
			x      = ENCOUNTER_STRIP.x + 8 + f32(i) * (STAGE_CHIP_W + 6),
			y      = ENCOUNTER_STRIP.y + 24,
			width  = STAGE_CHIP_W,
			height = STAGE_CHIP_H,
		}
		draw_stage_chip(state, chip, i, progress.index)
	}
}

// draw_stage_chip draws one stage of the strip in one of three states: the stage under
// the cursor is filled in its own colour, one already walked is dimmed, one still ahead
// is an outline — done / here / to come.
draw_stage_chip :: proc(state: ^Game_State, chip: rl.Rectangle, index: int, cursor: int) {
	kind, known := encounter_stage_kind(state, index)
	if !known {
		return
	}
	tint := stage_tint(kind)
	label := stage_kind_label(kind)

	switch {
	case index == cursor:
		rl.DrawRectangleRec(chip, tint)
		rl.DrawRectangleLinesEx(chip, 2, rl.RAYWHITE)
		rl.DrawText(fmt.ctprintf("%s", label), i32(chip.x + 8), i32(chip.y + 4), 14, rl.BLACK)
	case index < cursor:
		rl.DrawRectangleRec(chip, rl.Fade(tint, 0.35))
		rl.DrawText(fmt.ctprintf("%s", label), i32(chip.x + 8), i32(chip.y + 4), 14, rl.Fade(rl.RAYWHITE, 0.6))
	case:
		rl.DrawRectangleLinesEx(chip, 1, rl.Fade(tint, 0.7))
		rl.DrawText(fmt.ctprintf("%s", label), i32(chip.x + 8), i32(chip.y + 4), 14, rl.Fade(rl.RAYWHITE, 0.6))
	}
}

// draw_scene_contents draws whichever screen is relevant (battle or map), the player's
// ship panel, and an optional overlay banner. It does not Begin/EndDrawing itself, so a
// caller that draws more on top (menu.odin's button lists) can share one Begin/End pair
// around it; draw_scene is the standalone wrapper for callers with nothing further.
draw_scene_contents :: proc(state: ^Game_State, overlay: string, mouse: rl.Vector2) {
	rl.ClearBackground(COLOUR_DEEP)

	if state.in_battle {
		if opponent, ok := state.sighted_opponent.?; ok {
			draw_ship_panel(&opponent, rl.Vector2{SHIP_PANEL_X, 20}, "Opponent", true)
		}
		draw_ship_panel(&state.player, rl.Vector2{SHIP_PANEL_X, 220}, "Your Ship", false)
	} else {
		draw_map(state, mouse)
		draw_ship_panel(&state.player, rl.Vector2{SHIP_PANEL_X, 20}, "Your Ship", false)
	}

	// Last of the left column, so it sits over the map rather than under it — drawn for
	// both layouts, since an encounter is walked across all of them.
	draw_encounter_strip(state)

	if len(overlay) > 0 {
		rl.DrawRectangle(0, WINDOW_HEIGHT - 60, WINDOW_WIDTH, 60, rl.Fade(rl.BLACK, 0.75))
		rl.DrawText(fmt.ctprintf("%s", overlay), 20, WINDOW_HEIGHT - 44, 20, rl.RAYWHITE)
	}

	draw_version_stamp()
}

// draw_version_stamp draws the build's VERSION in the top-right corner of every scene,
// right-aligned so a short "dev" and a full git SHA both sit flush to the edge. Guards on
// IsWindowReady() like the rest of the render layer (ADR-0003), so it's a no-op under
// `odin test`.
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

// draw_scene is draw_scene_contents wrapped in its own Begin/EndDrawing pair, for the
// callers with nothing further to draw on top: the travel screen and capture's non-option
// fallback. `mouse` is threaded to the map's hover; a caller with no live pointer (capture)
// passes an off-screen {-1, -1} so nothing rings.
draw_scene :: proc(state: ^Game_State, overlay: string, mouse: rl.Vector2) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	draw_scene_contents(state, overlay, mouse)
}

// draw_beat renders one frame of a playback beat: the stage or scene beneath, then the shared
// playback overlay laid over it (#304, encounter_frame.odin). The beat is the styled
// scrim-and-headline surface — it dims the stage but leaves it visible — replacing play_beat's
// old bottom bar. The scene draws with no bottom-bar overlay of its own (empty overlay arg);
// the headline rides the overlay instead. Its own Begin/EndDrawing pair, like draw_scene.
draw_beat :: proc(state: ^Game_State, headline: string) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	draw_scene_contents(state, "", rl.Vector2{-1, -1})
	draw_playback_overlay(headline)
}
