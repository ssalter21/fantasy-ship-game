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
	draw_ship_backdrop(cutaway.galleon_horizon_y(view))

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
		return colour_shade(COLOUR_ROCK, 1.05)
	}
	return colour_shade(COLOUR_CLIFF, 0.82)
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

// draw_ship_backdrop paints the sky, its pixel clouds and the sea, with the water starting at
// the camera's own horizon (cutaway.galleon_horizon_y) rather than at a guessed height — which
// is what puts the sea across the ship's lower planking and leaves her riding high.
draw_ship_backdrop :: proc(horizon_y: f32) {
	SKY_BAND :: f32(96)
	rl.ClearBackground(COLOUR_SKY_HIGH)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = SKY_BAND, width = WINDOW_WIDTH, height = SKY_BAND}, COLOUR_SKY)
	rl.DrawRectangleRec(
		rl.Rectangle{x = 0, y = 2 * SKY_BAND, width = WINDOW_WIDTH, height = horizon_y - 2 * SKY_BAND},
		COLOUR_HAZE,
	)
	draw_ship_cloud(220, 92)
	draw_ship_cloud(1010, 70)

	// A band of deeper water at the horizon reads as distance; the near sea is the field tone.
	SHELF :: f32(24)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = horizon_y, width = WINDOW_WIDTH, height = SHELF}, COLOUR_SEA_DEEP)
	rl.DrawRectangleRec(
		rl.Rectangle{x = 0, y = horizon_y + SHELF, width = WINDOW_WIDTH, height = WINDOW_HEIGHT - horizon_y - SHELF},
		COLOUR_SEA,
	)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = horizon_y, width = WINDOW_WIDTH, height = 2}, COLOUR_FOAM)

	// Scattered chop, spread by two co-prime strides so the dashes never fall into rows.
	for i in 0 ..< 64 {
		x := f32((i * 211) % 1180) + 30
		y := horizon_y + SHELF + 12 + f32((i * 137) % 340)
		tone := i % 3 == 0 ? COLOUR_SEA_SHALLOW : COLOUR_SEA_BRIGHT
		rl.DrawRectangleRec(rl.Rectangle{x = x, y = y, width = 22, height = 3}, rl.Fade(tone, 0.5))
	}
}

// draw_ship_cloud stacks three blocky rects over a shadow — a pixel cloud, no curves.
draw_ship_cloud :: proc(cx, cy: f32) {
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 70, y = cy + 14, width = 150, height = 22}, COLOUR_CLOUD_SHADOW)
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 60, y = cy, width = 120, height = 24}, COLOUR_CLOUD)
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 28, y = cy - 14, width = 62, height = 18}, COLOUR_CLOUD)
}

// draw_ship_hull paints the timber the rooms are cut into: the far inner wall and the
// underside as strips following the hull's curves, the main deck spanning the beam, and the
// stem and transom capping the ends. The near (-z) side is left open — that is the cutaway.
draw_ship_hull :: proc() {
	STRIP :: f32(0.16)
	// Deep hull timber: the roster's darkest warm, taken down again — planking below the wale
	// has to sit under every room cut into it or the cutaway reads as a flat board.
	hull := colour_shade(COLOUR_ROCK, 0.78)
	dark := colour_shade(hull, 0.9)
	darker := colour_shade(hull, 0.66)
	midships := (cutaway.GALLEON_STERN_X + cutaway.GALLEON_BOW_X) / 2
	length := cutaway.GALLEON_BOW_X - cutaway.GALLEON_STERN_X

	for x := cutaway.GALLEON_STERN_X; x < cutaway.GALLEON_BOW_X - 0.001; x += STRIP {
		mid := x + STRIP / 2
		keel := cutaway.galleon_keel_y(mid)
		sheer := cutaway.galleon_sheer_y(mid)

		// The far inner wall, aft in shadow and the bow catching the light, so the interior has
		// depth down its length rather than reading as one flat board.
		if sheer - keel > 0.05 {
			lit := 0.78 + (mid - cutaway.GALLEON_STERN_X) / length * 0.28
			rl.DrawCube(
				rl.Vector3{mid, (keel + sheer) / 2, cutaway.GALLEON_HALF_BEAM},
				STRIP + 0.006,
				sheer - keel,
				0.09,
				colour_shade(hull, lit),
			)
		}

		// The underside, spanning the beam and following the keel's curve.
		rl.DrawCube(rl.Vector3{mid, keel - 0.05, 0}, STRIP + 0.006, 0.14, 2 * cutaway.GALLEON_HALF_BEAM, darker)
	}

	// The main deck: ceiling of the holds, floor of the waist.
	rl.DrawCube(
		rl.Vector3{midships, cutaway.GALLEON_DECK_Y, 0},
		length - 0.4,
		0.08,
		2 * cutaway.GALLEON_HALF_BEAM,
		colour_shade(hull, 1.15),
	)

	// A gilded wale over a dark rubbing strake, banding the hull below the sheer.
	wale := length - 0.5
	rl.DrawCube(
		rl.Vector3{midships, cutaway.GALLEON_DECK_Y - 0.09, cutaway.GALLEON_HALF_BEAM - 0.05},
		wale,
		0.07,
		0.05,
		COLOUR_SAND,
	)
	rl.DrawCube(
		rl.Vector3{midships, cutaway.GALLEON_DECK_Y - 0.19, cutaway.GALLEON_HALF_BEAM - 0.05},
		wale,
		0.06,
		0.05,
		darker,
	)

	// Stem and transom, capping the ends above the waterline.
	beam := 2 * cutaway.GALLEON_HALF_BEAM - 0.04
	rl.DrawCube(
		rl.Vector3{cutaway.GALLEON_BOW_X - 0.14, cutaway.galleon_sheer_y(cutaway.GALLEON_BOW_X) - 0.1, 0},
		0.28,
		0.95,
		beam,
		dark,
	)
	rl.DrawCube(
		rl.Vector3{cutaway.GALLEON_STERN_X + 0.12, cutaway.galleon_sheer_y(cutaway.GALLEON_STERN_X) - 0.05, 0},
		0.24,
		1.05,
		beam,
		dark,
	)
}

