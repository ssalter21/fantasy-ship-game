package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

// The Chart Table is the one screen above a voyage (#278): a title, Begin a voyage,
// Quit, and nothing else. The exe boots into it, and it is stateless — a voyage draws
// its own ending, then hands back to a Chart Table unchanged from boot, so nothing
// here reads or holds voyage state.

// Chart_Table_Choice is what the Chart Table answers main with: the button the player
// clicked. A close is not one of these — window_quit_if_closed ends the process rather
// than returning a choice — so both values here mean a deliberate click. Quit is the zero
// value so that the answer you get by default is the one that stops.
Chart_Table_Choice :: enum {
	Quit,
	Begin,
}

// Layout, from docs/ui/style-guide.md's proportions table (measured off the mock and
// scaled to this window). The stack's vertical origin is not in that table — the mock
// stacks four items where the Chart Table has two, so its origin doesn't transfer — and
// is set here to centre the stack in the space the title leaves.
CHART_TABLE_BUTTON_W :: 356
CHART_TABLE_BUTTON_H :: 45
CHART_TABLE_BUTTON_PITCH :: 64
CHART_TABLE_BUTTON_Y0 :: 360
CHART_TABLE_TITLE_CENTRE_Y :: 115

// The title is letterspaced rather than enlarged: the guide fixes 40px as the display
// size, so `spacing` is the only knob left for the mock's wide, airy title. 8 lands the
// rendered title on the mock's title-to-window-width ratio (~43%).
CHART_TABLE_TITLE :: "Fantasy Ship Game"
CHART_TABLE_TITLE_SPACING :: 8

// The label sits left of centre inside a centred box, with the caret in the margin the
// inset leaves. A centred label in a centred box gives the eye no edge to run down.
CHART_TABLE_LABEL_INSET :: 44

Chart_Table_Button :: struct {
	rect:   rl.Rectangle,
	label:  string,
	choice: Chart_Table_Choice,
}

// chart_table_buttons lays the stack out as a pure function of the constants, so
// rendering and hit-testing each ask for it rather than sharing a local — the same
// split build_slot_rects uses, and what lets capture draw a screen it never clicks.
chart_table_buttons :: proc() -> [2]Chart_Table_Button {
	buttons := [2]Chart_Table_Button {
		{label = "Begin a voyage", choice = .Begin},
		{label = "Quit", choice = .Quit},
	}
	for &b, i in buttons {
		b.rect = rl.Rectangle {
			x      = (WINDOW_WIDTH - CHART_TABLE_BUTTON_W) / 2,
			y      = CHART_TABLE_BUTTON_Y0 + f32(i * CHART_TABLE_BUTTON_PITCH),
			width  = CHART_TABLE_BUTTON_W,
			height = CHART_TABLE_BUTTON_H,
		}
	}
	return buttons
}

// chart_table_loop is the blocking modal render loop above run_session (ADR-0022):
// same technique as play_beat and the *_menu_loop family, but in main rather than
// inside a run_session callback, because no Sim exists while this screen is up.
chart_table_loop :: proc() -> Chart_Table_Choice {
	if !rl.IsWindowReady() {
		return .Quit
	}
	buttons := chart_table_buttons()

	for {
		window_quit_if_closed()
		hovered := chart_table_hovered(buttons[:])
		draw_chart_table(hovered)

		if hovered >= 0 && rl.IsMouseButtonPressed(.LEFT) {
			return buttons[hovered].choice
		}
	}
}

// chart_table_hovered returns the index of the button under the mouse, or -1.
chart_table_hovered :: proc(buttons: []Chart_Table_Button) -> int {
	mouse := rl.GetMousePosition()
	for b, i in buttons {
		if rl.CheckCollisionPointRec(mouse, b.rect) {
			return i
		}
	}
	return -1
}

// draw_chart_table draws one whole frame. It is split from chart_table_loop so that
// composing the screen and waiting for a click are separate acts — the loop draws then
// polls, capture draws and never polls (ADR-0022, #277). `hovered` is the button index
// to mark, or -1 for none, which is what capture passes.
draw_chart_table :: proc(hovered: int) {
	buttons := chart_table_buttons()

	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	draw_chart_table_ground()

	title := fmt.ctprint(CHART_TABLE_TITLE)
	size := rl.MeasureTextEx(ui_font_title, title, UI_TITLE_SIZE, CHART_TABLE_TITLE_SPACING)
	origin := rl.Vector2{(WINDOW_WIDTH - size.x) / 2, CHART_TABLE_TITLE_CENTRE_Y - size.y / 2}
	rl.DrawTextEx(ui_font_title, title, origin, UI_TITLE_SIZE, CHART_TABLE_TITLE_SPACING, COLOUR_CREAM)

	for b, i in buttons {
		draw_chart_table_button(b, i == hovered)
	}

	draw_vignette()
	draw_chart_table_version_stamp()
}

