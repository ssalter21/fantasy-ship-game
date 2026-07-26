#+private
package presentation

import "core:math"
import cutaway "./cutaway"
import rl "vendor:raylib"

// The rig: three masts square-rigged, a bowsprit, and the standing rigging that holds the lot
// up. Three things here are doing the work that the first pass's flat boards could not.
//
// The canvas has a belly. A sail is not a rectangle — it is cut full and the wind puts a curve
// in it, and every strip of it faces a slightly different way. Drawn as a lofted surface of lit
// strips, the light runs across that curve and the sail turns from a card into cloth.
//
// The masts taper and rake. A mast is thickest at the partners and thinnest at the truck, and
// the three of them lean aft together; the tops are real platforms with rails.
//
// And there is rigging. Shrouds off each masthead down to the channels, ratlines across them,
// stays running forward: cordage is most of what the eye reads as "rig", and three bare poles
// with boards nailed on read as a raft with ideas.

// Mast is one of her three: where it steps along the keel, how tall, how many yards it crosses,
// and how far out the shrouds are set up on the channel below it.
Mast :: struct {
	x, height: f32,
	tiers:     int,
	spread:    f32,
}

// The rake: her masts lean aft as they climb, all by the same amount, which is what stops the
// rig reading as scaffolding standing on a boat.
RIG_RAKE :: f32(0.055)

// The wind: on the quarter, so the yards are braced round a touch and the canvas bellies
// forward. One number for the whole rig, so every sail draws the same way.
RIG_BELLY :: f32(0.19)

// SAIL_STRIPS is how many panels a sail's curve is lofted from. Enough to read as a curve, few
// enough to stay faceted — the same choice the hull's bands make.
SAIL_STRIPS :: 7

// rig_masts is her three lower masts, laid bow to stern: fore, main and mizzen.
rig_masts :: proc() -> [3]Mast {
	return [3]Mast {
		{x = 1.85, height = 3.1, tiers = 2, spread = 0.86},
		{x = 0.4, height = 3.9, tiers = 3, spread = 1.0},
		{x = -1.15, height = 2.8, tiers = 2, spread = 0.84},
	}
}

// rig_mast_point is a point on a mast at height h above the deck, carried aft by the rake.
rig_mast_point :: proc(mast: Mast, h: f32) -> rl.Vector3 {
	deck := cutaway.GALLEON_DECK_Y
	return rl.Vector3{mast.x - RIG_RAKE * h, deck + h, 0}
}

// draw_ship_rig raises the whole rig: masts and their tops, the yards and their canvas, the
// standing rigging, the bowsprit, and a pennant at every truck.
draw_ship_rig :: proc() {
	for mast in rig_masts() {
		draw_rig_mast(mast)
		draw_rig_shrouds(mast)
		draw_rig_canvas(mast)
	}
	draw_rig_stays()
	draw_rig_bowsprit()
}

// draw_rig_mast steps one mast: a lower mast tapering to the top, a topmast above it, the top
// itself — a real platform with a rail, where the first pass had a bare pole — and the pennant
// streaming off the truck.
draw_rig_mast :: proc(mast: Mast) {
	timber := colour_shade(COLOUR_TRUNK, 1.0)
	top_h := mast.height * 0.62

	ship_spar(rig_mast_point(mast, -0.1), rig_mast_point(mast, top_h), 0.075, 0.048, timber)
	ship_spar(rig_mast_point(mast, top_h - 0.1), rig_mast_point(mast, mast.height), 0.045, 0.026, colour_shade(timber, 1.1))

	// The top: a platform thrown out round the masthead, with a rail round its after edge.
	platform := rig_mast_point(mast, top_h)
	ship_box(platform, {0.34, 0.05, 0.52}, colour_shade(COLOUR_CLIFF, 0.92))
	ship_box({platform.x - 0.15, platform.y + 0.09, platform.z}, {0.04, 0.13, 0.52}, colour_shade(COLOUR_TRUNK, 0.9))

	// The pennant, streaming aft off the truck in three narrowing lengths.
	truck := rig_mast_point(mast, mast.height)
	for k in 0 ..< 3 {
		f := f32(k)
		ship_box(
			{truck.x - 0.14 - f * 0.19, truck.y + 0.06 - f * 0.03, 0},
			{0.19, 0.10 - f * 0.02, 0.02},
			k == 1 ? COLOUR_CREAM : COLOUR_SEA_DEEP,
		)
	}
}

