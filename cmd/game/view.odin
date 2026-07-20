package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import voyage "../../core/voyage"
import ship "../../core/ship"
import rl "vendor:raylib"

MAP_AREA := rl.Rectangle{x = 20, y = 20, width = 620, height = 640}
SHIP_PANEL_X :: 670
NODE_RADIUS :: 12
// MAP_PAD_X / MAP_PAD_Y inset the node field from MAP_AREA, and differ because the layout drives
// the axes differently: `fx` runs the full 0..1 across layers, putting the Start and the Haven
// *exactly* on the field's left and right edge, while `fy` is (lane+1)/(w+1) and never reaches
// its extremes. So x alone has to clear the torn deckled rim baked into the page (spec §2) — up
// to ~60px of irregular edge — plus the overhang of what those two stops wear: the Start carries
// the 32px ship sprite, wider than a node, and both carry a centred label. Short of that they
// draw onto the rim and their labels onto the Build surface behind. y stays tight; spending the
// same room there would only squash the map.
MAP_PAD_X :: 85
MAP_PAD_Y :: 34

// The parchment Chart's ink palette (spec 0001 §8). The reskin drops the blue
// nautical-chart tones on this surface — steel rings, CHART_INK routes, the amber
// snap — for a cartographer's-hand ink language over the sourced parchment page. Two
// registers carry identity vs. recession: node identity and the road behind you ink
// in strong sepia; the fog ahead (unexplored ? buoys, charted-not-yet routes) recedes
// to faded-ink. Coral is the page's one warm accent, and it is spent only on the
// Haven X and the danger tick — nowhere else, and never amber.
INK_SEPIA :: rl.Color{126, 92, 58, 255} // Rock #7E5C3A — node identity, the road behind
INK_FADED :: rl.Color{156, 138, 99, 255} // Faded-ink #9C8A63 — the recessive register only
INK_SEA_DEEP :: rl.Color{23, 134, 188, 255} // #1786BC — reachable ring + hover, the interactive tone
INK_CORAL :: rl.Color{225, 85, 43, 255} // #E1552B — the one warm accent: Haven X + danger tick
INK_TEXT :: rl.Color{18, 51, 63, 255} // Ink #12333F — landmark labels on the warm page
INK_PARCHMENT :: rl.Color{235, 217, 166, 255} // Parchment #EBD9A6 — the page ground; the ship's chip

// Ship_Heading is the sailing sprite's eight baked directions, ordered to match the columns of
// the embedded strip (art.odin): N, NE, E, SE, S, SW, W, NW, left-to-right. Step 4 only rests
// the ship (SHIP_REST_HEADING); step 5 snaps this to the route tangent as the ship sails.
Ship_Heading :: enum {
	N,
	NE,
	E,
	SE,
	S,
	SW,
	W,
	NW,
}

// SHIP_REST_HEADING is the heading the ship holds while moored on the current node. East points
// it up-map toward the Haven (layers run Start-left → Haven-right, view.odin positions), so the
// resting vessel reads as poised to sail toward the treasure.
SHIP_REST_HEADING :: Ship_Heading.E

// SHIP_DRAW_SIZE is the sprite's on-page square in pixels — ~1.3× the node radius (spec §5), a
// little larger than a node so the vessel sits proud of the marks. A clean 2:1 POINT downscale
// from the 64px source frames.
SHIP_DRAW_SIZE :: 32

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

	usable_w := MAP_AREA.width - 2 * MAP_PAD_X
	usable_h := MAP_AREA.height - 2 * MAP_PAD_Y
	for p in voyage_map.nodes {
		fx := max_layer > 0 ? f32(p.layer) / f32(max_layer) : 0
		w := layer_counts[p.layer]
		fy := f32(p.lane + 1) / f32(w + 1)
		positions[p.id] = rl.Vector2{
			MAP_AREA.x + MAP_PAD_X + fx * usable_w,
			MAP_AREA.y + MAP_PAD_Y + fy * usable_h,
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

// ink_state fades an identity ink to a memory when the node has been visited (~0.3
// alpha): the map keeps where you've been without letting it compete with the road
// ahead (spec §3 states, §7 recession). An unvisited identity inks at full strength.
ink_state :: proc(ink: rl.Color, visited: bool) -> rl.Color {
	return visited ? rl.Fade(ink, 0.3) : ink
}

// node_appearance picks the ink colour and label for a node. Identity inks in strong
// sepia (INK_SEPIA), faded to a memory once visited; a masked or opening-less Encounter
// recedes to faded-ink with no label (the Sim's hiding contract). The category *hue* the
// blue chart used is gone — on the parchment identity is carried by the doodle's shape
// (node_mark), not its colour, so every mark inks in the one sepia register (spec §3).
//
// The shape each node is drawn as (home port, island, anchor, cutlasses, scroll, scales,
// chest, buoy) is node_mark's call, keyed on the same predicates; this proc owns only the
// ink and the label. It is still a place the reveal question is asked of the stage list,
// never the node kind (ADR-0014, voyage_encounter_reveals) — the same question the Sim's
// mask asks. The label keeps node_marker's Shop→"Port" rename; the colour it computes is
// discarded, since the parchment inks every identity the same.
node_appearance :: proc(p: voyage.Node, visited: bool) -> (color: rl.Color, label: string) {
	switch p.kind {
	case .Start:
		return ink_state(INK_SEPIA, visited), "Start"
	case .Haven:
		return ink_state(INK_SEPIA, visited), "Haven"
	case .Encounter:
		// A masked node has no encounter to label; an unvisited one that doesn't reveal
		// keeps its content back until arrival. Both are the Sim's answer rendered, never
		// re-derived here (ADR-0009): a hidden encounter's stages aren't in presentation's
		// payload, so there's nothing to leak.
		encounter, has_encounter := p.encounter.?
		if !has_encounter || (!visited && !voyage.voyage_encounter_reveals(encounter)) {
			return INK_FADED, ""
		}
		opening, has_opening := voyage.voyage_encounter_opening(encounter)
		if !has_opening {
			return INK_FADED, ""
		}
		_, label = node_marker(voyage.voyage_stage_kind(opening))
		return ink_state(INK_SEPIA, visited), label
	}
	return INK_FADED, ""
}

// Node_Mark is the cartographer's-hand doodle a node is drawn as on the parchment: the
// Start home port, the Haven treasure island (bearing the coral X), and one doodle per
// revealed encounter identity — anchor (a Port you can put in at), crossed cutlasses (a
// battle), scroll (an offer), scales (a trade), chest (a reward) — or the dotted ? buoy an
// unrevealed encounter keeps until reached. Shape *is* the identity here: the parchment
// inks every mark in the one sepia register (node_appearance), so unlike the blue chart's
// single "diamond + hue", the doodle alone tells a captain what a known stop holds without
// a legend (spec §3).
Node_Mark :: enum {
	Home,
	Island,
	Anchor,
	Cutlasses,
	Scroll,
	Scales,
	Chest,
	Buoy,
}

// node_mark classifies a node into its doodle. It re-asks the same reveal predicate
// node_appearance does (voyage_encounter_reveals) rather than share a computed value: the
// two answer different questions off one fact — what shape, what ink — and keeping them
// side by side is the file's own idiom (move_fires re-derived reveal the same way). A
// masked or opening-less encounter falls through to a buoy, the same "nothing to show yet";
// a revealed one splits by its opening Stage_Kind into the four encounter doodles, with a
// Shop opening reading as the Port's anchor (ADR-0016, only a Shop opening reveals).
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
		switch voyage.voyage_stage_kind(opening) {
		case .Shop:
			return .Anchor
		case .Fight:
			return .Cutlasses
		case .Offer:
			return .Scroll
		case .Trade:
			return .Scales
		case .Reward:
			return .Chest
		}
		return .Buoy
	}
	return .Buoy
}

