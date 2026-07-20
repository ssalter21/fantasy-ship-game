package ship

import "../testutil"
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
a_fitting_may_both_carry_and_fire :: proc(t: ^testing.T) {
	// The whole point of the axis: the fit rule used to hold a cargo fitting to
	// "stackable and effect-less", which made carrying a *kind* of item and meant a
	// slot spent on offence was automatically a slot spent against the purse. A gun
	// that authors less than its full slot in bulk carries the remainder.
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)
	armed_trader := Fitting{name = "Armed Trader", size = .Large, bulk = 30, active = effect_phase_contribution(expr_const(4))}

	testing.expect(t, ship_fit(&layout_slot, armed_trader))
	testing.expect_value(t, ship_fitting_capacity(armed_trader), 10) // the Large's 40, less its bulk
}

@(test)
an_empty_hold_is_an_ordinary_fitting_not_an_empty_slot :: proc(t: ^testing.T) {
	// A zero-count cargo fitting used to be unrepresentable — an empty hold *was* an
	// empty slot. Now the hold is an installed fitting that happens to be carrying
	// nothing: it weighs nothing, and it is the ship's capacity.
	layout_slot := make_layout_slot("hold", .Small, .Concealed)
	hold := ship_fitting_hold(.Small)

	testing.expect(t, ship_fit(&layout_slot, hold))
	testing.expect_value(t, hold.cargo_held, 0)
	testing.expect_value(t, ship_fitting_weight(hold), 0)
	testing.expect_value(t, ship_fitting_capacity(hold), 10)
}

