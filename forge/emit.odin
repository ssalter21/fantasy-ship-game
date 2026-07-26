package forge

import "core:fmt"
import "core:strings"
import ship "../core/ship"
import voyage "../core/voyage"

// Odin source emission: what every surface's "copy as Odin" hands over.
//
// The output is the **exact table line** each authored row is written as, in the house
// style the tables already use, so the emitted text is pasted rather than adapted. An
// item emits through roster_item and its effect trees through the expr_* helpers, which
// is what makes the round-trip honest: re-reading the emitted source through core
// reassembles the same tree, and so reproduces the Roster_Verdict the tool showed.
//
// Every proc here returns a string allocated from the temp allocator — the caller either
// draws it or copies it to the clipboard within the frame.

// emit_item is one ship_item_roster line. The two optional parameters are emitted only
// where they differ from what roster_item defaults them to: naming a bulk that already is
// the size's full contribution would say nothing, and naming `requires_exposed = false`
// would say less than leaving it out.
emit_item :: proc(draft: Item_Draft) -> string {
	f := draft.item.fitting
	b := strings.builder_make(context.temp_allocator)

	fmt.sbprintf(
		&b,
		"roster_item(.%v, %q, .%v, %d, %s, {{",
		draft.item.tier,
		name_text(draft.name),
		f.size,
		f.weight,
		emit_tags(f.tags),
	)
	for i in 0 ..< f.effect_count {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, emit_effect(f.effects[i]))
	}
	strings.write_string(&b, "}")

	if f.bulk != ship.ship_cargo_slot_contribution(f.size) {
		fmt.sbprintf(&b, ", bulk = %d", f.bulk)
	}
	if f.requires_exposed {
		strings.write_string(&b, ", requires_exposed = true")
	}
	strings.write_string(&b, "),")
	return strings.to_string(b)
}

// emit_roster_size is the compile-checked count an appended item has to bump. It is part
// of the emit rather than a note beside it: ITEM_ROSTER_SIZE is what makes an appended
// row a compile error instead of a silent miscount, so the paste has to carry both.
emit_roster_size :: proc(count: int) -> string {
	return fmt.tprintf("ITEM_ROSTER_SIZE :: %d", count)
}

// emit_effect is one entry of a roster_item's effect list: the verb helper that names its
// phase, its synergy selector when it carries one, wrapped in effect_with_timing when it
// leaves Timing_Always.
emit_effect :: proc(effect: ship.Effect) -> string {
	verb: string
	switch effect.verb {
	case .Phase_Contribution:
		verb = "effect_phase_contribution"
	case .Repair:
		verb = "effect_repair"
	case .Modify_Speed:
		verb = "effect_modify_speed"
	}

	body := fmt.tprintf("%s(%s", verb, emit_expr(effect.magnitude))
	if selector, is_synergy := effect.synergy.?; is_synergy {
		body = fmt.tprintf("%s, %s", body, emit_selector(selector))
	}
	body = fmt.tprintf("%s)", body)

	if _, always := effect.timing.(ship.Timing_Always); always {
		return body
	}
	return fmt.tprintf("effect_with_timing(%s, %s)", body, emit_timing(effect.timing))
}

emit_timing :: proc(timing: ship.Timing) -> string {
	switch t in timing {
	case ship.Timing_Always:
		return "Timing_Always{}"
	case ship.Timing_Once_Per_Battle:
		return "Timing_Once_Per_Battle{}"
	case ship.Timing_Every_N:
		return fmt.tprintf("Timing_Every_N{{n = %d}", t.n)
	case ship.Timing_Ramp:
		return fmt.tprintf("Timing_Ramp{{per_round = %d, cap = %d}", t.per_round, t.cap)
	case ship.Timing_Charge:
		return fmt.tprintf("Timing_Charge{{cost = %d, per_round = %d}", t.cost, t.per_round)
	}
	unreachable()
}

emit_selector :: proc(selector: ship.Selector) -> string {
	switch criterion in selector {
	case ship.Tag:
		return fmt.tprintf("Selector(Tag.%v)", criterion)
	case ship.Slot_Size:
		return fmt.tprintf("Selector(Slot_Size.%v)", criterion)
	case ship.Visibility:
		return fmt.tprintf("Selector(Visibility.%v)", criterion)
	}
	return "nil"
}

emit_tags :: proc(tags: bit_set[ship.Tag]) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "{")
	first := true
	for tag in ship.Tag {
		if tag not_in tags {
			continue
		}
		if !first {
			strings.write_string(&b, ", ")
		}
		fmt.sbprintf(&b, ".%v", tag)
		first = false
	}
	strings.write_string(&b, "}")
	return strings.to_string(b)
}

