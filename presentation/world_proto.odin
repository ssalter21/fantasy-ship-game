package presentation

import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import cutaway "./cutaway"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// PROTOTYPE — THROWAWAY. Not a screen, not a tool the game ships, and not a decision.
//
// It exists to answer one question, issue #512: *does the sea and sky become 3D space, or stay
// flat layers that fake depth?* You cannot fog a 2D band, and today sky and sea are flat dithered
// rectangles on a 4-logical-pixel lattice (backdrop.odin, ship_sea.odin) composited **under** a
// genuinely 3D ship (ship_cutaway.odin). The reference's depth comes from atmospheric recession
// through real space, and there is no space here to recede through.
//
// So this stands the *existing* galleon — the real loft, the real rooms, the real rig, untouched —
// in three structurally different worlds at three depths of haze, and photographs the nine frames
// onto one sheet. Nothing here is a proposal for how the shipped code should be organised; it is
// the cheapest thing that shows the difference, which is what #512 asks to be decided by looking.
//
//	odin run cmd/game -- --world-proto        one PNG, nine tiles, then exits
//	odin run cmd/game -- --world-proto-live   the real window, through the real blit, steerable
//
// **No shaders.** Deliberately: #513 is still establishing what raylib's shader path gives us, and
// #515 has yet to decide where light is computed. Every gradient here is per-face or per-band
// arithmetic on the CPU, the same currency ship_paint.odin already pays in — so this settles the
// *structural* question without prejudging either of those. It also means what you see is a floor,
// not a ceiling: a fragment shader can only do this better.
//
// What it does **not** answer, so nobody reads it as having: the resolution question (#514 — the
// sheet is composed at exact logical size and never sees the upscale; use --world-proto-live for
// that), the colour-roster question (#516 — the haze here is COLOUR_HAZE because it had to be
// something), and the chrome retune (#518 — no chrome is drawn at all).

@(private)
WORLD_PROTO_FILE :: "world-proto.png"

// The three candidates #512 puts up, in the order they are argued there.
@(private)
World_Proto_World :: enum {
	Space, // real 3D: sea, sky and islands are geometry inside the existing BeginMode3D block
	Plates, // 2.5D: sky, sea and islands stay 2D layers, each tinted by a depth value
	Hybrid, // 3D sea, layered sky and islands
}

@(private)
world_proto_world_name :: proc(world: World_Proto_World) -> string {
	switch world {
	case .Space:
		return "real 3D world"
	case .Plates:
		return "2.5D layered plates"
	case .Hybrid:
		return "hybrid: 3D sea, layered sky"
	}
	return "?"
}

// The haze the sheet's columns run through. Three depths rather than two because the interesting
// reading is not light-vs-heavy but *where it stops helping* — the middle column is the one that
// has to look like a decision rather than like a compromise.
@(private)
World_Proto_Haze :: struct {
	name:    string,
	density: f32,
}

@(private)
WORLD_PROTO_HAZES := [?]World_Proto_Haze {
	{name = "light haze", density = 0.0035},
	{name = "medium haze", density = 0.0100},
	{name = "heavy haze", density = 0.0240},
}

// Where fog starts, in world units. The galleon is about seven units long and the camera stands
// 6.92 out, so her own surfaces sit between roughly 3 and 11 — and the reference's midground
// subject is *not* hazed, it is the thing the haze is behind. Starting the fog past her keeps her
// the lit subject and leaves the recession to everything beyond. A fog that begins at the eye
// would answer a different question (and grey the ship out), so this is a knob, not a constant of
// nature: --world-proto-live moves it.
@(private)
WORLD_PROTO_FOG_START :: f32(12)

// The colour everything recedes into. COLOUR_HAZE is the roster's existing "band of sky just above
// the horizon", which is the one swatch on the roster that already means *distance* — so it is the
// least prejudicial choice available while #516 is open. Note what picking it costs: fog **lerps
// toward a third colour**, which is precisely the guarantee style-guide.md:526 spends to permit
// lighting at all ("a lit face and a shadowed one are the same swatch under different light rather
// than two colours"). Every tile on this sheet breaks that written rule on purpose. Nothing fails
// — the enforcing test covers widgets only — which is exactly why #517 exists.
@(private)
world_proto_fog_colour :: proc() -> rl.Color {
	return COLOUR_HAZE
}

// world_proto_haze is how much of a surface at `dist` has been eaten by air: exponential
// extinction, the standard model and the one raylib's own fog example uses. Beyond about three
// e-folds it is indistinguishable from the fog colour, which is what makes a far plane optional
// rather than a cliff.
@(private)
world_proto_haze_at :: proc(dist, density: f32) -> f32 {
	return 1 - math.exp(-density * max(dist - WORLD_PROTO_FOG_START, 0))
}

// world_proto_fogged is one surface seen through that air.
@(private)
world_proto_fogged :: proc(colour: rl.Color, dist, density: f32) -> rl.Color {
	return colour_mix(colour, world_proto_fog_colour(), world_proto_haze_at(dist, density))
}

// ---------------------------------------------------------------------------------------------
// The light model: the shipped one, or a go at the reference's
// ---------------------------------------------------------------------------------------------

// When set, every lit surface in the frame — the world this file draws *and* the hull, through a
// hook at the top of `ship_lit` — takes the model below instead of the shipped one. Prototype
// state, and the hook in ship_paint.odin goes out with it.
world_proto_soft_light: bool

// The shipped model is `AMBIENT + SUNLIGHT * max(dot(n, sun), 0)` — a hard terminator, because
// everything facing more than 90 degrees off the sun clamps to exactly the same ambient. That is
// what makes the current hull read as faceted-and-hard rather than faceted-and-soft, and no amount
// of raising the ambient fixes it: it flattens the lit half without ever softening the edge.
//
// Half-Lambert wraps the light right round the form instead, so the falloff is continuous from the
// key to the far side. Squaring it puts the contrast back that wrapping takes out. This is the
// cheapest thing that is actually the reference's *soft light falloff on flat-shaded low-poly*
// rather than an imitation of it, and it costs one multiply.
@(private)
WORLD_PROTO_SOFT_AMBIENT :: f32(0.46)
@(private)
WORLD_PROTO_SOFT_KEY :: f32(0.74)

