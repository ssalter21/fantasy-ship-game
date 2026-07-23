#+private
package presentation

// PROTOTYPE — THROWAWAY. Branch worktree-prototype-ship-side-view; never merges to main.
//
// Question under test: what should the main ship screen (Home / Build surface) look like as
// a *mostly-side, 3D-feeling view of the ship*, with the fittings' descriptions read more
// clearly than the current cutaway's name + chip + terse intent?
//
// Three structurally different variants, cycled with the LEFT/RIGHT arrow keys or the
// floating top-centre bar (deliberately styled foreign to the palette — it is not part of
// any design being evaluated):
//
//   Current  — today's flat cutaway, untouched, as the baseline to flip against.
//   A        — a true 3D ghost hull (raylib Camera3D, mostly side-on): slots are markers on
//              deck and in the belly, name chips pinned to them, and a docked inspector
//              panel on the right carries the full description of the hovered fitting.
//   B        — a labelled diagram: a large painted side elevation with an oblique deck for
//              depth, and every fitting's description always visible in callout boxes with
//              leader lines — nothing is behind a hover.
//   C        — profile + manifest: the ship as a big side profile with numbered berth pins,
//              and a full-width manifest table below giving each fitting a whole row of
//              description. Hovering a row lights its pin and vice versa.
//
// While a variant is up it owns the whole frame (the skill's rule: a variant may throw out
// the layout); drag-refit is inert (read-only prototype). The Current screen keeps every
// behaviour it has on main.

import "core:fmt"
import "core:math"
import ship "../core/ship"
import sim "../core/sim"
import rl "vendor:raylib"

Proto_Variant :: enum {
	Current,
	Hull_3D,
	Diagram,
	Manifest,
}

proto_variant: Proto_Variant = .Current

proto_variant_label :: proc(v: Proto_Variant) -> string {
	switch v {
	case .Current:
		return "Current — flat cutaway"
	case .Hull_3D:
		return "A — 3D hull + inspector"
	case .Diagram:
		return "B — labelled diagram"
	case .Manifest:
		return "C — profile + manifest"
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

// proto_lines is the one description formatter all three variants read, so "what a clearer
// description says" is a single edit: title, the spec line (size · phase · tags), the effect
// intent, and the material facts (weight, cargo, the berth and its visibility).
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
	case .Hull_3D:
		draw_proto_hull3d(state, mouse)
	case .Diagram:
		draw_proto_diagram(state, mouse)
	case .Manifest:
		draw_proto_manifest(state, mouse)
	}
}

// ---------------------------------------------------------------------------------------
// Variant A — true 3D ghost hull. Mostly side-on Camera3D; translucent hull cubes with
// solid wires so the belly slots read through the near side; name chips projected from the
// markers; the right-hand inspector carries the hovered (or first) fitting's whole story.
// ---------------------------------------------------------------------------------------

