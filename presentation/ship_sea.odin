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
//
// Well outboard, and that is the fix for the two brightest marks on the water landing on each
// other. The glitter path runs from the sun straight down the frame toward the viewer — it has
// nowhere else to go — and her wake fans aft from the stern across the same water, so with the
// sun set just abaft her quarter the two stacked into one bright smear that read as neither.
//
// Moving the sun *forward* instead would separate them too, and is wrong: SHIP_SUN puts the
// light aft for a reason, and the camera stands off her port bow. Bring the light round to the
// bow and it falls on the faces the camera can already see, the castles lose the shadowed
// forward faces that say which way the hull turns, and she flattens out. Outboard costs nothing
// — the light is still abaft her beam, so every shaded face on the ship is unchanged.
SHIP_SUN_X :: f32(1120)
SHIP_SUN_Y :: f32(116)

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
// SHIP_GLARE is the sky right where it meets the water: the bright band the sun's heat bleaches
// into a tropical horizon. Grading the sky straight from its deep top down to COLOUR_HAZE and
// stopping there left the backdrop cold — the whole sky was one blue, and a blue with nothing
// warm in it reads as overcast however bright it is.
//
// But warming it by mixing the haze halfway to parchment made it *grey*: blue and a warm yellow
// are opposite hues, and halfway along that line is neutral by construction. It measured 6%
// saturation — a dead band straight across the middle of the frame, the largest single flat
// area on the screen. The fix is to warm it from a tone that is already on the cool side of the
// wheel, so the mix travels a short way round rather than straight through the middle: the sky
// pales toward the *sea's* brightest cool as it nears the water, and takes only a quarter of a
// step toward parchment for its warmth. Same intent, and it keeps its chroma.
SHIP_GLARE :: proc() -> rl.Color {
	return colour_mix(COLOUR_SEA_SHALLOW, COLOUR_PARCHMENT, 0.24)
}

// How many flat stops each of the backdrop's grades is cut into. Small on purpose — "limited
// ramps per hue" is the register — and counted per grade rather than shared, because a stop's
// visible height is its grade's span divided by this: the same count over a short span puts the
// steps close enough together to read as stripes.
SHIP_SKY_STOPS :: 6
SHIP_GLARE_STOPS :: 3
SHIP_SEA_STOPS :: 4

