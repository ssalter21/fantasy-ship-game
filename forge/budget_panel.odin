package forge

import "core:fmt"
import ship "../core/ship"
import rl "vendor:raylib"

// The budget panel: the power budget rendered **as the equation, never as a verdict**.
//
// budget.odin is explicit that the formula has no optional term, so an author rearranges
// it for the magnitude they may spend rather than guessing a number and asking whether it
// passed. This panel therefore prints every term with its source beside it, and offers the
// inverse — pin the shape, read back the magnitude range that lands inside the band.
//
// Every number here comes from a call into core: roster_check for the verdict,
// effect_peak / effect_point_rate / effect_cost_factor / effect_cost for the per-effect
// line, ship_count_peaks for the census a synergy is priced against. Nothing is restated.

budget_pane :: proc(f: ^Forge, bounds: rl.Rectangle) {
	draft := workbench_item(f)^
	item := draft.item
	verdict := ship.roster_check(item)
	peaks := ship.ship_count_peaks()

	inner := panel(bounds, fmt.tprintf("Power budget  -  %s", name_text(draft.name)))
	form := form_begin(inner)

	form_line(&form, "allowance")
	grant := ship.budget_grant(item.fitting.size, item.tier)
	equation_row(
		&form,
		"grant",
		points_text(grant),
		fmt.tprintf(
			"(%d base + %d rank x %d) x POINT",
			ship.GRANT_SIZE_BASE[item.fitting.size],
			ship.GRANT_SIZE_RANK[item.fitting.size],
			int(item.tier),
		),
		FORGE_TEXT,
	)
	weight_allowance := ship.budget_weight_allowance(item.fitting.size, item.fitting.weight)
	equation_row(
		&form,
		"weight allowance",
		points_text(weight_allowance),
		fmt.tprintf(
			"%d vs default %d, at %d weight per point",
			item.fitting.weight,
			ship.WEIGHT_DEFAULT[item.fitting.size],
			ship.WEIGHT_PER_POINT,
		),
		weight_allowance < 0 ? FORGE_WARN : FORGE_TEXT,
	)
	equation_row(&form, "allowance", points_text(verdict.allowance), "grant + weight allowance", FORGE_TEXT)
	equation_row(
		&form,
		"band",
		fmt.tprintf("%s .. %s", points_text(verdict.low), points_text(verdict.high)),
		fmt.tprintf("+/- %d%%, never narrower than %s - two-sided", ship.BUDGET_BAND_PERCENT, points_text(ship.BUDGET_BAND_MINIMUM)),
		FORGE_TEXT,
	)

	form_line(&form, "cost")
	capacity_cost := ship.budget_capacity_cost(item.fitting)
	equation_row(
		&form,
		"capacity",
		points_text(capacity_cost),
		fmt.tprintf(
			"%d capacity at 1 point per %d, floored for anything that carries",
			ship.ship_fitting_capacity(item.fitting),
			ship.CAPACITY_PER_POINT,
		),
		FORGE_TEXT,
	)

	for i in 0 ..< item.fitting.effect_count {
		effect := item.fitting.effects[i]
		peak := ship.effect_peak(effect, peaks)
		rate := ship.effect_point_rate(effect)
		factor := ship.effect_cost_factor(effect)
		equation_row(
			&form,
			fmt.tprintf("effect %d", i + 1),
			points_text(ship.effect_cost(effect, peaks)),
			fmt.tprintf("peak %d x rate %s x factor %d%%", max(0, peak), points_text(rate), factor),
			i == f.workbench.effect ? FORGE_ACCENT : FORGE_TEXT,
		)
		if effect.verb == .Repair {
			form_note(
				&form,
				effect_burst_reason(effect),
				ship.effect_is_burst(effect) ? FORGE_PASS : FORGE_TEXT_DIM,
			)
			form_note(&form, "  gate factors are suppressed for Repair: burst is repair's conditionality discount", FORGE_TEXT_DIM)
		} else if ship.expr_is_conditional(effect.magnitude) {
			form_note(&form, fmt.tprintf("  %s", gate_factor_reason(effect.magnitude)), FORGE_TEXT_DIM)
		}
		if expr_peaks_at_nothing(effect.magnitude, peaks) {
			form_note(&form, "  this tree reads a quantity as its magnitude: it peaks at 0, so it prices at nothing", FORGE_FAULT)
		}
	}
	equation_row(&form, "cost", points_text(verdict.cost), "capacity + every effect", FORGE_TEXT)

	form_line(&form, "verdict")
	if verdict.fault == .None {
		form_note(&form, fmt.tprintf("clean: %s sits inside the band", points_text(verdict.cost)), FORGE_PASS)
	} else {
		form_note(&form, fmt.tprintf("%v - stopped at %s", verdict.fault, fault_stage(verdict.fault)), FORGE_FAULT)
		form_note(&form, "  the check reports the first fault it finds and short-circuits", FORGE_TEXT_DIM)
	}

	form_line(&form, "solve for magnitude")
	solve_for(f, &form, item, verdict, peaks)

	form_line(&form, "pricing census (ship_count_peaks)")
	peak_vector(&form, peaks)
}

