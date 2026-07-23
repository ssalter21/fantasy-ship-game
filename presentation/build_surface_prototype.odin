#+private
package presentation

// PROTOTYPE — THROWAWAY. Branch worktree-prototype-ship-side-view; never merges to main.
//
// Round 4. The verdict on round 3 picked the true-3D open-room look (old "B2"), with two
// changes: the rooms must stack ONE PER FLOOR (decks), not sit side-by-side on a single
// floor, and the whole thing must read as a SHIP. So this round is a mostly-side 3D cutaway
// of a galleon: a wooden hull with a curved profile, a stern castle, a main deck, mast and
// bowsprit — cut open on the near side so you look into the stacked decks. Each berth is one
// empty deck-room, a placeholder chamber for the bespoke per-slot / per-fitting art to come.
// Holds sit below the waterline, topside stations above it.
//
//   Current      — today's flat navy cutaway, untouched, as the baseline to flip against.
//   Ship_Cutaway — the chosen direction, and now the default: the 3D stacked-deck ship.
//
// Names ride parchment nameplates beside each deck; hovering a deck pops a description
// tooltip. Rooms are empty by design — the art that fills them is what we are NOT building
// yet. Drag-refit is inert (read-only prototype).
//
// The new-roster colours are PROTO_* locals here on purpose: the style guide leaves the
// shipped COLOUR_* constants navy until the real migration, and a throwaway must not front-run
// it.

import "core:fmt"
import ship "../core/ship"
import sim "../core/sim"
import rl "vendor:raylib"

// --- The new roster (style-guide values, prototype-local) --------------------------------

PROTO_SEA :: rl.Color{31, 169, 208, 255}
PROTO_SEA_BRIGHT :: rl.Color{44, 195, 222, 255}
PROTO_SHALLOW :: rl.Color{99, 226, 236, 255}
PROTO_SEA_DEEP :: rl.Color{23, 134, 188, 255}
PROTO_FOAM :: rl.Color{242, 251, 251, 255}
PROTO_SKY_HIGH :: rl.Color{63, 121, 192, 255}
PROTO_SKY :: rl.Color{90, 147, 210, 255}
PROTO_HAZE :: rl.Color{143, 188, 232, 255}
PROTO_CLOUD :: rl.Color{238, 241, 248, 255}
PROTO_CLOUD_SHADOW :: rl.Color{183, 188, 224, 255}
PROTO_PARCHMENT :: rl.Color{235, 217, 166, 255}
PROTO_SAND :: rl.Color{210, 169, 104, 255}
PROTO_CLIFF :: rl.Color{185, 138, 80, 255}
PROTO_ROCK :: rl.Color{126, 92, 58, 255}
PROTO_TRUNK :: rl.Color{135, 95, 56, 255}
PROTO_INK :: rl.Color{18, 51, 63, 255}
PROTO_INK_MUTED :: rl.Color{76, 115, 133, 255}
PROTO_INK_FADED :: rl.Color{156, 138, 99, 255}
PROTO_CREAM :: rl.Color{243, 230, 196, 255}

Proto_Variant :: enum {
	Current,
	Ship_Cutaway,
}

// The chosen direction is the default: opening the ship screen shows the 3D cutaway.
proto_variant: Proto_Variant = .Ship_Cutaway

proto_variant_label :: proc(v: Proto_Variant) -> string {
	switch v {
	case .Current:
		return "Current — navy cutaway"
	case .Ship_Cutaway:
		return "Ship cutaway — 3D stacked decks"
	}
	return ""
}

proto_cycle :: proc(dir: int) {
	n := len(Proto_Variant)
	proto_variant = Proto_Variant((int(proto_variant) + dir + n) % n)
}

