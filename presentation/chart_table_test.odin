package presentation

import "core:testing"

@(test)
chart_table_choice_zero_value_is_quit :: proc(t: ^testing.T) {
	// ADR-0022 makes the window-close fallback Quit and calls that rule load-bearing:
	// a Begin fallback starts a voyage that instantly winds down, then another, forever.
	// The enum's order is what makes the safe answer the default one.
	choice: Chart_Table_Choice
	testing.expect_value(t, choice, Chart_Table_Choice.Quit)
}

@(test)
chart_table_loop_quits_without_a_live_window :: proc(t: ^testing.T) {
	// Respects the same IsWindowReady() guard as the rest of the render layer
	// (ADR-0003): under `odin test` it answers rather than entering a render loop that
	// can never draw, and the answer it gives is the fallback.
	testing.expect_value(t, chart_table_loop(), Chart_Table_Choice.Quit)
}

@(test)
chart_table_offers_exactly_begin_and_quit :: proc(t: ^testing.T) {
	// #278: the Chart Table holds a title, Begin a voyage, Quit, and nothing else.
	buttons := chart_table_buttons()
	testing.expect_value(t, buttons[0].choice, Chart_Table_Choice.Begin)
	testing.expect_value(t, buttons[1].choice, Chart_Table_Choice.Quit)
}

@(test)
chart_table_buttons_are_centred_and_evenly_pitched :: proc(t: ^testing.T) {
	buttons := chart_table_buttons()
	for b in buttons {
		testing.expect_value(t, b.rect.width, f32(CHART_TABLE_BUTTON_W))
		testing.expect_value(t, b.rect.height, f32(CHART_TABLE_BUTTON_H))
		// Centred: the margin either side of the box is the same.
		testing.expect_value(t, b.rect.x, WINDOW_WIDTH - (b.rect.x + b.rect.width))
	}
	testing.expect_value(t, buttons[1].rect.y - buttons[0].rect.y, f32(CHART_TABLE_BUTTON_PITCH))
}
