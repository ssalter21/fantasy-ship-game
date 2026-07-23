#+private
package presentation

// PROTOTYPE — THROWAWAY. Branch worktree-prototype-ship-side-view; never merges to main.
//
// Round 3. The verdict on round 2 (a big ship sprite/painting on a bright sea) was: it lost
// the 3D, look-into-the-ship perspective the original vision (round 1's Variant A, a real
// Camera3D ghost hull) had. This round brings that perspective back and puts it *inside the
// slots*: every berth is now an EMPTY ROOM you look into — a placeholder chamber that later
// gets its own bespoke sprites and animations per slot and per fitting.
//
// Three structurally different takes on "each slot is an empty room", cycled with LEFT/RIGHT
// or the floating top-centre bar (styled foreign to the palette on purpose — scaffolding):
//
//   Current — today's flat navy cutaway, untouched, as the baseline to flip against.
//   B1      — cutaway rooms, oblique: the exact cutaway slot layout, but each slot card is a
//             one-point-perspective empty room carved into the hull. Pixel-flat fills, hard
//             edges. The original perspective, brought inside the slots, in pixel art.
//   B2      — cutaway rooms, true 3D: round 1's Camera3D revived, each slot an open, roofless
//             compartment you look down into. The literal original 3D perspective.
//   B3      — cutaway rooms, isometric: the same empty rooms in a 3/4 iso register.
//
// The name of each fitting rides a parchment nameplate on its room; hovering a room loads the
// full description into the docked inspector. Rooms are drawn empty by design — the art that
// fills them is the thing we are NOT building yet. Drag-refit is inert (read-only prototype).
//
// The new-roster colours are PROTO_* locals here on purpose: the style guide leaves the
// shipped COLOUR_* constants navy until the real migration, and a throwaway must not front-run
// it. The bright scene (sky/sea) is kept from round 2; only the ship is reconceived as rooms.

import "core:fmt"
import "core:math"
import cutaway "./cutaway"
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
	Rooms_Oblique,
	Rooms_3D,
	Rooms_Iso,
}

proto_variant: Proto_Variant = .Current

proto_variant_label :: proc(v: Proto_Variant) -> string {
	switch v {
	case .Current:
		return "Current — navy cutaway"
	case .Rooms_Oblique:
		return "B1 — cutaway rooms (oblique)"
	case .Rooms_3D:
		return "B2 — cutaway rooms (true 3D)"
	case .Rooms_Iso:
		return "B3 — cutaway rooms (isometric)"
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

PROTO_BAR_W :: 430
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

// proto_lines is the one description formatter every variant reads: title, the spec line
// (size · phase · tags), the effect intent, and the material facts (weight, cargo, berth).
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
	case .Rooms_Oblique:
		draw_proto_rooms_oblique(state, mouse)
	case .Rooms_3D:
		draw_proto_rooms_3d(state, mouse)
	case .Rooms_Iso:
		draw_proto_rooms_iso(state, mouse)
	}
}

// --- Shared paint helpers ----------------------------------------------------------------

// proto_shade multiplies a colour's rgb by f (clamped) — one base wood tone lit five ways
// gives a room its floor/back/wall shading without five hand-picked constants.
proto_shade :: proc(c: rl.Color, f: f32) -> rl.Color {
	m :: proc(v: u8, f: f32) -> u8 {
		r := f32(v) * f
		if r > 255 {r = 255}
		if r < 0 {r = 0}
		return u8(r)
	}
	return rl.Color{m(c.r, f), m(c.g, f), m(c.b, f), c.a}
}

// proto_quad fills a four-corner face. Drawn in both windings so a face never vanishes to
// 2D back-face culling whichever way its corners wound — overdraw is free at this scale.
proto_quad :: proc(a, b, c, d: rl.Vector2, col: rl.Color) {
	rl.DrawTriangle(a, b, c, col)
	rl.DrawTriangle(a, c, d, col)
	rl.DrawTriangle(a, c, b, col)
	rl.DrawTriangle(a, d, c, col)
}

// draw_proto_cloud stacks three blocky rects — a pixel cloud, no curves.
draw_proto_cloud :: proc(cx, cy: f32) {
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 70, y = cy + 14, width = 150, height = 22}, PROTO_CLOUD_SHADOW)
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 60, y = cy, width = 120, height = 24}, PROTO_CLOUD)
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 28, y = cy - 14, width = 62, height = 18}, PROTO_CLOUD)
}

PROTO_WATER_Y :: f32(290) // the waterline: exposed rooms above, concealed holds below