// proto_poll is the switcher's whole input: arrow keys and the two bar arrows. Called at
// the top of the Home and Refit loops; the bar sits in a strip (y < 40) no live control
// shares, so its click never doubles as a drag or a chart raise.
proto_poll :: proc() {
	if !rl.IsWindowReady() {
		return
	}
	if rl.IsKeyPressed(.LEFT) {
		proto_cycle(-1)
	}
	if rl.IsKeyPressed(.RIGHT) {
		proto_cycle(1)
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		m := rl.GetMousePosition()
		if rl.CheckCollisionPointRec(m, proto_arrow_rect(false)) {
			proto_cycle(-1)
		} else if rl.CheckCollisionPointRec(m, proto_arrow_rect(true)) {
			proto_cycle(1)
		}
	}
}

PROTO_BAR_W :: 460
PROTO_BAR_H :: 30

proto_bar_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle{x = (WINDOW_WIDTH - PROTO_BAR_W) / 2, y = 6, width = PROTO_BAR_W, height = PROTO_BAR_H}
}

proto_arrow_rect :: proc(right: bool) -> rl.Rectangle {
	bar := proto_bar_rect()
	x := right ? bar.x + bar.width - 34 : bar.x + 4
	return rl.Rectangle{x = x, y = bar.y + 3, width = 30, height = bar.height - 6}
}

// draw_proto_switcher is the floating variant bar: pure white on near-black, high contrast,
// obviously not part of the game's palette — the point is that it reads as scaffolding.
draw_proto_switcher :: proc(mouse: rl.Vector2) {
	bar := proto_bar_rect()
	rl.DrawRectangleRec(bar, rl.Color{0, 0, 0, 220})
	rl.DrawRectangleLinesEx(bar, 2, rl.WHITE)

	for right in ([2]bool{false, true}) {
		arrow := proto_arrow_rect(right)
		if rl.CheckCollisionPointRec(mouse, arrow) {
			rl.DrawRectangleRec(arrow, rl.Color{255, 255, 255, 60})
		}
		glyph := right ? cstring(">") : cstring("<")
		rl.DrawTextEx(ui_font_body, glyph, rl.Vector2{arrow.x + 11, arrow.y + 3}, UI_BODY_SIZE, 1, rl.WHITE)
	}

	label := fmt.ctprintf("%s", proto_variant_label(proto_variant))
	lw := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1).x
	rl.DrawTextEx(ui_font_body, label, rl.Vector2{bar.x + (bar.width - lw) / 2, bar.y + 7}, UI_BODY_SIZE, 1, rl.WHITE)

	hint := cstring("PROTOTYPE - arrows switch")
	hw := rl.MeasureTextEx(ui_font_body, hint, UI_BODY_SIZE, 1).x
	rl.DrawTextEx(ui_font_body, hint, rl.Vector2{bar.x + (bar.width - hw) / 2, bar.y + bar.height + 4}, UI_BODY_SIZE, 1, rl.Color{255, 255, 255, 140})
}

// proto_lines is the one description formatter: title, the spec line (size · phase · tags),
// the effect intent, and the material facts (weight, cargo, berth).
proto_lines :: proc(ls: ship.Layout_Slot) -> (title, spec, intent, extra: string) {
	fitting, filled := ls.fitting.?
	if !filled {
		title = fmt.tprintf("(empty %v)", ls.slot.size)
		spec = fmt.tprintf("%v berth", ls.slot.size)
		intent = "nothing installed"
		extra = fmt.tprintf("%s · %v", ls.slot.name, ls.slot.base_visibility)
		return
	}
	title = fitting.name
	spec, intent = fitting_summary_lines(fitting)
	extra = fmt.tprintf(
		"wt %d · %d/%d · %s · %v",
		fitting.weight,
		fitting.cargo_held,
		ship.ship_fitting_capacity(fitting),
		ls.slot.name,
		ls.slot.base_visibility,
	)
	return
}

proto_slot_title :: proc(ls: ship.Layout_Slot) -> string {
	if fitting, filled := ls.fitting.?; filled {
		return fitting.name
	}
	return fmt.tprintf("(empty %v)", ls.slot.size)
}

