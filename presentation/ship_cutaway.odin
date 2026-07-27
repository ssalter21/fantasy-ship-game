#+private
package presentation

import "core:fmt"
import cutaway "./cutaway"
import ship "../core/ship"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// The ship screen's galleon: the player's own flagship drawn as a three-quarter cutaway with
// her port side opened up, so every berth is a room you look into. The cutaway module places
// the rooms and answers what the cursor is over (cutaway/galleon.odin); this file paints them,
// the hull they are cut into, the rig above and the sea behind.
//
// The rooms are empty on purpose: they are placeholder chambers, and what a berth *is* is
// carried by the description card a hover pops, not by anything standing in the room.
//
// Nothing labels the ship at rest: the hull is never obscured, and the one card that appears
// is thrown clear of it into open water with a leader line back to the berth it describes.

// Room_Highlight is what a berth's opening is saying this frame: nothing at rest, the bright
// cool under the cursor or under a fitting that may land there, and a wash of shadow over a
// berth the fitting in hand cannot go in.
Room_Highlight :: enum {
	Resting,
	Hovered,
	Legal,
	Blocked,
}

// draw_ship_cutaway paints one frame of the ship: sea and sky, the hull with its rooms, the
// rig, and — only when the cursor is in a room and nothing is in hand — that berth's outline
// and description card. `drag` lights the berths a dragged fitting may legally land in and
// dims the rest, the same steer the flat cutaway gave (#302), now on the rooms themselves.
draw_ship_cutaway :: proc(state: ^Game_State, drag: Build_Drag, mouse: rl.Vector2) {
	view := cutaway.galleon_view(WINDOW_WIDTH, WINDOW_HEIGHT)
	if eye, flown := ship_debug_eye.?; flown {
		view = cutaway.galleon_view_from(eye, WINDOW_WIDTH, WINDOW_HEIGHT)
	}
	// The horizon goes onto the art lattice before anything is drawn against it. The sky's last
	// row, the sea's first and the foam standing up her planking all key off this one number, and
	// a backdrop snapped around an unsnapped horizon leaves a part-pixel seam along the join.
	horizon := backdrop_floor(cutaway.galleon_horizon_y(view))
	draw_ship_sky(horizon)
	draw_ship_sea(horizon)
	draw_ship_wake(view, horizon)

	rooms, n := cutaway.galleon_rooms(state.player.layout)

	// A drag owns the highlight while it is up, so the description card never competes with
	// the fitting in hand.
	hovered: Maybe(ship.Slot_Index)
	if !drag.active {
		hovered = cutaway.galleon_room_at(state.player.layout, mouse, view)
	}

	ship_paint_view(view.camera)
	rl.BeginMode3D(view.camera)
	// The wireframe view is bracketed by explicit batch flushes. Wire mode is a GL polygon-mode
	// switch, but rlgl queues geometry and only settles it when the batch fills or is drawn — so
	// without the flushes the mode lands on whatever happened to be in flight and the ship comes
	// out part solid, part mesh. Flush, switch, draw, flush, switch back.
	if ship_debug_wires {
		rlgl.DrawRenderBatchActive()
		rlgl.EnableWireMode()
	}
	draw_ship_hull()
	for i in 0 ..< n {
		draw_ship_room(rooms[i], ship_room_timber(rooms[i].kind))
	}
	draw_ship_ornament(rooms, n)
	draw_ship_rig()
	if ship_debug_wires {
		rlgl.DrawRenderBatchActive()
		rlgl.DisableWireMode()
	}
	rl.EndMode3D()

	// The foam standing up her planking goes on last, over the hull it is breaking against.
	draw_ship_waterline(view, horizon)

	// Highlights wash over the openings rather than tinting the timber: a room's inside is
	// mostly shadow and a colour mixed into the wood barely reads, where a wash across the
	// opening the eye is already pointed into reads at a glance.
	for i in 0 ..< n {
		highlight := ship_room_highlight(state, drag, rooms[i].slot, hovered)
		if highlight == .Resting {
			continue
		}
		draw_ship_face_highlight(cutaway.galleon_room_face(rooms[i], view), highlight)
	}

	if slot, over := hovered.?; over {
		room, _ := cutaway.galleon_room_for_slot(rooms, n, slot)
		draw_ship_slot_card(state.player.layout[slot], room, view)
	}
}

