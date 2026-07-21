package ship

// The power budget (CONTEXT.md, "The power budget"): the one place the grant table, the
// band, the verb rates, the node cost factors and the gate factors are published, and
// `roster_check`, the pure arithmetic that prices one authored Roster_Item against them.
//
// **The unit is one magnitude of Fire**, so the grant table reads directly as licensed
// magnitudes. An item's allowance is its size x tier cell, moved by its weight; its cost is
// its effects plus its capacity; legality is the two meeting inside a band.
//
// **The formula has no optional term**, so an author rearranges it for the magnitude they
// may spend rather than guessing a number and asking whether it passed. This confirms that
// arithmetic and cannot replace it: an item must compile to be checked at all.

// Points is a budget quantity in **hundredths of a point**, distinct from a plain int
// (ADR-0011) so a price is never passed where a magnitude belongs. Hundredths because the
// published rates and factors are 0.5, 0.7, 2.0 and 3.0: whole points cannot hold their
// products, and rounding each term as it lands would let a price depend on the order the
// terms were multiplied in.
Points :: distinct int

// POINT is one point — one magnitude of Fire, five hull of swing over the reference fight.
POINT :: Points(100)

// GRANT_SIZE_BASE and GRANT_SIZE_RANK are the grant table, spelled as the two ladders it
// is built from: a cell grants `base[size] + rank[size] x tier_index`, so tier buys more in
// a bigger slot. Convex in size on purpose — a steeper size ladder would leave the tier
// ladder decreasing.
@(rodata)
GRANT_SIZE_BASE := [Slot_Size]int {
	.Small  = 3,
	.Medium = 4,
	.Large  = 6,
}

@(rodata)
GRANT_SIZE_RANK := [Slot_Size]int {
	.Small  = 1,
	.Medium = 2,
	.Large  = 3,
}

// BUDGET_BAND_PERCENT and BUDGET_BAND_MINIMUM are the legality band around a grant, taken
// on the **total** cost and **two-sided**: an item too weak to be worth its slot is
// rejected as loudly as one too strong. The minimum keeps the smallest cells from having
// no band at all.
BUDGET_BAND_PERCENT :: 25
BUDGET_BAND_MINIMUM :: POINT

// VERB_POINT_RATE is what one magnitude of each verb costs. Fire is the numeraire; Speed
// costs three because 10 weight is 1 speed and 3 weight is 1 point; sustained repair costs
// two.
@(rodata)
VERB_POINT_RATE := [Verb]Points {
	.Phase_Contribution = POINT,
	.Repair             = 2 * POINT,
	.Modify_Speed       = 3 * POINT,
}

// REPAIR_BURST_POINT_RATE is repair's second rate. Repair needs two because the
// press-competitiveness floor and the turtle ceiling are opposite demands on one number:
// the timing axis reconciles them, a price cannot.
//
// It is **earned when each individual firing is paid for** — by frequency (Once_Per_Battle,
// Charge, Every_N) or by cost (a Commit gate, which forfeits a round of Fire) — or by a
// gate whose quantity can turn off again inside a fight, of which there are exactly two
// (the captain's order and the damage taken last round). A Press gate earns nothing: Press
// rations by frequency but is free.
REPAIR_BURST_POINT_RATE :: POINT / 2

// NODE_COST_FACTOR is every node kind's cost factor as a percent, read through
// budget_node_factor. Count publishes no discount because a tag count resolves at purchase
// time and the purchase is optional, so the author controls it; Min, Max and Pct need none
// because the peak already reflects them and pricing them again double-counts. `Gate` alone
// carries a **per-quantity** factor, and its entry here is the no-discount case
// budget_gate_factor falls back to.
@(rodata)
NODE_COST_FACTOR := [Node_Kind]int {
	.Const    = 100,
	.Quantity = 100,
	.Count    = 100,
	.Add      = 100,
	.Sub      = 100,
	.Mul      = 100,
	.Min      = 100,
	.Max      = 100,
	.Pct      = 100,
	.Gate     = GATE_FACTOR_UNCONTROLLED,
}

