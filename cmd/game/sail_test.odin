package main

import "core:testing"
import voyage "../../core/voyage"
import rl "vendor:raylib"

// The sail phase's pure half (spec 0001 §5): the tween, the 8-way heading snap, and the
// skip. The drawing half can't be tested here — rl.IsWindowReady() is false under `odin test`
// — so these cover the procs home_loop and draw_map read their motion from.

@(test)
sail_tween_runs_from_rest_to_arrival_and_stops_there :: proc(t: ^testing.T) {
	// Endpoints are exact: a leg must start on its origin node and land on its destination,
	// never near them, or the ship would visibly jump on arrival.
	testing.expect_value(t, sail_ease(0), 0)
	testing.expect_value(t, sail_ease(1), 1)

	// One SAIL_DURATION of frame time carries raw progress exactly to arrival, and further
	// frames clamp there rather than overshooting.
	progress := f32(0)
	progress = sail_advance(progress, SAIL_DURATION / 2)
	testing.expect_value(t, progress, 0.5)
	progress = sail_advance(progress, SAIL_DURATION / 2)
	testing.expect_value(t, progress, 1)
	testing.expect_value(t, sail_advance(progress, SAIL_DURATION), 1)

	// Eased midpoint sits at the halfway mark, and the curve is monotone between the ends.
	testing.expect_value(t, sail_ease(0.5), 0.5)
	testing.expect(t, sail_ease(0.25) < sail_ease(0.5) && sail_ease(0.5) < sail_ease(0.75))

	// Smoothstep leans out of and into the endpoints: slower than linear at both ends.
	testing.expect(t, sail_ease(0.1) < 0.1)
	testing.expect(t, sail_ease(0.9) > 0.9)
}

@(test)
sail_skip_snaps_progress_to_arrival :: proc(t: ^testing.T) {
	// home_loop's skip forces raw progress to 1; the eased position must land exactly on the
	// destination so a skipped sail is indistinguishable from a completed one.
	skipped := f32(1)
	testing.expect_value(t, sail_ease(skipped), 1)
	testing.expect_value(t, sail_curve_t(sail_ease(skipped), true), 1)
	testing.expect_value(t, sail_curve_t(sail_ease(skipped), false), 0)
}

@(test)
sail_heading_snaps_a_tangent_to_the_nearest_of_eight :: proc(t: ^testing.T) {
	// Chart space is screen space: -y is north. The eight cardinals must each land on their own
	// baked frame, or the hull faces the wrong way down a route.
	testing.expect_value(t, heading_from_tangent(rl.Vector2{0, -1}), Ship_Heading.N)
	testing.expect_value(t, heading_from_tangent(rl.Vector2{1, -1}), Ship_Heading.NE)
	testing.expect_value(t, heading_from_tangent(rl.Vector2{1, 0}), Ship_Heading.E)
	testing.expect_value(t, heading_from_tangent(rl.Vector2{1, 1}), Ship_Heading.SE)
	testing.expect_value(t, heading_from_tangent(rl.Vector2{0, 1}), Ship_Heading.S)
	testing.expect_value(t, heading_from_tangent(rl.Vector2{-1, 1}), Ship_Heading.SW)
	testing.expect_value(t, heading_from_tangent(rl.Vector2{-1, 0}), Ship_Heading.W)
	testing.expect_value(t, heading_from_tangent(rl.Vector2{-1, -1}), Ship_Heading.NW)

	// Off-axis tangents round to their nearest octant, and magnitude is irrelevant.
	testing.expect_value(t, heading_from_tangent(rl.Vector2{40, -3}), Ship_Heading.E)
	testing.expect_value(t, heading_from_tangent(rl.Vector2{3, -40}), Ship_Heading.N)

	// A degenerate leg leaves the ship at its moored heading rather than picking a frame at
	// random.
	testing.expect_value(t, heading_from_tangent(rl.Vector2{0, 0}), SHIP_REST_HEADING)
}

@(test)
sail_pose_rides_the_drawn_route_in_both_directions :: proc(t: ^testing.T) {
	// The sprite must ride the very curve draw_map strokes. Routes are drawn once per
	// undirected pair, low id first, so a leg sailed high→low walks the same curve backwards —
	// same points, opposite heading.
	positions := []rl.Vector2{{100, 400}, {300, 400}}
	lo, hi := voyage.Node_ID(0), voyage.Node_ID(1)

	start, heading_out := sail_ship_pose(positions, lo, hi, 0)
	testing.expect_value(t, start, positions[lo])
	testing.expect_value(t, heading_out, Ship_Heading.E)

	end, _ := sail_ship_pose(positions, lo, hi, 1)
	testing.expect_value(t, end, positions[hi])

	// Midpoints coincide: the same physical point on the same drawn curve.
	mid_out, _ := sail_ship_pose(positions, lo, hi, 0.5)
	mid_back, heading_back := sail_ship_pose(positions, hi, lo, 0.5)
	testing.expect_value(t, mid_out, mid_back)
	testing.expect_value(t, heading_back, Ship_Heading.W)

	back_start, _ := sail_ship_pose(positions, hi, lo, 0)
	testing.expect_value(t, back_start, positions[hi])
}

@(test)
sail_leg_matches_its_edge_in_either_orientation :: proc(t: ^testing.T) {
	// draw_map tests each undirected edge against the leg under way; the leg is the same edge
	// whichever end the ship started from.
	testing.expect(t, edge_is_sail_leg(2, 5, 2, 5))
	testing.expect(t, edge_is_sail_leg(2, 5, 5, 2))
	testing.expect(t, !edge_is_sail_leg(2, 6, 2, 5))
	testing.expect(t, !edge_is_sail_leg(3, 5, 2, 5))
}