draw_proto_hull3d :: proc(state: ^Game_State, mouse: rl.Vector2) {
	rl.ClearBackground(COLOUR_DEEP)

	camera := rl.Camera3D {
		position   = rl.Vector3{4.4, 2.9, 9.0},
		target     = rl.Vector3{0, 1.5, 0},
		up         = rl.Vector3{0, 1, 0},
		fovy       = 42,
		projection = .PERSPECTIVE,
	}

	// World-space anchor per slot: exposed spread along the deck, concealed along the belly.
	n := min(len(state.player.layout), 8)
	exposed_total, concealed_total := 0, 0
	for i in 0 ..< n {
		if state.player.layout[i].slot.base_visibility == .Exposed {
			exposed_total += 1
		} else {
			concealed_total += 1
		}
	}
	anchors: [8]rl.Vector3
	ei, ci := 0, 0
	for i in 0 ..< n {
		ls := state.player.layout[i]
		if ls.slot.base_visibility == .Exposed {
			t := f32(ei + 1) / f32(exposed_total + 1)
			ei += 1
			anchors[i] = rl.Vector3{-4.2 + 8.4 * t, 2.35, 0}
		} else {
			t := f32(ci + 1) / f32(concealed_total + 1)
			ci += 1
			anchors[i] = rl.Vector3{-3.2 + 6.4 * t, 1.05, 0}
		}
	}

	// Project the anchors and hit-test their chips before drawing, so the 3D pass can tint
	// the hovered marker.
	chips: [8]rl.Rectangle
	screens: [8]rl.Vector2
	hovered := -1
	for i in 0 ..< n {
		p := rl.GetWorldToScreen(anchors[i], camera)
		screens[i] = p
		label := fmt.ctprintf("%s", proto_slot_title(state.player.layout[i]))
		w := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1).x
		above := state.player.layout[i].slot.base_visibility == .Exposed
		chip_y := above ? p.y - 64 - f32(i % 2) * 26 : p.y + 30 + f32(i % 2) * 26
		chips[i] = rl.Rectangle{x = p.x - w / 2 - 6, y = chip_y, width = w + 12, height = 22}
		if rl.CheckCollisionPointRec(mouse, chips[i]) {
			hovered = i
		}
	}

	rl.BeginMode3D(camera)

	// The sea, at the waterline.
	rl.DrawPlane(rl.Vector3{0, 0.55, 0}, rl.Vector2{60, 60}, rl.Fade(COLOUR_MID, 0.95))

	// Slot markers first, hull after: the hull's translucent faces write depth, so cubes
	// drawn later would be culled inside it — drawn first, the belly markers show through
	// the ghost hull as things behind glass (measured: the first cut lost all four).
	for i in 0 ..< n {
		ls := state.player.layout[i]
		s: f32
		switch ls.slot.size {
		case .Small:
			s = 0.44
		case .Medium:
			s = 0.58
		case .Large:
			s = 0.74
		}
		tint := COLOUR_STEEL
		if proto_slot_is_hold(ls) {
			tint = COLOUR_BLUE_RECESSIVE
		}
		if i == hovered {
			tint = COLOUR_CYAN
		}
		if _, filled := ls.fitting.?; filled {
			rl.DrawCube(anchors[i], s, s, s, rl.Fade(tint, 0.85))
		}
		rl.DrawCubeWires(anchors[i], s, s, s, tint)
	}

	// The ghost hull: main run, bow taper, sprit block, aftcastle, overlapped so the masses
	// read as one hull; the wires carry the shape.
	hull_fill := rl.Fade(COLOUR_SHALLOW, 0.38)
	wire := rl.Fade(COLOUR_STEEL, 0.75)
	rl.DrawCube(rl.Vector3{0, 1.0, 0}, 7.4, 1.9, 2.4, hull_fill)
	rl.DrawCubeWires(rl.Vector3{0, 1.0, 0}, 7.4, 1.9, 2.4, wire)
	rl.DrawCube(rl.Vector3{4.0, 1.1, 0}, 1.6, 1.7, 1.8, hull_fill)
	rl.DrawCubeWires(rl.Vector3{4.0, 1.1, 0}, 1.6, 1.7, 1.8, wire)
	rl.DrawCube(rl.Vector3{4.9, 1.25, 0}, 0.9, 1.3, 1.0, hull_fill)
	rl.DrawCubeWires(rl.Vector3{4.9, 1.25, 0}, 0.9, 1.3, 1.0, wire)
	rl.DrawCube(rl.Vector3{-3.9, 1.55, 0}, 1.3, 2.5, 2.1, hull_fill)
	rl.DrawCubeWires(rl.Vector3{-3.9, 1.55, 0}, 1.3, 2.5, 2.1, wire)

	// Deck plank at the exposed/concealed split — the waterline of ADR-0030's geography.
	rl.DrawCube(rl.Vector3{0, 1.98, 0}, 7.4, 0.08, 2.3, rl.Fade(COLOUR_STEEL, 0.25))

	// Masts and fore-and-aft sails (spanning x so they read from the side).
	rl.DrawCylinder(rl.Vector3{-1.5, 2.0, 0}, 0.06, 0.1, 3.6, 8, rl.Fade(COLOUR_STEEL, 0.9))
	rl.DrawCylinder(rl.Vector3{1.9, 2.0, 0}, 0.05, 0.09, 3.0, 8, rl.Fade(COLOUR_STEEL, 0.9))
	rl.DrawCube(rl.Vector3{-1.5, 4.5, 0}, 2.2, 1.6, 0.06, rl.Fade(COLOUR_CREAM, 0.16))
	rl.DrawCubeWires(rl.Vector3{-1.5, 4.5, 0}, 2.2, 1.6, 0.06, rl.Fade(COLOUR_CREAM, 0.4))
	rl.DrawCube(rl.Vector3{1.9, 4.1, 0}, 1.8, 1.3, 0.06, rl.Fade(COLOUR_CREAM, 0.16))
	rl.DrawCubeWires(rl.Vector3{1.9, 4.1, 0}, 1.8, 1.3, 0.06, rl.Fade(COLOUR_CREAM, 0.4))

	rl.EndMode3D()

	// Leaders and name chips, in screen space over the scene.
	for i in 0 ..< n {
		chip := chips[i]
		hot := i == hovered
		leader_end := rl.Vector2{chip.x + chip.width / 2, chip.y + (chip.y < screens[i].y ? chip.height : 0)}
		rl.DrawLineEx(screens[i], leader_end, 1, rl.Fade(hot ? COLOUR_CYAN : COLOUR_STEEL, 0.5))
		rl.DrawRectangleRec(chip, rl.Fade(COLOUR_GROUND, 0.85))
		rl.DrawRectangleLinesEx(chip, 1, hot ? COLOUR_CYAN : rl.Fade(COLOUR_STEEL, 0.7))
		name_tone := proto_slot_is_hold(state.player.layout[i]) ? rl.Fade(COLOUR_CREAM, 0.7) : COLOUR_CREAM
		rl.DrawTextEx(
			ui_font_body,
			fmt.ctprintf("%s", proto_slot_title(state.player.layout[i])),
			rl.Vector2{chip.x + 6, chip.y + 3},
			UI_BODY_SIZE,
			1,
			hot ? COLOUR_CYAN : name_tone,
		)
	}

	// The inspector: the hovered fitting's full description, or the first berth's while
	// nothing is hovered — the panel never sits empty.
	shown := hovered >= 0 ? hovered : 0
	panel := rl.Rectangle{x = WINDOW_WIDTH - 352, y = 64, width = 332, height = 168}
	rl.DrawRectangleRec(panel, rl.Fade(COLOUR_GROUND, 0.88))
	rl.DrawRectangleLinesEx(panel, 2, hovered >= 0 ? COLOUR_CYAN : COLOUR_BLUE_RECESSIVE)
	if n > 0 {
		title, spec, intent, extra := proto_lines(state.player.layout[shown])
		px := panel.x + 14
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", title), rl.Vector2{px, panel.y + 12}, UI_BODY_SIZE, 1, COLOUR_CREAM)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", spec), rl.Vector2{px, panel.y + 40}, UI_BODY_SIZE, 1, COLOUR_STEEL)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", intent), rl.Vector2{px, panel.y + 68}, UI_BODY_SIZE, 1, COLOUR_CYAN_DIM)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", extra), rl.Vector2{px, panel.y + 96}, UI_BODY_SIZE, 1, COLOUR_BLUE_RECESSIVE)
		rl.DrawTextEx(ui_font_body, "hover a name chip to inspect", rl.Vector2{px, panel.y + 136}, UI_BODY_SIZE, 1, rl.Fade(COLOUR_STEEL, 0.5))
	}

	draw_build_heading("At Anchor")
	draw_proto_stat_line(state, rl.Vector2{45, WINDOW_HEIGHT - 36})
}

