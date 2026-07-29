package presentation

import "core:reflect"
import "core:strings"
import "core:testing"

import cutaway "./cutaway"

// The workbench's two contracts. Both are about the same risk: this is the one tool that writes
// to the geometry the game draws from, and the one that hands tuning back as source. A knob
// that is missing loses a curve to text editing; a field missing from the emit loses an
// afternoon's dragging silently, which is worse.

@(private = "file")
hull_bench :: proc() -> Hull_Workbench {
	return Hull_Workbench {
		eye = cutaway.GALLEON_EYE,
		loft = cutaway.GALLEON_LOFT,
		bench = Workbench{held = -1, emit = {name = "GALLEON_LOFT", type = "Loft"}},
	}
}

@(test)
every_loft_curve_has_a_knob :: proc(t: ^testing.T) {
	h := hull_bench()
	defer delete(h.bench.knobs)
	hull_workbench_knobs(&h)

	// The camera knobs are not part of the loft and so name no field; the rest are one per field.
	curves := 0
	for knob in h.bench.knobs {
		if knob.field != "" {
			curves += 1
		}
	}
	testing.expect_value(t, curves, len(reflect.struct_field_names(cutaway.Loft)))

	// And every knob's range actually contains the value it ships at, or the slider opens with
	// its handle pinned to an end and the shipped hull is unreachable by dragging.
	for knob in h.bench.knobs {
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
	h := hull_bench()
	defer delete(h.bench.knobs)
	hull_workbench_knobs(&h)

	h.loft.tumblehome = 0.4242
	source := workbench_emit(&h.bench)

	for field in reflect.struct_field_names(cutaway.Loft) {
		testing.expectf(t, strings.contains(source, field), "the emitted source names %s", field)
	}
	testing.expect(t, strings.contains(source, "0.4242"), "a dragged value reaches the emitted source")
	testing.expect(t, strings.contains(source, "GALLEON_LOFT :: Loft {"), "the emit is a drop-in replacement")
}

// A knob remembers what it shipped at, which is what R puts back and what the panel's
// moved-from mark compares against. Without it a session that wandered has no way home.
@(test)
reset_puts_every_knob_back_to_what_it_ships_at :: proc(t: ^testing.T) {
	h := hull_bench()
	defer delete(h.bench.knobs)
	hull_workbench_knobs(&h)

	for knob in h.bench.knobs {
		testing.expectf(t, knob.shipped == knob.value^, "%s remembers what it ships at", knob.label)
	}

	h.loft.tumblehome = 0.4242
	h.eye.yaw = 137
	for &knob in h.bench.knobs {
		knob.value^ = knob.shipped
	}
	testing.expect_value(t, h.loft, cutaway.GALLEON_LOFT)
	testing.expect_value(t, h.eye, cutaway.GALLEON_EYE)
}

@(test)
the_workbench_hooks_are_inert_in_the_game :: proc(t: ^testing.T) {
	// The game must draw the same frame whether or not this tool exists. That is one fact about
	// each hook: the loft in force is the shipped one, nothing is overriding the paint, no
	// screen's layout has been steered, and nothing is drawn over a presented frame.
	testing.expect_value(t, cutaway.galleon_loft, cutaway.GALLEON_LOFT)
	testing.expect_value(t, offer_shop_layout, OFFER_SHOP_LAYOUT)
	testing.expect(t, frame_overlay == nil, "no overlay draws into a player session's frame")

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

// The two view keys, as the keyboard half of the hull mode drives them. A key that could only
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