// The three gate factors, and the floor their product cannot pass. **A gate prices
// uncertainty, so a gate the author controls gets no discount**: the captain's own order,
// the slot's own visibility, and the two readings that are as likely as not all pay full.
// A soft condition (a hull threshold at or above half, an early round) pays 0.7, and one
// that may never arrive at all pays 0.5.
GATE_FACTOR_UNCONTROLLED :: 100
GATE_FACTOR_SOFT :: 70
GATE_FACTOR_REMOTE :: 50
GATE_FACTOR_FLOOR :: 50

// GATE_SOFT_HULL_PERCENT and GATE_SOFT_ROUND are where the two threshold-carrying gates
// cross from soft to remote: a hull gate at or above half the pool is a condition a fight
// reaches, and so is an early round; below and beyond, the item may never fire at all.
GATE_SOFT_HULL_PERCENT :: 50
GATE_SOFT_ROUND :: 3

// WEIGHT_DEFAULT is the derived per-size weight an item is authored around, and
// WEIGHT_DEVIATION_PERCENT how far either way it may be authored from it. Weight is the
// **one sanctioned way to be slow**, and it converts into and out of allowance rather than
// into cost: Speed is `base + sum(Modify_Speed) - weight/10`, so 10 weight is 1 speed is 3
// points, hence WEIGHT_PER_POINT.
@(rodata)
WEIGHT_DEFAULT := [Slot_Size]int {
	.Small  = 6,
	.Medium = 18,
	.Large  = 40,
}

WEIGHT_DEVIATION_PERCENT :: 50
WEIGHT_PER_POINT :: 3

// CAPACITY_PER_POINT is what a point of capacity buys. Capacity is priced as an **option,
// not as cargo**: a carried unit is already a wash against the weight it adds, so what
// capacity buys is only the option on a windfall that would otherwise spill. **Low bulk is
// never rewarded** — the grant table already priced full bulk, so a refund would be a
// double-count, which is why the cost has a floor and no negative branch.
CAPACITY_PER_POINT :: 20

// PEAK_OUTPUT_CAP bounds `peak magnitude x selector peak` for a **gated** effect. Ungated
// effects need no cap: with Count at factor 1.0 the cost of a pure-count effect *is* its
// peak, so the band bounds those directly — but a gate discounts the price without
// shrinking the number that lands, so the discount alone could buy an unbounded spike.
PEAK_OUTPUT_CAP :: 24

// Roster_Fault is what one authored item got wrong, `.None` when it got nothing wrong.
// A single fault rather than a list: the check reports the first thing it finds, and the
// author fixes one thing at a time.
Roster_Fault :: enum {
	None,
	Unnamed,
	Weight_Off_Band,
	Bulk_Outside_Slot,
	Effect_Count_Off_Band,
	Node_Bound_Overrun,
	Speed_Reads_Speed,
	Order_Is_Not_A_Scale,
	Speed_Carries_A_Timing,
	Peak_Output_Over_Cap,
	Under_Band,
	Over_Band,
}

// Roster_Verdict is the check's answer **as the equation, never as a verdict**: the item it
// is about, the fault if there is one, and the three numbers whose relation decides
// legality — so a caller reports the line an author should disagree with rather than a yes
// or a no. Plain data holding the item's authored name, so a failing build names the one
// file's worth of work it is asking for.
Roster_Verdict :: struct {
	item:      string,
	fault:     Roster_Fault,
	cost:      Points,
	allowance: Points,
	low:       Points,
	high:      Points,
}

// budget_grant is one cell of the grant table: what a size and tier license an item to
// spend before weight moves it.
budget_grant :: proc(size: Slot_Size, tier: Tier) -> Points {
	return Points((GRANT_SIZE_BASE[size] + GRANT_SIZE_RANK[size] * int(tier)) * int(POINT))
}

// budget_band is the published min/max for a cell: the grant either way by a quarter
// of it, rounded half-up to whole points and never narrower than one. The band is a
// property of the **cell**, so the two bounds move with an item's weight only through the
// allowance it is compared against (roster_check).
budget_band :: proc(size: Slot_Size, tier: Tier) -> (low: Points, high: Points) {
	grant := budget_grant(size, tier)
	quarter := int(grant) * BUDGET_BAND_PERCENT / 100
	band := max(BUDGET_BAND_MINIMUM, Points(budget_round_half_up(quarter, int(POINT)) * int(POINT)))
	return grant - band, grant + band
}

