package forge

import "core:fmt"
import "core:strings"
import "core:testing"
import combat "../core/combat"
import ship "../core/ship"
import voyage "../core/voyage"

// The Forge's own tests. Everything checked here is the tool's *logic* — what it loads,
// what it refuses, what it emits and what it lints — which is exactly the part that has no
// window in it: the drawing is a thin layer over these, and none of it is called below.

@(test)
the_forge_loads_every_live_content_table :: proc(t: ^testing.T) {
	// The tool is linked against core, so what it edits is what the game ships. A load
	// that quietly dropped a row would put the author's work in a table shorter than the
	// one they think they are editing.
	c := new(Content)
	defer free(c)
	content_load(c)

	testing.expectf(t, c.item_count == ship.ITEM_ROSTER_SIZE, "loaded %d items, the roster holds %d", c.item_count, ship.ITEM_ROSTER_SIZE)
	testing.expectf(
		t,
		c.recipe_count == len(voyage.voyage_recipe_catalog()) + len(voyage.voyage_port_bucket()),
		"loaded %d recipes from two pools holding %d + %d",
		c.recipe_count,
		len(voyage.voyage_recipe_catalog()),
		len(voyage.voyage_port_bucket()),
	)
	testing.expect(t, c.archetype_count == len(voyage.voyage_hostile_roster()), "loaded a different number of archetypes than the roster holds")
	testing.expect(t, c.trade_count == len(voyage.voyage_trade_roster()), "loaded a different number of trade axes than the roster holds")

	for pool in voyage.Stock_Pool {
		testing.expectf(t, name_text(c.stocks[pool].name) == voyage.voyage_stock_pool(pool).name, "the %v pool loaded under a different name", pool)
	}
	for i in 0 ..< c.item_count {
		testing.expectf(t, name_text(c.items[i].name) == c.items[i].item.fitting.name, "item %d's name view and its fitting's name disagree", i)
	}
}

@(test)
a_loaded_item_prices_exactly_as_core_prices_it :: proc(t: ^testing.T) {
	// The tool never restates the budget: it calls roster_check. This pins that a draft
	// round-trips through the editor's own storage without changing what it is worth.
	c := new(Content)
	defer free(c)
	content_load(c)

	for item, i in ship.ship_item_roster() {
		theirs := ship.roster_check(item)
		ours := ship.roster_check(c.items[i].item)
		testing.expectf(
			t,
			theirs.cost == ours.cost && theirs.fault == ours.fault && theirs.allowance == ours.allowance,
			"%q prices differently as a draft: %v vs %v",
			item.fitting.name,
			theirs,
			ours,
		)
	}
}

@(test)
a_new_item_defaults_to_carrying_nothing :: proc(t: ^testing.T) {
	// bulk's zero value is the *carrying* end, so a default of zero would bolt a free
	// full-slot hold onto every new item and hand the budget capacity it never priced.
	c := new(Content)
	defer free(c)
	content_load(c)

	index, ok := content_append_item(c)
	testing.expect(t, ok, "the roster had no headroom to append into")
	fitting := c.items[index].item.fitting
	testing.expectf(
		t,
		fitting.bulk == ship.ship_cargo_slot_contribution(fitting.size),
		"a new item defaulted to bulk %d, not its size's full contribution %d",
		fitting.bulk,
		ship.ship_cargo_slot_contribution(fitting.size),
	)
	testing.expect(t, ship.ship_fitting_capacity(fitting) == 0, "a new item carries something")
	testing.expect(t, c.items[index].appended, "an appended item is not marked as one, so an emit would not bump the roster size")
}

@(test)
rebuilding_a_tree_through_the_helpers_reproduces_it :: proc(t: ^testing.T) {
	// expr_rebuild is what makes an ill-formed tree unrepresentable: every node the editor
	// commits is re-composed through core's own expr_* helpers. If that were not an
	// identity on an authored tree, the editor would silently rewrite the roster.
	for item in ship.ship_item_roster() {
		for i in 0 ..< item.fitting.effect_count {
			original := item.fitting.effects[i].magnitude
			rebuilt, _ := expr_rebuild(original)
			testing.expectf(t, expr_equal(original, rebuilt), "%q effect %d does not survive a rebuild", item.fitting.name, i)
		}
	}
}

@(test)
re_kinding_a_node_keeps_the_children_the_new_arity_has_room_for :: proc(t: ^testing.T) {
	// The kind control is an edit, not a reset: an author who picked Add and meant Max
	// keeps both operands.
	original := ship.expr_add(ship.expr_const(3), ship.expr_quantity(.Own_Hull))
	changed, ok := expr_with_kind(original, 0, .Max)
	testing.expect(t, ok, "re-kinding a binary node to another binary node was refused")

	expected := ship.expr_max(ship.expr_const(3), ship.expr_quantity(.Own_Hull))
	testing.expectf(t, expr_equal(changed, expected), "re-kinding dropped the children: %v", changed)
}

