package presentation

import "core:fmt"
import "core:testing"
import ship "../core/ship"

// ship_stat_line is the one formatter for the ship-stat readout (#428); these pin the
// vocabulary (Cargo, per the glossary — Hold is a fitting), the middot separator, and the
// derived reads (ADR-0020): effective Speed and cargo against capacity, not the raw fields.

@(test)
ship_stat_line_reads_hull_speed_and_cargo :: proc(t: ^testing.T) {
	s := ship.ship_starting_ship()
	defer delete(s.layout)

	want := fmt.tprintf(
		"Hull %d/%d · SPD %d · Cargo %d/%d",
		s.hull,
		s.max_hull,
		ship.ship_effective_speed(&s),
		ship.ship_cargo(s),
		ship.ship_cargo_capacity(s),
	)
	testing.expect_value(t, ship_stat_line(&s), want)
}

@(test)
ship_stat_line_appends_weight_on_request :: proc(t: ^testing.T) {
	s := ship.ship_starting_ship()
	defer delete(s.layout)

	want := fmt.tprintf(
		"Hull %d/%d · SPD %d · Cargo %d/%d · Weight %d",
		s.hull,
		s.max_hull,
		ship.ship_effective_speed(&s),
		ship.ship_cargo(s),
		ship.ship_cargo_capacity(s),
		ship.ship_weight(s),
	)
	testing.expect_value(t, ship_stat_line(s = &s, weight = true), want)
}

@(test)
ship_stat_line_gate_stops_at_speed :: proc(t: ^testing.T) {
	s := ship.ship_starting_ship()
	defer delete(s.layout)

	want := fmt.tprintf("Hull %d/%d · SPD %d", s.hull, s.max_hull, ship.ship_effective_speed(&s))
	testing.expect_value(t, ship_stat_line(s = &s, gate = true), want)
	// The concealment gate (ADR-0030) hides the wealth reads wholesale — cargo and weight
	// together — so a gated line ignores the weight request rather than leaking it.
	testing.expect_value(t, ship_stat_line(s = &s, gate = true, weight = true), want)
}
