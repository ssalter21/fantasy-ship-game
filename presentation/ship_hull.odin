#+private
package presentation

import cutaway "./cutaway"
import rl "vendor:raylib"

// The hull the rooms are cut into, painted off the loft in cutaway/galleon.odin: her plan
// (galleon_half_beam) and her sections (galleon_frame_half_beam) give a surface, and this file
// plates it. Every strake is a lit quad (ship_paint.odin), so what models the hull is the light
// falling across her curve — the turn of the bilge, the tumblehome above the wale, the fine
// entry forward — rather than an outline drawn round a box.
//
// The cut: her port planking is opened from just under the hold floor up, so every compartment
// is looked into. It closes again at the stem, so the bow wraps round instead of ending in a
// slice, and the cut edge carries the thickness of her planking — the timber you see in the
// edge of a cutaway drawing.

// The loft's resolution: strips down her length, bands up each frame. As coarse as it can be
// and still read as a curve, because the art is blocky and faceted planking is wanted.
// Fine enough that the entry resolves as a curve. At the coarse setting the last strip carried
// the whole of the fining-away, so her bow arrived at its point in one facet — a corner, which
// is exactly what a bow must not have.
HULL_STRIPS :: 48
HULL_BANDS :: 10

// HULL_SKIN is how thick her planking is — the timber the cut edge shows, and the offset
// between the outer skin and the inner face of the same strake.
HULL_SKIN :: f32(0.055)

// HULL_CUT_Y is where the port planking is opened to: a hand's breadth under the hold floor, so
// the compartments stand clear of the cut rather than sitting behind it.
HULL_CUT_Y :: cutaway.GALLEON_HOLD_FLOOR_Y - 0.07

// What a fathom of water does to the light coming back off her bottom. Two separate effects,
// and keeping them separate is the whole point.
//
// Absorption: how much of each channel the water eats on the way. Red goes first — that is why
// a reef reads green in a fathom and blue in ten — green goes slowly, blue barely goes at all.
// Scatter: the water's own lit colour, added back on top, because a fathom of sunlit sea is
// itself glowing and some of that glow is between her and the eye.
//
// Neither one is a lerp, and that is deliberate. Fading the hull *toward* the sea walks a
// straight line from copper to turquoise, and those two sit on opposite sides of the colour
// wheel — so the line passes through neutral, and every strake at mid-depth came out the same
// dead sage. Absorbing and scattering can't do that: absorption only ever takes a channel down,
// scatter only ever puts a saturated tone in, and the path between them stays in colour.
HULL_ABSORB_R :: f32(0.86)
HULL_ABSORB_G :: f32(0.26)
HULL_ABSORB_B :: f32(0.0)
HULL_SCATTER :: f32(0.5)

// HULL_WET_STEP is how much of the full fathom's worth of water is applied the instant a strake
// goes under. Small, but not zero: water has a surface, and a hull crossing it changes colour at
// the crossing.
HULL_WET_STEP :: f32(0.2)

// HULL_TINT_SPAN is the depth at which the keel-end values are reached — about a fathom, which
// is as far down as any of her gets.
HULL_TINT_SPAN :: f32(0.95)

// hull_surface is one point on her outer skin: the frame at length x, at section height t — 0
// at the keel, 1 at the rail — on the given side, +1 starboard and -1 port.
hull_surface :: proc(x, t, side: f32) -> rl.Vector3 {
	keel := cutaway.galleon_keel_y(x)
	rail := cutaway.galleon_sheer_y(x)
	y := keel + (rail - keel) * t
	return rl.Vector3{x, y, side * cutaway.galleon_frame_half_beam(x, y)}
}

// hull_normal is which way the skin faces at (x, t) on the starboard side, taken off the loft by
// difference rather than off the little quad standing in for it — near the keel and at the stem
// the quads go so nearly degenerate that a cross product on their corners is noise.
hull_normal :: proc(x, t, side: f32) -> rl.Vector3 {
	DX :: f32(0.07)
	DT :: f32(0.04)
	along := hull_surface(x + DX, t, 1) - hull_surface(x - DX, t, 1)
	up := hull_surface(x, min(t + DT, 1), 1) - hull_surface(x, max(t - DT, 0), 1)
	n := rl.Vector3Normalize(rl.Vector3CrossProduct(along, up))
	// The port side is the starboard side mirrored, and so is its normal.
	return rl.Vector3{n.x, n.y, side * n.z}
}

// hull_section_t is where a world height falls on the frame at length x, 0 at the keel and 1 at
// the rail — the parameter the loft is drawn in.
hull_section_t :: proc(x, y: f32) -> f32 {
	keel := cutaway.galleon_keel_y(x)
	rail := cutaway.galleon_sheer_y(x)
	return clamp((y - keel) / max(rail - keel, 0.001), 0, 1)
}

