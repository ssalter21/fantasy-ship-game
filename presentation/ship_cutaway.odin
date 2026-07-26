#+private
package presentation

import "core:fmt"
import cutaway "./cutaway"
import ship "../core/ship"
import rl "vendor:raylib"

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
	horizon := cutaway.galleon_horizon_y(view)
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

	rl.BeginMode3D(view.camera)
	draw_ship_hull()
	for i in 0 ..< n {
		draw_ship_room(rooms[i], ship_room_timber(rooms[i].kind))
	}
	draw_ship_ornament(rooms, n)
	draw_ship_rig()
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

// draw_ship_room paints one empty chamber, open on the cut side and on top so the camera looks
// straight in. The waist is the open weather deck: it is planking and nothing else, since no
// wall may stand up in the middle of the main deck.
draw_ship_room :: proc(room: cutaway.Room, base: rl.Color) {
	THICKNESS :: f32(0.05)
	size := 2 * room.half

	// Her decks run fore and aft like the weather deck above them, so a compartment's floor reads
	// as laid planking rather than as a painted panel.
	floor_y := room.centre.y - room.half.y
	PLANKS :: 5
	for p in 0 ..< PLANKS {
		z0 := room.centre.z + (f32(p) / PLANKS * 2 - 1) * room.half.z
		z1 := room.centre.z + (f32(p + 1) / PLANKS * 2 - 1) * room.half.z
		tone := colour_shade(base, p % 2 == 0 ? 0.50 : 0.44)
		ship_quad_lit(
			{room.centre.x - room.half.x, floor_y, z0},
			{room.centre.x + room.half.x, floor_y, z0},
			{room.centre.x + room.half.x, floor_y, z1},
			{room.centre.x - room.half.x, floor_y, z1},
			tone,
			{0, 1, 0},
		)
	}

	if room.kind == .Waist {
		return
	}

	// The bulkheads: aft, forward, and the far side. Lit rather than tinted by hand — the sun
	// over the port quarter is what darkens the forward bulkhead and catches the after one, and
	// that spread is what models the room. An open box shaded by one flat colour reads flat.
	ship_box({room.centre.x, room.centre.y, room.centre.z + room.half.z}, {size.x, size.y, THICKNESS}, base)
	ship_box({room.centre.x - room.half.x, room.centre.y, room.centre.z}, {THICKNESS, size.y, size.z}, base)
	ship_box({room.centre.x + room.half.x, room.centre.y, room.centre.z}, {THICKNESS, size.y, size.z}, base)
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