// ship_room_timber is a room's base wood, off the roster's warm neutrals: warm oak for the
// weather-deck structures, a darker stowage timber for the holds, so above and below deck read
// as different places.
ship_room_timber :: proc(kind: cutaway.Room_Kind) -> rl.Color {
	if kind == .Hold {
		// The holds are down in the belly with the sun nowhere near them, and shaded off the same
		// dark hull timber they are cut into they came out as a row of black boxes. They are given
		// a lighter stowage deal instead, so the light that does reach them has something to find.
		return colour_shade(COLOUR_CLIFF, 0.94)
	}
	return colour_shade(COLOUR_CLIFF, 1.0)
}

// ship_room_highlight is what a berth's opening should say this frame. A drag speaks over
// everything — while a fitting is in hand every berth answers whether it will take it — and
// only with nothing in hand does the cursor's own room light.
ship_room_highlight :: proc(
	state: ^Game_State,
	drag: Build_Drag,
	slot: ship.Slot_Index,
	hovered: Maybe(ship.Slot_Index),
) -> Room_Highlight {
	if drag.active {
		return build_is_legal_berth(state, drag, slot) ? .Legal : .Blocked
	}
	if under, over := hovered.?; over && under == slot {
		return .Hovered
	}
	return .Resting
}

// draw_ship_face_highlight washes a room's projected opening: a translucent fill, and a bright
// edge on the two that are pointing somewhere (the cursor's room, and a berth that will take
// what is in hand). A blocked berth is only shaded — it is being pushed back, not pointed at.
draw_ship_face_highlight :: proc(face: [4]rl.Vector2, highlight: Room_Highlight) {
	fill: rl.Color
	edge: Maybe(rl.Color)
	switch highlight {
	case .Resting:
		return
	case .Hovered:
		fill, edge = rl.Fade(COLOUR_SEA_BRIGHT, 0.3), COLOUR_FOAM
	case .Legal:
		fill, edge = rl.Fade(COLOUR_SEA_SHALLOW, 0.3), COLOUR_SEA_SHALLOW
	case .Blocked:
		fill, edge = rl.Fade(COLOUR_INK_PRIMARY, 0.35), nil
	}

	// raylib culls clockwise triangles into nothing, and perspective can hand back either
	// winding, so the quad is wound counter-clockwise (negative signed area, screen y down)
	// before it is filled.
	quad := face
	area: f32 = 0
	for i in 0 ..< len(quad) {
		a, b := quad[i], quad[(i + 1) % len(quad)]
		area += a.x * b.y - b.x * a.y
	}
	if area > 0 {
		quad = {face[3], face[2], face[1], face[0]}
	}
	rl.DrawTriangle(quad[0], quad[1], quad[2], fill)
	rl.DrawTriangle(quad[0], quad[2], quad[3], fill)

	if stroke, outlined := edge.?; outlined {
		for i in 0 ..< len(face) {
			rl.DrawLineEx(face[i], face[(i + 1) % len(face)], 2.5, stroke)
		}
	}
}

// SHIP_CASTLE_ROOF is how far above a castle's walls its own deck is laid. draw_ship_ornament
// lays that deck and this file builds the walls under it, and the two used to arrive at the
// height separately — three centimetres apart. Three centimetres of daylight running right round
// a castle is not a detail: the camera is *below* these structures, so the eye goes in at the
// slit on the near side, through the chamber, and out at the slit on the far side, and what it
// finds there is sky. Those were the bright bands cutting across her castles. One constant, read
// by both, is the only thing that keeps a roof on a wall.
SHIP_CASTLE_ROOF :: f32(0.03)

// ship_room_roofed is whether a room carries a deck of its own overhead. The holds are roofed by
// the weather deck the hull draws, and the waist is the weather deck, so it is the structures
// standing on it that need one — and they are exactly the rooms draw_ship_ornament decks.
ship_room_roofed :: proc(kind: cutaway.Room_Kind) -> bool {
	return kind != .Hold && kind != .Waist
}