draw_proto_backdrop :: proc() {
	rl.ClearBackground(PROTO_SKY_HIGH)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = 84, width = WINDOW_WIDTH, height = 80}, PROTO_SKY)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = 164, width = WINDOW_WIDTH, height = PROTO_WATER_Y - 164}, PROTO_HAZE)
	draw_proto_cloud(210, 96)
	draw_proto_cloud(940, 62)
	draw_proto_cloud(1130, 150)

	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_WATER_Y, width = WINDOW_WIDTH, height = 26}, PROTO_SEA_DEEP)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_WATER_Y + 26, width = WINDOW_WIDTH, height = WINDOW_HEIGHT - PROTO_WATER_Y - 26}, PROTO_SEA)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_WATER_Y, width = WINDOW_WIDTH, height = 2}, PROTO_FOAM)
	for i in 0 ..< 60 {
		sx := f32((i * 211) % 1160) + 40
		sy := PROTO_WATER_Y + 40 + f32((i * 137) % 360)
		tone := i % 3 == 0 ? PROTO_SHALLOW : PROTO_SEA_BRIGHT
		rl.DrawRectangleRec(rl.Rectangle{x = sx, y = sy, width = 24, height = 3}, rl.Fade(tone, 0.5))
	}
}

// draw_proto_room_base picks a room's wood tone: cooler/darker for holds and for anything
// below the waterline, so a glance reads exposed-vs-hold and above-vs-below off the wood.
draw_proto_room_base :: proc(ls: ship.Layout_Slot, submerged: bool) -> rl.Color {
	base := PROTO_CLIFF
	if proto_slot_is_hold(ls) {
		base = rl.Color{150, 132, 96, 255} // a greyer, cargo-store timber
	}
	if submerged {
		base = proto_shade(base, 0.8)
	}
	return base
}

// --- B1: cutaway rooms, oblique ----------------------------------------------------------
// The shipped cutaway's own slot layout (cutaway_slot_rects), but each slot card is drawn as
// a one-point-perspective empty room set into the hull.

draw_proto_rooms_oblique :: proc(state: ^Game_State, mouse: rl.Vector2) {
	draw_proto_backdrop()
	draw_proto_hull_frame()

	region := cutaway.cutaway_home_region(WINDOW_WIDTH)
	rects, n := cutaway.cutaway_slot_rects(state.player.layout[:], region)

	// Hover is the room card itself — the whole opening is the target.
	hovered := -1
	for i in 0 ..< n {
		if rl.CheckCollisionPointRec(mouse, rects[i]) {
			hovered = i
		}
	}

	for i in 0 ..< n {
		ls := state.player.layout[i]
		exposed := ls.slot.base_visibility == .Exposed
		base := draw_proto_room_base(ls, !exposed)
		draw_proto_room(rects[i], base, exposed, i == hovered)

		// Nameplate on the room's sill.
		plate_y := rects[i].y + rects[i].height - 26
		draw_proto_nameplate(rects[i].x + rects[i].width / 2, plate_y, ls, i == hovered)
	}

	if hovered >= 0 {
		draw_proto_tooltip(state, hovered, rects[hovered])
	}
	draw_build_heading("At Anchor")
	draw_proto_stat_strip(state)
}

