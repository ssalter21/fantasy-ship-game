package cutaway

import "core:testing"

import ship "../../core/ship"
import rl "vendor:raylib"

// The galleon's placement contract, asserted without a window (ADR-0003 keeps pixels out of
// unit tests): the projection is arithmetic on a camera and a frame size, so where a room
// lands and what the cursor picks are both testable off-screen.

// The logical frame the game renders into. Passed explicitly, as the live screen passes it.
@(private = "file")
FRAME_W :: 1244
@(private = "file")
FRAME_H :: 700

// Four exposed berths and four concealed holds of mixed size — the shape the vertical-slice
// ship has, and enough to fill all four weather-deck structures.
@(private = "file")
test_layout :: proc() -> [8]ship.Layout_Slot {
	return [8]ship.Layout_Slot {
		{slot = ship.Slot{name = "top deck", size = .Medium, base_visibility = .Exposed}},
		{slot = ship.Slot{name = "top crew", size = .Medium, base_visibility = .Exposed}},
		{slot = ship.Slot{name = "gun deck", size = .Large, base_visibility = .Exposed}},
		{slot = ship.Slot{name = "forecastle", size = .Large, base_visibility = .Exposed}},
		{slot = ship.Slot{name = "hold 1", size = .Medium, base_visibility = .Concealed}},
		{slot = ship.Slot{name = "hold 2", size = .Small, base_visibility = .Concealed}},
		{slot = ship.Slot{name = "hold 3", size = .Small, base_visibility = .Concealed}},
		{slot = ship.Slot{name = "hold 4", size = .Small, base_visibility = .Concealed}},
	}
}

@(test)
holds_share_one_below_deck_floor_split_by_slot_size :: proc(t: ^testing.T) {
	layout := test_layout()
	rooms, n := galleon_rooms(layout[:])
	testing.expect_value(t, n, 8)

	// One floor: every hold sits below the weather deck at the same height, and they run
	// stern → bow without overlapping.
	previous_bow_edge := max(f32) * -1
	first := true
	floor_y: f32
	for i in 0 ..< n {
		room := rooms[i]
		if room.kind != .Hold {
			continue
		}
		testing.expect(t, room.centre.y + room.half.y < GALLEON_DECK_Y, "a hold sits below the weather deck")
		if first {
			floor_y, first = room.centre.y, false
		}
		testing.expect_value(t, room.centre.y, floor_y)
		testing.expect(t, room.centre.x - room.half.x >= previous_bow_edge, "compartments do not overlap")
		previous_bow_edge = room.centre.x + room.half.x
	}

	// A compartment's length follows its slot size, so size reads off the room.
	medium, _ := galleon_room_for_slot(rooms, n, 4)
	small, _ := galleon_room_for_slot(rooms, n, 5)
	testing.expect(t, medium.half.x > small.half.x, "a Medium hold claims more of the floor than a Small")
}

@(test)
exposed_berths_become_the_weather_deck_structures :: proc(t: ^testing.T) {
	layout := test_layout()
	rooms, n := galleon_rooms(layout[:])

	// Taken in layout order: sterncastle, the poop above it, the open waist, the forecastle.
	kinds := [4]Room_Kind{.Sterncastle, .Poop, .Waist, .Forecastle}
	for kind, i in kinds {
		room, placed := galleon_room_for_slot(rooms, n, ship.Slot_Index(i))
		testing.expectf(t, placed, "exposed berth %d is placed", i)
		testing.expect_value(t, room.kind, kind)
		testing.expect(t, room.centre.y > GALLEON_DECK_Y, "a weather-deck structure stands above the deck")
	}

	sterncastle, _ := galleon_room_for_slot(rooms, n, 0)
	poop, _ := galleon_room_for_slot(rooms, n, 1)
	waist, _ := galleon_room_for_slot(rooms, n, 2)
	forecastle, _ := galleon_room_for_slot(rooms, n, 3)
	testing.expect(t, poop.centre.y > sterncastle.centre.y, "the poop deck rides above the sterncastle")
	testing.expect(t, forecastle.centre.x > waist.centre.x, "the forecastle is forward of the waist")
	testing.expect(t, waist.centre.x > sterncastle.centre.x, "the waist is forward of the sterncastle")
}

