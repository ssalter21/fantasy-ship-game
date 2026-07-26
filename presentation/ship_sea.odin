#+private
package presentation

import "core:math"
import cutaway "./cutaway"
import rl "vendor:raylib"

// The world the ship floats in. The first pass drew three flat bands and a scatter of dashes,
// which is a backdrop; this one is a place. Three things do the work.
//
// Depth. Sky and sea are both graded — hot and hazy where they meet at the horizon, deep and
// cool away from it — so distance is carried by colour rather than by a hard band.
//
// Perspective in the water. The camera stands at the waterline, so the sea's true vanishing
// point is the horizon itself and the surface has no foreshortening to give. The chop supplies
// it instead: short, fine and dense up at the horizon, growing long and heavy as it comes down
// the frame toward the viewer. That gradient of scale *is* the perspective.
//
// Somewhere to be. A sun low over her quarter with a glitter path under it, tropical cumulus
// stacked in two ranks, and islands hull-down on the horizon — so the ship is in a sea with
// edges, not on an infinite blue plane.

// The sun's place in frame: over her quarter, aft and high, which is the same quarter
// SHIP_SUN lights her from. It is what backlights the canvas and lays the glitter down the water.
SHIP_SUN_X :: f32(980)
SHIP_SUN_Y :: f32(118)

// sea_noise is the scatter every mark on the water is placed by: one number in 0..1 per (index,
// salt). Broken water has to look unplanned, and stepping an index through a modulus — which is
// what the first pass did — lays the marks out along a line, so a glitter path came out as a
// dotted road and a wake as a ruled one. Hashing kills the pattern outright, and being pure
// arithmetic it gives the same sea every frame: the water never crawls.
sea_noise :: proc(index, salt: int) -> f32 {
	h := u32(index) * 374761393 + u32(salt) * 668265263
	h = (h ~ (h >> 13)) * 1274126177
	h = h ~ (h >> 16)
	return f32(h % 10007) / 10007
}

// draw_ship_sky paints everything above the water: the graded sky, the sun and its haze, two
// ranks of cumulus, and the islands standing hull-down along the horizon.
draw_ship_sky :: proc(horizon_y: f32) {
	rl.ClearBackground(COLOUR_SKY_HIGH)
	rl.DrawRectangleGradientV(0, 0, WINDOW_WIDTH, i32(horizon_y), COLOUR_SKY_HIGH, COLOUR_HAZE)

	// The sun: a disc inside two rings of haze, so it sits *in* the sky rather than on it.
	for k := 5; k >= 1; k -= 1 {
		radius := f32(k) * 26
		rl.DrawCircleV({SHIP_SUN_X, SHIP_SUN_Y}, radius, rl.Fade(COLOUR_CLOUD, 0.10))
	}
	rl.DrawCircleV({SHIP_SUN_X, SHIP_SUN_Y}, 26, rl.Fade(COLOUR_FOAM, 0.85))

	// Cumulus in two ranks: a high near rank, and a smaller far one lying along the horizon,
	// where the sky's own haze has already taken most of the contrast out of them.
	draw_ship_cloud(206, 96, 1.15, 1.0)
	draw_ship_cloud(1042, 74, 0.9, 1.0)
	draw_ship_cloud(520, 132, 0.7, 0.85)
	draw_ship_cloud(742, horizon_y - 96, 0.5, 0.55)
	draw_ship_cloud(118, horizon_y - 74, 0.42, 0.5)
	draw_ship_cloud(1160, horizon_y - 88, 0.46, 0.5)

	draw_ship_island(160, horizon_y, 168, 30)
	draw_ship_island(1094, horizon_y, 124, 22)
}