proto_slot_is_hold :: proc(ls: ship.Layout_Slot) -> bool {
	fitting, filled := ls.fitting.?
	return filled && ship.ship_fitting_is_hold(fitting)
}

draw_ship_prototype :: proc(state: ^Game_State, mouse: rl.Vector2) {
	switch proto_variant {
	case .Current:
	// unreachable — the hook only enters on a non-Current variant
	case .Ship_Cutaway:
		draw_proto_ship_cutaway(state, mouse)
	}
}

// --- Shared paint helpers ----------------------------------------------------------------

// proto_shade multiplies a colour's rgb by f (clamped) — one base wood tone lit several ways.
proto_shade :: proc(c: rl.Color, f: f32) -> rl.Color {
	m :: proc(v: u8, f: f32) -> u8 {
		r := f32(v) * f
		if r > 255 {r = 255}
		if r < 0 {r = 0}
		return u8(r)
	}
	return rl.Color{m(c.r, f), m(c.g, f), m(c.b, f), c.a}
}

// draw_proto_cloud stacks three blocky rects — a pixel cloud, no curves.
draw_proto_cloud :: proc(cx, cy: f32) {
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 70, y = cy + 14, width = 150, height = 22}, PROTO_CLOUD_SHADOW)
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 60, y = cy, width = 120, height = 24}, PROTO_CLOUD)
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 28, y = cy - 14, width = 62, height = 18}, PROTO_CLOUD)
}

PROTO_HORIZON :: f32(300) // 2D sea horizon behind the ship

draw_proto_backdrop :: proc() {
	rl.ClearBackground(PROTO_SKY_HIGH)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = 96, width = WINDOW_WIDTH, height = 96}, PROTO_SKY)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = 192, width = WINDOW_WIDTH, height = PROTO_HORIZON - 192}, PROTO_HAZE)
	draw_proto_cloud(220, 92)
	draw_proto_cloud(1010, 70)

	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_HORIZON, width = WINDOW_WIDTH, height = 24}, PROTO_SEA_DEEP)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_HORIZON + 24, width = WINDOW_WIDTH, height = WINDOW_HEIGHT - PROTO_HORIZON - 24}, PROTO_SEA)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_HORIZON, width = WINDOW_WIDTH, height = 2}, PROTO_FOAM)
	for i in 0 ..< 64 {
		sx := f32((i * 211) % 1180) + 30
		sy := PROTO_HORIZON + 36 + f32((i * 137) % 340)
		tone := i % 3 == 0 ? PROTO_SHALLOW : PROTO_SEA_BRIGHT
		rl.DrawRectangleRec(rl.Rectangle{x = sx, y = sy, width = 22, height = 3}, rl.Fade(tone, 0.5))
	}
}

// draw_proto_room_base picks a deck's wood tone: greyer for holds, cooler/darker below water.
draw_proto_room_base :: proc(ls: ship.Layout_Slot, submerged: bool) -> rl.Color {
	base := PROTO_CLIFF
	if proto_slot_is_hold(ls) {
		base = rl.Color{150, 132, 96, 255}
	}
	if submerged {
		base = proto_shade(base, 0.82)
	}
	return base
}

// --- The 3D stacked-deck ship cutaway ----------------------------------------------------
// World axes: x = ship length (bow +x, stern -x), y = up (decks stack), z = beam. The near
// side (+z) is cut away; the camera looks mostly along -z, a touch from +x and above, so we
// read the side profile and look into every open deck.

PROTO_ZB :: f32(1.15) // half-beam
PROTO_KEEL_Y :: f32(0.3) // floor of the lowest deck
PROTO_DH :: f32(0.6) // height of one deck; the hull stands n decks tall
PROTO_MARGIN :: f32(0.12) // hull planking inset around each deck