// The chart's tones, measured off menu-ui-mock.png's own chart rather than invented.
// Land is khaki with an inland green, not parchment: treasure-map.jpg's parchment is
// 9.67% strongly-warm against 0.2-2.7% for every other reference, and the amber rule
// works only because warm is scarce (#294). A cream title and an amber button cannot
// sit on cream.
CHART_LAND :: rl.Color{83, 80, 73, 255} // the mock's island body, #535049
CHART_LAND_SHADE :: rl.Color{73, 67, 55, 255} // its shadowed edge, #494337
CHART_LAND_GREEN :: rl.Color{35, 65, 44, 255} // its inland green, #23412C
CHART_GRID :: rl.Color{77, 88, 99, 255} // the mock's grid, #4D5863 — H210, already on the ramp
CHART_MARK :: rl.Color{178, 72, 43, 255} // the mock's X, #B2482B
// CHART_INK is the chart's own linework — the rose, the route. Opaque and quiet on
// purpose. The world must never outshine the chrome (the guide's rule for zone tints
// is the same rule), and a translucent tone cannot enforce that: alpha composites
// per-draw, so eight Fade(CREAM, 0.7) spokes crossing at a hub stack to near-opaque
// cream. The first attempt peaked at luminance 209 against the title's 185 — the
// background was the brightest thing on the screen. An opaque dim tone is the only
// one whose peak you can predict from the constant. H215, so it is on the ramp.
CHART_INK :: rl.Color{110, 130, 160, 255}

// Chart_Lobe is one blob of land. An island is several overlapping lobes: DrawPoly
// draws a *regular* polygon, which alone reads as a gem rather than a coastline, so
// the irregularity has to come from the overlap.
//
// `green` scales the inland patch (0 = bare sand). `sides` low and `rot` arbitrary is
// what keeps the edges hard and faceted — the reference set's 16-bit register.
Chart_Lobe :: struct {
	centre: rl.Vector2,
	radius: f32,
	sides:  i32,
	rot:    f32,
	green:  f32,
}

// A fixed table, not anything generated. Capture photographs this screen at frame 0
// (#278), so the chart has to be identical on every run or every screenshot diff is
// noise. Laid out to leave the title band (y<160) and the hint row clear, and to put
// coastline behind the button stack the way the mock does — the scrim is what lets it
// read through.
CHART_LOBES :: [?]Chart_Lobe {
	{{120, 205}, 70, 7, 12, 0.55},
	{{178, 248}, 46, 6, 40, 0.50},
	{{878, 190}, 84, 8, 30, 0.60},
	{{812, 246}, 52, 7, 10, 0.45},
	{{470, 345}, 118, 9, 18, 0.50},
	{{562, 302}, 78, 7, 50, 0.55},
	{{398, 398}, 62, 6, 25, 0.00},
	{{165, 556}, 74, 7, 55, 0.50},
	{{224, 606}, 48, 6, 15, 0.45},
	{{888, 556}, 90, 8, 22, 0.55},
	{{820, 610}, 52, 7, 45, 0.00},
	{{618, 636}, 54, 6, 8, 0.50},
}

CHART_HALO :: 13 // how far the shallows reach past the sand
CHART_GRID_PITCH :: 64

