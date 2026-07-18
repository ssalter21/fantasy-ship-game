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

// The starting cargo is stowed smallest-first (ADR-0020, #172), not spread across
// every free slot: the three small holds and the concealed medium fill to exactly
// 50, while the exposed Large forecastle is left **empty** as visible headroom —
// the player starts at the fine end of the jettison-granularity property (#157),
// with room a Reward can fall into before it costs a payout.
@(test)
ship_starting_ship_stows_the_starting_cargo_smallest_first_leaving_the_large_empty :: proc(t: ^testing.T) {
	s := ship_starting_ship()
	defer delete(s.layout)

	// Every cargo fitting matches its slot size; cargo lands in the Small and Medium
	// holds, never the Large forecastle.
	saw_size := [Slot_Size]bool{}
	for layout_slot in s.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting || !fitting.is_cargo {
			continue
		}
		testing.expect_value(t, fitting.size, layout_slot.slot.size)
		saw_size[layout_slot.slot.size] = true
	}
	testing.expect(t, saw_size[.Small])
	testing.expect(t, saw_size[.Medium])
	testing.expect(t, !saw_size[.Large]) // the forecastle is headroom, not stowed

	// The exposed Large forecastle is empty, and the whole cargo is exactly 50.
	forecastle := find_slot(s, "forecastle")
	_, forecastle_filled := forecastle.fitting.?
	testing.expect(t, !forecastle_filled)
	testing.expect_value(t, ship_cargo(s), STARTING_CARGO + CAPTAIN_STARTING_CARGO)
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
	testing.expect_value(t, ship_fitting_cargo("Cargo", .Small, 10).tags, bit_set[Tag]{.Cargo})
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

