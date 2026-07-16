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
a_fitting_defaults_to_carrying_no_tags :: proc(t: ^testing.T) {
	bare := Fitting{name = "Ballast", size = .Small}

	testing.expect_value(t, bare.tags, bit_set[Tag]{})
}

@(test)
a_fitting_can_carry_more_than_one_tag :: proc(t: ^testing.T) {
	// The set is the axis synergy effects will later count along (#88); a
	// single fitting may sit in more than one family at once.
	war_beast := Fitting{name = "War Kraken", size = .Large, tags = {.Beast, .Weapon}}

	testing.expect(t, .Beast in war_beast.tags)
	testing.expect(t, .Weapon in war_beast.tags)
	testing.expect(t, .Crew not_in war_beast.tags)
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
cargo_capacity_excludes_a_slot_holding_a_non_cargo_fitting :: proc(t: ^testing.T) {
	// A slot spent on a gun holds no cargo (ADR-0020, #157): its size does not
	// count toward capacity, but empty and cargo-filled slots both do.
	s := Ship{
		layout = []Layout_Slot{
			{slot = Slot{name = "gun deck", size = .Large, base_visibility = .Exposed}, fitting = Fitting{name = "Cannon", size = .Large}},
			{slot = Slot{name = "hold 1", size = .Small, base_visibility = .Concealed}},
			{slot = Slot{name = "hold 2", size = .Medium, base_visibility = .Concealed}, fitting = Fitting{name = "Cargo", size = .Medium, is_cargo = true, stack_count = 5}},
		},
	}

	// The empty Small (10) and the cargo-filled Medium (20); the gun's Large is out.
	testing.expect_value(t, ship_cargo_capacity(s), 10 + 20)
}

@(test)
cargo_capacity_sums_each_cargo_capable_slots_size_contribution :: proc(t: ^testing.T) {
	s := Ship{
		layout = []Layout_Slot{
			{slot = Slot{name = "hold 1", size = .Small, base_visibility = .Concealed}},
			{slot = Slot{name = "hold 2", size = .Medium, base_visibility = .Concealed}},
			{slot = Slot{name = "hold 3", size = .Large, base_visibility = .Concealed}},
		},
	}

	// Small 10, Medium 20, Large 40 (#156: ×10 and doubling, a Large worth four Smalls).
	testing.expect_value(t, ship_cargo_capacity(s), 10 + 20 + 40)
}

@(test)
the_starting_hull_reads_ninety_capacity_against_a_fifty_cargo :: proc(t: ^testing.T) {
	// The destination's headroom by construction (ADR-0020, #156): the 8-slot hull
	// with its three exposed guns has five cargo-capable slots — Large 40 + Medium
	// 20 + three Small 30 = 90 — and is stowed with a 50 cargo, leaving 40 spare.
	s := ship_starting_ship()
	defer delete(s.layout)

	testing.expect_value(t, ship_cargo_capacity(s), 90)
	testing.expect_value(t, ship_cargo(s), 50)
}

// The stow-overflow tests below share a two-slot hold — Small 10 + Large 40 = 50 of
// capacity — so the returned `spilled` reads against a capacity that is easy to see.

@(test)
stowing_within_capacity_returns_zero_spilled :: proc(t: ^testing.T) {
	// A stow that fits reports no loss: the return is the overflow, and there is none.
	s := Ship{layout = []Layout_Slot{{slot = Slot{size = .Small}}, {slot = Slot{size = .Large}}}}
	testing.expect_value(t, ship_stow_cargo(s.layout, 30), 0) // 30 into 50 of capacity
	testing.expect_value(t, ship_cargo(s), 30)
}

@(test)
stowing_exactly_to_capacity_returns_zero_spilled :: proc(t: ^testing.T) {
	// The fits-exactly boundary: filling every slot to the brim drops nothing.
	s := Ship{layout = []Layout_Slot{{slot = Slot{size = .Small}}, {slot = Slot{size = .Large}}}}
	testing.expect_value(t, ship_stow_cargo(s.layout, 50), 0) // exactly capacity
	testing.expect_value(t, ship_cargo(s), 50)
}

@(test)
stowing_above_capacity_returns_the_overflow :: proc(t: ^testing.T) {
	// Overflow above capacity is dropped (#157) and returned, never stored: the holds
	// fill to 50 and the return names the 15 that found no slot.
	s := Ship{layout = []Layout_Slot{{slot = Slot{size = .Small}}, {slot = Slot{size = .Large}}}}
	testing.expect_value(t, ship_stow_cargo(s.layout, 65), 15) // 15 over a 50 capacity
	testing.expect_value(t, ship_cargo(s), 50)
}

@(test)
refilling_an_emptied_hold_reports_its_overflow_afresh :: proc(t: ^testing.T) {
	// A re-stow rebuilds the hold from scratch, so the return reflects the new total,
	// not the old: brim-fill, empty, then refill past capacity, and each stow reports
	// its own overflow.
	s := Ship{layout = []Layout_Slot{{slot = Slot{size = .Small}}, {slot = Slot{size = .Large}}}}
	testing.expect_value(t, ship_stow_cargo(s.layout, 50), 0) // brim-full
	testing.expect_value(t, ship_stow_cargo(s.layout, 0), 0) // emptied: nothing to spill
	testing.expect_value(t, ship_cargo(s), 0)
	testing.expect_value(t, ship_stow_cargo(s.layout, 70), 20) // refilled past capacity
	testing.expect_value(t, ship_cargo(s), 50)
}

@(test)
ship_stow_spill_predicts_the_overflow_a_stow_would_drop :: proc(t: ^testing.T) {
	// The predictive twin agrees with the mutating stow's return across the range, so a
	// caller that must name the loss before stowing (the Reward beat) gets the same
	// number ship_stow_cargo would report after.
	for amount in ([]int{0, 30, 50, 65, 120}) {
		predicted := Ship{layout = []Layout_Slot{{slot = Slot{size = .Small}}, {slot = Slot{size = .Large}}}}
		actual := Ship{layout = []Layout_Slot{{slot = Slot{size = .Small}}, {slot = Slot{size = .Large}}}}
		testing.expectf(
			t,
			ship_stow_spill(predicted, amount) == ship_stow_cargo(actual.layout, amount),
			"ship_stow_spill disagreed with ship_stow_cargo at amount %d",
			amount,
		)
	}
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

@(test)
remove_takes_the_fitting_out_and_leaves_the_slot_empty :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)
	ok := ship_fit(&layout_slot, Fitting{name = "Gun Deck", size = .Large})
	testing.expect(t, ok)

	removed, was_there := ship_remove(&layout_slot)

	testing.expect(t, was_there)
	testing.expect_value(t, removed.name, "Gun Deck")
	_, still_there := layout_slot.fitting.?
	testing.expect(t, !still_there) // discarded: nothing holds it now
}