// hull_cut_t is the top of the port planking below the cut: a long window opened in her side
// over the compartments, closing up to the rail at *both* ends so the bow and the quarter wrap
// round rather than ending in a slice. Closing it only forward — which is all the first pass
// did — left her whole after end an open shell with the transom standing behind it, and the
// gaps between the two read exactly as the holes they were.
// The window is opened over the compartments and nowhere else. Run on past them — which it was,
// by a length and a half forward — it opens onto the bare inside of her bow planking: a lit,
// empty, curving shell with no floor and no end, which is precisely the "front of the bottom
// floor that doesn't read like a real space". There is nothing wrong with what was drawn there;
// the mistake was cutting a window into a part of the ship that has nothing in it.
hull_cut_t :: proc(x: f32) -> f32 {
	stem := clamp((x - cutaway.GALLEON_HOLD_X1) / 0.75, 0, 1)
	post := clamp((cutaway.GALLEON_HOLD_X0 - 0.1 - x) / 0.55, 0, 1)
	closing := max(stem, post)
	rail := cutaway.galleon_sheer_y(x)
	return hull_section_t(x, HULL_CUT_Y + (rail - HULL_CUT_Y) * closing * closing)
}

// hull_bulwark_t is the bottom of the strip of port side that survives the cut: the bulwark
// standing round the weather deck, and the rail capping it. Cutting that away too would take
// the sheer line with it — the one curve that reads as a ship from any distance — and leave an
// open barge. So the window stops at the deck, and above it her side is whole.
hull_bulwark_t :: proc(x: f32) -> f32 {
	return max(hull_section_t(x, cutaway.GALLEON_DECK_Y - 0.02), hull_cut_t(x))
}

// hull_water is the sea laid over a strake that is under it — applied to the *lit* colour, not
// to the timber, because the water is the last thing between the hull and the eye. Doing it the
// other way round tints the wood itself and then shades the result down, which is what left her
// bottom a dark olive wedge beside bright turquoise: it read as a hole in her side rather than
// as copper seen through a fathom of clear water.
hull_water :: proc(lit: rl.Color, y: f32) -> rl.Color {
	if y >= 0 {
		return lit
	}
	depth := min(-y / HULL_TINT_SPAN, 1)

	// Both effects run on depth *squared*, not on depth. Water this clear does almost nothing
	// over the first hand's breadth, and a linear ramp spends its whole middle in the crossover
	// where her warm and the sea's cool cancel. Squaring holds her copper — barely cooled, still
	// plainly her — down to half a fathom, then turns her over quickly, so the neutral crossing
	// is a band a few strakes deep instead of most of her bottom.
	//
	// The two curves are not the same, though, and that difference is what puts a waterline on
	// the hull. Squared from zero, the first hand's breadth under the surface is tinted so little
	// that her planking there is the same tan as her dry topsides: the eye finds no crossing at
	// all, and the parts of her below it read as standing out of the water rather than in it.
	//
	// The obvious repair — start *both* curves off a step — puts the crossing back and makes it
	// sage, because a step in absorption is a step toward the neutral crossing. So only the
	// scatter steps. Absorption still begins at nothing, so her copper keeps its hue right up to
	// the surface, and what changes at the crossing is that the water's own light starts landing
	// on her: she brightens and cools without turning. That is what wet timber does.
	absorbed := depth * depth
	scattered := HULL_WET_STEP + (1 - HULL_WET_STEP) * depth * depth

	// What is between her and the eye changes with depth, so what scatters back changes too: near
	// the surface it is the bright near-surface turquoise, a fathom down the sea's own deep.
	surface := colour_mix(COLOUR_SEA_BRIGHT, COLOUR_SEA_SHALLOW, 0.5)
	sea := colour_mix(surface, COLOUR_SEA_DEEP, depth)

	channel :: proc(lit, sea: u8, absorb, absorbed, scattered: f32) -> u8 {
		through := f32(lit) * (1 - absorb * absorbed)
		return u8(clamp(through + f32(sea) * HULL_SCATTER * scattered, 0, 255))
	}
	return rl.Color {
		channel(lit.r, sea.r, HULL_ABSORB_R, absorbed, scattered),
		channel(lit.g, sea.g, HULL_ABSORB_G, absorbed, scattered),
		channel(lit.b, sea.b, HULL_ABSORB_B, absorbed, scattered),
		lit.a,
	}
}