@(test)
re_kinding_a_leaf_to_a_gate_fills_the_branches_it_gained :: proc(t: ^testing.T) {
	changed, ok := expr_with_kind(ship.expr_const(7), 0, .Gate)
	testing.expect(t, ok, "growing a leaf into a Gate was refused")
	testing.expectf(t, changed.count == 5, "a Gate over four leaves is 5 nodes, got %d", changed.count)
	testing.expect(t, changed.nodes[0].kind == .Gate, "the re-kinded node is not a Gate")
}

@(test)
the_editor_refuses_a_tree_past_the_node_bound :: proc(t: ^testing.T) {
	// expr_push asserts on an overrun, so an editor that let one be assembled would crash
	// on the author's work rather than decline the keystroke.
	crowded := ship.expr_below_hull_percent(50, 4)
	_, ok := expr_with_kind(crowded, crowded.count - 1, .Gate)
	testing.expect(t, !ok, "a re-kind that would overrun EXPR_MAX_NODES was taken")

	testing.expect(t, expr_edit_fault(ship.Expr{}, .Phase_Contribution) == .Node_Bound_Overrun, "an empty tree is not reported as a node-bound fault")
}

@(test)
the_editor_refuses_arithmetic_over_the_captains_order :: proc(t: ^testing.T) {
	// expr_binary asserts on this. The order is an ordinal encoding, and arithmetic over
	// it is an ordering comparison spelled without an ordering operator.
	candidate: ship.Expr
	candidate.nodes[0] = ship.Node{kind = .Mul}
	candidate.nodes[1] = ship.Node{kind = .Quantity, quantity = .Captains_Order}
	candidate.nodes[2] = ship.Node{kind = .Const, value = 2}
	candidate.count = 3

	testing.expect(t, expr_edit_fault(candidate, .Phase_Contribution) == .Order_Is_Not_A_Scale, "multiplying by the captain's order was admitted")
}

@(test)
the_editor_refuses_an_ordering_comparison_on_the_captains_order :: proc(t: ^testing.T) {
	// expr_gate asserts on this one, and admits Eq/Ne — so the check has to admit the
	// legal spelling as well as refuse the illegal one.
	ordered: ship.Expr
	ordered.nodes[0] = ship.Node{kind = .Gate, compare = .Gte}
	ordered.nodes[1] = ship.Node{kind = .Quantity, quantity = .Captains_Order}
	ordered.nodes[2] = ship.Node{kind = .Const, value = 2}
	ordered.nodes[3] = ship.Node{kind = .Const, value = 5}
	ordered.nodes[4] = ship.Node{kind = .Const, value = 0}
	ordered.count = 5
	testing.expect(t, expr_edit_fault(ordered, .Phase_Contribution) == .Order_Is_Not_A_Scale, "an ordering comparison on the order was admitted")

	matched := ship.expr_gate(
		.Eq,
		ship.expr_quantity(.Captains_Order),
		ship.expr_const(int(ship.Captains_Order.Commit)),
		ship.expr_const(5),
		ship.expr_const(0),
	)
	testing.expect(t, expr_edit_fault(matched, .Phase_Contribution) == .None, "matching the order with Eq was refused")
}

@(test)
the_editor_refuses_the_captains_order_read_as_part_of_a_comparand :: proc(t: ^testing.T) {
	// expr_gate wants the **bare reading** as the comparand, even under Eq: `max(order, 2)
	// == 2` is an ordering comparison spelled through the arithmetic door. A Gate nested in
	// a Gate's comparand is the shape the tree editor can reach it by, and expr_rebuild
	// would assert on it.
	nested: ship.Expr
	nested.nodes[0] = ship.Node{kind = .Gate, compare = .Eq}
	nested.nodes[1] = ship.Node{kind = .Gate, compare = .Eq}
	nested.nodes[2] = ship.Node{kind = .Quantity, quantity = .Captains_Order}
	nested.nodes[3] = ship.Node{kind = .Const, value = 3}
	nested.nodes[4] = ship.Node{kind = .Const, value = 1}
	nested.nodes[5] = ship.Node{kind = .Const, value = 0}
	nested.nodes[6] = ship.Node{kind = .Const, value = 1}
	nested.nodes[7] = ship.Node{kind = .Const, value = 4}
	nested.nodes[8] = ship.Node{kind = .Const, value = 0}
	nested.count = 9

	testing.expect(t, expr_edit_fault(nested, .Phase_Contribution) == .Order_Is_Not_A_Scale, "an order reading buried in a comparand was admitted")

	_, fault := expr_commit(nested, .Phase_Contribution)
	testing.expect(t, fault == .Order_Is_Not_A_Scale, "expr_commit rebuilt a tree the helpers would have asserted on")
}