// proto_hull_x is the hull's side profile: the fore (right) and aft (left) x at a given deck
// height, as a fraction of hull height so it scales to however many decks the ship has. The
// hull swells to full length amidships and narrows toward the keel and the sheer.
proto_hull_x :: proc(y, deck_top: f32, right: bool) -> f32 {
	frac := (y - PROTO_KEEL_Y) / (deck_top - PROTO_KEEL_Y)
	fr := [5]f32{0.0, 0.22, 0.5, 0.82, 1.0}
	ls := [5]f32{-2.2, -3.7, -4.1, -4.05, -3.9}
	rs := [5]f32{2.0, 3.5, 3.9, 3.7, 3.4}
	vs := right ? rs : ls
	if frac <= 0 {
		return vs[0]
	}
	for i in 1 ..< 5 {
		if frac <= fr[i] {
			t := (frac - fr[i - 1]) / (fr[i] - fr[i - 1])
			return vs[i - 1] + (vs[i] - vs[i - 1]) * t
		}
	}
	return vs[4]
}

draw_proto_ship_cutaway :: proc(state: ^Game_State, mouse: rl.Vector2) {
	draw_proto_backdrop()

	// Order the berths bottom-to-top: holds (concealed) fill the lower decks below the water,
	// topside stations (exposed) the upper decks — one berth per deck.
	n := min(len(state.player.layout), 8)
	order: [8]int
	concealed := 0
	di := 0
	for pass in 0 ..< 2 {
		want: ship.Visibility = pass == 0 ? .Concealed : .Exposed
		for i in 0 ..< n {
			if state.player.layout[i].slot.base_visibility == want {
				order[di] = i
				di += 1
				if want == .Concealed {
					concealed += 1
				}
			}
		}
	}

	deck_top := PROTO_KEEL_Y + f32(n) * PROTO_DH
	wl := PROTO_KEEL_Y + f32(concealed) * PROTO_DH // waterline sits atop the holds
	deck_mid := (PROTO_KEEL_Y + deck_top) / 2

	// Near-level camera, a touch above and to the side: mostly-side, just enough 3D to look
	// into each open deck rather than down onto its floor.
	camera := rl.Camera3D {
		position   = rl.Vector3{1.5, deck_mid + 0.5, 16.5},
		target     = rl.Vector3{-0.2, deck_mid, 0},
		up         = rl.Vector3{0, 1, 0},
		fovy       = 34,
		projection = .PERSPECTIVE,
	}

	// Deck centres/sizes, and the projected nameplate for each, resolved before the 3D pass so
	// it can tint the hovered deck.
	centres: [8]rl.Vector3
	hxs, hys, hzs: [8]f32
	plates: [8]rl.Rectangle
	hovered := -1
	for d in 0 ..< n {
		y_bot := PROTO_KEEL_Y + f32(d) * PROTO_DH
		ymid := y_bot + PROTO_DH * 0.5
		lx := proto_hull_x(ymid, deck_top, false) + PROTO_MARGIN
		rx := proto_hull_x(ymid, deck_top, true) - PROTO_MARGIN
		centres[d] = rl.Vector3{(lx + rx) / 2, ymid, 0}
		hxs[d] = (rx - lx) / 2
		hys[d] = PROTO_DH * 0.5 - 0.05
		hzs[d] = PROTO_ZB - PROTO_MARGIN

		// Nameplate to the right of the deck's open front, projected to screen.
		p := rl.GetWorldToScreen(rl.Vector3{rx, ymid, PROTO_ZB}, camera)
		plates[d] = proto_nameplate_rect(p.x + 70, p.y - 11, state.player.layout[order[d]])
		if rl.CheckCollisionPointRec(mouse, plates[d]) {
			hovered = d
		}
	}

	rl.BeginMode3D(camera)

	draw_proto_hull_body(deck_top)

	for d in 0 ..< n {
		ls := state.player.layout[order[d]]
		base := draw_proto_room_base(ls, centres[d].y < wl)
		if d == hovered {
			base = PROTO_SEA_BRIGHT
		}
		draw_proto_deck_room(centres[d], hxs[d], hys[d], hzs[d], base)
	}

	draw_proto_rig(deck_top)

	// A translucent sea slab filling the hull below the waterline — the submerged holds read as
	// underwater. Drawn after the opaque hull so it blends over it.
	rl.DrawCube(rl.Vector3{0, wl - 12, 0.2}, 40, 24, 40, rl.Fade(PROTO_SEA, 0.32))

	rl.EndMode3D()

	// Nameplates and leader ticks over the scene.
	for d in 0 ..< n {
		anchor := rl.GetWorldToScreen(rl.Vector3{proto_hull_x(centres[d].y, deck_top, true) - PROTO_MARGIN, centres[d].y, PROTO_ZB}, camera)
		hot := d == hovered
		rl.DrawLineEx(anchor, rl.Vector2{plates[d].x, plates[d].y + plates[d].height / 2}, hot ? 2 : 1, rl.Fade(hot ? PROTO_FOAM : PROTO_INK, 0.6))
		draw_proto_nameplate_at(plates[d], state.player.layout[order[d]], hot)
	}

	if hovered >= 0 {
		draw_proto_tooltip(state, order[hovered], plates[hovered])
	}
	draw_build_heading("At Anchor")
	draw_proto_stat_strip(state)
}