// hull_timber is a strake's wood at height y: oak topsides in alternating courses, and the
// brighter copper sheathing below the waterline. The alternation is what gives the skin planking
// without a single drawn line. What the water then does to it is hull_water's business.
hull_timber :: proc(y: f32, band: int) -> rl.Color {
	if y < 0 {
		return colour_shade(COLOUR_SAND, band % 2 == 0 ? 1.0 : 0.9)
	}
	// Her topsides are deliberately the darkest warm on the ship. Everything built on the deck —
	// castles, rails, deck planking — is the lighter sand, so the hull reads as one mass under
	// them instead of the whole ship washing out into a single tan.
	return colour_shade(COLOUR_ROCK, band % 2 == 0 ? 0.88 : 0.76)
}

// hull_timber_inner is the same strake seen from *inboard* — the ceiling planking a compartment
// is looked at across. It takes no depth tint whatever, and that is the whole point of it being
// its own procedure: the tint is what a fathom of clear tropical water does to a colour seen
// through it, and there is no water inside a hold. Shading the outer colour for the inner face,
// which is what the first pass did, filled every compartment below the waterline with teal — and
// what that reads as, unmistakably, is a hull full of standing water.
hull_timber_inner :: proc(band: int) -> rl.Color {
	return colour_shade(COLOUR_CLIFF, band % 2 == 0 ? 0.72 : 0.64)
}

// draw_ship_hull plates her: the skin both sides, the cut edge, the keel and posts, the wales,
// the weather deck, and the transom and stem that cap her ends.
draw_ship_hull :: proc() {
	stern := cutaway.GALLEON_STERN_X
	bow := cutaway.GALLEON_BOW_X
	step := (bow - stern) / HULL_STRIPS

	for i in 0 ..< HULL_STRIPS {
		x0 := stern + f32(i) * step
		x1 := x0 + step
		// Each band is taken to the cut's height *at each end of the strip*, not to one height
		// for the whole of it. Squaring them off — the lower band to the lowest cut across the
		// strip, the upper to the highest — leaves a triangular sliver of nothing wherever the
		// cut is climbing, which it does hard at both her ends. Those slivers were the ragged
		// wedges of daylight in her bow and quarter.
		draw_hull_side(x0, x1, 1, 0, 0, 1, 1) // starboard, whole from keel to rail
		draw_hull_side(x0, x1, -1, 0, 0, hull_cut_t(x0), hull_cut_t(x1)) // port below the window
		draw_hull_side(x0, x1, -1, hull_bulwark_t(x0), hull_bulwark_t(x1), 1, 1) // the bulwark above it
		draw_hull_cut_edge(x0, x1, hull_cut_t, 1)
		draw_hull_cut_edge(x0, x1, hull_bulwark_t, -1)
		draw_hull_keel(x0, x1)
	}

	draw_hull_cap(stern, -1)
	draw_hull_cap(bow, 1)
	draw_hull_sole()
	draw_hull_wales()
	draw_hull_deck()
	draw_hull_transom()
	draw_hull_stem()
}

// draw_hull_side plates one strip of one side over a run of the section. The run is given at
// each end of the strip — `lo0`..`hi0` at x0 and `lo1`..`hi1` at x1 — so a band whose top or
// bottom is climbing keeps its two ends where they belong and meets its neighbour exactly.
// Both faces of the planking are laid: the outer skin, and the inner face the cutaway looks
// across the ship at, lit by the opposite normal, since a hull's inside is in its own shadow.
// Strakes are counted off the section itself rather than off this run's subdivisions, so the
// courses line up across a cut instead of stepping at it.
draw_hull_side :: proc(x0, x1, side, lo0, lo1, hi0, hi1: f32) {
	if hi0 - lo0 <= 0.002 && hi1 - lo1 <= 0.002 {
		return
	}
	for j in 0 ..< HULL_BANDS {
		f0 := f32(j) / HULL_BANDS
		f1 := f32(j + 1) / HULL_BANDS
		t0 := lo0 + (hi0 - lo0) * f0 // at x0, bottom of the band
		u0 := lo1 + (hi1 - lo1) * f0 // at x1, bottom
		t1 := lo0 + (hi0 - lo0) * f1 // at x0, top
		u1 := lo1 + (hi1 - lo1) * f1 // at x1, top

		a := hull_surface(x0, t0, side)
		b := hull_surface(x1, u0, side)
		c := hull_surface(x1, u1, side)
		d := hull_surface(x0, t1, side)
		normal := hull_normal((x0 + x1) / 2, (t0 + t1) / 2, side)
		timber := hull_timber((a.y + d.y) / 2, int((t0 + t1) * 7))

		ship_quad_flat(a, b, c, d, hull_water(ship_lit(timber, ship_facing((a + c) / 2, normal)), (a.y + d.y) / 2))

		inner := normal * HULL_SKIN
		ship_quad_lit(a - inner, b - inner, c - inner, d - inner, hull_timber_inner(int((t0 + t1) * 7)), -normal)
	}
}