// draw_chart_table_ground draws the chart this screen is named for.
//
// #278 settled that the Chart Table *is* a chart with buttons over it, and #294 settled
// that the chart is drawn rather than sourced: raylib primitives out of the palette,
// which costs no bytes in the exe (ADR-0009), is self-authored so no licence question
// arises, and — the point — cannot clash with the chrome, because the chrome's ground
// and the chart's deep water are one ramp stop, not two. This is what makes it a
// placeholder only in ambition: #284's parchment raster would still be an improvement
// in *depiction*, but not in *palette*.
//
// The ramp is drawn as depth: deep field, open water above it, shallows hugging the
// land.
draw_chart_table_ground :: proc() {
	rl.ClearBackground(COLOUR_DEEP)
	rl.DrawRectangleGradientV(
		0,
		WINDOW_HEIGHT / 3,
		WINDOW_WIDTH,
		WINDOW_HEIGHT * 2 / 3,
		COLOUR_DEEP,
		COLOUR_MID,
	)
	draw_chart_grid()

	lobes := CHART_LOBES

	// Three passes over every lobe, not three per lobe: a halo drawn after a
	// neighbour's sand would cut into it.
	for l in lobes {
		rl.DrawPoly(l.centre, l.sides, l.radius + CHART_HALO, l.rot, COLOUR_SHALLOW)
	}
	for l in lobes {
		rl.DrawPoly(l.centre, l.sides, l.radius + 3, l.rot, CHART_LAND_SHADE)
		rl.DrawPoly(l.centre, l.sides, l.radius, l.rot, CHART_LAND)
	}
	for l in lobes {
		if l.green <= 0 {
			continue
		}
		rl.DrawPoly(l.centre, l.sides, l.radius * l.green, l.rot + 20, CHART_LAND_GREEN)
	}

	draw_chart_route()
	// In open water, left of the button stack, the way the mock puts its rose in open
	// water left of the title. The first placement sat it on an island, where a chart
	// would never put one.
	draw_chart_compass(rl.Vector2{195, 385}, 44)
}

// draw_chart_grid draws the chart's graticule. Faded hard, because it is the quietest
// thing on the screen: the guide ranks the version stamp last of what must be *read*,
// and this sits below even that.
draw_chart_grid :: proc() {
	for x := f32(CHART_GRID_PITCH); x < WINDOW_WIDTH; x += CHART_GRID_PITCH {
		rl.DrawLineV(rl.Vector2{x, 0}, rl.Vector2{x, WINDOW_HEIGHT}, rl.Fade(CHART_GRID, 0.22))
	}
	for y := f32(CHART_GRID_PITCH); y < WINDOW_HEIGHT; y += CHART_GRID_PITCH {
		rl.DrawLineV(rl.Vector2{0, y}, rl.Vector2{WINDOW_WIDTH, y}, rl.Fade(CHART_GRID, 0.22))
	}
}

// The dashed route and its X, the one thing on the chart that says "treasure map"
// rather than "sea chart". Dashes are drawn rather than stippled — raylib has no dash
// pattern — and the X is two strokes, not a glyph (the guide: above U+00FF, assume a
// shape).
CHART_ROUTE :: [?]rl.Vector2{{178, 248}, {300, 300}, {398, 398}, {470, 345}, {562, 302}, {700, 250}, {812, 246}}
CHART_X :: rl.Vector2{812, 246}

draw_chart_route :: proc() {
	route := CHART_ROUTE
	DASH :: 9
	for i in 0 ..< len(route) - 1 {
		a, b := route[i], route[i + 1]
		span := rl.Vector2Distance(a, b)
		steps := int(span / DASH)
		for s in 0 ..< steps {
			if s % 2 == 1 {
				continue
			}
			t0 := f32(s) / f32(steps)
			t1 := f32(s + 1) / f32(steps)
			rl.DrawLineEx(linalg.lerp(a, b, t0), linalg.lerp(a, b, t1), 2, CHART_INK)
		}
	}
	R :: 11
	rl.DrawLineEx(CHART_X + rl.Vector2{-R, -R}, CHART_X + rl.Vector2{R, R}, 4, CHART_MARK)
	rl.DrawLineEx(CHART_X + rl.Vector2{R, -R}, CHART_X + rl.Vector2{-R, R}, 4, CHART_MARK)
}

// draw_chart_compass draws the mock's compass rose: eight spokes, the cardinals long.
// Shapes, not a glyph — same rule as the caret, and the same trap. Vertex order is
// raylib's counter-clockwise requirement: wound the other way all eight spokes are
// culled and only the hub draws, which is exactly what the first attempt did. The
// base goes `-perp` then `+perp` so that every spoke winds CCW whatever its angle.
draw_chart_compass :: proc(centre: rl.Vector2, radius: f32) {
	for i in 0 ..< 8 {
		angle := f32(i) * math.PI / 4
		long := i % 2 == 0
		reach := long ? radius : radius * 0.52
		dir := rl.Vector2{math.cos(angle), math.sin(angle)}
		perp := rl.Vector2{-dir.y, dir.x} * (long ? 5 : 3)
		rl.DrawTriangle(centre - perp, centre + perp, centre + dir * reach, long ? CHART_INK : CHART_GRID)
	}
	rl.DrawPoly(centre, 8, 4, 0, CHART_INK)
}