@(test)
pointing_into_a_room_picks_its_slot :: proc(t: ^testing.T) {
	layout := test_layout()
	view := galleon_view(FRAME_W, FRAME_H)
	rooms, n := galleon_rooms(layout[:])

	// The centre of every drawn opening picks that opening's berth — the one-answer property
	// the module exists for, now in three dimensions.
	for i in 0 ..< n {
		face := galleon_room_face(rooms[i], view)
		centre := galleon_face_centre(face)
		hit, over := galleon_room_at(layout[:], centre, view).?
		testing.expectf(t, over, "the centre of room %d's open face is over a slot", i)
		if over {
			testing.expect_value(t, hit, rooms[i].slot)
		}
	}

	// The top-left corner is open sky, over nothing.
	_, over := galleon_room_at(layout[:], rl.Vector2{2, 2}, view).?
	testing.expect(t, !over, "a point off the ship picks no slot")
}

@(test)
picking_projects_against_the_logical_frame_it_is_given :: proc(t: ^testing.T) {
	// The live build renders 1244x700 into a texture and blits it to a larger fullscreen
	// surface, so picking must project against the size it is handed rather than a window's.
	// The camera's own target lands at the centre of whatever frame the view was built at.
	for frame in ([2][2]i32{{FRAME_W, FRAME_H}, {2 * FRAME_W, 2 * FRAME_H}}) {
		view := galleon_view(frame.x, frame.y)
		centre := galleon_project(view.camera.target, view)
		testing.expectf(t, abs(centre.x - f32(frame.x) / 2) < 1, "target is centred across %v", frame)
		testing.expectf(t, abs(centre.y - f32(frame.y) / 2) < 1, "target is centred down %v", frame)
	}

	// And the same room, projected into a frame twice the size, lands twice as far out.
	layout := test_layout()
	rooms, n := galleon_rooms(layout[:])
	testing.expect(t, n > 0, "the test ship places rooms")
	small := galleon_room_face(rooms[0], galleon_view(FRAME_W, FRAME_H))
	large := galleon_room_face(rooms[0], galleon_view(2 * FRAME_W, 2 * FRAME_H))
	testing.expect(t, abs(large[0].x - 2 * small[0].x) < 1, "a doubled frame doubles the projection")
}

@(test)
the_sea_horizon_meets_the_cameras_true_horizon :: proc(t: ^testing.T) {
	// The camera sits at the waterline looking up, so its true horizon falls well below the
	// middle of the frame — and the whole ship must ride above it, or the sea would be drawn
	// slicing through the deck.
	view := galleon_view(FRAME_W, FRAME_H)
	horizon := galleon_horizon_y(view)
	testing.expect(t, horizon > FRAME_H / 2, "an upward-tilted camera puts its horizon below frame centre")

	// The horizon crosses the hull between the keel and the deck: the ship rides high, with the
	// sea meeting its lower planking and no horizon line drawn through the weather deck.
	for x := GALLEON_STERN_X; x <= GALLEON_BOW_X; x += 0.25 {
		deck := galleon_project(rl.Vector3{x, galleon_sheer_y(x), -GALLEON_HALF_BEAM}, view)
		keel := galleon_project(rl.Vector3{x, galleon_keel_y(x), -GALLEON_HALF_BEAM}, view)
		testing.expectf(t, deck.y < horizon, "the deck rides above the horizon at x=%.2f", x)
		testing.expectf(t, keel.y > horizon, "the hull's bottom falls below the horizon at x=%.2f", x)
	}

	// Every weather-deck structure stands clear of the sea line; the holds are in the belly and
	// are meant to sit under it.
	layout := test_layout()
	rooms, n := galleon_rooms(layout[:])
	for i in 0 ..< n {
		if rooms[i].kind == .Hold {
			continue
		}
		for corner in galleon_room_face(rooms[i], view) {
			testing.expectf(t, corner.y < horizon, "room %d's opening rides above the horizon", i)
		}
	}
}
