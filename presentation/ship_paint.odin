#+private
package presentation

import rl "vendor:raylib"

// How the ship screen paints a surface. raylib's immediate-mode 3D carries no lights:
// `DrawCube` paints all six faces one flat colour, which is why a box drawn with it reads as a
// sticker rather than a solid, and why a hull built out of them reads as stacked cardboard.
// Everything the galleon draws in three dimensions goes through the primitives here instead —
// a surface is handed its own normal, and the sun decides which shade of the roster swatch it
// comes out as. Curve, camber, tumblehome and the belly of a sail are then modelled by light
// rather than drawn as outlines, which is the whole of the difference between the flat pass and
// this one. The palette is untouched: every colour that reaches the screen is still a roster
// swatch, only lit.

// SHIP_SUN is where the light comes from: high, over the port quarter and a little aft. The
// camera stands off the port bow, so it reads lit decks and lit topsides down the ship's side,
// with the forward faces of the castles falling into shadow — the modelling that tells the eye
// which way the hull turns.
SHIP_SUN :: rl.Vector3{-0.42, 0.80, -0.43}

// The light budget. Ambient is what a surface facing away from the sun still gets, because
// nothing on a bright tropical sea is black — the sky and the water fill it in. Sunlight is
// what a face turned to the sun adds on top, and the two fills are the extra a surface picks up
// from the sky above it or the water beneath.
SHIP_AMBIENT :: f32(0.60)
SHIP_SUNLIGHT :: f32(0.52)
SHIP_SKY_FILL :: f32(0.14)
// The sea fill is large because the sea here is a mirror. The camera is down at the waterline
// and everything above it — decks, the roofs of her castles, her counter — is seen from
// *underneath*, so what lights the whole upper half of this ship is turquoise bounced up off
// the water. Set as low as the sky fill it is balanced against, every underside on the ship
// goes to flat ambient and she reads as a paper model.
SHIP_SEA_FILL :: f32(0.24)

// ship_eye is where the camera stands this frame. Lighting needs it because every surface here
// is drawn two-sided — a cutaway is looked into from an angle that sees the inside of half of
// what is drawn, and a culled face would be a silent hole — and the two sides of a surface do
// not face the same way. Shading both from one normal paints the underside of a deck with the
// sunlight falling on its top, which is why her decks and castle roofs read as flat lids
// hanging in the air: from a camera at sea level you are looking at the *bottom* of every one
// of them. ship_paint_view is called once before the 3D pass opens.
ship_eye: rl.Vector3

ship_paint_view :: proc(camera: rl.Camera3D) {
	ship_eye = camera.position
}

// ship_facing turns a surface's outward normal into the normal of the side actually being
// looked at, so the light lands on the face the eye is on.
ship_facing :: proc(point: rl.Vector3, normal: rl.Vector3) -> rl.Vector3 {
	return rl.Vector3DotProduct(ship_eye - point, normal) < 0 ? -normal : normal
}

// ship_lit is a roster swatch under this sun: one flat shade per surface, off that surface's
// normal. Flat, not smooth, on purpose — the game's art is blocky, and a faceted hull keeps the
// strakes and the frames reading as planking rather than dissolving into an airbrush.
ship_lit :: proc(base: rl.Color, normal: rl.Vector3) -> rl.Color {
	n := rl.Vector3Normalize(normal)
	// The workbench's normals view: +x red, +y green, +z blue, and the negative of each dark,
	// so which way a surface faces is a colour rather than a shade (ship_debug.odin).
	if ship_debug_normals {
		axis :: proc(v: f32) -> u8 {
			return u8(clamp(v > 0 ? 235 * v : 70 * -v, 0, 255))
		}
		return rl.Color{axis(n.x), axis(n.y), axis(n.z), 255}
	}
	sun := rl.Vector3Normalize(SHIP_SUN)
	lambert := max(rl.Vector3DotProduct(n, sun), 0)
	fill := SHIP_SKY_FILL * max(n.y, 0) + SHIP_SEA_FILL * max(-n.y, 0)
	return colour_shade(base, SHIP_AMBIENT + SHIP_SUNLIGHT * lambert + fill)
}

// ship_quad paints one flat four-cornered surface, lit by the normal its own winding implies.
// Corners go round the quad; which way round decides which side the light comes from, so a
// surface meant to be seen from inside is wound inside-out on purpose.
ship_quad :: proc(a, b, c, d: rl.Vector3, base: rl.Color) {
	ship_quad_lit(a, b, c, d, base, rl.Vector3CrossProduct(b - a, c - a))
}