@(test)
remove_of_an_empty_slot_is_a_rejected_no_op :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)

	_, was_there := ship_remove(&layout_slot)

	testing.expect(t, !was_there)
}

@(test)
move_relocates_a_fitting_into_an_empty_same_size_slot :: proc(t: ^testing.T) {
	layout := []Layout_Slot{
		make_layout_slot("gun deck", .Large, .Exposed),
		make_layout_slot("forecastle", .Large, .Exposed),
	}
	ok := ship_fit(&layout[0], Fitting{name = "Gun Deck", size = .Large})
	testing.expect(t, ok)

	moved, did_move := ship_move(&layout[0], &layout[1])

	testing.expect(t, did_move)
	testing.expect_value(t, moved.name, "Gun Deck")
	_, source_empty := layout[0].fitting.?
	testing.expect(t, !source_empty)
	dest, dest_full := layout[1].fitting.?
	testing.expect(t, dest_full)
	testing.expect_value(t, dest.name, "Gun Deck")
}

@(test)
move_into_an_occupied_slot_is_rejected_without_disturbing_either_slot :: proc(t: ^testing.T) {
	layout := []Layout_Slot{
		make_layout_slot("gun deck", .Large, .Exposed),
		make_layout_slot("forecastle", .Large, .Exposed),
	}
	testing.expect(t, ship_fit(&layout[0], Fitting{name = "Gun Deck", size = .Large}))
	testing.expect(t, ship_fit(&layout[1], Fitting{name = "Ballista", size = .Large}))

	_, did_move := ship_move(&layout[0], &layout[1])

	testing.expect(t, !did_move)
	source, _ := layout[0].fitting.?
	dest, _ := layout[1].fitting.?
	testing.expect_value(t, source.name, "Gun Deck") // untouched
	testing.expect_value(t, dest.name, "Ballista") // untouched
}