// draw_proto_room paints an empty one-point-perspective chamber inside r: the back wall
// inset uniformly, floor/ceiling/side walls as the four connecting quads, the opening left
// open. Flat fills, hard edges — a pixel-art room waiting for its bespoke sprite.
draw_proto_room :: proc(r: rl.Rectangle, base: rl.Color, exposed, hot: bool) {
	d := f32(20)
	if r.width < 150 || r.height < 116 {
		d = 15
	}
	ftl := rl.Vector2{r.x, r.y}
	ftr := rl.Vector2{r.x + r.width, r.y}
	fbl := rl.Vector2{r.x, r.y + r.height}
	fbr := rl.Vector2{r.x + r.width, r.y + r.height}
	btl := rl.Vector2{r.x + d, r.y + d}
	btr := rl.Vector2{r.x + r.width - d, r.y + d}
	bbl := rl.Vector2{r.x + d, r.y + r.height - d}
	bbr := rl.Vector2{r.x + r.width - d, r.y + r.height - d}

	// Back wall, then the four receding faces.
	rl.DrawRectangleRec(rl.Rectangle{x = btl.x, y = btl.y, width = btr.x - btl.x, height = bbl.y - btl.y}, proto_shade(base, 0.9))
	proto_quad(fbl, fbr, bbr, bbl, proto_shade(base, 0.56)) // floor
	proto_quad(ftl, ftr, btr, btl, proto_shade(base, 0.68)) // ceiling
	proto_quad(ftl, btl, bbl, fbl, proto_shade(base, 0.78)) // left wall
	proto_quad(ftr, btr, bbr, fbr, proto_shade(base, 1.1)) // right wall (lit)

	// Floorboard perspective lines toward the vanishing centre.
	for k in 1 ..< 4 {
		t := f32(k) / 4
		fp := rl.Vector2{fbl.x + (fbr.x - fbl.x) * t, fbl.y}
		bp := rl.Vector2{bbl.x + (bbr.x - bbl.x) * t, bbl.y}
		rl.DrawLineEx(fp, bp, 1, proto_shade(base, 0.46))
	}

	// One quiet feature on the back wall so the empty room still reads "ship": a porthole to
	// the sea for exposed rooms, a floor hatch for the holds below.
	bw := btr.x - btl.x
	bh := bbl.y - btl.y
	if exposed {
		cx := (btl.x + btr.x) / 2
		cy := btl.y + bh * 0.42
		rr := min(bw, bh) * 0.16
		rl.DrawCircleV(rl.Vector2{cx, cy}, rr + 3, PROTO_TRUNK)
		rl.DrawCircleV(rl.Vector2{cx, cy}, rr, PROTO_SEA_BRIGHT)
		rl.DrawRectangleRec(rl.Rectangle{x = cx - rr, y = cy, width = rr * 2, height = rr}, rl.Fade(PROTO_SEA_DEEP, 0.85))
		rl.DrawCircleLines(i32(cx), i32(cy), rr, PROTO_FOAM)
	} else {
		hs := bw * 0.16
		cx := (bbl.x + bbr.x) / 2
		cy := (bbl.y + fbl.y) / 2
		rl.DrawRectangleRec(rl.Rectangle{x = cx - hs, y = cy - hs * 0.4, width = hs * 2, height = hs * 0.8}, proto_shade(base, 0.38))
	}

	// Crisp linework: opening, depth edges, back-wall frame.
	edge := rl.Fade(PROTO_INK, 0.5)
	rl.DrawLineEx(ftl, btl, 1, edge)
	rl.DrawLineEx(ftr, btr, 1, edge)
	rl.DrawLineEx(fbl, bbl, 1, edge)
	rl.DrawLineEx(fbr, bbr, 1, edge)
	rl.DrawRectangleLinesEx(rl.Rectangle{x = btl.x, y = btl.y, width = bw, height = bh}, 1, edge)
	rl.DrawRectangleLinesEx(r, hot ? 3 : 2, hot ? PROTO_SEA_DEEP : PROTO_INK)
}

// draw_proto_hull_frame is the wooden ship the rooms are cut into: a side-profile hull from
// deck to keel (stern nearly plumb, bow sweeping), a deck cap, a stern castle, two masts
// into the sky, and a sea tint over the submerged run. Drawn before the rooms, which sit on
// top; the gaps between rooms read as the hull's own beams.
draw_proto_hull_frame :: proc() {
	deck := f32(84)
	keel := f32(636)
	x0 := f32(120)
	x1 := f32(1128)

	for yy := deck; yy < keel; yy += 4 {
		t := (yy - deck) / (keel - deck)
		stern_inset := 46 * t * t
		bow_inset := 150 * t * math.sqrt_f32(t)
		tone := yy >= PROTO_WATER_Y ? proto_shade(PROTO_TRUNK, 0.72) : PROTO_TRUNK
		rl.DrawRectangleRec(rl.Rectangle{x = x0 + stern_inset, y = yy, width = (x1 - bow_inset) - (x0 + stern_inset), height = 4}, tone)
	}

	// Deck cap and stern castle.
	rl.DrawRectangleRec(rl.Rectangle{x = x0, y = deck - 12, width = x1 - x0 - 44, height = 14}, PROTO_CLIFF)
	rl.DrawRectangleRec(rl.Rectangle{x = x0, y = deck - 12, width = x1 - x0 - 44, height = 3}, PROTO_SAND)
	rl.DrawRectangleRec(rl.Rectangle{x = x0 - 6, y = deck - 66, width = 132, height = 56}, PROTO_TRUNK)
	rl.DrawRectangleRec(rl.Rectangle{x = x0 - 6, y = deck - 66, width = 132, height = 6}, PROTO_SAND)
	rl.DrawRectangleLinesEx(rl.Rectangle{x = x0 - 6, y = deck - 66, width = 132, height = 56}, 2, PROTO_ROCK)
	// Two dark windows in the stern castle, echoing the topside portholes.
	rl.DrawRectangleRec(rl.Rectangle{x = x0 + 22, y = deck - 50, width = 20, height = 22}, PROTO_SEA_DEEP)
	rl.DrawRectangleRec(rl.Rectangle{x = x0 + 66, y = deck - 50, width = 20, height = 22}, PROTO_SEA_DEEP)

	// Bowsprit off the bow (kept low so it clears the top UI; masts are omitted — the cutaway
	// rooms and hull carry the ship read without rigging climbing into the switcher bar).
	rl.DrawLineEx(rl.Vector2{x1 - 70, deck - 4}, rl.Vector2{x1 + 40, deck - 30}, 5, PROTO_TRUNK)

	// Waterline rule and a translucent tint over the submerged hull run.
	rl.DrawRectangleRec(rl.Rectangle{x = x0 - 40, y = PROTO_WATER_Y, width = (x1 + 40) - (x0 - 40), height = PROTO_WATER_Y < keel ? keel - PROTO_WATER_Y : 0}, rl.Fade(PROTO_SEA, 0.16))
	rl.DrawLineEx(rl.Vector2{40, PROTO_WATER_Y}, rl.Vector2{WINDOW_WIDTH - 40, PROTO_WATER_Y}, 2, rl.Fade(PROTO_FOAM, 0.8))
}

