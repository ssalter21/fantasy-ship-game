#+private
package presentation

import "core:fmt"
import ship "../core/ship"

// The one formatter for the ship-stat readout (#428): every screen that prints a ship's
// stat line composes it here, so the vocabulary and shape are a one-place edit.
//
// The line is the derived reads (ADR-0020) a captain weighs a decision against — effective
// Speed, cargo against capacity — never the raw fields. The wealth stat reads "Cargo" (the
// glossary's word; "Hold" is a fitting), and the terms join on a middot.
//
// `gate` is the concealment gate (ADR-0030): a scouted opponent's wealth reads — cargo and
// weight both — stay hidden, so a gated line stops at SPD and ignores `weight`. `weight`
// appends the term ship_effective_speed reads down from Speed, for the screens where the
// player is managing it (the Build ledger, the own-ship panel).
//
// Stat_Field is one term of the readout kept apart: what it is called, and what it reads. A
// screen with room to lay the terms out in columns needs the two separately — the label is
// secondary and the number is what the captain is actually reading, and the guide ranks by
// colour, which cannot be done to a term already joined into a sentence.
Stat_Field :: struct {
	label: string,
	value: string,
}

// ship_stat_fields is the readout's terms, in order. It is the source ship_stat_line is built
// from rather than a second listing beside it: two renderings of the same readout that each
// know the vocabulary is exactly how a screen ends up saying "Hold" where another says "Cargo".
//
// Returns a temp-allocator slice of temp-allocator strings, freed at the frame boundary.
ship_stat_fields :: proc(s: ^ship.Ship, gate := false, weight := false) -> []Stat_Field {
	fields := make([dynamic]Stat_Field, 0, 4, context.temp_allocator)
	append(&fields, Stat_Field{"Hull", fmt.tprintf("%d/%d", s.hull, s.max_hull)})
	append(&fields, Stat_Field{"SPD", fmt.tprintf("%d", ship.ship_effective_speed(s))})
	if !gate {
		append(&fields, Stat_Field{"Cargo", fmt.tprintf("%d/%d", ship.ship_cargo(s^), ship.ship_cargo_capacity(s^))})
		if weight {
			append(&fields, Stat_Field{"Weight", fmt.tprintf("%d", ship.ship_weight(s^))})
		}
	}
	return fields[:]
}

// Returns a temp-allocator string, freed at the frame boundary like every readout.
ship_stat_line :: proc(s: ^ship.Ship, gate := false, weight := false) -> string {
	line := ""
	for field, i in ship_stat_fields(s, gate, weight) {
		line = fmt.tprintf("%s%s%s %s", line, i == 0 ? "" : " · ", field.label, field.value)
	}
	return line
}
