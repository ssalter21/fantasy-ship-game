package forge

import "core:fmt"
import ship "../core/ship"
import rl "vendor:raylib"

// The effect and expression editors: an item's up-to-three effects, and the magnitude
// tree each of them resolves.
//
// The tree is edited as a tree — a prefix walk drawn with its structure indented — and
// every edit goes through expr_commit, which checks the candidate against the authoring
// rules and then reassembles it through core's own expr_* helpers. So an ill-formed tree
// is unrepresentable rather than rejected, and a rule that would have asserted on emit is
// refused at the keystroke with the rule attached.

// NODE_CHILD_ROLE names what each of a node's children *is*, so a Gate's four subtrees
// read as a condition and two branches rather than as four anonymous rows.
@(rodata)
NODE_CHILD_ROLE := [ship.Node_Kind][ship.EXPR_MAX_ARITY]string {
	.Const    = {"", "", "", ""},
	.Quantity = {"", "", "", ""},
	.Count    = {"", "", "", ""},
	.Add      = {"+", "+", "", ""},
	.Sub      = {"from", "less", "", ""},
	.Mul      = {"x", "x", "", ""},
	.Min      = {"min", "min", "", ""},
	.Max      = {"max", "max", "", ""},
	.Pct      = {"value", "percent", "", ""},
	.Gate     = {"if", "vs", "then", "else"},
}

// effect_pane is one effect's whole vocabulary: verb, timing, synergy, and the tree.
effect_pane :: proc(f: ^Forge, bounds: rl.Rectangle) {
	fitting := &workbench_item(f).item.fitting
	f.workbench.effect = clamp(f.workbench.effect, 0, max(fitting.effect_count - 1, 0))

	inner := panel(bounds, fmt.tprintf("Effects  (%d of %d)", fitting.effect_count, ship.FITTING_MAX_EFFECTS))
	form := form_begin(inner)

	tabs := form_row(&form)
	width := f32(58)
	for i in 0 ..< fitting.effect_count {
		tab := rl.Rectangle{tabs.x + f32(i) * (width + FORGE_GAP), tabs.y, width, tabs.height}
		if ui_button(&f.ui, tab, fmt.tprintf("effect %d", i + 1), "select which of the fitting's effects to edit") {
			f.workbench.effect = i
			f.workbench.node = 0
		}
		if i == f.workbench.effect {
			rl.DrawRectangleRec({tab.x, tab.y + tab.height - 2, tab.width, 2}, color_of(FORGE_ACCENT))
		}
	}
	buttons := tabs.x + 3 * (width + FORGE_GAP)
	if fitting.effect_count < ship.FITTING_MAX_EFFECTS &&
	   ui_button(&f.ui, {buttons, tabs.y, 40, tabs.height}, "add", "a fitting carries at most FITTING_MAX_EFFECTS effects") {
		fitting.effects[fitting.effect_count] = ship.effect_phase_contribution(ship.expr_const(1))
		fitting.effect_count += 1
		f.workbench.effect = fitting.effect_count - 1
	}
	if fitting.effect_count > 1 &&
	   ui_button(&f.ui, {buttons + 44, tabs.y, 52, tabs.height}, "remove", "an item with no effects fails at Effect_Count_Off_Band") {
		for i in f.workbench.effect ..< fitting.effect_count - 1 {
			fitting.effects[i] = fitting.effects[i + 1]
		}
		fitting.effect_count -= 1
		f.workbench.effect = clamp(f.workbench.effect, 0, fitting.effect_count - 1)
	}

	effect := &fitting.effects[f.workbench.effect]
	effect_fields(f, &form, effect)
	form_line(&form, "magnitude")
	preset_row(f, &form, effect)
	tree_view(f, form_remaining(&form), effect)
}