@(test)
move_into_a_different_size_slot_is_rejected_by_the_fit_rule :: proc(t: ^testing.T) {
	layout := []Layout_Slot{
		make_layout_slot("top deck", .Medium, .Exposed),
		make_layout_slot("gun deck", .Large, .Exposed),
	}
	testing.expect(t, ship_fit(&layout[0], Fitting{name = "Top Crew", size = .Medium}))

	_, did_move := ship_move(&layout[0], &layout[1])

	testing.expect(t, !did_move)
	source, source_full := layout[0].fitting.?
	testing.expect(t, source_full) // the medium fitting stayed put
	testing.expect_value(t, source.name, "Top Crew")
	_, dest_full := layout[1].fitting.?
	testing.expect(t, !dest_full) // the large slot never received it
}

@(test)
move_from_an_empty_slot_is_rejected :: proc(t: ^testing.T) {
	layout := []Layout_Slot{
		make_layout_slot("gun deck", .Large, .Exposed),
		make_layout_slot("forecastle", .Large, .Exposed),
	}

	_, did_move := ship_move(&layout[0], &layout[1])

	testing.expect(t, !did_move)
}

@(test)
replace_swaps_a_same_size_fitting_into_an_occupied_slot :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)
	testing.expect(t, ship_fit(&layout_slot, Fitting{name = "Cannon", size = .Large}))

	ok := ship_replace_fitting(&layout_slot, Fitting{name = "Ballista", size = .Large})

	testing.expect(t, ok)
	installed, has_fitting := layout_slot.fitting.?
	testing.expect(t, has_fitting)
	testing.expect_value(t, installed.name, "Ballista") // the displaced Cannon is gone
}

@(test)
replace_into_an_empty_slot_places_the_fitting :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)

	ok := ship_replace_fitting(&layout_slot, Fitting{name = "Cannon", size = .Large})

	testing.expect(t, ok)
	installed, has_fitting := layout_slot.fitting.?
	testing.expect(t, has_fitting)
	testing.expect_value(t, installed.name, "Cannon")
}

@(test)
replace_with_a_different_size_fitting_is_rejected_and_leaves_the_slot_untouched :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)
	testing.expect(t, ship_fit(&layout_slot, Fitting{name = "Cannon", size = .Large}))

	ok := ship_replace_fitting(&layout_slot, Fitting{name = "Dagger", size = .Small})

	testing.expect(t, !ok)
	installed, has_fitting := layout_slot.fitting.?
	testing.expect(t, has_fitting)
	testing.expect_value(t, installed.name, "Cannon") // untouched
}

@(test)
replace_with_a_cargo_fitting_carrying_an_effect_is_rejected :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("hold", .Large, .Concealed)
	testing.expect(t, ship_fit(&layout_slot, Fitting{name = "Cannon", size = .Large}))
	cursed_loot := Fitting{name = "Cursed Loot", size = .Large, is_cargo = true, stack_count = 1, passive = Effect{}}

	ok := ship_replace_fitting(&layout_slot, cursed_loot)

	testing.expect(t, !ok)
	installed, has_fitting := layout_slot.fitting.?
	testing.expect(t, has_fitting)
	testing.expect_value(t, installed.name, "Cannon") // untouched
}