@(test)
choosing_modify_speed_locks_the_timing_rather_than_bouncing_off_it :: proc(t: ^testing.T) {
	// The spec's rule is that the timing control **locks** to Always for this verb. Refusing
	// the verb change because of the timing the effect happened to carry would make
	// Modify_Speed unreachable from any timed effect.
	timed := ship.effect_with_timing(ship.effect_repair(ship.expr_const(2)), ship.Timing_Every_N{n = 2})

	candidate := timed
	candidate.verb = .Modify_Speed
	candidate.phase = ship.ship_verb_phase(.Modify_Speed)
	testing.expect(t, effect_edit_fault(candidate, ship.ship_count_peaks()) == .Speed_Carries_A_Timing, "keeping the timing was not the thing that would be refused")

	candidate.timing = ship.Timing_Always{}
	testing.expect(t, effect_edit_fault(candidate, ship.ship_count_peaks()) == .None, "the verb change was still refused once the timing locked to Always")
}

@(test)
the_editor_refuses_a_modify_speed_tree_that_reads_a_speed :: proc(t: ^testing.T) {
	// effect_modify_speed asserts on this: Speed is the layer a Modify_Speed tree is an
	// input to.
	reads_speed := ship.expr_add(ship.expr_const(1), ship.expr_quantity(.Own_Speed))
	testing.expect(t, expr_edit_fault(reads_speed, .Modify_Speed) == .Speed_Reads_Speed, "a speed-reading Modify_Speed tree was admitted")
	testing.expect(t, expr_edit_fault(reads_speed, .Phase_Contribution) == .None, "the same tree was refused on a verb that may read a speed")
}

@(test)
the_editor_refuses_a_timing_a_helper_would_assert_on :: proc(t: ^testing.T) {
	// The three settings effect_with_timing makes coherent: the verb pairing, a cadence of
	// zero rounds, and a charge that never fills.
	testing.expect(t, timing_edit_fault(ship.Timing_Once_Per_Battle{}, .Modify_Speed) == .Speed_Carries_A_Timing, "a timing on Modify_Speed was admitted")
	testing.expect(t, timing_edit_fault(ship.Timing_Always{}, .Modify_Speed) == .None, "Always was refused on Modify_Speed")
	testing.expect(t, timing_edit_fault(ship.Timing_Every_N{n = 0}, .Repair) == .Cadence_Not_Positive, "a cadence of zero rounds was admitted")
	testing.expect(t, timing_edit_fault(ship.Timing_Charge{cost = 3, per_round = 0}, .Repair) == .Charge_Not_Positive, "a charge that never fills was admitted")
}

@(test)
the_editor_refuses_a_gated_effect_past_the_peak_output_cap :: proc(t: ^testing.T) {
	// A gate discounts the price without shrinking the number that lands, so the spike is
	// capped directly. The tool refuses the edit rather than emitting an item roster_check
	// would fault.
	peaks := ship.ship_count_peaks()
	over := ship.effect_phase_contribution(ship.expr_below_hull_percent(50, ship.PEAK_OUTPUT_CAP + 1))
	under := ship.effect_phase_contribution(ship.expr_below_hull_percent(50, ship.PEAK_OUTPUT_CAP))

	testing.expect(t, effect_edit_fault(over, peaks) == .Peak_Output_Over_Cap, "a gated effect above PEAK_OUTPUT_CAP was admitted")
	testing.expect(t, effect_edit_fault(under, peaks) == .None, "a gated effect at the cap was refused")
}

@(test)
a_tree_that_prices_at_nothing_is_a_finding :: proc(t: ^testing.T) {
	// expr_peak documents the trap: a tree reading a quantity as its magnitude peaks at 0
	// and so prices at nothing, while its showcase reading says the item does something.
	peaks := ship.ship_count_peaks()
	testing.expect(t, expr_peaks_at_nothing(ship.expr_quantity(.Own_Hull), peaks), "a bare quantity magnitude was not flagged")
	testing.expect(t, !expr_peaks_at_nothing(ship.expr_const(4), peaks), "a constant magnitude was flagged")
}