// draw_ship_room paints one empty chamber, open on the cut side and on top so the camera looks
// straight in. The waist is the open weather deck: it is planking and nothing else, since no
// wall may stand up in the middle of the main deck.
draw_ship_room :: proc(room: cutaway.Room, base: rl.Color) {
	THICKNESS :: f32(0.05)
	wire := rl.Fade(COLOUR_INK_PRIMARY, 0.6)
	size := 2 * room.half

	floor := rl.Vector3{room.centre.x, room.centre.y - room.half.y, room.centre.z}
	rl.DrawCube(floor, size.x, THICKNESS, size.z, colour_shade(base, 0.44))
	rl.DrawCubeWires(floor, size.x, THICKNESS, size.z, wire)

	if room.kind == .Waist {
		return
	}

	// Back wall and the two end walls. The spread between the lit fore end and the shadowed aft
	// one is what models the room — without it an open box reads flat.
	back := rl.Vector3{room.centre.x, room.centre.y, room.centre.z + room.half.z}
	rl.DrawCube(back, size.x, size.y, THICKNESS, colour_shade(base, 0.82))
	rl.DrawCubeWires(back, size.x, size.y, THICKNESS, wire)
	rl.DrawCube(
		rl.Vector3{room.centre.x - room.half.x, room.centre.y, room.centre.z},
		THICKNESS,
		size.y,
		size.z,
		colour_shade(base, 0.58),
	)
	rl.DrawCube(
		rl.Vector3{room.centre.x + room.half.x, room.centre.y, room.centre.z},
		THICKNESS,
		size.y,
		size.z,
		colour_shade(base, 1.14),
	)
}

