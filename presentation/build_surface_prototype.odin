#+private
package presentation

// PROTOTYPE — THROWAWAY. Branch worktree-prototype-ship-side-view; never merges to main.
//
// Round 2. Round 1 put three layouts up (3D ghost hull + inspector / labelled diagram /
// profile + manifest — history: 6f583bb); the verdict picked A's shape: the ship large,
// name chips pinned on it, a docked inspector carrying the hovered fitting's full story.
//
// Question now under test: that layout on the NEW style guide (docs/ui/style-guide.md —
// bright, saturated, warm-vs-cool; sea #1FA9D0 as the field, parchment #EBD9A6 wherever
// words sit) instead of the shipped navy constants — and what the ship itself should be.
// The variants are now *ship art styles* on that one bright scene:
//
//   Current    — today's flat navy cutaway, untouched, as the baseline to flip against.
//   A1         — the ship drawn in-engine with raylib primitives from the new roster
//                (no assets; the ADR-0009-clean option).
//   A2–A5      — generated pixel-art ship sprites (PixelLab), one per style register:
//                classic 16-bit / chunky 8-bit / painterly lineless / 3/4 view.
//                Sprites live in docs/ui/proto-art/ and load lazily; a missing file
//                draws a note instead of crashing.
//
// The new-roster colours are PROTO_* locals here on purpose: the style guide explicitly
// leaves the shipped COLOUR_* constants navy until the real migration, and a throwaway
// file must not front-run that.

import "core:fmt"
import "core:math"
import ship "../core/ship"
import sim "../core/sim"
import rl "vendor:raylib"

// --- The new roster (style-guide values, prototype-local) --------------------------------

PROTO_SEA :: rl.Color{31, 169, 208, 255} // sea — field
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
	Bright_Engine,
	Pixel_16bit,
	Pixel_Chunky,
	Pixel_Painterly,
	Pixel_34,
}

proto_variant: Proto_Variant = .Current