// **A cool ambient broken by one warm key** — the reference's colour structure, and the thing the
// current four scalars cannot express at all, because `colour_shade` multiplies a swatch by a
// *scalar*: a lit face and a shadowed one are the same hue at two brightnesses. Here the light
// itself carries colour, so a surface travels cool-to-warm as it turns to the key rather than
// dark-to-bright at one hue.
//
// Both are normalised to a 255 peak so modulating by them tints without dimming. **Deliberately
// not coral** — the roster's only saturated warm is reserved for danger and the chart's X (#516,
// style-guide.md:142), and a key light spends its colour over the whole frame. This warm is a
// low-saturation gold that does not read as the danger swatch; whether it may exist at all is
// #516's call, not this prototype's.
@(private)
WORLD_PROTO_KEY_WARM :: rl.Color{255, 216, 158, 255}
@(private)
WORLD_PROTO_AMBIENT_COOL :: rl.Color{138, 186, 255, 255}

// world_proto_modulate is light times surface, per channel — real modulation rather than a lerp
// toward the light colour. A lerp washes a surface out toward the light as the light strengthens;
// a multiply keeps the surface's own hue and lets the light colour it, which is the difference
// between tinted timber and beige.
@(private)
world_proto_modulate :: proc(surface, light: rl.Color) -> rl.Color {
	channel :: proc(s, l: u8) -> u8 {
		return u8(clamp(f32(s) * f32(l) / 255, 0, 255))
	}
	return {
		channel(surface.r, light.r),
		channel(surface.g, light.g),
		channel(surface.b, light.b),
		surface.a,
	}
}

// world_proto_lit is one surface under the soft model.
world_proto_lit :: proc(base: rl.Color, normal: rl.Vector3) -> rl.Color {
	n := rl.Vector3Normalize(normal)
	sun := rl.Vector3Normalize(SHIP_SUN)
	wrap := rl.Vector3DotProduct(n, sun) * 0.5 + 0.5
	wrap *= wrap
	fill := SHIP_SKY_FILL * max(n.y, 0) + SHIP_SEA_FILL * max(-n.y, 0)
	lit := colour_shade(base, WORLD_PROTO_SOFT_AMBIENT + WORLD_PROTO_SOFT_KEY * wrap + fill)
	return world_proto_modulate(lit, colour_mix(WORLD_PROTO_AMBIENT_COOL, WORLD_PROTO_KEY_WARM, wrap))
}

// ---------------------------------------------------------------------------------------------
// The 3D world: sea, sky and islands as geometry
// ---------------------------------------------------------------------------------------------

// The sea's grid. Rings from the eye outward with radii growing geometrically, so the water is
// finely tessellated where a wave is a shape and coarse where it is a pixel — the same
// distribution ship_sea.odin fakes in 2D by growing its chop down the frame, except here it falls
// out of the geometry instead of being drawn in.
@(private)
WORLD_PROTO_SEA_RINGS :: 44
@(private)
WORLD_PROTO_SEA_SEGMENTS :: 64
@(private)
WORLD_PROTO_SEA_NEAR :: f32(0.6)
@(private)
WORLD_PROTO_SEA_FAR :: f32(420)

// The swell's height, in world units — about 1.0 m if the galleon's seven units are 30 m.
//
// **This number is the whole ball game for the 3D candidates, and it is a design choice, not a
// measurement.** GALLEON_CAM_HEIGHT is 0.0: the shipped eye sits *exactly on* the water plane. A
// flat plane containing the eye projects to a single screen row, so a real 3D sea is only visible
// at all to the extent that it is not flat — every pixel of water you get is swell standing above
// the eye. Set this to a physically honest 0.1 and the sea is a ten-pixel band under the horizon;
// set it to 0.6 and you are in a gale. --world-proto-live puts it on a key for exactly that
// reason, and the sheet's caption prints it so no tile can be read without it.
@(private)
WORLD_PROTO_SWELL :: f32(0.26)

// world_proto_wave is the swell's height at a point: two crossed sinusoids, which is enough for
// broken water to read as broken and cheap enough to evaluate five times per vertex for normals.
// A real one would be noise-summed; that is not what is being decided here.
@(private)
world_proto_wave :: proc(x, z, swell: f32) -> f32 {
	return swell * (math.sin(x * 0.9 + z * 0.42) * 0.6 + math.sin(x * 0.33 - z * 1.05) * 0.4)
}

@(private)
world_proto_wave_point :: proc(x, z, swell: f32) -> rl.Vector3 {
	return {x, world_proto_wave(x, z, swell), z}
}

// world_proto_wave_normal is the surface normal by finite difference. Flat-shaded per quad, like
// everything else the ship is painted with — a smooth-shaded sea in a game whose hull is
// deliberately faceted would be the one soft thing in the frame.
@(private)
world_proto_wave_normal :: proc(x, z, swell: f32) -> rl.Vector3 {
	E :: f32(0.05)
	dx := (world_proto_wave(x + E, z, swell) - world_proto_wave(x - E, z, swell)) / (2 * E)
	dz := (world_proto_wave(x, z + E, swell) - world_proto_wave(x, z - E, swell)) / (2 * E)
	return rl.Vector3Normalize({-dx, 1, -dz})
}

// world_proto_quad paints one flat surface, one colour, both windings — the sea and the islands
// are looked at from grazing angles where a culled face is a hole. ship_quad_flat would do, but it
// carries the hull's below-waterline slicing with it and none of that applies here.
@(private)
world_proto_quad :: proc(a, b, c, d: rl.Vector3, colour: rl.Color) {
	rl.DrawTriangle3D(a, b, c, colour)
	rl.DrawTriangle3D(a, c, d, colour)
	rl.DrawTriangle3D(c, b, a, colour)
	rl.DrawTriangle3D(d, c, a, colour)
}

// world_proto_inside_hull reports whether a point on the water plane stands inside her waterline
// plan — her exact shape where she cuts the surface, from the same loft the hull is drawn off
// (`galleon_frame_half_beam(x, 0)`), not a box drawn round her.
//
// **This is what stops the sea filling her open side.** She is a cutaway: her port side is opened
// and her below-deck compartments are meant to be looked into, and several of them sit below the
// waterline. An opaque sea of real geometry runs between the camera and that opening and hides
// them — which is a correctness failure, not a cosmetic one, because those rooms are hover targets
// and drag targets (`galleon_room_at`). So the water is cut away exactly where she is, the way a
// museum cutaway cuts the water away around the model. What you see through the hole is her own
// interior — the sole, the bulkheads, the inboard planking — because the hull encloses it. There is
// no void to fall through.
@(private)
world_proto_inside_hull :: proc(x, z: f32) -> bool {
	if x < cutaway.GALLEON_STERN_X || x > cutaway.GALLEON_BOW_X {
		return false
	}
	return abs(z) < cutaway.galleon_frame_half_beam(x, 0)
}