// budget_weight_band is the weight a size is authored around, either way by
// WEIGHT_DEVIATION_PERCENT. The deviation is what keeps the light-fast / heavy-gunship axis
// authorable without freehand weights walking the hostile straddle off its feet.
budget_weight_band :: proc(size: Slot_Size) -> (low: int, high: int) {
	default := WEIGHT_DEFAULT[size]
	deviation := budget_round_half_up(default * WEIGHT_DEVIATION_PERCENT, 100)
	return default - deviation, default + deviation
}

// budget_weight_allowance is what an item's weight is worth in allowance: heavier than its
// size's default earns points at WEIGHT_PER_POINT, lighter spends them at the same rate. Its
// own proc rather than a line inside the check, because it is the term an author drops.
budget_weight_allowance :: proc(size: Slot_Size, weight: int) -> Points {
	return Points(budget_round_half_up((weight - WEIGHT_DEFAULT[size]) * int(POINT), WEIGHT_PER_POINT))
}

// budget_capacity_cost prices what a fitting can carry: one point per CAPACITY_PER_POINT of
// capacity, floored at a whole point for anything that carries at all, and nothing for an
// item that carries nothing. At zero bulk that is Small 1 / Medium 1 / Large 2.
budget_capacity_cost :: proc(fitting: Fitting) -> Points {
	capacity := ship_fitting_capacity(fitting)
	if capacity <= 0 {
		return 0
	}
	return Points(max(1, budget_round_half_up(capacity, CAPACITY_PER_POINT)) * int(POINT))
}

// ship_count_peaks is the census a pricing walk reads: the most of each countable thing one
// ship can ever hold, **derived by walking the real ship template** rather than transcribed.
// A tag's peak is the whole layout — every slot could hold a fitting carrying it — while a
// size's and a visibility's are the slots that are of it.
//
// Deriving it is what makes the **ship layout a balance surface**: re-sizing a hold
// re-prices every counting item in the roster, and the pinned peak vector is where that is
// answered for rather than discovered in playtest.
ship_count_peaks :: proc() -> Count_Table {
	layout := ship_template_layout()
	defer delete(layout)

	peaks: Count_Table
	for layout_slot in layout {
		peaks.size[layout_slot.slot.size] += 1
		peaks.visibility[layout_slot.slot.base_visibility] += 1
	}
	for tag in Tag {
		peaks.tag[tag] = len(layout)
	}
	return peaks
}

// effect_peak is the magnitude an effect prices at: its tree's peak (expr_peak) plus
// everything a ramp can add to it, taken to the effect's site scale, times the count a
// synergy selector can reach. It is the same composition effect_magnitude resolves a round
// with, read at its ceiling.
effect_peak :: proc(effect: Effect, peaks: Count_Table) -> int {
	growth := 0
	if ramp, ramps := effect.timing.(Timing_Ramp); ramps {
		growth = ramp.cap
	}
	peak := effect_site_scaled(expr_peak(effect.magnitude, peaks) + growth, effect)
	if selector, is_synergy := effect.synergy.?; is_synergy {
		peak *= expr_selector_count(peaks, selector)
	}
	return peak
}

// effect_point_rate is the verb's rate for this effect: the published per-verb rate,
// except that repair drops to the burst rate when each of its firings is individually paid
// for (effect_is_burst).
effect_point_rate :: proc(effect: Effect) -> Points {
	if effect.verb == .Repair && effect_is_burst(effect) {
		return REPAIR_BURST_POINT_RATE
	}
	return VERB_POINT_RATE[effect.verb]
}

// effect_is_burst reports whether each individual firing of `effect` is paid for: by
// frequency, which is three of the five timings, or by cost — a **gate** on the captain's
// order matched against Commit, which forfeits that round's Fire, or on the damage taken
// last round. Press is deliberately not here: it rations by frequency but costs nothing.
//
// The two quantities are the only two that can turn *off* again inside a fight, which is
// what makes this one line rather than a taxonomy: everything else a gate can read, once
// true, stays true. It must be a gate — a tree that merely multiplies by the damage taken
// still fires every round, so it has bought nothing.
effect_is_burst :: proc(effect: Effect) -> bool {
	switch _ in effect.timing {
	case Timing_Once_Per_Battle, Timing_Every_N, Timing_Charge:
		return true
	case Timing_Always, Timing_Ramp:
	}
	if expr_gates_on_quantity(effect.magnitude, .Damage_Taken_Last_Round) {
		return true
	}
	return expr_gates_on_order(effect.magnitude, .Commit)
}

