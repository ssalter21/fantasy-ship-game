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
SHIP_SEA_FILL :: f32(0.07)

// ship_lit is a roster swatch under this sun: one flat shade per surface, off that surface's
// normal. Flat, not smooth, on purpose — the game's art is blocky, and a faceted hull keeps the
// strakes and the frames reading as planking rather than dissolving into an airbrush.
ship_lit :: proc(base: rl.Color, normal: rl.Vector3) -> rl.Color {
	n := rl.Vector3Normalize(normal)
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
	colour := ship_lit(base, normal)
	// Wound both ways. raylib culls back faces into nothing, and a cutaway is looked into from
	// an angle that sees the inside of half of what is drawn — a face culled away would be a
	// silent hole, the failure mode the run-game skill warns about. Both windings carry the same
	// shade, so the surface is lit by the normal above whichever side of it the camera is on.
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
