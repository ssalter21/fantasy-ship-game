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

	start, heading_out, _ := sail_ship_pose(positions, lo, hi, 0)
	testing.expect_value(t, start, positions[lo])
	testing.expect_value(t, heading_out, Ship_Heading.E)

	end, _, _ := sail_ship_pose(positions, lo, hi, 1)
	testing.expect_value(t, end, positions[hi])

	// Midpoints coincide: the same physical point on the same drawn curve.
	mid_out, _, _ := sail_ship_pose(positions, lo, hi, 0.5)
	mid_back, heading_back, _ := sail_ship_pose(positions, hi, lo, 0.5)
	testing.expect_value(t, mid_out, mid_back)
	testing.expect_value(t, heading_back, Ship_Heading.W)

	back_start, _, _ := sail_ship_pose(positions, hi, lo, 0)
	testing.expect_value(t, back_start, positions[hi])
}

@(test)
spume_flecks_are_thrown_along_the_leg_and_all_fade_out :: proc(t: ^testing.T) {
	// A fleck doesn't exist before its moment, is freshest the instant it leaves the bow, and is
	// gone a fixed part of the leg later — the spume must never outlast the sail as a mark on the
	// page (spec §6: the solid wake is the only lasting line).
	_, _, alive_early := spume_fleck(8, 0.1)
	testing.expect(t, !alive_early)

	spawn, age, alive := spume_fleck(8, 0.5)
	testing.expect_value(t, spawn, 0.5)
	testing.expect_value(t, age, 0)
	testing.expect(t, alive)

	_, mid_age, still_alive := spume_fleck(8, 0.5 + SPUME_LIFE / 2)
	testing.expect_value(t, mid_age, 0.5)
	testing.expect(t, still_alive)

	_, _, expired := spume_fleck(8, 0.5 + SPUME_LIFE)
	testing.expect(t, !expired)

	// The skip forces progress to 1 on its own frame. Everything thrown before the leg's final
	// stretch is already gone by then, so a skipped sail lands on near-clear water rather than
	// under the whole leg's foam arriving at once.
	for i in 0 ..< SPUME_FLECKS / 2 {
		_, _, hanging := spume_fleck(i, 1)
		testing.expect(t, !hanging)
	}
}

@(test)
ship_rocks_gently_and_never_stops :: proc(t: ^testing.T) {
	// Swell, not jitter: the bob and heel stay inside their dials at every moment, and a moored
	// ship rocks less than one under way.
	for step in 0 ..< 40 {
		time := f64(step) * 0.1
		sail_bob, sail_heel := ship_rock(time, true)
		idle_bob, idle_heel := ship_rock(time, false)
		testing.expect(t, abs(sail_bob) <= SHIP_BOB_SAILING)
		testing.expect(t, abs(sail_heel) <= SHIP_HEEL_SAILING)
		testing.expect(t, abs(idle_bob) <= SHIP_BOB_IDLE)
		testing.expect(t, abs(idle_heel) <= SHIP_HEEL_IDLE)
	}

	// The idle rock is driven by the wall clock, not the sail, so it is still moving well after a
	// sail has ended — a hull that froze on arrival would read as pasted on.
	moored_now, _ := ship_rock(0, false)
	moored_later, _ := ship_rock(f64(SHIP_BOB_PERIOD_IDLE) / 4, false)
	testing.expect(t, moored_now != moored_later)
}

@(test)
ship_leans_into_the_bend_and_rights_itself_at_both_ends :: proc(t: ^testing.T) {
	// A ship stands upright as it leaves and as it lands, and is at its fullest lean mid-leg.
	east := rl.Vector2{1, 0}
	turning_south := rl.Vector2{0, 1} // heading east, bending downward: a clockwise turn

	testing.expect_value(t, heel_into_turn(east, turning_south, 0), 0)
	testing.expect_value(t, heel_into_turn(east, turning_south, 1), 0)
	testing.expect_value(t, heel_into_turn(east, turning_south, 0.5), SHIP_HEEL_INTO_TURN)

	// Raylib rotates clockwise on a positive angle and chart space is screen space, so a
	// clockwise bend leans positive and the mirrored bend leans the other way by the same amount.
	testing.expect_value(
		t,
		heel_into_turn(east, rl.Vector2{0, -1}, 0.5),
		-SHIP_HEEL_INTO_TURN,
	)

	// A ruled-straight leg (no bend) and a stationary tangent both leave the hull upright rather
	// than picking a side.
	testing.expect_value(t, heel_into_turn(east, rl.Vector2{0, 0}, 0.5), 0)
	testing.expect_value(t, heel_into_turn(rl.Vector2{0, 0}, turning_south, 0.5), 0)
}

@(test)
arrival_ink_bloom_spreads_then_expires_on_its_own :: proc(t: ^testing.T) {
	// The ripple starts at the mark at full ink and thins as it widens.
	spread_at_start, alpha_at_start, alive := ink_bloom_phase(100, 100)
	testing.expect_value(t, spread_at_start, 0)
	testing.expect_value(t, alpha_at_start, 1)
	testing.expect(t, alive)

	mid_spread, mid_alpha, mid_alive := ink_bloom_phase(100 + INK_BLOOM_LIFE / 2, 100)
	testing.expect(t, mid_alive)
	testing.expect(t, mid_spread > 0.5) // eased out: fast into the paper, slowing as it sets
	testing.expect_value(t, mid_alpha, 0.5)

	// Nothing clears the field, so an old landing must expire by age alone — otherwise a stale
	// bloom would sit on the chart for the rest of the voyage.
	_, _, expired := ink_bloom_phase(100 + INK_BLOOM_LIFE, 100)
	testing.expect(t, !expired)
	_, _, long_expired := ink_bloom_phase(3600, 100)
	testing.expect(t, !long_expired)
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