// draw_map_page blits the sourced parchment sheet (art.odin) to fill MAP_AREA — the warm
// aged page and its rough torn deckled rim baked into one texture (spec 0001 §2). The
// parchment is the Chart ground and its torn edge is the frame, so there is no border box:
// the sheet is a torn object on a transparent canvas, and the surround shows the darkened
// Build behind the page rather than a second frame. POINT-scaled at native resolution
// (art.odin sets the filter). The live layer (routes, marks, rings, ship) draws procedurally
// over it.
draw_map_page :: proc() {
	src := rl.Rectangle{0, 0, f32(parchment_page_tex.width), f32(parchment_page_tex.height)}
	rl.DrawTexturePro(parchment_page_tex, src, MAP_AREA, rl.Vector2{0, 0}, 0, rl.WHITE)
}

// draw_map draws the whole parchment Chart at once: the sourced parchment page, every route
// in one of three sepia states on a hand-wavy curve, every node as its cartographer's-hand
// doodle, the Sea-deep reachability rings with a coral danger tick on an unrevealed
// reachable node, the hover caret, and the ink placeholder for the node the ship stands on.
// Composition only — `mouse` carries the hover so the loop can poll while capture passes a
// no-mouse sentinel and photographs the chart at rest (#277).
draw_map :: proc(state: ^Game_State, mouse: rl.Vector2) {
	draw_map_page()

	// The reachable set is recomputed here rather than borrowed from state.travel_options:
	// the map is also drawn mid-encounter (behind a beat) when no options are current, so a
	// fresh recompute rings the nodes reachable from wherever the ship is. options is
	// voyage_travel_options' temp_allocator scratch, reclaimed by draw_scene's per-frame
	// free_all — no hand-free here.
	options := voyage.voyage_travel_options(state.voyage_map, state.current_node_id, state.visited)

	// A sail in flight redraws two things: the leg under way fills its wake in behind the sprite,
	// and the sprite rides that leg instead of resting. current_node_id is still the origin
	// throughout — the Sim only learns of the move when home_loop returns on arrival.
	sail_dest, sailing := state.sail_pending.?
	sail_eased := sail_ease(state.sail_progress)

	// The juice's clock (spec §6). Wall time, not the sail's progress: the hull keeps rocking
	// while moored and an arrival's bloom outlives the sail that caused it, so neither can be
	// driven off a tween that stops at 1.
	now := rl.GetTime()

	// Routes, under the marks; each undirected pair once. A route reads in one of three sepia
	// states — sailable now (from the ship to a reachable node) is bold dashes; already sailed
	// (both ends visited) is solid ink, the wake left behind; everything else is faint
	// faded-ink dots, charted but not yet a choice. That weighting *is* the visited recession
	// (spec §7): the road behind inks strong, the road ahead recedes to faded-ink. Sailable-now
	// wins over sailed so a backtrack edge reads as the option it is (ADR-0009). Every route
	// rides a gently hand-wavy curve, not a ruled line (spec §3).
	for p in state.voyage_map.nodes {
		for v in state.voyage_map.edges[p.id] {
			if v <= p.id {
				continue
			}
			a, b := state.positions[p.id], state.positions[v]
			switch {
			case sailing && edge_is_sail_leg(p.id, v, state.current_node_id, sail_dest):
				forward := state.current_node_id < sail_dest
				draw_sail_leg(a, b, sail_curve_t(sail_eased, forward), forward)
			case edge_is_sailable(state.current_node_id, p.id, v, options):
				// While a leg is under way the other legal dashes recede to charted dots, so the
				// eye stays on the route being sailed rather than on choices already spent.
				draw_route(a, b, sailing ? .Charted : .Sailable)
			case state.visited[p.id] && state.visited[v]:
				draw_route(a, b, .Sailed)
			case:
				draw_route(a, b, .Charted)
			}
		}
	}

	// Marks, over the routes. The doodle is node_mark's call, the ink node_appearance's.
	for p, i in state.voyage_map.nodes {
		pos := state.positions[i]
		color, label := node_appearance(p, state.visited[i])
		mark := node_mark(p, state.visited[i])
		switch mark {
		case .Home:
			draw_home_mark(pos, color)
		case .Island:
			draw_haven_island(pos, color)
		case .Anchor:
			draw_anchor_mark(pos, color)
		case .Cutlasses:
			draw_cutlasses_mark(pos, color)
		case .Scroll:
			draw_scroll_mark(pos, color)
		case .Scales:
			draw_scales_mark(pos, color)
		case .Chest:
			draw_chest_mark(pos, color)
		case .Buoy:
			draw_buoy_mark(pos)
		}
		// Labels only on the landmarks and the Port — the marks a captain orients by (Start
		// and Haven aren't stages; a Port is a routable waypoint, ADR-0016). The four encounter
		// doodles carry their identity in shape, so a text label under them would only crowd the
		// chart where nodes sit close. Buoys stay anonymous (the Sim's hiding contract).
		#partial switch mark {
		case .Home, .Island, .Anchor:
			tone := state.visited[i] ? rl.Fade(INK_TEXT, 0.6) : INK_TEXT
			draw_map_label(label, pos, tone)
		}
	}

	// Reachability, over the marks: a Sea-deep dashed ring on each reachable node — the
	// parchment's interactive tone (spec §3) — with a caret under the pointer, and a coral
	// danger tick on one whose encounter is still unrevealed (a buoy — it might fire; a
	// revealed node already carries its identity so its risk reads on its own).
	//
	// A leg under way dims them, the same recession the legal dashes take above (spec §5.5).
	// current_node_id does not move until the Sim is told, so for the whole sail and its arrival
	// hold the destination is still in `options` — undimmed, the map would ring the node the hull
	// is standing on as somewhere to sail to. The caret is the exception and goes out entirely:
	// it tracks the pointer rather than marking state, and home_loop is swallowing clicks.
	for dest in options {
		pos := state.positions[dest]
		hovered := !sailing && rl.CheckCollisionPointCircle(mouse, pos, NODE_RADIUS)
		draw_dashed_ring(pos, NODE_RADIUS + 5, sail_dimmed(INK_SEA_DEEP, sailing))
		if node_mark(state.voyage_map.nodes[dest], state.visited[dest]) == .Buoy {
			draw_danger_tick(pos, sail_dimmed(INK_CORAL, sailing))
		}
		if hovered {
			draw_caret(rl.Vector2{pos.x - NODE_RADIUS - 12, pos.y}, INK_SEA_DEEP)
		}
	}

	// The arrival ripple, over the marks: the last landing's ink still spreading into the paper
	// (spec §6). It expires on its own age, so a stale bloom from an arrival ago simply draws
	// nothing and no one has to clear it.
	if bloom, landed := state.arrival_bloom.?; landed {
		draw_ink_bloom(state.positions[bloom.node], now, bloom.started)
	}

	// The ship is the one raster on the inked page (spec §5) and the current-node marker: moored
	// at its default heading on the node it stands on, or out on the leg it is sailing, facing the
	// curve's tangent. Either way it rocks in the water (spec §6) — bob and heel over the baked
	// frame, the heading snap untouched. No amber ring+dot, no procedural glyph. A landed sail
	// still holding while its ink sets rocks at its moored amplitude, not its working one: the
	// ship has arrived, and only the Sim hasn't heard yet.
	under_way := sailing && state.sail_progress < 1
	bob, heel := ship_rock(now, under_way)
	if sailing {
		pos, heading, lean := sail_ship_pose(
			state.positions,
			state.current_node_id,
			sail_dest,
			sail_eased,
		)
		// Spume under the hull, over the wake it is thrown across, so the flecks read as water
		// off the bow rather than marks on the chart.
		draw_spume(state.positions, state.current_node_id, sail_dest, state.sail_progress)
		draw_ship_sprite(pos, heading, bob, heel + lean)
	} else {
		draw_ship_sprite(state.positions[state.current_node_id], SHIP_REST_HEADING, bob, heel)
	}
}

