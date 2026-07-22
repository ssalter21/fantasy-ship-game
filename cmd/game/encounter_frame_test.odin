package main

import "core:testing"

// The drawing half of the frame can't be tested here — rl.IsWindowReady() is false under
// `odin test` — so these cover the pure layout procs the drawing reads from. The stat
// line's text is ship_stat_line's (#428), pinned in stat_line_test.odin.

@(test)
encounter_chart_tab_is_centred_on_the_bottom_edge :: proc(t: ^testing.T) {
	rect := encounter_chart_tab_rect()
	// Centred: the margin either side of the tab is the same.
	testing.expect_value(t, rect.x, WINDOW_WIDTH - (rect.x + rect.width))
	// Flush to the bottom edge, so the flick reads as a pull-tab off the screen's edge.
	testing.expect_value(t, rect.y + rect.height, f32(WINDOW_HEIGHT))
}

@(test)
subpanel_border_is_steel_when_interactive_recessive_when_inert :: proc(t: ^testing.T) {
	// The framing rule: steel states "interactive", recessive blue states "inert" (#304).
	testing.expect_value(t, subpanel_border_colour(true), COLOUR_STEEL)
	testing.expect_value(t, subpanel_border_colour(false), COLOUR_BLUE_RECESSIVE)
}
