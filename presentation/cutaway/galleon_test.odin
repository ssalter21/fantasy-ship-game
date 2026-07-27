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
the_shipped_view_is_the_shipped_eye :: proc(t: ^testing.T) {
	// galleon_view_from exists so the hull workbench can fly the camera; the game's own framing
	// must not become a thing a tool can move. These two are the same view, and that is what
	// keeps the five tuned knobs the single account of how this screen is composed.
	from_knobs := galleon_view_from(GALLEON_EYE, FRAME_W, FRAME_H)
	testing.expect_value(t, galleon_view(FRAME_W, FRAME_H), from_knobs)
}

@(test)
projecting_through_the_carried_matrix_is_raylibs_own_answer :: proc(t: ^testing.T) {
	// galleon_project stopped asking rl.GetWorldToScreenEx when the View started carrying its
	// projection (#476) — a blended projection is not a thing a camera can describe, so the
	// matrix had to come out of the camera and into the view. The arithmetic is otherwise
	// raylib's, and this is what says so: for an ordinary perspective view the two agree, so
	// nothing on the shipped ship screen moved by a pixel when the seam opened.
	view := galleon_view(FRAME_W, FRAME_H)
	probes := [?]rl.Vector3 {
		{GALLEON_BOW_X, 0, 0},
		{GALLEON_STERN_X, GALLEON_DECK_Y, -GALLEON_HALF_BEAM},
		{0, GALLEON_KEEL_Y, GALLEON_HALF_BEAM},
		{0.2, 3.9, 0},
	}
	for probe in probes {
		mine := galleon_project(probe, view)
		raylibs := rl.GetWorldToScreenEx(probe, view.camera, view.width, view.height)
		testing.expectf(
			t,
			abs(mine.x - raylibs.x) < 0.01 && abs(mine.y - raylibs.y) < 0.01,
			"%v projects to %v, raylib says %v",
			probe,
			mine,
			raylibs,
		)
	}
}

@(test)
the_alongside_framing_is_orthographic_and_level :: proc(t: ^testing.T) {
	// The invariant galleon_view_from asserts, held as a fact about the shipped stage framing:
	// an orthographic camera whose axis is not horizontal has a water plane with no edge at all,
	// so the eye that presents her broadside must look dead level.
	testing.expect_value(t, GALLEON_ALONGSIDE_EYE.height, GALLEON_ALONGSIDE_EYE.look)
	testing.expect(t, GALLEON_ALONGSIDE_EYE.ortho > 0, "the alongside framing is orthographic")

	view := galleon_view_from(GALLEON_ALONGSIDE_EYE, FRAME_W, FRAME_H)
	testing.expect_value(t, view.camera.projection, rl.CameraProjection.ORTHOGRAPHIC)
	testing.expect_value(t, view.camera.position.y, view.camera.target.y)

	// The pan slides the eye and its target together, so the view direction is untouched: a
	// broadside stays a broadside however far she slides out of frame centre.
	unpanned := GALLEON_ALONGSIDE_EYE
	unpanned.pan = 0
	plain := galleon_view_from(unpanned, FRAME_W, FRAME_H)
	moved := view.camera.position - plain.camera.position
	testing.expect(t, rl.Vector3Length(moved) > 0.5, "the pan actually moves the eye")
	testing.expect_value(t, view.camera.target - plain.camera.target, moved)
}

@(test)
an_orthographic_sea_lands_on_one_screen_row :: proc(t: ^testing.T) {
	// What the horizontal-view-axis invariant buys: with the plane exactly edge-on, world y maps
	// linearly to screen y and *every* point at y = 0 lands on the same row, whatever its length
	// or beam. That row is the sea's edge, and it is the only reason this framing has one.
	view := galleon_view_from(GALLEON_ALONGSIDE_EYE, FRAME_W, FRAME_H)
	horizon := galleon_horizon_y(view)
	for x := GALLEON_STERN_X - 200; x <= GALLEON_BOW_X + 200; x += 47 {
		for z in ([3]f32{-400, 0, 400}) {
			landed := galleon_project(rl.Vector3{x, 0, z}, view).y
			testing.expectf(t, abs(landed - horizon) < 0.01, "y=0 at (%.0f, %.0f) lands at %.2f, not %.2f", x, z, landed, horizon)
		}
	}

	// And she floats in it: the sea's edge crosses her between the keel and the weather deck.
	for x := GALLEON_STERN_X; x <= GALLEON_BOW_X; x += 0.25 {
		deck := galleon_project(rl.Vector3{x, galleon_sheer_y(x), -GALLEON_HALF_BEAM}, view)
		keel := galleon_project(rl.Vector3{x, galleon_keel_y(x), -GALLEON_HALF_BEAM}, view)
		testing.expectf(t, deck.y < horizon, "the deck rides above the sea line at x=%.2f", x)
		testing.expectf(t, keel.y > horizon, "the hull's bottom falls below the sea line at x=%.2f", x)
	}
}