@(test)
effect_magnitude_resolves_a_flat_effect_to_its_stored_constant :: proc(t: ^testing.T) {
	s := Ship{}
	ctx := Effect_Context{owner = &s}

	testing.expect_value(t, effect_magnitude(Effect{magnitude = 7}, ctx), Magnitude(7))
	testing.expect_value(t, effect_magnitude(Effect{kind = .Modify_Durability, magnitude = 4}, ctx), Magnitude(4))
}

// synergy_ship builds a ship whose layout holds the given fittings in bare
// same-size slots, for the selector-count and synergy-resolution tests below.
synergy_ship :: proc(fittings: ..Fitting) -> Ship {
	layout := make([]Layout_Slot, len(fittings))
	for f, i in fittings {
		layout[i] = Layout_Slot{slot = Slot{size = f.size, base_visibility = .Exposed}, fitting = f}
	}
	return Ship{layout = layout}
}

@(test)
selector_matches_over_each_of_tag_size_visibility_and_category :: proc(t: ^testing.T) {
	slot := Layout_Slot{
		slot    = Slot{size = .Large, base_visibility = .Concealed},
		fitting = Fitting{name = "War Kraken", size = .Large, category = .Fire, tags = {.Beast, .Weapon}},
	}

	// Tag: a multi-tag fitting matches on each of its own tags, and misses a tag it lacks.
	testing.expect(t, selector_matches(slot, Selector(Tag.Beast)))
	testing.expect(t, selector_matches(slot, Selector(Tag.Weapon)))
	testing.expect(t, !selector_matches(slot, Selector(Tag.Crew)))
	// Size / Category: the fitting's own field.
	testing.expect(t, selector_matches(slot, Selector(Slot_Size.Large)))
	testing.expect(t, !selector_matches(slot, Selector(Slot_Size.Small)))
	testing.expect(t, selector_matches(slot, Selector(Category.Fire)))
	testing.expect(t, !selector_matches(slot, Selector(Category.Muster)))
	// Visibility: the fitting's effective visibility (through the slot), not a raw field.
	testing.expect(t, selector_matches(slot, Selector(Visibility.Concealed)))
	testing.expect(t, !selector_matches(slot, Selector(Visibility.Exposed)))
}

@(test)
count_matching_counts_installed_fittings_and_skips_empty_slots :: proc(t: ^testing.T) {
	s := synergy_ship(
		Fitting{name = "Gun Deck", size = .Large, tags = {.Weapon}},
		Fitting{name = "Ballista", size = .Small, tags = {.Weapon}},
		Fitting{name = "Top Crew", size = .Medium, tags = {.Crew}},
	)
	defer delete(s.layout)
	// Leave one slot empty to prove empties don't count.
	s.layout[1].fitting = nil

	testing.expect_value(t, ship_count_matching(&s, Selector(Tag.Weapon)), 1)
	testing.expect_value(t, ship_count_matching(&s, Selector(Tag.Crew)), 1)
	testing.expect_value(t, ship_count_matching(&s, Selector(Tag.Beast)), 0)
}

@(test)
count_matching_counts_a_multi_tag_fitting_once_for_each_of_its_tags :: proc(t: ^testing.T) {
	s := synergy_ship(
		Fitting{name = "War Kraken", size = .Large, tags = {.Beast, .Weapon}},
		Fitting{name = "Gun Deck", size = .Large, tags = {.Weapon}},
	)
	defer delete(s.layout)

	// The War Kraken counts toward both a Weapon-count and a Beast-count.
	testing.expect_value(t, ship_count_matching(&s, Selector(Tag.Weapon)), 2)
	testing.expect_value(t, ship_count_matching(&s, Selector(Tag.Beast)), 1)
}