@(test)
emit_writes_the_table_line_the_roster_is_authored_in :: proc(t: ^testing.T) {
	// The emitted line is pasted, not adapted, so it has to match the house style the
	// table already uses — down to the optional parameters that are left out.
	c := new(Content)
	defer free(c)
	content_load(c)

	index, found := content_item_index(c^, "Deckhands")
	testing.expect(t, found, "the roster no longer holds Deckhands")
	testing.expectf(
		t,
		emit_item(c.items[index]) == `roster_item(.Splash, "Deckhands", .Small, 3, {.Crew}, {effect_phase_contribution(expr_const(2))}),`,
		"emitted %s",
		emit_item(c.items[index]),
	)
}

@(test)
emit_names_the_optional_parameters_only_where_they_move :: proc(t: ^testing.T) {
	// roster_item defaults bulk to the size's full contribution and requires_exposed off,
	// so naming either where it has not moved says nothing.
	draft: Item_Draft
	name_set(&draft.name, "Test Hold")
	draft.item = ship.roster_item(.Deep, name_text(draft.name), .Medium, 18, {.Cargo}, {ship.effect_repair(ship.expr_const(2))}, 0, true)
	draft.item.fitting.name = name_text(draft.name)

	testing.expectf(
		t,
		emit_item(draft) == `roster_item(.Deep, "Test Hold", .Medium, 18, {.Cargo}, {effect_repair(expr_const(2))}, bulk = 0, requires_exposed = true),`,
		"emitted %s",
		emit_item(draft),
	)
}

@(test)
emit_recovers_the_composed_shapes_a_tree_was_written_from :: proc(t: ^testing.T) {
	// A tree written from a preset comes back out as the preset, which is what keeps the
	// emitted roster reading like the roster it is pasted into.
	testing.expect(t, emit_expr(ship.expr_below_hull_percent(50, 4)) == "expr_below_hull_percent(50, 4)", "the desperate shape did not round-trip")
	testing.expect(t, emit_expr(ship.expr_from_round(3, 3)) == "expr_from_round(3, 3)", "the warm-up shape did not round-trip")
	testing.expect(t, emit_expr(ship.expr_while_concealed(4)) == "expr_while_concealed(4)", "the hidden shape did not round-trip")
	testing.expect(t, emit_expr(ship.expr_while_opponent_faster(2)) == "expr_while_opponent_faster(2)", "the chase shape did not round-trip")
	testing.expect(t, emit_expr(ship.expr_while_opponent_slower(8)) == "expr_while_opponent_slower(8)", "the chase shape did not round-trip")
}

@(test)
emit_writes_a_timing_and_a_synergy_the_way_the_helpers_take_them :: proc(t: ^testing.T) {
	timed := ship.effect_with_timing(ship.effect_repair(ship.expr_const(6)), ship.Timing_Every_N{n = 2})
	testing.expectf(t, emit_effect(timed) == "effect_with_timing(effect_repair(expr_const(6)), Timing_Every_N{n = 2})", "emitted %s", emit_effect(timed))

	synergy := ship.effect_phase_contribution(ship.expr_const(1), ship.Selector(ship.Tag.Cargo))
	testing.expectf(t, emit_effect(synergy) == "effect_phase_contribution(expr_const(1), Selector(Tag.Cargo))", "emitted %s", emit_effect(synergy))
}

@(test)
emit_derives_a_backing_array_name_the_way_the_tables_do :: proc(t: ^testing.T) {
	testing.expect(t, emit_screaming_name("Smuggler's Cove", "STAGES") == "SMUGGLERS_COVE_STAGES", "a recipe's backing array name drifted from the convention")
	testing.expect(t, emit_screaming_name("Coastal Privateer", "ITEMS") == "COASTAL_PRIVATEER_ITEMS", "an archetype's backing array name drifted from the convention")
}

@(test)
emit_writes_an_unfiltered_pool_as_nil_and_never_as_every_family :: proc(t: ^testing.T) {
	// families = nil means *no filter*, so an unfiltered shop keeps stocking a sixth Tag
	// the day one is authored. Emitting the full set instead would freeze it.
	c := new(Content)
	defer free(c)
	content_load(c)

	testing.expectf(
		t,
		emit_stock(.Chandlery, c.stocks[.Chandlery]) == `.Chandlery = {name = "Chandlery", families = nil, depth = 12},`,
		"emitted %s",
		emit_stock(.Chandlery, c.stocks[.Chandlery]),
	)
	testing.expectf(
		t,
		emit_stock(.Ordnance_Hoy, c.stocks[.Ordnance_Hoy]) == `.Ordnance_Hoy = {name = "Ordnance Hoy", families = bit_set[ship.Tag]{.Weapon}, depth = 6},`,
		"emitted %s",
		emit_stock(.Ordnance_Hoy, c.stocks[.Ordnance_Hoy]),
	)
}