// draw_hull_cut_edge caps an opened edge of the port planking with the thickness of the plank
// itself — the top of the window below, and the underside of the bulwark above it. It is the one
// line that says her side was *cut away* rather than never built, so it is left bright: raw sawn
// timber against the shadowed interior. `facing` is which way the exposed edge looks, up off the
// lower planking or down off the bulwark.
draw_hull_cut_edge :: proc(x0, x1: f32, edge: proc(x: f32) -> f32, facing: f32) {
	t0, t1 := edge(x0), edge(x1)
	if t0 >= 0.999 && t1 >= 0.999 {
		return
	}
	a := hull_surface(x0, t0, -1)
	b := hull_surface(x1, t1, -1)
	n0 := hull_normal(x0, t0, -1) * HULL_SKIN
	n1 := hull_normal(x1, t1, -1) * HULL_SKIN
	ship_quad_lit(a - n0, b - n1, b, a, colour_shade(COLOUR_CLIFF, 1.05), {0, facing, 0})
}

// draw_hull_keel lays the keel timber under her bottom, standing proud of the planking the way
// a keel does — the spine the whole loft hangs from.
draw_hull_keel :: proc(x0, x1: f32) {
	y0 := cutaway.galleon_keel_y(x0)
	y1 := cutaway.galleon_keel_y(x1)
	// The keel narrows into the posts along with her. Carried out to the stem at full width it
	// is wider than the hull above it — the entry fines to a knife edge and a slab of keel then
	// stands out either side of it, which reads as a lump stuck on the bow rather than a stem.
	fullness := cutaway.galleon_half_beam((x0 + x1) / 2) / cutaway.GALLEON_HALF_BEAM
	KEEL := 0.075 * (0.40 + 0.60 * fullness)
	DROP :: f32(0.09)
	oak := colour_shade(COLOUR_ROCK, 1.05)
	deep := (y0 + y1) / 2 - DROP / 2

	side := hull_water(ship_lit(oak, {0, 0, -1}), deep)
	ship_quad_flat({x0, y0 - DROP, -KEEL}, {x1, y1 - DROP, -KEEL}, {x1, y1, -KEEL}, {x0, y0, -KEEL}, side)
	ship_quad_flat({x0, y0 - DROP, KEEL}, {x0, y0, KEEL}, {x1, y1, KEEL}, {x1, y1 - DROP, KEEL}, side)
	ship_quad_flat(
		{x0, y0 - DROP, -KEEL},
		{x0, y0 - DROP, KEEL},
		{x1, y1 - DROP, KEEL},
		{x1, y1 - DROP, -KEEL},
		hull_water(ship_lit(oak, {0, -1, 0}), y0 - DROP),
	)
}

// draw_hull_cap closes a frame across the beam — the transom aft and the stem's fine cross-
// section forward — so the loft is a solid with ends rather than an open shell.
draw_hull_cap :: proc(x, facing: f32) {
	for j in 0 ..< HULL_BANDS {
		t0 := f32(j) / HULL_BANDS
		t1 := f32(j + 1) / HULL_BANDS
		p0 := hull_surface(x, t0, -1)
		s0 := hull_surface(x, t0, 1)
		s1 := hull_surface(x, t1, 1)
		p1 := hull_surface(x, t1, -1)
		ship_quad_flat(p0, s0, s1, p1, hull_water(ship_lit(hull_timber(p0.y, j), ship_facing(p0, {facing, 0, 0})), p0.y))

		// And its inboard face, a plank's thickness in. The cut looks straight down the length of
		// the ship at both of these, so a cap with only an outside is a hole seen from within.
		in_ := rl.Vector3{facing * HULL_SKIN, 0, 0}
		ship_quad_lit(p0 - in_, s0 - in_, s1 - in_, p1 - in_, hull_timber_inner(j), {-facing, 0, 0})
	}
}