@(test)
effect_magnitude_scales_a_synergy_effect_by_the_matching_count :: proc(t: ^testing.T) {
	s := synergy_ship(
		Fitting{name = "Gun Deck", size = .Large, tags = {.Weapon}},
		Fitting{name = "Ballista", size = .Small, tags = {.Weapon}},
		Fitting{name = "Top Crew", size = .Medium, tags = {.Crew}},
	)
	defer delete(s.layout)
	ctx := ship_effect_context(&s)

	// +2 per Weapon aboard, over the two Weapon fittings.
	synergy := Effect{magnitude = 2, synergy = Selector(Tag.Weapon)}
	testing.expect_value(t, effect_magnitude(synergy, ctx), Magnitude(4))
}

@(test)
count_matching_on_a_category_selector_counts_by_the_fittings_category_field :: proc(t: ^testing.T) {
	// A Category selector reads Fitting.category directly. That field's zero
	// value is .Muster, and cargo / effect-less fittings never set it, so a
	// Selector(Category.Muster) counts every such fitting as a Muster. This test
	// pins that behavior down (ship_count_matching's doc caveat): a content
	// author selecting on .Muster must expect zero-value fittings in the count.
	s := synergy_ship(
		Fitting{name = "Top Crew", size = .Medium, category = .Muster},
		Fitting{name = "Gun Deck", size = .Large, category = .Fire},
		Fitting{name = "Cargo", size = .Small, tags = {.Cargo}, is_cargo = true, stack_count = 1},
	)
	defer delete(s.layout)

	// Top Crew (explicit .Muster) and Cargo (zero-value .Muster) both count.
	testing.expect_value(t, ship_count_matching(&s, Selector(Category.Muster)), 2)
	testing.expect_value(t, ship_count_matching(&s, Selector(Category.Fire)), 1)
}

@(test)
effect_magnitude_of_a_synergy_with_no_matches_is_zero :: proc(t: ^testing.T) {
	s := synergy_ship(Fitting{name = "Top Crew", size = .Medium, tags = {.Crew}})
	defer delete(s.layout)
	ctx := ship_effect_context(&s)

	synergy := Effect{magnitude = 5, synergy = Selector(Tag.Weapon)}
	testing.expect_value(t, effect_magnitude(synergy, ctx), Magnitude(0))
}

@(test)
effective_stats_equal_the_raw_fields_when_no_stat_modifier_is_installed :: proc(t: ^testing.T) {
	cannon := Fitting{name = "Cannon", size = .Large, weight = 38, category = .Fire, active = Effect{magnitude = 10}}
	s := Ship{
		durability = 2, speed = 4, max_hull = 20,
		layout = []Layout_Slot{{slot = Slot{size = .Large}, fitting = cannon}},
	}

	// A plain fitting adds no stat modifier, so Durability and Max Hull read their
	// raw fields. Speed is different now (ADR-0020): every non-cargo fitting has an
	// authored weight, so effective Speed is base − weight/10, not the raw field. The
	// Large Cannon weighs 38, so 4 − 3 = 1.
	testing.expect_value(t, ship_effective_durability(&s), 2)
	testing.expect_value(t, ship_effective_speed(&s), 4 - ship_weight(s) / 10)
	testing.expect_value(t, ship_effective_max_hull(&s), 20)
}

@(test)
a_stat_modifier_fitting_raises_the_matching_effective_stat_only :: proc(t: ^testing.T) {
	reinforced := Fitting{
		name = "Reinforced Hull", size = .Small,
		passive = Effect{kind = .Modify_Durability, magnitude = 3},
	}
	s := Ship{
		durability = 2, speed = 4, max_hull = 20,
		layout = []Layout_Slot{{slot = Slot{size = .Small}, fitting = reinforced}},
	}

	testing.expect_value(t, ship_effective_durability(&s), 2 + 3)
	testing.expect_value(t, ship_effective_speed(&s), 4) // unaffected
	testing.expect_value(t, ship_effective_max_hull(&s), 20) // unaffected
}

