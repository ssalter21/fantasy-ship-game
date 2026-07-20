package ship

import "core:testing"

// The whole budget is one pure function over one authored item, so the whole budget is
// testable as arithmetic. Prices are in hundredths of a point throughout (Points), so a
// failure message reading 750 is seven and a half points.

// --- The published tables ----------------------------------------------------

@(test)
the_grant_table_is_convex_in_size_and_rising_in_tier :: proc(t: ^testing.T) {
	// Tier buys more in a bigger slot: every cell of the published table, spelled out.
	expected := [Slot_Size][Tier]int {
		.Small  = {.Splash = 3, .Shallow = 4, .Deep = 5},
		.Medium = {.Splash = 4, .Shallow = 6, .Deep = 8},
		.Large  = {.Splash = 6, .Shallow = 9, .Deep = 12},
	}
	for size in Slot_Size {
		for tier in Tier {
			testing.expect_value(t, budget_grant(size, tier), Points(expected[size][tier]) * POINT)
		}
	}

	// Convex in size, not merely rising: the step from Medium to Large is at least the
	// step from Small to Medium, at every tier. A steeper size ladder than that would
	// leave the tier ladder decreasing.
	for tier in Tier {
		small := budget_grant(.Small, tier)
		medium := budget_grant(.Medium, tier)
		large := budget_grant(.Large, tier)
		testing.expect(t, large - medium >= medium - small)
		// And tier itself rises inside every size.
		if tier > min(Tier) {
			for size in Slot_Size {
				testing.expect(t, budget_grant(size, tier) > budget_grant(size, Tier(int(tier) - 1)))
			}
		}
	}
}

@(test)
the_band_is_a_quarter_of_the_grant_either_way_and_never_narrower_than_a_point :: proc(t: ^testing.T) {
	for size in Slot_Size {
		for tier in Tier {
			grant := budget_grant(size, tier)
			low, high := budget_band(size, tier)
			testing.expect_value(t, grant - low, high - grant) // two-sided, symmetric
			testing.expect(t, grant - low >= BUDGET_BAND_MINIMUM)
		}
	}

	// The smallest cell's quarter is 0.75 of a point, which the minimum lifts to one; the
	// largest cell's is a clean three.
	small_low, small_high := budget_band(.Small, .Splash)
	testing.expect_value(t, small_low, Points(200))
	testing.expect_value(t, small_high, Points(400))
	large_low, large_high := budget_band(.Large, .Deep)
	testing.expect_value(t, large_low, Points(900))
	testing.expect_value(t, large_high, Points(1500))
}

// **The count peaks are derived by walking the real ship layout**, and this is where a
// re-sized hold is answered for: change the template and this fails loudly rather than
// silently re-pricing every counting item in the roster. The layout is a balance surface.
@(test)
the_count_peaks_are_derived_from_the_one_ship_template :: proc(t: ^testing.T) {
	peaks := ship_count_peaks()

	for tag in Tag {
		testing.expectf(t, peaks.tag[tag] == 8, "%v peaks at %v, not 8", tag, peaks.tag[tag])
	}
	testing.expect_value(t, peaks.visibility[.Exposed], 4)
	testing.expect_value(t, peaks.visibility[.Concealed], 4)
	testing.expect_value(t, peaks.size[.Small], 3)
	testing.expect_value(t, peaks.size[.Medium], 3)
	testing.expect_value(t, peaks.size[.Large], 2)
}

// --- The cost formula --------------------------------------------------------

// Fire is the numeraire: a flat Fire magnitude costs exactly itself, which is what lets the
// grant table read as licensed magnitudes. Speed costs three times as much, sustained repair
// twice.
@(test)
a_flat_effect_costs_its_magnitude_times_its_verbs_rate :: proc(t: ^testing.T) {
	peaks := ship_count_peaks()
	testing.expect_value(t, effect_cost(effect_phase_contribution(expr_const(5)), peaks), Points(500))
	testing.expect_value(t, effect_cost(effect_repair(expr_const(5)), peaks), Points(1000))
	testing.expect_value(t, effect_cost(effect_modify_speed(expr_const(2)), peaks), Points(600))
}