// equation_row is one term of the formula: what it is, what it came to, and where it came
// from. The number is right-aligned on the mono step so the column reads as a sum.
@(private = "file")
equation_row :: proc(form: ^Form, label: string, value: string, source: string, color: u32) {
	row := form_row(form)
	draw_text(label, row.x, row.y + 5, color_of(color))
	draw_mono_right(value, row.x + row.width, row.y + 5, color_of(color))
	// The source sits between the label and the number, and is cut rather than allowed to
	// run under the number it is explaining.
	source_x := row.x + 108
	draw_text_clipped(source, source_x, row.y + 5, row.x + row.width - source_x - f32(len(value)) * mono_advance - 8, color_of(FORGE_TEXT_DIM))
}

// effect_burst_reason says whether repair earned the burst rate and **why** — by
// frequency, or by a gate on one of the two quantities that can turn off again inside a
// fight. A Press gate earns nothing: it rations by frequency but is free.
@(private = "file")
effect_burst_reason :: proc(effect: ship.Effect) -> string {
	switch _ in effect.timing {
	case ship.Timing_Once_Per_Battle:
		return "  burst: Once_Per_Battle pays for its one firing"
	case ship.Timing_Every_N:
		return "  burst: Every_N pays for each firing by frequency"
	case ship.Timing_Charge:
		return "  burst: Charge pays for each firing by frequency"
	case ship.Timing_Always, ship.Timing_Ramp:
	}
	if ship.expr_gates_on_quantity(effect.magnitude, .Damage_Taken_Last_Round) {
		return "  burst: gated on the damage taken last round, which can turn off again"
	}
	if ship.expr_gates_on_order(effect.magnitude, .Commit) {
		return "  burst: gated on Commit, which forfeits that round's Fire"
	}
	return "  sustained: each firing is not individually paid for, so it pays the full Repair rate"
}

// gate_factor_reason names the rules that actually fired, by walking **the path the
// magnitude rides** — the root, and then each open branch below a Gate — exactly as
// effect_cost_factor does. Reporting the first Gate in prefix order instead would announce
// a discount for a gate buried under arithmetic, which pays nothing.
@(private = "file")
gate_factor_reason :: proc(e: ship.Expr) -> string {
	if e.count > 0 && e.nodes[0].kind != .Gate {
		return "the gate is buried under arithmetic: it is part of the tree's value rather than a condition in front of it, so it pays nothing"
	}
	text := ""
	for index := 0; index < e.count && e.nodes[index].kind == .Gate; {
		if len(text) > 0 {
			text = fmt.tprintf("%s; then ", text)
		}
		text = fmt.tprintf("%s%s", text, gate_rule_at(e, index))
		_, _, then_branch := ship.expr_gate_comparands(e, index)
		index = then_branch
	}
	return text
}

