package main

import "core:math"
import voyage "../../core/voyage"
import rl "vendor:raylib"

// SAIL_DURATION is the seconds a leg takes end to end (spec §5): snappy enough that travel never
// reads as a wait, long enough that the ship leaving one node and reaching another is a motion the
// eye follows.
SAIL_DURATION :: f32(0.5)

// sail_advance steps a sail's raw progress one frame toward arrival, clamped at 1. dt is a
// parameter rather than an rl.GetFrameTime() read inside so the tween is a pure function of its
// inputs — home_loop supplies the frame time, tests supply their own.
sail_advance :: proc(progress, dt: f32) -> f32 {
	return min(progress + dt / SAIL_DURATION, 1)
}

// sail_ease maps raw progress to the eased position along the leg: smoothstep, so the ship leans
// out of the node it leaves and settles into the one it reaches instead of starting and stopping
// at full speed (spec §5, weighted at both ends). Fixed at the endpoints, so arrival and departure
// land exactly on their nodes.
sail_ease :: proc(progress: f32) -> f32 {
	p := clamp(progress, 0, 1)
	return p * p * (3 - 2 * p)
}

// bezier_tangent is the derivative of the quadratic bezier a→c→b at t — the direction the curve is
// heading there, which is what the sprite's 8-way heading snaps to. Unnormalised: only its
// direction is read.
bezier_tangent :: proc(a, c, b: rl.Vector2, t: f32) -> rl.Vector2 {
	return 2 * (1 - t) * (c - a) + 2 * t * (b - c)
}

// heading_from_tangent snaps a direction to the nearest of the sprite's eight baked headings.
// Chart space is screen space (y grows downward), so north is -y and the angle is measured
// clockwise from it — the same order the strip's columns run in. A zero tangent (degenerate leg)
// keeps the resting heading rather than picking an arbitrary column.
heading_from_tangent :: proc(tangent: rl.Vector2) -> Ship_Heading {
	if tangent.x == 0 && tangent.y == 0 {
		return SHIP_REST_HEADING
	}
	clockwise_from_north := math.atan2(tangent.x, -tangent.y)
	octant := int(math.round(clockwise_from_north / (math.PI / 4)))
	return Ship_Heading((octant %% 8))
}

// sail_leg_curve returns the leg from→to as the very curve draw_map strokes for that edge, plus
// the direction the ship rides it. Routes are drawn once per undirected pair, low id first, and
// route_control's bow flips sign when the endpoints swap — so the curve is fetched in the drawn
// order and `forward` carries which way along it the ship is going.
sail_leg_curve :: proc(
	positions: []rl.Vector2,
	from, to: voyage.Node_ID,
) -> (
	a, c, b: rl.Vector2,
	forward: bool,
) {
	forward = from < to
	lo, hi := from, to
	if !forward {
		lo, hi = to, from
	}
	a, b = positions[lo], positions[hi]
	c = route_control(a, b)
	return
}

// sail_curve_t converts eased progress along the leg into the curve's own parameter, which runs
// low id → high id. A ship sailing the edge backwards walks that parameter down from 1.
sail_curve_t :: proc(eased: f32, forward: bool) -> f32 {
	return forward ? eased : 1 - eased
}

// sail_ship_pose is where the sprite sits and which way it faces at a given eased progress along
// the leg from→to: a point on the drawn route, and the curve's tangent there snapped to eight
// directions. The tangent is flipped on a backwards leg so the bow points at the destination
// rather than the origin.
sail_ship_pose :: proc(
	positions: []rl.Vector2,
	from, to: voyage.Node_ID,
	eased: f32,
) -> (
	pos: rl.Vector2,
	heading: Ship_Heading,
) {
	a, c, b, forward := sail_leg_curve(positions, from, to)
	t := sail_curve_t(eased, forward)
	tangent := bezier_tangent(a, c, b, t)
	if !forward {
		tangent = -tangent
	}
	return bezier_quad(a, c, b, t), heading_from_tangent(tangent)
}

// draw_sail_leg strokes the leg under way with its wake filling in as the ship passes (spec §5):
// the stretch already crossed inks solid sepia, the stretch ahead stays the sailable dash. `t` is
// the ship's position in the curve's own low→high parameter and `forward` which side of it is
// behind the ship, so the fill works on a leg ridden in either direction.
draw_sail_leg :: proc(a, b: rl.Vector2, t: f32, forward: bool) {
	SEGS :: 18
	c := route_control(a, b)
	prev := a
	for s in 1 ..= SEGS {
		u := f32(s) / f32(SEGS)
		pt := bezier_quad(a, c, b, u)
		passed := forward ? u <= t : u >= t
		if passed || s % 2 == 1 {
			rl.DrawLineEx(prev, pt, 3, INK_SEPIA)
		}
		prev = pt
	}
}

// edge_is_sail_leg reports whether the undirected edge (a, b) is the leg currently being sailed.
edge_is_sail_leg :: proc(a, b, from, to: voyage.Node_ID) -> bool {
	return (a == from && b == to) || (a == to && b == from)
}