@(test)
an_orthographic_room_opening_is_a_true_rectangle :: proc(t: ^testing.T) {
	// The point of choosing orthographic over a side-on perspective camera: with no convergence
	// anywhere, every bulkhead is square however far off-axis she sits. A perspective camera is
	// square only near frame centre, and this framing pans her a long way off it.
	layout := test_layout()
	view := galleon_view_from(GALLEON_ALONGSIDE_EYE, FRAME_W, FRAME_H)
	rooms, n := galleon_rooms(layout[:])
	for i in 0 ..< n {
		face := galleon_room_face(rooms[i], view)
		// Corners come back aft-floor, fore-floor, fore-head, aft-head.
		testing.expectf(t, abs(face[0].y - face[1].y) < 0.01, "room %d's sill is level", i)
		testing.expectf(t, abs(face[2].y - face[3].y) < 0.01, "room %d's header is level", i)
		testing.expectf(t, abs(face[0].x - face[3].x) < 0.01, "room %d's after post is plumb", i)
		testing.expectf(t, abs(face[1].x - face[2].x) < 0.01, "room %d's forward post is plumb", i)
	}
}

@(test)
pointing_into_a_room_picks_its_slot_alongside_too :: proc(t: ^testing.T) {
	// The one-answer property has to survive the second framing, or a drop lands in a berth the
	// player was not pointing at. Same assertion as the moored case, through the panned
	// orthographic view an Offer or Shop presents her under.
	layout := test_layout()
	view := galleon_view_from(GALLEON_ALONGSIDE_EYE, FRAME_W, FRAME_H)
	rooms, n := galleon_rooms(layout[:])
	for i in 0 ..< n {
		centre := galleon_face_centre(galleon_room_face(rooms[i], view))
		hit, over := galleon_room_at(layout[:], centre, view).?
		testing.expectf(t, over, "the centre of room %d's open face is over a slot", i)
		if over {
			testing.expect_value(t, hit, rooms[i].slot)
		}
	}
}

@(test)
the_travel_between_two_framings_is_exact_at_both_ends :: proc(t: ^testing.T) {
	// A move that does not arrive at the shipped framing is a pop at whichever end it misses, so
	// both ends are the framings themselves and not an approximation of them.
	a, b := GALLEON_EYE, GALLEON_ALONGSIDE_EYE
	testing.expect_value(t, galleon_view_between(a, b, 0, FRAME_W, FRAME_H), galleon_view_from(a, FRAME_W, FRAME_H))
	testing.expect_value(t, galleon_view_between(a, b, 1, FRAME_W, FRAME_H), galleon_view_from(b, FRAME_W, FRAME_H))

	// And in between the camera really travels: monotonically along every knob that differs, so
	// nothing doubles back part-way through the swing.
	previous := galleon_view_between(a, b, 0, FRAME_W, FRAME_H)
	for step in 1 ..= 10 {
		k := f32(step) / 10
		view := galleon_view_between(a, b, k, FRAME_W, FRAME_H)
		testing.expectf(t, view.camera.position.y >= previous.camera.position.y, "the eye rises through k=%.1f", k)
		previous = view
	}

	// The projection is blended rather than switched: half-way along, the matrix sits between the
	// two and is neither. A switch at the end is what makes every bulkhead straighten in one frame.
	half := galleon_view_between(a, b, 0.5, FRAME_W, FRAME_H)
	perspective := galleon_view_from(a, FRAME_W, FRAME_H).projection
	orthographic := galleon_view_from(b, FRAME_W, FRAME_H).projection
	// Row 3 is the divide: `0 0 -1 0` under perspective, `0 0 0 1` under orthographic.
	testing.expect(t, half.projection[3, 2] > perspective[3, 2] && half.projection[3, 2] < orthographic[3, 2], "the divide by -z fades")
	testing.expect(t, half.projection[3, 3] > perspective[3, 3] && half.projection[3, 3] < orthographic[3, 3], "and the constant w comes in")
}

@(test)
every_room_stands_inside_her_planking :: proc(t: ^testing.T) {
	// A compartment that reaches wider than the frames around it stands *through* the hull, and
	// what that draws is a hole in her side — which is exactly what a room sized to one width
	// did at the bow and the quarter. Every station of every room is checked against the frame
	// it stands in, at the floor, where those frames are tightest.
	layout := test_layout()
	rooms, n := galleon_rooms(layout[:])
	for i in 0 ..< n {
		room := rooms[i]
		floor := room.centre.y - room.half.y
		testing.expectf(t, room.half_aft > 0 && room.half_fore > 0, "room %d has both ends", i)
		for k in 0 ..= 8 {
			x := room.centre.x + (f32(k) / 8 * 2 - 1) * room.half.x
			reach := abs(room.centre.z) + galleon_room_half_z(room, x)
			testing.expectf(
				t,
				reach <= galleon_frame_half_beam(x, floor) + 0.001,
				"room %d reaches %.3f at x=%.2f, where her frame carries %.3f",
				i,
				reach,
				x,
				galleon_frame_half_beam(x, floor),
			)
		}
	}

	// And her hold deck stays inside her bottom: a flat floor carried past the point where the
	// rising floors meet it comes out through the planking under her bow.
	for i in 0 ..< n {
		if rooms[i].kind != .Hold {
			continue
		}
		for x in ([2]f32{rooms[i].centre.x - rooms[i].half.x, rooms[i].centre.x + rooms[i].half.x}) {
			testing.expectf(t, galleon_keel_y(x) < GALLEON_HOLD_FLOOR_Y, "the hold floor rides above the keel at x=%.2f", x)
		}
	}
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