// ship_quad_lit is the same surface with its normal given rather than derived — for the strips
// of a curved skin, where the true surface normal is known from the loft and the little quad
// standing in for it is too nearly degenerate to hand back a usable one.
ship_quad_lit :: proc(a, b, c, d: rl.Vector3, base: rl.Color, normal: rl.Vector3) {
	lit := ship_lit(base, ship_facing((a + c) / 2, normal))
	lo := min(a.y, b.y, c.y, d.y)
	hi := max(a.y, b.y, c.y, d.y)

	// A quad is one flat colour, so a surface that stands a fathom tall takes the dusk of its own
	// midpoint and nothing else — and her whole opened waist is exactly that: bulkheads running
	// sole to deck, each a single quad. Measured off the shot, every pixel from y=450 to y=510
	// came back #523D23, the same brown at the bilge as at the deck head, over the largest area
	// of the ship. Beside a bow carrying fourteen courses of planking and a gradient down to the
	// keel, a slab that flat reads as a hole cut in card rather than as the inside of a hull.
	//
	// So a tall surface is sliced and each slice takes its own depth. The seam a→d is the way up
	// on every quad this file draws — the hull bands, the box faces, the bulkheads — so slicing
	// along it needs no knowledge of what is being drawn. Slices scale with height and stop at
	// eight, which keeps the strakes (a band is well under the threshold) on the single-quad path
	// they were always on.
	if lo < 0 && hi - lo > HULL_TINT_SPAN / 4 {
		slices := clamp(int((hi - lo) / (HULL_TINT_SPAN / 8)), 2, 8)
		for i in 0 ..< slices {
			f0 := f32(i) / f32(slices)
			f1 := f32(i + 1) / f32(slices)
			a0 := a + (d - a) * f0
			b0 := b + (c - b) * f0
			b1 := b + (c - b) * f1
			a1 := a + (d - a) * f1
			ship_quad_flat(a0, b0, b1, a1, ship_inboard_dusk(lit, (a0.y + b0.y + b1.y + a1.y) / 4))
		}
		return
	}

	// Wound both ways. raylib culls back faces into nothing, and a cutaway is looked into from
	// an angle that sees the inside of half of what is drawn — a face culled away would be a
	// silent hole, the failure mode the run-game skill warns about. Both windings carry the same
	// shade, so the surface is lit by the normal above whichever side of it the camera is on.
	ship_quad_flat(a, b, c, d, ship_inboard_dusk(lit, (a.y + b.y + c.y + d.y) / 4))
}

// SHIP_INBOARD_DUSK is how much of the light is gone off an inboard surface at a full fathom
// down — the same fathom the skin's tint is measured against, because it is the same water.
SHIP_INBOARD_DUSK :: f32(0.52)

// ship_inboard_dusk takes the light off a surface the further below the waterline it sits.
//
// Everything the cutaway looks into stands behind the same water her outer planking stands
// behind, and water eats light before it does anything else. Without this her bow went green
// below the waterline while her opened waist stayed dry brown down to the keel — one end sunk and
// the other in a dry dock, which is exactly what "the front is deep in the water but the side
// isn't" describes. It is the outer skin's own waterline, continued across the opening.
//
// Value only, deliberately, and this is the part that is easy to get wrong. Tinting her interior
// toward the sea is what fills a hold with standing water; worse, warm timber mixed toward a cool
// sea passes through neutral on the way, which is the trap the style guide now has a section
// about. Taking the light off asserts that this is under the water and asserts nothing else — the
// timber keeps its own hue, and the bottom of a hold really is the darkest place on a ship.
//
// It goes here, in the one procedure every inboard surface is painted through, rather than at
// each call site: the ceiling planking, the sole, the bulkheads and every fitting yet to be drawn
// in a room all take it without knowing about it.
ship_inboard_dusk :: proc(colour: rl.Color, y: f32) -> rl.Color {
	if y >= 0 {
		return colour
	}
	return colour_shade(colour, 1 - SHIP_INBOARD_DUSK * min(-y / HULL_TINT_SPAN, 1))
}