// draw_hull_sole lays the below-deck floor the compartments stand on, wall to wall, and closes
// it at both ends with a peak bulkhead.
//
// The compartments each carried a floor of their own and nothing else did, so what the eye got
// forward was a row of separate planes pinching away into the bow with no end to them and the
// bare inside of the hull showing between — a space that stopped existing rather than one that
// finished. A sole running the whole length under all of them, and a wall across each end of
// it, is what makes the belly of her one room with compartments in it. The peaks are what the
// forward one in particular was missing: something to be the front of.
draw_hull_sole :: proc() {
	floor := cutaway.GALLEON_HOLD_FLOOR_Y
	x0 := cutaway.GALLEON_HOLD_X0
	x1 := cutaway.GALLEON_HOLD_X1
	STEPS :: 22
	step := (x1 - x0) / STEPS
	deal := colour_shade(COLOUR_CLIFF, 0.62)

	for i in 0 ..< STEPS {
		a := x0 + f32(i) * step
		b := a + step
		wa := cutaway.galleon_frame_half_beam(a, floor) - HULL_SKIN
		wb := cutaway.galleon_frame_half_beam(b, floor) - HULL_SKIN
		tone := colour_shade(deal, i % 2 == 0 ? 1.0 : 0.92)
		ship_quad_lit({a, floor, -wa}, {b, floor, -wb}, {b, floor, wb}, {a, floor, wa}, tone, {0, 1, 0})
	}

	// The peaks: a bulkhead across each end of the sole, carried from the floor to the beams.
	// Solid, unlike a compartment's forward wall — nothing is looked into through them, and they
	// are the surface that says the hold ends here.
	ceiling := cutaway.GALLEON_HOLD_CEIL_Y
	for peak in ([2]f32{x0, x1}) {
		w := cutaway.galleon_frame_half_beam(peak, floor) - HULL_SKIN
		wt := cutaway.galleon_frame_half_beam(peak, ceiling) - HULL_SKIN
		ship_quad_lit(
			{peak, floor, -w},
			{peak, floor, w},
			{peak, ceiling, wt},
			{peak, ceiling, -wt},
			colour_shade(COLOUR_CLIFF, 0.80),
			{peak == x0 ? -1 : 1, 0, 0},
		)
	}
}

// draw_hull_wales bands her sides with the wales — the heavy strakes that take the chafe, and
// the gilded ribbon above them. They follow the section, so they curve with the hull instead of
// crossing it as a straight bar, and they are the strongest horizontal line on the ship.
draw_hull_wales :: proc() {
	Wale :: struct {
		t:         f32,
		thickness: f32,
		colour:    rl.Color,
	}
	wales := [3]Wale {
		{t = 0.985, thickness = 0.055, colour = COLOUR_SAND}, // the gilded rail cap
		{t = 0.80, thickness = 0.075, colour = colour_shade(COLOUR_ROCK, 0.52)},
		{t = 0.63, thickness = 0.065, colour = colour_shade(COLOUR_ROCK, 0.58)},
	}

	stern := cutaway.GALLEON_STERN_X
	bow := cutaway.GALLEON_BOW_X
	step := (bow - stern) / HULL_STRIPS

	for wale in wales {
		for i in 0 ..< HULL_STRIPS {
			x0 := stern + f32(i) * step
			x1 := x0 + step
			for side in ([2]f32{1, -1}) {
				// A port wale runs only where there is planking under it to run along: below the
				// window, or up on the bulwark. Across the window itself there is nothing to band.
				if side < 0 && wale.t > min(hull_cut_t(x0), hull_cut_t(x1)) && wale.t < max(hull_bulwark_t(x0), hull_bulwark_t(x1)) {
					continue
				}
				a := hull_surface(x0, wale.t, side)
				b := hull_surface(x1, wale.t, side)
				n0 := hull_normal(x0, wale.t, side)
				n1 := hull_normal(x1, wale.t, side)
				out := f32(0.028)
				lo := rl.Vector3{0, wale.thickness / 2, 0}
				ship_quad_lit(
					a + n0 * out - lo,
					b + n1 * out - lo,
					b + n1 * out + lo,
					a + n0 * out + lo,
					wale.colour,
					(n0 + n1) / 2,
				)
			}
		}
	}
}

// draw_hull_deck lays the weather deck: planks running fore and aft in her own planform, so the
// deck comes to a point at the bow the way the hull does, and the beams show on its underside —
// which is the ceiling every hold is looked into under.
draw_hull_deck :: proc() {
	deck := cutaway.GALLEON_DECK_Y
	stern := cutaway.GALLEON_STERN_X + 0.18
	bow := cutaway.GALLEON_BOW_X - 0.12
	STEPS :: 30
	step := (bow - stern) / STEPS
	PLANKS :: 7

	for i in 0 ..< STEPS {
		x0 := stern + f32(i) * step
		x1 := x0 + step
		// The deck runs *into* her planking, not up to it. Held 2cm short — which is what the
		// inset here used to be — it left a slit down each side between the deck edge and the
		// hull, and from a camera at deck height that slit is a thin bright line of sky running
		// along the foot of both castles: the daylight showing through her walls. A deck lands on
		// the shelf inside the frames and its edge is buried in the side, so the overlap is what
		// the real join looks like as well as what closes the hole. The underside below was
		// already drawn at full width, and that mismatch is what made the gap one-sided.
		w0 := cutaway.galleon_frame_half_beam(x0, deck) + 0.03
		w1 := cutaway.galleon_frame_half_beam(x1, deck) + 0.03

		for p in 0 ..< PLANKS {
			f0 := f32(p) / PLANKS * 2 - 1
			f1 := f32(p + 1) / PLANKS * 2 - 1
			tone := colour_shade(COLOUR_CLIFF, p % 2 == 0 ? 1.0 : 0.92)
			ship_quad_lit(
				{x0, deck, f0 * w0},
				{x1, deck, f0 * w1},
				{x1, deck, f1 * w1},
				{x0, deck, f1 * w0},
				tone,
				{0, 1, 0},
			)
		}

		// The underside, and a beam every few strips crossing it.
		under := colour_shade(COLOUR_ROCK, 0.72)
		ship_quad_lit(
			{x0, deck - 0.045, -w0},
			{x1, deck - 0.045, -w1},
			{x1, deck - 0.045, w1},
			{x0, deck - 0.045, w0},
			under,
			{0, -1, 0},
		)
		if i % 3 == 0 {
			ship_box({(x0 + x1) / 2, deck - 0.08, 0}, {0.07, 0.07, 2 * w0}, colour_shade(COLOUR_ROCK, 0.85))
		}
	}
}

