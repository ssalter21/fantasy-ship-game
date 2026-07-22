#+private
package presentation

import "core:fmt"
import voyage "../core/voyage"
import ship "../core/ship"
import rl "vendor:raylib"

// The shared encounter frame (#304, ADR-0024): the constant chrome every encounter stage
// (Fight, Offer, Trade, Shop, Reward) sits inside, so the five read as one system rather
// than five screens — and so stage_tint's "a Battle node and a Battle chip read as the same
// thing" reaches the stage screen itself. The stage's own body fills the middle; these procs
// draw the furniture around it (a header naming the current stage, a stat line, the chart
// flick-tab, the vignette) and the one playback overlay every Event_Sink beat renders
// through. There is no encounter strip — a header naming the current stage replaces it,
// because the player meets stages one at a time (#304).
//
// Split from any poll loop (draw_X procs, never composed inside a loop) so --capture
// photographs the frame (#277, style guide).

ENCOUNTER_HEADING :: rl.Vector2{45, 28}
ENCOUNTER_STAT_MARGIN :: 24

// draw_encounter_header names the current stage top-left in its category colour — the same
// stage_tint the node and chip carry — one word, no strip and no preview. A label, not a
// control, so never amber.
draw_encounter_header :: proc(kind: voyage.Stage_Kind) {
	rl.DrawTextEx(
		ui_font_body,
		fmt.ctprintf("%s", stage_kind_label(kind)),
		ENCOUNTER_HEADING,
		UI_BODY_SIZE,
		1,
		stage_tint(kind),
	)
}

// draw_encounter_stat_line draws the compact top-right readout — the shared ship_stat_line
// (#428) — steel and right-aligned, so the top-right corner is identical on all five stages
// (#304). A readout, never amber.
draw_encounter_stat_line :: proc(s: ^ship.Ship) {
	draw_encounter_stat_line_text(ship_stat_line(s))
}

// draw_encounter_stat_line_text right-aligns an already-composed stat string into the
// top-right corner. Split from draw_encounter_stat_line so a stage that wants to overwrite
// one field — the Shop's live cargo projection on pickup (#312), `Cargo 6/8 → 2/8` — draws
// its own line in the same place and tone rather than duplicating the alignment.
draw_encounter_stat_line_text :: proc(text: string) {
	ctext := fmt.ctprintf("%s", text)
	size := rl.MeasureTextEx(ui_font_body, ctext, UI_BODY_SIZE, 1)
	rl.DrawTextEx(
		ui_font_body,
		ctext,
		rl.Vector2{WINDOW_WIDTH - size.x - ENCOUNTER_STAT_MARGIN, ENCOUNTER_HEADING.y},
		UI_BODY_SIZE,
		1,
		COLOUR_STEEL,
	)
}

ENCOUNTER_CHART_TAB_W :: 180
ENCOUNTER_CHART_TAB_H :: 30

// encounter_chart_tab_rect is the flick affordance's slot, centred on the bottom edge — the
// same place at Home and in every stage, so the gesture is learned once (#304, ADR-0024). A
// pure function of the window, so drawing and any future hit-test both ask for it.
encounter_chart_tab_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle {
		x = (WINDOW_WIDTH - ENCOUNTER_CHART_TAB_W) / 2,
		y = WINDOW_HEIGHT - ENCOUNTER_CHART_TAB_H,
		width = ENCOUNTER_CHART_TAB_W,
		height = ENCOUNTER_CHART_TAB_H,
	}
}

// draw_encounter_chart_tab draws the chart flick-tab view-only: in an encounter the raised
// chart is greyed and unclickable (ADR-0024), so the tab is a recessive-blue inert panel
// with an up-caret hinting the flick, not a steel control. The shipped stand-in for the
// swipe; #317's Home tab is the interactive twin.
draw_encounter_chart_tab :: proc() {
	rect := encounter_chart_tab_rect()
	rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, 0.55))
	draw_subpanel_border(rect, false)

	// An up-caret ("flick up to raise the chart") beside the label, the group centred in the
	// tab. A shape, not a glyph (style guide); wound base-left, base-right, apex so it
	// survives raylib's clockwise cull, the same winding draw_chart_compass proved for an
	// up-spoke.
	tint := rl.Fade(COLOUR_CYAN_DIM, 0.8)
	label := fmt.ctprint("Chart")
	lsize := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1)
	CARET := f32(16)
	GAP := f32(6)
	group_x := rect.x + (rect.width - (CARET + GAP + lsize.x)) / 2
	caret_cx := group_x + CARET / 2
	cy := rect.y + rect.height / 2
	rl.DrawTriangle(
		rl.Vector2{caret_cx - 7, cy + 4},
		rl.Vector2{caret_cx + 7, cy + 4},
		rl.Vector2{caret_cx, cy - 6},
		tint,
	)
	rl.DrawTextEx(
		ui_font_body,
		label,
		rl.Vector2{group_x + CARET + GAP, rect.y + (rect.height - UI_BODY_SIZE) / 2},
		UI_BODY_SIZE,
		1,
		tint,
	)
}

