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
// metadata (issue #71): layer is the column (Start at the left, Haven at the
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

// stage_kind_label names a stage primitive for the captain (issue #139) — the one
// place a Stage_Kind becomes words, shared by the encounter strip, a halt's beat, and
// (via node_marker) the map. The enum's own spelling is the authoring vocabulary, not
// the player's: nobody boards a "Stage_Offer".
stage_kind_label :: proc(kind: run.Stage_Kind) -> string {
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
stage_tint :: proc(kind: run.Stage_Kind) -> rl.Color {
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

// node_marker is the map's colour and label for an encounter, given the stage it
// **opens** with (issues #71, #139). The opening stage is what the encounter is from
// the map's point of view — the same fact the Sim's mask reveals it on (ADR-0016) —
// so the marker and the mask are answering one question, not two that agree.
//
// **A Shop reads "Port" here, and only here.** Everywhere else — the encounter strip,
// a halt's beat — a Shop stage is a "Market" (stage_kind_label). The two disagree
// because they name different things: this names a *node*, and a node that opens on a
// Shop **is** a Port. That equivalence is ADR-0016's, and it is the whole of why the
// six visible markers on a map are exactly the six Ports — "opens on a Shop" ≡
// "reveals" ≡ "is a Port". A merchant's Shop is a stage *inside* an encounter that
// opens on something else, so it is a market met at sea and never wears this label.
//
// Like run_encounter_reveals, that rests on the authoring convention that only the
// Port bucket opens on a Shop (catalog.odin), not on a type-level fact — author one
// `[Shop, Fight]` and this label starts lying. ADR-0016 records that cost knowingly;
// the_only_encounters_a_captain_can_see_coming_are_ports is the test that makes
// breaking it loud.
node_marker :: proc(opening: run.Stage_Kind) -> (color: rl.Color, label: string) {
	label = stage_kind_label(opening)
	if opening == .Shop {
		label = "Port"
	}
	return rl.Fade(stage_tint(opening), 0.7), label
}

// node_appearance picks the marker colour and label for a node (issue #71).
// An Encounter whose content is still hidden is a generic zone-tinted marker with
// no label (the Sim's hiding contract); one that has been visited, or that reveals
// itself before arrival, shows its opening stage's colour and label. The Start and
// Haven landmarks are always fully labelled.
//
// **Revealing is asked of the stage list, never of the node kind** (ADR-0014,
// run_encounter_reveals). This used to read `case .Port` — a port was labelled
// because of what kind of node it was — and issue #137 deleted that value, so the
// question is now the same one the Sim's mask asks.
//
// An encounter reveals iff its **first** stage reveals (ADR-0016), and only the
// Port bucket opens on a Shop, so the only encounters revealed before arrival are
// the six Ports. A merchant vessel carries its Shop behind a stage and stays dark:
// a market you can route to is what a Port is *for*, and a merchant is a windfall.
//
// **The label now asks run_encounter_opening, closing #161's drift** — it used to ask
// run_encounter_current, i.e. the cursor, while reveal asked stage 0. #161 left that
// commented at both ends on the reading that a walked-out node's cursor sits past the
// end and falls through to a blank marker. It never did: the walk advances the *Sim's*
// private map, and this node is presentation's copy taken at arrival
// (Event_Arrived_At_Node fires before sim_walk_encounter), so its cursor is frozen at
// 0 for the rest of the run. The two rules could not drift because one of them was
// reading a constant. Asking for the opening stage says what was always meant, and the
// blank-marker case it was supposed to produce is written below instead.
//
// A **visited** node keeps its marker, faded: the walk is over and there is nothing to
// go back for (ADR-0014 resolves a node once), but where the captain has been — and
// what it was — is the map's memory of the route, which a blank dot throws away.
node_appearance :: proc(p: run.Node, visited: bool) -> (color: rl.Color, label: string) {
	switch p.kind {
	case .Start:
		return rl.SKYBLUE, "Start"
	case .Haven:
		return rl.GOLD, "Haven"
	case .Encounter:
		// A masked node arrives with no encounter at all, so there is nothing to
		// label; an unvisited one that does not reveal itself keeps its content back
		// until arrival. Both cases are the Sim's answer, rendered — never re-derived
		// here (ADR-0009): the stages of a hidden encounter are absent from the payload
		// presentation was handed, so there is nothing to leak.
		encounter, has_encounter := p.encounter.?
		if !has_encounter || (!visited && !run.run_encounter_reveals(encounter)) {
			return zone_tint(p.zone), ""
		}
		opening, has_opening := run.run_encounter_opening(encounter)
		if !has_opening {
			return rl.GRAY, ""
		}
		color, label = node_marker(run.run_stage_kind(opening))
		if visited {
			color = rl.Fade(color, 0.3)
		}
		return color, label
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
	// SPD is the *effective* Speed now (ADR-0020): s.speed is only the base term,
	// and a ship's real Speed reads its weight (ship_effective_speed). Showing the
	// raw base here would print 16 for a ship that actually sails at 4.
	rl.DrawText(
		fmt.ctprintf("HP %d/%d   DUR %d   SPD %d", s.hp, s.max_hp, s.durability, ship.ship_effective_speed(s)),
		x,
		y + 26,
		16,
		rl.BLACK,
	)
	// The weight economy, in the glossary's words (issue #201, ADR-0020). Weight is
	// the subtrahend the SPD above reads (ship_effective_speed subtracts weight/10), so
	// the captain can finally see the number that governs their Speed. "Hold X/Y" is the
	// purse rendered as the treasure in the cargo holds against the hull's capacity
	// (ship_treasure / ship_cargo_capacity) — no bare money number rides on a ship, and
	// "your hold is full" now means treasure has met capacity. It doubles as the ceiling
	// readout #157/#196 make load-bearing: a payout above capacity spills overboard, so
	// this is how a captain reads their headroom *before* walking into a Reward.
	//
	// Own ship only. A scouted opponent's wealth stays behind the concealment gate
	// (ADR-0005) — the same reason its concealed fittings read "???" below — so the
	// weight/hold line is drawn only when the panel is ungated.
	if !gate_visibility {
		rl.DrawText(
			fmt.ctprintf(
				"Hold %d/%d   Weight %d",
				ship.ship_treasure(s^),
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
// ("Crew, Weapon"), or "none" when it carries none. Used by the Item Offer and
// Refit screens (issue #96) to show which families an item belongs to.
//
// "none" rather than an em-dash: rl.DrawText's built-in font only carries
// codepoints 32-255, so a "—" (U+2014) rasterises as "?" (issue #168). A "·"
// (U+00B7) is inside that range and draws fine — the limit is Latin-1, not
// ASCII. Anything above U+00FF needs a real font loaded first.
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

// ENCOUNTER_STRIP is the band the stage sequence is drawn in while an encounter is
// being walked (issue #139). It sits over the top of the map area on purpose: it is the
// one region free in **both** of draw_scene_contents' layouts — the map screens and the
// battle screen, which leaves the whole left column empty — so the strip is in the same
// place whichever stage the captain is on, which is the point of it. Covering the map's
// top band costs nothing while an encounter is up, since routing is not the decision in
// front of you.
ENCOUNTER_STRIP := rl.Rectangle{x = 20, y = 20, width = 620, height = 54}
STAGE_CHIP_W :: 112
STAGE_CHIP_H :: 22

// current_encounter is the encounter at the node the ship is standing at, as
// presentation was handed it on Event_Arrived_At_Node (issue #139). Not a copy of the
// Sim's live walk — the cursor in here is frozen at the moment of arrival — so it
// answers "what does this encounter consist of" and never "where is the walk now",
// which is Event_Stage_Entered's job.
current_encounter :: proc(state: ^Game_State) -> (run.Encounter, bool) {
	if len(state.run_map.nodes) == 0 {
		return {}, false
	}
	return state.run_map.nodes[state.current_node_id].encounter.?
}

// encounter_stage is the stage at `index` of the current encounter, baked content and
// all — how presentation reads the *shape* of what it is walking (issue #139). The shape
// comes from the arrival copy rather than from the walk's events because arrival is
// already where an encounter's content is handed over (ADR-0009's contract is about what
// happens *before* you get there); the events carry only the cursor, which no copy can.
encounter_stage :: proc(state: ^Game_State, index: int) -> (run.Stage, bool) {
	encounter, has_encounter := current_encounter(state)
	if !has_encounter || index < 0 || index >= encounter.count {
		return nil, false
	}
	return encounter.stages[index], true
}

// encounter_stage_kind names the primitive at `index` of the current encounter, for the
// callers that only need to know what step it is rather than what it holds.
encounter_stage_kind :: proc(state: ^Game_State, index: int) -> (run.Stage_Kind, bool) {
	stage, known := encounter_stage(state, index)
	if !known {
		return nil, false
	}
	return run.run_stage_kind(stage), true
}

// draw_encounter_strip draws the encounter's whole stage sequence with the current one
// picked out — "Stage 2 of 3", over chips reading Battle | Market | Loot (issue #139).
// Drawn on every screen an encounter can be on, so a 3-stage Deep encounter reads as one
// sequence being walked rather than three unrelated popups. Nothing is drawn between
// encounters: state.stage_progress is nil unless the walk is on a stage.
//
// **The stages ahead are shown, not just the position**, and that is a decision the
// pacing question on #127 was carrying. Arrival reveals the node — the hiding contract
// is about what a captain can see *before* routing there (ADR-0009/ADR-0016) — so there
// is nothing left to withhold once the walk starts, and showing only "2 of 3" would
// withhold it anyway. It is what makes a halt a decision instead of a surprise: a
// captain looking at Battle | Loot can see what Leave Combat costs *before* paying for
// it, which is the same legibility the halt beat gives afterwards. Since #151 made Leave
// Combat fire at all (0/189 measured escapes, then 21/177), that is a live choice rather
// than a hypothetical one.
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

// draw_stage_chip draws one stage of the strip in one of three states (issue #139): the
// stage under the cursor is filled in its own colour, a stage already walked is dimmed,
// and a stage still ahead is an outline. The three read as done / here / to come, which
// is what turns a halt into a visible loss — the outlines are what the captain forfeits.
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

	// Last of the left column, so it sits over the map rather than under it — and drawn
	// for both layouts, since an encounter is walked across all of them (issue #139).
	draw_encounter_strip(state)

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
