package presentation

import "core:reflect"
import "core:strings"
import "core:testing"

import cutaway "./cutaway"

// The workbench's two contracts. Both are about the same risk: this is the one tool that writes
// to the geometry the game draws from, and the one that hands tuning back as source. A knob
// that is missing loses a curve to text editing; a field missing from the emit loses an
// afternoon's dragging silently, which is worse.

@(test)
every_loft_curve_has_a_knob :: proc(t: ^testing.T) {
	w := Workbench {
		eye  = cutaway.GALLEON_EYE,
		loft = cutaway.GALLEON_LOFT,
		held = -1,
	}
	defer delete(w.knobs)
	workbench_knobs(&w)

	// The camera knobs are not part of the loft and are not emitted; the rest are one per field.
	curves := 0
	for knob in w.knobs {
		if knob.emitted {
			curves += 1
		}
	}
	testing.expect_value(t, curves, len(reflect.struct_field_names(cutaway.Loft)))

	// And every knob's range actually contains the value it ships at, or the slider opens with
	// its handle pinned to an end and the shipped hull is unreachable by dragging.
	for knob in w.knobs {
		testing.expectf(
			t,
			knob.value^ >= knob.lo && knob.value^ <= knob.hi,
			"%s ships at %.3f, inside its %.3f..%.3f range",
			knob.label,
			knob.value^,
			knob.lo,
			knob.hi,
		)
	}
}

@(test)
the_emitted_loft_carries_every_field_and_the_dragged_value :: proc(t: ^testing.T) {
	w := Workbench {
		eye  = cutaway.GALLEON_EYE,
		loft = cutaway.GALLEON_LOFT,
		held = -1,
	}
	defer delete(w.knobs)
	workbench_knobs(&w)

	w.loft.tumblehome = 0.4242
	source := workbench_emit(&w)

	for field in reflect.struct_field_names(cutaway.Loft) {
		testing.expectf(t, strings.contains(source, field), "the emitted source names %s", field)
	}
	testing.expect(t, strings.contains(source, "0.4242"), "a dragged value reaches the emitted source")
	testing.expect(t, strings.contains(source, "GALLEON_LOFT :: Loft {"), "the emit is a drop-in replacement")
}

@(test)
the_workbench_hooks_are_inert_in_the_game :: proc(t: ^testing.T) {
	// The game must draw the same frame whether or not this tool exists. That is one fact about
	// each hook: the loft in force is the shipped one, and nothing is overriding the paint.
	testing.expect_value(t, cutaway.galleon_loft, cutaway.GALLEON_LOFT)

	// Nothing in the game sets the paint mode, so what the game paints by is the mode's zero value
	// — which has to be the shipped shading and not a diagnosis. That the live mode is still that
	// one is asserted in ship_paint_test.odin, the only test that moves it.
	unset: Ship_Paint
	testing.expect_value(t, unset, Ship_Paint.Shaded)

	// The camera needs no hook at all any more: the framing is a parameter (#476), so the
	// workbench asks for its own and the shipped screens ask for the moored one. Which means
	// the fact to hold is that the moored framing *is* the shipped eye's, with nothing between.
	testing.expect_value(t, ship_framing_moored().view, cutaway.galleon_view(WINDOW_WIDTH, WINDOW_HEIGHT))
}

// The two view keys, as the keyboard half of workbench_keys drives them. A key that could only
// turn a mode *on* would leave the tool stuck in a diagnosis, and one that cycled would make
// getting back to the ship a matter of pressing until it looks right.
@(test)
each_view_key_turns_its_paint_on_and_off_again :: proc(t: ^testing.T) {
	testing.expect_value(t, workbench_paint(.Shaded, .Normals), Ship_Paint.Normals)
	testing.expect_value(t, workbench_paint(.Normals, .Normals), Ship_Paint.Shaded)
	testing.expect_value(t, workbench_paint(.Shaded, .Wires), Ship_Paint.Wires)
	testing.expect_value(t, workbench_paint(.Wires, .Wires), Ship_Paint.Shaded)

	// The modes are exclusive, so asking for the other one from either is a switch rather than a
	// combination that paints neither diagnosis.
	testing.expect_value(t, workbench_paint(.Wires, .Normals), Ship_Paint.Normals)
	testing.expect_value(t, workbench_paint(.Normals, .Wires), Ship_Paint.Wires)
}