proto_variant_label :: proc(v: Proto_Variant) -> string {
	switch v {
	case .Current:
		return "Current — navy cutaway"
	case .Bright_Engine:
		return "A1 — engine-drawn ship"
	case .Pixel_16bit:
		return "A2 — pixel: 16-bit"
	case .Pixel_Chunky:
		return "A3 — pixel: chunky 8-bit"
	case .Pixel_Painterly:
		return "A4 — pixel: painterly"
	case .Pixel_34:
		return "A5 — pixel: 3/4 view"
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

// proto_lines is the one description formatter every variant reads, so "what a clearer
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

// --- Sprite loading ----------------------------------------------------------------------

Proto_Ship_Art :: enum {
	Bit16,
	Chunky,
	Painterly,
	ThreeQuarter,
}

proto_art_paths := [Proto_Ship_Art]cstring {
	.Bit16        = "docs/ui/proto-art/ship-16bit.png",
	.Chunky       = "docs/ui/proto-art/ship-chunky.png",
	.Painterly    = "docs/ui/proto-art/ship-painterly.png",
	.ThreeQuarter = "docs/ui/proto-art/ship-34view.png",
}

proto_art_tex: [Proto_Ship_Art]rl.Texture2D
proto_art_tried: [Proto_Ship_Art]bool

// proto_art_texture lazy-loads a sprite the first time its variant is shown. id 0 means
// the file was missing; the variant then draws a note instead. POINT filter keeps the
// pixels square under the 2x scale.
proto_art_texture :: proc(a: Proto_Ship_Art) -> rl.Texture2D {
	if !proto_art_tried[a] {
		proto_art_tried[a] = true
		tex := rl.LoadTexture(proto_art_paths[a])
		if tex.id != 0 {
			rl.SetTextureFilter(tex, .POINT)
		}
		proto_art_tex[a] = tex
	}
	return proto_art_tex[a]
}

draw_ship_prototype :: proc(state: ^Game_State, mouse: rl.Vector2) {
	switch proto_variant {
	case .Current:
	// unreachable — the hook only enters on a non-Current variant
	case .Bright_Engine:
		draw_proto_bright(state, mouse, nil)
	case .Pixel_16bit:
		draw_proto_bright(state, mouse, Proto_Ship_Art.Bit16)
	case .Pixel_Chunky:
		draw_proto_bright(state, mouse, Proto_Ship_Art.Chunky)
	case .Pixel_Painterly:
		draw_proto_bright(state, mouse, Proto_Ship_Art.Painterly)
	case .Pixel_34:
		draw_proto_bright(state, mouse, Proto_Ship_Art.ThreeQuarter)
	}
}

// --- The one bright scene ----------------------------------------------------------------
// Sky over sea, the ship large on the left, name chips pinned to its berths, and the
// parchment inspector on the right. Every variant shares it; only the ship differs.

// Where the ship lives. Sprites are 368x256 drawn at 2x; the engine ship paints the same
// rectangle so the chips land in the same places on every variant.
PROTO_SHIP :: rl.Rectangle{x = 70, y = 96, width = 736, height = 512}
PROTO_HORIZON :: f32(330)
PROTO_WATERLINE :: f32(578) // where the hull meets the sea; the cover band starts here

draw_proto_bright :: proc(state: ^Game_State, mouse: rl.Vector2, art: Maybe(Proto_Ship_Art)) {
	// Sky: three flat bands and blocky clouds — hard edges, no gradients, per the guide's
	// 16-bit register.
	rl.ClearBackground(PROTO_SKY_HIGH)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = 120, width = WINDOW_WIDTH, height = 110}, PROTO_SKY)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = 230, width = WINDOW_WIDTH, height = PROTO_HORIZON - 230}, PROTO_HAZE)
	draw_proto_cloud(150, 120)
	draw_proto_cloud(700, 70)
	draw_proto_cloud(1080, 170)

	// Sea: a deep band at the horizon for distance, the field below, foam on the line.
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_HORIZON, width = WINDOW_WIDTH, height = 30}, PROTO_SEA_DEEP)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_HORIZON + 30, width = WINDOW_WIDTH, height = WINDOW_HEIGHT - PROTO_HORIZON - 30}, PROTO_SEA)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_HORIZON, width = WINDOW_WIDTH, height = 2}, PROTO_FOAM)

	// Sparkle: fixed pseudo-random dashes of the brighter sea tones.
	for i in 0 ..< 70 {
		sx := f32((i * 211) % 1160) + 40
		sy := PROTO_HORIZON + 44 + f32((i * 137) % 290)
		tone := i % 3 == 0 ? PROTO_SHALLOW : PROTO_SEA_BRIGHT
		rl.DrawRectangleRec(rl.Rectangle{x = sx, y = sy, width = 24, height = 3}, rl.Fade(tone, 0.55))
	}

	// The ship.
	missing_art := false
	if a, is_sprite := art.?; is_sprite {
		tex := proto_art_texture(a)
		if tex.id != 0 {
			rl.DrawTextureEx(tex, rl.Vector2{PROTO_SHIP.x, PROTO_SHIP.y}, 0, 2, rl.WHITE)
		} else {
			missing_art = true
		}
	} else {
		draw_proto_engine_ship()
	}

	// The water the hull sits in: an opaque band over the keel, foam at the contact line.
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_WATERLINE, width = WINDOW_WIDTH, height = WINDOW_HEIGHT - PROTO_WATERLINE}, PROTO_SEA)
	for i in 0 ..< 26 {
		fx := PROTO_SHIP.x - 20 + f32(i) * 32
		rl.DrawRectangleRec(rl.Rectangle{x = fx, y = PROTO_WATERLINE - 2, width = 20, height = 4}, rl.Fade(PROTO_FOAM, i % 2 == 0 ? 0.9 : 0.5))
	}
	for i in 0 ..< 18 {
		sx := f32((i * 257) % 1160) + 40
		sy := PROTO_WATERLINE + 24 + f32((i * 149) % 70)
		rl.DrawRectangleRec(rl.Rectangle{x = sx, y = sy, width = 24, height = 3}, rl.Fade(PROTO_SEA_BRIGHT, 0.55))
	}

	if missing_art {
		note := rl.Rectangle{x = PROTO_SHIP.x + 120, y = PROTO_SHIP.y + 180, width = 480, height = 60}
		rl.DrawRectangleRec(note, PROTO_PARCHMENT)
		rl.DrawRectangleLinesEx(note, 2, PROTO_CLIFF)
		if a, is_sprite := art.?; is_sprite {
			rl.DrawTextEx(ui_font_body, fmt.ctprintf("art not on disk yet: %s", proto_art_paths[a]), rl.Vector2{note.x + 14, note.y + 20}, UI_BODY_SIZE, 1, PROTO_INK)
		}
	}

	draw_proto_chips_and_inspector(state, mouse)

	draw_build_heading("At Anchor")

	// Stat line on a parchment strip — words live on parchment, even short ones.
	stat := fmt.ctprintf("%s", ship_stat_line(s = &state.player, weight = true))
	sw := rl.MeasureTextEx(ui_font_body, stat, UI_BODY_SIZE, 1).x
	strip := rl.Rectangle{x = 38, y = WINDOW_HEIGHT - 42, width = sw + 20, height = 26}
	rl.DrawRectangleRec(strip, rl.Fade(PROTO_PARCHMENT, 0.92))
	rl.DrawRectangleLinesEx(strip, 2, PROTO_CLIFF)
	rl.DrawTextEx(ui_font_body, stat, rl.Vector2{strip.x + 10, strip.y + 5}, UI_BODY_SIZE, 1, PROTO_INK)
}