// subpanel_border_colour is a sub-panel's role tone: steel where the panel is interactive,
// recessive blue where it is inert (a shelf, a container). The framing rule in one place
// (#304, style guide) — a 2px role-toned border over a translucent ground, never a filled
// box.
subpanel_border_colour :: proc(interactive: bool) -> rl.Color {
	return interactive ? COLOUR_STEEL : COLOUR_BLUE_RECESSIVE
}

// draw_subpanel_border strokes a sub-panel's 2px role border. The stages reuse it for their
// discrete panels — a shelf (inert), an action row (interactive) — so the "one system" read
// comes from constant furniture and type, not a universal box around the body.
draw_subpanel_border :: proc(rect: rl.Rectangle, interactive: bool) {
	rl.DrawRectangleLinesEx(rect, 2, subpanel_border_colour(interactive))
}

// draw_playback_overlay is the one styled surface every Event_Sink beat renders through
// (#304, ADR-0024): a translucent scrim over the stage — dimmed but visible, so the hit
// lands on the ship you are looking at — a centred cream headline that reads the same
// wherever a beat fires, and a dim-cyan hint. It draws only the overlay, over whatever stage
// or scene is already composed, so any loop can lay it over its own body. Reward has no
// screen of its own — it is this beat.
draw_playback_overlay :: proc(headline: string) {
	rl.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, rl.Fade(COLOUR_DEEP, 0.55))

	if len(headline) > 0 {
		text := fmt.ctprintf("%s", headline)
		size := rl.MeasureTextEx(ui_font_body, text, UI_BODY_SIZE, 1)
		rl.DrawTextEx(
			ui_font_body,
			text,
			rl.Vector2{(WINDOW_WIDTH - size.x) / 2, WINDOW_HEIGHT / 2 - size.y / 2},
			UI_BODY_SIZE,
			1,
			COLOUR_CREAM,
		)
	}

	hint := fmt.ctprint("click to continue")
	hsize := rl.MeasureTextEx(ui_font_body, hint, UI_BODY_SIZE, 1)
	rl.DrawTextEx(
		ui_font_body,
		hint,
		rl.Vector2{(WINDOW_WIDTH - hsize.x) / 2, WINDOW_HEIGHT - 48},
		UI_BODY_SIZE,
		1,
		COLOUR_CYAN_DIM,
	)
}

// draw_encounter_chrome draws everything that sits on top of a stage body: the vignette that
// frames it, then the constant furniture — header, stat line, chart tab — and the styled
// version stamp. The furniture is drawn *over* the vignette on purpose: the header and stat
// line live in the top corners where the vignette darkens hardest, so drawing them under it
// (as build_surface does its cream heading, which survives being halved) would sink a muted
// category tint into the ground. The stamp already sits above the vignette for the same
// reason; this extends that to the whole frame. No ground clear and no Begin/EndDrawing — it
// decorates whatever the caller has composed, which the stage build tasks (#312/#315/#318)
// call once after their body.
// `stat_override`, when non-empty, replaces the computed stat line — the seam the Shop uses
// to ghost a post-buy cargo figure while a priced card is in hand (#312), leaving the rest
// of the furniture untouched.
draw_encounter_chrome :: proc(state: ^Game_State, kind: voyage.Stage_Kind, stat_override: string = "") {
	draw_vignette()
	draw_encounter_header(kind)
	if len(stat_override) > 0 {
		draw_encounter_stat_line_text(stat_override)
	} else {
		draw_encounter_stat_line(&state.player)
	}
	draw_encounter_chart_tab()
	draw_chart_table_version_stamp()
}

// draw_encounter_frame is the whole shared frame around an empty body, in its own drawing
// pair: ground, the chrome (vignette + furniture) over it, and — when `headline` is
// non-empty — a playback beat over all of it. It is the bare frame the stage build tasks
// fill, the Reward stage's whole screen (which is only a beat over the frame), and the frame
// capture photographs (#277). A stage with a real body composes the same pieces itself
// rather than calling this — clear, draw its body, then draw_encounter_chrome — exactly as
// draw_build_surface inlines its chrome.
draw_encounter_frame :: proc(state: ^Game_State, kind: voyage.Stage_Kind, headline: string) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	rl.ClearBackground(COLOUR_DEEP)
	draw_encounter_chrome(state, kind)
	if len(headline) > 0 {
		draw_playback_overlay(headline)
	}
}
