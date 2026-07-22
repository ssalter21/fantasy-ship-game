#+private
package presentation

import "core:math"
import voyage "../core/voyage"
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

// sail_ship_pose is where the sprite sits, which way it faces, and how far it is leaning at a
// given eased progress along the leg from→to: a point on the drawn route, the curve's tangent
// there snapped to eight directions, and the heel that tangent's bend calls for. The tangent is
// flipped on a backwards leg so the bow points at the destination rather than the origin.
sail_ship_pose :: proc(
	positions: []rl.Vector2,
	from, to: voyage.Node_ID,
	eased: f32,
) -> (
	pos: rl.Vector2,
	heading: Ship_Heading,
	lean: f32,
) {
	a, c, b, forward := sail_leg_curve(positions, from, to)
	t := sail_curve_t(eased, forward)
	tangent := bezier_tangent(a, c, b, t)
	if !forward {
		tangent = -tangent
	}
	lean = heel_into_turn(tangent, bezier_accel(a, c, b), eased)
	return bezier_quad(a, c, b, t), heading_from_tangent(tangent), lean
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

// ---- Travel juice (spec 0001 §6) ----
//
// The polish layered over the locked sail: spume off the bow, a hull that lives in the water,
// and an ink bloom where it lands. All of it is transient by construction — the solid sepia wake
// stays the only lasting line on the page — so none of it owns a particle list or a per-frame
// tick. Each effect is a pure function of a number the sail already carries (raw progress) or of
// the wall clock, which means draw_map can ask for it and nothing has to remember it.

// SPUME_FLECKS is how many foam flecks a leg throws off the bow, and SPUME_LIFE how long one
// drifts before it has faded out — as a fraction of the leg, not seconds, so the whole spume is a
// pure function of the sail's raw progress. That framing also means the skip clears the water
// instantly instead of leaving foam hanging over the arrival. Both are the spec's density dial,
// set by eye: enough flecks that the bow throws water, few enough that the page stays a chart.
SPUME_FLECKS :: 16
SPUME_LIFE :: f32(0.5)

// spume_fleck is fleck i's schedule at raw sail progress: where along the leg it left the bow and
// how far through its life it is — 0 the moment it is thrown, 1 when it has faded to nothing.
// Flecks spawn evenly along the leg so the bow sheds water at a steady rate; `alive` is false
// before its moment and after it is gone.
spume_fleck :: proc(i: int, progress: f32) -> (spawn, age: f32, alive: bool) {
	spawn = f32(i) / f32(SPUME_FLECKS)
	age = (progress - spawn) / SPUME_LIFE
	return spawn, age, age >= 0 && age < 1
}

// The sprite's life dials (spec §6): swell, not jitter. Bob is pixels of vertical rise on the
// 32px sprite, heel degrees of roll, and the periods are deliberately mismatched between the two
// so the vessel breathes rather than pumping to one metronome. A ship under way works harder and
// faster than one moored, so sailing gets the bigger, quicker figures.
SHIP_BOB_SAILING :: f32(2)
SHIP_BOB_IDLE :: f32(1)
SHIP_BOB_PERIOD_SAILING :: f32(0.8)
SHIP_BOB_PERIOD_IDLE :: f32(2.4)
SHIP_HEEL_SAILING :: f32(2.5)
SHIP_HEEL_IDLE :: f32(1.25)

// SHIP_HEEL_INTO_TURN is the degrees a ship leans into a bend at the middle of a leg, on top of
// the swell — the roll that says the hull is being carried through the turn rather than slid
// along it.
SHIP_HEEL_INTO_TURN :: f32(6)

// ship_rock is the sprite's swell at a moment: vertical bob in pixels and heel in degrees, an
// overlay on the baked 8-way frame that leaves the heading snap alone. `time` is wall-clock
// seconds, so the idle rock keeps running while the ship is moored — the sail's own progress
// stops at arrival, and a hull that froze the instant it landed would read as pasted on. Pure in
// its clock so the shape of the motion is testable without one.
ship_rock :: proc(time: f64, sailing: bool) -> (bob, heel: f32) {
	t := f32(time)
	bob_amp := sailing ? SHIP_BOB_SAILING : SHIP_BOB_IDLE
	heel_amp := sailing ? SHIP_HEEL_SAILING : SHIP_HEEL_IDLE
	period := sailing ? SHIP_BOB_PERIOD_SAILING : SHIP_BOB_PERIOD_IDLE

	bob = math.sin(t * 2 * math.PI / period) * bob_amp
	heel = math.cos(t * 2 * math.PI / (period * 1.6)) * heel_amp
	return
}

// bezier_accel is the quadratic bezier's second derivative. It is constant over the curve, which
// is why a leg bends one way for its whole length and the ship's lean never flips mid-sail.
bezier_accel :: proc(a, c, b: rl.Vector2) -> rl.Vector2 {
	return 2 * (a - 2 * c + b)
}

// heel_into_turn is the steady lean a hull carries through a bend: the sign of the turn — where
// the ship is heading crossed with how that heading is changing — leaned by SHIP_HEEL_INTO_TURN,
// swelling in and out over the leg so the vessel rolls up as it leaves and rights itself as it
// lands. Chart space is screen space, so a positive cross product is a clockwise turn and raylib
// rotates clockwise on a positive angle: the sign carries straight through. A straight leg (no
// bend, or the degenerate zero tangent at a stationary endpoint) leans not at all.
//
// The swell is a parabola rather than a sine hump for the same reason sail_ease is fixed at its
// endpoints: it is exactly 0 at both, so a ship moored on a node is exactly upright instead of
// heeled by the last float ulp of sin(π).
heel_into_turn :: proc(tangent, accel: rl.Vector2, eased: f32) -> f32 {
	turn := tangent.x * accel.y - tangent.y * accel.x
	if turn == 0 {
		return 0
	}
	e := clamp(eased, 0, 1)
	lean := SHIP_HEEL_INTO_TURN * 4 * e * (1 - e)
	return turn > 0 ? lean : -lean
}

// Ink_Bloom is an arrival's sepia ripple: the node the ship landed on and the wall-clock second
// it landed. Started rather than remaining, so nothing has to tick it down — the bloom outlives
// the frame that set it and expires on its own age.
Ink_Bloom :: struct {
	node:    voyage.Node_ID,
	started: f64,
}

// INK_BLOOM_LIFE is how long the arrival ripple takes to spread and fade (spec §6), and
// INK_BLOOM_REACH how far past the node's own radius it reaches at full spread.
INK_BLOOM_LIFE :: f64(0.6)
INK_BLOOM_REACH :: f32(22)

// ink_bloom_phase is the ripple's state at `now`: how far it has spread from the node (0 at the
// mark, 1 at full reach) and how much ink is left in it. The spread eases *out* — the ink runs
// fast into the paper and slows as it sets — while the alpha drains evenly, so the ring thins as
// it widens instead of vanishing at a stroke.
ink_bloom_phase :: proc(now, started: f64) -> (spread, alpha: f32, alive: bool) {
	age := f32((now - started) / INK_BLOOM_LIFE)
	if age < 0 || age >= 1 {
		return 0, 0, false
	}
	return 1 - (1 - age) * (1 - age), 1 - age, true
}
