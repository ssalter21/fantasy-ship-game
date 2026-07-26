#+private
package presentation

import "core:math"
import cutaway "./cutaway"
import rl "vendor:raylib"

// The world the ship floats in. Three things do the work.
//
// One resolution. Every mark here goes down through `backdrop.odin` and lands on the art
// lattice, and every grade is a short ramp of flat stops dissolved by its ordered dither. Sky,
// cloud and sea therefore step at the same size, which is what stops the sky reading as a
// smooth vector field behind pixel-art weather.
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
// SHIP_GLARE is the sky right where it meets the water: the pale warm band the sun's heat
// bleaches into a tropical horizon. Grading the sky straight from its deep top down to
// COLOUR_HAZE and stopping there is what left the backdrop looking cold — the whole sky was one
// blue, and a blue with nothing warm anywhere in it reads as overcast however bright it is.
SHIP_GLARE :: proc() -> rl.Color {
	return colour_mix(COLOUR_HAZE, COLOUR_PARCHMENT, 0.5)
}

// How many flat stops each of the backdrop's grades is cut into. They are small on purpose —
// "limited ramps per hue" is the register — and sized to their own span rather than shared: the
// glare burns off in a sixth of the sky's height and would show its steps as stripes at the
// sky's count.
SHIP_SKY_STOPS :: 6
SHIP_GLARE_STOPS :: 3
SHIP_SEA_STOPS :: 4

draw_ship_sky :: proc(horizon_y: f32) {
	rl.ClearBackground(COLOUR_SKY_HIGH)

	// Graded in two ramps rather than one, so the sky has somewhere to go: deep overhead,
	// opening out through the middle, and burning off to the glare along the horizon.
	glare := backdrop_ceil(horizon_y * 0.16)
	backdrop_grade(0, 0, WINDOW_WIDTH, horizon_y - glare, COLOUR_SKY_HIGH, COLOUR_HAZE, SHIP_SKY_STOPS)
	backdrop_grade(0, horizon_y - glare, WINDOW_WIDTH, glare, COLOUR_HAZE, SHIP_GLARE(), SHIP_GLARE_STOPS)

	// The sun: a disc inside rings of haze, so it sits *in* the sky rather than on it. The haze
	// is warm — it is what the sun is doing to the air around it, and a grey one made a hole.
	for k := 6; k >= 1; k -= 1 {
		radius := f32(k) * 26
		backdrop_disc({SHIP_SUN_X, SHIP_SUN_Y}, radius, rl.Fade(COLOUR_PARCHMENT, 0.09))
	}
	backdrop_disc({SHIP_SUN_X, SHIP_SUN_Y}, 34, rl.Fade(COLOUR_PARCHMENT, 0.55))
	backdrop_disc({SHIP_SUN_X, SHIP_SUN_Y}, 26, rl.Fade(COLOUR_FOAM, 0.92))

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
		backdrop_block({x, y, w, h}, rl.Fade(colour, haze))
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
	// A strand of sand at the water's edge under the headland: one art pixel of warm, and it is
	// what makes the island land rather than a blue lump standing in the sea.
	strand := colour_mix(COLOUR_SAND, SHIP_GLARE(), 0.5)
	backdrop_block({cx - width / 2 - 6, horizon_y - 4, width + 12, 4}, strand)

	rock := colour_mix(COLOUR_BLUE_RECESSIVE, COLOUR_HAZE, 0.38)
	for k in 0 ..< 4 {
		f := f32(k) / 4
		w := width * (1 - f * 0.66)
		h := height * (0.4 + f * 0.6)
		backdrop_block({cx - w / 2 + f * width * 0.06, horizon_y - h, w, h}, rock)
	}
	// Palms breaking the ridge: a trunk under a crown broad enough to read as fronds at this
	// distance rather than as a mast. The crown is one wide bar with a cell drooping off each
	// tip, which is the whole silhouette a palm has at five art pixels wide. Stacking it
	// narrower toward the top instead leaves a cross standing on the ridge.
	P :: BACKDROP_PIXEL
	crown := colour_mix(COLOUR_BLUE_RECESSIVE, COLOUR_HAZE, 0.24)
	for k in 0 ..< 3 {
		x := backdrop_snap(cx - width * 0.22 + f32(k) * width * 0.22)
		lean := f32(k - 1) * P
		crest := backdrop_snap(horizon_y - height) - 4 * P
		backdrop_block({x, crest + P, P, 3 * P}, crown)
		backdrop_block({x - 2 * P + lean, crest, 5 * P, P}, crown)
		backdrop_block({x - 3 * P + lean, crest + P, P, P}, crown)
		backdrop_block({x + 3 * P + lean, crest + P, P, P}, crown)
	}
}

