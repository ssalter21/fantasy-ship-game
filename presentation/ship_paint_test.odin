package presentation

import "core:testing"
import rl "vendor:raylib"

// What the normal-paint row has to be able to say. The sheet photographs it (hull_sheet.odin);
// this is the arithmetic underneath, which is the part that can be checked without a window.

// The defect the row exists for: a surface wound the wrong way round. Shaded, it is invisible —
// every surface here is lit from whichever side the eye is on, so a reversed winding paints the
// identical colour — which is why looking harder at the shaded row can never find it.
@(test)
a_face_wound_backwards_is_a_wrong_colour_only_in_normal_paint :: proc(t: ^testing.T) {
	// The game must draw the same frame whether or not the hull tools exist, so the paint standing
	// when nothing has set it is the shipped shading. Asserted here rather than beside the
	// workbench's other inert-hook checks because this is the only test that moves the mode, and
	// the runner is threaded — a second test reading it could read this one's.
	testing.expect_value(t, ship_debug_paint, Ship_Paint.Shaded)

	// One flat quad on her deck, wound so that its own normal points up out of the deck, and the
	// same four corners taken the other way round.
	corners := [4]rl.Vector3{{-1, 1, -1}, {-1, 1, 1}, {1, 1, 1}, {1, 1, -1}}
	centre := (corners[0] + corners[2]) / 2
	right := rl.Vector3CrossProduct(corners[1] - corners[0], corners[2] - corners[0])
	backwards := rl.Vector3CrossProduct(corners[2] - corners[0], corners[1] - corners[0])

	ship_paint_view(rl.Camera3D{position = {6, 4, 6}})
	timber := COLOUR_CLIFF
	testing.expect_value(
		t,
		ship_lit(timber, ship_facing(centre, backwards)),
		ship_lit(timber, ship_facing(centre, right)),
	)

	// Under normal paint the surface keeps its own outward normal, so the two read as opposite
	// colours — a bright face against a dark one, at a glance, in the same frame.
	ship_debug_paint = .Normals
	defer ship_debug_paint = .Shaded
	wrong := ship_lit(timber, ship_facing(centre, backwards))
	well := ship_lit(timber, ship_facing(centre, right))
	testing.expectf(
		t,
		wrong != well,
		"a reversed face should paint a different colour, not %v twice",
		well,
	)
	testing.expect(t, well.g > wrong.g, "a face pointing up should be the brighter green of the two")
}