// draw_proto_cloud stacks three blocky rects — a pixel cloud, no curves.
draw_proto_cloud :: proc(cx, cy: f32) {
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 70, y = cy + 14, width = 150, height = 22}, PROTO_CLOUD_SHADOW)
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 60, y = cy, width = 120, height = 24}, PROTO_CLOUD)
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 28, y = cy - 14, width = 62, height = 18}, PROTO_CLOUD)
}

// --- Chips + inspector (shared by all bright variants) -----------------------------------

// Berth anchors as fractions of PROTO_SHIP: exposed along the deck line, concealed low in
// the hull. Fractions, so swapping the sprite never moves the chips.
proto_anchor :: proc(exposed: bool, t: f32) -> rl.Vector2 {
	if exposed {
		return rl.Vector2{PROTO_SHIP.x + PROTO_SHIP.width * (0.16 + 0.66 * t), PROTO_SHIP.y + PROTO_SHIP.height * 0.55}
	}
	return rl.Vector2{PROTO_SHIP.x + PROTO_SHIP.width * (0.24 + 0.52 * t), PROTO_SHIP.y + PROTO_SHIP.height * 0.79}
}

draw_proto_chips_and_inspector :: proc(state: ^Game_State, mouse: rl.Vector2) {
	n := min(len(state.player.layout), 8)

	anchors: [8]rl.Vector2
	chips: [8]rl.Rectangle
	hovered := -1
	ei, ci := 0, 0
	exposed_total, concealed_total := 0, 0
	for i in 0 ..< n {
		if state.player.layout[i].slot.base_visibility == .Exposed {
			exposed_total += 1
		} else {
			concealed_total += 1
		}
	}
	for i in 0 ..< n {
		ls := state.player.layout[i]
		exposed := ls.slot.base_visibility == .Exposed
		t: f32
		if exposed {
			t = f32(ei) / f32(max(exposed_total - 1, 1))
			ei += 1
		} else {
			t = f32(ci) / f32(max(concealed_total - 1, 1))
			ci += 1
		}
		anchors[i] = proto_anchor(exposed, t)

		label := fmt.ctprintf("%s", proto_slot_title(ls))
		w := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1).x
		chip_y := exposed ? anchors[i].y - 190 - f32(i % 2) * 30 : anchors[i].y + 96 + f32(i % 2) * 30
		chips[i] = rl.Rectangle{x = anchors[i].x - w / 2 - 8, y = chip_y, width = w + 16, height = 24}
		if rl.CheckCollisionPointRec(mouse, chips[i]) {
			hovered = i
		}
	}

	// Leaders, pins, chips. Chips are parchment — words live on parchment.
	for i in 0 ..< n {
		chip := chips[i]
		hot := i == hovered
		leader_end := rl.Vector2{chip.x + chip.width / 2, chip.y + (chip.y < anchors[i].y ? chip.height : 0)}
		rl.DrawLineEx(anchors[i], leader_end, hot ? 2 : 1, hot ? PROTO_FOAM : rl.Fade(PROTO_INK, 0.55))

		is_hold := proto_slot_is_hold(state.player.layout[i])
		pin_tone := hot ? PROTO_FOAM : (is_hold ? PROTO_SEA_DEEP : PROTO_INK)
		rl.DrawCircleV(anchors[i], 5, pin_tone)
		rl.DrawCircleLines(i32(anchors[i].x), i32(anchors[i].y), 8, rl.Fade(pin_tone, 0.7))

		rl.DrawRectangleRec(chip, rl.Fade(PROTO_PARCHMENT, hot ? 1.0 : 0.92))
		rl.DrawRectangleLinesEx(chip, hot ? 2 : 1, hot ? PROTO_SEA_DEEP : PROTO_CLIFF)
		name_tone := is_hold ? PROTO_INK_MUTED : PROTO_INK
		rl.DrawTextEx(
			ui_font_body,
			fmt.ctprintf("%s", proto_slot_title(state.player.layout[i])),
			rl.Vector2{chip.x + 8, chip.y + 4},
			UI_BODY_SIZE,
			1,
			name_tone,
		)
	}

	// The inspector: parchment panel, ink hierarchy — the hovered fitting's full story, or
	// the first berth's while nothing is hovered, so it never sits empty.
	shown := hovered >= 0 ? hovered : 0
	panel := rl.Rectangle{x = WINDOW_WIDTH - 342, y = 64, width = 322, height = 186}
	rl.DrawRectangleRec(panel, rl.Fade(PROTO_PARCHMENT, 0.96))
	rl.DrawRectangleLinesEx(panel, 2, hovered >= 0 ? PROTO_SEA_DEEP : PROTO_CLIFF)
	if n > 0 {
		title, spec, intent, extra := proto_lines(state.player.layout[shown])
		px := panel.x + 14
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", title), rl.Vector2{px, panel.y + 12}, UI_BODY_SIZE, 1, PROTO_INK)
		rl.DrawRectangleRec(rl.Rectangle{x = px, y = panel.y + 34, width = panel.width - 28, height = 2}, PROTO_SAND)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", intent), rl.Vector2{px, panel.y + 46}, UI_BODY_SIZE, 1, PROTO_INK)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", spec), rl.Vector2{px, panel.y + 74}, UI_BODY_SIZE, 1, PROTO_INK_MUTED)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", extra), rl.Vector2{px, panel.y + 102}, UI_BODY_SIZE, 1, PROTO_INK_MUTED)
		rl.DrawTextEx(ui_font_body, "hover a name chip to inspect", rl.Vector2{px, panel.y + 154}, UI_BODY_SIZE, 1, PROTO_INK_FADED)
	}
}