// effect_cost_factor is the product of the cost factors on the path the effect's magnitude
// actually rides — the root, and then each open branch below a Gate, floored at
// GATE_FACTOR_FLOOR. Nesting is how `and` is spelled, so nested gates compound; a gate
// buried under arithmetic is part of that tree's value rather than a condition standing in
// front of it, and pays nothing.
//
// **Suppressed for Repair**: burst *is* repair's conditionality discount, and charging both
// prices the same conditionality twice. The side effect is the one the defensive roster
// needed — gates become free distinctness on burst repair.
effect_cost_factor :: proc(effect: Effect) -> int {
	if effect.verb == .Repair {
		return GATE_FACTOR_UNCONTROLLED
	}
	e := effect.magnitude
	factor, index := 100, 0
	for index < e.count {
		factor = factor * budget_node_factor(e, index) / 100
		if e.nodes[index].kind != .Gate {
			break
		}
		_, _, then_branch := expr_gate_comparands(e, index)
		index = then_branch
	}
	return max(GATE_FACTOR_FLOOR, factor)
}

// budget_node_factor is what the node at `index` costs its effect, as a percent: the
// published per-kind factor, refined for a Gate by the quantity it turns on.
budget_node_factor :: proc(e: Expr, index: int) -> int {
	if e.nodes[index].kind != .Gate {
		return NODE_COST_FACTOR[e.nodes[index].kind]
	}
	return budget_gate_factor(e, index)
}

// budget_gate_factor prices the uncertainty of the Gate node at `index` from the quantity
// it turns on. An unrecognised gate pays full: the budget never discounts what it cannot
// read.
budget_gate_factor :: proc(e: Expr, index: int) -> int {
	lhs, rhs, _ := expr_gate_comparands(e, index)

	// The captain's order and the slot's own visibility are the author's to arrange, and
	// the damage taken last round is as likely as not: none of the three is uncertainty.
	for quantity in ([]Quantity{.Captains_Order, .Own_Visibility, .Damage_Taken_Last_Round}) {
		if expr_reads_quantity(lhs, quantity) || expr_reads_quantity(rhs, quantity) {
			return GATE_FACTOR_UNCONTROLLED
		}
	}

	// A chase gate: being outrun is the ordinary case and pays full, outrunning is the
	// one the captain has to buy.
	if expr_reads_quantity(lhs, .Opponent_Speed) || expr_reads_quantity(rhs, .Opponent_Speed) {
		op := e.nodes[index].compare
		opponent_on_the_left := expr_reads_quantity(lhs, .Opponent_Speed)
		opens_on_a_faster_opponent := (op == .Gt || op == .Gte) == opponent_on_the_left
		return opens_on_a_faster_opponent ? GATE_FACTOR_UNCONTROLLED : GATE_FACTOR_REMOTE
	}

	// The two threshold gates: a hull fraction (written as a cross-multiplication, so the
	// percent sits beside the max-Hull reading) and a round number.
	if expr_reads_quantity(lhs, .Own_Hull) || expr_reads_quantity(rhs, .Own_Hull) {
		percent := expr_reads_quantity(lhs, .Own_Max_Hull) ? expr_first_const(lhs) : expr_first_const(rhs)
		return percent >= GATE_SOFT_HULL_PERCENT ? GATE_FACTOR_SOFT : GATE_FACTOR_REMOTE
	}
	if expr_reads_quantity(lhs, .Round) || expr_reads_quantity(rhs, .Round) {
		round := expr_reads_quantity(lhs, .Round) ? expr_first_const(rhs) : expr_first_const(lhs)
		return round <= GATE_SOFT_ROUND ? GATE_FACTOR_SOFT : GATE_FACTOR_REMOTE
	}
	return GATE_FACTOR_UNCONTROLLED
}