// --- B2: cutaway rooms, true 3D ----------------------------------------------------------
// Round 1's Camera3D, mostly side-on, but the slots are now open, roofless compartment boxes
// you look down and in to — the original 3D perspective made literal, rooms left empty.

draw_proto_rooms_3d :: proc(state: ^Game_State, mouse: rl.Vector2) {
	draw_proto_backdrop()

	// Raised, closer camera looking down the length: top-down enough to see into the roofless
	// rooms, side enough to keep the "mostly-side" read.
	camera := rl.Camera3D {
		position   = rl.Vector3{3.6, 5.6, 8.4},
		target     = rl.Vector3{0, 0.9, 0},
		up         = rl.Vector3{0, 1, 0},
		fovy       = 46,
		projection = .PERSPECTIVE,
	}

	n := min(len(state.player.layout), 8)
	exposed_total, concealed_total := 0, 0
	for i in 0 ..< n {
		if state.player.layout[i].slot.base_visibility == .Exposed {
			exposed_total += 1
		} else {
			concealed_total += 1
		}
	}
	// Two ranks in depth (z), not height: exposed forward (near, +z), concealed aft (far, -z),
	// both on one floor so the camera looks down into every open room instead of stacking them.
	anchors: [8]rl.Vector3
	halfs: [8]f32
	ei, ci := 0, 0
	for i in 0 ..< n {
		ls := state.player.layout[i]
		switch ls.slot.size {
		case .Small:
			halfs[i] = 0.62
		case .Medium:
			halfs[i] = 0.78
		case .Large:
			halfs[i] = 0.95
		}
		if ls.slot.base_visibility == .Exposed {
			t := f32(ei + 1) / f32(exposed_total + 1)
			ei += 1
			anchors[i] = rl.Vector3{-3.9 + 7.8 * t, 0.95, 1.35}
		} else {
			t := f32(ci + 1) / f32(concealed_total + 1)
			ci += 1
			anchors[i] = rl.Vector3{-3.3 + 6.6 * t, 0.95, -1.35}
		}
	}

	// Project centres and hit-test nameplates before the 3D pass, so it can tint the hovered.
	plates: [8]rl.Rectangle
	hovered := -1
	for i in 0 ..< n {
		p := rl.GetWorldToScreen(rl.Vector3{anchors[i].x, anchors[i].y + halfs[i], anchors[i].z}, camera)
		plates[i] = proto_nameplate_rect(p.x, p.y - 30, state.player.layout[i])
		if rl.CheckCollisionPointRec(mouse, plates[i]) {
			hovered = i
		}
	}

	rl.BeginMode3D(camera)

	// A wireframe hull cage — the near wall cut away — so every open room reads through it
	// instead of being fogged inside a solid block.
	rl.DrawCubeWires(rl.Vector3{0, 0.95, 0}, 8.6, 2.0, 3.4, rl.Fade(PROTO_CREAM, 0.5))
	rl.DrawCubeWires(rl.Vector3{-4.3, 1.4, 0}, 1.1, 2.6, 3.2, rl.Fade(PROTO_CREAM, 0.4)) // stern castle
	// A faint deck floor plane the rooms sit on.
	rl.DrawPlane(rl.Vector3{0, -0.02, 0}, rl.Vector2{9.0, 3.6}, rl.Fade(PROTO_TRUNK, 0.55))

	for i in 0 ..< n {
		ls := state.player.layout[i]
		base := draw_proto_room_base(ls, false)
		if i == hovered {
			base = PROTO_SEA_BRIGHT
		}
		draw_proto_room_3d(anchors[i], halfs[i], base)
	}
	rl.EndMode3D()

	for i in 0 ..< n {
		draw_proto_nameplate_at(plates[i], state.player.layout[i], i == hovered)
	}

	if hovered >= 0 {
		draw_proto_tooltip(state, hovered, plates[hovered])
	}
	draw_build_heading("At Anchor")
	draw_proto_stat_strip(state)
}