// The round-trip. The shipped tables are embedded at compile time and every emitted line
// is checked to be **already in them** — which is the strongest form the claim can take
// without a parser: what the tool would hand an author to paste is byte-for-byte the line
// the table already holds, so pasting it back compiles and prices identically.
TABLE_ROSTER :: #load("../core/ship/roster.odin", string)
TABLE_CATALOG :: #load("../core/voyage/catalog.odin", string)
TABLE_CONTENT :: #load("../core/voyage/content.odin", string)

// table_normalized strips what only the formatter decides: all whitespace, and the
// trailing comma odinfmt leaves before a closing bracket when it wraps a literal across
// lines. What is left is the authored text itself.
@(private = "file")
table_normalized :: proc(source: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for i in 0 ..< len(source) {
		switch source[i] {
		case ' ', '\t', '\r', '\n':
		case:
			strings.write_byte(&b, source[i])
		}
	}
	text := strings.to_string(b)
	for _, replaced := strings.replace_all(text, ",)", ")", context.temp_allocator); replaced; {
		text, replaced = strings.replace_all(text, ",)", ")", context.temp_allocator)
	}
	for _, replaced := strings.replace_all(text, ",}", "}", context.temp_allocator); replaced; {
		text, replaced = strings.replace_all(text, ",}", "}", context.temp_allocator)
	}
	return table_canonical_tag_sets(text)
}

// table_canonical_tag_sets rewrites every `bit_set[Tag]` literal into Tag order. A set has
// no order, so two spellings of the same families are the same authored value — and the
// Forge emits one canonical spelling while the tables were hand-written in whichever order
// read best. Everything else is compared as written.
@(private = "file")
table_canonical_tag_sets :: proc(source: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(source); {
		close := source[i] == '{' ? strings.index_byte(source[i:], '}') : -1
		canonical, is_tag_set := "", false
		if close > 0 {
			canonical, is_tag_set = tag_group_sorted(source[i + 1:i + close])
		}
		if !is_tag_set {
			strings.write_byte(&b, source[i])
			i += 1
			continue
		}
		fmt.sbprintf(&b, "{{%s}", canonical)
		i += close + 1
	}
	return strings.to_string(b)
}

// tag_group_sorted reports the members of one brace group in Tag order, and false for a
// group that is not a tag set at all.
@(private = "file")
tag_group_sorted :: proc(group: string) -> (canonical: string, ok: bool) {
	if len(group) == 0 {
		return "", false
	}
	present: bit_set[ship.Tag]
	for member in strings.split(group, ",", context.temp_allocator) {
		matched := false
		for tag in ship.Tag {
			if member == fmt.tprintf(".%v", tag) {
				present += {tag}
				matched = true
				break
			}
		}
		if !matched {
			return "", false
		}
	}

	b := strings.builder_make(context.temp_allocator)
	for tag in ship.Tag {
		if tag not_in present {
			continue
		}
		if strings.builder_len(b) > 0 {
			strings.write_byte(&b, ',')
		}
		fmt.sbprintf(&b, ".%v", tag)
	}
	return strings.to_string(b), true
}

// table_needle is one emitted fragment normalized for the search, less its trailing comma
// — the last entry of a table is followed by the closing bracket rather than by another
// entry, so the comma is the separator's and not the line's.
@(private = "file")
table_needle :: proc(source: string) -> string {
	text := table_normalized(source)
	if strings.has_suffix(text, ",") {
		return text[:len(text) - 1]
	}
	return text
}

@(test)
every_emitted_item_is_the_line_the_roster_already_holds :: proc(t: ^testing.T) {
	c := new(Content)
	defer free(c)
	content_load(c)

	table := table_normalized(TABLE_ROSTER)
	for i in 0 ..< c.item_count {
		line := table_needle(emit_item(c.items[i]))
		testing.expectf(t, strings.contains(table, line), "%q emits a line roster.odin does not hold: %s", name_text(c.items[i].name), emit_item(c.items[i]))
	}
	testing.expect(
		t,
		strings.contains(table, table_needle(emit_roster_size(c.item_count))),
		"the emitted ITEM_ROSTER_SIZE does not match the one the table is compiled against",
	)
}