// draw_ship_cloud stacks a tropical cumulus: a shadowed base with two banks of sun on top of
// it, blocky throughout — the house style has no curves in its clouds, and a cloud stacked in
// steps still reads as a cloud. `scale` sizes it and `haze` fades it back into the sky, which
// is how the far rank sits behind the near one.
draw_ship_cloud :: proc(cx, cy, scale, haze: f32) {
	block :: proc(x, y, w, h: f32, colour: rl.Color, haze: f32) {
		rl.DrawRectangleRec({x, y, w, h}, rl.Fade(colour, haze))
	}
	block(cx - 78 * scale, cy + 15 * scale, 168 * scale, 20 * scale, COLOUR_CLOUD_SHADOW, haze)
	block(cx - 66 * scale, cy - 2 * scale, 138 * scale, 22 * scale, COLOUR_CLOUD, haze)
	block(cx - 34 * scale, cy - 20 * scale, 76 * scale, 22 * scale, COLOUR_CLOUD, haze)
	block(cx - 4 * scale, cy - 33 * scale, 40 * scale, 16 * scale, COLOUR_CLOUD, haze)
}

// draw_ship_island stands one island hull-down on the horizon: a headland in stepped blocks
// with palms breaking its ridge, all of it pulled far back toward the sky's haze — an island a
// dozen miles off keeps its shape and almost none of its colour.
draw_ship_island :: proc(cx, horizon_y, width, height: f32) {
	rock := colour_mix(COLOUR_BLUE_RECESSIVE, COLOUR_HAZE, 0.46)
	for k in 0 ..< 4 {
		f := f32(k) / 4
		w := width * (1 - f * 0.66)
		h := height * (0.4 + f * 0.6)
		rl.DrawRectangleRec({cx - w / 2 + f * width * 0.06, horizon_y - h, w, h}, rock)
	}
	// Palms breaking the ridge: a trunk under a crown broad enough to read as fronds at this
	// distance rather than as a mast.
	crown := colour_mix(COLOUR_BLUE_RECESSIVE, COLOUR_HAZE, 0.3)
	for k in 0 ..< 3 {
		x := cx - width * 0.22 + f32(k) * width * 0.22
		lean := f32(k) - 1
		rl.DrawRectangleRec({x, horizon_y - height - 10, 2, 10}, crown)
		rl.DrawRectangleRec({x - 7 + lean, horizon_y - height - 15, 17, 5}, crown)
		rl.DrawRectangleRec({x - 3 + lean, horizon_y - height - 18, 9, 3}, crown)
	}
}

// draw_ship_sea paints the water: graded from the deep of distance at the horizon to the lit
// shallows nearest the viewer, then worked over with chop that grows as it comes down the
// frame, and a glitter path laid under the sun.
draw_ship_sea :: proc(horizon_y: f32) {
	depth := WINDOW_HEIGHT - horizon_y

	// A hard shelf of deep water right at the horizon, then the grade in toward the viewer.
	SHELF :: f32(14)
	rl.DrawRectangleRec({0, horizon_y, WINDOW_WIDTH, SHELF}, COLOUR_SEA_DEEP)
	rl.DrawRectangleGradientV(
		0,
		i32(horizon_y + SHELF),
		WINDOW_WIDTH,
		i32(depth - SHELF) + 1,
		COLOUR_SEA,
		COLOUR_SEA_BRIGHT,
	)

	// The chop. `f` is how far down the frame a wave lies, and everything about it — its length,
	// its weight, how dark it is — is taken off that one number, so the water gains scale as it
	// approaches. This is the only perspective a sea seen from its own surface has: the swell
	// crowds fine and tight at the horizon and comes on long and heavy at the viewer's feet.
	for i in 0 ..< 230 {
		f := math.pow(sea_noise(i, 1), 1.7)
		y := horizon_y + SHELF + f * (depth - SHELF)
		x := sea_noise(i, 2) * (WINDOW_WIDTH + 60) - 30
		length := 7 + f * 52
		thickness := 1 + f * 3
		tone := sea_noise(i, 3) < 0.28 ? COLOUR_SEA_SHALLOW : COLOUR_SEA_BRIGHT
		rl.DrawRectangleRec({x, y, length, thickness}, rl.Fade(tone, 0.18 + f * 0.42))

		// Every so often a crest breaks white — sparse, so a whitecap still means something.
		if sea_noise(i, 4) > 0.93 {
			rl.DrawRectangleRec({x + length * 0.3, y - 2, length * 0.4, thickness}, rl.Fade(COLOUR_FOAM, 0.3 + f * 0.4))
		}
	}

	// The glitter path: the sun's own road down the water. It stays under the sun and widens as
	// it comes on, every fleck thrown by the scatter so the road is broken light rather than a
	// dotted line drawn from A to B.
	for i in 0 ..< 200 {
		f := math.pow(sea_noise(i, 11), 1.4)
		y := horizon_y + 4 + f * (depth - 4)
		spread := 30 + f * 240
		x := SHIP_SUN_X + (sea_noise(i, 12) - 0.5) * spread
		rl.DrawRectangleRec({x, y, 4 + f * 22, 1 + f * 2}, rl.Fade(COLOUR_FOAM, 0.46 - f * 0.2))
	}
}