// ship_quad_flat paints a surface whose colour has already been decided — for the skin below
// the waterline, where the sun is not the last thing that happens to a strake. Water sits
// between it and the eye, so the sea's colour goes *over* the lit timber rather than under it,
// and a call site that needs that order has to do its own lighting first.
ship_quad_flat :: proc(a, b, c, d: rl.Vector3, colour: rl.Color) {
	rl.DrawTriangle3D(a, b, c, colour)
	rl.DrawTriangle3D(a, c, d, colour)
	rl.DrawTriangle3D(c, b, a, colour)
	rl.DrawTriangle3D(d, c, a, colour)
}

// ship_quad_cloth is canvas rather than timber: lit from either face, and brighter for it. A
// sail is one thickness of cloth with the sun behind it as often as in front, so the side in
// shadow still glows — which is why a sail shaded like a plank comes out grey and dead, and why
// this is a separate primitive rather than a colour choice at the call site.
ship_quad_cloth :: proc(a, b, c, d: rl.Vector3, base: rl.Color) {
	n := rl.Vector3Normalize(rl.Vector3CrossProduct(b - a, c - a))
	through := abs(rl.Vector3DotProduct(n, rl.Vector3Normalize(SHIP_SUN)))
	colour := colour_shade(base, 0.82 + 0.34 * through)
	rl.DrawTriangle3D(a, b, c, colour)
	rl.DrawTriangle3D(a, c, d, colour)
	rl.DrawTriangle3D(c, b, a, colour)
	rl.DrawTriangle3D(d, c, a, colour)
}

// ship_box is a lit rectangular solid: the same footprint `DrawCube` takes, but with each face
// shaded by the way it faces. The lit top and the shadowed forward face are what make a
// deckhouse read as a solid standing in sunlight.
ship_box :: proc(centre, size: rl.Vector3, base: rl.Color) {
	h := size / 2
	x0, x1 := centre.x - h.x, centre.x + h.x
	y0, y1 := centre.y - h.y, centre.y + h.y
	z0, z1 := centre.z - h.z, centre.z + h.z

	ship_quad_lit({x0, y1, z0}, {x1, y1, z0}, {x1, y1, z1}, {x0, y1, z1}, base, {0, 1, 0})
	ship_quad_lit({x0, y0, z0}, {x0, y0, z1}, {x1, y0, z1}, {x1, y0, z0}, base, {0, -1, 0})
	ship_quad_lit({x1, y0, z0}, {x1, y0, z1}, {x1, y1, z1}, {x1, y1, z0}, base, {1, 0, 0})
	ship_quad_lit({x0, y0, z0}, {x0, y1, z0}, {x0, y1, z1}, {x0, y0, z1}, base, {-1, 0, 0})
	ship_quad_lit({x0, y0, z1}, {x0, y1, z1}, {x1, y1, z1}, {x1, y0, z1}, base, {0, 0, 1})
	ship_quad_lit({x0, y0, z0}, {x1, y0, z0}, {x1, y1, z0}, {x0, y1, z0}, base, {0, 0, -1})
}

// ship_spar is a tapered round timber between two points — a mast, a yard, a bowsprit. raylib
// shades a cylinder no better than a cube, so the taper and the tone carry it: a spar is drawn
// one shade off the surfaces around it so it stands away from them.
ship_spar :: proc(from, to: rl.Vector3, radius_from, radius_to: f32, base: rl.Color) {
	rl.DrawCylinderEx(from, to, radius_from, radius_to, 8, ship_lit(base, {-0.5, 0.7, -0.5}))
}

// ship_rope is standing or running rigging: a line thin enough to read as cordage at this
// distance. Every stay and shroud on the ship is one of these, and they are what turn three
// bare poles into a rig.
ship_rope :: proc(from, to: rl.Vector3, thickness: f32, base: rl.Color) {
	rl.DrawCylinderEx(from, to, thickness, thickness, 4, base)
}

// colour_mix blends two roster swatches. Used where a surface is not simply lit but is being
// seen *through* something — the hull below the waterline, greening off into clear water.
colour_mix :: proc(a, b: rl.Color, k: f32) -> rl.Color {
	t := clamp(k, 0, 1)
	channel :: proc(from, to: u8, t: f32) -> u8 {
		return u8(clamp(f32(from) + (f32(to) - f32(from)) * t, 0, 255))
	}
	return rl.Color {
		channel(a.r, b.r, t),
		channel(a.g, b.g, t),
		channel(a.b, b.b, t),
		channel(a.a, b.a, t),
	}
}