// draw_hull_transom is her stern: the raked face across the quarters, the row of great-cabin
// lights across it, and the taffrail capping the lot. A galleon is known by her stern before
// anything else, so it is the one place the ornament is spent freely.
//
// It is built as a closed slab rather than a single plate. A plate has an edge, and every edge
// of it stood open onto the inside of the ship — you could see daylight between the transom and
// her quarters from almost anywhere on this camera. Outer face, inner face, and all four edges
// capped: the stern is now an object.
draw_hull_transom :: proc() {
	x := cutaway.GALLEON_STERN_X
	rail := cutaway.galleon_sheer_y(x)
	beam := cutaway.galleon_frame_half_beam(x, rail)
	top := rail + 0.44
	oak := colour_shade(COLOUR_ROCK, 0.94)

	// The four corners of the raked face, and the same four carried forward into the ship by
	// the slab's thickness.
	SLAB :: f32(0.13)
	outer := [4]rl.Vector3 {
		{x, rail - 0.08, -beam},
		{x, rail - 0.08, beam},
		{x - 0.22, top, beam * 0.94},
		{x - 0.22, top, -beam * 0.94},
	}
	inner: [4]rl.Vector3
	for corner, i in outer {
		inner[i] = corner + rl.Vector3{SLAB, 0, 0}
	}

	ship_quad_lit(outer[0], outer[1], outer[2], outer[3], oak, {-0.9, 0.44, 0})
	ship_quad_lit(inner[3], inner[2], inner[1], inner[0], hull_timber_inner(0), {0.9, -0.44, 0})
	// The four edges of the slab, each capped between the two faces: the quarters either side,
	// the head under the taffrail, and the heel where it meets her planking.
	for i in 0 ..< 4 {
		j := (i + 1) % 4
		normal := rl.Vector3Normalize(rl.Vector3CrossProduct(outer[j] - outer[i], inner[i] - outer[i]))
		ship_quad_lit(outer[i], outer[j], inner[j], inner[i], colour_shade(oak, 0.92), normal)
	}

	// The stern lights: a row of tall windows, warm behind their glazing bars.
	for k in 0 ..< 5 {
		z := (f32(k) / 4 * 2 - 1) * beam * 0.72
		ship_quad_lit(
			{x - 0.13, rail + 0.06, z - 0.11},
			{x - 0.13, rail + 0.06, z + 0.11},
			{x - 0.19, rail + 0.32, z + 0.10},
			{x - 0.19, rail + 0.32, z - 0.10},
			COLOUR_PARCHMENT,
			{-0.9, 0.44, 0},
		)
	}

	// The taffrail, and gilding under the lights.
	ship_box({x - 0.23, top + 0.03, 0}, {0.14, 0.07, 2 * beam * 0.96}, COLOUR_SAND)
	ship_box({x - 0.10, rail - 0.02, 0}, {0.1, 0.06, 2 * beam * 0.98}, COLOUR_SAND)
}