// effect_cost is one effect's price: its peak magnitude at its verb's rate, discounted by
// what its gates make uncertain. Every term is mandatory, which is the whole design — a
// formula with an optional term still returns green when the term is dropped.
//
// **A negative magnitude never refunds allowance, for any verb**: a drawback is free exactly
// when you do not care about it, so an effect that only ever subtracts is priced at nothing
// rather than paid for. Weight remains the one sanctioned way to be slow.
effect_cost :: proc(effect: Effect, peaks: Count_Table) -> Points {
	peak := max(0, effect_peak(effect, peaks))
	return Points(peak * int(effect_point_rate(effect)) * effect_cost_factor(effect) / 100)
}

// roster_check prices one authored Roster_Item against the published budget and reports
// what it found. Pure arithmetic over the item alone: it reads no other item, no shop and no
// battle, so a failing build points at one file's worth of work.
//
// The structural faults are checked first and short-circuit, because an item that overruns
// the node bound or authors a speed that reads a speed has no meaningful price to report.
// The band comes last, and is **two-sided**: the returned verdict carries the cost, the
// allowance and the two bounds whether or not it passed.
roster_check :: proc(item: Roster_Item) -> Roster_Verdict {
	f := item.fitting
	low, high := budget_band(f.size, item.tier)
	verdict := Roster_Verdict{item = f.name, low = low, high = high}

	if len(f.name) == 0 {
		verdict.fault = .Unnamed
		return verdict
	}
	if weight_low, weight_high := budget_weight_band(f.size); f.weight < weight_low || f.weight > weight_high {
		verdict.fault = .Weight_Off_Band
		return verdict
	}
	if f.bulk < 0 || f.bulk > ship_cargo_slot_contribution(f.size) {
		verdict.fault = .Bulk_Outside_Slot
		return verdict
	}
	if f.effect_count <= 0 || f.effect_count > FITTING_MAX_EFFECTS {
		verdict.fault = .Effect_Count_Off_Band
		return verdict
	}

	peaks := ship_count_peaks()
	cost := budget_capacity_cost(f)
	for i in 0 ..< f.effect_count {
		effect := f.effects[i]
		if fault := effect_fault(effect, peaks); fault != .None {
			verdict.fault = fault
			return verdict
		}
		cost += effect_cost(effect, peaks)
	}

	// The band's width is the cell's; weight converts into and out of the allowance, and
	// carries the two bounds with it.
	weight_allowance := budget_weight_allowance(f.size, f.weight)
	verdict.cost = cost
	verdict.allowance = budget_grant(f.size, item.tier) + weight_allowance
	verdict.low += weight_allowance
	verdict.high += weight_allowance
	switch {
	case cost < verdict.low:
		verdict.fault = .Under_Band
	case cost > verdict.high:
		verdict.fault = .Over_Band
	}
	return verdict
}

// effect_fault is the per-effect half of the check: the node bound, the layering rule,
// the captain's-order encoding, and the peak-output cap. Each of these is also refused where
// the effect is *authored* (expr_gate, effect_modify_speed, effect_with_timing); stating them
// again here is what lets the whole contract be read in one place, and what would catch a
// hand-built Effect literal that never went through a helper.
effect_fault :: proc(effect: Effect, peaks: Count_Table) -> Roster_Fault {
	e := effect.magnitude
	if e.count <= 0 || e.count > EXPR_MAX_NODES {
		return .Node_Bound_Overrun
	}
	if effect.verb == .Modify_Speed {
		if expr_reads_quantity(e, .Own_Speed) || expr_reads_quantity(e, .Opponent_Speed) {
			return .Speed_Reads_Speed
		}
		if _, always := effect.timing.(Timing_Always); !always {
			return .Speed_Carries_A_Timing
		}
	}
	if expr_scales_the_captains_order(e) {
		return .Order_Is_Not_A_Scale
	}
	if expr_is_conditional(e) && effect_peak(effect, peaks) > PEAK_OUTPUT_CAP {
		return .Peak_Output_Over_Cap
	}
	return .None
}

// budget_round_half_up divides, rounding halves away from zero on both signs — so a weight
// deviation and a capacity round the same way in each direction, rather than the truncation
// the expression language uses.
@(private = "file")
budget_round_half_up :: proc(numerator: int, denominator: int) -> int {
	if numerator < 0 {
		return -((-numerator + denominator / 2) / denominator)
	}
	return (numerator + denominator / 2) / denominator
}