// world_proto_sea_3d is the water as geometry, centred on the eye and lit by the same sun and the
// same Lambert the hull takes (ship_lit), then hazed by each quad's real distance. This is the
// candidate's whole claim: depth cueing becomes a function of z rather than something drawn in.
@(private)
world_proto_sea_3d :: proc(view: cutaway.View, density, swell: f32) {
	eye := view.camera.position
	step := math.pow(WORLD_PROTO_SEA_FAR / WORLD_PROTO_SEA_NEAR, 1.0 / f32(WORLD_PROTO_SEA_RINGS))

	r0 := WORLD_PROTO_SEA_NEAR
	for ring in 0 ..< WORLD_PROTO_SEA_RINGS {
		r1 := r0 * step
		for seg in 0 ..< WORLD_PROTO_SEA_SEGMENTS {
			a0 := 2 * math.PI * f32(seg) / f32(WORLD_PROTO_SEA_SEGMENTS)
			a1 := 2 * math.PI * f32(seg + 1) / f32(WORLD_PROTO_SEA_SEGMENTS)

			// How much of this quad her waterline plan takes out. A quad clear of her is drawn
			// whole; a quad wholly inside her is skipped; and only a quad on the boundary pays for
			// subdivision. That local refinement is the whole reason the hole can follow her
			// planking: the grid out here is more than a unit across at her range, which would carve
			// her a hole about six quads long and read as a torn rectangle rather than as a ship.
			in00 := world_proto_sea_inside(eye, r0, a0, swell)
			in01 := world_proto_sea_inside(eye, r0, a1, swell)
			in11 := world_proto_sea_inside(eye, r1, a1, swell)
			in10 := world_proto_sea_inside(eye, r1, a0, swell)

			if in00 && in01 && in11 && in10 {
				continue
			}
			if in00 || in01 || in11 || in10 {
				world_proto_sea_patch(view, r0, r1, a0, a1, density, swell)
				continue
			}
			world_proto_sea_cell(view, r0, r1, a0, a1, density, swell)
		}
		r0 = r1
	}
}

@(private)
world_proto_sea_inside :: proc(eye: rl.Vector3, r, a, swell: f32) -> bool {
	return world_proto_inside_hull(eye.x + r * math.sin(a), eye.z + r * math.cos(a))
}

// world_proto_sea_patch subdivides one boundary quad and draws the sub-cells that are still water.
@(private)
world_proto_sea_patch :: proc(view: cutaway.View, r0, r1, a0, a1, density, swell: f32) {
	SUB :: 10
	for i in 0 ..< SUB {
		ri0 := r0 + (r1 - r0) * f32(i) / SUB
		ri1 := r0 + (r1 - r0) * f32(i + 1) / SUB
		for j in 0 ..< SUB {
			aj0 := a0 + (a1 - a0) * f32(j) / SUB
			aj1 := a0 + (a1 - a0) * f32(j + 1) / SUB
			rm, am := (ri0 + ri1) / 2, (aj0 + aj1) / 2
			if world_proto_sea_inside(view.camera.position, rm, am, swell) {
				continue
			}
			world_proto_sea_cell(view, ri0, ri1, aj0, aj1, density, swell)
		}
	}
}

// world_proto_sea_cell paints one cell of water, lit and hazed.
@(private)
world_proto_sea_cell :: proc(view: cutaway.View, r0, r1, a0, a1, density, swell: f32) {
	eye := view.camera.position
	s0, c0 := math.sin(a0), math.cos(a0)
	s1, c1 := math.sin(a1), math.cos(a1)

	p00 := world_proto_wave_point(eye.x + r0 * s0, eye.z + r0 * c0, swell)
	p01 := world_proto_wave_point(eye.x + r0 * s1, eye.z + r0 * c1, swell)
	p11 := world_proto_wave_point(eye.x + r1 * s1, eye.z + r1 * c1, swell)
	p10 := world_proto_wave_point(eye.x + r1 * s0, eye.z + r1 * c0, swell)

	centre := (p00 + p01 + p11 + p10) / 4
	n := world_proto_wave_normal(centre.x, centre.z, swell)

	// A crest catches the sky and a trough is the deep looking up through itself. Off the height
	// rather than off a noise field, so the shading agrees with the shape.
	crest := clamp(centre.y / max(swell, 0.001) * 0.5 + 0.5, 0, 1)
	base := colour_mix(COLOUR_SEA_DEEP, COLOUR_SEA_SHALLOW, crest)
	lit := ship_lit(base, n)
	dist := rl.Vector3Length(centre - eye)
	world_proto_quad(p00, p01, p11, p10, world_proto_fogged(lit, dist, density))
}

// The sky as geometry: a dome, banded by elevation. Deliberately **not** fogged — the sky is what
// the fog is a haze *of*, so hazing it would mix the fog colour into itself and flatten the whole
// upper frame to one tone. That is an architectural fact worth having in front of you: the fog
// colour and the sky's colour at the horizon have to be the same value, or the join between them
// is a visible seam no amount of density tuning removes.
@(private)
WORLD_PROTO_DOME_RADIUS :: f32(900)
@(private)
WORLD_PROTO_DOME_BANDS :: 10
@(private)
WORLD_PROTO_DOME_SEGMENTS :: 32

@(private)
world_proto_sky_3d :: proc(view: cutaway.View) {
	eye := view.camera.position
	// Starts *below* the horizon so no gap opens between the dome's hem and the sea's far ring.
	LOW :: f32(-6)
	HIGH :: f32(90)

	for band in 0 ..< WORLD_PROTO_DOME_BANDS {
		e0 := math.to_radians(LOW + (HIGH - LOW) * f32(band) / f32(WORLD_PROTO_DOME_BANDS))
		e1 := math.to_radians(LOW + (HIGH - LOW) * f32(band + 1) / f32(WORLD_PROTO_DOME_BANDS))
		// The band's colour by elevation: haze at the hem climbing to the deep of the zenith. Real
		// interpolation, no ordered dither — that retirement is the point of the whole map.
		k0 := f32(band) / f32(WORLD_PROTO_DOME_BANDS)
		colour := colour_mix(world_proto_fog_colour(), COLOUR_SKY_HIGH, k0 * k0)

		for seg in 0 ..< WORLD_PROTO_DOME_SEGMENTS {
			a0 := 2 * math.PI * f32(seg) / f32(WORLD_PROTO_DOME_SEGMENTS)
			a1 := 2 * math.PI * f32(seg + 1) / f32(WORLD_PROTO_DOME_SEGMENTS)
			point :: proc(eye: rl.Vector3, elev, azim: f32) -> rl.Vector3 {
				r := WORLD_PROTO_DOME_RADIUS
				return {
					eye.x + r * math.cos(elev) * math.sin(azim),
					r * math.sin(elev),
					eye.z + r * math.cos(elev) * math.cos(azim),
				}
			}
			world_proto_quad(
				point(eye, e0, a0),
				point(eye, e0, a1),
				point(eye, e1, a1),
				point(eye, e1, a0),
				colour,
			)
		}
	}
}