// ---------------------------------------------------------------------------------------
// Variant B — labelled diagram. A large painted side elevation with an oblique deck plane
// for depth; every fitting's description always on screen in a callout box, leader-lined
// to its pin on the hull. Exposed callouts above the ship, concealed below.
// ---------------------------------------------------------------------------------------

draw_proto_diagram :: proc(state: ^Game_State, mouse: rl.Vector2) {
	rl.ClearBackground(COLOUR_DEEP)

	deck_y := f32(300)
	waterline_y := f32(420)
	keel_y := f32(496)
	x0 := f32(250) // stern
	x1 := f32(1010) // bow

	// Oblique deck plane: rows sliding right as they rise, a parallelogram of depth.
	OX :: f32(48)
	OY :: f32(22)
	for k in 0 ..< 11 {
		t := f32(k) / 10
		yy := deck_y - OY * (1 - t)
		shift := OX * (1 - t)
		rl.DrawRectangleRec(
			rl.Rectangle{x = x0 + shift + 20, y = yy, width = (x1 - 90) - (x0 + 20), height = 2.4},
			rl.Fade(COLOUR_SHALLOW, 0.5),
		)
	}
	// Far rail atop the oblique plane.
	rl.DrawLineEx(rl.Vector2{x0 + OX + 20, deck_y - OY}, rl.Vector2{x1 - 90 + OX, deck_y - OY}, 2, rl.Fade(COLOUR_STEEL, 0.5))

	// The hull: horizontal strips, stern nearly plumb, bow sweeping to a point.
	for yy := deck_y; yy < keel_y; yy += 2 {
		t := (yy - deck_y) / (keel_y - deck_y)
		stern_inset := 34 * t * t
		bow_inset := 130 * t * math.sqrt_f32(t)
		below := yy >= waterline_y
		tint := below ? rl.Fade(COLOUR_MID, 0.9) : rl.Fade(COLOUR_SHALLOW, 0.65)
		rl.DrawRectangleRec(rl.Rectangle{x = x0 + stern_inset, y = yy, width = (x1 - bow_inset) - (x0 + stern_inset), height = 2}, tint)
	}

	// Bulwark, aftcastle, bowsprit — enough superstructure to say "ship", quietly.
	rl.DrawRectangleRec(rl.Rectangle{x = x0, y = deck_y - 14, width = x1 - x0 - 30, height = 14}, rl.Fade(COLOUR_SHALLOW, 0.8))
	rl.DrawRectangleRec(rl.Rectangle{x = x0, y = deck_y - 60, width = 130, height = 46}, rl.Fade(COLOUR_SHALLOW, 0.7))
	rl.DrawRectangleLinesEx(rl.Rectangle{x = x0, y = deck_y - 60, width = 130, height = 46}, 1, rl.Fade(COLOUR_STEEL, 0.5))
	rl.DrawLineEx(rl.Vector2{x1 - 60, deck_y - 12}, rl.Vector2{x1 + 80, deck_y - 52}, 3, rl.Fade(COLOUR_STEEL, 0.7))

	// Masts and sails.
	masts := [3]f32{470, 690, 880}
	heights := [3]f32{180, 205, 150}
	for mx, mi in masts {
		rl.DrawLineEx(rl.Vector2{mx, deck_y - 12}, rl.Vector2{mx, deck_y - 12 - heights[mi]}, 3, rl.Fade(COLOUR_STEEL, 0.8))
		sail := rl.Rectangle{x = mx - 56, y = deck_y - 10 - heights[mi] + 18, width = 112, height = heights[mi] * 0.5}
		rl.DrawRectangleRec(sail, rl.Fade(COLOUR_CREAM, 0.12))
		rl.DrawRectangleLinesEx(sail, 1, rl.Fade(COLOUR_CREAM, 0.35))
	}

	// Waterline rule with ticks, the same language as the current cutaway.
	rl.DrawLineEx(rl.Vector2{60, waterline_y}, rl.Vector2{WINDOW_WIDTH - 60, waterline_y}, 2, rl.Fade(COLOUR_CYAN_DIM, 0.5))
	for x := f32(80); x < WINDOW_WIDTH - 80; x += 26 {
		rl.DrawLineEx(rl.Vector2{x, waterline_y}, rl.Vector2{x + 8, waterline_y + 4}, 1, rl.Fade(COLOUR_CYAN_DIM, 0.3))
	}

	// Pins and callouts. Exposed pins ride the deck, boxes fanned across the top; concealed
	// pins sit in the belly, boxes across the bottom.
	n := min(len(state.player.layout), 8)
	BOX_W :: f32(280)
	BOTTOM_W :: f32(258)
	BOX_H :: f32(100)
	// The bottom row leaves a centre gutter for Home's chart tab (a real ~180px control at
	// x 533–711 this prototype must live beside, not under); the top row spreads evenly.
	top_xs := [4]f32{16, 326, 636, 946}
	bottom_xs := [4]f32{4, 268, 714, 980}

	ei, ci := 0, 0
	for i in 0 ..< n {
		ls := state.player.layout[i]
		exposed := ls.slot.base_visibility == .Exposed
		pin: rl.Vector2
		box: rl.Rectangle
		if exposed {
			t := f32(ei + 1) / 5
			pin = rl.Vector2{x0 + 90 + (x1 - x0 - 220) * t, deck_y - 20}
			box = rl.Rectangle{x = top_xs[min(ei, 3)], y = 64, width = BOX_W, height = BOX_H}
			ei += 1
		} else {
			t := f32(ci + 1) / 5
			pin = rl.Vector2{x0 + 70 + (x1 - x0 - 260) * t, deck_y + 62}
			box = rl.Rectangle{x = bottom_xs[min(ci, 3)], y = 540, width = BOTTOM_W, height = BOX_H}
			ci += 1
		}

		hot := rl.CheckCollisionPointRec(mouse, box) || rl.CheckCollisionPointCircle(mouse, pin, 14)
		line_tone := rl.Fade(hot ? COLOUR_CYAN : COLOUR_STEEL, hot ? 0.9 : 0.4)
		anchor := rl.Vector2{box.x + box.width / 2, exposed ? box.y + box.height : box.y}
		rl.DrawLineEx(pin, anchor, 1, line_tone)

		is_hold := proto_slot_is_hold(ls)
		pin_tone := hot ? COLOUR_CYAN : (is_hold ? COLOUR_BLUE_RECESSIVE : COLOUR_STEEL)
		rl.DrawCircleV(pin, 6, pin_tone)
		rl.DrawCircleLines(i32(pin.x), i32(pin.y), 9, rl.Fade(pin_tone, 0.6))

		title, spec, intent, extra := proto_lines(ls)
		rl.DrawRectangleRec(box, rl.Fade(COLOUR_GROUND, 0.85))
		rl.DrawRectangleLinesEx(box, hot ? 2 : 1, hot ? COLOUR_CYAN : rl.Fade(COLOUR_STEEL, 0.55))
		bx := box.x + 10
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", title), rl.Vector2{bx, box.y + 8}, UI_BODY_SIZE, 1, COLOUR_CREAM)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", intent), rl.Vector2{bx, box.y + 30}, UI_BODY_SIZE, 1, COLOUR_CYAN_DIM)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", spec), rl.Vector2{bx, box.y + 52}, UI_BODY_SIZE, 1, COLOUR_STEEL)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", extra), rl.Vector2{bx, box.y + 74}, UI_BODY_SIZE, 1, COLOUR_BLUE_RECESSIVE)
	}

	draw_build_heading("At Anchor")
	draw_proto_stat_line(state, rl.Vector2{45, WINDOW_HEIGHT - 32})
}