@(test)
every_emitted_recipe_is_the_two_lines_the_catalog_already_holds :: proc(t: ^testing.T) {
	c := new(Content)
	defer free(c)
	content_load(c)

	table := table_normalized(TABLE_CATALOG)
	for i in 0 ..< c.recipe_count {
		source := emit_recipe(c.recipes[i])
		parts := strings.split(source, "\n\n", context.temp_allocator)
		testing.expectf(t, len(parts) == 2, "a recipe emit is its backing array and its table line, got %d parts", len(parts))
		if len(parts) != 2 {
			continue
		}
		// The second part opens with the comment naming which pool the line belongs in.
		table_line := parts[1][strings.index_byte(parts[1], '\n') + 1:]
		for fragment in ([]string{parts[0], table_line}) {
			testing.expectf(
				t,
				strings.contains(table, table_needle(fragment)),
				"%q emits source catalog.odin does not hold: %s",
				name_text(c.recipes[i].name),
				fragment,
			)
		}
	}
}

@(test)
every_emitted_roster_row_is_the_line_content_already_holds :: proc(t: ^testing.T) {
	c := new(Content)
	defer free(c)
	content_load(c)

	table := table_normalized(TABLE_CONTENT)
	for i in 0 ..< c.trade_count {
		line := emit_trade(c.trades[i])
		testing.expectf(t, strings.contains(table, table_needle(line)), "a trade axis emits a line content.odin does not hold: %s", line)
	}
	for pool in voyage.Stock_Pool {
		line := emit_stock(pool, c.stocks[pool])
		testing.expectf(t, strings.contains(table, table_needle(line)), "the %v pool emits a line content.odin does not hold: %s", pool, line)
	}
	for i in 0 ..< c.archetype_count {
		source := emit_archetype(c^, c.archetypes[i])
		parts := strings.split(source, "\n\n", context.temp_allocator)
		if !testing.expect(t, len(parts) == 2, "an archetype emit is its backing array and its table line") {
			continue
		}
		table_line := parts[1][strings.index_byte(parts[1], '\n') + 1:]
		for fragment in ([]string{parts[0], table_line}) {
			testing.expectf(
				t,
				strings.contains(table, table_needle(fragment)),
				"%q emits source content.odin does not hold: %s",
				name_text(c.archetypes[i].name),
				fragment,
			)
		}
	}
}

@(test)
an_edited_row_is_flagged_as_moving_every_seed_that_draws_it :: proc(t: ^testing.T) {
	// Roster order is load-bearing: a shop's shelf and an Offer's options index into the
	// table, so replacing a row in place re-deals every seed that already drew it.
	c := new(Content)
	defer free(c)
	content_load(c)

	testing.expect(t, !item_moves_a_seed(c^, 0), "an untouched row was reported as moving a seed")
	c.items[0].item.fitting.weight += 1
	testing.expect(t, item_moves_a_seed(c^, 0), "an edited roster row was not reported as moving a seed")

	appended, ok := content_append_item(c)
	testing.expect(t, ok, "no headroom to append an item")
	testing.expect(t, !item_moves_a_seed(c^, appended), "an appended row was reported as moving a seed: nothing has ever drawn it")
}

@(test)
the_roster_sort_reorders_the_view_and_nothing_else :: proc(t: ^testing.T) {
	// Sorting is a view: the index column still shows the roster index, because that is
	// what a seed draws by.
	f := new(Forge)
	defer free(f)
	forge_init(f)

	f.workbench.sort = int(Roster_Sort.Name)
	sorted := roster_filter(f)
	testing.expectf(t, sorted.count == f.content.item_count, "the unfiltered view dropped rows: %d of %d", sorted.count, f.content.item_count)
	for row in 1 ..< sorted.count {
		before := name_text(f.content.items[sorted.index[row - 1]].name)
		after := name_text(f.content.items[sorted.index[row]].name)
		testing.expectf(t, before <= after, "sorting by name left %q before %q", before, after)
	}

	f.workbench.sort = int(Roster_Sort.Roster)
	in_roster_order := roster_filter(f)
	for row in 0 ..< in_roster_order.count {
		testing.expectf(t, in_roster_order.index[row] == row, "roster order is not the roster's own order at row %d", row)
	}
}

@(test)
every_authored_recipe_lints_clean :: proc(t: ^testing.T) {
	// The lint's whole claim is that it is the catalog's own conventions checked live. If
	// the shipped catalog did not satisfy it, it would be checking something else.
	c := new(Content)
	defer free(c)
	content_load(c)

	for i in 0 ..< c.recipe_count {
		testing.expectf(t, recipe_lint(c^, i) == .None, "%q lints as %v, but the catalog's tests pass", name_text(c.recipes[i].name), recipe_lint(c^, i))
	}
}