// draw_rig_canvas hangs one mast's sails: a yard across each tier, and under it a course of
// canvas lofted with a belly in it. Each sail narrows as it climbs, so the rig comes to a point
// the way a square rig does, and the yards taper to their arms.
draw_rig_canvas :: proc(mast: Mast) {
	COURSE :: f32(1.72)
	tier_h := mast.height * 0.24

	for tier in 0 ..< mast.tiers {
		width := COURSE * mast.spread * (1.0 - f32(tier) / f32(mast.tiers) * 0.34)
		head := mast.height * 0.46 + f32(tier) * tier_h
		foot := head - tier_h * 0.82

		yard := rig_mast_point(mast, head)
		ship_spar({yard.x, yard.y, -width / 2 - 0.1}, {yard.x, yard.y, 0}, 0.02, 0.042, COLOUR_TRUNK)
		ship_spar({yard.x, yard.y, width / 2 + 0.1}, {yard.x, yard.y, 0}, 0.02, 0.042, COLOUR_TRUNK)

		draw_rig_sail(rig_mast_point(mast, head), rig_mast_point(mast, foot), width)
	}
}

// draw_rig_sail lofts one square sail between its yard and its foot. The belly is a bow across
// the sail's width, deepest amidships and pinned at the yardarms, and the foot hangs a touch
// deeper than the head — so the canvas is a curved surface, every strip of it facing its own
// way, and the light models the bag of wind in it. That, rather than any outline, is what makes
// it cloth.
draw_rig_sail :: proc(head, foot: rl.Vector3, width: f32) {
	// belly_at is how far forward the canvas is blown at a fraction f across the sail.
	belly_at :: proc(f: f32) -> f32 {
		return math.sin(f * math.PI)
	}

	for s in 0 ..< SAIL_STRIPS {
		f0 := f32(s) / SAIL_STRIPS
		f1 := f32(s + 1) / SAIL_STRIPS
		z0 := (f0 - 0.5) * width
		z1 := (f1 - 0.5) * width
		b0 := belly_at(f0) * RIG_BELLY
		b1 := belly_at(f1) * RIG_BELLY

		// The head is laced to the yard and can only bow a little; the foot is loose and bags.
		a := rl.Vector3{head.x + b0 * 0.55, head.y, z0}
		b := rl.Vector3{head.x + b1 * 0.55, head.y, z1}
		c := rl.Vector3{foot.x + b1, foot.y - b1 * 0.22, z1}
		d := rl.Vector3{foot.x + b0, foot.y - b0 * 0.22, z0}

		ship_quad_cloth(a, b, c, d, COLOUR_PARCHMENT)

		// A reef band across the canvas, a shade off it, so the cloth has a seam to catch light.
		mid_a := (a + d) / 2
		mid_b := (b + c) / 2
		band := rl.Vector3{0, 0.028, 0}
		ship_quad_cloth(mid_a - band, mid_b - band, mid_b + band, mid_a + band, colour_shade(COLOUR_PARCHMENT, 0.88))
	}
}