// emit_expr writes a magnitude as the composition of expr_* calls that builds it. A
// subtree that **is** one of the composed shapes emits as that shape's helper rather than
// as the gate it expands to, so a tree written from a preset comes back out as the preset
// — which is what keeps the emitted roster reading like the roster it is pasted into.
emit_expr :: proc(e: ship.Expr, index: int = 0) -> string {
	if text, matched := emit_preset(e, index); matched {
		return text
	}

	node := e.nodes[index]
	children, _ := expr_children(e, index)

	switch node.kind {
	case .Const:
		return fmt.tprintf("expr_const(%d)", node.value)
	case .Quantity:
		return fmt.tprintf("expr_quantity(.%v)", node.quantity)
	case .Count:
		if node.side == .Opponent {
			return fmt.tprintf("expr_count_opponent(%s)", emit_selector(node.selector))
		}
		return fmt.tprintf("expr_count(%s)", emit_selector(node.selector))
	case .Add, .Sub, .Mul, .Min, .Max, .Pct:
		return fmt.tprintf(
			"%s(%s, %s)",
			EXPR_BINARY_HELPER[node.kind],
			emit_expr(children[0]),
			emit_expr(children[1]),
		)
	case .Gate:
		return fmt.tprintf(
			"expr_gate(.%v, %s, %s, %s, %s)",
			node.compare,
			emit_expr(children[0]),
			emit_expr(children[1]),
			emit_expr(children[2]),
			emit_expr(children[3]),
		)
	}
	unreachable()
}

// EXPR_BINARY_HELPER names the authoring helper for each even-arity arithmetic kind. Gate
// is absent because it takes an operator as well, and the three leaves because they take
// a payload rather than children.
@(rodata)
EXPR_BINARY_HELPER := [ship.Node_Kind]string {
	.Const    = "",
	.Quantity = "",
	.Count    = "",
	.Add      = "expr_add",
	.Sub      = "expr_sub",
	.Mul      = "expr_mul",
	.Min      = "expr_min",
	.Max      = "expr_max",
	.Pct      = "expr_pct",
	.Gate     = "",
}

// emit_preset recognises a subtree as one of expr.odin's composed shapes by rebuilding
// each shape from the constants the subtree itself holds and comparing whole trees. The
// search is over the subtree's own constants — a preset's parameters are constants in the
// tree it expands to, so nothing outside that set can produce a match.
emit_preset :: proc(e: ship.Expr, index: int) -> (text: string, matched: bool) {
	sub, _ := ship.expr_subtree(e, index)
	if sub.count == 0 || sub.nodes[0].kind != .Gate {
		return "", false
	}

	consts: [ship.EXPR_MAX_NODES]int
	count := 0
	for i in 0 ..< sub.count {
		if sub.nodes[i].kind == .Const {
			consts[count] = int(sub.nodes[i].value)
			count += 1
		}
	}

	for preset in Preset {
		for m in 0 ..< count {
			if !preset_takes_threshold(preset) {
				if expr_equal(preset_expr(preset, 0, consts[m]), sub) {
					return fmt.tprintf("%s(%d)", PRESET_HELPER[preset], consts[m]), true
				}
				continue
			}
			for threshold in 0 ..< count {
				if expr_equal(preset_expr(preset, consts[threshold], consts[m]), sub) {
					return fmt.tprintf("%s(%d, %d)", PRESET_HELPER[preset], consts[threshold], consts[m]), true
				}
			}
		}
	}
	return "", false
}

@(rodata)
PRESET_HELPER := [Preset]string {
	.Below_Hull_Percent    = "expr_below_hull_percent",
	.From_Round            = "expr_from_round",
	.While_Concealed       = "expr_while_concealed",
	.While_Opponent_Faster = "expr_while_opponent_faster",
	.While_Opponent_Slower = "expr_while_opponent_slower",
}

// expr_equal compares two trees over their live nodes only. The nodes past `count` are
// inert storage, so a whole-struct comparison would answer a question about padding.
expr_equal :: proc(a: ship.Expr, b: ship.Expr) -> bool {
	if a.count != b.count {
		return false
	}
	for i in 0 ..< a.count {
		x, y := a.nodes[i], b.nodes[i]
		if x.kind != y.kind {
			return false
		}
		switch x.kind {
		case .Const:
			if x.value != y.value {
				return false
			}
		case .Quantity:
			if x.quantity != y.quantity {
				return false
			}
		case .Count:
			if x.side != y.side || !selector_equal(x.selector, y.selector) {
				return false
			}
		case .Gate:
			if x.compare != y.compare {
				return false
			}
		case .Add, .Sub, .Mul, .Min, .Max, .Pct:
		}
	}
	return true
}