// The islands: the reference's receding planes of rock, and the only content this prototype draws
// that is not already in the game. They are in scope (the map's Notes name "sky, sea, islands, sun,
// and the lit hull and rig"); the reference's figures, campfire, beach and foliage props are not,
// and none of them are here.
//
// Four of them at four distances, because *one* island cannot show recession — the whole claim
// under test is that depth reads as a series of planes, and a series needs members.
@(private)
World_Proto_Island :: struct {
	angle:  f32, // degrees off the eye's forward, so a placement stays in frame from any framing
	dist:   f32,
	width:  f32,
	height: f32,
}

// Placed by *angle* off the eye's forward rather than in world coordinates, so the first pass's
// mistake cannot recur: an island 27 units out and 10 wide subtends 21 degrees, which put it under
// her forefoot and read as ground she was aground on. The frame is ±43 degrees horizontally (a
// 55.24-degree vertical fov at 1244x700), and she herself spans about ±25 — so a near plane has to
// sit beyond 30 degrees to frame her rather than beach her.
@(private)
WORLD_PROTO_ISLANDS := [?]World_Proto_Island {
	// The near plane. This is the reference's dark foreground framing, and the one place this
	// prototype takes a liberty: at sea there is no natural near-black element to frame with, so a
	// close island stands in for the rocks the reference puts in the corners of its frame.
	{angle = -37, dist = 58, width = 16, height = 5.5},
	{angle = 34, dist = 110, width = 30, height = 9},
	{angle = -14, dist = 210, width = 60, height = 16},
	{angle = 12, dist = 380, width = 130, height = 30},
}

@(private)
world_proto_island_place :: proc(view: cutaway.View, island: World_Proto_Island) -> rl.Vector3 {
	forward := view.camera.target - view.camera.position
	forward.y = 0
	forward = rl.Vector3Normalize(forward)
	right := rl.Vector3{-forward.z, 0, forward.x}
	offset := island.dist * math.tan(math.to_radians(island.angle))
	return view.camera.position + forward * island.dist + right * offset
}

// world_proto_box is a lit solid, hazed by its own distance. ship_box would do the lighting but not
// the haze, and threading fog through the shipped painter is a change to production code this
// prototype has no business making.
@(private)
world_proto_box :: proc(centre, size: rl.Vector3, base: rl.Color, eye: rl.Vector3, density: f32) {
	h := size / 2
	x0, x1 := centre.x - h.x, centre.x + h.x
	y0, y1 := centre.y - h.y, centre.y + h.y
	z0, z1 := centre.z - h.z, centre.z + h.z
	dist := rl.Vector3Length(centre - eye)

	face :: proc(a, b, c, d: rl.Vector3, base: rl.Color, n: rl.Vector3, dist, density: f32) {
		world_proto_quad(a, b, c, d, world_proto_fogged(ship_lit(base, n), dist, density))
	}
	face({x0, y1, z0}, {x1, y1, z0}, {x1, y1, z1}, {x0, y1, z1}, base, {0, 1, 0}, dist, density)
	face({x1, y0, z0}, {x1, y0, z1}, {x1, y1, z1}, {x1, y1, z0}, base, {1, 0, 0}, dist, density)
	face({x0, y0, z0}, {x0, y1, z0}, {x0, y1, z1}, {x0, y0, z1}, base, {-1, 0, 0}, dist, density)
	face({x0, y0, z1}, {x0, y1, z1}, {x1, y1, z1}, {x1, y0, z1}, base, {0, 0, 1}, dist, density)
	face({x0, y0, z0}, {x1, y0, z0}, {x1, y1, z0}, {x0, y1, z0}, base, {0, 0, -1}, dist, density)
}

// world_proto_island_3d stands one island up as a stepped mass — rock, with the top step in
// foliage. Stepped rather than smooth because it is built out of the same boxes the deckhouses are,
// and because a low-poly faceted mass is what the reference's rock actually is.
//
// The steps are shouldered off-centre by the sea's own hash. A symmetric ziggurat reads as a
// staircase rather than as land, which the first pass proved: five steps that all share a centre
// line is a wedding cake seen from the side.
@(private)
world_proto_island_3d :: proc(
	view: cutaway.View,
	island: World_Proto_Island,
	salt: int,
	density: f32,
) {
	STEPS :: 5
	base := world_proto_island_place(view, island)
	eye := view.camera.position
	for s in 0 ..< STEPS {
		f0 := f32(s) / STEPS
		f1 := f32(s + 1) / STEPS
		w := island.width * (1 - f0 * 0.62)
		y0 := island.height * f0
		y1 := island.height * f1
		lean := (sea_noise(s, salt) - 0.5) * island.width * 0.22
		timber := s >= STEPS - 2 ? COLOUR_GREEN : COLOUR_ROCK
		world_proto_box(
			{base.x + lean, (y0 + y1) / 2, base.z + lean * 0.6},
			{w, y1 - y0, w * 0.68},
			timber,
			eye,
			density,
		)
	}
}

@(private)
world_proto_islands_3d :: proc(view: cutaway.View, density: f32) {
	// Far to near, so the painter's order agrees with the depth buffer's and a missing depth write
	// cannot be mistaken for a fog artefact.
	#reverse for island, i in WORLD_PROTO_ISLANDS {
		world_proto_island_3d(view, island, 71 + i * 13, density)
	}
}

// ---------------------------------------------------------------------------------------------
// The 2.5D world: depth-tagged 2D plates
// ---------------------------------------------------------------------------------------------