// draw_rig_shrouds sets up one mast's shrouds: a fan of cordage from the masthead down to the
// channel outboard of the rail, with ratlines across them. They are drawn to both sides — the
// port shrouds cross the cut, which is exactly right, since a cutaway takes the planking away
// and leaves the rigging standing.
draw_rig_shrouds :: proc(mast: Mast) {
	SHROUDS :: 4
	RATLINES :: 6
	cord := colour_shade(COLOUR_ROCK, 0.62)
	head := rig_mast_point(mast, mast.height * 0.60)
	rail := cutaway.galleon_sheer_y(mast.x)

	for side in ([2]f32{1, -1}) {
		channel := cutaway.galleon_frame_half_beam(mast.x, rail) + 0.06

		// The channel itself: the shelf the shrouds are set up on, thrust out from her side.
		ship_box({mast.x, rail - 0.04, side * (channel - 0.05)}, {0.42, 0.05, 0.2}, colour_shade(COLOUR_CLIFF, 0.85))

		foot_of :: proc(mast: Mast, rail, channel, side: f32, k: int) -> rl.Vector3 {
			f := f32(k) / f32(SHROUDS - 1)
			return rl.Vector3{mast.x + 0.17 - f * 0.34, rail + 0.02, side * channel}
		}

		for k in 0 ..< SHROUDS {
			ship_rope(head, foot_of(mast, rail, channel, side, k), 0.011, cord)
		}

		// Ratlines: the rungs across the shrouds, closing up as they climb. This is the detail
		// the eye reads as a rig rather than as guy-wires.
		for r in 1 ..< RATLINES {
			f := f32(r) / RATLINES
			f = f * f // bunched toward the deck, spread aloft, the way ratlines run
			a := rl.Vector3 {
				head.x + (foot_of(mast, rail, channel, side, 0).x - head.x) * (1 - f),
				head.y + (rail + 0.02 - head.y) * (1 - f),
				side * channel * (1 - f),
			}
			b := rl.Vector3 {
				head.x + (foot_of(mast, rail, channel, side, SHROUDS - 1).x - head.x) * (1 - f),
				a.y,
				a.z,
			}
			ship_rope(a, b, 0.008, cord)
		}
	}
}

// draw_rig_stays runs the fore-and-aft standing rigging: each mast stayed forward to the one
// ahead of it and the foremast to the bowsprit, with backstays leading aft to her quarters. It
// is the web that makes three masts one rig.
draw_rig_stays :: proc() {
	cord := colour_shade(COLOUR_ROCK, 0.68)
	masts := rig_masts()
	deck := cutaway.GALLEON_DECK_Y

	// Forestays, each mast leaning its weight on the deck ahead of it.
	for i in 0 ..< len(masts) {
		head := rig_mast_point(masts[i], masts[i].height * 0.92)
		ahead := i == 0 ? rl.Vector3{cutaway.GALLEON_BOW_X + 1.05, deck + 1.05, 0} : rig_mast_point(masts[i - 1], masts[i - 1].height * 0.5)
		ship_rope(head, ahead, 0.013, cord)

		// And a preventer under it, down to the deck, so the run of cordage reads as a web.
		ship_rope(rig_mast_point(masts[i], masts[i].height * 0.60), {ahead.x, deck + 0.08, 0}, 0.009, cord)
	}

	// Backstays from each masthead down to her quarters, outboard of the shrouds.
	for mast in masts {
		head := rig_mast_point(mast, mast.height * 0.88)
		for side in ([2]f32{1, -1}) {
			foot_x := mast.x - 1.15
			rail := cutaway.galleon_sheer_y(foot_x)
			ship_rope(head, {foot_x, rail, side * cutaway.galleon_frame_half_beam(foot_x, rail)}, 0.01, cord)
		}
	}
}

// draw_rig_bowsprit runs the bowsprit out over the head, with its spritsail slung under and the
// bobstay holding it down to the stem — the spar that carries the whole rig's forward pull.
draw_rig_bowsprit :: proc() {
	stem := rl.Vector3{cutaway.GALLEON_BOW_X - 0.35, cutaway.GALLEON_DECK_Y + 0.42, 0}
	tip := rl.Vector3{cutaway.GALLEON_BOW_X + 0.92, cutaway.GALLEON_DECK_Y + 1.02, 0}
	ship_spar(stem, tip, 0.062, 0.03, COLOUR_TRUNK)

	// The spritsail, on its own little yard under the spar.
	yard := rl.Vector3{cutaway.GALLEON_BOW_X + 0.42, cutaway.GALLEON_DECK_Y + 0.85, 0}
	ship_spar({yard.x, yard.y, -0.38}, {yard.x, yard.y, 0.38}, 0.022, 0.022, COLOUR_TRUNK)
	draw_rig_sail(yard, {yard.x + 0.05, yard.y - 0.36, 0}, 0.68)

	// The bobstay, down to the stem, and the jackstaff at the tip.
	ship_rope(tip, {cutaway.GALLEON_BOW_X + 0.05, cutaway.galleon_sheer_y(cutaway.GALLEON_BOW_X) - 0.18, 0}, 0.011, colour_shade(COLOUR_ROCK, 0.62))
}