@(test)
the_item_roster_is_about_fifty_distinct_placeable_items :: proc(t: ^testing.T) {
	roster := ship_item_roster()

	// ADR-0012 targets "~50"; the pool must clear the offer's option count so an
	// offer can present that many distinct items (voyage.ITEM_OFFER_OPTION_COUNT).
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
shop_item_cost_rises_strictly_with_tier :: proc(t: ^testing.T) {
	// #98: tier prices a shop item, weakest-to-strongest, and the whole ladder
	// sits under the starting cargo so the fixed budget bites — a Deep item costs
	// most, and even it is affordable from a full cargo. "A full cargo" is now
	// *derived* from the stow amounts (ADR-0020): STARTING_CARGO + the captain's
	// bonus, not a single standalone constant, so `45 <= 50` stays true rather than
	// silently inverting against the 40 hull constant (`45 <= 40` would fail).
	full_cargo :: STARTING_CARGO + CAPTAIN_STARTING_CARGO
	splash := ship_item_cost(.Splash)
	shallow := ship_item_cost(.Shallow)
	deep := ship_item_cost(.Deep)
	testing.expect(t, splash < shallow)
	testing.expect(t, shallow < deep)
	testing.expect(t, deep <= full_cargo) // a full cargo can buy one Deep item
	// But not two: the budget is deliberately tight enough that a second buy can
	// be unaffordable, so "an unaffordable item cannot be bought" is reachable.
	testing.expect(t, deep + splash > full_cargo)
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
// Each builds its ship with synergy_ship (ship_test.odin), the package's bare
// install-these-fittings test helper.

@(test)
splash_powder_monkeys_offense_scales_with_weapons_aboard :: proc(t: ^testing.T) {
	item := roster_item_named("Powder Monkeys")
	testing.expect_value(t, item.tier, Tier.Splash)
	active, _ := item.fitting.active.?

	// No Weapons aboard (Powder Monkeys itself is Crew): the synergy is 0.
	alone := synergy_ship(item.fitting)
	defer delete(alone.layout)
	testing.expect_value(t, effect_magnitude(active, ship_effect_context(&alone)), Magnitude(0))

	// Each Weapon aboard lifts it by the per-unit magnitude.
	armed := synergy_ship(item.fitting, roster_item_named("Swivel Guns").fitting, roster_item_named("Deck Cannon").fitting)
	defer delete(armed.layout)
	testing.expect_value(t, effect_magnitude(active, ship_effect_context(&armed)), active.magnitude * 2)
}

@(test)
shallow_reinforced_hull_raises_effective_durability :: proc(t: ^testing.T) {
	item := roster_item_named("Reinforced Hull")
	testing.expect_value(t, item.tier, Tier.Shallow)
	passive, _ := item.fitting.passive.?

	bare := synergy_ship()
	defer delete(bare.layout)
	base := ship_effective_durability(&bare)

	hulled := synergy_ship(item.fitting)
	defer delete(hulled.layout)

	// The stat-modifier lifts effective Durability by its magnitude, not a phase.
	testing.expect_value(t, ship_effective_durability(&hulled), base + int(passive.magnitude))
}

@(test)
deep_cornered_beast_only_bites_below_half_hull :: proc(t: ^testing.T) {
	item := roster_item_named("Cornered Beast")
	testing.expect_value(t, item.tier, Tier.Deep)
	active, _ := item.fitting.active.?

	s := synergy_ship(item.fitting)
	defer delete(s.layout)
	s.max_hull = 20
	ctx := ship_effect_context(&s)

	// At full Hull the conditional contributes nothing; below half it resolves to
	// its full magnitude.
	s.hull = s.max_hull
	testing.expect_value(t, effect_magnitude(active, ctx), Magnitude(0))
	s.hull = s.max_hull / 2 - 1
	testing.expect_value(t, effect_magnitude(active, ctx), active.magnitude)
}

// --- Roster lookup and first-empty fitting (issue #135) ----------------------

// The lookup that lets a content table name the items it is built from. Every
// roster item must be findable by the name it was authored under, and a name that
// isn't in the roster must miss rather than return a zero Roster_Item as if it hit.
@(test)
ship_item_by_name_finds_every_roster_item_and_misses_on_anything_else :: proc(t: ^testing.T) {
	for item in ship_item_roster() {
		found, ok := ship_item_by_name(item.fitting.name)
		testing.expectf(t, ok, "%q is in the roster but ship_item_by_name missed it", item.fitting.name)
		testing.expect_value(t, found.fitting.name, item.fitting.name)
		testing.expect_value(t, found.tier, item.tier)
	}

	_, ok := ship_item_by_name("Not A Real Fitting")
	testing.expect(t, !ok)
}

// First-empty-fit is what lets a loadout be authored as an ordered list of fittings
// rather than as slot assignments: each item takes the earliest free slot of its
// own size, and sizes don't poach each other's slots.
@(test)
ship_fit_first_empty_slot_takes_the_earliest_free_slot_of_matching_size :: proc(t: ^testing.T) {
	layout := ship_template_layout()
	defer delete(layout)

	// "top deck" is the first Medium; the next Medium goes to "top crew".
	testing.expect(t, ship_fit_first_empty_slot(layout, ship_fitting_captains_quarters()))
	testing.expect_value(t, occupant_name(layout, "top deck"), "Captain's Quarters")
	testing.expect(t, ship_fit_first_empty_slot(layout, ship_fitting_top_crew()))
	testing.expect_value(t, occupant_name(layout, "top crew"), "Top Crew")

	// A Large skips both Mediums entirely and lands in "gun deck".
	testing.expect(t, ship_fit_first_empty_slot(layout, ship_fitting_gun_deck()))
	testing.expect_value(t, occupant_name(layout, "gun deck"), "Gun Deck")
}

// The template holds Medium x3 (two exposed, then the concealed "hold 1"), so a
// third Medium falls into the hold. That fallback is content-visible — it is what
// decides whether a Condition_Self_Visibility effect fires — so it is pinned here
// rather than left as an accident of slot order. core/voyage's Smuggler's Run archetype
// is built on exactly this.
@(test)
ship_fit_first_empty_slot_falls_back_from_exposed_slots_to_the_concealed_hold :: proc(t: ^testing.T) {
	layout := ship_template_layout()
	defer delete(layout)

	medium :: proc(name: string) -> Fitting {
		return Fitting{name = name, size = .Medium, category = .Fire, active = Effect{magnitude = 1}}
	}
	testing.expect(t, ship_fit_first_empty_slot(layout, medium("first")))
	testing.expect(t, ship_fit_first_empty_slot(layout, medium("second")))
	testing.expect(t, ship_fit_first_empty_slot(layout, medium("third")))

	testing.expect_value(t, occupant_name(layout, "top deck"), "first")
	testing.expect_value(t, occupant_name(layout, "top crew"), "second")
	// The third lands concealed, which is the whole point.
	testing.expect_value(t, occupant_name(layout, "hold 1"), "third")
	testing.expect_value(t, find_layout_slot(layout, "hold 1").slot.base_visibility, Visibility.Concealed)

	// A fourth Medium has nowhere left to go, and says so rather than displacing one.
	testing.expect(t, !ship_fit_first_empty_slot(layout, medium("fourth")))
}

find_layout_slot :: proc(layout: []Layout_Slot, slot_name: string) -> Layout_Slot {
	for layout_slot in layout {
		if layout_slot.slot.name == slot_name {
			return layout_slot
		}
	}
	return {}
}

occupant_name :: proc(layout: []Layout_Slot, slot_name: string) -> string {
	fitting, has_fitting := find_layout_slot(layout, slot_name).fitting.?
	if !has_fitting {
		return ""
	}
	return fitting.name
}

// --- ship_fitting_output_scaled (issue #165) ---------------------------------

// **A Modify_* effect is not output, and must survive a scaling untouched.** This is
// the property core/voyage's Fight stakes leans on rather than a nicety: it scales whole
// Categories, and `.Fire` holds every Modify_Speed item in the roster (Spare Rigging,
// Copper Sheathing, Outriggers, Enchanted Keel) alongside the damage fittings. A
// hostile's Speed is its archetype's axis, explicitly not a stakes
// reading — so if this proc ever started scaling by category rather than by effect,
// a Deep node would hand a hostile more Speed than a Coastal one and quietly decide
// who is allowed to break off (combat_may_break_off is *strictly faster*).
@(test)
ship_fitting_output_scaled_moves_phase_contributions_and_leaves_stat_modifiers_alone :: proc(t: ^testing.T) {
	rigging := Fitting{name = "Spare Rigging", size = .Small, category = .Fire, passive = Effect{kind = .Modify_Speed, magnitude = 2}}
	halved := ship_fitting_output_scaled(rigging, 50)
	passive, has_passive := halved.passive.?
	testing.expect(t, has_passive)
	testing.expect_value(t, passive.magnitude, Magnitude(2)) // a stat modifier is not output

	gun := Fitting{name = "Long Nines", size = .Large, category = .Fire, active = Effect{magnitude = 8}}
	active, has_active := ship_fitting_output_scaled(gun, 50).active.?
	testing.expect(t, has_active)
	testing.expect_value(t, active.magnitude, Magnitude(4))
}

// A scaling preserves everything about an effect except its strength — the selector,
// the condition and the kind all ride through — so a synergy stays a synergy and only
// its per-match magnitude moves. That is what makes the scaling proportional to what
// a fitting deals rather than to the build around it: `(m x pct) x count`.
@(test)
ship_fitting_output_scaled_keeps_an_effects_character_and_moves_only_its_strength :: proc(t: ^testing.T) {
	guard := Fitting {
		name     = "Admiral's Guard",
		size     = .Medium,
		category = .Fire,
		active   = Effect{magnitude = 4, synergy = Selector(Tag.Crew), conditional = Condition_Hull_Below{percent = 50}},
	}

	scaled, _ := ship_fitting_output_scaled(guard, 50).active.?
	testing.expect_value(t, scaled.magnitude, Magnitude(2))
	testing.expect_value(t, scaled.kind, Effect_Kind.Phase_Contribution)
	testing.expect_value(t, scaled.synergy.?, Selector(Tag.Crew))
	testing.expect_value(t, scaled.conditional.?, Condition(Condition_Hull_Below{percent = 50}))
}

// **Rounds half-up, so a scale-down cannot silently disarm the roster's smallest
// fittings.** Powder Monkeys is a magnitude of 1; truncating would take it to 0 and
// delete a fitting from the game at Coastal rather than weaken it. 100 is the identity
// — the property that lets the hostile roster's entries mean exactly what they say at
// the zone they are authored for (ADR-0019).
@(test)
ship_fitting_output_scaled_rounds_half_up_and_is_the_identity_at_a_hundred :: proc(t: ^testing.T) {
	monkeys := Fitting{name = "Powder Monkeys", size = .Small, category = .Fire, active = Effect{magnitude = 1, synergy = Selector(Tag.Weapon)}}
	halved, _ := ship_fitting_output_scaled(monkeys, 50).active.?
	testing.expect_value(t, halved.magnitude, Magnitude(1)) // 0.5 rounds up, not away

	swivel := Fitting{name = "Swivel Guns", size = .Small, category = .Fire, active = Effect{magnitude = 3}}
	up, _ := ship_fitting_output_scaled(swivel, 50).active.?
	testing.expect_value(t, up.magnitude, Magnitude(2)) // 1.5 rounds up

	testing.expect_value(t, ship_fitting_output_scaled(swivel, 100), swivel)

	// A cargo filler carries no effect at all and is returned untouched.
	filler := ship_fitting_cargo("Spoils", .Small, 10)
	testing.expect_value(t, ship_fitting_output_scaled(filler, 50), filler)
}