// ---------------------------------------------------------------------------------------
// Variant C — profile + manifest. The ship large across the top as a side profile with a
// hinted stern face; numbered pins on every berth; below, a manifest table giving each
// fitting a full row. Hover links row and pin both ways.
// ---------------------------------------------------------------------------------------

draw_proto_manifest :: proc(state: ^Game_State, mouse: rl.Vector2) {
	rl.ClearBackground(COLOUR_DEEP)

	deck_y := f32(170)
	waterline_y := f32(268)
	keel_y := f32(330)
	x0 := f32(180)
	x1 := f32(1080)

	// Hull strips, as B but larger; a darker stern face hints the 3D turn of the quarter.
	for yy := deck_y; yy < keel_y; yy += 2 {
		t := (yy - deck_y) / (keel_y - deck_y)
		stern_inset := 30 * t * t
		bow_inset := 150 * t * math.sqrt_f32(t)
		below := yy >= waterline_y
		tint := below ? rl.Fade(COLOUR_MID, 0.9) : rl.Fade(COLOUR_SHALLOW, 0.65)
		rl.DrawRectangleRec(rl.Rectangle{x = x0 + stern_inset, y = yy, width = (x1 - bow_inset) - (x0 + stern_inset), height = 2}, tint)
	}
	// The stern face: a shaded band with a slight oblique top, the "mostly" in mostly-side.
	for yy := deck_y - 8; yy < waterline_y; yy += 2 {
		t := (yy - (deck_y - 8)) / (waterline_y - (deck_y - 8))
		w := 42 * (1 - 0.3 * t)
		rl.DrawRectangleRec(rl.Rectangle{x = x0 - w, y = yy, width = w, height = 2}, rl.Fade(COLOUR_MID, 0.95))
	}
	rl.DrawRectangleLinesEx(rl.Rectangle{x = x0 - 42, y = deck_y - 8, width = 42, height = waterline_y - deck_y + 8}, 1, rl.Fade(COLOUR_STEEL, 0.35))

	// Bulwark, aftcastle, bowsprit, masts.
	rl.DrawRectangleRec(rl.Rectangle{x = x0, y = deck_y - 12, width = x1 - x0 - 40, height = 12}, rl.Fade(COLOUR_SHALLOW, 0.8))
	rl.DrawRectangleRec(rl.Rectangle{x = x0, y = deck_y - 52, width = 150, height = 40}, rl.Fade(COLOUR_SHALLOW, 0.7))
	rl.DrawLineEx(rl.Vector2{x1 - 20, deck_y - 6}, rl.Vector2{x1 + 90, deck_y - 42}, 3, rl.Fade(COLOUR_STEEL, 0.7))
	masts := [2]f32{520, 810}
	heights := [2]f32{120, 105}
	for mx, mi in masts {
		rl.DrawLineEx(rl.Vector2{mx, deck_y - 10}, rl.Vector2{mx, deck_y - 10 - heights[mi]}, 3, rl.Fade(COLOUR_STEEL, 0.8))
		sail := rl.Rectangle{x = mx - 50, y = deck_y - 8 - heights[mi] + 12, width = 100, height = heights[mi] * 0.5}
		rl.DrawRectangleRec(sail, rl.Fade(COLOUR_CREAM, 0.12))
		rl.DrawRectangleLinesEx(sail, 1, rl.Fade(COLOUR_CREAM, 0.35))
	}
	rl.DrawLineEx(rl.Vector2{60, waterline_y}, rl.Vector2{WINDOW_WIDTH - 60, waterline_y}, 2, rl.Fade(COLOUR_CYAN_DIM, 0.5))

	// Pins and rows share hover, so resolve the manifest geometry first.
	n := min(len(state.player.layout), 8)
	// Rows end above Home's chart tab (y 604): 350 + 24 + 8×28 = 598.
	HEADER_Y :: f32(350)
	ROW_H :: f32(28)
	row_rect :: proc(i: int) -> rl.Rectangle {
		return rl.Rectangle{x = 30, y = HEADER_Y + 24 + f32(i) * ROW_H, width = WINDOW_WIDTH - 60, height = ROW_H}
	}

	pins: [8]rl.Vector2
	ei, ci := 0, 0
	for i in 0 ..< n {
		ls := state.player.layout[i]
		if ls.slot.base_visibility == .Exposed {
			t := f32(ei + 1) / 5
			pins[i] = rl.Vector2{x0 + 100 + (x1 - x0 - 260) * t, deck_y - 24}
			ei += 1
		} else {
			t := f32(ci + 1) / 5
			pins[i] = rl.Vector2{x0 + 80 + (x1 - x0 - 300) * t, deck_y + 48}
			ci += 1
		}
	}
	hovered := -1
	for i in 0 ..< n {
		if rl.CheckCollisionPointRec(mouse, row_rect(i)) || rl.CheckCollisionPointCircle(mouse, pins[i], 14) {
			hovered = i
		}
	}

	// Pins: numbered discs, cyan when their row (or they) are hovered.
	for i in 0 ..< n {
		hot := i == hovered
		is_hold := proto_slot_is_hold(state.player.layout[i])
		tone := hot ? COLOUR_CYAN : (is_hold ? COLOUR_BLUE_RECESSIVE : COLOUR_STEEL)
		rl.DrawCircleV(pins[i], 11, rl.Fade(COLOUR_GROUND, 0.9))
		rl.DrawCircleLines(i32(pins[i].x), i32(pins[i].y), 11, tone)
		num := fmt.ctprintf("%d", i + 1)
		nw := rl.MeasureTextEx(ui_font_body, num, UI_BODY_SIZE, 1).x
		rl.DrawTextEx(ui_font_body, num, rl.Vector2{pins[i].x - nw / 2, pins[i].y - 8}, UI_BODY_SIZE, 1, tone)
	}

	// The manifest. Header row, then one full-width row per berth: number, name, the whole
	// description in-line, and the material facts right-aligned.
	rl.DrawTextEx(ui_font_body, "#", rl.Vector2{44, HEADER_Y}, UI_BODY_SIZE, 1, rl.Fade(COLOUR_STEEL, 0.7))
	rl.DrawTextEx(ui_font_body, "FITTING", rl.Vector2{80, HEADER_Y}, UI_BODY_SIZE, 1, rl.Fade(COLOUR_STEEL, 0.7))
	rl.DrawTextEx(ui_font_body, "WHAT IT DOES", rl.Vector2{330, HEADER_Y}, UI_BODY_SIZE, 1, rl.Fade(COLOUR_STEEL, 0.7))
	rl.DrawTextEx(ui_font_body, "BERTH / LOAD", rl.Vector2{930, HEADER_Y}, UI_BODY_SIZE, 1, rl.Fade(COLOUR_STEEL, 0.7))
	rl.DrawLineEx(rl.Vector2{30, HEADER_Y + 20}, rl.Vector2{WINDOW_WIDTH - 30, HEADER_Y + 20}, 1, rl.Fade(COLOUR_STEEL, 0.4))

	for i in 0 ..< n {
		ls := state.player.layout[i]
		rect := row_rect(i)
		hot := i == hovered
		if hot {
			rl.DrawRectangleRec(rect, rl.Fade(COLOUR_CYAN, 0.08))
			rl.DrawRectangleRec(rl.Rectangle{x = rect.x, y = rect.y, width = 3, height = rect.height}, COLOUR_CYAN)
		} else if i % 2 == 1 {
			rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, 0.4))
		}

		title, spec, intent, extra := proto_lines(ls)
		_ = extra
		is_hold := proto_slot_is_hold(ls)
		ty := rect.y + (ROW_H - UI_BODY_SIZE) / 2
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%d", i + 1), rl.Vector2{44, ty}, UI_BODY_SIZE, 1, COLOUR_BLUE_RECESSIVE)
		name_tone := is_hold ? rl.Fade(COLOUR_CREAM, 0.7) : COLOUR_CREAM
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", title), rl.Vector2{80, ty}, UI_BODY_SIZE, 1, hot ? COLOUR_CYAN : name_tone)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s — %s", intent, spec), rl.Vector2{330, ty}, UI_BODY_SIZE, 1, COLOUR_STEEL)

		load: string
		if fitting, filled := ls.fitting.?; filled {
			load = fmt.tprintf("%s · wt %d · %d/%d", ls.slot.name, fitting.weight, fitting.cargo_held, ship.ship_fitting_capacity(fitting))
		} else {
			load = fmt.tprintf("%s · empty", ls.slot.name)
		}
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", load), rl.Vector2{930, ty}, UI_BODY_SIZE, 1, COLOUR_BLUE_RECESSIVE)
	}

	draw_build_heading("At Anchor")
	draw_proto_stat_line(state, rl.Vector2{45, BUILD_HEADING_Y + 28})
}

// draw_proto_stat_line prints the shared derived stat line where each variant asks for it.
draw_proto_stat_line :: proc(state: ^Game_State, pos: rl.Vector2) {
	rl.DrawTextEx(
		ui_font_body,
		fmt.ctprintf("%s", ship_stat_line(s = &state.player, weight = true)),
		pos,
		UI_BODY_SIZE,
		1,
		COLOUR_STEEL,
	)
}

// capture_shot_ship_prototypes photographs the three variants the same way capture_shot_home
// shoots Home: a throwaway Sim ticked once into a fresh Game_State, one shot per variant,
// the global put back to Current on the way out. Prototype-only, removed with this file.
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
	}{{.Hull_3D, "proto-a-hull3d"}, {.Diagram, "proto-b-diagram"}, {.Manifest, "proto-c-manifest"}}

	for shot in shots {
		proto_variant = shot.variant
		draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0)
		draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0)
		capture_write(state, shot.label)
	}
	proto_variant = .Current
}
