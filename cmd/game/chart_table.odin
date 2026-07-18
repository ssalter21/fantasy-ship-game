package main

import "core:fmt"
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

// The title is letterspaced rather than enlarged: the guide fixes the display size (now
// 32px, Pixel Operator's crisp title size), so `spacing` is the only knob left for the
// mock's wide, airy title, and it also holds the title to the width the surrounding
// composition clears for it (the islands avoid the title band). 13 lands the rendered
// title on the mock's title-to-window-width ratio (~43%, measured 432px in 1024). Keep it
// an integer: a fractional spacing drifts glyphs off the pixel grid and softens a POINT-
// filtered face. (Pixelify at 40px reached the same ratio at 8; the smaller face needs more.)
CHART_TABLE_TITLE :: "Fantasy Ship Game"
CHART_TABLE_TITLE_SPACING :: 13

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
	draw_menu_title_scrim()

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
// They were the Chart Table's drawn ground until #284's sourced background replaced it
// (art.odin); their live consumer now is the voyage map's mini-chart (view.odin), which
// still draws land and a route from the ramp. Kept here beside the screen they were
// measured for.
//
// Land is khaki with an inland green, not parchment: treasure-map.jpg's parchment is
// 9.67% strongly-warm against 0.2-2.7% for every other reference, and the amber rule
// works only because warm is scarce (#294). A cream title and an amber button cannot
// sit on cream.
CHART_LAND :: rl.Color{83, 80, 73, 255} // the mock's island body, #535049
CHART_LAND_SHADE :: rl.Color{73, 67, 55, 255} // its shadowed edge, #494337
CHART_LAND_GREEN :: rl.Color{35, 65, 44, 255} // its inland green, #23412C
CHART_GRID :: rl.Color{77, 88, 99, 255} // the mock's grid, #4D5863 — H210, already on the ramp
// CHART_INK is the chart's own linework — the rose, the route. Opaque and quiet on
// purpose. The world must never outshine the chrome (the guide's rule for zone tints
// is the same rule), and a translucent tone cannot enforce that: alpha composites
// per-draw, so eight Fade(CREAM, 0.7) spokes crossing at a hub stack to near-opaque
// cream. An opaque dim tone is the only one whose peak you can predict from the
// constant. H215, so it is on the ramp.
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

// draw_chart_table_ground draws the sourced tropical-island background this screen
// sits on (art.odin, the #284 carve-out). It replaces the sea-chart that #294 drew
// from the ramp with raylib primitives — that ground was a placeholder "only in
// ambition", and #284 always named a sourced image as the improvement in *depiction*
// it would take. The palette rule is unchanged and was enforced at conform time rather
// than draw time: the asset is measured onto the ramp (peak luminance 142, below the
// title's ~211) and carries no warm pixels, so the guide's two hard rules — the world
// never outshines the chrome, amber stays scarce — hold before the texture is ever
// blitted.
//
// The scene is 400x272 at native resolution, POINT-scaled to the window (art.odin sets
// the filter). Composition is split from polling the same way the chart was: capture
// photographs this at frame 0 (#278), and a fixed asset keeps every screenshot diff
// meaningful.
draw_chart_table_ground :: proc() {
	rl.ClearBackground(COLOUR_DEEP)
	src := rl.Rectangle{0, 0, f32(menu_island_tex.width), f32(menu_island_tex.height)}
	dst := rl.Rectangle{0, 0, WINDOW_WIDTH, WINDOW_HEIGHT}
	rl.DrawTexturePro(menu_island_tex, src, dst, rl.Vector2{0, 0}, 0, rl.WHITE)
}

// draw_menu_title_scrim darkens a full-width band behind the title so the cream reads
// over the daytime background's bright sky. The sourced daylight scene (art.odin) sits
// above the title's own luminance, so the guide's "world never outshines the chrome"
// rule cannot hold globally for it — legibility is bought locally here instead of by
// draining the daylight out of the whole image. Centred on the title line
// (CHART_TABLE_TITLE_CENTRE_Y) and fading to nothing top and bottom so it reads as
// atmosphere, not a drawn bar. The dusk variant does not need this and drops it.
MENU_TITLE_SCRIM_HALF :: 60
MENU_TITLE_SCRIM_ALPHA :: 0.62

draw_menu_title_scrim :: proc() {
	SCRIM_TOP :: CHART_TABLE_TITLE_CENTRE_Y - MENU_TITLE_SCRIM_HALF
	clear := rl.Fade(COLOUR_VIGNETTE, 0)
	dark := rl.Fade(COLOUR_VIGNETTE, MENU_TITLE_SCRIM_ALPHA)
	rl.DrawRectangleGradientV(0, SCRIM_TOP, WINDOW_WIDTH, MENU_TITLE_SCRIM_HALF, clear, dark)
	rl.DrawRectangleGradientV(0, CHART_TABLE_TITLE_CENTRE_Y, WINDOW_WIDTH, MENU_TITLE_SCRIM_HALF, dark, clear)
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