// --- A1: the engine-drawn ship -----------------------------------------------------------
// The no-assets option: hull, castle, masts, and sails from raylib primitives in the new
// roster's warm column, painted into the same PROTO_SHIP rectangle the sprites occupy.

draw_proto_engine_ship :: proc() {
	deck_y := PROTO_SHIP.y + PROTO_SHIP.height * 0.52 // ~362
	x0 := PROTO_SHIP.x + 30 // stern
	x1 := PROTO_SHIP.x + PROTO_SHIP.width - 30 // bow

	// Hull: horizontal strips from deck to waterline, stern nearly plumb, bow sweeping in.
	// Cliff body with sand plank highlights every fourth strip — flat blocks, no gradients.
	for yy := deck_y; yy < PROTO_WATERLINE + 20; yy += 4 {
		t := (yy - deck_y) / (PROTO_WATERLINE + 20 - deck_y)
		stern_inset := 26 * t * t
		bow_inset := 120 * t * math.sqrt_f32(t)
		tone := PROTO_CLIFF
		if int(yy - deck_y) % 16 < 4 {
			tone = PROTO_SAND
		}
		rl.DrawRectangleRec(rl.Rectangle{x = x0 + stern_inset, y = yy, width = (x1 - bow_inset) - (x0 + stern_inset), height = 4}, tone)
	}
	// A rock shadow line under the bulwark, and the keel shadow at the water.
	rl.DrawRectangleRec(rl.Rectangle{x = x0, y = deck_y, width = x1 - x0, height = 3}, PROTO_ROCK)

	// Bulwark and the stern castle.
	rl.DrawRectangleRec(rl.Rectangle{x = x0 - 6, y = deck_y - 16, width = x1 - x0 - 60, height = 16}, PROTO_SAND)
	rl.DrawRectangleRec(rl.Rectangle{x = x0 - 6, y = deck_y - 16, width = x1 - x0 - 60, height = 3}, PROTO_ROCK)
	rl.DrawRectangleRec(rl.Rectangle{x = x0 - 10, y = deck_y - 66, width = 132, height = 50}, PROTO_CLIFF)
	rl.DrawRectangleRec(rl.Rectangle{x = x0 - 10, y = deck_y - 66, width = 132, height = 8}, PROTO_SAND)
	rl.DrawRectangleLinesEx(rl.Rectangle{x = x0 - 10, y = deck_y - 66, width = 132, height = 50}, 2, PROTO_ROCK)
	// Two castle windows.
	rl.DrawRectangleRec(rl.Rectangle{x = x0 + 18, y = deck_y - 48, width = 18, height = 18}, PROTO_SEA_DEEP)
	rl.DrawRectangleRec(rl.Rectangle{x = x0 + 62, y = deck_y - 48, width = 18, height = 18}, PROTO_SEA_DEEP)

	// Bowsprit.
	rl.DrawLineEx(rl.Vector2{x1 - 40, deck_y - 8}, rl.Vector2{x1 + 60, deck_y - 52}, 5, PROTO_TRUNK)

	// Masts and square-rigged cream sails; trunk timber, rock caps.
	masts := [2]f32{PROTO_SHIP.x + 250, PROTO_SHIP.x + 480}
	heights := [2]f32{250, 215}
	for mx, mi in masts {
		top := deck_y - 16 - heights[mi]
		rl.DrawRectangleRec(rl.Rectangle{x = mx - 3, y = top, width = 6, height = heights[mi]}, PROTO_TRUNK)
		sail := rl.Rectangle{x = mx - 78, y = top + 24, width = 156, height = heights[mi] * 0.62}
		rl.DrawRectangleRec(sail, PROTO_CREAM)
		rl.DrawRectangleRec(rl.Rectangle{x = sail.x, y = sail.y + sail.height - 10, width = sail.width, height = 10}, PROTO_CLOUD_SHADOW)
		rl.DrawRectangleLinesEx(sail, 2, PROTO_SAND)
		// Yard.
		rl.DrawRectangleRec(rl.Rectangle{x = mx - 84, y = top + 18, width = 168, height = 5}, PROTO_TRUNK)
	}
}

// capture_shot_ship_prototypes photographs every bright variant the way capture_shot_home
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

	shots := [5]struct {
		variant: Proto_Variant,
		label:   string,
	} {
		{.Bright_Engine, "proto-a1-engine"},
		{.Pixel_16bit, "proto-a2-16bit"},
		{.Pixel_Chunky, "proto-a3-chunky"},
		{.Pixel_Painterly, "proto-a4-painterly"},
		{.Pixel_34, "proto-a5-34view"},
	}

	for shot in shots {
		proto_variant = shot.variant
		draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0)
		draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0)
		capture_write(state, shot.label)
	}
	proto_variant = .Current
}