// A synergy is priced at the count it can reach, and the count comes off the layout — so a
// per-Weapon point is priced as eight, not as the three the author had in mind.
@(test)
a_synergy_is_priced_at_the_peak_the_layout_admits :: proc(t: ^testing.T) {
	peaks := ship_count_peaks()
	testing.expect_value(t, effect_cost(effect_phase_contribution(expr_const(1), Selector(Tag.Weapon)), peaks), Points(800))
	testing.expect_value(t, effect_cost(effect_phase_contribution(expr_const(1), Selector(Slot_Size.Large)), peaks), Points(200))
}

// **A gate prices uncertainty, so a gate the author controls gets no discount.** Each of the
// three published factors, on the shape that earns it.
@(test)
a_gate_is_discounted_by_how_little_the_author_controls_it :: proc(t: ^testing.T) {
	peaks := ship_count_peaks()

	// Uncontrolled: the chase you do not choose to be in.
	testing.expect_value(t, effect_cost(effect_phase_contribution(expr_while_opponent_faster(4)), peaks), Points(400))
	// Soft: half the hull pool, or an early round.
	testing.expect_value(t, effect_cost(effect_phase_contribution(expr_below_hull_percent(50, 4)), peaks), Points(280))
	testing.expect_value(t, effect_cost(effect_phase_contribution(expr_from_round(3, 4)), peaks), Points(280))
	// Remote: a condition the fight may never reach.
	testing.expect_value(t, effect_cost(effect_phase_contribution(expr_from_round(5, 4)), peaks), Points(200))
	testing.expect_value(t, effect_cost(effect_phase_contribution(expr_below_hull_percent(25, 4)), peaks), Points(200))
	testing.expect_value(t, effect_cost(effect_phase_contribution(expr_while_opponent_slower(4)), peaks), Points(200))

	// Nested gates multiply, and the product floors at half.
	deep := effect_phase_contribution(expr_gate(.Gte, expr_quantity(.Round), expr_const(5), expr_from_round(5, 4), expr_const(0)))
	testing.expect_value(t, effect_gate_factor(deep), GATE_FACTOR_FLOOR)
}

// **The Gate factor is suppressed for Repair**: burst is already the conditionality
// discount, and charging both prices the same conditionality twice. So gates are free
// distinctness on a burst repair — the thing the defensive roster needed.
@(test)
a_repair_pays_the_burst_rate_or_the_gate_factor_but_never_both :: proc(t: ^testing.T) {
	peaks := ship_count_peaks()

	// Sustained repair, gated: the gate buys nothing, so it costs the full sustained rate.
	gated := effect_repair(expr_below_hull_percent(50, 4))
	testing.expect_value(t, effect_gate_factor(gated), GATE_FACTOR_UNCONTROLLED)
	testing.expect_value(t, effect_cost(gated, peaks), Points(800))

	// Burst repair: each firing is paid for by frequency, so the rate falls to a quarter of
	// sustained — and a gate on top still buys nothing.
	burst := effect_with_timing(effect_repair(expr_below_hull_percent(50, 4)), Timing_Once_Per_Battle{})
	testing.expect_value(t, effect_cost(burst, peaks), Points(200))
	testing.expect_value(t, effect_cost(effect_with_timing(effect_repair(expr_const(4)), Timing_Every_N{n = 2}), peaks), Points(200))
}

// The burst rate is earned by cost as well as by frequency — but only by the order that
// pays for itself. **Commit forfeits a round of Fire; Press is free.**
@(test)
a_commit_gate_earns_the_burst_rate_and_a_press_gate_does_not :: proc(t: ^testing.T) {
	peaks := ship_count_peaks()
	on_order :: proc(order: Captains_Order) -> Effect {
		return effect_repair(
			expr_gate(.Eq, expr_quantity(.Captains_Order), expr_const(int(order)), expr_const(4), expr_const(0)),
		)
	}
	testing.expect_value(t, effect_cost(on_order(.Commit), peaks), Points(200))
	testing.expect_value(t, effect_cost(on_order(.Press_Brace), peaks), Points(800))
}