// draw_proto_room_3d draws one open, roofless compartment: floor, back wall, two side walls;
// front and top left open so the camera looks down and in. Wire outlines keep the edges crisp.
draw_proto_room_3d :: proc(c: rl.Vector3, h: f32, base: rl.Color) {
	t :: f32(0.06)
	floor := proto_shade(base, 0.58)
	back := proto_shade(base, 0.9)
	lwall := proto_shade(base, 0.76)
	rwall := proto_shade(base, 1.08)

	rl.DrawCube(rl.Vector3{c.x, c.y - h, c.z}, 2 * h, t, 2 * h, floor)
	rl.DrawCube(rl.Vector3{c.x, c.y, c.z - h}, 2 * h, 2 * h, t, back)
	rl.DrawCube(rl.Vector3{c.x - h, c.y, c.z}, t, 2 * h, 2 * h, lwall)
	rl.DrawCube(rl.Vector3{c.x + h, c.y, c.z}, t, 2 * h, 2 * h, rwall)

	wire := rl.Fade(PROTO_INK, 0.6)
	rl.DrawCubeWires(rl.Vector3{c.x, c.y - h, c.z}, 2 * h, t, 2 * h, wire)
	rl.DrawCubeWires(rl.Vector3{c.x, c.y, c.z - h}, 2 * h, 2 * h, t, wire)
}

// --- B3: cutaway rooms, isometric --------------------------------------------------------
// The same empty rooms in a 3/4 iso register: two rows of iso chambers, floor diamond and two
// back walls, open front and top.

draw_proto_rooms_iso :: proc(state: ^Game_State, mouse: rl.Vector2) {
	draw_proto_backdrop()

	n := min(len(state.player.layout), 8)
	exposed_total, concealed_total := 0, 0
	for i in 0 ..< n {
		if state.player.layout[i].slot.base_visibility == .Exposed {
			exposed_total += 1
		} else {
			concealed_total += 1
		}
	}

	centres: [8]rl.Vector2
	w2s: [8]f32
	ei, ci := 0, 0
	for i in 0 ..< n {
		ls := state.player.layout[i]
		switch ls.slot.size {
		case .Small:
			w2s[i] = 62
		case .Medium:
			w2s[i] = 78
		case .Large:
			w2s[i] = 96
		}
		if ls.slot.base_visibility == .Exposed {
			t := f32(ei) / f32(max(exposed_total - 1, 1))
			ei += 1
			centres[i] = rl.Vector2{170 + 900 * t, 250}
		} else {
			t := f32(ci) / f32(max(concealed_total - 1, 1))
			ci += 1
			centres[i] = rl.Vector2{210 + 820 * t, 470}
		}
	}

	// Nameplates sit below each iso room; hover them.
	plates: [8]rl.Rectangle
	hovered := -1
	for i in 0 ..< n {
		plates[i] = proto_nameplate_rect(centres[i].x, centres[i].y + w2s[i] * 0.5 + 12, state.player.layout[i])
		if rl.CheckCollisionPointRec(mouse, plates[i]) {
			hovered = i
		}
	}

	for i in 0 ..< n {
		ls := state.player.layout[i]
		base := draw_proto_room_base(ls, ls.slot.base_visibility != .Exposed)
		draw_proto_room_iso(centres[i], w2s[i], base, i == hovered)
		draw_proto_nameplate_at(plates[i], ls, i == hovered)
	}

	if hovered >= 0 {
		draw_proto_tooltip(state, hovered, plates[hovered])
	}
	draw_build_heading("At Anchor")
	draw_proto_stat_strip(state)
}

