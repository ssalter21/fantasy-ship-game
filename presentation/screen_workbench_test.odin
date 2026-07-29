package presentation

import "core:reflect"
import "core:slice"
import "core:strings"
import "core:testing"

// The 2D mode's contracts, which are the hull mode's two risks in the shape this mode takes
// them: a registry row that names a screen capture cannot stage draws nothing, and a layout
// field with no knob is a number that still costs a rebuild to move.

@(test)
every_workbench_screen_is_a_capture_shot :: proc(t: ^testing.T) {
	for screen in workbench_screens {
		_, _, staged := capture_shot_for(screen.name)
		testing.expectf(t, staged, "%s is a capture shot, so the workbench can stage and draw it", screen.name)
		testing.expectf(t, screen.knobs != nil, "%s needs the proc that spells its panel", screen.name)
		testing.expectf(t, screen.emit.name != "", "%s needs the constant C replaces", screen.name)
	}
}

@(test)
a_screen_is_asked_for_by_name_and_an_unknown_one_is_not :: proc(t: ^testing.T) {
	_, known := workbench_screen_for("shop")
	testing.expect(t, known, "the Shop is steerable")

	_, unknown := workbench_screen_for("no-such-screen")
	testing.expect(t, !unknown, "a name that is not a screen resolves to nothing")
}

// Every number the Offer/Shop column is laid out by is draggable, so tuning it never falls
// back to editing source — which is the whole of what this mode is for.
@(test)
every_offer_shop_layout_field_has_a_knob :: proc(t: ^testing.T) {
	// Over a layout of this test's own: the knob list is a fact about the type, and the live one
	// belongs to whatever session is drawing.
	layout := OFFER_SHOP_LAYOUT
	w := Workbench{held = -1, emit = OFFER_SHOP_EMIT}
	defer delete(w.knobs)
	workbench_offer_shop_knobs_into(&w, &layout)

	fields := reflect.struct_field_names(Offer_Shop_Layout)
	steered := make([dynamic]string, 0, len(w.knobs))
	defer delete(steered)
	for knob in w.knobs {
		testing.expectf(t, knob.field != "", "%s edits a field of the layout", knob.label)
		testing.expectf(t, !slice.contains(steered[:], knob.field), "%s has two knobs", knob.field)
		append(&steered, knob.field)
	}
	for field in fields {
		testing.expectf(t, slice.contains(steered[:], field), "%s is draggable rather than a source edit", field)
	}
	testing.expect_value(t, len(w.knobs), len(fields))

	// A range that does not contain the shipped value opens the slider with its handle pinned
	// to an end, and the shipped screen is then unreachable by dragging.
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

// The copy has to paste back over the constant it came from and compile, so it names the
// constant, its type, and every field — and carries what was dragged.
@(test)
the_emitted_layout_pastes_back_over_the_constant :: proc(t: ^testing.T) {
	layout := OFFER_SHOP_LAYOUT
	w := Workbench{held = -1, emit = OFFER_SHOP_EMIT}
	defer delete(w.knobs)
	workbench_offer_shop_knobs_into(&w, &layout)

	layout.pitch = 123.4567
	source := workbench_emit(&w)

	testing.expect(
		t,
		strings.contains(source, "OFFER_SHOP_LAYOUT :: Offer_Shop_Layout {"),
		"the emit is a drop-in replacement",
	)
	for field in reflect.struct_field_names(Offer_Shop_Layout) {
		testing.expectf(t, strings.contains(source, field), "the emitted source names %s", field)
	}
	testing.expect(t, strings.contains(source, "123.4567"), "a dragged value reaches the emitted source")
}

// The flag reader every mode's name comes through, including the two ways of writing it and
// the bare form that names nothing.
@(test)
a_flag_value_is_read_either_way_it_is_written :: proc(t: ^testing.T) {
	name, present := arg_value([]string{"--workbench", "shop"}, "--workbench")
	testing.expect(t, present)
	testing.expect_value(t, name, "shop")

	name, present = arg_value([]string{"--workbench=offer"}, "--workbench")
	testing.expect(t, present)
	testing.expect_value(t, name, "offer")

	// A bare flag is a request naming nothing — for the workbench that is the hull, not a
	// screen called "--capture".
	name, present = arg_value([]string{"--workbench", "--capture"}, "--workbench")
	testing.expect(t, present)
	testing.expect_value(t, name, "")

	name, present = arg_value([]string{"--capture"}, "--workbench")
	testing.expect(t, !present)
	testing.expect_value(t, name, "")
}