// gate_rule_at names which published row budget_gate_factor read for one Gate. The factor
// is core's; this only says which rule produced it.
@(private = "file")
gate_rule_at :: proc(e: ship.Expr, index: int) -> string {
	lhs, rhs, _ := ship.expr_gate_comparands(e, index)
	factor := ship.budget_gate_factor(e, index)

	for quantity in ([]ship.Quantity{.Captains_Order, .Own_Visibility, .Damage_Taken_Last_Round}) {
		if ship.expr_reads_quantity(lhs, quantity) || ship.expr_reads_quantity(rhs, quantity) {
			return fmt.tprintf("gate on %v: %d%% - the author's to arrange, or as likely as not", quantity, factor)
		}
	}
	if ship.expr_reads_quantity(lhs, .Opponent_Speed) || ship.expr_reads_quantity(rhs, .Opponent_Speed) {
		return fmt.tprintf(
			"chase gate: %d%% - %s",
			factor,
			factor == ship.GATE_FACTOR_UNCONTROLLED ? "being outrun is the ordinary case" : "outrunning is the one the captain has to buy",
		)
	}
	if ship.expr_reads_quantity(lhs, .Own_Hull) || ship.expr_reads_quantity(rhs, .Own_Hull) {
		return fmt.tprintf("hull threshold: %d%% - soft at or above %d%%, remote below", factor, ship.GATE_SOFT_HULL_PERCENT)
	}
	if ship.expr_reads_quantity(lhs, .Round) || ship.expr_reads_quantity(rhs, .Round) {
		return fmt.tprintf("round threshold: %d%% - soft at or before round %d, remote beyond", factor, ship.GATE_SOFT_ROUND)
	}
	return fmt.tprintf("unrecognised gate: %d%% - the budget never discounts what it cannot read", factor)
}

// fault_stage is which stage of roster_check a fault stopped at. The check short-circuits,
// so a structural fault hides a band fault and the panel has to say which one it is
// looking at.
@(private = "file")
fault_stage :: proc(fault: ship.Roster_Fault) -> string {
	switch fault {
	case .None:
		return "nothing"
	case .Unnamed:
		return "the name check, before any pricing"
	case .Weight_Off_Band:
		return "the weight band, before any pricing"
	case .Bulk_Outside_Slot:
		return "the bulk check, before any pricing"
	case .Effect_Count_Off_Band:
		return "the effect count, before any pricing"
	case .Node_Bound_Overrun, .Speed_Reads_Speed, .Order_Is_Not_A_Scale, .Speed_Carries_A_Timing, .Peak_Output_Over_Cap:
		return "a per-effect check, so the band was never reached"
	case .Under_Band, .Over_Band:
		return "the band, with every term priced"
	}
	unreachable()
}

// solve_for is the inverse of the formula, which is the workflow budget.odin is written
// for: with the size, tier, weight and effect shape pinned, what magnitude lands inside
// the band? Every other term is already fixed, so the answer is a range rather than a
// search.
@(private = "file")
solve_for :: proc(f: ^Forge, form: ^Form, item: ship.Roster_Item, verdict: ship.Roster_Verdict, peaks: ship.Count_Table) {
	index := clamp(f.workbench.effect, 0, max(item.fitting.effect_count - 1, 0))
	if item.fitting.effect_count == 0 {
		return
	}
	effect := item.fitting.effects[index]

	// Everything the pinned shape already spends: the capacity option, and every effect
	// but the one being solved for.
	others := ship.budget_capacity_cost(item.fitting)
	for i in 0 ..< item.fitting.effect_count {
		if i != index {
			others += ship.effect_cost(item.fitting.effects[i], peaks)
		}
	}

	rate := int(ship.effect_point_rate(effect))
	factor := ship.effect_cost_factor(effect)
	unit := rate * factor // points per unit of peak, in hundredths x 100
	if unit <= 0 {
		form_note(form, "this effect has no price per unit of peak to invert", FORGE_TEXT_DIM)
		return
	}

	low_peak := ceil_div(max(int(verdict.low - others), 0) * 100, unit)
	high_peak := (int(verdict.high - others) * 100) / unit
	if ship.expr_is_conditional(effect.magnitude) {
		high_peak = min(high_peak, ship.PEAK_OUTPUT_CAP)
	}

	synergy := 1
	if selector, is_synergy := effect.synergy.?; is_synergy {
		synergy = max(ship.expr_selector_count(peaks, selector), 1)
	}
	ramp := 0
	if timing, ramps := effect.timing.(ship.Timing_Ramp); ramps {
		ramp = timing.cap
	}

	equation_row(
		form,
		fmt.tprintf("effect %d peak", index + 1),
		fmt.tprintf("%d .. %d", low_peak, high_peak),
		fmt.tprintf("at rate %s x factor %d%%, with %s spent elsewhere", points_text(ship.effect_point_rate(effect)), factor, points_text(others)),
		high_peak >= low_peak ? FORGE_TEXT : FORGE_FAULT,
	)
	equation_row(
		form,
		"  tree peak",
		fmt.tprintf("%d .. %d", low_peak / synergy - ramp, high_peak / synergy - ramp),
		fmt.tprintf("less a ramp's %d cap, over a synergy peak of %d", ramp, synergy),
		FORGE_TEXT_DIM,
	)
	if high_peak < low_peak {
		form_note(form, "  nothing lands inside the band at this shape: change the weight, the size or the tier", FORGE_FAULT)
	}
}

