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
		testing.expect(t, ship_fitting_is_hold(fitting))
	}
	testing.expect_value(t, concealed_count, 4)
}

// The starting ship ships with **holds in all five free slots**, forecastle included.
// It has to: an empty slot carries nothing now (ship_cargo_capacity), so leaving the
// forecastle empty as "headroom" would be leaving 40 of capacity behind rather than
// reserving it. The five holds total exactly 90 — the same capacity the old
// empty-slots-count rule read — so the starting ship's observable state does not move.
@(test)
ship_starting_ship_holds_every_free_slot_and_still_reads_ninety_capacity :: proc(t: ^testing.T) {
	s := ship_starting_ship()
	defer delete(s.layout)

	// Every slot is filled, and every slot the loadout did not claim carries a hold
	// sized to it.
	holds := 0
	for layout_slot in s.layout {
		fitting, has_fitting := layout_slot.fitting.?
		testing.expect(t, has_fitting)
		testing.expect_value(t, fitting.size, layout_slot.slot.size)
		if ship_fitting_is_hold(fitting) {
			holds += 1
		}
	}
	testing.expect_value(t, holds, 5)

	// The forecastle is one of them, and it carries — headroom is a hold now.
	forecastle, forecastle_filled := find_slot(s, "forecastle").fitting.?
	testing.expect(t, forecastle_filled)
	testing.expect(t, ship_fitting_is_hold(forecastle))

	testing.expect_value(t, ship_cargo_capacity(s), 90) // 40 + 20 + 3×10
	testing.expect_value(t, ship_cargo(s), STARTING_CARGO + CAPTAIN_STARTING_CARGO)
}

// Water-filling spreads the starting 50 evenly rather than packing the small holds:
// five destinations, an equal share of 10 apiece, which is exactly the Smalls' whole
// capacity. That is what stops a poor ship heaving a full Small for a Speed gain a
// rich one has to buy with a whole Large.
@(test)
ship_starting_ship_water_fills_its_cargo_evenly :: proc(t: ^testing.T) {
	s := ship_starting_ship()
	defer delete(s.layout)

	for layout_slot in s.layout {
		fitting, _ := layout_slot.fitting.?
		expected := ship_fitting_is_hold(fitting) ? 10 : 0
		testing.expect_value(t, fitting.cargo_held, expected)
	}
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
	testing.expect_value(t, ship_fitting_hold(.Small).tags, bit_set[Tag]{.Cargo})
}

@(test)
an_upgraded_fitting_inherits_its_base_fittings_families :: proc(t: ^testing.T) {
	testing.expect_value(t, ship_fitting_upgraded_top_crew(1).tags, ship_fitting_top_crew().tags)
	testing.expect_value(t, ship_fitting_upgraded_captains_quarters(1).tags, ship_fitting_captains_quarters().tags)
	testing.expect_value(t, ship_fitting_upgraded_gun_deck(1).tags, ship_fitting_gun_deck().tags)
}

@(test)
upgraded_top_crew_keeps_size_and_phase_but_out_magnitudes_the_base_fitting :: proc(t: ^testing.T) {
	base := ship_fitting_top_crew()
	upgraded := ship_fitting_upgraded_top_crew(1)

	testing.expect_value(t, upgraded.size, base.size)
	testing.expect_value(t, ship_fitting_phases(upgraded), ship_fitting_phases(base))
	testing.expect(t, effect_showcase_magnitude(upgraded.effects[0]) > effect_showcase_magnitude(base.effects[0]))
}

@(test)
upgraded_captains_quarters_keeps_size_and_phase_but_out_magnitudes_the_base_fitting :: proc(t: ^testing.T) {
	base := ship_fitting_captains_quarters()
	upgraded := ship_fitting_upgraded_captains_quarters(1)

	testing.expect_value(t, upgraded.size, base.size)
	testing.expect_value(t, ship_fitting_phases(upgraded), ship_fitting_phases(base))
	testing.expect(t, effect_showcase_magnitude(upgraded.effects[0]) > effect_showcase_magnitude(base.effects[0]))
}