// A plate's depth is a number in 0..1 that stands in for a distance, so the same extinction curve
// prices a plate and a piece of geometry identically and the candidates are comparable. This is the
// candidate's whole economy: no geometry, no depth buffer, one multiply per layer.
@(private)
world_proto_plate_dist :: proc(depth: f32) -> f32 {
	NEAR :: f32(18)
	FAR :: f32(380)
	return NEAR + (FAR - NEAR) * clamp(depth, 0, 1)
}

@(private)
world_proto_plate_fog :: proc(colour: rl.Color, depth, density: f32) -> rl.Color {
	return world_proto_fogged(colour, world_proto_plate_dist(depth), density)
}

// world_proto_sky_plate is the sky as one smooth vertical gradient — rl.DrawRectangleGradientV,
// the exact call backdrop.odin exists to refuse ("it interpolates per *screen* pixel and so paints
// a smooth vector sky behind pixel-art clouds"). Calling it here is the retirement made visible in
// one line.
@(private)
world_proto_sky_plate :: proc(horizon: f32, density: f32) {
	top := colour_mix(world_proto_fog_colour(), COLOUR_SKY_HIGH, 1.0)
	rl.DrawRectangleGradientV(0, 0, WINDOW_WIDTH, i32(horizon), top, world_proto_fog_colour())
	_ = density
}

// world_proto_sea_plate is water that fakes its own recession: a smooth grade from the hazed deep
// at the horizon to the lit shallows at the viewer, worked over with chop whose scale and whose
// haze both come off the row it sits on. No lattice and no ordered dither — the marks land wherever
// the arithmetic puts them.
@(private)
world_proto_sea_plate :: proc(horizon: f32, density: f32) {
	bottom := f32(WINDOW_HEIGHT)
	span := max(bottom - horizon, 1)

	far := world_proto_plate_fog(COLOUR_SEA_DEEP, 0.95, density)
	near := world_proto_plate_fog(COLOUR_SEA_BRIGHT, 0.02, density)
	rl.DrawRectangleGradientV(0, i32(horizon), WINDOW_WIDTH, i32(span) + 1, far, near)

	// The chop. Placed by the sea's own hash so it does not lie in rows, sized by how far down the
	// frame it is, and hazed by the depth that row stands for — which is the plate candidate's
	// answer to perspective, and the same answer ship_sea.odin already gives.
	MARKS :: 900
	for i in 0 ..< MARKS {
		// Concentrated toward the horizon: squaring the parameter puts most marks in the top of the
		// band, where a real sea's chop is dense.
		t := sea_noise(i, 11)
		row := t * t
		y := horizon + row * span
		depth := 1 - row
		x := sea_noise(i, 23) * f32(WINDOW_WIDTH)
		scale := 0.6 + 5.4 * row
		bright := colour_mix(COLOUR_SEA_SHALLOW, COLOUR_FOAM, sea_noise(i, 37) * 0.5)
		rl.DrawRectangleRec(
			{x, y, scale * (1.4 + sea_noise(i, 41) * 2.2), max(scale * 0.55, 1)},
			world_proto_plate_fog(bright, depth, density),
		)
	}
}

// world_proto_island_plate is an island as a silhouette on a plate: stepped blocks, tinted and
// value-crushed toward the haze by its depth. No lighting at all — a plate has no normals, which is
// the candidate's real cost and the thing to look for in the tile. Compare a plate island against a
// 3D one in the column above it: the 3D one has a lit face and a shadowed one, and this has a
// silhouette.
@(private)
world_proto_island_plate :: proc(cx, base_y, width, height, depth, density: f32, salt: int) {
	STEPS :: 5
	for s in 0 ..< STEPS {
		f0 := f32(s) / STEPS
		f1 := f32(s + 1) / STEPS
		w := width * (1 - f0 * 0.62)
		y1 := base_y - height * f1
		lean := (sea_noise(s, salt) - 0.5) * width * 0.22
		timber := s >= STEPS - 2 ? COLOUR_GREEN : COLOUR_ROCK
		rl.DrawRectangleRec(
			{cx + lean - w / 2, y1, w, height * (f1 - f0) + 1},
			world_proto_plate_fog(timber, depth, density),
		)
	}
}

// The plate islands, in screen terms. Four planes again, at depths chosen to match the distances
// the 3D islands actually stand at — so a column of the sheet compares like with like.
@(private)
World_Proto_Plate_Island :: struct {
	cx, width, height, depth: f32,
	over:                     bool, // drawn after the 3D pass, so the ship sits *between* two plates
}

// Wider than they are tall, and spread clear of the ship — the same correction the 3D placements
// took. Depths chosen to sit at the distances the 3D islands actually stand at, so a column of the
// sheet compares like with like rather than comparing two different island fields.
@(private)
WORLD_PROTO_PLATE_ISLANDS := [?]World_Proto_Plate_Island {
	{cx = 800, width = 210, height = 30, depth = 0.94, over = false},
	{cx = 430, width = 180, height = 44, depth = 0.78, over = false},
	{cx = 1140, width = 165, height = 62, depth = 0.50, over = false},
	// The near plane, over the ship: this is what makes the candidate 2.5D rather than 2D — the
	// galleon occupies real space *between* two flat layers.
	{cx = 78, width = 240, height = 132, depth = 0.18, over = true},
}

@(private)
world_proto_island_plates :: proc(horizon: f32, density: f32, over: bool) {
	for island, i in WORLD_PROTO_PLATE_ISLANDS {
		if island.over != over {
			continue
		}
		// A near plate stands on the water rather than on the horizon, which is the only way a flat
		// layer can say it is close.
		base := horizon + (1 - island.depth) * (f32(WINDOW_HEIGHT) - horizon) * 0.55
		world_proto_island_plate(
			island.cx,
			base,
			island.width,
			island.height,
			island.depth,
			density,
			53 + i * 17,
		)
	}
}

// ---------------------------------------------------------------------------------------------
// Composing one frame
// ---------------------------------------------------------------------------------------------