// draw_ship_room paints one empty chamber, open on the cut side and on top so the camera looks
// straight in. It follows the room's taper (cutaway.galleon_room_half_z) rather than standing
// as a box, so a compartment narrows into the ends of the ship along with the planking it is
// cut into.
//
// A structure standing on the weather deck is not given a floor of its own: the deck *is* its
// floor, and a second one laid at exactly the same height fought the first for the depth buffer
// and left the castles flickering above a deck they never met. It gets a coaming instead — the
// raised sill a real deckhouse is framed on — which is a join the eye can actually see.
draw_ship_room :: proc(room: cutaway.Room, base: rl.Color) {
	THICKNESS :: f32(0.05)
	aft := room.centre.x - room.half.x
	fore := room.centre.x + room.half.x
	floor_y := room.centre.y - room.half.y
	on_deck := abs(floor_y - cutaway.GALLEON_DECK_Y) < 0.03

	if !on_deck {
		// Her decks run fore and aft like the weather deck above them, so a compartment's floor
		// reads as laid planking rather than as a painted panel. The planks converge with the
		// taper, which is what a deck laid in a narrowing hull does.
		PLANKS :: 5
		for p in 0 ..< PLANKS {
			f0 := f32(p) / PLANKS * 2 - 1
			f1 := f32(p + 1) / PLANKS * 2 - 1
			z_aft := room.centre.z + f0 * room.half_aft
			z_fore := room.centre.z + f0 * room.half_fore
			w_aft := room.centre.z + f1 * room.half_aft
			w_fore := room.centre.z + f1 * room.half_fore
			// The floor is the one surface in a compartment turned up at the sky, so it is the one
			// the light finds. Kept dark it took the last read of depth out of a room that is
			// otherwise all shadowed wall.
			tone := colour_shade(base, p % 2 == 0 ? 0.74 : 0.66)
			ship_quad_lit({aft, floor_y, z_aft}, {fore, floor_y, z_fore}, {fore, floor_y, w_fore}, {aft, floor_y, w_aft}, tone, {0, 1, 0})
		}
	}

	// Where a wall starts. A structure standing on the weather deck is matched to the deck by a
	// tolerance — `on_deck` admits anything within a few centimetres — and any part of that
	// tolerance that puts the room's floor *above* the plate leaves a horizontal slit between the
	// two. Looking into a castle from off the bow that slit is a thin bright line of sky running
	// along its foot, which is exactly what the gaps in her castles were. Walls of an on-deck
	// structure therefore start at the deck itself, with a hand's overlap below it: an overlap
	// costs nothing where two solids meet, and a hairline of daylight costs the whole illusion.
	//
	// A structure standing on *another* structure has the identical problem, and the poop is one:
	// it sits on the sterncastle's deck with its own floor three centimetres above it, and that gap
	// was a bright line of sky right round its foot. So the overlap is given to anything standing
	// above the weather deck, not only to what stands on it.
	above_deck := floor_y > cutaway.GALLEON_DECK_Y - 0.03
	wall_base := floor_y
	if on_deck {
		wall_base = cutaway.GALLEON_DECK_Y - 0.05
	} else if above_deck {
		wall_base = floor_y - 0.08
	}

	if room.kind == .Waist {
		// The waist is the open weather deck between the castles. It has no floor of its own and
		// no walls at all — nothing may stand up in the middle of the main deck.
		return
	}

	if on_deck {
		draw_ship_coaming(room, base)
	}

	// The after bulkhead, whole: it is the back wall of the room, and the sun over her quarter
	// catches it, which is what gives the chamber its depth.
	// A roofed room's walls are built up to the underside of its own deck rather than to the top of
	// its box — which is the same three centimetres, spent on timber instead of on sky.
	roofed := ship_room_roofed(room.kind)
	wall_top := room.centre.y + room.half.y + (roofed ? SHIP_CASTLE_ROOF : 0)
	ship_box(
		{aft, (wall_base + wall_top) / 2, room.centre.z},
		{THICKNESS, wall_top - wall_base, 2 * room.half_aft},
		base,
	)

	// The forward one is cut through, and that is not a shortcut — it is the whole cutaway. The
	// camera stands off her bow, so a compartment's *forward* bulkhead is the wall between the
	// eye and the room, presented near enough face-on to fill the opening. Drawn whole it is a
	// broad panel turned away from the sun, and a row of them is one flat brown slab across the
	// ship with every chamber sealed behind it — which is exactly what the belly of her read as.
	// A cutaway drawing cuts the near end as well as the near side, and leaves the frame of it
	// standing: sill, header, and the post at the outboard edge.
	draw_ship_cut_bulkhead(room, base, fore, wall_base, wall_top)

	// The far side follows the taper, so it is laid as a raked wall rather than a slab: the
	// outer face, the inner one the camera actually looks at, and the plank edge capping them.
	top := wall_top
	out_aft := room.centre.z + room.half_aft
	out_fore := room.centre.z + room.half_fore
	for inset in ([2]f32{0, THICKNESS}) {
		za := out_aft - inset
		zf := out_fore - inset
		ship_quad_lit({aft, wall_base, za}, {fore, wall_base, zf}, {fore, top, zf}, {aft, top, za}, base, {0, 0, inset == 0 ? 1 : -1})
	}
	// The plank edge across the top of that wall — but only where the wall is actually the top of
	// something. Under a castle's own deck it would be laid in the same plane as that deck and the
	// two would fight for the depth buffer, which is a flicker rather than a fix.
	if !roofed {
		ship_quad_lit(
			{aft, top, out_aft},
			{fore, top, out_fore},
			{fore, top, out_fore - THICKNESS},
			{aft, top, out_aft - THICKNESS},
			colour_shade(base, 1.1),
			{0, 1, 0},
		)
	}

	// Her frames, standing up the far side of the compartment. A hold is a space between ribs
	// and they are the only thing in it — without them the back wall is a painted panel, and no
	// amount of light on a panel makes it a room.
	if room.kind == .Hold {
		for f := f32(0.12); f < 0.99; f += 0.19 {
			x := aft + f * 2 * room.half.x
			z := room.centre.z + cutaway.galleon_room_half_z(room, x) - THICKNESS
			ship_box({x, room.centre.y, z - 0.03}, {0.055, 2 * room.half.y * 0.96, 0.06}, colour_shade(base, 0.82))
		}
	}
}