// draw_proto_hull_body paints the wooden ship the decks are cut into: the far side wall as
// horizontal bands following the hull profile (with a belly narrowing to the keel), a stern
// transom and stern castle, a forecastle, and the main deck plank. The near side is left open
// — that is the cutaway. The bands show through the margins between decks as the hull's beams.
draw_proto_hull_body :: proc(deck_top: f32) {
	far := -PROTO_ZB
	dark := proto_shade(PROTO_TRUNK, 0.82)

	// Far wall + belly, in fine horizontal bands.
	band := f32(0.12)
	for y := f32(-0.4); y < deck_top; y += band {
		ymid := y + band * 0.5
		l, r: f32
		if ymid < PROTO_KEEL_Y {
			// Belly: taper both ends toward the keel point.
			f := clamp((ymid + 0.4) / (PROTO_KEEL_Y + 0.4), 0, 1)
			l = proto_hull_x(PROTO_KEEL_Y, deck_top, false) * f
			r = proto_hull_x(PROTO_KEEL_Y, deck_top, true) * f
		} else {
			l = proto_hull_x(ymid, deck_top, false)
			r = proto_hull_x(ymid, deck_top, true)
		}
		if r - l < 0.05 {
			continue
		}
		rl.DrawCube(rl.Vector3{(l + r) / 2, ymid, far}, r - l, band + 0.01, 0.1, dark)
	}

	// Hull bottom: a shallow keel slab spanning the beam, so the ship has an underside.
	rl.DrawCube(rl.Vector3{0, PROTO_KEEL_Y - 0.34, 0}, 6.2, 0.55, 2 * PROTO_ZB, proto_shade(PROTO_TRUNK, 0.7))

	// Stern transom (flat aft face) and a stern castle standing above the main deck.
	sx := proto_hull_x(deck_top * 0.5, deck_top, false)
	rl.DrawCube(rl.Vector3{sx + 0.05, deck_top * 0.5, 0}, 0.16, deck_top, 2 * PROTO_ZB, dark)
	rl.DrawCube(rl.Vector3{sx + 0.55, deck_top + 0.55, 0}, 1.3, 1.3, 2 * PROTO_ZB - 0.08, PROTO_TRUNK)
	rl.DrawCubeWires(rl.Vector3{sx + 0.55, deck_top + 0.55, 0}, 1.3, 1.3, 2 * PROTO_ZB - 0.08, proto_shade(PROTO_ROCK, 0.9))

	// Forecastle at the bow.
	bx := proto_hull_x(deck_top * 0.86, deck_top, true)
	rl.DrawCube(rl.Vector3{bx - 0.55, deck_top + 0.4, 0}, 1.2, 1.0, 2 * PROTO_ZB - 0.08, PROTO_TRUNK)

	// Main deck plank across the top of the stacked decks.
	rl.DrawCube(rl.Vector3{-0.3, deck_top + 0.05, 0}, 7.6, 0.12, 2 * PROTO_ZB, PROTO_CLIFF)
}