@(private = "file")
ceil_div :: proc(numerator: int, denominator: int) -> int {
	return (numerator + denominator - 1) / denominator
}

// peak_vector shows the census a synergy selector is priced against. It is derived by
// walking the real ship template, which makes **the layout a balance surface**: re-sizing
// a hold re-prices every counting item in the roster.
@(private = "file")
peak_vector :: proc(form: ^Form, peaks: ship.Count_Table) {
	tags := ""
	for tag in ship.Tag {
		tags = fmt.tprintf("%s%v %d  ", tags, tag, peaks.tag[tag])
	}
	sizes := ""
	for size in ship.Slot_Size {
		sizes = fmt.tprintf("%s%v %d  ", sizes, size, peaks.size[size])
	}
	visibility := ""
	for seen in ship.Visibility {
		visibility = fmt.tprintf("%s%v %d  ", visibility, seen, peaks.visibility[seen])
	}
	form_note(form, tags, FORGE_TEXT_DIM)
	form_note(form, sizes, FORGE_TEXT_DIM)
	form_note(form, visibility, FORGE_TEXT_DIM)
}

// Probe is the context the Compared reading is poked with: one scalar per Quantity and a
// census per side. It is the tool's only invented data — everything else it shows is read
// off the content — so it is held apart from Content and never emitted.
Probe :: struct {
	quantities: [ship.Quantity]int,
	own:        ship.Count_Table,
	opponent:   ship.Count_Table,
	side:       int,
}

// probe_default is a plausible mid-battle round rather than a context of zeroes, which
// would answer every gate with "shut" and read as "this item does nothing".
probe_default :: proc() -> (p: Probe) {
	p.quantities[.Own_Hull] = ship.STARTING_HULL / 2
	p.quantities[.Own_Max_Hull] = ship.STARTING_HULL
	p.quantities[.Own_Speed] = ship.STARTING_SPEED
	p.quantities[.Opponent_Speed] = ship.STARTING_SPEED
	p.quantities[.Round] = 1
	for tag in ship.Tag {
		p.own.tag[tag] = 1
	}
	for size in ship.Slot_Size {
		p.own.size[size] = 1
	}
	for seen in ship.Visibility {
		p.own.visibility[seen] = 1
	}
	return
}

probe_context :: proc(p: Probe) -> ship.Expr_Context {
	return ship.Expr_Context{quantities = p.quantities, counts = p.own, opponent = p.opponent}
}

