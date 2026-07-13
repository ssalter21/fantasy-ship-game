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
ship_template_layout_has_eight_slots_two_large_three_medium_three_small_split_four_exposed_four_concealed :: proc(t: ^testing.T) {
	layout := ship_template_layout()
	defer delete(layout)

	testing.expect_value(t, len(layout), 8)

	large, medium, small := 0, 0, 0
	exposed, concealed := 0, 0
	for layout_slot in layout {
		switch layout_slot.slot.size {
		case .Large:
			large += 1
		case .Medium:
			medium += 1
		case .Small:
			small += 1
		}
		switch layout_slot.slot.base_visibility {
		case .Exposed:
			exposed += 1
		case .Concealed:
			concealed += 1
		}
	}

	testing.expect_value(t, large, 2)
	testing.expect_value(t, medium, 3)
	testing.expect_value(t, small, 3)
	testing.expect_value(t, exposed, 4)
	testing.expect_value(t, concealed, 4)
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
	testing.expect_value(t, concealed_count, 4)
}

// Every slot the starting loadout doesn't spend on a combat fitting becomes
// cargo, whatever its size (issue #91): the expanded hull leaves an exposed
// Large and a concealed Medium open alongside the small holds, and all of them
// must fill with a size-matching cargo filler rather than sit idle.
@(test)
ship_starting_ship_fills_every_non_combat_slot_with_size_matching_cargo :: proc(t: ^testing.T) {
	s := ship_starting_ship()
	defer delete(s.layout)

	saw_size := [Slot_Size]bool{}
	for layout_slot in s.layout {
		fitting, has_fitting := layout_slot.fitting.?
		testing.expect(t, has_fitting)
		if !fitting.is_cargo {
			continue
		}
		testing.expect_value(t, fitting.size, layout_slot.slot.size)
		saw_size[layout_slot.slot.size] = true
	}

	// Cargo fills slots of all three sizes now, not just Small.
	testing.expect(t, saw_size[.Small])
	testing.expect(t, saw_size[.Medium])
	testing.expect(t, saw_size[.Large])
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
the_three_starting_fittings_and_cargo_carry_their_families :: proc(t: ^testing.T) {
	testing.expect_value(t, ship_fitting_top_crew().tags, bit_set[Tag]{.Crew})
	testing.expect_value(t, ship_fitting_captains_quarters().tags, bit_set[Tag]{.Crew})
	testing.expect_value(t, ship_fitting_gun_deck().tags, bit_set[Tag]{.Weapon})
	testing.expect_value(t, ship_fitting_cargo("Cargo", .Small).tags, bit_set[Tag]{.Cargo})
}

@(test)
an_upgraded_fitting_inherits_its_base_fittings_families :: proc(t: ^testing.T) {
	testing.expect_value(t, ship_fitting_upgraded_top_crew(1).tags, ship_fitting_top_crew().tags)
	testing.expect_value(t, ship_fitting_upgraded_captains_quarters(1).tags, ship_fitting_captains_quarters().tags)
	testing.expect_value(t, ship_fitting_upgraded_gun_deck(1).tags, ship_fitting_gun_deck().tags)
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

// --- The ~50-item roster (issue #97, ADR-0012) ---

// roster_item_named finds the one Roster_Item with `name`, panicking if the
// catalog has no such item — the tests below name specific representative items
// and want a loud failure if one is renamed out from under them rather than a
// silent zero value.
roster_item_named :: proc(name: string) -> Roster_Item {
	for item in ship_item_roster() {
		if item.fitting.name == name {
			return item
		}
	}
	panic("roster item not found")
}

// bare_test_ship is an empty template-layout ship the behavior tests install a
// single roster item into, so an effect resolves against a known layout rather
// than the starting loadout's fittings. Caller owns the layout slice.
bare_test_ship :: proc() -> Ship {
	return Ship{hp = 20, max_hp = 20, durability = 2, speed = 4, layout = ship_template_layout()}
}

// fit_first_matching_size installs `fitting` into the first empty slot of its
// size, so a test can drop items onto the ship without hand-picking slot indices
// (every roster item's size exists in the template — Large x2 / Medium x3 /
// Small x3).
fit_first_matching_size :: proc(s: ^Ship, fitting: Fitting) {
	for &layout_slot in s.layout {
		if layout_slot.slot.size != fitting.size {
			continue
		}
		if _, occupied := layout_slot.fitting.?; occupied {
			continue
		}
		ship_fit(&layout_slot, fitting)
		return
	}
	panic("no empty slot of the fitting's size")
}

@(test)
the_item_roster_is_about_fifty_distinct_placeable_items :: proc(t: ^testing.T) {
	roster := ship_item_roster()

	// ADR-0012 targets "~50"; the pool must clear the offer's option count so an
	// offer can present that many distinct items (run.ITEM_OFFER_OPTION_COUNT).
	testing.expect_value(t, len(roster), ITEM_ROSTER_SIZE)
	testing.expect(t, ITEM_ROSTER_SIZE >= 45)

	for item, i in roster {
		f := item.fitting
		testing.expect(t, len(f.name) > 0)
		// A roster item is a real placeable fitting, not a cargo filler.
		testing.expect(t, !f.is_cargo)
		// Every item carries at least one tag family and exactly one effect
		// (in either the passive or the active slot, not both).
		testing.expect(t, f.tags != {})
		_, has_passive := f.passive.?
		_, has_active := f.active.?
		testing.expect(t, has_passive != has_active)
		// Names are distinct (the Item Offer presents distinct items by name).
		for other, j in roster {
			if i != j {
				testing.expect(t, f.name != other.fitting.name)
			}
		}
	}
}

@(test)
the_item_roster_spans_all_three_tiers :: proc(t: ^testing.T) {
	seen: [Tier]bool
	for item in ship_item_roster() {
		seen[item.tier] = true
	}
	for tier in Tier {
		testing.expect(t, seen[tier])
	}
}

@(test)
the_item_roster_spans_all_families_sizes_and_phases :: proc(t: ^testing.T) {
	seen_family: [Tag]bool
	seen_size: [Slot_Size]bool
	seen_phase: [Category]bool
	for item in ship_item_roster() {
		f := item.fitting
		for tag in Tag {
			if tag in f.tags {
				seen_family[tag] = true
			}
		}
		seen_size[f.size] = true
		seen_phase[f.category] = true
	}
	for tag in Tag {
		testing.expect(t, seen_family[tag])
	}
	for size in Slot_Size {
		testing.expect(t, seen_size[size])
	}
	for phase in Category {
		testing.expect(t, seen_phase[phase])
	}
}

@(test)
the_item_roster_uses_the_whole_effect_vocabulary :: proc(t: ^testing.T) {
	saw_flat, saw_stat_mod, saw_synergy, saw_conditional, saw_multi_tag: bool
	for item in ship_item_roster() {
		f := item.fitting
		if card(f.tags) > 1 {
			saw_multi_tag = true
		}
		for maybe_effect in ([2]Maybe(Effect){f.passive, f.active}) {
			effect, ok := maybe_effect.?
			if !ok {
				continue
			}
			if effect.kind != .Phase_Contribution {
				saw_stat_mod = true
			}
			if _, is_synergy := effect.synergy.?; is_synergy {
				saw_synergy = true
			}
			if _, is_conditional := effect.conditional.?; is_conditional {
				saw_conditional = true
			}
			if effect.kind == .Phase_Contribution && effect.synergy == nil && effect.conditional == nil {
				saw_flat = true
			}
		}
	}
	testing.expect(t, saw_flat)
	testing.expect(t, saw_stat_mod)
	testing.expect(t, saw_synergy)
	testing.expect(t, saw_conditional)
	testing.expect(t, saw_multi_tag)
}

// Representative behavior, one item per tier, each exercising a different effect
// kind — a Splash synergy, a Shallow stat-modifier, and a Deep conditional —
// confirming the authored items resolve the way their catalog intent describes.

@(test)
splash_powder_monkeys_buff_scales_with_weapons_aboard :: proc(t: ^testing.T) {
	item := roster_item_named("Powder Monkeys")
	testing.expect_value(t, item.tier, Tier.Splash)
	active, _ := item.fitting.active.?

	s := bare_test_ship()
	defer delete(s.layout)
	fit_first_matching_size(&s, item.fitting)
	ctx := ship_effect_context(&s)

	// No Weapons aboard yet (Powder Monkeys itself is Crew): the synergy is 0.
	testing.expect_value(t, effect_magnitude(active, ctx), Magnitude(0))

	// Each Weapon added lifts it by the per-unit magnitude.
	fit_first_matching_size(&s, roster_item_named("Swivel Guns").fitting) // Weapon
	fit_first_matching_size(&s, roster_item_named("Deck Cannon").fitting) // Weapon
	testing.expect_value(t, effect_magnitude(active, ctx), active.magnitude * 2)
}

@(test)
shallow_reinforced_hull_raises_effective_durability :: proc(t: ^testing.T) {
	item := roster_item_named("Reinforced Hull")
	testing.expect_value(t, item.tier, Tier.Shallow)
	passive, _ := item.fitting.passive.?

	s := bare_test_ship()
	defer delete(s.layout)
	base := ship_effective_durability(&s)
	fit_first_matching_size(&s, item.fitting)

	// The stat-modifier lifts effective Durability by its magnitude, not a phase.
	testing.expect_value(t, ship_effective_durability(&s), base + int(passive.magnitude))
}

@(test)
deep_cornered_beast_only_bites_below_half_hp :: proc(t: ^testing.T) {
	item := roster_item_named("Cornered Beast")
	testing.expect_value(t, item.tier, Tier.Deep)
	active, _ := item.fitting.active.?

	s := bare_test_ship()
	defer delete(s.layout)
	fit_first_matching_size(&s, item.fitting)
	ctx := ship_effect_context(&s)

	// At full HP the conditional contributes nothing; below half it resolves to
	// its full magnitude.
	s.hp = s.max_hp
	testing.expect_value(t, effect_magnitude(active, ctx), Magnitude(0))
	s.hp = s.max_hp / 2 - 1
	testing.expect_value(t, effect_magnitude(active, ctx), active.magnitude)
}