// draw_proto_deck_room paints one empty deck: floor, back wall (far z), fore and aft end
// walls; the front (+z) and top are open, so the camera looks in and the deck above closes it.
draw_proto_deck_room :: proc(c: rl.Vector3, hx, hy, hz: f32, base: rl.Color) {
	t :: f32(0.05)
	rl.DrawCube(rl.Vector3{c.x, c.y - hy, c.z}, 2 * hx, t, 2 * hz, proto_shade(base, 0.56)) // floor
	rl.DrawCube(rl.Vector3{c.x, c.y, c.z - hz}, 2 * hx, 2 * hy, t, proto_shade(base, 0.9)) // back
	rl.DrawCube(rl.Vector3{c.x - hx, c.y, c.z}, t, 2 * hy, 2 * hz, proto_shade(base, 0.72)) // aft end
	rl.DrawCube(rl.Vector3{c.x + hx, c.y, c.z}, t, 2 * hy, 2 * hz, proto_shade(base, 1.06)) // fore end

	wire := rl.Fade(PROTO_INK, 0.55)
	rl.DrawCubeWires(rl.Vector3{c.x, c.y - hy, c.z}, 2 * hx, t, 2 * hz, wire)
	rl.DrawCubeWires(rl.Vector3{c.x, c.y, c.z - hz}, 2 * hx, 2 * hy, t, wire)
}

// draw_proto_rig is the standing masts, sails and bowsprit above the main deck — the silhouette
// that says "ship" over the cutaway decks.
draw_proto_rig :: proc(deck_top: f32) {
	deck := deck_top + 0.1
	masts := [2]f32{-1.0, 1.4}
	heights := [2]f32{2.3, 2.0}
	for mx, mi in masts {
		top := deck + heights[mi]
		rl.DrawCylinder(rl.Vector3{mx, deck, 0}, 0.05, 0.07, heights[mi], 8, PROTO_TRUNK)
		// A square sail: a thin cube spanning x, facing the camera.
		sw := f32(1.6)
		sh := heights[mi] * 0.58
		sy := deck + heights[mi] * 0.52
		rl.DrawCube(rl.Vector3{mx, sy, 0.05}, sw, sh, 0.04, PROTO_CREAM)
		rl.DrawCubeWires(rl.Vector3{mx, sy, 0.05}, sw, sh, 0.04, PROTO_SAND)
		// Yard.
		rl.DrawCube(rl.Vector3{mx, top - 0.15, 0}, sw + 0.2, 0.06, 0.06, PROTO_TRUNK)
	}
	// Bowsprit off the bow.
	bx := proto_hull_x(deck_top * 0.9, deck_top, true)
	rl.DrawCylinder(rl.Vector3{bx - 0.2, deck, 0}, 0.05, 0.03, 1.4, 8, PROTO_TRUNK)
}

// --- Nameplates, tooltip, stat strip (shared) --------------------------------------------

proto_nameplate_rect :: proc(center_x, y: f32, ls: ship.Layout_Slot) -> rl.Rectangle {
	label := fmt.ctprintf("%s", proto_slot_title(ls))
	w := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1).x
	return rl.Rectangle{x = center_x - w / 2 - 8, y = y, width = w + 16, height = 22}
}

