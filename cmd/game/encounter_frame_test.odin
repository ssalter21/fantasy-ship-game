package main

import "core:fmt"
import "core:testing"
import ship "../../core/ship"

// The drawing half of the frame can't be tested here — rl.IsWindowReady() is false under
// `odin test` — so these cover the pure layout and text procs the drawing reads from.

@(test)
encounter_stat_line_reads_hull_speed_and_cargo :: proc(t: ^testing.T) {
	s := ship.ship_starting_ship()
	defer delete(s.layout)

	// The stat line is derived reads (ADR-0020), so it must match the ship procs, not the raw
	// fields — this pins the order, the labels, and the middot separators.
	want := fmt.tprintf(
		"Hull %d/%d · SPD %d · Cargo %d/%d",
		s.hull,
		s.max_hull,
		ship.ship_effective_speed(&s),
		ship.ship_cargo(s),
		ship.ship_cargo_capacity(s),
	)
	testing.expect_value(t, encounter_stat_line_text(&s), want)
}

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
