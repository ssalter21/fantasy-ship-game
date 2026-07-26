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
HULL_STRIPS :: 34
HULL_BANDS :: 10

// HULL_SKIN is how thick her planking is — the timber the cut edge shows, and the offset
// between the outer skin and the inner face of the same strake.
HULL_SKIN :: f32(0.055)

// HULL_CUT_Y is where the port planking is opened to: a hand's breadth under the hold floor, so
// the compartments stand clear of the cut rather than sitting behind it.
HULL_CUT_Y :: cutaway.GALLEON_HOLD_FLOOR_Y - 0.07

// HULL_DEPTH_TINT is how far a surface a fathom down is pulled toward the water's own colour.
// The tropics are the whole reason: the sea here is clear enough to see the copper through, and
// a bottom that greens off with depth is what settles the ship *into* the water instead of
// leaving her standing on a blue rectangle.
HULL_DEPTH_TINT :: f32(0.74)

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
// from just under the hold floor, closing up to the rail at the stem so the bow wraps round
// rather than ending in a slice.
hull_cut_t :: proc(x: f32) -> f32 {
	closing := clamp((x - 3.05) / 0.62, 0, 1)
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

// hull_timber is a strake's wood at height y: oak topsides in alternating courses, and copper
// sheathing under the waterline going green with depth. The alternation is what gives the skin
// planking without a single drawn line.
hull_timber :: proc(y: f32, band: int) -> rl.Color {
	if y < 0 {
		copper := colour_shade(COLOUR_CLIFF, band % 2 == 0 ? 1.0 : 0.9)
		return colour_mix(copper, COLOUR_SEA_BRIGHT, min(-y / 0.85, 1) * HULL_DEPTH_TINT)
	}
	// Her topsides are deliberately the darkest warm on the ship. Everything built on the deck —
	// castles, rails, deck planking — is the lighter sand, so the hull reads as one mass under
	// them instead of the whole ship washing out into a single tan.
	return colour_shade(COLOUR_ROCK, band % 2 == 0 ? 0.88 : 0.76)
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
		cut := min(hull_cut_t(x0), hull_cut_t(x1))
		bulwark := max(hull_bulwark_t(x0), hull_bulwark_t(x1))
		draw_hull_side(x0, x1, 1, 0, 1) // starboard, whole from keel to rail
		draw_hull_side(x0, x1, -1, 0, cut) // port below the window
		draw_hull_side(x0, x1, -1, bulwark, 1) // port above it: the bulwark and its rail
		draw_hull_cut_edge(x0, x1, hull_cut_t, 1)
		draw_hull_cut_edge(x0, x1, hull_bulwark_t, -1)
		draw_hull_keel(x0, x1)
	}

	draw_hull_cap(stern, -1)
	draw_hull_cap(bow, 1)
	draw_hull_wales()
	draw_hull_deck()
	draw_hull_transom()
	draw_hull_stem()
}

