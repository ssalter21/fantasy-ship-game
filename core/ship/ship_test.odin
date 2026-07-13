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
cargo_capacity_includes_the_ships_captains_structural_bonus :: proc(t: ^testing.T) {
	s := Ship{
		base_cargo_capacity = 4,
		captain             = Captain{name = "Blackheart", cargo_capacity_bonus = 2},
	}

	testing.expect_value(t, ship_cargo_capacity(s), 6)
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
slot_by_category_finds_the_slot_holding_a_fitting_of_that_category :: proc(t: ^testing.T) {
	s := Ship{
		layout = []Layout_Slot{
			{slot = Slot{name = "top crew", size = .Medium, base_visibility = .Exposed}, fitting = Fitting{name = "Top Crew", size = .Medium, category = .Buff}},
			{slot = Slot{name = "gun deck", size = .Large, base_visibility = .Exposed}, fitting = Fitting{name = "Gun Deck", size = .Large, category = .Offensive}},
		},
	}

	found := ship_slot_by_category(&s, .Offensive)

	testing.expect(t, found != nil)
	installed, _ := found.fitting.?
	testing.expect_value(t, installed.name, "Gun Deck")
}

@(test)
slot_by_category_returns_nil_when_no_slot_holds_a_matching_fitting :: proc(t: ^testing.T) {
	s := Ship{
		layout = []Layout_Slot{
			{slot = Slot{name = "hold 1", size = .Small, base_visibility = .Concealed}, fitting = Fitting{name = "Cargo", size = .Small, is_cargo = true, stack_count = 1}},
		},
	}

	found := ship_slot_by_category(&s, .Offensive)

	testing.expect(t, found == nil)
}

@(test)
replace_fitting_swaps_an_occupied_slots_fitting_for_a_same_sized_one :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)
	ok := ship_fit(&layout_slot, Fitting{name = "Gun Deck", size = .Large})
	testing.expect(t, ok)

	replaced := ship_replace_fitting(&layout_slot, Fitting{name = "Upgraded Gun Deck", size = .Large})

	testing.expect(t, replaced)
	installed, _ := layout_slot.fitting.?
	testing.expect_value(t, installed.name, "Upgraded Gun Deck")
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
		fitting = Fitting{name = "War Kraken", size = .Large, category = .Offensive, tags = {.Beast, .Weapon}},
	}

	// Tag: a multi-tag fitting matches on each of its own tags, and misses a tag it lacks.
	testing.expect(t, selector_matches(slot, Selector(Tag.Beast)))
	testing.expect(t, selector_matches(slot, Selector(Tag.Weapon)))
	testing.expect(t, !selector_matches(slot, Selector(Tag.Crew)))
	// Size / Category: the fitting's own field.
	testing.expect(t, selector_matches(slot, Selector(Slot_Size.Large)))
	testing.expect(t, !selector_matches(slot, Selector(Slot_Size.Small)))
	testing.expect(t, selector_matches(slot, Selector(Category.Offensive)))
	testing.expect(t, !selector_matches(slot, Selector(Category.Buff)))
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
	// value is .Buff, and cargo / effect-less fittings never set it, so a
	// Selector(Category.Buff) counts every such fitting as a Buff. This test
	// pins that behavior down (ship_count_matching's doc caveat): a content
	// author selecting on .Buff must expect zero-value fittings in the count.
	s := synergy_ship(
		Fitting{name = "Top Crew", size = .Medium, category = .Buff},
		Fitting{name = "Gun Deck", size = .Large, category = .Offensive},
		Fitting{name = "Cargo", size = .Small, tags = {.Cargo}, is_cargo = true, stack_count = 1},
	)
	defer delete(s.layout)

	// Top Crew (explicit .Buff) and Cargo (zero-value .Buff) both count.
	testing.expect_value(t, ship_count_matching(&s, Selector(Category.Buff)), 2)
	testing.expect_value(t, ship_count_matching(&s, Selector(Category.Offensive)), 1)
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
	cannon := Fitting{name = "Cannon", size = .Large, category = .Offensive, active = Effect{magnitude = 10}}
	s := Ship{
		durability = 2, speed = 4, max_hp = 20,
		layout = []Layout_Slot{{slot = Slot{size = .Large}, fitting = cannon}},
	}

	testing.expect_value(t, ship_effective_durability(&s), 2)
	testing.expect_value(t, ship_effective_speed(&s), 4)
	testing.expect_value(t, ship_effective_max_hp(&s), 20)
}