// Weight converts into and out of allowance rather than into cost — the line this effort
// kept dropping. Heavier than the size's default earns points; lighter spends them.
@(test)
weight_converts_into_and_out_of_allowance_at_three_to_the_point :: proc(t: ^testing.T) {
	testing.expect_value(t, budget_weight_allowance(.Medium, WEIGHT_DEFAULT[.Medium]), Points(0))
	testing.expect_value(t, budget_weight_allowance(.Medium, WEIGHT_DEFAULT[.Medium] + 3), POINT)
	testing.expect_value(t, budget_weight_allowance(.Medium, WEIGHT_DEFAULT[.Medium] - 3), -POINT)

	// The deviation cap is half the default either way.
	low, high := budget_weight_band(.Large)
	testing.expect_value(t, low, 20)
	testing.expect_value(t, high, 60)
}

// **Capacity is priced as an option, and low bulk is never rewarded.** A roster item that
// authors its full slot contribution carries nothing and pays nothing; a hold's worth of
// capacity costs by the twenty.
@(test)
capacity_costs_by_the_option_it_buys_and_never_refunds :: proc(t: ^testing.T) {
	for size in Slot_Size {
		full := Fitting{size = size, bulk = ship_cargo_slot_contribution(size)}
		testing.expect_value(t, budget_capacity_cost(full), Points(0))
	}
	testing.expect_value(t, budget_capacity_cost(Fitting{size = .Small}), POINT)
	testing.expect_value(t, budget_capacity_cost(Fitting{size = .Medium}), POINT)
	testing.expect_value(t, budget_capacity_cost(Fitting{size = .Large}), 2 * POINT)
}

// --- roster_check -------------------------------------------------------

// **Every roster item passes.** The one test the whole budget exists to make answerable,
// and the one an appended item answers to.
@(test)
every_roster_item_is_inside_its_cells_band :: proc(t: ^testing.T) {
	for item in ship_item_roster() {
		verdict := roster_check(item)
		testing.expectf(
			t,
			verdict.fault == .None,
			"%v (%v %v): %v — costs %v against an allowance of %v, band %v..%v",
			verdict.item,
			item.fitting.size,
			item.tier,
			verdict.fault,
			verdict.cost,
			verdict.allowance,
			verdict.low,
			verdict.high,
		)
	}
}

// **An item too weak for its cell fails as loudly as one too strong.** Both directions off
// one item, so neither bound can be lost while the other holds.
@(test)
an_item_too_weak_for_its_cell_is_as_illegal_as_one_too_strong :: proc(t: ^testing.T) {
	cell :: proc(magnitude: int) -> Roster_Item {
		return roster_item(.Shallow, "Test Gun", .Medium, WEIGHT_DEFAULT[.Medium], {.Weapon}, {effect_phase_contribution(expr_const(magnitude))})
	}
	testing.expect_value(t, roster_check(cell(6)).fault, Roster_Fault.None) // the grant itself
	testing.expect_value(t, roster_check(cell(4)).fault, Roster_Fault.None) // the band's floor
	testing.expect_value(t, roster_check(cell(8)).fault, Roster_Fault.None) // and its ceiling
	testing.expect_value(t, roster_check(cell(3)).fault, Roster_Fault.Under_Band)
	testing.expect_value(t, roster_check(cell(9)).fault, Roster_Fault.Over_Band)
}

// Weight moves the allowance, so the same effects are legal in a cell they missed once the
// item is authored heavier — and illegal once it is authored lighter.
@(test)
a_heavier_item_is_licensed_for_more_and_a_lighter_one_for_less :: proc(t: ^testing.T) {
	gun :: proc(weight: int) -> Roster_Item {
		return roster_item(.Shallow, "Test Gun", .Medium, weight, {.Weapon}, {effect_phase_contribution(expr_const(9))})
	}
	testing.expect_value(t, roster_check(gun(WEIGHT_DEFAULT[.Medium])).fault, Roster_Fault.Over_Band)
	testing.expect_value(t, roster_check(gun(WEIGHT_DEFAULT[.Medium] + 3)).fault, Roster_Fault.None)
	testing.expect_value(t, roster_check(gun(WEIGHT_DEFAULT[.Medium] - 3)).fault, Roster_Fault.Over_Band)

	// And the deviation itself is capped, so an item cannot buy an arbitrary allowance by
	// being a boat anchor.
	_, heaviest := budget_weight_band(.Medium)
	testing.expect_value(t, roster_check(gun(heaviest + 1)).fault, Roster_Fault.Weight_Off_Band)
}