@(test)
the_lint_catches_a_cost_authored_behind_a_boon :: proc(t: ^testing.T) {
	// [Offer, Fight] is the canonical mistake: skip an item you never had and the fight is
	// dodged for nothing.
	c := new(Content)
	defer free(c)
	content_load(c)

	index, ok := content_append_recipe(c, .Catalog)
	testing.expect(t, ok, "no headroom to append a recipe")
	name_set(&c.recipes[index].name, "Anti Shape")
	c.recipes[index].count = 2
	c.recipes[index].stages[0] = voyage.Stage_Spec{kind = .Offer}
	c.recipes[index].stages[1] = voyage.Stage_Spec{kind = .Fight}

	testing.expect(t, recipe_lint(c^, index) == .Cost_Behind_A_Boon, "[Offer, Fight] was admitted")
}

@(test)
the_lint_catches_a_duplicate_shape_regardless_of_pool :: proc(t: ^testing.T) {
	// Shape means the kind sequence and nothing else: a baked Stage_Shop carries its cards
	// but not the pool that dealt them, so a differing pool cannot rescue a collision.
	c := new(Content)
	defer free(c)
	content_load(c)

	index, ok := content_append_recipe(c, .Catalog)
	testing.expect(t, ok, "no headroom to append a recipe")
	name_set(&c.recipes[index].name, "Second Press Gang")
	c.recipes[index].count = 2
	c.recipes[index].stages[0] = voyage.Stage_Spec{kind = .Fight}
	c.recipes[index].stages[1] = voyage.Stage_Spec{kind = .Shop, stock = voyage.Stock_Pool.Menagerie}

	testing.expect(t, recipe_lint(c^, index) == .Duplicate_Shape, "a second [Fight, Shop] was admitted because it named a different pool")
}

@(test)
the_lint_keeps_a_counterfeit_port_out_of_the_catalog :: proc(t: ^testing.T) {
	// An encounter reveals iff its first stage reveals, and Shop is the only revealing
	// primitive — so a [Shop] merchant would draw the marker a Port's guaranteed placement
	// promises is a general market.
	c := new(Content)
	defer free(c)
	content_load(c)

	index, ok := content_append_recipe(c, .Catalog)
	testing.expect(t, ok, "no headroom to append a recipe")
	name_set(&c.recipes[index].name, "Counterfeit Port")
	c.recipes[index].count = 1
	c.recipes[index].stages[0] = voyage.Stage_Spec{kind = .Shop, stock = voyage.Stock_Pool.Menagerie}

	testing.expect(t, recipe_lint(c^, index) == .Catalog_Opens_On_A_Shop, "a catalog recipe opening on a Shop was admitted")

	c.recipes[index].pool = .Port
	testing.expect(t, recipe_lint(c^, index) != .Catalog_Opens_On_A_Shop, "the same recipe was refused in the Port bucket, which is where a [Shop] belongs")
}

@(test)
the_lint_holds_a_stock_pool_to_the_shop_that_draws_from_it :: proc(t: ^testing.T) {
	// voyage_bake_stage asserts both directions, so an author must not be able to leave a
	// pool on a Fight or take one off a Shop.
	c := new(Content)
	defer free(c)
	content_load(c)

	index, ok := content_append_recipe(c, .Catalog)
	testing.expect(t, ok, "no headroom to append a recipe")
	name_set(&c.recipes[index].name, "Pool On A Fight")
	c.recipes[index].count = 1
	c.recipes[index].stages[0] = voyage.Stage_Spec{kind = .Fight, stock = voyage.Stock_Pool.Chandlery}
	testing.expect(t, recipe_lint(c^, index) == .Pool_Without_A_Shop, "a pool on a Fight was admitted")

	c.recipes[index].stages[0] = voyage.Stage_Spec{kind = .Shop}
	testing.expect(t, recipe_lint(c^, index) == .Shop_Without_A_Pool, "a Shop with no pool was admitted")
}

@(test)
the_bucket_is_derived_from_the_stage_count :: proc(t: ^testing.T) {
	testing.expect(t, bucket_of(1) == .Coastal, "one stage does not file into Coastal")
	testing.expect(t, bucket_of(2) == .Open_Sea, "two stages do not file into Open Sea")
	testing.expect(t, bucket_of(3) == .Deep, "three stages do not file into The Deep")
}