// effect_fields is the effect's own vocabulary, with the two fields that are **not**
// authored rendered as derived: the phase is read off the verb, and the site scale is
// 100 for everything an author writes.
@(private = "file")
effect_fields :: proc(f: ^Forge, form: ^Form, effect: ^ship.Effect) {
	verb_options, verb_count := enum_options(ship.Verb)
	verb := int(effect.verb)
	if ui_enum(&f.ui, form_field(form, "verb"), verb_options, &verb, verb_count, "what the resolved magnitude does, and so which consumer reads it") {
		candidate := effect^
		candidate.verb = ship.Verb(verb)
		candidate.phase = ship.ship_verb_phase(candidate.verb)
		if candidate.verb == .Modify_Speed {
			// The timing control **locks** to Always for this verb rather than being
			// refused, so choosing the verb sets the timing the verb admits instead of
			// bouncing off whatever the effect happened to be firing on.
			candidate.timing = ship.Timing_Always{}
		}
		effect_try(f, effect, candidate)
	}

	phase, feeds := effect.phase.?
	ui_derived(
		form_field(form, "phase", 96),
		feeds ? fmt.tprintf("%v", phase) : "none",
		"derived from the verb (ship_verb_phase)",
	)

	timing_locked := effect.verb == .Modify_Speed
	timing_field := form_field(form, "timing", 116)
	if timing_locked {
		ui_derived(timing_field, "Always", "locked: a Modify_Speed effect may not carry a timing")
	} else {
		timing_options, timing_count := timing_option_list()
		timing := timing_index(effect.timing)
		if ui_enum(&f.ui, timing_field, timing_options, &timing, timing_count, "when the effect resolves at all across a battle") {
			candidate := effect^
			candidate.timing = timing_of(timing, effect.timing)
			effect_try(f, effect, candidate)
		}
		timing_parameters(f, form, effect)
	}

	axis_field := form_field(form, "synergy", 116)
	axis := synergy_axis(effect.synergy)
	if ui_enum(&f.ui, axis_field, "none;Tag;Slot_Size;Visibility", &axis, 4, "scales the resolved magnitude by the count of matching fittings") {
		candidate := effect^
		candidate.synergy = axis == 0 ? nil : selector_of(axis - 1, 0)
		effect_try(f, effect, candidate)
	}
	if selector, is_synergy := effect.synergy.?; is_synergy {
		value_field := rl.Rectangle{axis_field.x + axis_field.width + FORGE_GAP, axis_field.y, 116, axis_field.height}
		options, count := selector_value_options(axis - 1)
		value := selector_value(selector)
		if ui_enum(&f.ui, value_field, options, &value, count, "the criterion on the selector's one axis") {
			candidate := effect^
			candidate.synergy = selector_of(axis - 1, value)
			effect_try(f, effect, candidate)
		}
	}

	ui_derived(
		form_field(form, "site scale", 96),
		fmt.tprintf("%d", effect.site_scale),
		"EFFECT_SITE_SCALE_AUTHORED; only a Fight site moves it",
	)
}

// timing_parameters draws the settings the chosen timing carries, and nothing for the two
// that carry none. A cadence of zero and a charge that never fills are refused here
// rather than met by the resolver.
@(private = "file")
timing_parameters :: proc(f: ^Forge, form: ^Form, effect: ^ship.Effect) {
	switch t in effect.timing {
	case ship.Timing_Always, ship.Timing_Once_Per_Battle:
	case ship.Timing_Every_N:
		n := t.n
		if ui_value(&f.ui, form_field(form, "  every n rounds", 72), &n, 1, 99, "fires on every nth round and nothing between") {
			candidate := effect^
			candidate.timing = ship.Timing_Every_N{n = n}
			effect_try(f, effect, candidate)
		}
	case ship.Timing_Ramp:
		per_round, cap_value := t.per_round, t.cap
		changed := ui_value(&f.ui, form_field(form, "  per round", 72), &per_round, 0, 99, "added for each round past the first")
		changed ||= ui_value(&f.ui, form_field(form, "  cap", 72), &cap_value, 0, 99, "the most a ramp may add in total; the budget charges for it")
		if changed {
			candidate := effect^
			candidate.timing = ship.Timing_Ramp{per_round = per_round, cap = cap_value}
			effect_try(f, effect, candidate)
		}
	case ship.Timing_Charge:
		cost, per_round := t.cost, t.per_round
		changed := ui_value(&f.ui, form_field(form, "  cost", 72), &cost, 1, 99, "the charge a firing spends")
		changed ||= ui_value(&f.ui, form_field(form, "  per round", 72), &per_round, 1, 99, "the charge banked each round")
		if changed {
			candidate := effect^
			candidate.timing = ship.Timing_Charge{cost = cost, per_round = per_round}
			effect_try(f, effect, candidate)
		}
	}
}

