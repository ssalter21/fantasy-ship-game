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
// Returns a temp-allocator string, freed at the frame boundary like every readout.
ship_stat_line :: proc(s: ^ship.Ship, gate := false, weight := false) -> string {
	line := fmt.tprintf("Hull %d/%d · SPD %d", s.hull, s.max_hull, ship.ship_effective_speed(s))
	if gate {
		return line
	}
	line = fmt.tprintf("%s · Cargo %d/%d", line, ship.ship_cargo(s^), ship.ship_cargo_capacity(s^))
	if weight {
		line = fmt.tprintf("%s · Weight %d", line, ship.ship_weight(s^))
	}
	return line
}
