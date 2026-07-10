package ship

import "core:testing"

make_layout_slot :: proc(name: string, size: Slot_Size, base_visibility: Visibility) -> Layout_Slot {
	return Layout_Slot{slot = Slot{name = name, size = size, base_visibility = base_visibility}}
}

@(test)
fitting_with_matching_size_occupies_the_slot :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)
	cannon := Fitting{name = "Cannon", size = .Large}

	ok := ship_fit(&layout_slot, cannon)

	testing.expect(t, ok)
	installed, has_fitting := layout_slot.fitting.?
	testing.expect(t, has_fitting)
	testing.expect_value(t, installed.name, "Cannon")
}

@(test)
undersized_fitting_is_rejected_by_a_larger_slot :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)
	dagger := Fitting{name = "Dagger", size = .Small}

	ok := ship_fit(&layout_slot, dagger)

	testing.expect(t, !ok)
	_, has_fitting := layout_slot.fitting.?
	testing.expect(t, !has_fitting)
}

@(test)
oversized_fitting_is_rejected_by_a_smaller_slot :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("top crew", .Small, .Exposed)
	cannon := Fitting{name = "Cannon", size = .Large}

	ok := ship_fit(&layout_slot, cannon)

	testing.expect(t, !ok)
	_, has_fitting := layout_slot.fitting.?
	testing.expect(t, !has_fitting)
}

@(test)
fitting_into_an_already_occupied_slot_is_rejected :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)
	first := Fitting{name = "Cannon", size = .Large}
	second := Fitting{name = "Upgraded Cannon", size = .Large}
	ok_first := ship_fit(&layout_slot, first)
	testing.expect(t, ok_first)

	ok_second := ship_fit(&layout_slot, second)

	testing.expect(t, !ok_second)
	installed, _ := layout_slot.fitting.?
	testing.expect_value(t, installed.name, "Cannon")
}

@(test)
cargo_fitting_with_no_effects_and_a_positive_stack_count_is_accepted :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("hold", .Small, .Concealed)
	rations := Fitting{name = "Rations", size = .Small, is_cargo = true, stack_count = 3}

	ok := ship_fit(&layout_slot, rations)

	testing.expect(t, ok)
	_, has_fitting := layout_slot.fitting.?
	testing.expect(t, has_fitting)
}

@(test)
cargo_fitting_with_a_passive_effect_is_rejected :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("hold", .Small, .Concealed)
	cursed_loot := Fitting{name = "Cursed Loot", size = .Small, is_cargo = true, stack_count = 1, passive = Effect{}}

	ok := ship_fit(&layout_slot, cursed_loot)

	testing.expect(t, !ok)
	_, has_fitting := layout_slot.fitting.?
	testing.expect(t, !has_fitting)
}

@(test)
cargo_fitting_with_an_active_effect_is_rejected :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("hold", .Small, .Concealed)
	trapped_chest := Fitting{name = "Trapped Chest", size = .Small, is_cargo = true, stack_count = 1, active = Effect{}}

	ok := ship_fit(&layout_slot, trapped_chest)

	testing.expect(t, !ok)
	_, has_fitting := layout_slot.fitting.?
	testing.expect(t, !has_fitting)
}

@(test)
cargo_fitting_with_a_zero_stack_count_is_rejected :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("hold", .Small, .Concealed)
	empty_crate := Fitting{name = "Empty Crate", size = .Small, is_cargo = true, stack_count = 0}

	ok := ship_fit(&layout_slot, empty_crate)

	testing.expect(t, !ok)
	_, has_fitting := layout_slot.fitting.?
	testing.expect(t, !has_fitting)
}

@(test)
empty_slot_resolves_to_its_own_base_visibility :: proc(t: ^testing.T) {
	concealed_slot := make_layout_slot("hold", .Small, .Concealed)

	testing.expect_value(t, ship_effective_visibility(concealed_slot), Visibility.Concealed)
}

@(test)
fitting_with_no_override_resolves_to_the_slot_base_visibility :: proc(t: ^testing.T) {
	exposed_slot := Layout_Slot{
		slot = Slot{name = "top deck", size = .Medium, base_visibility = .Exposed},
		fitting = Fitting{name = "Crew", size = .Medium},
	}

	testing.expect_value(t, ship_effective_visibility(exposed_slot), Visibility.Exposed)
}

@(test)
fitting_override_forces_an_exposed_slot_to_read_as_concealed :: proc(t: ^testing.T) {
	exposed_slot := Layout_Slot{
		slot = Slot{name = "top deck", size = .Medium, base_visibility = .Exposed},
		fitting = Fitting{name = "Hidden Assassin", size = .Medium, visibility_override = Visibility.Concealed},
	}

	testing.expect_value(t, ship_effective_visibility(exposed_slot), Visibility.Concealed)
}

@(test)
fitting_override_forces_a_concealed_slot_to_read_as_exposed :: proc(t: ^testing.T) {
	concealed_slot := Layout_Slot{
		slot = Slot{name = "hold", size = .Large, base_visibility = .Concealed},
		fitting = Fitting{name = "Unmissable Artifact", size = .Large, visibility_override = Visibility.Exposed},
	}

	testing.expect_value(t, ship_effective_visibility(concealed_slot), Visibility.Exposed)
}

@(test)
cargo_capacity_with_no_cargo_slots_filled_is_the_ship_baseline :: proc(t: ^testing.T) {
	s := Ship{
		base_cargo_capacity = 4,
		layout = []Layout_Slot{
			{slot = Slot{name = "gun deck", size = .Large, base_visibility = .Exposed}, fitting = Fitting{name = "Cannon", size = .Large}},
		},
	}

	testing.expect_value(t, ship_cargo_capacity(s), 4)
}

@(test)
cargo_capacity_increases_by_the_size_contribution_of_each_cargo_filled_slot :: proc(t: ^testing.T) {
	s := Ship{
		base_cargo_capacity = 4,
		layout = []Layout_Slot{
			{slot = Slot{name = "hold 1", size = .Small, base_visibility = .Concealed}, fitting = Fitting{name = "Cargo", size = .Small, is_cargo = true, stack_count = 1}},
			{slot = Slot{name = "hold 2", size = .Medium, base_visibility = .Concealed}, fitting = Fitting{name = "Cargo", size = .Medium, is_cargo = true, stack_count = 1}},
			{slot = Slot{name = "hold 3", size = .Large, base_visibility = .Concealed}, fitting = Fitting{name = "Cargo", size = .Large, is_cargo = true, stack_count = 1}},
		},
	}

	// placeholder per-size contributions: small=1, medium=2, large=3
	testing.expect_value(t, ship_cargo_capacity(s), 4 + 1 + 2 + 3)
}

@(test)
ship_with_no_captain_assigned_has_no_captain :: proc(t: ^testing.T) {
	s := Ship{}

	_, has_captain := s.captain.?
	testing.expect(t, !has_captain)
}

@(test)
ship_with_a_captain_assigned_carries_that_captains_name :: proc(t: ^testing.T) {
	s := Ship{captain = Captain{name = "Blackheart"}}

	captain, has_captain := s.captain.?
	testing.expect(t, has_captain)
	testing.expect_value(t, captain.name, "Blackheart")
}