// draw_ship_wake lays the disturbed water the hull is sitting in, before the hull is drawn over
// it: the bow wave thrown out ahead of her and the wake trailing away astern. It goes down on
// the sea rather than on the ship, so what survives is the part standing out either side of
// her — which is all of it that should be seen.
draw_ship_wake :: proc(view: cutaway.View, horizon_y: f32) {
	bow := cutaway.galleon_project({cutaway.GALLEON_BOW_X, 0, 0}, view)
	stern := cutaway.galleon_project({cutaway.GALLEON_STERN_X, 0, 0}, view)

	// Astern: broken water fanning back from her quarter, thinning as it falls behind. Scattered
	// rather than stepped, or it draws itself as a road running off to the horizon.
	for i in 0 ..< 120 {
		f := sea_noise(i, 21)
		spread := sea_noise(i, 22)
		x := stern.x + f * 300
		y := horizon_y + 1 + f * 40 * spread
		rl.DrawRectangleRec({x, y, 30 - f * 20, 2 + f * 2}, rl.Fade(COLOUR_FOAM, (0.40 - f * 0.32) * (1 - spread * 0.5)))
	}

	// At the bow: the wave she is pushing, heaped where the stem takes the water and falling
	// away either side of her.
	for i in 0 ..< 60 {
		f := math.pow(sea_noise(i, 31), 1.3)
		side := sea_noise(i, 32)
		rl.DrawRectangleRec(
			{bow.x - 16 - f * 84, horizon_y - 3 + f * 40 * side, 34 - f * 18, 3 + f * 2},
			rl.Fade(COLOUR_FOAM, (0.40 - f * 0.3) * (1 - side * 0.45)),
		)
	}
}

// draw_ship_waterline is the one pass that goes on *after* the hull: the foam standing up her
// planking where the sea takes her, drawn along the camera's own horizon because that is
// precisely where the waterline lands from an eye at sea level. Without it the hull ends at the
// water on a ruled line, and no amount of work on either reads as a ship floating.
draw_ship_waterline :: proc(view: cutaway.View, horizon_y: f32) {
	bow := cutaway.galleon_project({cutaway.GALLEON_BOW_X + 0.2, 0, 0}, view)
	stern := cutaway.galleon_project({cutaway.GALLEON_STERN_X - 0.1, 0, 0}, view)
	span := max(stern.x - bow.x, 1)

	// Laid in two passes: a continuous wash of foam standing against her planking, and a ragged
	// upper edge broken by the scatter, so the waterline is a line the water made rather than
	// one that was ruled.
	rl.DrawRectangleRec({bow.x, horizon_y - 2, span, 4}, rl.Fade(COLOUR_FOAM, 0.26))
	for i in 0 ..< 150 {
		f := sea_noise(i, 41)
		x := bow.x + f * span
		h := 2 + sea_noise(i, 42) * 5
		// Heaviest forward, where she is driving the water, thinning away aft.
		rl.DrawRectangleRec({x, horizon_y - h * 0.7, span / 44, h}, rl.Fade(COLOUR_FOAM, 0.5 * (1 - f * 0.55)))
	}

	// Spray off the bow, thrown clear of her.
	for i in 0 ..< 24 {
		f := sea_noise(i, 51)
		rl.DrawRectangleRec(
			{bow.x - 14 - f * 70, horizon_y - 8 - f * 26, 12 - f * 6, 3 + f * 2},
			rl.Fade(COLOUR_FOAM, 0.6 - f * 0.44),
		)
	}
}