@(test)
upgraded_gun_deck_keeps_size_and_phase_but_out_magnitudes_the_base_fitting :: proc(t: ^testing.T) {
	base := ship_fitting_gun_deck()
	upgraded := ship_fitting_upgraded_gun_deck(1)

	testing.expect_value(t, upgraded.size, base.size)
	testing.expect_value(t, ship_fitting_phases(upgraded), ship_fitting_phases(base))
	testing.expect(t, effect_showcase_magnitude(upgraded.effects[0]) > effect_showcase_magnitude(base.effects[0]))
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

// Every roster item authors its full slot contribution as `bulk`, so none of them
// carries — which is what makes the roster free of the cargo axis: capacity is an
// authored power source nothing has yet spent on. roster_item's default supplies it,
// so this catches the entry that names a `bulk` of its own and lands on the carrying
// end of the axis, handing the budget capacity it never priced.
@(test)
the_roster_carries_nothing :: proc(t: ^testing.T) {
	for item in ship_item_roster() {
		f := item.fitting
		testing.expectf(
			t,
			ship_fitting_capacity(f) == 0,
			"%v authors bulk %v in a %v slot, so it carries %v — every roster item must author its full contribution",
			f.name,
			f.bulk,
			f.size,
			ship_fitting_capacity(f),
		)
	}
}

@(test)
the_item_roster_is_about_fifty_distinct_placeable_items :: proc(t: ^testing.T) {
	roster := ship_item_roster()

	// ADR-0012 targets "~50"; the pool must clear the offer's option count so an
	// offer can present that many distinct items (voyage.ITEM_OFFER_OPTION_COUNT).
	// The size is derived from the item list (ITEM_ROSTER_SIZE), so this line is the
	// only thing an appended item has to answer to: the fifty-first is a conversation
	// — about the shop pools and offer draws sized against the count — rather than a
	// silent widening.
	testing.expect_value(t, ITEM_ROSTER_SIZE, 50)
	testing.expect_value(t, len(roster), ITEM_ROSTER_SIZE)

	for item, i in roster {
		f := item.fitting
		testing.expect(t, len(f.name) > 0)
		// A roster item is authored, so it arrives carrying nothing.
		testing.expect_value(t, f.cargo_held, 0)
		// Every item carries at least one tag family and between one effect and the cap.
		testing.expect(t, f.tags != {})
		testing.expectf(
			t,
			f.effect_count > 0 && f.effect_count <= FITTING_MAX_EFFECTS,
			"%v carries %v effects, outside 1..%v",
			f.name,
			f.effect_count,
			FITTING_MAX_EFFECTS,
		)
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
	seen_phase: [Phase]bool
	for item in ship_item_roster() {
		f := item.fitting
		for tag in Tag {
			if tag in f.tags {
				seen_family[tag] = true
			}
		}
		seen_size[f.size] = true
		for phase in ship_fitting_phases(f) {
			seen_phase[phase] = true
		}
	}
	for tag in Tag {
		testing.expect(t, seen_family[tag])
	}
	for size in Slot_Size {
		testing.expect(t, seen_size[size])
	}
	for phase in Phase {
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
		for i in 0 ..< f.effect_count {
			effect := f.effects[i]
			if effect.verb != .Phase_Contribution {
				saw_stat_mod = true
			}
			if _, is_synergy := effect.synergy.?; is_synergy {
				saw_synergy = true
			}
			if expr_is_conditional(effect.magnitude) {
				saw_conditional = true
			}
			if effect.verb == .Phase_Contribution && effect.synergy == nil && !expr_is_conditional(effect.magnitude) {
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
splash_powder_monkeys_offense_scales_with_the_small_berths_aboard :: proc(t: ^testing.T) {
	item := roster_item_named("Powder Monkeys")
	testing.expect_value(t, item.tier, Tier.Splash)
	active := item.fitting.effects[0]

	// Alone: the one Small berth aboard is its own.
	alone := synergy_ship(item.fitting)
	defer delete(alone.layout)
	testing.expect_value(t, effect_magnitude(active, ship_effect_context(&alone)), Magnitude(effect_showcase_magnitude(active)))

	// Each further Small berth lifts it by the per-unit magnitude, and a berth of
	// another size is none of its business.
	crowded := synergy_ship(item.fitting, roster_item_named("Swivel Guns").fitting, roster_item_named("Deck Cannon").fitting)
	defer delete(crowded.layout)
	testing.expect_value(t, effect_magnitude(active, ship_effect_context(&crowded)), Magnitude(effect_showcase_magnitude(active) * 2))
}

// **An effect's phase is its verb's phase** (ADR-0027). Combat routes on the phase an
// effect names (combat_phase_output), so an effect whose phase disagreed with its verb
// would repair in the damage phase or be silently inert — which is why nothing authors the
// pair by hand and every effect_* helper sets it from ship_verb_phase. This is the guard
// that a hand-built literal has not slipped past them.
@(test)
every_authored_effect_names_its_verbs_phase :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, f: Fitting) {
		for i in 0 ..< f.effect_count {
			effect := f.effects[i]
			testing.expectf(
				t,
				effect.phase == ship_verb_phase(effect.verb),
				"%v carries a %v effect on the wrong phase — nothing resolves it",
				f.name, effect.verb,
			)
		}
	}

	for item in ship_item_roster() {
		check(t, item.fitting)
	}
	for f in ([]Fitting{ship_fitting_top_crew(), ship_fitting_captains_quarters(), ship_fitting_gun_deck()}) {
		check(t, f)
	}
}

// Brace holds real content: the phase a captain can press has items to press (ADR-0027).
@(test)
the_roster_authors_repair_items_at_every_tier :: proc(t: ^testing.T) {
	repairs: [Tier]int
	for item in ship_item_roster() {
		for i in 0 ..< item.fitting.effect_count {
			if item.fitting.effects[i].verb == .Repair {
				repairs[item.tier] += 1
			}
		}
	}
	for tier in Tier {
		testing.expectf(t, repairs[tier] > 0, "no %v repair item: Brace has nothing to press at that tier", tier)
	}
}

@(test)
deep_cornered_beast_only_bites_below_half_hull :: proc(t: ^testing.T) {
	item := roster_item_named("Cornered Beast")
	testing.expect_value(t, item.tier, Tier.Deep)
	active := item.fitting.effects[0]

	s := synergy_ship(item.fitting)
	defer delete(s.layout)
	s.max_hull = 20
	ctx := ship_effect_context(&s)

	// At full Hull the conditional contributes nothing; below half it resolves to
	// its full magnitude.
	s.hull = s.max_hull
	testing.expect_value(t, effect_magnitude(active, ctx), Magnitude(0))
	s.hull = s.max_hull / 2 - 1
	testing.expect_value(t, effect_magnitude(active, ctx), Magnitude(effect_showcase_magnitude(active)))
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
		return ship_fitting_with_effects(Fitting{name = name, size = .Medium}, effect_phase_contribution(expr_const(1)))
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
	rigging := ship_fitting_with_effects(Fitting{name = "Spare Rigging", size = .Small}, effect_modify_speed(expr_const(2)))
	halved := ship_fitting_output_scaled(rigging, 50)
	testing.expect_value(t, effect_showcase_magnitude(halved.effects[0]), 2) // a stat modifier is not output

	gun := ship_fitting_with_effects(Fitting{name = "Long Nines", size = .Large}, effect_phase_contribution(expr_const(8)))
	testing.expect_value(t, effect_showcase_magnitude(ship_fitting_output_scaled(gun, 50).effects[0]), 4)
}

// A scaling preserves everything about an effect except its strength — the selector, the
// tree and the kind all ride through untouched, with the scale riding beside them — so a
// synergy stays a synergy and a gate's threshold is still the number it was authored as.
// That is what makes the scaling proportional to what a fitting deals rather than to the
// build around it: `(m x pct) x count`.
@(test)
ship_fitting_output_scaled_keeps_an_effects_character_and_moves_only_its_strength :: proc(t: ^testing.T) {
	guard := ship_fitting_with_effects(Fitting{name = "Admiral's Guard", size = .Medium}, effect_phase_contribution(expr_below_hull_percent(50, 4), Selector(Tag.Crew)))

	scaled := ship_fitting_output_scaled(guard, 50).effects[0]
	testing.expect_value(t, effect_showcase_magnitude(scaled), 2)
	testing.expect_value(t, scaled.verb, Verb.Phase_Contribution)
	testing.expect_value(t, scaled.synergy.?, Selector(Tag.Crew))
	// The authored tree is the same tree: the 50%-Hull threshold inside it did not move
	// with the item's strength.
	testing.expect_value(t, scaled.magnitude, expr_below_hull_percent(50, 4))
}

// **Rounds half-up, so a scale-down cannot silently disarm the roster's smallest
// fittings.** Powder Monkeys is a magnitude of 1; truncating would take it to 0 and
// delete a fitting from the game at Coastal rather than weaken it. 100 is the identity
// — the property that lets the hostile roster's entries mean exactly what they say at
// the zone they are authored for (ADR-0019).
@(test)
ship_fitting_output_scaled_rounds_half_up_and_is_the_identity_at_a_hundred :: proc(t: ^testing.T) {
	monkeys := ship_fitting_with_effects(Fitting{name = "Powder Monkeys", size = .Small}, effect_phase_contribution(expr_const(1), Selector(Tag.Weapon)))
	halved := ship_fitting_output_scaled(monkeys, 50).effects[0]
	testing.expect_value(t, effect_showcase_magnitude(halved), 1) // 0.5 rounds up, not away

	swivel := ship_fitting_with_effects(Fitting{name = "Swivel Guns", size = .Small}, effect_phase_contribution(expr_const(3)))
	up := ship_fitting_output_scaled(swivel, 50).effects[0]
	testing.expect_value(t, effect_showcase_magnitude(up), 2) // 1.5 rounds up

	testing.expect_value(t, ship_fitting_output_scaled(swivel, 100), swivel)

	// A hold carries no effect at all and is returned untouched.
	filler := ship_fitting_hold(.Small, "Spoils")
	testing.expect_value(t, ship_fitting_output_scaled(filler, 50), filler)
}

// --- The offer bonus against a tree (#404) -----------------------------------

@(test)
an_offer_bonus_lands_on_a_gates_open_branch_and_never_on_its_fallback :: proc(t: ^testing.T) {
	// A gated item that pays nothing while its condition is unmet must still pay nothing
	// once an offer has sweetened it — otherwise every conditional item quietly becomes a
	// little unconditional, which is a balance change wearing a refactor's clothes.
	beast := ship_fitting_with_effects(Fitting{name = "Cornered Beast", size = .Large}, effect_phase_contribution(expr_below_hull_percent(50, 12)))
	sweetened := ship_fitting_scaled(beast, 2).effects[0]

	s := synergy_ship(beast)
	defer delete(s.layout)
	s.max_hull = 20

	s.hull = 20 // above the threshold: the gate is shut, and the bonus is behind it
	testing.expect_value(t, effect_magnitude(sweetened, ship_effect_context(&s)), Magnitude(0))

	s.hull = 9 // below it: the bonus is on the branch that opened
	testing.expect_value(t, effect_magnitude(sweetened, ship_effect_context(&s)), Magnitude(14))

	// An ungated item takes it at the root, where there is no branch to prefer.
	gun := ship_fitting_with_effects(Fitting{name = "Long Nines", size = .Large}, effect_phase_contribution(expr_const(8)))
	plain := ship_fitting_scaled(gun, 2).effects[0]
	testing.expect_value(t, effect_showcase_magnitude(plain), 10)
}

// The bonus costs nodes, and the bound is asserted where a tree is built — so a roster
// item that could not survive being offered would assert mid-voyage rather than in a test.
// The offer's largest bonus is a handful of points; this pins the whole roster against a
// generous one.
@(test)
every_roster_item_still_fits_the_node_bound_once_an_offer_has_sweetened_it :: proc(t: ^testing.T) {
	for item in ship_item_roster() {
		sweetened := ship_fitting_scaled(item.fitting, 9)
		for i in 0 ..< sweetened.effect_count {
			effect := sweetened.effects[i]
			base := item.fitting.effects[i]
			testing.expectf(
				t,
				effect.magnitude.count <= EXPR_MAX_NODES,
				"%s overruns the node bound once bonused: %d nodes",
				item.fitting.name,
				effect.magnitude.count,
			)
			testing.expectf(
				t,
				effect_showcase_magnitude(effect) > effect_showcase_magnitude(base),
				"%s did not get stronger",
				item.fitting.name,
			)
		}
	}
}