// draw_proto_room_iso paints an iso empty room centred at c: a floor diamond (half-width w2,
// 2:1 iso), two back walls rising by wall height, open front and top.
draw_proto_room_iso :: proc(c: rl.Vector2, w2: f32, base: rl.Color, hot: bool) {
	h2 := w2 * 0.5
	H := w2 * 0.62 // short walls: the floor dominates, so it reads as an open room, not a crate

	top := rl.Vector2{c.x, c.y - h2}
	right := rl.Vector2{c.x + w2, c.y}
	bot := rl.Vector2{c.x, c.y + h2}
	left := rl.Vector2{c.x - w2, c.y}

	// Floor diamond.
	proto_quad(top, right, bot, left, proto_shade(base, 0.58))

	// Back-left and back-right walls, rising by H.
	tlu := rl.Vector2{top.x, top.y - H}
	llu := rl.Vector2{left.x, left.y - H}
	rlu := rl.Vector2{right.x, right.y - H}
	proto_quad(left, top, tlu, llu, proto_shade(base, 0.8)) // back-left
	proto_quad(top, right, rlu, tlu, proto_shade(base, 1.06)) // back-right

	// A small porthole on the back-right wall so the empty room still reads "ship".
	pc := rl.Vector2{(top.x + right.x) / 2 + 2, (top.y + right.y) / 2 - H * 0.5}
	rl.DrawCircleV(pc, w2 * 0.12 + 2, PROTO_TRUNK)
	rl.DrawCircleV(pc, w2 * 0.12, PROTO_SEA_BRIGHT)
	rl.DrawCircleLines(i32(pc.x), i32(pc.y), w2 * 0.12, PROTO_FOAM)

	// Crisp edges.
	ink := hot ? PROTO_SEA_DEEP : PROTO_INK
	th := f32(hot ? 3 : 2)
	rl.DrawLineEx(left, top, th, ink)
	rl.DrawLineEx(top, right, th, ink)
	rl.DrawLineEx(left, bot, th, ink)
	rl.DrawLineEx(bot, right, th, ink)
	rl.DrawLineEx(left, llu, th, ink)
	rl.DrawLineEx(top, tlu, th, ink)
	rl.DrawLineEx(right, rlu, th, ink)
	rl.DrawLineEx(llu, tlu, th, ink)
	rl.DrawLineEx(tlu, rlu, th, ink)
}

// --- Nameplates, inspector, stat strip (shared) ------------------------------------------

proto_nameplate_rect :: proc(center_x, y: f32, ls: ship.Layout_Slot) -> rl.Rectangle {
	label := fmt.ctprintf("%s", proto_slot_title(ls))
	w := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1).x
	return rl.Rectangle{x = center_x - w / 2 - 8, y = y, width = w + 16, height = 22}
}

// draw_proto_nameplate positions and paints a plate centred on center_x at y.
draw_proto_nameplate :: proc(center_x, y: f32, ls: ship.Layout_Slot, hot: bool) {
	draw_proto_nameplate_at(proto_nameplate_rect(center_x, y, ls), ls, hot)
}

// draw_proto_nameplate_at paints a pre-placed plate — parchment, ink text; words on parchment.
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

// draw_proto_tooltip is the hovered room's full description, drawn as a parchment card next
// to that room and clamped on-screen — no persistent panel to occlude a room that a fixed
// dock would sit over. Nothing hovered draws nothing; the nameplates carry the names.
draw_proto_tooltip :: proc(state: ^Game_State, hovered: int, near: rl.Rectangle) {
	if hovered < 0 {
		return
	}
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

	title, spec, intent, extra := proto_lines(state.player.layout[hovered])
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

// capture_shot_ship_prototypes photographs every room variant the way capture_shot_home shoots
// Home: a throwaway Sim ticked once into a fresh Game_State, one shot per variant, the global
// put back to Current on the way out. Prototype-only, removed with this file.
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

	shots := [3]struct {
		variant: Proto_Variant,
		label:   string,
	} {
		{.Rooms_Oblique, "proto-b1-rooms-oblique"},
		{.Rooms_3D, "proto-b2-rooms-3d"},
		{.Rooms_Iso, "proto-b3-rooms-iso"},
	}

	for shot in shots {
		proto_variant = shot.variant
		draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0)
		draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0)
		capture_write(state, shot.label)
	}
	proto_variant = .Current
}