draw_proto_nameplate_at :: proc(rect: rl.Rectangle, ls: ship.Layout_Slot, hot: bool) {
	is_hold := proto_slot_is_hold(ls)
	rl.DrawRectangleRec(rect, rl.Fade(PROTO_PARCHMENT, hot ? 1.0 : 0.94))
	rl.DrawRectangleLinesEx(rect, hot ? 2 : 1, hot ? PROTO_SEA_DEEP : PROTO_CLIFF)
	rl.DrawTextEx(
		ui_font_body,
		fmt.ctprintf("%s", proto_slot_title(ls)),
		rl.Vector2{rect.x + 8, rect.y + 3},
		UI_BODY_SIZE,
		1,
		is_hold ? PROTO_INK_MUTED : PROTO_INK,
	)
}

// draw_proto_tooltip is the hovered deck's full description, a parchment card clamped
// on-screen beside the deck — no persistent panel to occlude a room.
draw_proto_tooltip :: proc(state: ^Game_State, slot: int, near: rl.Rectangle) {
	tw, th := f32(300), f32(150)
	tx := near.x + near.width + 12
	if tx + tw > WINDOW_WIDTH - 8 {
		tx = near.x - tw - 12
	}
	tx = clamp(tx, 8, WINDOW_WIDTH - 8 - tw)
	ty := clamp(near.y, 46, WINDOW_HEIGHT - 8 - th)

	card := rl.Rectangle{x = tx, y = ty, width = tw, height = th}
	rl.DrawRectangleRec(card, PROTO_PARCHMENT)
	rl.DrawRectangleLinesEx(card, 2, PROTO_SEA_DEEP)

	title, spec, intent, extra := proto_lines(state.player.layout[slot])
	px := card.x + 14
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", title), rl.Vector2{px, card.y + 12}, UI_BODY_SIZE, 1, PROTO_INK)
	rl.DrawRectangleRec(rl.Rectangle{x = px, y = card.y + 34, width = card.width - 28, height = 2}, PROTO_SAND)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", intent), rl.Vector2{px, card.y + 46}, UI_BODY_SIZE, 1, PROTO_INK)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", spec), rl.Vector2{px, card.y + 74}, UI_BODY_SIZE, 1, PROTO_INK_MUTED)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", extra), rl.Vector2{px, card.y + 102}, UI_BODY_SIZE, 1, PROTO_INK_MUTED)
}

draw_proto_stat_strip :: proc(state: ^Game_State) {
	stat := fmt.ctprintf("%s", ship_stat_line(s = &state.player, weight = true))
	sw := rl.MeasureTextEx(ui_font_body, stat, UI_BODY_SIZE, 1).x
	strip := rl.Rectangle{x = 38, y = WINDOW_HEIGHT - 42, width = sw + 20, height = 26}
	rl.DrawRectangleRec(strip, rl.Fade(PROTO_PARCHMENT, 0.92))
	rl.DrawRectangleLinesEx(strip, 2, PROTO_CLIFF)
	rl.DrawTextEx(ui_font_body, stat, rl.Vector2{strip.x + 10, strip.y + 5}, UI_BODY_SIZE, 1, PROTO_INK)
}

// capture_shot_ship_prototypes photographs the cutaway the way capture_shot_home shoots Home:
// a throwaway Sim ticked once into a fresh Game_State, the global put back to Current after.
capture_shot_ship_prototypes :: proc(state: ^Capture_State) {
	if !rl.IsWindowReady() {
		return
	}

	s := sim.sim_create(VOYAGE_SEED)
	defer sim.sim_destroy(&s)

	game := Game_State{}
	defer delete(game.visited)
	defer delete(game.positions)
	defer delete(game.voyage_map.nodes)

	events: [dynamic]sim.Event
	defer delete(events)
	sim.sim_tick(&s, &events)
	for e in events {
		dispatch(&game, e)
	}
	map_width_set(&game, MAP_HOME_W)

	proto_variant = .Ship_Cutaway
	draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0)
	draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0)
	capture_write(state, "proto-ship-cutaway")
	proto_variant = .Current
}