// draw_ship_cut_bulkhead leaves the frame of a bulkhead the cut has gone through: the sill it
// stood on, the header under the beams, and the post at its outboard edge — the raw sawn timber
// of a cut, bright against the shadow inside, so the eye is told the wall was taken away rather
// than never built. The middle is open, and the room is looked through it.
draw_ship_cut_bulkhead :: proc(room: cutaway.Room, base: rl.Color, x, floor_y, top: f32) {
	THICKNESS :: f32(0.05)
	FRAME :: f32(0.08)
	half_z := room.half_fore
	height := top - floor_y
	sawn := colour_shade(COLOUR_CLIFF, 1.05)

	ship_box({x, floor_y + FRAME / 2, room.centre.z}, {THICKNESS, FRAME, 2 * half_z}, sawn)
	ship_box({x, floor_y + height - FRAME / 2, room.centre.z}, {THICKNESS, FRAME, 2 * half_z}, sawn)
	ship_box({x, (floor_y + top) / 2, room.centre.z + half_z - FRAME / 2}, {THICKNESS, height, FRAME}, base)
}

// draw_ship_coaming frames a deck structure onto the deck it stands on: the raised sill its
// bulkheads are stepped into, run round all four sides of its footprint. It is a small piece
// and it does a large job — without it a castle is a box resting on a plane, and the eye reads
// it as floating rather than built.
draw_ship_coaming :: proc(room: cutaway.Room, base: rl.Color) {
	deck := cutaway.GALLEON_DECK_Y
	SILL :: f32(0.075)
	LIP :: f32(0.05)
	oak := colour_shade(COLOUR_ROCK, 1.0)

	aft := room.centre.x - room.half.x
	fore := room.centre.x + room.half.x
	ship_box({aft, deck + SILL / 2, room.centre.z}, {2 * LIP, SILL, 2 * room.half_aft + 2 * LIP}, oak)
	ship_box({fore, deck + SILL / 2, room.centre.z}, {2 * LIP, SILL, 2 * room.half_fore + 2 * LIP}, oak)

	// The two long sills, raked with the taper: the far one, and the threshold under the opening
	// the camera looks over into the room.
	for side in ([2]f32{1, -1}) {
		za := room.centre.z + side * (room.half_aft + LIP)
		zf := room.centre.z + side * (room.half_fore + LIP)
		for y in ([2]f32{deck, deck + SILL}) {
			ship_quad_lit(
				{aft, y, za},
				{fore, y, zf},
				{fore, y, zf - side * LIP},
				{aft, y, za - side * LIP},
				colour_shade(oak, y == deck ? 0.8 : 1.15),
				{0, y == deck ? -1 : 1, 0},
			)
		}
		ship_quad_lit({aft, deck, za}, {fore, deck, zf}, {fore, deck + SILL, zf}, {aft, deck + SILL, za}, oak, {0, 0, side})
	}
}