@(test)
a_trade_may_not_cost_hull :: proc(t: ^testing.T) {
	// Hull is gain-only: nothing else in the game heals, and a trade that damages you is a
	// Fight without the fight.
	c := new(Content)
	defer free(c)
	content_load(c)

	for i in 0 ..< c.trade_count {
		testing.expectf(t, trade_fault(c^, i) == .None, "%q faults as %v", name_text(c.trades[i].name), trade_fault(c^, i))
	}

	index, ok := content_append_trade(c)
	testing.expect(t, ok, "no headroom to append a trade axis")
	c.trades[index].gain = .Cargo
	c.trades[index].cost = .Hull
	testing.expect(t, trade_fault(c^, index) == .Hull_Is_Gain_Only, "a trade costing Hull was admitted")

	name_set(&c.trades[index].name, "Deckhands")
	c.trades[index].cost = .Cargo
	c.trades[index].gain = .Max_Hull
	testing.expect(t, trade_fault(c^, index) == .Name_Collides, "a trade sharing a name with a roster item was admitted")
}

@(test)
every_authored_archetype_sits_inside_both_walls :: proc(t: ^testing.T) {
	// The walls preview fights the build rather than scoring it, so this is the same claim
	// the roster's own test makes, read through the tool an author will read it through.
	//
	// archetype_walls allocates from context.allocator and frees nothing — the frame scopes
	// that to the temp allocator, and outside a frame the caller scopes its own.
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)

	for archetype in voyage.voyage_hostile_roster() {
		rounds, sank_the_player, scratched, ended := archetype_walls(archetype)
		testing.expectf(t, ended, "%v and a starting player cannot finish a fight at Coastal", archetype.name)
		testing.expectf(t, scratched, "a starting player cannot scratch %v at Coastal", archetype.name)
		testing.expectf(
			t,
			rounds >= combat.BASELINE_ROUND_COUNT,
			"%v resolves in %d rounds, before the escape gate at %d",
			archetype.name,
			rounds,
			combat.BASELINE_ROUND_COUNT,
		)
		testing.expectf(t, !sank_the_player || rounds >= combat.BASELINE_ROUND_COUNT, "%v sinks a starting ship before the gate", archetype.name)
	}
}

@(test)
undo_walks_the_session_back_and_forward :: proc(t: ^testing.T) {
	// Every edit in the tool is reversible, and reversible is what buys the absence of
	// confirm dialogs — so the history has to actually hold.
	c := new(Content)
	defer free(c)
	content_load(c)

	undo := new(Undo)
	defer free(undo)
	undo_reset(undo, c^)

	original := c.items[0].item.fitting.weight
	c.items[0].item.fitting.weight = original + 1
	undo_commit(undo, c^)
	c.items[0].item.fitting.weight = original + 2
	undo_commit(undo, c^)

	testing.expect(t, undo_can_undo(undo^), "the history has nothing to walk back to")
	stepped, ok := undo_undo(undo)
	testing.expect(t, ok, "an undo with history reported nothing to restore")
	testing.expectf(t, stepped.items[0].item.fitting.weight == original + 1, "undo restored weight %d", stepped.items[0].item.fitting.weight)

	stepped, ok = undo_undo(undo)
	testing.expect(t, ok, "a second undo reported nothing to restore")
	testing.expectf(t, stepped.items[0].item.fitting.weight == original, "a second undo restored weight %d", stepped.items[0].item.fitting.weight)
	testing.expect(t, !undo_can_undo(undo^), "the history walked back past its start")

	stepped, ok = undo_redo(undo)
	testing.expect(t, ok, "a redo with a tail reported nothing to restore")
	testing.expectf(t, stepped.items[0].item.fitting.weight == original + 1, "redo restored weight %d", stepped.items[0].item.fitting.weight)
}

@(test)
undo_drops_its_oldest_state_rather_than_its_newest :: proc(t: ^testing.T) {
	// The ring is bounded, so a long session loses the far end of its history. Losing the
	// near end instead would make the last edit unreversible, which is the one that matters.
	c := new(Content)
	defer free(c)
	content_load(c)

	undo := new(Undo)
	defer free(undo)
	undo_reset(undo, c^)

	for step in 1 ..= UNDO_DEPTH + 8 {
		c.items[0].item.fitting.weight = step
		undo_commit(undo, c^)
	}
	stepped, ok := undo_undo(undo)
	testing.expect(t, ok, "a full ring reported nothing to walk back to")
	testing.expectf(t, stepped.items[0].item.fitting.weight == UNDO_DEPTH + 7, "the newest state was dropped instead of the oldest: got %d", stepped.items[0].item.fitting.weight)
}

@(test)
the_roster_filter_matches_without_regard_to_case :: proc(t: ^testing.T) {
	testing.expect(t, text_contains_fold("Naval Gun Crew", "gun"), "type-to-filter missed a lower-case substring")
	testing.expect(t, text_contains_fold("Naval Gun Crew", ""), "an empty filter excluded a row")
	testing.expect(t, !text_contains_fold("Deckhands", "kraken"), "type-to-filter matched a substring that is not there")
}