// world_proto_draw is one frame of one candidate: the world, then **the real ship screen's own 3D
// pass, unmodified** — draw_ship_hull, the staged rooms, the ornament and the rig, through the
// shipped framing and the shipped projection override. That is the point. Nothing about the galleon
// is prototyped; she is the constant against which the three worlds are compared, and the cutaway's
// rooms are visible in every tile so #512's hard constraint ("berths must still read as
// hover-highlightable, drag-targetable rooms while there is haze in the frame") can be judged.
@(private)
world_proto_draw :: proc(
	state: ^Game_State,
	view: cutaway.View,
	world: World_Proto_World,
	density, swell: f32,
) {
	horizon := backdrop_floor(cutaway.galleon_horizon_y(view))

	// **Clear first, always — and the depth buffer is the reason.** rl.ClearBackground clears depth
	// as well as colour, and BeginTextureMode does not. Without this, a tile inherits the previous
	// tile's depth buffer, and the first eye-height sheet showed exactly what that costs: the plate
	// candidates came back with their sails floating free and half the hull missing, because her
	// geometry was being depth-tested against a frame taken from a different camera. It went
	// unnoticed on the haze sheet only because every tile there shares one eye, so the stale depths
	// happened to match.
	//
	// The fog colour is the honest value to clear to: under .Space it fills whatever the dome's hem
	// and the sea's far ring do not, and anything that far away *is* the haze. Under the plate
	// candidates the sky plate covers it anyway.
	rl.ClearBackground(world_proto_fog_colour())

	switch world {
	case .Space:
	// the sky and sea are geometry; nothing to lay down first
	case .Plates:
		world_proto_sky_plate(horizon, density)
		world_proto_sea_plate(horizon, density)
		world_proto_island_plates(horizon, density, over = false)
		// Her own water: the bow wave thrown ahead and the wake fanning astern. It is a 2D mark laid
		// on the sea *before* the hull, and the first pass omitted it — with the result that she read
		// as flying, because nothing local said which surface she was sitting in.
		//
		// **The 3D candidates cannot have it, and that is a finding rather than an omission.** An
		// opaque sea of real geometry paints over anything drawn beneath it, so draw_ship_wake and
		// everything like it stops working the moment the water becomes a surface: it has to be
		// rebuilt as geometry, or as something written onto the sea, neither of which is a tweak.
		draw_ship_wake(view)
	case .Hybrid:
		world_proto_sky_plate(horizon, density)
		world_proto_island_plates(horizon, density, over = false)
	}

	ship_paint_view(view.camera)
	rl.BeginMode3D(view.camera)
	// The shipped override, for the shipped reason (ship_cutaway.odin:126): anything drawing in
	// world space has to agree with galleon_project's matrix or the scene comes apart. The world
	// this prototype adds is inside that agreement, which is the cheapest evidence that a 3D world
	// *can* be — #512 names it as a constraint the winner has to survive.
	rlgl.SetMatrixProjection(view.projection)

	switch world {
	case .Space:
		world_proto_sky_3d(view)
		world_proto_sea_3d(view, density, swell)
		world_proto_islands_3d(view, density)
	case .Hybrid:
		world_proto_sea_3d(view, density, swell)
	case .Plates:
	// nothing in 3D but the ship
	}

	rooms, n := cutaway.galleon_rooms(state.player.layout)
	draw_ship_hull()
	for i in 0 ..< n {
		draw_ship_room(rooms[i], ship_room_timber(rooms[i].kind))
	}
	draw_ship_ornament(rooms, n)
	draw_ship_rig(0)
	rl.EndMode3D()

	// Over-layers, and then her own foam — which is hull water rather than world water, so it goes
	// on last exactly as the shipped screen puts it.
	if world != .Space {
		world_proto_island_plates(horizon, density, over = true)
	}
	draw_ship_waterline(view)
}

// ---------------------------------------------------------------------------------------------
// The sheet
// ---------------------------------------------------------------------------------------------

@(private)
WORLD_PROTO_EYE_FILE :: "world-proto-eye.png"

// A tile is a candidate, a haze and an eye. Two sheets are cut from the same procedure because the
// first sheet found the second one: haze depth turns out to be the *less* decisive axis, and a
// prototype that only varied the axis it was asked to vary would have hidden that.
@(private)
World_Proto_Tile :: struct {
	world: World_Proto_World,
	haze:  World_Proto_Haze,
	eye:   cutaway.Eye,
	note:  string,
}

// The eye heights the second sheet runs through: the camera rises and keeps looking at the same
// point on her, which is what "lift the camera" means and what keeps her in frame. Raising `look`
// along with `height` was the first attempt and it is wrong — it aims the camera at a point in the
// air above her masthead, and by an eye of 3.0 she has slid out of the bottom of the frame.
//
// So the horizon's screen row *does* move down the frame as the eye rises. That is not an artefact
// to correct; it is the whole of what lifting an eye off a plane does, and it is half the cost the
// column is there to show.
@(private)
World_Proto_Eye_Step :: struct {
	name:  string,
	lift:  f32,
}

@(private)
WORLD_PROTO_EYE_STEPS := [?]World_Proto_Eye_Step {
	{name = "eye 0.00 — shipped, on the water", lift = 0},
	{name = "eye 1.20 — lifted", lift = 1.2},
	{name = "eye 3.00 — well clear", lift = 3.0},
}

@(private)
world_proto_lifted :: proc(lift: f32) -> cutaway.Eye {
	eye := cutaway.GALLEON_EYE
	eye.height += lift
	return eye
}

world_proto_requested :: proc() -> bool {
	return slice.contains(os.args[1:], "--world-proto")
}

// world_proto_main renders both sheets and exits — capture's window, capture's staged ship,
// capture's directory. Modelled on hull_sheet_main, and for the same reason: a grid of frames does
// not fit in one window, and a sheet is one Read.
//
// **world-proto.png** is #512's own ask: a row per candidate, a column per haze depth, all at the
// shipped eye. **world-proto-eye.png** is the same three candidates at one haze depth over three
// eye heights, and it exists because the first sheet made GALLEON_CAM_HEIGHT the question — a real
// 3D sea seen from an eye sitting exactly on it is not a surface, it is the nearest crest.
world_proto_main :: proc() -> bool {
	capture_open("Fantasy Ship Game (world prototype)")
	defer capture_close()

	if !rl.IsWindowReady() {
		fmt.eprintln("world-proto: needs a window to render into")
		return false
	}

	scene := Capture_Scene{}
	defer capture_scene_destroy(&scene)
	capture_stage_refit(&scene)

	haze_tiles: [dynamic]World_Proto_Tile
	defer delete(haze_tiles)
	for world in World_Proto_World {
		for haze in WORLD_PROTO_HAZES {
			append(
				&haze_tiles,
				World_Proto_Tile {
					world = world,
					haze = haze,
					eye = cutaway.GALLEON_EYE,
					note = haze.name,
				},
			)
		}
	}

	eye_tiles: [dynamic]World_Proto_Tile
	defer delete(eye_tiles)
	for world in World_Proto_World {
		for step in WORLD_PROTO_EYE_STEPS {
			append(
				&eye_tiles,
				World_Proto_Tile {
					world = world,
					haze = WORLD_PROTO_HAZES[1],
					eye = world_proto_lifted(step.lift),
					note = step.name,
				},
			)
		}
	}

	if !world_proto_sheet(&scene, haze_tiles[:], len(WORLD_PROTO_HAZES), WORLD_PROTO_FILE) {
		return false
	}
	return world_proto_sheet(
		&scene,
		eye_tiles[:],
		len(WORLD_PROTO_EYE_STEPS),
		WORLD_PROTO_EYE_FILE,
	)
}

