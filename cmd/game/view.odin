package main

import "core:fmt"
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

// zone_tint is the ambient colour of a zone, used both for the background
// gradient band and for an unvisited encounter's generic marker.
//
// These sit on the style guide's depth ramp: hue falls and value rises as the water
// shallows (H222 -> H212 -> H200), which is the same ramp ui.odin's COLOUR_DEEP /
// COLOUR_MID / COLOUR_SHALLOW name. Before #294 they came from colour-palette.webp —
// a dusk mountain valley sitting at H~193 at every depth, i.e. not a sea — which is
// what put the world 31.8° of hue away from the chrome and made the two read as
// different games.
//
// They are the ramp's *hues*, not its values, and that is a limit rather than a
// choice. draw_scene clears this canvas to RAYWHITE and the band draws at 18% alpha,
// so a wash carries almost none of the underlying value: dropping the ramp's true
// stops (V0.15/0.19/0.25) in here composites all three zones to within 5/255 of each
// other — one indistinguishable grey. The values below are lifted until they survive
// that wash, which holds adjacent zones 9/255 apart, exactly what shipped before.
// The ramp's value axis lands only when the canvas stops being white, and that is the
// restyle effort's (#275, out of scope), not this one's.
zone_tint :: proc(zone: Maybe(voyage.Zone)) -> rl.Color {
	z, ok := zone.?
	if !ok {
		return rl.Color{102, 114, 128, 255}
	}
	switch z {
	case .Coastal:
		return rl.Color{103, 167, 199, 255}
	case .Open_Sea:
		return rl.Color{61, 104, 153, 255}
	case .Deep:
		return rl.Color{48, 66, 107, 255}
	}
	return rl.Color{102, 114, 128, 255}
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

// stage_tint is a stage primitive's colour, shared by the map marker and the
// encounter strip so a Battle node and a Battle chip read as the same thing.
stage_tint :: proc(kind: voyage.Stage_Kind) -> rl.Color {
	switch kind {
	case .Fight:
		return rl.MAROON
	case .Offer:
		return rl.LIME
	case .Trade:
		return rl.ORANGE
	case .Shop:
		return rl.SKYBLUE
	case .Reward:
		return rl.GOLD
	}
	return rl.GRAY
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
	return rl.Fade(stage_tint(opening), 0.7), label
}

// node_appearance picks the marker colour and label for a node. A hidden Encounter is
// a generic zone-tinted marker with no label (the Sim's hiding contract); a visited one,
// or one that reveals before arrival, shows its opening stage's colour and label, faded
// when visited so the map keeps a memory of the route. Start and Haven are always labelled.
//
// Revealing is asked of the stage list, never the node kind (ADR-0014,
// voyage_encounter_reveals) — the same question the Sim's mask asks.
node_appearance :: proc(p: voyage.Node, visited: bool) -> (color: rl.Color, label: string) {
	switch p.kind {
	case .Start:
		return rl.SKYBLUE, "Start"
	case .Haven:
		return rl.GOLD, "Haven"
	case .Encounter:
		// A masked node has no encounter to label; an unvisited one that doesn't reveal
		// keeps its content back until arrival. Both are the Sim's answer rendered, never
		// re-derived here (ADR-0009): a hidden encounter's stages aren't in presentation's
		// payload, so there's nothing to leak.
		encounter, has_encounter := p.encounter.?
		if !has_encounter || (!visited && !voyage.voyage_encounter_reveals(encounter)) {
			return zone_tint(p.zone), ""
		}
		opening, has_opening := voyage.voyage_encounter_opening(encounter)
		if !has_opening {
			return rl.GRAY, ""
		}
		color, label = node_marker(voyage.voyage_stage_kind(opening))
		if visited {
			color = rl.Fade(color, 0.3)
		}
		return color, label
	}
	return rl.GRAY, ""
}

// move_fires reports whether traveling to node p would trigger a fresh encounter:
// only an unvisited Encounter fires (never a landmark, never a revisit). Lets the UI
// colour-code offered moves without knowing the still-hidden kind.
move_fires :: proc(p: voyage.Node, visited: bool) -> bool {
	return p.kind == .Encounter && !visited
}

// draw_zone_background paints a faint per-zone tint band behind the graph as an
// ambient depth cue: each zone's tint spans the x-range of its columns.
draw_zone_background :: proc(state: ^Game_State) {
	for zone in voyage.Zone {
		lo, hi: f32 = 1e9, -1e9
		found := false
		for p, i in state.voyage_map.nodes {
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

// draw_map draws the whole graph at once: the zone background, every edge, every
// node's marker (unvisited encounters as generic zone dots), the current location,
// and a numbered highlight on each reachable node — red if stepping there fires a
// fresh encounter, green if safe.
draw_map :: proc(state: ^Game_State) {
	draw_zone_background(state)
	rl.DrawRectangleLinesEx(MAP_AREA, 2, rl.GRAY)

	// Edges (drawn under the nodes; each undirected pair once).
	for p in state.voyage_map.nodes {
		for v in state.voyage_map.edges[p.id] {
			if v <= p.id {
				continue
			}
			rl.DrawLineV(state.positions[p.id], state.positions[v], rl.Fade(rl.GRAY, 0.5))
		}
	}

	// Recompute the reachable set here rather than borrow the emitted state.travel_options:
	// the map is also drawn mid-encounter (behind the upgrade menu, the end-of-voyage beat)
	// when no travel options are current, so the fresh recompute rings the nodes reachable
	// from wherever the ship is. travel_menu_loop is what consumes the Sim's emitted options.
	// options is voyage_travel_options' temp_allocator scratch — reclaimed by the per-frame
	// free_all in draw_scene, no hand-free here.
	options := voyage.voyage_travel_options(state.voyage_map, state.current_node_id, state.visited)

	for p, i in state.voyage_map.nodes {
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
		ring := move_fires(state.voyage_map.nodes[dest], state.visited[dest]) ? rl.RED : rl.GREEN
		rl.DrawCircleLinesV(pos, NODE_RADIUS + 4, ring)
		rl.DrawText(fmt.ctprintf("%d", n + 1), i32(pos.x - 4), i32(pos.y - 7), 14, rl.WHITE)
	}

	// Current location outline, drawn last so it reads on top.
	cur := state.positions[state.current_node_id]
	rl.DrawCircleLinesV(cur, NODE_RADIUS + 7, rl.BLACK)
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
	rl.DrawText(
		fmt.ctprintf("Hull %d/%d   DUR %d   SPD %d", s.hull, s.max_hull, s.durability, ship.ship_effective_speed(s)),
		x,
		y + 26,
		16,
		rl.BLACK,
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
		rl.DrawText(fmt.ctprintf("%s", label), x, row_y, 14, rl.BLACK)
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

// draw_scene is draw_scene_contents wrapped in its own Begin/EndDrawing pair
// (used by the blocking event-playback beats in menu.odin, which have
// nothing further to draw on top).
draw_scene :: proc(state: ^Game_State, overlay: string) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	draw_scene_contents(state, overlay)
}