// SHIP_CARD is the hovered berth's description card, parked bottom-right over open water: the
// bow looms into the left of the frame and the stats ledger runs along the bottom, so the
// right corner is the one reliably clear of both the ship and the chrome.
SHIP_CARD_W :: f32(300)
SHIP_CARD_H :: f32(150)

ship_card_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle {
		x = WINDOW_WIDTH - SHIP_CARD_W - 14,
		y = BUILD_LEDGER_Y - SHIP_CARD_H - 14,
		width = SHIP_CARD_W,
		height = SHIP_CARD_H,
	}
}

// draw_ship_slot_card writes the hovered berth up on parchment thrown clear of the hull, tied
// back to the room by a leader line to its opening. Nothing about the berth is drawn on the
// ship itself, so at rest the galleon carries no labels at all.
draw_ship_slot_card :: proc(layout_slot: ship.Layout_Slot, room: cutaway.Room, view: cutaway.View) {
	card := ship_card_rect()
	anchor := cutaway.galleon_face_centre(cutaway.galleon_room_face(room, view))
	tie := rl.Vector2{card.x + 12, card.y + 10}

	rl.DrawLineEx(anchor, tie, 2, rl.Fade(COLOUR_INK_PRIMARY, 0.7))
	rl.DrawCircleV(anchor, 5, rl.Fade(COLOUR_FOAM, 0.9))
	rl.DrawCircleLinesV(anchor, 5, COLOUR_SEA_DEEP)

	rl.DrawRectangleRec(card, COLOUR_PARCHMENT)
	rl.DrawRectangleLinesEx(card, 2, COLOUR_SEA_DEEP)

	title, spec, intent, material := ship_slot_description(layout_slot)
	x := card.x + 14
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", title), rl.Vector2{x, card.y + 12}, UI_BODY_SIZE, 1, COLOUR_INK_PRIMARY)
	rl.DrawRectangleRec(rl.Rectangle{x = x, y = card.y + 34, width = card.width - 28, height = 2}, COLOUR_SAND)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", intent), rl.Vector2{x, card.y + 46}, UI_BODY_SIZE, 1, COLOUR_INK_PRIMARY)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", spec), rl.Vector2{x, card.y + 74}, UI_BODY_SIZE, 1, COLOUR_INK_MUTED)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", material), rl.Vector2{x, card.y + 102}, UI_BODY_SIZE, 1, COLOUR_INK_MUTED)
}

// ship_slot_description is what a berth's card says: its name, the effect it is there for, the
// spec (size · phase · tags) and the material facts a captain weighs — weight, what it is
// carrying against what it can, and which berth it is. An empty berth has only the last two to
// give, so it says so plainly rather than showing blank lines.
ship_slot_description :: proc(layout_slot: ship.Layout_Slot) -> (title, spec, intent, material: string) {
	fitting, filled := layout_slot.fitting.?
	if !filled {
		return fmt.tprintf("(empty %v)", layout_slot.slot.size),
			fmt.tprintf("%v berth", layout_slot.slot.size),
			"nothing installed",
			fmt.tprintf("%s · %v", layout_slot.slot.name, layout_slot.slot.base_visibility)
	}
	spec, intent = fitting_summary_lines(fitting)
	material = fmt.tprintf(
		"wt %d · %d/%d · %s · %v",
		fitting.weight,
		fitting.cargo_held,
		ship.ship_fitting_capacity(fitting),
		layout_slot.slot.name,
		layout_slot.slot.base_visibility,
	)
	return fitting.name, spec, intent, material
}