// draw_ship_ornament is the finery a flagship carries, hung off the rooms themselves rather
// than off positions of its own, so trim cannot drift away from the structure it crowns: a
// planked deck over every enclosed castle with a rail round it, the quarter galleries, the
// stern lantern, and the figurehead under the beakhead. The castles stand above the camera's
// eye, so what the eye actually reads of them is their roofs and their rails — which is why
// this is where the detail is spent.
draw_ship_ornament :: proc(rooms: [cutaway.MAX_SLOTS]cutaway.Room, n: int) {
	for i in 0 ..< n {
		room := rooms[i]
		if room.kind == .Hold || room.kind == .Waist {
			continue
		}
		top := room.centre.y + room.half.y + 0.03

		// The deck over the castle, planked athwartships and following the castle's own taper —
		// a roof cut to one width over a structure that narrows would overhang her side at the
		// fine end and stand back from it at the full one.
		PLANKS :: 6
		for p in 0 ..< PLANKS {
			x0 := room.centre.x + (f32(p) / PLANKS * 2 - 1) * (room.half.x + 0.05)
			x1 := room.centre.x + (f32(p + 1) / PLANKS * 2 - 1) * (room.half.x + 0.05)
			z0 := cutaway.galleon_room_half_z(room, x0) + 0.04
			z1 := cutaway.galleon_room_half_z(room, x1) + 0.04
			ship_quad_lit(
				{x0, top, room.centre.z - z0},
				{x1, top, room.centre.z - z1},
				{x1, top, room.centre.z + z1},
				{x0, top, room.centre.z + z0},
				colour_shade(COLOUR_CLIFF, p % 2 == 0 ? 1.0 : 0.9),
				{0, 1, 0},
			)
		}

		// The gilded band capping her side under that deck, run down both quarters with the same
		// taper — the strongest horizontal on the castle, and the line that ties roof to wall.
		for side in ([2]f32{1, -1}) {
			za := room.centre.z + side * (cutaway.galleon_room_half_z(room, room.centre.x - room.half.x) + 0.04)
			zf := room.centre.z + side * (cutaway.galleon_room_half_z(room, room.centre.x + room.half.x) + 0.04)
			x0 := room.centre.x - room.half.x - 0.05
			x1 := room.centre.x + room.half.x + 0.05
			ship_quad_lit(
				{x0, top - 0.075, za},
				{x1, top - 0.075, zf},
				{x1, top, zf},
				{x0, top, za},
				COLOUR_SAND,
				{0, 0, side},
			)
		}

		// The rail round that deck: a capping bar on stanchions, drawn down her port side and
		// across her after end, the two runs the camera sees.
		draw_ornament_rail(room, top)

		// The bulkhead the camera is looking at — a castle's forward face, since the camera
		// stands off the bow — carrying a door and its lights. A blank slab of timber this size
		// is what made the first pass's castles read as crates.
		draw_ornament_bulkhead(room)

		if room.kind == .Poop {
			// The stern lantern, on its standard over the taffrail.
			ship_box({room.centre.x - room.half.x + 0.06, top + 0.14, 0}, {0.05, 0.2, 0.05}, COLOUR_TRUNK)
			ship_box({room.centre.x - room.half.x + 0.06, top + 0.31, 0}, {0.17, 0.19, 0.17}, COLOUR_PARCHMENT)
			ship_box({room.centre.x - room.half.x + 0.06, top + 0.43, 0}, {0.09, 0.08, 0.09}, COLOUR_SAND)
		}

		// Lights down the far bulkhead of the great cabin, so the sterncastle is a room with
		// windows in it rather than a crate.
		if room.kind == .Sterncastle {
			for wx := room.centre.x - room.half.x + 0.2; wx < room.centre.x + room.half.x - 0.1; wx += 0.34 {
				z := room.centre.z + cutaway.galleon_room_half_z(room, wx) - 0.03
				ship_box({wx, room.centre.y + 0.04, z}, {0.2, 0.3, 0.03}, COLOUR_PARCHMENT)
				ship_box({wx, room.centre.y - 0.13, z}, {0.23, 0.04, 0.04}, COLOUR_SAND)
			}
		}
	}

	// The figurehead, under the beakhead where one belongs, and the trailboards sweeping back
	// from it along the stem.
	bow := cutaway.GALLEON_BOW_X
	rail := cutaway.galleon_sheer_y(bow)
	ship_box({bow + 0.16, rail - 0.16, 0}, {0.3, 0.3, 0.26}, COLOUR_PARCHMENT)
	ship_box({bow + 0.02, rail - 0.3, 0}, {0.24, 0.16, 0.2}, COLOUR_SAND)
}

