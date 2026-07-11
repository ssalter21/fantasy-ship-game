package ship

import "core:testing"

find_slot :: proc(s: Ship, slot_name: string) -> Layout_Slot {
	for layout_slot in s.layout {
		if layout_slot.slot.name == slot_name {
			return layout_slot
		}
	}
	panic("slot not found")
}

@(test)
ship_template_layout_has_six_slots_two_medium_exposed_one_large_exposed_three_small_concealed :: proc(t: ^testing.T) {
	layout := ship_template_layout()
	defer delete(layout)

	testing.expect_value(t, len(layout), 6)

	medium_exposed, large_exposed, small_concealed := 0, 0, 0
	for layout_slot in layout {
		switch {
		case layout_slot.slot.size == .Medium && layout_slot.slot.base_visibility == .Exposed:
			medium_exposed += 1
		case layout_slot.slot.size == .Large && layout_slot.slot.base_visibility == .Exposed:
			large_exposed += 1
		case layout_slot.slot.size == .Small && layout_slot.slot.base_visibility == .Concealed:
			small_concealed += 1
		}
	}

	testing.expect_value(t, medium_exposed, 2)
	testing.expect_value(t, large_exposed, 1)
	testing.expect_value(t, small_concealed, 3)
}

Expected_Loadout :: struct {
	slot_name:    string,
	fitting_name: string,
}

@(test)
ship_starting_ship_fills_the_exposed_slots_with_the_fixed_starting_loadout :: proc(t: ^testing.T) {
	s := ship_starting_ship()
	defer delete(s.layout)

	expected := []Expected_Loadout{
		{"top deck", "Captain's Quarters"},
		{"top crew", "Top Crew"},
		{"gun deck", "Gun Deck"},
	}

	for e in expected {
		fitting, has_fitting := find_slot(s, e.slot_name).fitting.?
		testing.expect(t, has_fitting)
		testing.expect_value(t, fitting.name, e.fitting_name)
	}
}

@(test)
ship_starting_ship_fills_every_concealed_slot_with_cargo_by_default :: proc(t: ^testing.T) {
	s := ship_starting_ship()
	defer delete(s.layout)

	concealed_count := 0
	for layout_slot in s.layout {
		if layout_slot.slot.base_visibility != .Concealed {
			continue
		}
		concealed_count += 1
		fitting, has_fitting := layout_slot.fitting.?
		testing.expect(t, has_fitting)
		testing.expect(t, fitting.is_cargo)
	}
	testing.expect_value(t, concealed_count, 3)
}

@(test)
ship_starting_ship_is_assigned_the_one_captain :: proc(t: ^testing.T) {
	s := ship_starting_ship()
	defer delete(s.layout)

	captain, has_captain := s.captain.?
	testing.expect(t, has_captain)
	testing.expect_value(t, captain.name, ship_starting_captain().name)
}

@(test)
upgraded_top_crew_keeps_size_and_category_but_out_magnitudes_the_base_fitting :: proc(t: ^testing.T) {
	base := ship_fitting_top_crew()
	upgraded := ship_fitting_upgraded_top_crew(1)

	testing.expect_value(t, upgraded.size, base.size)
	testing.expect_value(t, upgraded.category, base.category)
	base_active, _ := base.active.?
	upgraded_active, _ := upgraded.active.?
	testing.expect(t, upgraded_active.magnitude > base_active.magnitude)
}

@(test)
upgraded_captains_quarters_keeps_size_and_category_but_out_magnitudes_the_base_fitting :: proc(t: ^testing.T) {
	base := ship_fitting_captains_quarters()
	upgraded := ship_fitting_upgraded_captains_quarters(1)

	testing.expect_value(t, upgraded.size, base.size)
	testing.expect_value(t, upgraded.category, base.category)
	base_active, _ := base.active.?
	upgraded_active, _ := upgraded.active.?
	testing.expect(t, upgraded_active.magnitude > base_active.magnitude)
}

@(test)
upgraded_gun_deck_keeps_size_and_category_but_out_magnitudes_the_base_fitting :: proc(t: ^testing.T) {
	base := ship_fitting_gun_deck()
	upgraded := ship_fitting_upgraded_gun_deck(1)

	testing.expect_value(t, upgraded.size, base.size)
	testing.expect_value(t, upgraded.category, base.category)
	base_active, _ := base.active.?
	upgraded_active, _ := upgraded.active.?
	testing.expect(t, upgraded_active.magnitude > base_active.magnitude)
}