// draw_hull_side plates one strip of one side over a run of the section, `lo` to `hi`. Both
// faces of the planking are laid: the outer skin, and the inner face the cutaway looks across
// the ship at — lit by the opposite normal, since a hull's inside is in its own shadow. Strakes
// are counted off the section itself rather than off this run's subdivisions, so the courses
// line up across a cut instead of stepping at it.
draw_hull_side :: proc(x0, x1, side, lo, hi: f32) {
	if hi - lo <= 0.002 {
		return
	}
	for j in 0 ..< HULL_BANDS {
		t0 := lo + (hi - lo) * f32(j) / HULL_BANDS
		t1 := lo + (hi - lo) * f32(j + 1) / HULL_BANDS

		a := hull_surface(x0, t0, side)
		b := hull_surface(x1, t0, side)
		c := hull_surface(x1, t1, side)
		d := hull_surface(x0, t1, side)
		normal := hull_normal((x0 + x1) / 2, (t0 + t1) / 2, side)
		timber := hull_timber((a.y + d.y) / 2, int((t0 + t1) * 7))

		ship_quad_lit(a, b, c, d, timber, normal)

		inner := normal * HULL_SKIN
		ship_quad_lit(a - inner, b - inner, c - inner, d - inner, colour_shade(timber, 0.88), -normal)
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
	KEEL :: f32(0.075)
	DROP :: f32(0.09)
	oak := colour_mix(colour_shade(COLOUR_ROCK, 0.8), COLOUR_SEA_BRIGHT, min(-(y0 + y1) / 2 / 0.85, 1) * HULL_DEPTH_TINT)

	ship_quad_lit({x0, y0 - DROP, -KEEL}, {x1, y1 - DROP, -KEEL}, {x1, y1, -KEEL}, {x0, y0, -KEEL}, oak, {0, 0, -1})
	ship_quad_lit({x0, y0 - DROP, KEEL}, {x0, y0, KEEL}, {x1, y1, KEEL}, {x1, y1 - DROP, KEEL}, oak, {0, 0, 1})
	ship_quad_lit(
		{x0, y0 - DROP, -KEEL},
		{x0, y0 - DROP, KEEL},
		{x1, y1 - DROP, KEEL},
		{x1, y1 - DROP, -KEEL},
		colour_shade(oak, 0.8),
		{0, -1, 0},
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
		ship_quad_lit(p0, s0, s1, p1, hull_timber(p0.y, j), {facing, 0, 0})
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
		w0 := cutaway.galleon_frame_half_beam(x0, deck) - 0.02
		w1 := cutaway.galleon_frame_half_beam(x1, deck) - 0.02

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

// draw_hull_transom is her stern: the flat raked face across the quarters, the row of great-
// cabin lights across it, and the taffrail capping the lot. A galleon is known by her stern
// before anything else, so it is the one place the ornament is spent freely.
draw_hull_transom :: proc() {
	x := cutaway.GALLEON_STERN_X
	rail := cutaway.galleon_sheer_y(x)
	beam := cutaway.galleon_frame_half_beam(x, rail)
	top := rail + 0.44

	// The transom face, raked aft as it rises.
	ship_quad_lit(
		{x, rail - 0.08, -beam},
		{x, rail - 0.08, beam},
		{x - 0.22, top, beam * 0.94},
		{x - 0.22, top, -beam * 0.94},
		colour_shade(COLOUR_ROCK, 0.94),
		{-0.9, 0.44, 0},
	)

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

		// The deck over the castle, planked athwartships, and the gilded band capping its side.
		PLANKS :: 6
		for p in 0 ..< PLANKS {
			x0 := room.centre.x + (f32(p) / PLANKS * 2 - 1) * (room.half.x + 0.05)
			x1 := room.centre.x + (f32(p + 1) / PLANKS * 2 - 1) * (room.half.x + 0.05)
			ship_quad_lit(
				{x0, top, room.centre.z - room.half.z - 0.04},
				{x1, top, room.centre.z - room.half.z - 0.04},
				{x1, top, room.centre.z + room.half.z + 0.04},
				{x0, top, room.centre.z + room.half.z + 0.04},
				colour_shade(COLOUR_CLIFF, p % 2 == 0 ? 1.0 : 0.9),
				{0, 1, 0},
			)
		}
		ship_box(
			{room.centre.x, top - 0.045, room.centre.z},
			{2 * room.half.x + 0.12, 0.06, 2 * room.half.z + 0.1},
			COLOUR_SAND,
		)

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
			z := room.centre.z + room.half.z - 0.03
			for wx := room.centre.x - room.half.x + 0.2; wx < room.centre.x + room.half.x - 0.1; wx += 0.34 {
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
	timber := colour_shade(COLOUR_CLIFF, 0.88)

	for k in 0 ..< 5 {
		z := room.centre.z + (f32(k) / 4 * 2 - 1) * (room.half.z - 0.06)
		ship_box({x, room.centre.y, z}, {0.03, height * 0.92, 0.05}, timber)
	}

	door := rl.Vector3{x + 0.02, sill + height * 0.34, room.centre.z}
	ship_box(door, {0.04, height * 0.56, 0.24}, colour_shade(COLOUR_ROCK, 1.0))
	ship_box({door.x + 0.01, door.y + height * 0.3, door.z}, {0.06, 0.05, 0.32}, COLOUR_SAND)

	for side in ([2]f32{1, -1}) {
		z := room.centre.z + side * (room.half.z * 0.62)
		ship_box({x + 0.02, sill + height * 0.66, z}, {0.04, height * 0.2, 0.17}, COLOUR_PARCHMENT)
	}
}

// draw_ornament_rail runs a stanchioned rail round the two edges of a castle's deck the camera
// can see: down her port side, and across her after end.
draw_ornament_rail :: proc(room: cutaway.Room, top: f32) {
	RAIL :: f32(0.15)
	post := colour_shade(COLOUR_TRUNK, 1.05)
	z := room.centre.z - room.half.z - 0.04
	x_aft := room.centre.x - room.half.x - 0.05

	for k in 0 ..< 6 {
		f := f32(k) / 5
		ship_box({x_aft + f * 2 * (room.half.x + 0.05), top + RAIL / 2, z}, {0.035, RAIL, 0.035}, post)
	}
	ship_box({room.centre.x, top + RAIL, z}, {2 * room.half.x + 0.12, 0.04, 0.05}, COLOUR_SAND)

	for k in 0 ..< 4 {
		f := f32(k) / 3
		ship_box({x_aft, top + RAIL / 2, z + f * 2 * (room.half.z + 0.04)}, {0.035, RAIL, 0.035}, post)
	}
	ship_box({x_aft, top + RAIL, room.centre.z}, {0.05, 0.04, 2 * room.half.z + 0.08}, COLOUR_SAND)
}

// draw_hull_stem is her bow above water: the stempost carrying up out of the planking, the
// beakhead thrust forward under the bowsprit, and the head rails sweeping back to the
// forecastle. It is the profile the camera looks straight into, so it is where the eye decides
// whether this is a ship or a box.
draw_hull_stem :: proc() {
	x := cutaway.GALLEON_BOW_X
	rail := cutaway.galleon_sheer_y(x)
	oak := colour_shade(COLOUR_ROCK, 0.86)

	// The stempost, raked forward as it climbs.
	ship_spar({x - 0.06, cutaway.galleon_keel_y(x) + 0.1, 0}, {x + 0.22, rail + 0.22, 0}, 0.085, 0.052, oak)

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