// draw_ornament_bulkhead dresses the face of a castle the camera is looking straight at: a
// panelled door under a hooded lintel, a light either side of it, and the vertical battens
// between. All of it is hung a plank's thickness proud of the bulkhead, so the shading picks the
// pieces out without a single drawn outline.
draw_ornament_bulkhead :: proc(room: cutaway.Room) {
	x := room.centre.x + room.half.x + 0.03
	sill := room.centre.y - room.half.y
	height := 2 * room.half.y
	// The face is at the room's forward end, so it is that end's width the fittings are set out
	// across — the forecastle's forward bulkhead is barely a third the width of its after one.
	half_z := room.half_fore
	timber := colour_shade(COLOUR_CLIFF, 0.88)

	for k in 0 ..< 5 {
		z := room.centre.z + (f32(k) / 4 * 2 - 1) * max(half_z - 0.06, 0.02)
		ship_box({x, room.centre.y, z}, {0.03, height * 0.92, 0.05}, timber)
	}

	door := rl.Vector3{x + 0.02, sill + height * 0.34, room.centre.z}
	ship_box(door, {0.04, height * 0.56, min(0.24, half_z * 1.1)}, colour_shade(COLOUR_ROCK, 1.0))
	ship_box({door.x + 0.01, door.y + height * 0.3, door.z}, {0.06, 0.05, min(0.32, half_z * 1.4)}, COLOUR_SAND)

	// Lights either side of the door — only where the bulkhead is wide enough to carry them.
	if half_z > 0.34 {
		for side in ([2]f32{1, -1}) {
			z := room.centre.z + side * (half_z * 0.62)
			ship_box({x + 0.02, sill + height * 0.66, z}, {0.04, height * 0.2, 0.17}, COLOUR_PARCHMENT)
		}
	}
}

// draw_ornament_rail runs a stanchioned rail round the two edges of a castle's deck the camera
// can see: down her port side, and across her after end.
draw_ornament_rail :: proc(room: cutaway.Room, top: f32) {
	RAIL :: f32(0.15)
	post := colour_shade(COLOUR_TRUNK, 1.05)
	x_aft := room.centre.x - room.half.x - 0.05
	x_fore := room.centre.x + room.half.x + 0.05

	// Down her port side, each stanchion set on the roof edge where that edge actually runs.
	for k in 0 ..< 6 {
		x := x_aft + f32(k) / 5 * (x_fore - x_aft)
		z := room.centre.z - cutaway.galleon_room_half_z(room, x) - 0.04
		ship_box({x, top + RAIL / 2, z}, {0.035, RAIL, 0.035}, post)
	}
	z_aft := room.centre.z - cutaway.galleon_room_half_z(room, x_aft) - 0.04
	z_fore := room.centre.z - cutaway.galleon_room_half_z(room, x_fore) - 0.04
	ship_quad_lit(
		{x_aft, top + RAIL, z_aft},
		{x_fore, top + RAIL, z_fore},
		{x_fore, top + RAIL + 0.045, z_fore},
		{x_aft, top + RAIL + 0.045, z_aft},
		COLOUR_SAND,
		{0, 0, -1},
	)

	// And across her after end.
	half_aft := room.half_aft + 0.04
	for k in 0 ..< 4 {
		f := f32(k) / 3
		ship_box({x_aft, top + RAIL / 2, room.centre.z - half_aft + f * 2 * half_aft}, {0.035, RAIL, 0.035}, post)
	}
	ship_box({x_aft, top + RAIL, room.centre.z}, {0.05, 0.04, 2 * half_aft}, COLOUR_SAND)
}

// draw_hull_stem is her bow above water: the stempost carrying up out of the planking, the
// beakhead thrust forward under the bowsprit, and the head rails sweeping back to the
// forecastle. It is the profile the camera looks straight into, so it is where the eye decides
// whether this is a ship or a box.
draw_hull_stem :: proc() {
	x := cutaway.GALLEON_BOW_X
	rail := cutaway.galleon_sheer_y(x)
	oak := colour_shade(COLOUR_ROCK, 0.86)

	// The stempost, raked forward as it climbs. It starts at the waterline and no lower: her
	// planking now closes to a true edge at the stem, so below the water the two sides *are* the
	// cutwater, and a timber run down over them would only stand proud of the point they make.
	ship_spar({x - 0.02, 0, 0}, {x + 0.22, rail + 0.22, 0}, 0.06, 0.045, oak)

	// The beakhead: a short grated platform out over the water, kept low and narrow. The camera
	// stands barely two lengths off the stem, so anything built out here is drawn enormous — the
	// head is the one place on the ship where less is more.
	ship_box({x + 0.24, rail - 0.06, 0}, {0.44, 0.05, 0.26}, colour_shade(COLOUR_CLIFF, 0.86))

	// The head rails, sweeping back from the stem to her bow — thin, so they draw the eye along
	// the curve of the bow instead of blocking it.
	for side in ([2]f32{1, -1}) {
		ship_rope(
			{x + 0.42, rail + 0.02, side * 0.12},
			{x - 0.62, rail + 0.16, side * cutaway.galleon_frame_half_beam(x - 0.62, rail) * 0.92},
			0.022,
			ship_lit(COLOUR_SAND, {0.4, 0.6, -0.6}),
		)
	}
}