// draw_ship_sprite blits the ship at pos facing heading, riding `bob` pixels of swell and heeled
// `heel` degrees. A faint parchment chip is laid down first so the routes and marks crossing the
// current node don't muddy under the hull (spec §5) — the chip stays put while the hull moves,
// since the water under a ship doesn't bob with it. The heading's column of the embedded strip is
// then drawn centred and scaled to SHIP_DRAW_SIZE; frame size is read from the sheet height so the
// layout stays a single source of truth with the strip art.odin loads, and the sprite carries its
// own transparency so it composites over the chip. Rotation turns about the sprite's own centre,
// which is why the destination rect is placed *at* pos and the origin carries the half-size — a
// top-left rect would swing the hull around the node instead of rolling it in place.
draw_ship_sprite :: proc(pos: rl.Vector2, heading: Ship_Heading, bob, heel: f32) {
	rl.DrawCircleV(pos, f32(NODE_RADIUS) + 3, rl.Fade(INK_PARCHMENT, 0.62))

	frame := f32(ship_sprite_tex.height)
	src := rl.Rectangle{f32(int(heading)) * frame, 0, frame, frame}
	d := f32(SHIP_DRAW_SIZE)
	dst := rl.Rectangle{pos.x, pos.y + bob, d, d}
	rl.DrawTexturePro(ship_sprite_tex, src, dst, rl.Vector2{d / 2, d / 2}, heel, rl.WHITE)
}