@(private)
world_proto_sheet :: proc(
	scene: ^Capture_Scene,
	tiles: []World_Proto_Tile,
	cols: int,
	file: string,
) -> bool {
	rows := (len(tiles) + cols - 1) / cols

	// No alpha, both sides — hull_sheet_main says why: a frame composed into a render texture comes
	// back with its alpha eroded wherever anything translucent was drawn, and blending such a tile
	// would pull the sheet's ground up through it.
	sheet := rl.GenImageColor(i32(WINDOW_WIDTH * cols), i32(WINDOW_HEIGHT * rows), COLOUR_INK_PRIMARY)
	defer rl.UnloadImage(sheet)
	rl.ImageFormat(&sheet, .UNCOMPRESSED_R8G8B8)

	frame := rl.LoadRenderTexture(WINDOW_WIDTH, WINDOW_HEIGHT)
	defer rl.UnloadRenderTexture(frame)

	for tile, index in tiles {
		view := cutaway.galleon_view_from(tile.eye, WINDOW_WIDTH, WINDOW_HEIGHT)
		rl.BeginTextureMode(frame)
		world_proto_draw(&scene.game, view, tile.world, tile.haze.density, WORLD_PROTO_SWELL)
		world_proto_caption(tile)
		rl.EndTextureMode()

		shot := rl.LoadImageFromTexture(frame.texture)
		defer rl.UnloadImage(shot)
		rl.ImageFlipVertical(&shot)
		rl.ImageFormat(&shot, .UNCOMPRESSED_R8G8B8)
		whole := rl.Rectangle{x = 0, y = 0, width = WINDOW_WIDTH, height = WINDOW_HEIGHT}
		col, row := index % cols, index / cols
		cell := rl.Rectangle {
			x      = f32(col * WINDOW_WIDTH),
			y      = f32(row * WINDOW_HEIGHT),
			width  = WINDOW_WIDTH,
			height = WINDOW_HEIGHT,
		}
		rl.ImageDraw(&sheet, shot, whole, cell, rl.WHITE)
	}

	path := fmt.tprintf("%s/%s", capture_dir(), file)
	capture_keep_previous(path)
	if !rl.ExportImage(sheet, strings.clone_to_cstring(path, context.temp_allocator)) {
		fmt.eprintfln("world-proto: could not write %s", path)
		return false
	}
	fmt.printfln("world-proto: wrote %s", path)
	return true
}

// world_proto_caption names the candidate, what the column varies, and the swell. The swell is on
// every tile rather than in a header because it is the number that decides whether the 3D
// candidates have a sea at all (WORLD_PROTO_SWELL says why), and a tile read without it is
// unreadable.
@(private)
world_proto_caption :: proc(tile: World_Proto_Tile) {
	PAD :: f32(12)
	text := fmt.ctprintf(
		"%s — %s (density %.4f, swell %.2f)",
		world_proto_world_name(tile.world),
		tile.note,
		tile.haze.density,
		WORLD_PROTO_SWELL,
	)
	size := rl.MeasureTextEx(ui_font_title, text, UI_TITLE_SIZE, 1)
	rl.DrawRectangleRec({0, 0, size.x + 2 * PAD, size.y + 2 * PAD}, COLOUR_INK_PRIMARY)
	rl.DrawTextEx(ui_font_title, text, {PAD, PAD}, UI_TITLE_SIZE, 1, COLOUR_FOAM)
}

// ---------------------------------------------------------------------------------------------
// The live mode: the real window, through the real blit
// ---------------------------------------------------------------------------------------------

world_proto_live_requested :: proc() -> bool {
	return slice.contains(os.args[1:], "--world-proto-live")
}