// readings_pane shows the same tree answering the three different questions an author
// needs at once: a real round against a context they can poke, the item-card reading
// presentation shows, and the pricing reading the budget charges for.
readings_pane :: proc(f: ^Forge, bounds: rl.Rectangle) {
	item := workbench_item(f).item
	inner := panel(bounds, "Three readings of the tree")
	form := form_begin(inner)
	if item.fitting.effect_count == 0 {
		return
	}
	effect := item.fitting.effects[clamp(f.workbench.effect, 0, item.fitting.effect_count - 1)]
	peaks := ship.ship_count_peaks()

	equation_row(
		&form,
		"expr_eval",
		fmt.tprintf("%d", ship.expr_eval(effect.magnitude, probe_context(f.workbench.probe))),
		"a real round, against the context below",
		FORGE_TEXT,
	)
	equation_row(
		&form,
		"expr_showcase",
		fmt.tprintf("%d", ship.expr_showcase(effect.magnitude)),
		"every gate open, every count 1 - the item-card reading",
		FORGE_TEXT,
	)
	equation_row(
		&form,
		"expr_peak",
		fmt.tprintf("%d", ship.expr_peak(effect.magnitude, peaks)),
		"every gate at its larger branch, every count at its peak",
		FORGE_ACCENT,
	)
	equation_row(
		&form,
		"effect peak",
		fmt.tprintf("%d", ship.effect_peak(effect, peaks)),
		"the tree's peak, ramped, site-scaled, times the synergy count",
		FORGE_ACCENT,
	)

	form_line(&form, "probe")
	// Two to a row: the probe is eight scalars and a census, and a pane that spent a row on
	// each would push the census off the bottom of the panel.
	row: rl.Rectangle
	for quantity, index in ship.Quantity {
		if index % 2 == 0 {
			row = form_row(&form)
		}
		half := row.width / 2
		x := row.x + f32(index % 2) * half
		draw_text_clipped(fmt.tprintf("%v", quantity), x, row.y + 5, half - 60, color_of(FORGE_TEXT_DIM))
		value := f.workbench.probe.quantities[quantity]
		if ui_value(&f.ui, {x + half - 56, row.y, 48, row.height}, &value, -999, 999, "a scalar the Compared reading resolves against") {
			f.workbench.probe.quantities[quantity] = value
		}
	}
	form_note(&form, "order: Hold 0, Press_Brace 1, Press_Fire 2, Commit 3   visibility: Exposed 0, Concealed 1", FORGE_TEXT_DIM)

	side_row := form_row(&form)
	ui_enum(&f.ui, {side_row.x, side_row.y, 150, side_row.height}, "census: Own;census: Opponent", &f.workbench.probe.side, 2, "Own is this ship; Opponent is the scouting report, which sees no concealed fitting")
	census := f.workbench.probe.side == 0 ? &f.workbench.probe.own : &f.workbench.probe.opponent
	census_grid(f, &form, census)
}

// census_grid edits one side's Count_Table: one spinner per criterion on each of the three
// selector axes, laid out as a grid because that is what a census is.
@(private = "file")
census_grid :: proc(f: ^Forge, form: ^Form, census: ^ship.Count_Table) {
	row := form_row(form)
	x := row.x
	for tag in ship.Tag {
		draw_text(fmt.tprintf("%v", tag)[:2], x, row.y + 5, color_of(FORGE_TEXT_DIM))
		ui_value(&f.ui, {x + 20, row.y, 34, row.height}, &census.tag[tag], 0, 99, "how many fittings carry this tag")
		x += 60
	}
	row = form_row(form)
	x = row.x
	for size in ship.Slot_Size {
		draw_text(fmt.tprintf("%v", size)[:2], x, row.y + 5, color_of(FORGE_TEXT_DIM))
		ui_value(&f.ui, {x + 20, row.y, 34, row.height}, &census.size[size], 0, 99, "how many fittings are of this slot size")
		x += 60
	}
	row = form_row(form)
	x = row.x
	for seen in ship.Visibility {
		draw_text(fmt.tprintf("%v", seen)[:2], x, row.y + 5, color_of(FORGE_TEXT_DIM))
		ui_value(&f.ui, {x + 20, row.y, 34, row.height}, &census.visibility[seen], 0, 99, "how many fittings sit in a slot of this visibility")
		x += 60
	}
}