// draw_spume throws the sail's two kinds of transient water (spec §6): pale-parchment foam flecks
// flung off the bow and out to the side, and faded-ink sepia stipple settling back into the wake.
// Both fade inside half a leg and neither leaves a mark — the solid sepia wake draw_sail_leg fills
// in is the only lasting line. Each fleck is placed where the ship actually was when it was
// thrown (its spawn progress run back through the same ease and the same drawn curve), so the
// spray trails the hull down the route instead of hanging in a line.
draw_spume :: proc(positions: []rl.Vector2, from, to: voyage.Node_ID, progress: f32) {
	a, c, b, forward := sail_leg_curve(positions, from, to)
	for i in 0 ..< SPUME_FLECKS {
		spawn, age, alive := spume_fleck(i, progress)
		if !alive {
			continue
		}

		t := sail_curve_t(sail_ease(spawn), forward)
		at := bezier_quad(a, c, b, t)
		tangent := bezier_tangent(a, c, b, t)
		if !forward {
			tangent = -tangent
		}
		// Heading and its perpendicular: foam is thrown sideways off alternating bows, stipple
		// falls away astern. The wobble is the doodles' own hand-jitter, seeded on the fleck so
		// the spray is scattered but never shimmers between frames.
		dir := linalg.normalize0(tangent)
		side := rl.Vector2{-dir.y, dir.x} * (i % 2 == 0 ? 1 : -1)
		wobble := ink_wobble(f32(i) * 3.7, 1.5)

		// Foam off the bow, thrown clear of the hull and out to alternating sides. Parchment
		// cored but rimmed in Cliff, because a pale-parchment fleck *on the parchment page* is
		// the page: the rim is what makes it read as water rather than as nothing. Both are
		// roster colours (spec §8) — the fleck spends no new ink on the chart.
		foam := at + dir * 3 + side * (SPUME_CLEARANCE + SPUME_DRIFT * age) + rl.Vector2{wobble, wobble}
		fade := 1 - age
		r := SPUME_FOAM_R - SPUME_FOAM_SHRINK * age
		rl.DrawCircleV(foam, r, rl.Fade(INK_PARCHMENT, 0.95 * fade))
		rl.DrawCircleLinesV(foam, r, rl.Fade(SPUME_FOAM_RIM, 0.8 * fade))

		// Sepia stipple falling astern and settling into the wake, in the recessive register so
		// it reads as ink drying rather than as a second line drawn on the chart.
		stipple := at - dir * (SPUME_CLEARANCE + SPUME_DRIFT * 0.7 * age) + side * (3 + wobble)
		rl.DrawCircleV(stipple, 2, rl.Fade(INK_FADED, 0.7 * fade))
	}
}

// SPUME_CLEARANCE is how far a fleck starts from the hull, and SPUME_DRIFT how much further it
// travels before it fades. Both are sized against the *sprite*, not the leg: the zero-crossing
// layout sits connected nodes right next to each other (spec §4), so a leg is only a couple of
// ship-lengths and spume thrown any tighter than the 32px sprite and its chip is simply drawn
// underneath them. Measured on the running game, which is where this dial belongs (spec §6).
SPUME_CLEARANCE :: f32(9)
SPUME_DRIFT :: f32(14)

// SPUME_FOAM_RIM is the foam fleck's edge: Cliff, the page's own mid mottle tone, dark enough to
// outline a parchment-coloured fleck against clean parchment and light enough not to read as ink.
SPUME_FOAM_RIM :: rl.Color{185, 138, 80, 255} // Cliff #B98A50

// SPUME_FOAM_R is a fresh fleck's radius and SPUME_FOAM_SHRINK how much of it drift takes back.
// The radius has to sit above the page's own mottle speckle: SPUME_FOAM_RIM is Cliff, which is
// also a mottle tone, so foam drawn at the speckle's scale reads as more page rather than as
// water however many flecks are thrown. Spec §6 leaves the density to the build.
SPUME_FOAM_R :: f32(4.5)
SPUME_FOAM_SHRINK :: f32(1.5)

// draw_ink_bloom ripples the arrival flourish out of a node (spec §6): two thin sepia rings
// widening and thinning together, the outer one leading — "the ink just set". Strong sepia
// outside over faded-ink within, the page's own two registers, so the bloom reads as the chart's
// ink rather than a new colour. Silently draws nothing once the ripple has expired.
draw_ink_bloom :: proc(centre: rl.Vector2, now, started: f64) {
	spread, alpha, alive := ink_bloom_phase(now, started)
	if !alive {
		return
	}
	outer := f32(NODE_RADIUS) + spread * INK_BLOOM_REACH
	rl.DrawCircleLinesV(centre, outer, rl.Fade(INK_SEPIA, alpha))
	rl.DrawCircleLinesV(centre, outer * 0.62, rl.Fade(INK_FADED, alpha * 0.7))
}