draw_ship_sky :: proc(horizon_y: f32) {
	rl.ClearBackground(COLOUR_SKY_HIGH)

	// Graded in two ramps, so the sky has somewhere to go: deep overhead, opening out through the
	// middle, and burning off to the glare along the horizon.
	glare := backdrop_ceil(horizon_y * 0.16)
	backdrop_grade({0, 0, WINDOW_WIDTH, horizon_y - glare}, COLOUR_SKY_HIGH, COLOUR_HAZE, SHIP_SKY_STOPS)
	backdrop_grade({0, horizon_y - glare, WINDOW_WIDTH, glare}, COLOUR_HAZE, SHIP_GLARE(), SHIP_GLARE_STOPS)

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

	draw_ship_island(150, horizon_y, 196, 46)
	draw_ship_island(1102, horizon_y, 140, 34)
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

// draw_ship_island stands one island on the horizon. It is built as vegetation first and rock
// second, which is what makes it an island rather than a headland with some trees on it.
//
// It used to be neither: a stepped lump of the recessive slate with three slate palms on top, at
// 18% saturation, twice, at two sizes. The cause was upstream of the drawing — the palette held
// no green at all, so there was nothing to paint foliage with and the island got built out of
// the only distance tone there was. The guide has had a Foliage roster the whole time, headed
// "this is where the old guide was most muted"; the code had simply never reached for it.
//
// Atmospheric perspective is carried by *alpha* over the lit sky rather than by mixing the
// greens toward the haze — mixing a saturated green into a pale blue is the complementary trap
// again, and it is exactly how the last version got to slate.
draw_ship_island :: proc(cx, horizon_y, width, height: f32) {
	CELL :: BACKDROP_PIXEL
	seed := int(cx)

	// The reef first: water shoaling over the shelf that rings her. From hull-down this is the
	// part of an island that reads before the land does — a low green line standing on a ring of
	// impossibly bright water is the whole picture of the tropics.
	shoal := colour_mix(COLOUR_SEA_SHALLOW, SHIP_GLARE(), 0.35)
	backdrop_block({cx - width * 0.68, horizon_y, width * 1.36, CELL}, rl.Fade(shoal, 0.45))
	backdrop_block({cx - width * 0.56, horizon_y, width * 1.12, CELL}, rl.Fade(shoal, 0.8))

	// The mass of the island, stepped in from the shoulders to the summit, in the roster's green
	// with the sun on each crest. The step count and every shoulder's jog come off the island's
	// own width and position, so the two on the horizon are not one silhouette printed twice.
	steps := 3 + int(width / 60)
	for k in 0 ..< steps {
		f := f32(k) / f32(steps)
		jog := (sea_noise(k, seed) - 0.5) * 0.3
		w := backdrop_ceil(width * (1 - f * 0.62) * (1 + jog))
		h := backdrop_ceil(height * (0.34 + f * 0.66))
		x := backdrop_floor(cx - w / 2 + f * width * 0.05)
		backdrop_block({x, horizon_y - h, w, h}, rl.Fade(COLOUR_GREEN, 0.86))
		// Sun along the top of each shoulder, and the deep shade under its lee. Two cells of each
		// is all it takes to stop the mass reading as one flat green wall.
		backdrop_block({x, horizon_y - h, w, 2 * CELL}, rl.Fade(COLOUR_GREEN_LIGHT, 0.9))
		backdrop_block({x, horizon_y - h + 2 * CELL, w, CELL}, rl.Fade(COLOUR_GREEN_DEEP, 0.5))
	}

	// The beach the green stops at, and with it the only warm on the horizon.
	strand := colour_mix(COLOUR_SAND, COLOUR_PARCHMENT, 0.25)
	backdrop_block({cx - width * 0.5, horizon_y - 2 * CELL, width, 2 * CELL}, rl.Fade(strand, 0.92))

	// Palms breaking the skyline: a trunk under a crown broad enough to read as fronds at this
	// distance rather than as a mast. The crown is one lit bar with a frond drooping off each tip
	// — stack it narrower toward the top instead and it comes out a cross standing on the ridge.
	// They stand on the ridge under them rather than at one height, so the row of them follows
	// the island's own profile.
	palms := 3 + int(width / 52)
	for k in 0 ..< palms {
		t := (f32(k) + 0.5) / f32(palms)
		x := backdrop_floor(cx - width * 0.42 + t * width * 0.84)
		ridge := height * (0.42 + 0.58 * (1 - min(abs(t - 0.55) * 1.9, 1)))
		base := backdrop_floor(horizon_y - ridge)
		trunk := backdrop_ceil(height * (0.3 + sea_noise(k, seed + 7) * 0.34))
		crest := base - trunk
		lean := f32(k % 3 - 1) * CELL
		backdrop_block({x, crest, CELL, trunk}, rl.Fade(COLOUR_TRUNK, 0.85))
		// The drooping tips sit under the *ends of the bar*, not outside them. Set a cell wide of
		// it they read as two dark specks floating beside the tree rather than as fronds hanging
		// off it.
		backdrop_block({x - 3 * CELL + lean, crest, 7 * CELL, CELL}, COLOUR_GREEN_LIGHT)
		backdrop_block({x - CELL + lean, crest - CELL, 3 * CELL, CELL}, COLOUR_GREEN_HIGHLIGHT)
		backdrop_block({x - 3 * CELL + lean, crest + CELL, 2 * CELL, CELL}, COLOUR_GREEN_DEEP)
		backdrop_block({x + 2 * CELL + lean, crest + CELL, 2 * CELL, CELL}, COLOUR_GREEN_DEEP)
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
	middle := backdrop_floor(depth * 0.5)
	backdrop_block({0, horizon_y, WINDOW_WIDTH, SHELF}, COLOUR_SEA_DEEP)
	backdrop_grade({0, horizon_y + SHELF, WINDOW_WIDTH, middle - SHELF}, COLOUR_SEA, COLOUR_SEA_BRIGHT, SHIP_SEA_STOPS)
	backdrop_grade({0, horizon_y + middle, WINDOW_WIDTH, depth - middle}, COLOUR_SEA_BRIGHT, near, SHIP_SEA_STOPS)

	// The chop. `f` is how far down the frame a wave lies, and everything about it — its length,
	// its weight, how dark it is — is taken off that one number, so the water gains scale as it
	// approaches. This is the only perspective a sea seen from its own surface has: the swell
	// crowds fine and tight at the horizon and comes on long and heavy at the viewer's feet.
	// The exponent is what decides how hard the chop crowds toward the horizon, and 1.7 crowded
	// it so hard that the nearest third of the water got almost no marks at all. The perspective
	// wants crowding; it does not want the bottom of the frame empty.
	for i in 0 ..< 300 {
		f := math.pow(sea_noise(i, 1), 1.35)
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

	// Near swells: the one thing that carries the bottom of the frame. More chop would not have
	// done it — chop is a scatter of short marks, and a scatter of short marks on flat colour is
	// still flat colour with speckle on it. A swell is a *long* mark with two sides: the back of
	// it turned away from the eye and falling into the sea's own deep, and the lit crest under
	// that. Two dozen of them give the near water form and something for the eye to travel
	// along, which is what the guide means by never painting a flat wall of it edge to edge.
	//
	// They are drawn on the lattice like everything else in the backdrop, and only over the near
	// two-thirds of the water — a swell this long up at the horizon would be a mile of sea in one
	// mark, and reads as a ruled line across the frame.
	for i in 0 ..< 40 {
		f := 0.26 + sea_noise(i, 61) * 0.74
		y := backdrop_floor(horizon_y + SHELF + f * (depth - SHELF))
		x := backdrop_floor(sea_noise(i, 62) * (WINDOW_WIDTH + 200) - 100)
		length := backdrop_ceil(90 + f * 220)
		rise := backdrop_ceil(3 + f * 4)
		backdrop_block({x, y - rise, length, rise}, rl.Fade(COLOUR_SEA_DEEP, 0.24 + f * 0.20))
		backdrop_block({x, y, length, rise}, rl.Fade(COLOUR_SEA_SHALLOW, 0.32 + f * 0.34))
	}

	// The glitter path: the sun's own road down the water. It stays under the sun and widens as
	// it comes on, every fleck thrown by the scatter so the road is broken light rather than a
	// dotted line drawn from A to B.
	// The taper runs the way perspective runs it: a point at the horizon opening out toward the
	// viewer. It was doing the opposite. `pow(noise, 1.4)` crowds the marks up at the horizon,
	// where the road is at its narrowest, so two hundred flecks piled into a twenty-pixel column
	// and the near end thinned away to nothing — a white geyser standing on the sea, tapering
	// downward, which is exactly inverted from a sun path.
	//
	// Linear f spreads the flecks evenly down the road; the spread starts near nothing and opens
	// wide; and the weight now falls off *toward* the horizon rather than away from it, so the
	// far end is a suggestion and the near end is where the light actually is. Each fleck is a
	// flat horizontal dash, because that is what a wave face catching the sun looks like.
	for i in 0 ..< 200 {
		f := sea_noise(i, 11)
		y := horizon_y + 4 + f * (depth - 4)
		spread := 6 + f * 300
		x := SHIP_SUN_X + (sea_noise(i, 12) - 0.5) * spread
		backdrop_block({x, y, 5 + f * 26, 1 + f}, rl.Fade(COLOUR_FOAM, 0.16 + f * 0.30))
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
	// The reach is short enough to end well before the sun's road begins. Two hundred pixels of
	// broken water astern still reads as a wake; three hundred only got it far enough aft to
	// collide with the glitter, and the pair of them together read as one smear rather than as
	// a wake and a sun path.
	// Shortened and taken off the white to match the stem. The wave ahead of her is gone, and a
	// two-hundred-pixel road of near-solid foam left behind a quiet bow does not read as half a
	// wake — it reads as a ship making sternway. What both ends are now drawing is one thing: the
	// stream she is lying to, turning at the stem and running out astern as a slick.
	for i in 0 ..< 120 {
		f := sea_noise(i, 21)
		spread := sea_noise(i, 22)
		x := stern.x + f * 138
		y := horizon_y + 1 + f * 34 * spread
		backdrop_block(
			{x, y, 26 - f * 17, 2 + f * 2},
			rl.Fade(
				colour_mix(COLOUR_SEA_SHALLOW, COLOUR_FOAM, 0.62),
				(0.34 - f * 0.27) * (1 - spread * 0.5),
			),
		)
	}

	// At the bow: the water working round her stem. Not a bow wave — this screen only ever shows
	// her stopped, headed "At Anchor" on the home ground and "Refit" while she is worked on, and a
	// wave heaped ahead of the stem says she is driving through the sea at both. It reached a
	// hundred pixels out in front of her in near-solid white, which is the single loudest thing
	// forward of the ship and the first thing the eye lands on.
	//
	// What an anchored ship actually makes is this: she lies to the tide, the stream runs past her,
	// and it turns at the stem in a short broken ring — close in, low, and more sea than foam. The
	// slick astern is the other half of the same current, so the two still agree about which way
	// the water is going.
	for i in 0 ..< 34 {
		f := math.pow(sea_noise(i, 31), 1.3)
		side := sea_noise(i, 32)
		backdrop_block(
			{bow.x - 12 - f * 34, horizon_y - 2 + f * 26 * side, 22 - f * 12, 2 + f * 2},
			rl.Fade(
				colour_mix(COLOUR_SEA_SHALLOW, COLOUR_FOAM, 0.5),
				(0.34 - f * 0.24) * (1 - side * 0.45),
			),
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
	// On the lattice that means walking her side a cell at a time and leaving cells unlit, rather
	// than scattering marks and trusting the gaps: every mark here is at least a cell wide and
	// starts on a cell boundary, so a scatter dense enough to read tiles into the bar instead.
	// And only at her ends. Breaking the run up did not save it and could not have: the marks
	// were correct — her waterline really is that straight from this eye — but eight hundred
	// pixels of near-white laid along a dark wale reads as a line of particles drawn *across the
	// ship*, whatever the marks are shaped like. Nothing about a dash pattern survives being
	// ruled that far.
	//
	// So the foam is spent where the eye already expects broken water and nowhere else: a run at
	// the stem, a shorter one off her quarter, and her whole middle left alone. Amidships a ship
	// lying at anchor meets the sea on a line, and drawing that line honestly is better than
	// papering over it for two-thirds of her length.
	// Where those two runs end is not a fraction any more — it is asked of the hull. A fifth of her
	// length forward and a sixth aft were guesses, and the aft one was wrong: her side is cut open
	// well abaft of where that run started, so the last of its marks were laid over the *inside* of
	// her hold. Bright water standing in mid-air inside a compartment is the same failure as the
	// line across her wale, in a smaller place.
	//
	// Foam belongs where the sea meets whole planking, and the hull already knows exactly where that
	// is: it is where the cut is still above the waterline. Asked rather than guessed, the two runs
	// end at her openings by construction, and they follow the cut if it is ever moved.
	whole :: proc(x: f32) -> bool {
		return hull_cut_t(x) > hull_section_t(x, 0)
	}
	STEP :: f32(0.04)
	fwd, aft := cutaway.GALLEON_BOW_X, cutaway.GALLEON_STERN_X
	for x := cutaway.GALLEON_BOW_X; x > cutaway.GALLEON_STERN_X && whole(x); x -= STEP {
		fwd = x
	}
	for x := cutaway.GALLEON_STERN_X; x < cutaway.GALLEON_BOW_X && whole(x); x += STEP {
		aft = x
	}
	f_bow := max((cutaway.galleon_project({fwd, 0, 0}, view).x - bow.x) / span, 0.001)
	f_aft := min((cutaway.galleon_project({aft, 0, 0}, view).x - bow.x) / span, 0.999)

	base := backdrop_floor(bow.x)
	cells := int(backdrop_ceil(span) / BACKDROP_PIXEL)
	for i in 0 ..< cells {
		if sea_noise(i, 41) < 0.3 {
			continue // the sea showing through: without these gaps the marks tile into the rule
		}
		f := f32(i) / f32(max(cells, 1))
		ends := max(1 - f / f_bow, (f - f_aft) / max(1 - f_aft, 0.001), 0)
		if ends <= 0 {
			continue
		}
		// One or two cells, never four. Standing up to sixteen pixels the run became a stripe
		// painted along her wale. Foam hugs the line it belongs to.
		h := (1 + math.floor(sea_noise(i, 42) * 2)) * BACKDROP_PIXEL
		// Nor is it white. Foam seen edge-on at the waterline is mostly lit water with a little
		// air in it, and COLOUR_FOAM against her dark topsides was the highest contrast on the
		// screen — which is what made a soft effect shout. Mixed back toward the shallow sea it
		// belongs to, it reads as water rather than as paint.
		// Most of the mark is below the line, and what is above it is one cell laid on almost solid.
		// Both because of the same trap in a place the guide had not yet caught it: a light cool
		// composited at a third alpha over her dark planking does not come out pale, it comes out
		// *grey*. The compositor walks brown toward turquoise and passes through neutral exactly as a
		// lerp would — alpha is a lerp — so the run at her stem was a row of grey teeth bolted to her
		// side. Below the waterline the same mark lands on sea it already agrees with and stays foam.
		// Above it, one cell at near-full weight is a colour rather than a blend, and that thin bright
		// lip is all that was ever wanted: the line where the water actually takes her.
		backdrop_block(
			{base + f32(i) * BACKDROP_PIXEL, horizon_y - BACKDROP_PIXEL, BACKDROP_PIXEL, h + BACKDROP_PIXEL},
			rl.Fade(colour_mix(COLOUR_SEA_SHALLOW, COLOUR_FOAM, 0.62), (0.66 + sea_noise(i, 44) * 0.30) * ends),
		)
	}

	// Spray off the bow: thrown up where the stem takes the water, and falling back into it.
	//
	// The arc is the fix for water that looked like it climbed. This ran as a straight ramp —
	// every mark further forward was also higher — so the marks lined up into a rising diagonal
	// that left the sea at her stem and carried on up into open sky, with nothing under it and no
	// crest it could have come off. The camera stands at the waterline, which makes it worse than
	// it sounds: world y=0 lands on the horizon at *every* distance, so there is no far water up
	// there for the spray to be standing on. Anything drawn high and forward is simply in the air.
	//
	// So the height is a sine over the throw instead: each mark leaves the water at the stem,
	// peaks a little way out, and comes back down to the surface. It reads as one burst rather
	// than a ramp, and both ends of it are in the sea where they belong. The throw is short for
	// the same reason — spray goes where the bow put it, not halfway to the horizon.
	// Spray is scarce on purpose. Two dozen heavy marks inside a short throw pile into one solid
	// white mass at her stem — a snowbank sitting on the water, which is the same failure as the
	// climb wearing different clothes. Broken water has to have sea showing through it.
	//
	// Scarcer still now, and lower. Spray is what a stem throws when it is driven into the sea, and
	// this ship is never driven anywhere on this screen — she is at anchor or under refit. What is
	// left is the lap: the stream turning at her cutwater and lifting a little, which peaks at a few
	// pixels rather than at eleven. The arc is kept because it is what puts both ends of the throw
	// back in the water, and that reasoning does not change with the size of it.
	SPRAY_REACH :: f32(24)
	SPRAY_PEAK :: f32(4)
	for i in 0 ..< 9 {
		f := sea_noise(i, 51)
		arc := math.sin(f * math.PI)
		backdrop_block(
			{bow.x - 8 - f * SPRAY_REACH, horizon_y - arc * SPRAY_PEAK, 6 - f * 3, 2},
			rl.Fade(colour_mix(COLOUR_SEA_SHALLOW, COLOUR_FOAM, 0.6), 0.18 + arc * 0.22),
		)
	}
}