// draw_ship_sea paints the water: graded from the deep of distance at the horizon to the lit
// shallows nearest the viewer, then worked over with chop that grows as it comes down the
// frame, and a glitter path laid under the sun.
draw_ship_sea :: proc(horizon_y: f32) {
	depth := WINDOW_HEIGHT - horizon_y

	// A hard shelf of deep water right at the horizon, then the grade in toward the viewer — and
	// it does not stop at COLOUR_SEA_BRIGHT. The water nearest the eye runs on into the roster's
	// brightest cool, because that turquoise *is* the tropics: a sea graded between its two mid
	// blues is a temperate one, and no amount of light on the ship above it says otherwise.
	SHELF :: f32(16)
	near := colour_mix(COLOUR_SEA_BRIGHT, COLOUR_SEA_SHALLOW, 0.72)
	middle := backdrop_snap(depth * 0.5)
	backdrop_block({0, horizon_y, WINDOW_WIDTH, SHELF}, COLOUR_SEA_DEEP)
	backdrop_grade(0, horizon_y + SHELF, WINDOW_WIDTH, middle - SHELF, COLOUR_SEA, COLOUR_SEA_BRIGHT, SHIP_SEA_STOPS)
	backdrop_grade(0, horizon_y + middle, WINDOW_WIDTH, depth - middle, COLOUR_SEA_BRIGHT, near, SHIP_SEA_STOPS)

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
		backdrop_block({x, y, length, thickness}, rl.Fade(tone, 0.18 + f * 0.42))

		// Every so often a crest breaks white — sparse, so a whitecap still means something.
		if sea_noise(i, 4) > 0.93 {
			backdrop_block({x + length * 0.3, y - 4, length * 0.4, thickness}, rl.Fade(COLOUR_FOAM, 0.3 + f * 0.4))
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
		backdrop_block({x, y, 4 + f * 22, 1 + f * 2}, rl.Fade(COLOUR_FOAM, 0.46 - f * 0.2))
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
		backdrop_block({x, y, 30 - f * 20, 2 + f * 2}, rl.Fade(COLOUR_FOAM, (0.40 - f * 0.32) * (1 - spread * 0.5)))
	}

	// At the bow: the wave she is pushing, heaped where the stem takes the water and falling
	// away either side of her.
	for i in 0 ..< 60 {
		f := math.pow(sea_noise(i, 31), 1.3)
		side := sea_noise(i, 32)
		backdrop_block(
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

	// Broken water only — no continuous bar. With the camera exactly at the waterline, world y=0
	// projects onto the horizon at every distance, so anything drawn along the waterline is
	// *mathematically* a straight horizontal line. A bar there is a drawn rule, and no scatter laid
	// on top of it breaks that up: the foam has to be made of marks and nothing else, each one its
	// own height and its own weight, with sea showing between them.
	//
	// So it is walked one art pixel at a time along her side rather than scattered. A scatter is
	// what closes back up into a bar here — on the lattice every mark is at least a cell wide and
	// starts on a cell boundary, so overlapping marks stop reading as depth and start tiling.
	base := backdrop_snap(bow.x)
	cells := int(backdrop_ceil(span) / BACKDROP_PIXEL)
	for i in 0 ..< cells {
		if sea_noise(i, 41) < 0.45 {
			continue // the sea showing through: without these gaps the marks tile into the rule
		}
		f := f32(i) / f32(max(cells, 1))
		h := (1 + math.floor(sea_noise(i, 42) * 3)) * BACKDROP_PIXEL
		// Heaviest forward, where she is driving the water, thinning away aft.
		backdrop_block(
			{base + f32(i) * BACKDROP_PIXEL, horizon_y - h, BACKDROP_PIXEL, h},
			rl.Fade(COLOUR_FOAM, (0.30 + sea_noise(i, 44) * 0.4) * (1 - f * 0.6)),
		)
	}

	// Spray off the bow, thrown clear of her.
	for i in 0 ..< 24 {
		f := sea_noise(i, 51)
		backdrop_block(
			{bow.x - 14 - f * 70, horizon_y - 8 - f * 26, 12 - f * 6, 3 + f * 2},
			rl.Fade(COLOUR_FOAM, 0.6 - f * 0.44),
		)
	}
}