// edge_is_sailable reports whether the undirected edge (a, b) is a move the ship can make
// right now: one end is the node it stands on and the other is in the emitted reachable
// set. That is exactly the set home_loop's raised chart accepts a click on, so the steel
// dashes mark precisely the edges a click will sail.
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

// ink_wobble returns a small deterministic offset in [-amp, amp], hashed off `seed`. The
// cartographer's-hand doodles and routes are jittered so they read drawn-by-hand rather than
// CAD-ruled, but the jitter must be *stable* frame-to-frame — a per-frame random would make
// the whole map shimmer. Seeding on a mark's position (not a call counter) fixes each stroke
// in place while giving neighbours different wobble.
ink_wobble :: proc(seed, amp: f32) -> f32 {
	h := math.sin(seed * 12.9898) * 43758.5453
	return (h - math.floor(h) - 0.5) * 2 * amp
}

// ink_line strokes a hand-drawn line: each end nudged by a deterministic wobble seeded on
// its own coordinates, so the stroke reads inked-by-hand yet never shimmers. The doodle set
// builds on this so every mark shares the same wobble register.
ink_line :: proc(a, b: rl.Vector2, thickness: f32, color: rl.Color) {
	wa := rl.Vector2{ink_wobble(a.x + a.y * 3, 0.7), ink_wobble(a.x * 3 - a.y, 0.7)}
	wb := rl.Vector2{ink_wobble(b.x - b.y * 3, 0.7), ink_wobble(b.x * 3 + b.y, 0.7)}
	rl.DrawLineEx(a + wa, b + wb, thickness, color)
}

// bezier_quad evaluates the quadratic bezier a→c→b at t via de Casteljau (two lerps), the
// curve every route and the sailing ship (step 5) ride so the map reads hand-wavy.
bezier_quad :: proc(a, c, b: rl.Vector2, t: f32) -> rl.Vector2 {
	return linalg.lerp(linalg.lerp(a, c, t), linalg.lerp(c, b, t), t)
}

// route_control is the bezier control point for the edge a→b: the midpoint bowed
// perpendicular by a small deterministic amount, so a route curves by hand instead of ruling
// straight (spec §3). Deterministic on the endpoints so the bow never shimmers, and shared
// with step 5 so the ship sails the very curve the route is drawn on.
route_control :: proc(a, b: rl.Vector2) -> rl.Vector2 {
	mid := linalg.lerp(a, b, f32(0.5))
	perp := linalg.normalize0(rl.Vector2{-(b.y - a.y), b.x - a.x})
	return mid + perp * ink_wobble(a.x + b.x + a.y + b.y, 7)
}

// Route_Style is a route's state as drawn: Sailable now (bold sepia dashes from the ship),
// Sailed already (solid sepia wake), or Charted-not-yet (faint faded-ink dots). The weight
// carries the state so a captain reads each leg without a legend (spec §3), and the strong-vs-
// faded split is the visited recession (spec §7).
Route_Style :: enum {
	Sailable,
	Sailed,
	Charted,
}

// The faded register's two weights, and the invariant between them: a ? buoy must out-ink the
// charted route it sits on. §3 reserves faded-ink for both, so weight is the only thing left to
// separate a stop from the trail running through it — keep DOT_R_BUOY above DOT_R_CHARTED.
// CHARTED_DOT_EVERY is how many curve samples pass between dots; larger is sparser.
DOT_R_BUOY :: f32(1.6)
DOT_R_CHARTED :: f32(1.1)
CHARTED_DOT_EVERY :: 3

// draw_route strokes an edge as its state's sepia trail on the hand-wavy bezier. Sampled into
// short segments so the curve reads; Sailable skips alternate segments for a dash, Charted
// drops sparse faded-ink dots, Sailed inks solid — the wake left behind.
draw_route :: proc(a, b: rl.Vector2, style: Route_Style) {
	SEGS :: 18
	c := route_control(a, b)
	prev := a
	for s in 1 ..= SEGS {
		pt := bezier_quad(a, c, b, f32(s) / f32(SEGS))
		switch style {
		case .Sailed:
			rl.DrawLineEx(prev, pt, 3, INK_SEPIA)
		case .Sailable:
			if s % 2 == 1 {
				rl.DrawLineEx(prev, pt, 3, INK_SEPIA)
			}
		case .Charted:
			// The deepest point of the §7 recession, and the map draws far more route than
			// node — so this dot stays under DOT_R_BUOY. A charted stipple that outweighs the
			// ? buoys sitting in it inverts §3's "identity reads before recession".
			if s % CHARTED_DOT_EVERY == 0 {
				rl.DrawCircleV(pt, DOT_R_CHARTED, INK_FADED)
			}
		}
		prev = pt
	}
}

// SAIL_DIM is how far the reachable marks recede while a leg is under way (spec §5.5) — faint
// enough to stop reading as an offer, present enough that the map doesn't reshuffle mid-sail.
SAIL_DIM :: f32(0.25)

// sail_dimmed is a reachable mark's ink for the frame: full strength when the captain can act,
// SAIL_DIM once a leg is under way and the choice is no longer theirs to make.
sail_dimmed :: proc(ink: rl.Color, sailing: bool) -> rl.Color {
	return sailing ? rl.Fade(ink, SAIL_DIM) : ink
}