selector_equal :: proc(a: ship.Selector, b: ship.Selector) -> bool {
	switch criterion in a {
	case ship.Tag:
		other, same_axis := b.(ship.Tag)
		return same_axis && other == criterion
	case ship.Slot_Size:
		other, same_axis := b.(ship.Slot_Size)
		return same_axis && other == criterion
	case ship.Visibility:
		other, same_axis := b.(ship.Visibility)
		return same_axis && other == criterion
	}
	return b == nil
}

// emit_recipe is a recipe's two lines: the @(rodata) backing array its `stages` slice
// points at, and the catalog or port_bucket entry that names it. Both, because a recipe
// authored without its backing array would be a slice of nothing.
emit_recipe :: proc(draft: Recipe_Draft) -> string {
	b := strings.builder_make(context.temp_allocator)
	array := emit_screaming_name(name_text(draft.name), "STAGES")

	fmt.sbprintf(&b, "@(rodata)\n%s := [?]Stage_Spec{{", array)
	for i in 0 ..< draft.count {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		spec := draft.stages[i]
		if pool, authored := spec.stock.?; authored {
			fmt.sbprintf(&b, "{{kind = .%v, stock = .%v}", spec.kind, pool)
			continue
		}
		fmt.sbprintf(&b, "{{kind = .%v}", spec.kind)
	}
	strings.write_string(&b, "}\n\n")

	table := draft.pool == .Port ? "port_bucket" : "recipe_catalog"
	fmt.sbprintf(&b, "// in %s:\n{{name = %q, stages = %s[:]},", table, name_text(draft.name), array)
	return strings.to_string(b)
}

// emit_archetype is a hostile build's two lines. The item list is emitted in edit order,
// which is authoring: placement is first-empty-fit into an exposed-first template, so
// reordering the list moves an item between the deck and the hold.
emit_archetype :: proc(c: Content, draft: Archetype_Draft) -> string {
	b := strings.builder_make(context.temp_allocator)
	array := emit_screaming_name(name_text(draft.name), "ITEMS")

	fmt.sbprintf(&b, "@(rodata)\n%s := [?]string{{", array)
	for i in 0 ..< draft.count {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		fmt.sbprintf(&b, "%q", name_text(c.items[draft.items[i]].name))
	}
	strings.write_string(&b, "}\n\n")
	fmt.sbprintf(&b, "// in hostile_roster:\n{{name = %q, items = %s[:]},", name_text(draft.name), array)
	return strings.to_string(b)
}

emit_trade :: proc(draft: Trade_Draft) -> string {
	return fmt.tprintf("{{name = %q, gain = .%v, cost = .%v},", name_text(draft.name), draft.gain, draft.cost)
}

// emit_stock is one stock_pools row. `families = nil` is emitted as nil and never as the
// full set: nil means *no filter*, so an unfiltered shop keeps stocking a sixth Tag the
// day one is authored.
emit_stock :: proc(pool: voyage.Stock_Pool, draft: Stock_Draft) -> string {
	families := "nil"
	if draft.filtered {
		families = fmt.tprintf("bit_set[ship.Tag]%s", emit_tags(draft.families))
	}
	return fmt.tprintf(
		".%v = {{name = %q, families = %s, depth = %d},",
		pool,
		name_text(draft.name),
		families,
		draft.depth,
	)
}

// emit_screaming_name turns an authored name into the SCREAMING_SNAKE identifier its
// backing array is declared under: letters and digits kept and upper-cased, everything
// else a separator, and the suffix the table's convention appends.
emit_screaming_name :: proc(name: string, suffix: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	pending_separator := false
	for r in name {
		switch {
		case r >= 'a' && r <= 'z':
			if pending_separator {
				strings.write_byte(&b, '_')
				pending_separator = false
			}
			strings.write_byte(&b, u8(r) - 'a' + 'A')
		case (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9'):
			if pending_separator {
				strings.write_byte(&b, '_')
				pending_separator = false
			}
			strings.write_byte(&b, u8(r))
		case r == ' ' || r == '-' || r == '_':
			pending_separator = strings.builder_len(b) > 0
		}
	}
	if strings.builder_len(b) == 0 {
		strings.write_string(&b, "UNNAMED")
	}
	fmt.sbprintf(&b, "_%s", suffix)
	return strings.to_string(b)
}