// The structural faults, each on an item that is otherwise unremarkable. They are refused
// where an item is authored as well; the check states them again so the whole contract is
// answerable in one place.
@(test)
roster_check_refuses_the_structural_faults :: proc(t: ^testing.T) {
	nameless := roster_item(.Splash, "", .Small, 6, {.Crew}, {effect_phase_contribution(expr_const(3))})
	testing.expect_value(t, roster_check(nameless).fault, Roster_Fault.Unnamed)

	overbulked := roster_item(.Splash, "Test", .Small, 6, {.Crew}, {effect_phase_contribution(expr_const(3))}, bulk = 11)
	testing.expect_value(t, roster_check(overbulked).fault, Roster_Fault.Bulk_Outside_Slot)

	effectless := Roster_Item{tier = .Splash, fitting = Fitting{name = "Test", size = .Small, weight = 6, bulk = 10}}
	testing.expect_value(t, roster_check(effectless).fault, Roster_Fault.Effect_Count_Off_Band)

	// A gated spike: the discount buys the price down without shrinking what lands, so the
	// peak cap is what bounds it.
	spike := roster_item(
		.Deep,
		"Test",
		.Large,
		60,
		{.Weapon},
		{effect_phase_contribution(expr_below_hull_percent(25, 30))},
	)
	testing.expect_value(t, roster_check(spike).fault, Roster_Fault.Peak_Output_Over_Cap)
}

// The quantity-legality faults are unreachable through the authoring helpers — each of them
// asserts (effect_modify_speed, expr_gate, effect_with_timing) — so they are reached here
// through hand-built Effect literals, which is exactly the case the check exists to catch.
@(test)
roster_check_refuses_a_speed_that_reads_a_speed_and_an_order_used_as_a_scale :: proc(t: ^testing.T) {
	item :: proc(effect: Effect) -> Roster_Item {
		f := ship_fitting_with_effects(Fitting{name = "Test", size = .Small, weight = 6, bulk = 10, tags = {.Artifact}}, effect)
		return Roster_Item{tier = .Splash, fitting = f}
	}

	reads_speed := Effect {
		verb       = .Modify_Speed,
		magnitude  = expr_quantity(.Own_Speed),
		site_scale = EFFECT_SITE_SCALE_AUTHORED,
	}
	testing.expect_value(t, roster_check(item(reads_speed)).fault, Roster_Fault.Speed_Reads_Speed)

	timed_speed := Effect {
		verb       = .Modify_Speed,
		magnitude  = expr_const(1),
		timing     = Timing_Once_Per_Battle{},
		site_scale = EFFECT_SITE_SCALE_AUTHORED,
	}
	testing.expect_value(t, roster_check(item(timed_speed)).fault, Roster_Fault.Speed_Carries_A_Timing)

	// An ordering comparison on the captain's order is a sentence about the integers the
	// orders happen to be numbered with, not about the orders.
	ordered := Effect {
		verb       = .Phase_Contribution,
		phase      = Phase.Fire,
		magnitude  = Expr {
			nodes = {
				0 = {kind = .Gate, compare = .Gte},
				1 = {kind = .Quantity, quantity = .Captains_Order},
				2 = {kind = .Const, value = i32(Captains_Order.Press_Fire)},
				3 = {kind = .Const, value = 3},
				4 = {kind = .Const, value = 0},
			},
			count = 5,
		},
		site_scale = EFFECT_SITE_SCALE_AUTHORED,
	}
	testing.expect_value(t, roster_check(item(ordered)).fault, Roster_Fault.Order_Is_Not_A_Scale)
}