// draw_dashed_ring strokes a dashed circle — the reachable node's Sea-deep interactive ring
// (spec §3), drawn as arcs because raylib carries no dash pattern for circles.
draw_dashed_ring :: proc(centre: rl.Vector2, radius: f32, color: rl.Color) {
	SEGS :: 20
	for i in 0 ..< SEGS {
		if i % 2 == 1 {
			continue
		}
		a0 := f32(i) / f32(SEGS) * 2 * math.PI
		a1 := f32(i + 1) / f32(SEGS) * 2 * math.PI
		p0 := centre + rl.Vector2{math.cos(a0), math.sin(a0)} * radius
		p1 := centre + rl.Vector2{math.cos(a1), math.sin(a1)} * radius
		rl.DrawLineEx(p0, p1, 2, color)
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

// The doodle set — one cartographer's-hand mark per node identity (spec §3, Idiom A). Every
// doodle inks in the one sepia register `color` the caller passes (strong for identity, faded
// to a memory when visited), built from ink_line so the strokes share the hand-wobble. Only
// the Haven's X and the danger tick ever spend coral; no doodle here does.

// draw_home_mark draws the Start as a little home port — a hut with a pitched roof on a short
// pier, a pennant flying from the ridge. Where you weigh anchor at the run's start.
draw_home_mark :: proc(pos: rl.Vector2, color: rl.Color) {
	R :: f32(NODE_RADIUS)
	// Hut: three walls and a pitched roof, drawn as strokes so it reads inked, not filled.
	bl := rl.Vector2{pos.x - R * 0.5, pos.y + R * 0.55}
	br := rl.Vector2{pos.x + R * 0.5, pos.y + R * 0.55}
	tl := rl.Vector2{pos.x - R * 0.5, pos.y - R * 0.1}
	tr := rl.Vector2{pos.x + R * 0.5, pos.y - R * 0.1}
	apex := rl.Vector2{pos.x, pos.y - R * 0.75}
	ink_line(bl, br, 2, color)
	ink_line(bl, tl, 2, color)
	ink_line(br, tr, 2, color)
	ink_line(tl, apex, 2, color)
	ink_line(tr, apex, 2, color)
	// Pier: a run of decking to the right with two short posts into the water.
	pier_l := rl.Vector2{pos.x + R * 0.5, pos.y + R * 0.55}
	pier_r := rl.Vector2{pos.x + R * 1.35, pos.y + R * 0.55}
	ink_line(pier_l, pier_r, 2, color)
	ink_line(rl.Vector2{pos.x + R * 0.8, pos.y + R * 0.55}, rl.Vector2{pos.x + R * 0.8, pos.y + R * 1.0}, 2, color)
	ink_line(rl.Vector2{pos.x + R * 1.2, pos.y + R * 0.55}, rl.Vector2{pos.x + R * 1.2, pos.y + R * 1.0}, 2, color)
	// Pennant: a pole from the ridge with a little flag.
	pole_top := rl.Vector2{apex.x, apex.y - R * 0.6}
	ink_line(apex, pole_top, 2, color)
	rl.DrawTriangle(
		pole_top,
		rl.Vector2{pole_top.x + R * 0.5, pole_top.y + R * 0.15},
		rl.Vector2{pole_top.x, pole_top.y + R * 0.35},
		color,
	)
}

// draw_anchor_mark draws a revealed Port (an Encounter opening on a Shop, ADR-0016) as an
// anchor — a landfall you can put in at. Ring at the crown, a stock across the shank, two
// curved flukes at the foot.
draw_anchor_mark :: proc(pos: rl.Vector2, color: rl.Color) {
	R :: f32(NODE_RADIUS)
	crown := rl.Vector2{pos.x, pos.y - R * 0.7}
	foot := rl.Vector2{pos.x, pos.y + R * 0.7}
	rl.DrawCircleLinesV(rl.Vector2{pos.x, pos.y - R * 0.55}, R * 0.22, color)
	ink_line(rl.Vector2{crown.x, crown.y + R * 0.3}, foot, 2, color) // shank
	ink_line(rl.Vector2{pos.x - R * 0.45, pos.y - R * 0.15}, rl.Vector2{pos.x + R * 0.45, pos.y - R * 0.15}, 2, color) // stock
	// Flukes: a short arm each side sweeping up from the foot.
	ink_line(foot, rl.Vector2{pos.x - R * 0.6, pos.y + R * 0.25}, 2, color)
	ink_line(rl.Vector2{pos.x - R * 0.6, pos.y + R * 0.25}, rl.Vector2{pos.x - R * 0.75, pos.y - R * 0.05}, 2, color)
	ink_line(foot, rl.Vector2{pos.x + R * 0.6, pos.y + R * 0.25}, 2, color)
	ink_line(rl.Vector2{pos.x + R * 0.6, pos.y + R * 0.25}, rl.Vector2{pos.x + R * 0.75, pos.y - R * 0.05}, 2, color)
}

// draw_cutlasses_mark draws a revealed Fight as two crossed cutlasses — a battle.
draw_cutlasses_mark :: proc(pos: rl.Vector2, color: rl.Color) {
	R :: f32(NODE_RADIUS)
	// Two blades crossing at the centre; a short guard tick across each hilt.
	ink_line(rl.Vector2{pos.x - R * 0.75, pos.y + R * 0.75}, rl.Vector2{pos.x + R * 0.75, pos.y - R * 0.75}, 2, color)
	ink_line(rl.Vector2{pos.x + R * 0.75, pos.y + R * 0.75}, rl.Vector2{pos.x - R * 0.75, pos.y - R * 0.75}, 2, color)
	ink_line(rl.Vector2{pos.x - R * 0.85, pos.y + R * 0.45}, rl.Vector2{pos.x - R * 0.45, pos.y + R * 0.85}, 2, color)
	ink_line(rl.Vector2{pos.x + R * 0.85, pos.y + R * 0.45}, rl.Vector2{pos.x + R * 0.45, pos.y + R * 0.85}, 2, color)
}

// draw_scroll_mark draws a revealed Offer as a scroll — a take-it-or-leave-it note.
draw_scroll_mark :: proc(pos: rl.Vector2, color: rl.Color) {
	R :: f32(NODE_RADIUS)
	top := pos.y - R * 0.7
	bot := pos.y + R * 0.7
	left := pos.x - R * 0.5
	right := pos.x + R * 0.5
	// Body: two sides, and a rolled curl top and bottom.
	ink_line(rl.Vector2{left, top}, rl.Vector2{left, bot}, 2, color)
	ink_line(rl.Vector2{right, top}, rl.Vector2{right, bot}, 2, color)
	rl.DrawCircleLinesV(rl.Vector2{pos.x, top}, R * 0.5, color)
	rl.DrawCircleLinesV(rl.Vector2{pos.x, bot}, R * 0.5, color)
	// A couple of writing lines across it.
	ink_line(rl.Vector2{left + R * 0.15, pos.y - R * 0.15}, rl.Vector2{right - R * 0.15, pos.y - R * 0.15}, 1, color)
	ink_line(rl.Vector2{left + R * 0.15, pos.y + R * 0.2}, rl.Vector2{right - R * 0.15, pos.y + R * 0.2}, 1, color)
}

// draw_scales_mark draws a revealed Trade as a pair of balance scales — a bargain.
draw_scales_mark :: proc(pos: rl.Vector2, color: rl.Color) {
	R :: f32(NODE_RADIUS)
	top := rl.Vector2{pos.x, pos.y - R * 0.75}
	beam_l := rl.Vector2{pos.x - R * 0.7, pos.y - R * 0.4}
	beam_r := rl.Vector2{pos.x + R * 0.7, pos.y - R * 0.4}
	ink_line(top, rl.Vector2{pos.x, pos.y + R * 0.75}, 2, color) // post
	ink_line(beam_l, beam_r, 2, color) // beam
	// Pans: a shallow V hanging from each beam end.
	ink_line(beam_l, rl.Vector2{beam_l.x - R * 0.35, pos.y + R * 0.15}, 1, color)
	ink_line(beam_l, rl.Vector2{beam_l.x + R * 0.35, pos.y + R * 0.15}, 1, color)
	ink_line(rl.Vector2{beam_l.x - R * 0.35, pos.y + R * 0.15}, rl.Vector2{beam_l.x + R * 0.35, pos.y + R * 0.15}, 1, color)
	ink_line(beam_r, rl.Vector2{beam_r.x - R * 0.35, pos.y + R * 0.15}, 1, color)
	ink_line(beam_r, rl.Vector2{beam_r.x + R * 0.35, pos.y + R * 0.15}, 1, color)
	ink_line(rl.Vector2{beam_r.x - R * 0.35, pos.y + R * 0.15}, rl.Vector2{beam_r.x + R * 0.35, pos.y + R * 0.15}, 1, color)
	ink_line(rl.Vector2{pos.x - R * 0.35, pos.y + R * 0.75}, rl.Vector2{pos.x + R * 0.35, pos.y + R * 0.75}, 2, color) // base
}

// draw_chest_mark draws a revealed Reward as a treasure chest — cargo & coin.
draw_chest_mark :: proc(pos: rl.Vector2, color: rl.Color) {
	R :: f32(NODE_RADIUS)
	left := pos.x - R * 0.7
	right := pos.x + R * 0.7
	bot := pos.y + R * 0.65
	band := pos.y - R * 0.15
	top := pos.y - R * 0.5
	// Body box.
	ink_line(rl.Vector2{left, band}, rl.Vector2{left, bot}, 2, color)
	ink_line(rl.Vector2{right, band}, rl.Vector2{right, bot}, 2, color)
	ink_line(rl.Vector2{left, bot}, rl.Vector2{right, bot}, 2, color)
	// Lid: a shallow arc, drawn as two strokes to the crown.
	ink_line(rl.Vector2{left, band}, rl.Vector2{pos.x, top}, 2, color)
	ink_line(rl.Vector2{pos.x, top}, rl.Vector2{right, band}, 2, color)
	ink_line(rl.Vector2{left, band}, rl.Vector2{right, band}, 2, color) // lid line
	// Lock.
	rl.DrawRectangleLinesEx(rl.Rectangle{pos.x - R * 0.15, band - R * 0.05, R * 0.3, R * 0.4}, 1, color)
}

// draw_buoy_mark draws an unrevealed encounter as a dotted "?" buoy in faded-ink — the whole
// of the Sim's fog (spec §7). Faded-ink is the recessive register: present, charted, but its
// content held back until reached, so it never pulls the eye before the road ahead does.
draw_buoy_mark :: proc(pos: rl.Vector2) {
	R :: f32(NODE_RADIUS)
	// Dotted ring: dots around the circle rather than a solid line.
	DOTS :: 12
	for i in 0 ..< DOTS {
		a := f32(i) / f32(DOTS) * 2 * math.PI
		p := pos + rl.Vector2{math.cos(a), math.sin(a)} * (R * 0.8)
		rl.DrawCircleV(p, DOT_R_BUOY, INK_FADED)
	}
	q := fmt.ctprint("?")
	size := rl.MeasureTextEx(ui_font_body, q, UI_BODY_SIZE, 1)
	rl.DrawTextEx(ui_font_body, q, rl.Vector2{pos.x - size.x / 2, pos.y - size.y / 2}, UI_BODY_SIZE, 1, INK_FADED)
}

// draw_haven_island draws the run's end — the one landfall that matters — as a hand-inked
// sepia island bearing the coral X that marks the treasure. The X is the *only* spend of
// coral on the page besides the danger tick (spec §3/§8), so the captain's eye is always
// pulled to where they are ultimately sailing. `color` is the island's sepia ink (faded once
// the Haven is visited); the X stays full coral so the goal never dims.
draw_haven_island :: proc(pos: rl.Vector2, color: rl.Color) {
	R :: f32(NODE_RADIUS)
	// Island: a low mound over a waterline, drawn as an inked outline rather than a filled
	// khaki mass so it sits in the parchment's ink language.
	base_l := rl.Vector2{pos.x - R * 0.95, pos.y + R * 0.55}
	base_r := rl.Vector2{pos.x + R * 0.95, pos.y + R * 0.55}
	ink_line(base_l, base_r, 2, color) // waterline
	// Mound: a shallow arc from left base up over to right base, as three strokes.
	ink_line(base_l, rl.Vector2{pos.x - R * 0.45, pos.y - R * 0.35}, 2, color)
	ink_line(rl.Vector2{pos.x - R * 0.45, pos.y - R * 0.35}, rl.Vector2{pos.x + R * 0.45, pos.y - R * 0.35}, 2, color)
	ink_line(rl.Vector2{pos.x + R * 0.45, pos.y - R * 0.35}, base_r, 2, color)
	// The coral X marking the treasure — always full coral, drawn bold over the island.
	ink_line(rl.Vector2{pos.x - R * 0.4, pos.y + R * 0.35}, rl.Vector2{pos.x + R * 0.4, pos.y - R * 0.15}, 3, INK_CORAL)
	ink_line(rl.Vector2{pos.x + R * 0.4, pos.y + R * 0.35}, rl.Vector2{pos.x - R * 0.4, pos.y - R * 0.15}, 3, INK_CORAL)
}

// draw_danger_tick draws a short coral stroke at a reachable buoy's shoulder — "this stop is
// still a mystery, and you'd be sailing into it". Coral is the page's one warm accent, shared
// only with the Haven X (spec §3): it warns exactly where the risk is, and nowhere else.
draw_danger_tick :: proc(pos: rl.Vector2, tint := INK_CORAL) {
	R :: f32(NODE_RADIUS)
	rl.DrawLineEx(
		rl.Vector2{pos.x + R * 0.55, pos.y - R * 1.15},
		rl.Vector2{pos.x + R * 1.15, pos.y - R * 0.55},
		3,
		tint,
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
		fmt.ctprintf("Hull %d/%d   SPD %d", s.hull, s.max_hull, ship.ship_effective_speed(s)),
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
				magnitude = ship.effect_showcase_magnitude(active)
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
// the magnitude and the verb it carries (Effect_Kind), with synergy and conditionality
// spelled out ("+2 Offense per Weapon", "+8 Offense when its condition holds"). Reads
// whichever of active/passive carries the effect; "no effect" for a cargo filler.
//
// The magnitude is the effect read **at showcase** (effect_showcase_magnitude): what the
// item is worth when what its tree asks for is true. An item held in the hand has no ship,
// round or opponent to resolve against, and resolving it against nothing would print every
// conditional item as "+0". Since #404 a magnitude is an arbitrary tree, so what the
// condition *is* no longer has a closed set of clauses to render — the line says only that
// there is one, which is the honest reading until the item card is re-cut (#405).
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
		target = "Offense"
	case .Repair:
		target = "Repair"
	case .Modify_Speed:
		target = "Speed"
	}

	intent := fmt.tprintf("+%d %s", ship.effect_showcase_magnitude(effect), target)
	if selector, ok := effect.synergy.?; ok {
		intent = fmt.tprintf("%s per %v", intent, selector)
	}
	if ship.expr_is_conditional(effect.magnitude) {
		intent = fmt.tprintf("%s when its condition holds", intent)
	}
	return intent
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

// draw_scene_contents draws the map/travel scene — the chart, the player's ship panel, the
// encounter strip, and an optional overlay banner. It does not Begin/EndDrawing itself, so a
// caller that draws more on top can share one Begin/End pair around it; draw_scene is the
// standalone wrapper for callers with nothing further. The Fight is no longer drawn here — it
// has its own facing-cutaway scene (draw_fight_contents, #315), which draw_beat routes battle
// beats through — so this is always the out-of-battle scene now.
draw_scene_contents :: proc(state: ^Game_State, overlay: string, mouse: rl.Vector2) {
	rl.ClearBackground(COLOUR_DEEP)

	draw_map(state, mouse)
	draw_ship_panel(&state.player, rl.Vector2{SHIP_PANEL_X, 20}, "Your Ship", false)

	// Last of the left column, so it sits over the map rather than under it.
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

// draw_beat renders one frame of a playback beat: the scene beneath, then the shared playback
// overlay laid over it (#304, encounter_frame.odin). The beat is the styled scrim-and-headline
// surface — it dims the scene but leaves it visible — replacing play_beat's old bottom bar. The
// scene under it is the Fight's facing cutaways when a battle is live (so a battle beat lands
// on the two ships the captain is looking at, #315), otherwise the map/travel scene. Its own
// Begin/EndDrawing pair, like draw_scene.
draw_beat :: proc(state: ^Game_State, headline: string) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	if state.in_battle {
		draw_fight_scene(state, rl.Vector2{-1, -1})
	} else {
		draw_scene_contents(state, "", rl.Vector2{-1, -1})
	}
	draw_playback_overlay(headline)
}