// preset_row offers each of expr.odin's composed shapes as a one-click subtree at the
// selected node. What it drops is ordinary nodes, still editable — a preset is a starting
// point, not a closed set an author picks from.
@(private = "file")
preset_row :: proc(f: ^Forge, form: ^Form, effect: ^ship.Effect) {
	row := form_row(form)
	options, count := enum_options(Preset)
	ui_enum(&f.ui, {row.x, row.y, 150, row.height}, options, &f.workbench.preset, count, "a composed shape to drop at the selected node")

	preset := Preset(f.workbench.preset)
	x := row.x + 154
	if preset_takes_threshold(preset) {
		ui_value(&f.ui, {x, row.y, 48, row.height}, &f.workbench.threshold, 0, 100, "the preset's threshold: a hull percent, or a round number")
		x += 52
	}
	ui_value(&f.ui, {x, row.y, 48, row.height}, &f.workbench.magnitude, -99, 99, "the magnitude the preset pays out when its condition holds")
	x += 52

	if ui_button(&f.ui, {x, row.y, 96, row.height}, "insert here", "replaces the selected node's subtree with the preset") {
		sub := preset_expr(preset, f.workbench.threshold, f.workbench.magnitude)
		if candidate, ok := expr_graft(effect.magnitude, f.workbench.node, sub); ok {
			effect_try_tree(f, effect, candidate)
		} else {
			ui_refuse(&f.ui, .Node_Bound_Overrun)
		}
	}
}

// tree_view draws the magnitude as its prefix walk, indented by structure, one editable
// row per node. The selected row is where every structural edit lands.
@(private = "file")
tree_view :: proc(f: ^Forge, bounds: rl.Rectangle, effect: ^ship.Effect) {
	e := effect.magnitude
	depths, roles := expr_shape(e)

	header := bounds.y
	draw_text(
		fmt.tprintf("%d of %d nodes - the largest well-formed tree is %d", e.count, ship.EXPR_MAX_NODES, ship.EXPR_MAX_NODES - 1),
		bounds.x,
		header,
		color_of(e.count > ship.EXPR_MAX_NODES - 1 ? FORGE_WARN : FORGE_TEXT_DIM),
	)

	region := rl.Rectangle{bounds.x, bounds.y + FORGE_ROW, bounds.width, bounds.height - FORGE_ROW}
	if ui_focus_region(&f.ui, region, "up/down selects a node; the kind control re-kinds it, keeping the children the new arity has room for") {
		if key_pressed(.DOWN) {
			f.workbench.node += 1
		}
		if key_pressed(.UP) {
			f.workbench.node -= 1
		}
	}
	f.workbench.node = clamp(f.workbench.node, 0, max(e.count - 1, 0))

	rows := min(e.count, int(region.height / FORGE_ROW))
	for index in 0 ..< rows {
		row := rl.Rectangle{region.x, region.y + f32(index) * FORGE_ROW, region.width, FORGE_ROW - 2}
		if index == f.workbench.node {
			rl.DrawRectangleRec(row, color_of(FORGE_PANEL_ALT))
		}
		if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(), row) {
			f.workbench.node = index
		}

		indent := f32(depths[index]) * 12
		if len(roles[index]) > 0 {
			draw_text(roles[index], row.x + indent - 34, row.y + 5, color_of(FORGE_TEXT_DIM))
		}
		tree_node_row(f, {row.x + indent, row.y, row.width - indent, row.height}, effect, index)
	}
}

