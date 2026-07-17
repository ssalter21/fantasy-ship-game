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
// split option_screen_boxes uses, and what lets capture draw a screen it never clicks.
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

// draw_chart_table_ground fills the screen's field.
//
// The real background is a treasure map — #278 settled that this screen *is* a chart
// with buttons over it — and sourcing a shippable one is #284, which is unlanded: the
// reference copy is watermarked and cannot ship. Until it lands this is the guide's
// flat ground, which is what the chrome above it was specified against anyway, so the
// image drops in here without moving anything else.
draw_chart_table_ground :: proc() {
	rl.ClearBackground(COLOUR_GROUND)
	rl.DrawRectangleGradientV(
		0,
		WINDOW_HEIGHT / 3,
		WINDOW_WIDTH,
		WINDOW_HEIGHT * 2 / 3,
		COLOUR_GROUND,
		COLOUR_GROUND_MID,
	)
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