@(test)
bulk_is_clamped_to_the_slots_own_contribution :: proc(t: ^testing.T) {
	// Capacity reads `contribution − bulk` clamped to `[0, contribution]`, so an
	// out-of-band authored bulk lands on one of the two corners rather than reading as
	// a negative hold or an oversized one.
	testing.expect_value(t, ship_fitting_capacity(Fitting{size = .Medium, bulk = 500}), 0)
	testing.expect_value(t, ship_fitting_capacity(Fitting{size = .Medium, bulk = -500}), 20)
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
cargo_capacity_is_what_the_installed_fittings_leave_over :: proc(t: ^testing.T) {
	// Capacity is `contribution − bulk`, summed over what is installed (ADR-0020,
	// #157): a gun authoring its whole slot carries nothing, a hold authoring none of
	// it carries everything, and a hybrid carries the difference.
	s := Ship{
		layout = []Layout_Slot{
			{slot = Slot{name = "gun deck", size = .Large, base_visibility = .Exposed}, fitting = Fitting{name = "Cannon", size = .Large, bulk = 40}},
			{slot = Slot{name = "hold 1", size = .Small, base_visibility = .Concealed}, fitting = ship_fitting_hold(.Small)},
			{slot = Slot{name = "hold 2", size = .Medium, base_visibility = .Concealed}, fitting = Fitting{name = "Armed Launch", size = .Medium, bulk = 15}},
		},
	}

	// The hold's whole Small (10) plus the hybrid's leftover (20 − 15); the gun's
	// Large contributes nothing.
	testing.expect_value(t, ship_cargo_capacity(s), 10 + 5)
}

@(test)
an_empty_slot_carries_nothing :: proc(t: ^testing.T) {
	// Forced rather than chosen: if an empty slot still contributed, a free zero-bulk
	// hold would be byte-identical to leaving the slot empty and would exist purely as
	// a farmable Cargo-tagged token. The accepted consequence is that an empty slot is
	// wasted rather than neutral — which is why every vacated slot backfills a hold.
	s := Ship{
		layout = []Layout_Slot{
			{slot = Slot{name = "hold 1", size = .Small, base_visibility = .Concealed}},
			{slot = Slot{name = "hold 2", size = .Medium, base_visibility = .Concealed}},
			{slot = Slot{name = "hold 3", size = .Large, base_visibility = .Concealed}},
		},
	}
	testing.expect_value(t, ship_cargo_capacity(s), 0)

	// The same three slots, held: Small 10, Medium 20, Large 40 (#156: ×10 and
	// doubling, a Large worth four Smalls).
	for &layout_slot in s.layout {
		layout_slot.fitting = ship_fitting_hold(layout_slot.slot.size)
	}
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
// Both slots carry a hold, because capacity comes from installed fittings: a pair of
// *empty* slots would carry nothing at all and every stow would spill.
// Returned by value, not as a Ship: a compound-literal slice cannot outlive the frame
// that built it, so the caller owns the array and takes its own slice of it.
make_held_layout :: proc() -> [2]Layout_Slot {
	return [2]Layout_Slot {
		{slot = Slot{size = .Small}, fitting = ship_fitting_hold(.Small)},
		{slot = Slot{size = .Large}, fitting = ship_fitting_hold(.Large)},
	}
}

@(test)
stowing_within_capacity_returns_zero_spilled :: proc(t: ^testing.T) {
	// A stow that fits reports no loss: the return is the overflow, and there is none.
	layout := make_held_layout()
	s := Ship{layout = layout[:]}
	testing.expect_value(t, ship_stow_cargo(s.layout, 30), 0) // 30 into 50 of capacity
	testing.expect_value(t, ship_cargo(s), 30)
}

@(test)
stowing_exactly_to_capacity_returns_zero_spilled :: proc(t: ^testing.T) {
	// The fits-exactly boundary: filling every slot to the brim drops nothing.
	layout := make_held_layout()
	s := Ship{layout = layout[:]}
	testing.expect_value(t, ship_stow_cargo(s.layout, 50), 0) // exactly capacity
	testing.expect_value(t, ship_cargo(s), 50)
}

@(test)
stowing_above_capacity_returns_the_overflow :: proc(t: ^testing.T) {
	// Overflow above capacity is dropped (#157) and returned, never stored: the holds
	// fill to 50 and the return names the 15 that found no slot.
	layout := make_held_layout()
	s := Ship{layout = layout[:]}
	testing.expect_value(t, ship_stow_cargo(s.layout, 65), 15) // 15 over a 50 capacity
	testing.expect_value(t, ship_cargo(s), 50)
}

@(test)
refilling_an_emptied_hold_reports_its_overflow_afresh :: proc(t: ^testing.T) {
	// A re-stow rebuilds the hold from scratch, so the return reflects the new total,
	// not the old: brim-fill, empty, then refill past capacity, and each stow reports
	// its own overflow.
	layout := make_held_layout()
	s := Ship{layout = layout[:]}
	testing.expect_value(t, ship_stow_cargo(s.layout, 50), 0) // brim-full
	testing.expect_value(t, ship_stow_cargo(s.layout, 0), 0) // emptied: nothing to spill
	testing.expect_value(t, ship_cargo(s), 0)
	testing.expect_value(t, ship_stow_cargo(s.layout, 70), 20) // refilled past capacity
	testing.expect_value(t, ship_cargo(s), 50)
}

@(test)
stowing_is_a_pure_function_of_the_amount_and_the_capacities :: proc(t: ^testing.T) {
	// Water-filling is arrangement-independent: shuffling the same capacities into a
	// different slot order changes neither the hold's total nor the spill. That is what
	// lets every caller keep passing a scalar total and re-derive the arrangement from
	// it — sim_refit_restow, the Reward beat and the bootstrap stow all rely on it.
	forwards := [3]Layout_Slot {
		{slot = Slot{size = .Small}, fitting = ship_fitting_hold(.Small)},
		{slot = Slot{size = .Medium}, fitting = ship_fitting_hold(.Medium)},
		{slot = Slot{size = .Large}, fitting = ship_fitting_hold(.Large)},
	}
	backwards := [3]Layout_Slot{forwards[2], forwards[1], forwards[0]}

	for amount in ([]int{0, 1, 7, 30, 55, 70, 200}) {
		a, b := forwards, backwards
		spilled_a := ship_stow_cargo(a[:], amount)
		spilled_b := ship_stow_cargo(b[:], amount)

		testing.expectf(t, spilled_a == spilled_b, "spill differed by arrangement at amount %d", amount)
		testing.expectf(
			t,
			ship_cargo(Ship{layout = a[:]}) == ship_cargo(Ship{layout = b[:]}),
			"hold total differed by arrangement at amount %d",
			amount,
		)
	}
}

@(test)
water_filling_caps_the_small_holds_first_and_cascades_the_rest :: proc(t: ^testing.T) {
	// Equal absolute shares, capping and cascading: 70 across 10/20/40 gives everyone
	// 23 on the first pass, which the Small caps at 10 and the Medium at 20; the 40
	// leftover cascades to the Large, which was already holding 23.
	layout := [3]Layout_Slot {
		{slot = Slot{size = .Small}, fitting = ship_fitting_hold(.Small)},
		{slot = Slot{size = .Medium}, fitting = ship_fitting_hold(.Medium)},
		{slot = Slot{size = .Large}, fitting = ship_fitting_hold(.Large)},
	}

	testing.expect_value(t, ship_stow_cargo(layout[:], 70), 0)

	small, _ := layout[0].fitting.?
	medium, _ := layout[1].fitting.?
	large, _ := layout[2].fitting.?
	testing.expect_value(t, small.cargo_held, 10) // capped
	testing.expect_value(t, medium.cargo_held, 20) // capped
	testing.expect_value(t, large.cargo_held, 40) // took what the other two could not
}

@(test)
tag_cargo_is_authored_and_never_derived :: proc(t: ^testing.T) {
	// Tag.Cargo says "this fitting's job is carrying", not "this fitting is carrying".
	// The distinction is load-bearing: a selector reads authored constants, and
	// `cargo_held` is the one field of a Fitting that moves at runtime — so a tag that
	// appeared when cargo was stowed would be a selector reading live state.
	gun := Fitting{name = "Deck Cannon", size = .Medium, bulk = 5, tags = {.Weapon}}
	gun.cargo_held = 15

	testing.expect_value(t, gun.tags, bit_set[Tag]{.Weapon}) // carrying earns no tag
	testing.expect(t, !ship_fitting_is_hold(gun))

	// And the converse: a hold declares Cargo while carrying nothing at all.
	empty_hold := ship_fitting_hold(.Large)
	testing.expect_value(t, empty_hold.cargo_held, 0)
	testing.expect_value(t, empty_hold.tags, bit_set[Tag]{.Cargo})
}

@(test)
ship_stow_spill_predicts_the_overflow_a_stow_would_drop :: proc(t: ^testing.T) {
	// The predictive twin agrees with the mutating stow's return across the range, so a
	// caller that must name the loss before stowing (the Reward beat) gets the same
	// number ship_stow_cargo would report after.
	for amount in ([]int{0, 30, 50, 65, 120}) {
		predicted_layout, actual_layout := make_held_layout(), make_held_layout()
		predicted := Ship{layout = predicted_layout[:]}
		actual := Ship{layout = actual_layout[:]}
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
remove_takes_the_fitting_out_and_backfills_a_matching_hold :: proc(t: ^testing.T) {
	// The removed fitting is discarded — nothing holds it now (no inventory) — but the
	// slot does not go empty: an empty slot carries nothing, so leaving one would hand
	// the captain a berth that is worse than useless and a rule to remember about it.
	// Backfilling makes the empty slot unreachable, and costs nothing: holds are free.
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)
	testing.expect(t, ship_fit(&layout_slot, Fitting{name = "Gun Deck", size = .Large, bulk = 40}))

	removed, was_there := ship_remove(&layout_slot)

	testing.expect(t, was_there)
	testing.expect_value(t, removed.name, "Gun Deck")
	backfilled, still_there := layout_slot.fitting.?
	testing.expect(t, still_there)
	testing.expect(t, ship_fitting_is_hold(backfilled))
	testing.expect_value(t, backfilled.size, Slot_Size.Large) // sized to the slot it vacated
	testing.expect_value(t, ship_fitting_capacity(backfilled), 40)
}

@(test)
remove_of_an_empty_slot_is_a_rejected_no_op :: proc(t: ^testing.T) {
	layout_slot := make_layout_slot("gun deck", .Large, .Exposed)

	_, was_there := ship_remove(&layout_slot)

	testing.expect(t, !was_there)
}

@(test)
move_relocates_a_fitting_and_backfills_the_slot_it_left :: proc(t: ^testing.T) {
	layout := []Layout_Slot{
		make_layout_slot("gun deck", .Large, .Exposed),
		make_layout_slot("forecastle", .Large, .Exposed),
	}
	testing.expect(t, ship_fit(&layout[0], Fitting{name = "Gun Deck", size = .Large, bulk = 40}))

	moved, did_move := ship_move(&layout[0], &layout[1])

	testing.expect(t, did_move)
	testing.expect_value(t, moved.name, "Gun Deck")
	source, source_filled := layout[0].fitting.?
	testing.expect(t, source_filled)
	testing.expect(t, ship_fitting_is_hold(source)) // vacated, then backfilled
	dest, dest_full := layout[1].fitting.?
	testing.expect(t, dest_full)
	testing.expect_value(t, dest.name, "Gun Deck")
}

@(test)
move_may_displace_a_bare_hold_but_not_a_real_fitting :: proc(t: ^testing.T) {
	// Every vacated slot backfills, so a genuinely empty berth is unreachable in play
	// and an empty-only destination rule would delete rearranging outright. A hold is
	// free and unowned, so displacing one takes nothing from anybody; a real fitting
	// still refuses, because a move is not a swap.
	layout := []Layout_Slot{
		make_layout_slot("gun deck", .Large, .Exposed),
		make_layout_slot("forecastle", .Large, .Exposed),
	}
	testing.expect(t, ship_fit(&layout[0], Fitting{name = "Gun Deck", size = .Large, bulk = 40}))
	testing.expect(t, ship_fit(&layout[1], ship_fitting_hold(.Large)))

	_, did_move := ship_move(&layout[0], &layout[1])
	testing.expect(t, did_move)

	dest, _ := layout[1].fitting.?
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
replace_admits_a_carrying_fitting_that_also_has_an_effect :: proc(t: ^testing.T) {
	// The fit rule used to reject this outright: cargo was a *kind* of fitting, held
	// to "stackable and effect-less", so nothing could both carry and do something.
	// Replace now applies the exact-size rule and nothing else, exactly as install does.
	layout_slot := make_layout_slot("hold", .Large, .Concealed)
	testing.expect(t, ship_fit(&layout_slot, Fitting{name = "Cannon", size = .Large, bulk = 40}))
	cursed_loot := Fitting{name = "Cursed Loot", size = .Large, bulk = 20, passive = Effect{}}

	testing.expect(t, ship_replace_fitting(&layout_slot, cursed_loot))

	installed, has_fitting := layout_slot.fitting.?
	testing.expect(t, has_fitting)
	testing.expect_value(t, installed.name, "Cursed Loot")
	testing.expect_value(t, ship_fitting_capacity(installed), 20)
}

@(test)
effect_magnitude_resolves_a_flat_effect_to_its_stored_constant :: proc(t: ^testing.T) {
	s := Ship{}
	ctx := Effect_Context{owner = &s}

	testing.expect_value(t, effect_magnitude(effect_phase_contribution(expr_const(7)), ctx), Magnitude(7))
	testing.expect_value(t, effect_magnitude(effect_repair(expr_const(4)), ctx), Magnitude(4))
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
selector_matches_over_each_of_tag_size_and_visibility :: proc(t: ^testing.T) {
	slot := Layout_Slot{
		slot    = Slot{size = .Large, base_visibility = .Concealed},
		fitting = Fitting{name = "War Kraken", size = .Large, category = .Fire, tags = {.Beast, .Weapon}},
	}

	// Tag: a multi-tag fitting matches on each of its own tags, and misses a tag it lacks.
	testing.expect(t, selector_matches(slot, Selector(Tag.Beast)))
	testing.expect(t, selector_matches(slot, Selector(Tag.Weapon)))
	testing.expect(t, !selector_matches(slot, Selector(Tag.Crew)))
	// Size: the fitting's own field. A round Category is not an axis at all — a phase is
	// not a countable constant (see Selector).
	testing.expect(t, selector_matches(slot, Selector(Slot_Size.Large)))
	testing.expect(t, !selector_matches(slot, Selector(Slot_Size.Small)))
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
	synergy := effect_phase_contribution(expr_const(2), Selector(Tag.Weapon))
	testing.expect_value(t, effect_magnitude(synergy, ctx), Magnitude(4))
}

@(test)
effect_magnitude_of_a_synergy_with_no_matches_is_zero :: proc(t: ^testing.T) {
	s := synergy_ship(Fitting{name = "Top Crew", size = .Medium, tags = {.Crew}})
	defer delete(s.layout)
	ctx := ship_effect_context(&s)

	synergy := effect_phase_contribution(expr_const(5), Selector(Tag.Weapon))
	testing.expect_value(t, effect_magnitude(synergy, ctx), Magnitude(0))
}

@(test)
effective_speed_is_the_raw_field_less_weight_when_no_modifier_is_installed :: proc(t: ^testing.T) {
	cannon := Fitting{name = "Cannon", size = .Large, weight = 38, category = .Fire, active = effect_phase_contribution(expr_const(10))}
	s := Ship{
		speed = 4, max_hull = 20,
		layout = []Layout_Slot{{slot = Slot{size = .Large}, fitting = cannon}},
	}

	// A plain fitting adds no Speed modifier, but every non-cargo fitting has an authored
	// weight (ADR-0020), so effective Speed is base − weight/10 rather than the raw field.
	testing.expect_value(t, ship_effective_speed(&s), 4 - ship_weight(s) / 10)
	testing.expect_value(t, s.max_hull, 20) // no fitting moves the ceiling (ADR-0027)
}

@(test)
only_a_modify_speed_effect_moves_effective_speed :: proc(t: ^testing.T) {
	// Speed is the one stat a fitting can modify, and it reads exactly the effects that
	// name it: a Brace fitting's Repair magnitude resolves through combat's phase totals,
	// never into a stat, so it must not leak here.
	sails := Fitting{name = "Fast Sails", size = .Small, passive = effect_modify_speed(expr_const(3))}
	surgeon := Fitting{name = "Ship's Surgeon", size = .Small, category = .Brace, active = effect_repair(expr_const(6))}
	s := Ship{
		speed = 4, max_hull = 20,
		layout = []Layout_Slot{
			{slot = Slot{size = .Small}, fitting = sails},
			{slot = Slot{size = .Small}, fitting = surgeon},
		},
	}

	testing.expect_value(t, ship_effective_speed(&s), 4 + 3)
}

@(test)
speed_modifiers_stack_across_slots :: proc(t: ^testing.T) {
	sails := Fitting{name = "Fast Sails", size = .Small, weight = 8, passive = effect_modify_speed(expr_const(4))}
	rigging := Fitting{name = "Spare Rigging", size = .Small, weight = 8, passive = effect_modify_speed(expr_const(2))}
	timbers := Fitting{name = "Spare Timbers", size = .Small, weight = 8, category = .Brace, active = effect_repair(expr_const(3))}
	s := Ship{
		speed = 5, max_hull = 20,
		layout = []Layout_Slot{
			{slot = Slot{size = .Small}, fitting = sails},
			{slot = Slot{size = .Small}, fitting = rigging},
			{slot = Slot{size = .Small}, fitting = timbers},
		},
	}

	// base 5 + Modify_Speed (4 + 2), minus the three Small fittings' weight/10 (ADR-0020).
	testing.expect_value(t, ship_effective_speed(&s), 5 + 4 + 2 - ship_weight(s) / 10)
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

// --- Trees at the magnitude seam ---------------------------------------------
//
// An effect's magnitude is an authored tree (expr.odin's composed shapes), resolved by
// expr_eval against the flattened context effect_magnitude builds. These pin each of the
// readings the roster leans on through that seam.

@(test)
a_hull_gated_tree_resolves_to_zero_above_the_threshold_and_full_below :: proc(t: ^testing.T) {
	effect := effect_phase_contribution(expr_below_hull_percent(50, 6))
	s := Ship{max_hull = 20}

	s.hull = 20 // full: above the half-Hull threshold
	testing.expect_value(t, effect_magnitude(effect, ship_effect_context(&s)), Magnitude(0))

	s.hull = 10 // exactly half: strictly-below means still shut
	testing.expect_value(t, effect_magnitude(effect, ship_effect_context(&s)), Magnitude(0))

	s.hull = 9 // below half: full magnitude
	testing.expect_value(t, effect_magnitude(effect, ship_effect_context(&s)), Magnitude(6))
}

// in_round builds a complete two-pass context for a bare ship at `round`, with no speeds
// worth naming — the shape the tests that only care about the round number want.
in_round :: proc(s: ^Ship, round: int) -> Effect_Context {
	return ship_effect_context_in_battle(s, Round_Facts{round = round}, Speeds{})
}

@(test)
a_round_gated_tree_is_shut_before_its_round_and_off_the_battlefield :: proc(t: ^testing.T) {
	effect := effect_phase_contribution(expr_from_round(3, 5))
	s := Ship{}

	// No round: off the battlefield there is no round number, and the gate reads shut.
	testing.expect_value(t, effect_magnitude(effect, ship_effect_context(&s)), Magnitude(0))

	testing.expect_value(t, effect_magnitude(effect, in_round(&s, 2)), Magnitude(0))
	testing.expect_value(t, effect_magnitude(effect, in_round(&s, 3)), Magnitude(5))
	testing.expect_value(t, effect_magnitude(effect, in_round(&s, 9)), Magnitude(5))
}

@(test)
a_visibility_reading_tree_reads_the_slot_the_effect_is_resolved_for :: proc(t: ^testing.T) {
	effect := effect_phase_contribution(expr_while_concealed(4))
	s := Ship{}

	ctx := ship_effect_context(&s)
	// No self slot: the quantity reads Exposed, the ordinal's zero.
	testing.expect_value(t, effect_magnitude(effect, ctx), Magnitude(0))

	ctx.self_slot = Layout_Slot{slot = Slot{base_visibility = .Exposed}}
	testing.expect_value(t, effect_magnitude(effect, ctx), Magnitude(0))

	ctx.self_slot = Layout_Slot{slot = Slot{base_visibility = .Concealed}}
	testing.expect_value(t, effect_magnitude(effect, ctx), Magnitude(4))
}

@(test)
speed_reading_trees_compare_the_speeds_pass_one_computed :: proc(t: ^testing.T) {
	s := Ship{}
	faster := effect_phase_contribution(expr_while_opponent_faster(3))
	slower := effect_phase_contribution(expr_while_opponent_slower(3))

	// own 5, opponent 8: the opponent is the faster side.
	quick_foe := ship_effect_context_in_battle(&s, Round_Facts{round = 1}, Speeds{own = 5, opponent = 8})
	testing.expect_value(t, effect_magnitude(faster, quick_foe), Magnitude(3))
	testing.expect_value(t, effect_magnitude(slower, quick_foe), Magnitude(0))

	// own 8, opponent 5: the opponent is the slower side.
	slow_foe := ship_effect_context_in_battle(&s, Round_Facts{round = 1}, Speeds{own = 8, opponent = 5})
	testing.expect_value(t, effect_magnitude(faster, slow_foe), Magnitude(0))
	testing.expect_value(t, effect_magnitude(slower, slow_foe), Magnitude(3))

	// Equal speed: neither strict comparison holds.
	tie := ship_effect_context_in_battle(&s, Round_Facts{round = 1}, Speeds{own = 6, opponent = 6})
	testing.expect_value(t, effect_magnitude(faster, tie), Magnitude(0))
	testing.expect_value(t, effect_magnitude(slower, tie), Magnitude(0))
}

// The captain's own order is one ordinal quantity an item may read, so "pays off on the
// round you commit" is authorable — and the opponent's order is nowhere in the context to
// be read at all.
@(test)
a_tree_reads_the_captains_own_order_as_one_ordinal :: proc(t: ^testing.T) {
	s := Ship{}
	on_commit := effect_phase_contribution(
		expr_gate(.Eq, expr_quantity(.Captains_Order), expr_const(int(Captains_Order.Commit)), expr_const(9), expr_const(0)),
	)

	held := ship_effect_context_in_battle(&s, Round_Facts{round = 1, captains_order = .Hold}, Speeds{})
	testing.expect_value(t, effect_magnitude(on_commit, held), Magnitude(0))

	pressed := ship_effect_context_in_battle(&s, Round_Facts{round = 1, captains_order = .Press_Fire}, Speeds{})
	testing.expect_value(t, effect_magnitude(on_commit, pressed), Magnitude(0))

	committed := ship_effect_context_in_battle(&s, Round_Facts{round = 1, captains_order = .Commit}, Speeds{})
	testing.expect_value(t, effect_magnitude(on_commit, committed), Magnitude(9))
}

// The damage a ship took last round is the second momentary quantity (the captain's order
// is the first): it can turn off again inside one fight.
@(test)
a_tree_reads_the_damage_taken_last_round :: proc(t: ^testing.T) {
	s := Ship{}
	vengeful := effect_phase_contribution(expr_quantity(.Damage_Taken_Last_Round))

	untouched := ship_effect_context_in_battle(&s, Round_Facts{round = 2}, Speeds{})
	testing.expect_value(t, effect_magnitude(vengeful, untouched), Magnitude(0))

	mauled := ship_effect_context_in_battle(&s, Round_Facts{round = 2, damage_taken_last_round = 7}, Speeds{})
	testing.expect_value(t, effect_magnitude(vengeful, mauled), Magnitude(7))
}

// The opponent enters as a **flattened, visibility-filtered counter block** and nothing
// else: a Count over it reads what the lookouts could see, and concealment deletes a
// fitting from the report rather than hiding it behind a check.
@(test)
an_opponent_count_reads_the_scouting_report_and_concealment_empties_it :: proc(t: ^testing.T) {
	foe := synergy_ship(
		Fitting{name = "Long Nines", size = .Large, tags = {.Weapon}},
		Fitting{name = "Swivel Guns", size = .Small, tags = {.Weapon}},
	)
	defer delete(foe.layout)

	s := Ship{}
	per_enemy_gun := effect_phase_contribution(expr_mul(expr_const(2), expr_count_opponent(Selector(Tag.Weapon))))

	exposed := ship_effect_context_in_battle(
		&s,
		Round_Facts{round = 1, opponent = ship_scouting_report(&foe)},
		Speeds{},
	)
	testing.expect_value(t, effect_magnitude(per_enemy_gun, exposed), Magnitude(4))

	// Hide one gun below decks: the report loses it, so the count does too.
	foe.layout[1].slot.base_visibility = .Concealed
	half_seen := ship_effect_context_in_battle(
		&s,
		Round_Facts{round = 1, opponent = ship_scouting_report(&foe)},
		Speeds{},
	)
	testing.expect_value(t, effect_magnitude(per_enemy_gun, half_seen), Magnitude(2))
}

// The layering rule, enforced where the spec says it must be: at authoring time. A
// runtime zero here would *be* the dead-conditions defect, in a new place.
@(test)
a_modify_speed_tree_that_reads_a_speed_is_rejected_when_it_is_authored :: proc(t: ^testing.T) {
	// A Modify_Speed effect may read anything below its layer.
	round_gated := effect_modify_speed(expr_from_round(3, 2))
	testing.expect_value(t, round_gated.kind, Effect_Kind.Modify_Speed)

	// It may not read either speed — own or opponent. Both readings are refused by
	// effect_modify_speed's assert; expr_reads_quantity is the question it asks.
	testing.expect(t, expr_reads_quantity(expr_while_opponent_faster(2), .Own_Speed))
	testing.expect(t, expr_reads_quantity(expr_while_opponent_faster(2), .Opponent_Speed))
	testing.expect(t, expr_reads_quantity(expr_quantity(.Own_Speed), .Own_Speed))
	testing.expect(t, !expr_reads_quantity(expr_from_round(3, 2), .Own_Speed))

	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}
	testing.expect_assert(t, "a Modify_Speed tree cannot read a speed")
	_ = effect_modify_speed(expr_while_opponent_faster(2))
}

// Pass one is what gives a speed modifier a round to read: given none, its gate has no
// reading to open on and the item is dormant in every round of every battle.
@(test)
a_round_gated_speed_modifier_fires_mid_battle_through_pass_one :: proc(t: ^testing.T) {
	sails := Fitting {
		name    = "Storm Canvas",
		size    = .Small,
		passive = effect_modify_speed(expr_from_round(3, 4)),
	}
	s := Ship {
		speed  = 2,
		max_hull = 20,
		layout = []Layout_Slot{{slot = Slot{size = .Small}, fitting = sails}},
	}

	// Outside a battle there is no round, and the modifier is dormant.
	testing.expect_value(t, ship_effective_speed(&s), 2)

	testing.expect_value(t, ship_effective_speed(&s, Round_Facts{round = 2}), 2)
	testing.expect_value(t, ship_effective_speed(&s, Round_Facts{round = 3}), 2 + 4)
}

@(test)
a_gated_stat_modifier_applies_only_while_its_gate_is_open :: proc(t: ^testing.T) {
	// A "below half Hull, run for it" rigging: the effective-stat readers resolve it
	// through the same magnitude seam, self_slot filled per slot. Speed rather than
	// Max Hull, so the gate's own reading cannot move underneath it.
	rigging := Fitting {
		name    = "Panic Rigging",
		size    = .Small,
		passive = effect_modify_speed(expr_below_hull_percent(50, 5)),
	}
	s := Ship {
		speed  = 2,
		max_hull = 20,
		layout = []Layout_Slot{{slot = Slot{size = .Small}, fitting = rigging}},
	}

	s.hull = 20 // above the threshold: raw speed only
	testing.expect_value(t, ship_effective_speed(&s), 2)

	s.hull = 8 // below the threshold: the +Speed kicks in
	testing.expect_value(t, ship_effective_speed(&s), 2 + 5)
}

@(test)
jettisoning_empties_the_named_fitting_and_re_stows_what_is_left :: proc(t: ^testing.T) {
	// The heave sheds one fitting's cargo and water-fills the remainder back over the
	// whole layout, so the ship is lighter by what went over the side and the fitting
	// itself stays installed.
	layout := make_held_layout()
	ship_stow_cargo(layout[:], 50) // Small 10 + Large 40, both brim-full

	heaved, ok := ship_jettison_cargo(layout[:], Slot_Index(1))

	testing.expect(t, ok)
	testing.expect_value(t, heaved.cargo_held, 40) // what the heave reports going over the side
	testing.expect_value(t, ship_cargo(Ship{layout = layout[:]}), 10) // the Small's 10 survives
	_, still_installed := layout[1].fitting.?
	testing.expect(t, still_installed)
}

@(test)
jettisoning_re_stows_across_the_emptied_fitting_too :: proc(t: ^testing.T) {
	// The remainder is water-filled over everything that can carry, the emptied slot
	// included, so successive heaves shed less each time.
	layout := make_held_layout()
	ship_stow_cargo(layout[:], 50)

	ship_jettison_cargo(layout[:], Slot_Index(1)) // sheds the Large's 40, 10 left
	first, _ := layout[1].fitting.?
	testing.expect(t, first.cargo_held > 0) // the survivors flowed back into it

	second, ok := ship_jettison_cargo(layout[:], Slot_Index(1))
	testing.expect(t, ok)
	testing.expect(t, second.cargo_held < 40) // a second heave sheds strictly less
}

@(test)
jettisoning_a_fitting_carrying_nothing_is_refused :: proc(t: ^testing.T) {
	// A fitting carrying nothing weighs nothing extra, so there is no Speed in heaving
	// it — refused rather than silently emptied, and an empty slot likewise.
	layout := [2]Layout_Slot {
		{slot = Slot{size = .Small}, fitting = ship_fitting_hold(.Small)},
		{slot = Slot{size = .Large}},
	}

	_, laden := ship_jettison_cargo(layout[:], Slot_Index(0))
	testing.expect(t, !laden)
	_, filled := ship_jettison_cargo(layout[:], Slot_Index(1))
	testing.expect(t, !filled)
}