// world_proto_live_main is the same nine frames, steerable, in a borderless-fullscreen session that
// goes through fullscreen_init and frame_begin/frame_end — so what is on screen has been through
// the render texture and the BILINEAR upscale a player actually sees. The sheet cannot show that
// (`--shot` and `--capture` bypass fullscreen_target entirely), and #512 says to look in the real
// window.
//
// The camera height is on a key because of what GALLEON_CAM_HEIGHT is: 0.0, the eye exactly on the
// water plane. Whether a 3D sea is worth having is mostly a question about that number, and the
// only honest way to see it is to move it.
world_proto_live_main :: proc() -> bool {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Fantasy Ship Game (world prototype)")
	defer rl.CloseWindow()
	fullscreen_init()
	defer fullscreen_shutdown()
	rl.SetTargetFPS(60)
	ui_fonts_load()
	defer ui_fonts_unload()
	art_load()

	scene := Capture_Scene{}
	defer capture_scene_destroy(&scene)
	capture_stage_refit(&scene)
	capture_dir_prepare()
	defer capture_dir_release()

	world := World_Proto_World.Space
	density := WORLD_PROTO_HAZES[1].density
	swell := WORLD_PROTO_SWELL
	eye := cutaway.GALLEON_EYE
	help := true
	// Frames to wait before grabbing, so a shot is never one frame stale. rl.TakeScreenshot reads
	// back the framebuffer EndDrawing has *already presented*, so grabbing in the same iteration as
	// the keypress photographs the settings as they were before it.
	pending := 0

	for !rl.WindowShouldClose() {
		if rl.IsKeyPressed(.ONE) {world = .Space}
		if rl.IsKeyPressed(.TWO) {world = .Plates}
		if rl.IsKeyPressed(.THREE) {world = .Hybrid}
		if rl.IsKeyPressed(.TAB) {help = !help}
		if rl.IsKeyPressed(.L) {world_proto_soft_light = !world_proto_soft_light}
		if rl.IsKeyDown(.LEFT_BRACKET) {density = max(density * 0.97, 0.0002)}
		if rl.IsKeyDown(.RIGHT_BRACKET) {density = min(density * 1.03, 0.2)}
		if rl.IsKeyDown(.MINUS) {swell = max(swell - 0.004, 0)}
		if rl.IsKeyDown(.EQUAL) {swell = min(swell + 0.004, 1.6)}
		// The one that matters — the camera rises and keeps looking at the same point on her, so she
		// stays framed while the water goes from edge-on to oblique.
		if rl.IsKeyDown(.W) {eye.height += 0.02}
		if rl.IsKeyDown(.S) {eye.height -= 0.02}
		if rl.IsKeyDown(.A) {eye.yaw -= 0.5}
		if rl.IsKeyDown(.D) {eye.yaw += 0.5}
		if rl.IsKeyDown(.Q) {eye.dist = max(eye.dist - 0.04, 1)}
		if rl.IsKeyDown(.E) {eye.dist += 0.04}
		if rl.IsKeyPressed(.R) {
			eye = cutaway.GALLEON_EYE
			density = WORLD_PROTO_HAZES[1].density
			swell = WORLD_PROTO_SWELL
		}

		if rl.IsKeyPressed(.P) {
			// Generous on purpose. Two frames was not enough — the panel still came back in the
			// shot, so the driver's readback is staler than the one frame raylib's own docs imply
			// (a swap chain may be three deep, and the value is not worth pinning down here).
			// Ten frames is a sixth of a second, invisible to the hand on the key, and it makes the
			// suppression window wider than any plausible readback lag.
			pending = 10
		}

		view := cutaway.galleon_view_from(eye, WINDOW_WIDTH, WINDOW_HEIGHT)
		frame_begin()
		world_proto_draw(&scene.game, view, world, density, swell)
		// The help panel is suppressed for *every* frame between the keypress and the grab. Only
		// the frame after it was suppressed, which is one frame too late: TakeScreenshot reads the
		// framebuffer EndDrawing has already presented, so the grab lands on the frame *before* the
		// one it was fired on — and the first shot came back with the panel across the corner of it.
		if help && pending == 0 {
			world_proto_help(world, density, swell, eye)
		}
		frame_end()

		if pending > 0 {
			pending -= 1
			if pending == 0 {
				world_proto_grab(world, density, swell, eye)
			}
		}
	}
	return true
}

// world_proto_grab photographs **what is actually on the monitor** — the logical frame after
// fullscreen_target's scale-to-fit BILINEAR upscale, at the panel's own resolution.
//
// This is the one thing in the tree that can do it. `--capture` and `--shot` draw at logical size
// with no render texture in the path (fullscreen.odin's header says so outright), so the whole
// gallery and every `docs/ui/shot-manifest.txt` hash is taken at exact 1244x700 and **the upscale a
// player sees has never been photographed**. That blind spot is tolerable for flat pixel art and is
// not tolerable here: what the upscale does to a soft gradient is precisely what #514 has to
// decide, and you cannot decide it from a frame that never went through one.
//
// rl.TakeScreenshot after frame_end reads the presented framebuffer, which is the monitor-sized
// one — so the PNG comes out at panel resolution, letterbox bars and all, not at 1244x700.
//
// Every setting rides in the filename. The point of the shot is to be able to say "this one" and
// have the numbers travel with it.
@(private)
world_proto_grab :: proc(world: World_Proto_World, density, swell: f32, eye: cutaway.Eye) {
	tag := ""
	switch world {
	case .Space:
		tag = "space"
	case .Plates:
		tag = "plates"
	case .Hybrid:
		tag = "hybrid"
	}
	name := fmt.tprintf(
		"world-proto-%s-%s-eye%.2f-swell%.2f-fog%.4f-yaw%.1f-dist%.2f.png",
		tag,
		world_proto_soft_light ? "softlight" : "hardlight",
		eye.height,
		swell,
		density,
		eye.yaw,
		eye.dist,
	)
	rl.TakeScreenshot(strings.clone_to_cstring(name, context.temp_allocator))

	// raylib drops any path prefix and writes into the process's cwd, so the shot is moved out of
	// the repo root — `*.png` there is not gitignored and a stranded one is a `git add .` away from
	// being committed (capture_write, capture.odin).
	dest := fmt.tprintf("%s/%s", capture_dir(), name)
	if err := os.rename(name, dest); err != nil {
		fmt.eprintfln("world-proto: could not move %s into %s (%v)", name, capture_dir(), err)
		if err := os.remove(name); err != nil {
			fmt.eprintfln("world-proto: %s is stranded in the working directory (%v)", name, err)
		}
		return
	}
	fmt.printfln("world-proto: wrote %s (panel resolution, through the blit)", dest)
}

@(private)
world_proto_help :: proc(
	world: World_Proto_World,
	density, swell: f32,
	eye: cutaway.Eye,
) {
	lines := [?]string {
		fmt.tprintf("1/2/3  world: %s", world_proto_world_name(world)),
		fmt.tprintf("[ ]    fog density: %.4f", density),
		fmt.tprintf("- =    swell: %.3f  (0 = a flat plane through the eye)", swell),
		fmt.tprintf("W/S    eye height: %.2f  (shipped: 0.00, level with the waterline)", eye.height),
		fmt.tprintf("A/D    yaw: %.1f      Q/E  standoff: %.2f", eye.yaw, eye.dist),
		fmt.tprintf(
			"L      light: %s",
			world_proto_soft_light \
			? "SOFT — wrapped falloff, cool ambient + one warm key" \
			: "shipped — hard terminator, one hue at two brightnesses",
		),
		"P      grab a shot AT PANEL RESOLUTION, through the blit",
		"R      reset      Tab  hide this",
	}
	PAD :: f32(10)
	LINE :: f32(22)
	plate := rl.Rectangle {
		x      = PAD,
		y      = f32(WINDOW_HEIGHT) - (LINE * f32(len(lines)) + 2 * PAD) - PAD,
		width  = 620,
		height = LINE * f32(len(lines)) + 2 * PAD,
	}
	rl.DrawRectangleRec(plate, COLOUR_INK_PRIMARY)
	for line, i in lines {
		rl.DrawTextEx(
			ui_font_body,
			fmt.ctprintf("%s", line),
			{plate.x + PAD, plate.y + PAD + LINE * f32(i)},
			UI_BODY_SIZE,
			1,
			COLOUR_FOAM,
		)
	}
}