// tree_node_row is one node: the kind it is, and the payload only that kind reads.
@(private = "file")
tree_node_row :: proc(f: ^Forge, bounds: rl.Rectangle, effect: ^ship.Effect, index: int) {
	node := effect.magnitude.nodes[index]

	kind_options, kind_count := enum_options(ship.Node_Kind)
	kind := int(node.kind)
	kind_field := rl.Rectangle{bounds.x, bounds.y, 84, bounds.height}
	if ui_enum(&f.ui, kind_field, kind_options, &kind, kind_count, "the node's operation; arity is fixed per kind") {
		if candidate, ok := expr_with_kind(effect.magnitude, index, ship.Node_Kind(kind)); ok {
			effect_try_tree(f, effect, candidate)
		} else {
			ui_refuse(&f.ui, .Node_Bound_Overrun)
		}
	}

	payload := rl.Rectangle{bounds.x + 88, bounds.y, 108, bounds.height}
	switch node.kind {
	case .Const:
		value := int(node.value)
		if ui_value(&f.ui, {payload.x, payload.y, 64, payload.height}, &value, -999, 999, "a literal magnitude, denominated in Hull") {
			tree_node_edit(f, effect, index, proc(n: ^ship.Node, v: int) {n.value = i32(v)}, value)
		}
	case .Quantity:
		options, count := enum_options(ship.Quantity)
		quantity := int(node.quantity)
		if ui_enum(&f.ui, payload, options, &quantity, count, "the closed set of scalars a tree may read off the round") {
			tree_node_edit(f, effect, index, proc(n: ^ship.Node, v: int) {n.quantity = ship.Quantity(v)}, quantity)
		}
	case .Count:
		axis := selector_axis(node.selector)
		if ui_enum(&f.ui, payload, "Tag;Slot_Size;Visibility", &axis, 3, "a selector names one axis; there is no Phase axis and no empty-slot axis") {
			tree_node_edit(f, effect, index, proc(n: ^ship.Node, v: int) {n.selector = selector_of(v, 0)}, axis)
		}
		value_field := rl.Rectangle{payload.x + 112, payload.y, 108, payload.height}
		options, count := selector_value_options(axis)
		value := selector_value(node.selector)
		if ui_enum(&f.ui, value_field, options, &value, count, "the criterion on that axis") {
			tree_node_edit(f, effect, index, proc(n: ^ship.Node, v: int) {n.selector = selector_of(selector_axis(n.selector), v)}, value)
		}
		side_field := rl.Rectangle{value_field.x + 112, value_field.y, 96, value_field.height}
		side_options, side_count := enum_options(ship.Count_Side)
		side := int(node.side)
		if ui_enum(&f.ui, side_field, side_options, &side, side_count, "Own is this ship's census; Opponent is the scouting report, which cannot see a concealed fitting") {
			tree_node_edit(f, effect, index, proc(n: ^ship.Node, v: int) {n.side = ship.Count_Side(v)}, side)
		}
		if node.side == .Opponent {
			draw_text(
				"outside a battle every opponent count reads 0",
				side_field.x + side_field.width + FORGE_GAP,
				side_field.y + 5,
				color_of(FORGE_TEXT_DIM),
			)
		}
	case .Gate:
		options, count := enum_options(ship.Compare_Op)
		compare := int(node.compare)
		if ui_enum(&f.ui, {payload.x, payload.y, 64, payload.height}, options, &compare, count, "comparisons appear nowhere but a Gate; the language has no boolean value") {
			tree_node_edit(f, effect, index, proc(n: ^ship.Node, v: int) {n.compare = ship.Compare_Op(v)}, compare)
		}
		if ship.expr_reads_quantity(effect.magnitude, .Captains_Order) {
			draw_text(
				"the captain's order is matched with Eq or Ne only: Hold 0, Press_Brace 1, Press_Fire 2, Commit 3",
				payload.x + 72,
				payload.y + 5,
				color_of(FORGE_TEXT_DIM),
			)
		}
	case .Add, .Sub, .Mul, .Min, .Max, .Pct:
		if node.kind == .Pct {
			ui_derived({payload.x, payload.y, 40, payload.height}, "/100", "the divisor is pinned to the literal 100 - the language's only division")
		}
	}
}

// tree_node_edit writes one node's payload and puts the whole tree back through the
// commit path, because a payload change can make an ancestor illegal: a Const swapped for
// a Captains_Order reading turns the Mul above it into arithmetic over the order.
@(private = "file")
tree_node_edit :: proc(f: ^Forge, effect: ^ship.Effect, index: int, set: proc(n: ^ship.Node, v: int), value: int) {
	candidate := effect.magnitude
	set(&candidate.nodes[index], value)
	effect_try_tree(f, effect, candidate)
}

// effect_try_tree commits a candidate tree onto `effect`: checked against the authoring
// rules, rebuilt through the expr_* helpers, then checked as a whole effect.
effect_try_tree :: proc(f: ^Forge, effect: ^ship.Effect, candidate: ship.Expr) -> bool {
	built, fault := expr_commit(candidate, effect.verb)
	if fault != .None {
		ui_refuse(&f.ui, fault)
		return false
	}
	next := effect^
	next.magnitude = built
	return effect_try(f, effect, next)
}