@(test)
a_stat_modifier_fitting_raises_the_matching_effective_stat_only :: proc(t: ^testing.T) {
	reinforced := Fitting{
		name = "Reinforced Hull", size = .Small,
		passive = Effect{kind = .Modify_Durability, magnitude = 3},
	}
	s := Ship{
		durability = 2, speed = 4, max_hp = 20,
		layout = []Layout_Slot{{slot = Slot{size = .Small}, fitting = reinforced}},
	}

	testing.expect_value(t, ship_effective_durability(&s), 2 + 3)
	testing.expect_value(t, ship_effective_speed(&s), 4) // unaffected
	testing.expect_value(t, ship_effective_max_hp(&s), 20) // unaffected
}

@(test)
stat_modifiers_stack_across_slots_and_span_max_hp_and_speed :: proc(t: ^testing.T) {
	hull := Fitting{name = "Reinforced Hull", size = .Small, passive = Effect{kind = .Modify_Durability, magnitude = 3}}
	plating := Fitting{name = "Iron Plating", size = .Small, passive = Effect{kind = .Modify_Durability, magnitude = 2}}
	sails := Fitting{name = "Fast Sails", size = .Small, passive = Effect{kind = .Modify_Speed, magnitude = 4}}
	ballast := Fitting{name = "Ballast Tanks", size = .Small, passive = Effect{kind = .Modify_Max_HP, magnitude = 10}}
	s := Ship{
		durability = 1, speed = 5, max_hp = 20,
		layout = []Layout_Slot{
			{slot = Slot{size = .Small}, fitting = hull},
			{slot = Slot{size = .Small}, fitting = plating},
			{slot = Slot{size = .Small}, fitting = sails},
			{slot = Slot{size = .Small}, fitting = ballast},
		},
	}

	testing.expect_value(t, ship_effective_durability(&s), 1 + 3 + 2)
	testing.expect_value(t, ship_effective_speed(&s), 5 + 4)
	testing.expect_value(t, ship_effective_max_hp(&s), 20 + 10)
}

@(test)
replace_fitting_rejects_a_size_mismatch_and_leaves_the_original_installed :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)
	ok := ship_fit(&layout_slot, Fitting{name = "Gun Deck", size = .Large})
	testing.expect(t, ok)

	replaced := ship_replace_fitting(&layout_slot, Fitting{name = "Dagger", size = .Small})

	testing.expect(t, !replaced)
	installed, has_fitting := layout_slot.fitting.?
	testing.expect(t, has_fitting)
	testing.expect_value(t, installed.name, "Gun Deck")
}

@(test)
hp_below_conditional_resolves_to_zero_above_the_threshold_and_full_below :: proc(t: ^testing.T) {
	effect := Effect{magnitude = 6, conditional = Condition_HP_Below{percent = 50}}
	s := Ship{max_hp = 20}

	s.hp = 20 // full: above the half-HP threshold
	testing.expect_value(t, effect_magnitude(effect, ship_effect_context(&s)), Magnitude(0))

	s.hp = 10 // exactly half: strictly-below means still unmet
	testing.expect_value(t, effect_magnitude(effect, ship_effect_context(&s)), Magnitude(0))

	s.hp = 9 // below half: full magnitude
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
	// A "below half HP, +Durability" plating: the effective-stat readers gate it
	// through the same conditional seam, self_slot filled per slot.
	plating := Fitting{
		name = "Panic Plating", size = .Small,
		passive = Effect{kind = .Modify_Durability, magnitude = 5, conditional = Condition_HP_Below{percent = 50}},
	}
	s := Ship{
		durability = 2, max_hp = 20,
		layout = []Layout_Slot{{slot = Slot{size = .Small}, fitting = plating}},
	}

	s.hp = 20 // above the threshold: raw durability only
	testing.expect_value(t, ship_effective_durability(&s), 2)

	s.hp = 8 // below the threshold: the +Durability kicks in
	testing.expect_value(t, ship_effective_durability(&s), 2 + 5)
}