@(test)
stat_modifiers_stack_across_slots_and_span_max_hull_and_speed :: proc(t: ^testing.T) {
	hull := Fitting{name = "Reinforced Hull", size = .Small, weight = 8, passive = Effect{kind = .Modify_Durability, magnitude = 3}}
	plating := Fitting{name = "Iron Plating", size = .Small, weight = 8, passive = Effect{kind = .Modify_Durability, magnitude = 2}}
	sails := Fitting{name = "Fast Sails", size = .Small, weight = 8, passive = Effect{kind = .Modify_Speed, magnitude = 4}}
	ballast := Fitting{name = "Ballast Tanks", size = .Small, weight = 8, passive = Effect{kind = .Modify_Max_Hull, magnitude = 10}}
	s := Ship{
		durability = 1, speed = 5, max_hull = 20,
		layout = []Layout_Slot{
			{slot = Slot{size = .Small}, fitting = hull},
			{slot = Slot{size = .Small}, fitting = plating},
			{slot = Slot{size = .Small}, fitting = sails},
			{slot = Slot{size = .Small}, fitting = ballast},
		},
	}

	testing.expect_value(t, ship_effective_durability(&s), 1 + 3 + 2)
	// base 5 + Modify_Speed 4, minus the four Small fittings' weight/10 (ADR-0020).
	testing.expect_value(t, ship_effective_speed(&s), 5 + 4 - ship_weight(s) / 10)
	testing.expect_value(t, ship_effective_max_hull(&s), 20 + 10)
}

// The calibration BASE_SPEED is solved against (ADR-0020, #158): the starting ship
// — its loadout plus the 50-cargo hold — reads exactly STARTING_SPEED. If
// ship_fitting_weight's band or BASE_SPEED drifts, this is what catches it.
@(test)
the_starting_ship_reads_the_starting_speed :: proc(t: ^testing.T) {
	s := ship_starting_ship()
	defer delete(s.layout)
	testing.expect_value(t, ship_effective_speed(&s), STARTING_SPEED)
}

// The weight-floor invariant (ADR-0020, #175): `base − weight/10 >= 0` for the ship
// at its realistic maximum fill — every cargo slot of the starting loadout full.
// The starting ship lands on 0 *exactly* (capacity 90 − starting cargo 50 = the
// 40-point budget), which is the destination's "getting rich makes you catchable"
// as arithmetic — never a live clamp, so an empty hold reads well above 0.
@(test)
a_full_hold_floors_the_starting_ship_speed_at_zero_never_below :: proc(t: ^testing.T) {
	s := ship_starting_ship()
	defer delete(s.layout)

	ship_stow_cargo(s.layout, ship_cargo_capacity(s)) // fill every cargo slot
	full := ship_effective_speed(&s)
	testing.expect(t, full >= 0)
	testing.expect_value(t, full, 0)

	ship_stow_cargo(s.layout, 0) // empty every hold
	testing.expect(t, ship_effective_speed(&s) > full) // emptiness is what varies
}

@(test)
hull_below_conditional_resolves_to_zero_above_the_threshold_and_full_below :: proc(t: ^testing.T) {
	effect := Effect{magnitude = 6, conditional = Condition_Hull_Below{percent = 50}}
	s := Ship{max_hull = 20}

	s.hull = 20 // full: above the half-Hull threshold
	testing.expect_value(t, effect_magnitude(effect, ship_effect_context(&s)), Magnitude(0))

	s.hull = 10 // exactly half: strictly-below means still unmet
	testing.expect_value(t, effect_magnitude(effect, ship_effect_context(&s)), Magnitude(0))

	s.hull = 9 // below half: full magnitude
	testing.expect_value(t, effect_magnitude(effect, ship_effect_context(&s)), Magnitude(6))
}