// draw_ship_rig is the full square rig of a flagship of the line: fore, main and mizzen, each
// carrying stacked sails that narrow as they climb, a pennant at every masthead, and a
// bowsprit with its spritsail. The sails hang athwartships from yards crossing the masts —
// spanning the beam and facing fore-and-aft — so from the bow quarter the canvas is read at an
// angle, the way a square-rigger's actually sits.
draw_ship_rig :: proc() {
	// One mast: where it stands along the hull, how tall, and how many sails it carries. Laid
	// bow to stern, so the rows are fore, main and mizzen.
	Mast :: struct {
		x, height: f32,
		tiers:     int,
	}
	COURSE_WIDTH :: f32(1.75)

	deck := cutaway.GALLEON_DECK_Y + 0.04
	masts := [3]Mast{{x = 1.85, height = 3.1, tiers = 2}, {x = 0.4, height = 3.9, tiers = 3}, {x = -1.15, height = 2.8, tiers = 2}}

	for mast in masts {
		rl.DrawCylinder(rl.Vector3{mast.x, deck, 0}, 0.05, 0.09, mast.height, 10, COLOUR_TRUNK)

		// The sails start halfway up so the canvas rides clear above the castles, and each tier
		// narrows as it climbs — a wide course under progressively shorter topsails.
		tier_h := mast.height * 0.26
		for tier in 0 ..< mast.tiers {
			width := COURSE_WIDTH * (1.0 - f32(tier) / f32(mast.tiers) * 0.4)
			y := deck + mast.height * 0.5 + f32(tier) * tier_h
			rl.DrawCube(rl.Vector3{mast.x, y, 0}, 0.04, tier_h * 0.86, width, COLOUR_CREAM)
			rl.DrawCubeWires(rl.Vector3{mast.x, y, 0}, 0.04, tier_h * 0.86, width, COLOUR_SAND)
			rl.DrawCube(rl.Vector3{mast.x, y + tier_h * 0.48, 0}, 0.05, 0.05, width + 0.18, COLOUR_TRUNK)
		}

		truck := deck + mast.height
		rl.DrawCube(rl.Vector3{mast.x, truck + 0.02, 0}, 0.05, 0.22, 0.05, COLOUR_TRUNK)
		rl.DrawCube(rl.Vector3{mast.x + 0.32, truck + 0.1, 0}, 0.6, 0.13, 0.02, COLOUR_SEA_DEEP)
	}

	// The bowsprit angling up off the stem, with its spritsail slung beneath.
	rl.DrawCylinderEx(
		rl.Vector3{cutaway.GALLEON_BOW_X - 0.2, cutaway.GALLEON_DECK_Y + 0.5, 0},
		rl.Vector3{cutaway.GALLEON_BOW_X + 1.25, cutaway.GALLEON_DECK_Y + 1.2, 0},
		0.05,
		0.03,
		8,
		COLOUR_TRUNK,
	)
	spritsail := rl.Vector3{cutaway.GALLEON_BOW_X + 0.7, cutaway.GALLEON_DECK_Y + 0.95, 0}
	rl.DrawCube(spritsail, 0.03, 0.5, 0.7, COLOUR_CREAM)
	rl.DrawCubeWires(spritsail, 0.03, 0.5, 0.7, COLOUR_SAND)
}

// draw_ship_ornament is the flagship's finery: gilded trim capping every enclosed weather-deck
// structure, a stern lantern over the poop, lit great-cabin windows across the sterncastle's
// far wall, and a figurehead at the stem. The caps are taken off the placed rooms rather than
// from positions of their own, so trim cannot drift off the structure it crowns.
draw_ship_ornament :: proc(rooms: [cutaway.MAX_SLOTS]cutaway.Room, n: int) {
	for i in 0 ..< n {
		room := rooms[i]
		if room.kind == .Hold || room.kind == .Waist {
			continue
		}
		cap_y := room.centre.y + room.half.y + 0.02
		rl.DrawCube(
			rl.Vector3{room.centre.x, cap_y, room.centre.z},
			2 * room.half.x + 0.08,
			0.07,
			2 * room.half.z,
			COLOUR_SAND,
		)

		if room.kind == .Poop {
			rl.DrawCube(rl.Vector3{room.centre.x, cap_y + 0.16, room.centre.z}, 0.2, 0.3, 0.2, COLOUR_PARCHMENT)
			rl.DrawCube(rl.Vector3{room.centre.x, cap_y + 0.36, room.centre.z}, 0.1, 0.12, 0.1, COLOUR_SAND)
		}

		// The stern gallery: a row of lit windows down the great cabin's inner wall.
		if room.kind == .Sterncastle {
			z := room.centre.z + room.half.z - 0.04
			for wx := room.centre.x - room.half.x + 0.18; wx < room.centre.x + room.half.x; wx += 0.36 {
				rl.DrawCube(rl.Vector3{wx, room.centre.y + 0.02, z}, 0.22, 0.32, 0.03, COLOUR_SEA_SHALLOW)
				rl.DrawCubeWires(rl.Vector3{wx, room.centre.y + 0.02, z}, 0.22, 0.32, 0.03, COLOUR_SAND)
			}
		}
	}

	figurehead := rl.Vector3{cutaway.GALLEON_BOW_X - 0.02, cutaway.GALLEON_DECK_Y + 0.14, 0}
	rl.DrawCube(figurehead, 0.34, 0.34, 0.44, COLOUR_PARCHMENT)
	rl.DrawCubeWires(figurehead, 0.34, 0.34, 0.44, COLOUR_SAND)
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