// effect_try commits a whole candidate effect, or refuses it with the rule it broke.
effect_try :: proc(f: ^Forge, effect: ^ship.Effect, candidate: ship.Effect) -> bool {
	peaks := ship.ship_count_peaks()
	if fault := effect_edit_fault(candidate, peaks); fault != .None {
		ui_refuse(&f.ui, fault)
		return false
	}
	effect^ = candidate
	return true
}

// expr_shape computes, in one prefix pass, how deep each node sits and what role it plays
// in its parent. Both are properties of arity and position alone, which is what lets a
// flat array be drawn as a tree.
expr_shape :: proc(e: ship.Expr) -> (depths: [ship.EXPR_MAX_NODES]int, roles: [ship.EXPR_MAX_NODES]string) {
	pending: [ship.EXPR_MAX_NODES]int
	parent: [ship.EXPR_MAX_NODES]ship.Node_Kind
	top := 0
	for i in 0 ..< e.count {
		depths[i] = top
		if top > 0 {
			arity := ship.EXPR_NODE_ARITY[parent[top - 1]]
			roles[i] = NODE_CHILD_ROLE[parent[top - 1]][arity - pending[top - 1]]
		}
		if arity := ship.EXPR_NODE_ARITY[e.nodes[i].kind]; arity > 0 {
			pending[top] = arity
			parent[top] = e.nodes[i].kind
			top += 1
			continue
		}
		for top > 0 {
			pending[top - 1] -= 1
			if pending[top - 1] > 0 {
				break
			}
			top -= 1
		}
	}
	return
}

// Selector is a one-axis union, so the editor picks the axis and then the criterion. These
// three fold that pair back and forth.
selector_axis :: proc(s: ship.Selector) -> int {
	switch _ in s {
	case ship.Tag:
		return 0
	case ship.Slot_Size:
		return 1
	case ship.Visibility:
		return 2
	}
	return 0
}

selector_value :: proc(s: ship.Selector) -> int {
	switch criterion in s {
	case ship.Tag:
		return int(criterion)
	case ship.Slot_Size:
		return int(criterion)
	case ship.Visibility:
		return int(criterion)
	}
	return 0
}

selector_of :: proc(axis: int, value: int) -> ship.Selector {
	switch axis {
	case 1:
		return ship.Slot_Size(clamp(value, 0, len(ship.Slot_Size) - 1))
	case 2:
		return ship.Visibility(clamp(value, 0, len(ship.Visibility) - 1))
	}
	return ship.Tag(clamp(value, 0, len(ship.Tag) - 1))
}

selector_value_options :: proc(axis: int) -> (options: string, count: int) {
	switch axis {
	case 1:
		return enum_options(ship.Slot_Size)
	case 2:
		return enum_options(ship.Visibility)
	}
	return enum_options(ship.Tag)
}

synergy_axis :: proc(synergy: Maybe(ship.Selector)) -> int {
	selector, is_synergy := synergy.?
	if !is_synergy {
		return 0
	}
	return selector_axis(selector) + 1
}

// Timing is a closed union of five, so it is edited as a variant choice plus that
// variant's own settings. timing_of keeps whatever the previously chosen variant held, so
// cycling past a variant does not wipe the one either side of it.
timing_option_list :: proc() -> (options: string, count: int) {
	return "Always;Once_Per_Battle;Every_N;Ramp;Charge", 5
}

timing_index :: proc(timing: ship.Timing) -> int {
	switch _ in timing {
	case ship.Timing_Always:
		return 0
	case ship.Timing_Once_Per_Battle:
		return 1
	case ship.Timing_Every_N:
		return 2
	case ship.Timing_Ramp:
		return 3
	case ship.Timing_Charge:
		return 4
	}
	return 0
}

timing_of :: proc(index: int, current: ship.Timing) -> ship.Timing {
	switch index {
	case 1:
		return ship.Timing_Once_Per_Battle{}
	case 2:
		if t, same := current.(ship.Timing_Every_N); same {
			return t
		}
		return ship.Timing_Every_N{n = 2}
	case 3:
		if t, same := current.(ship.Timing_Ramp); same {
			return t
		}
		return ship.Timing_Ramp{per_round = 1, cap = 3}
	case 4:
		if t, same := current.(ship.Timing_Charge); same {
			return t
		}
		return ship.Timing_Charge{cost = 3, per_round = 1}
	}
	return ship.Timing_Always{}
}