@(test)
round_at_least_conditional_is_unmet_before_the_round_and_off_the_battlefield :: proc(t: ^testing.T) {
	effect := Effect{magnitude = 5, conditional = Condition_Round_At_Least{round = 3}}
	s := Ship{}

	// No battle state: a battle-state trigger is simply unmet off the battlefield.
	testing.expect_value(t, effect_magnitude(effect, ship_effect_context(&s)), Magnitude(0))

	testing.expect_value(t, effect_magnitude(effect, ship_effect_context_in_battle(&s, Battle_State{round = 2})), Magnitude(0))
	testing.expect_value(t, effect_magnitude(effect, ship_effect_context_in_battle(&s, Battle_State{round = 3})), Magnitude(5))
	testing.expect_value(t, effect_magnitude(effect, ship_effect_context_in_battle(&s, Battle_State{round = 9})), Magnitude(5))
}

@(test)
self_visibility_conditional_reads_the_slot_the_effect_is_resolved_for :: proc(t: ^testing.T) {
	effect := Effect{magnitude = 4, conditional = Condition_Self_Visibility{visibility = .Concealed}}
	s := Ship{}

	ctx := ship_effect_context(&s)
	// No self slot: unmet.
	testing.expect_value(t, effect_magnitude(effect, ctx), Magnitude(0))

	ctx.self_slot = Layout_Slot{slot = Slot{base_visibility = .Exposed}}
	testing.expect_value(t, effect_magnitude(effect, ctx), Magnitude(0))

	ctx.self_slot = Layout_Slot{slot = Slot{base_visibility = .Concealed}}
	testing.expect_value(t, effect_magnitude(effect, ctx), Magnitude(4))
}

@(test)
opponent_speed_conditionals_compare_the_live_battle_speeds :: proc(t: ^testing.T) {
	s := Ship{}
	faster := Effect{magnitude = 3, conditional = Condition_Opponent_Faster{}}
	slower := Effect{magnitude = 3, conditional = Condition_Opponent_Slower{}}

	// own_speed 5, opponent_speed 8: opponent is the faster side.
	quick_foe := ship_effect_context_in_battle(&s, Battle_State{round = 1, own_speed = 5, opponent_speed = 8})
	testing.expect_value(t, effect_magnitude(faster, quick_foe), Magnitude(3))
	testing.expect_value(t, effect_magnitude(slower, quick_foe), Magnitude(0))

	// own_speed 8, opponent_speed 5: opponent is the slower side.
	slow_foe := ship_effect_context_in_battle(&s, Battle_State{round = 1, own_speed = 8, opponent_speed = 5})
	testing.expect_value(t, effect_magnitude(faster, slow_foe), Magnitude(0))
	testing.expect_value(t, effect_magnitude(slower, slow_foe), Magnitude(3))

	// Equal speed: neither strict comparison holds.
	tie := ship_effect_context_in_battle(&s, Battle_State{round = 1, own_speed = 6, opponent_speed = 6})
	testing.expect_value(t, effect_magnitude(faster, tie), Magnitude(0))
	testing.expect_value(t, effect_magnitude(slower, tie), Magnitude(0))
}

@(test)
a_conditional_stat_modifier_applies_only_while_its_condition_holds :: proc(t: ^testing.T) {
	// A "below half Hull, +Durability" plating: the effective-stat readers gate it
	// through the same conditional seam, self_slot filled per slot.
	plating := Fitting{
		name = "Panic Plating", size = .Small,
		passive = Effect{kind = .Modify_Durability, magnitude = 5, conditional = Condition_Hull_Below{percent = 50}},
	}
	s := Ship{
		durability = 2, max_hull = 20,
		layout = []Layout_Slot{{slot = Slot{size = .Small}, fitting = plating}},
	}

	s.hull = 20 // above the threshold: raw durability only
	testing.expect_value(t, ship_effective_durability(&s), 2)

	s.hull = 8 // below the threshold: the +Durability kicks in
	testing.expect_value(t, ship_effective_durability(&s), 2 + 5)
}