// draw_chart_table_button renders one row of the stack.
//
// Begin is amber-filled and Quit is steel-bordered on a scrim, and that assignment is
// fixed rather than following the mouse: the guide reserves amber for "the thing you
// can act on right now" and holds one amber per screen, so hovering Quit cannot turn it
// amber without putting two on screen. Hover is carried by the caret and a lift in the
// scrim instead.
draw_chart_table_button :: proc(button: Chart_Table_Button, hovered: bool) {
	label := fmt.ctprint(button.label)
	text_pos := rl.Vector2 {
		button.rect.x + CHART_TABLE_LABEL_INSET,
		button.rect.y + (CHART_TABLE_BUTTON_H - UI_BODY_SIZE) / 2,
	}

	if button.choice == .Begin {
		rl.DrawRectangleRec(button.rect, COLOUR_AMBER)
		rl.DrawTextEx(ui_font_body, label, text_pos, UI_BODY_SIZE, 1, COLOUR_INK)
	} else {
		scrim: f32 = hovered ? 0.75 : 0.55
		rl.DrawRectangleRec(button.rect, rl.Fade(COLOUR_GROUND, scrim))
		rl.DrawRectangleLinesEx(button.rect, 2, COLOUR_STEEL)
		rl.DrawTextEx(ui_font_body, label, text_pos, UI_BODY_SIZE, 1, COLOUR_STEEL)
	}

	if hovered {
		draw_caret(
			rl.Vector2{button.rect.x + CHART_TABLE_LABEL_INSET / 2, button.rect.y + CHART_TABLE_BUTTON_H / 2},
			button.choice == .Begin ? COLOUR_INK : COLOUR_STEEL,
		)
	}
}

CARET_W :: 10
CARET_H :: 14

// draw_caret draws the mock's ▶ as a shape rather than as text: no candidate typeface
// examined carries the glyphs the mock draws, so depending on a font for them means
// depending on a font that does not exist (style guide, "Glyphs are shapes, not text").
//
// `centre` is the caret's midpoint. Vertex order is raylib's counter-clockwise
// requirement — reverse it and the triangle is culled, drawing nothing at all.
draw_caret :: proc(centre: rl.Vector2, colour: rl.Color) {
	rl.DrawTriangle(
		rl.Vector2{centre.x - CARET_W / 2, centre.y - CARET_H / 2},
		rl.Vector2{centre.x - CARET_W / 2, centre.y + CARET_H / 2},
		rl.Vector2{centre.x + CARET_W / 2, centre.y},
		colour,
	)
}

VIGNETTE_DEPTH :: 150

// draw_vignette darkens the screen to COLOUR_VIGNETTE at its edges. The torn parchment
// edge and dark border are the only framing signal in the reference set, and the guide
// keeps them as a vignette: this is the frame, rather than a drawn border.
//
// Drawn last, over the chrome, so it frames the whole composition rather than sitting
// under it.
draw_vignette :: proc() {
	fade := rl.Fade(COLOUR_VIGNETTE, 0)
	rl.DrawRectangleGradientV(0, 0, WINDOW_WIDTH, VIGNETTE_DEPTH, COLOUR_VIGNETTE, fade)
	rl.DrawRectangleGradientV(0, WINDOW_HEIGHT - VIGNETTE_DEPTH, WINDOW_WIDTH, VIGNETTE_DEPTH, fade, COLOUR_VIGNETTE)
	rl.DrawRectangleGradientH(0, 0, VIGNETTE_DEPTH, WINDOW_HEIGHT, COLOUR_VIGNETTE, fade)
	rl.DrawRectangleGradientH(WINDOW_WIDTH - VIGNETTE_DEPTH, 0, VIGNETTE_DEPTH, WINDOW_HEIGHT, fade, COLOUR_VIGNETTE)
}

// draw_chart_table_version_stamp is the Chart Table's own build stamp, deliberately not
// view.odin's draw_version_stamp: that one draws at 12px in the stock font and stock
// GRAY, both of which the style guide rules out, and it is shared with the five voyage
// screens whose restyle is out of this effort's scope. The two converge when that
// effort takes it.
draw_chart_table_version_stamp :: proc() {
	MARGIN :: 8
	text := fmt.ctprintf("%s", VERSION)
	size := rl.MeasureTextEx(ui_font_body, text, UI_BODY_SIZE, 1)
	rl.DrawTextEx(
		ui_font_body,
		text,
		rl.Vector2{WINDOW_WIDTH - size.x - MARGIN, MARGIN},
		UI_BODY_SIZE,
		1,
		COLOUR_BLUE_RECESSIVE,
	)
}
