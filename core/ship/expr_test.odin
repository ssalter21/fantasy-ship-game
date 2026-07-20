package ship

import "../testutil"
import "core:testing"

// The expression language is tested as arithmetic: every test below builds a tree
// with the authoring helpers and evaluates it against a hand-filled Expr_Context.
// No Ship, no layout and no Battle appears in this file — that the language is
// answerable without them is the point of the seam.

@(test)
a_const_evaluates_to_its_literal :: proc(t: ^testing.T) {
	testing.expect_value(t, expr_eval(expr_const(7), Expr_Context{}), 7)
}

@(test)
an_empty_tree_evaluates_to_zero :: proc(t: ^testing.T) {
	testing.expect_value(t, expr_eval(Expr{}, Expr_Context{}), 0)
}

@(test)
a_quantity_reads_its_slot_of_the_context :: proc(t: ^testing.T) {
	ctx := Expr_Context{}
	ctx.quantities[.Own_Hull] = 14
	ctx.quantities[.Round] = 3

	testing.expect_value(t, expr_eval(expr_quantity(.Own_Hull), ctx), 14)
	testing.expect_value(t, expr_eval(expr_quantity(.Round), ctx), 3)
	testing.expect_value(t, expr_eval(expr_quantity(.Opponent_Speed), ctx), 0)
}

@(test)
a_count_reads_its_selector_axis_of_the_census :: proc(t: ^testing.T) {
	ctx := Expr_Context{}
	ctx.counts.tag[.Weapon] = 3
	ctx.counts.size[.Large] = 2
	ctx.counts.visibility[.Concealed] = 1

	testing.expect_value(t, expr_eval(expr_count(Tag.Weapon), ctx), 3)
	testing.expect_value(t, expr_eval(expr_count(Slot_Size.Large), ctx), 2)
	testing.expect_value(t, expr_eval(expr_count(Visibility.Concealed), ctx), 1)
	testing.expect_value(t, expr_eval(expr_count(Tag.Beast), ctx), 0)
}

@(test)
the_binary_kinds_are_ordinary_arithmetic :: proc(t: ^testing.T) {
	ctx := Expr_Context{}

	testing.expect_value(t, expr_eval(expr_add(expr_const(4), expr_const(6)), ctx), 10)
	testing.expect_value(t, expr_eval(expr_sub(expr_const(4), expr_const(6)), ctx), -2)
	testing.expect_value(t, expr_eval(expr_mul(expr_const(4), expr_const(6)), ctx), 24)
	testing.expect_value(t, expr_eval(expr_min(expr_const(4), expr_const(6)), ctx), 4)
	testing.expect_value(t, expr_eval(expr_max(expr_const(4), expr_const(6)), ctx), 6)
}

@(test)
pct_divides_by_a_pinned_hundred_and_truncates :: proc(t: ^testing.T) {
	ctx := Expr_Context{}

	testing.expect_value(t, expr_eval(expr_pct(expr_const(50), expr_const(20)), ctx), 10)
	testing.expect_value(t, expr_eval(expr_pct(expr_const(7), expr_const(150)), ctx), 10)
	testing.expect_value(t, expr_eval(expr_pct(expr_const(9), expr_const(99)), ctx), 8)
	testing.expect_value(t, expr_eval(expr_pct(expr_const(1), expr_const(1)), ctx), 0)

	// Truncation is toward zero, so a negative value rounds up rather than down.
	testing.expect_value(t, expr_eval(expr_pct(expr_const(-9), expr_const(99)), ctx), -8)
}

@(test)
a_zero_percent_is_the_only_way_to_reach_zero_output_and_never_divides_by_zero :: proc(t: ^testing.T) {
	// Pct's divisor is the pinned literal, so the authored operand is a
	// multiplicand: a zero there yields zero rather than a division fault, which
	// is the whole reason Div is absent.
	testing.expect_value(t, expr_eval(expr_pct(expr_const(40), expr_const(0)), Expr_Context{}), 0)
	testing.expect_value(t, expr_eval(expr_pct(expr_const(0), expr_const(40)), Expr_Context{}), 0)
}

@(test)
a_gate_yields_its_then_branch_while_the_comparison_holds :: proc(t: ^testing.T) {
	ctx := Expr_Context{}
	ctx.quantities[.Round] = 2

	// "6 from round 3 onward, 2 before it"
	tree := expr_gate(
		.Gte,
		expr_quantity(.Round),
		expr_const(3),
		expr_const(6),
		expr_const(2),
	)

	testing.expect_value(t, expr_eval(tree, ctx), 2)
	ctx.quantities[.Round] = 3
	testing.expect_value(t, expr_eval(tree, ctx), 6)
	ctx.quantities[.Round] = 9
	testing.expect_value(t, expr_eval(tree, ctx), 6)
}

@(test)
every_comparison_op_answers_its_own_question :: proc(t: ^testing.T) {
	ctx := Expr_Context{}
	answer := proc(op: Compare_Op, lhs: int, rhs: int, ctx: Expr_Context) -> int {
		return expr_eval(
			expr_gate(op, expr_const(lhs), expr_const(rhs), expr_const(1), expr_const(0)),
			ctx,
		)
	}

	testing.expect_value(t, answer(.Eq, 3, 3, ctx), 1)
	testing.expect_value(t, answer(.Eq, 3, 4, ctx), 0)
	testing.expect_value(t, answer(.Ne, 3, 4, ctx), 1)
	testing.expect_value(t, answer(.Ne, 3, 3, ctx), 0)
	testing.expect_value(t, answer(.Lt, 3, 4, ctx), 1)
	testing.expect_value(t, answer(.Lt, 4, 4, ctx), 0)
	testing.expect_value(t, answer(.Lte, 4, 4, ctx), 1)
	testing.expect_value(t, answer(.Lte, 5, 4, ctx), 0)
	testing.expect_value(t, answer(.Gt, 5, 4, ctx), 1)
	testing.expect_value(t, answer(.Gt, 4, 4, ctx), 0)
	testing.expect_value(t, answer(.Gte, 4, 4, ctx), 1)
	testing.expect_value(t, answer(.Gte, 3, 4, ctx), 0)
}

@(test)
a_gate_branch_may_be_a_whole_subtree :: proc(t: ^testing.T) {
	ctx := Expr_Context{}
	ctx.quantities[.Own_Hull] = 20
	ctx.quantities[.Own_Max_Hull] = 100
	ctx.counts.tag[.Crew] = 4

	// "below half hull, one per Crew aboard; otherwise a flat 1"
	tree := expr_gate(
		.Lt,
		expr_mul(expr_quantity(.Own_Hull), expr_const(100)),
		expr_mul(expr_quantity(.Own_Max_Hull), expr_const(50)),
		expr_count(Tag.Crew),
		expr_const(1),
	)

	testing.expect_value(t, expr_eval(tree, ctx), 4)
	ctx.quantities[.Own_Hull] = 60
	testing.expect_value(t, expr_eval(tree, ctx), 1)
}

@(test)
nesting_a_gate_in_a_branch_is_how_the_language_spells_and :: proc(t: ^testing.T) {
	ctx := Expr_Context{}
	ctx.quantities[.Round] = 4
	ctx.quantities[.Captains_Order] = 3

	// "3 when the captain has committed on round 3 or later, else 0"
	tree := expr_gate(
		.Gte,
		expr_quantity(.Round),
		expr_const(3),
		expr_gate(
			.Eq,
			expr_quantity(.Captains_Order),
			expr_const(3),
			expr_const(3),
			expr_const(0),
		),
		expr_const(0),
	)

	testing.expect_value(t, expr_eval(tree, ctx), 3)
	ctx.quantities[.Captains_Order] = 0
	testing.expect_value(t, expr_eval(tree, ctx), 0)
	ctx.quantities[.Captains_Order] = 3
	ctx.quantities[.Round] = 1
	testing.expect_value(t, expr_eval(tree, ctx), 0)
}

@(test)
only_the_selected_branch_reaches_the_result :: proc(t: ^testing.T) {
	ctx := Expr_Context{}
	ctx.quantities[.Own_Speed] = 5
	ctx.quantities[.Opponent_Speed] = 2

	tree := expr_gate(
		.Gt,
		expr_quantity(.Own_Speed),
		expr_quantity(.Opponent_Speed),
		expr_const(11),
		expr_mul(expr_const(1000), expr_const(1000)),
	)

	testing.expect_value(t, expr_eval(tree, ctx), 11)
}

@(test)
prefix_order_alone_decides_which_operand_is_which :: proc(t: ^testing.T) {
	ctx := Expr_Context{}

	// Same three leaves, two shapes: only the prefix ordering separates
	// (10 - 4) - 3 from 10 - (4 - 3).
	left := expr_sub(expr_sub(expr_const(10), expr_const(4)), expr_const(3))
	right := expr_sub(expr_const(10), expr_sub(expr_const(4), expr_const(3)))

	testing.expect_value(t, left.count, right.count)
	testing.expect_value(t, expr_eval(left, ctx), 3)
	testing.expect_value(t, expr_eval(right, ctx), 9)
}

@(test)
a_tree_is_inline_pod_that_copies_by_assignment :: proc(t: ^testing.T) {
	original := expr_add(expr_const(1), expr_const(2))

	copy := original
	copy.nodes[1].value = 40

	testing.expect_value(t, expr_eval(original, Expr_Context{}), 3)
	testing.expect_value(t, expr_eval(copy, Expr_Context{}), 42)
}

@(test)
the_node_set_is_closed_at_ten_and_gate_alone_takes_four_children :: proc(t: ^testing.T) {
	testing.expect_value(t, len(Node_Kind), 10)
	testing.expect_value(t, expr_node_arity(.Gate), EXPR_MAX_ARITY)

	widest := 0
	for kind in Node_Kind {
		if kind != .Gate {
			widest = max(widest, expr_node_arity(kind))
		}
	}
	testing.expect_value(t, widest, 2)
}

// Derives, from the arity table alone, that every well-formed tree has an odd node
// count: a leaf is 1, and an interior node adds itself to an even number of
// odd-sized children. So the worst case a 12-node bound can hold is 11 — asserting
// against 12 would assert against a size the language cannot reach.
@(test)
every_arity_is_even_so_a_trees_node_count_is_odd :: proc(t: ^testing.T) {
	for kind in Node_Kind {
		testing.expectf(
			t,
			expr_node_arity(kind) % 2 == 0,
			"%v has odd arity, which would break the odd-node-count worst case",
			kind,
		)
	}
}

@(test)
the_largest_tree_the_bound_admits_evaluates :: proc(t: ^testing.T) {
	// Widest root the language has (Gate, arity 4), with its budget spent down to
	// the last node a tree can occupy: EXPR_MAX_NODES less the unreachable even
	// slot. Building it is half the assertion — a helper that overran the bound
	// would assert at authoring time.
	largest := EXPR_MAX_NODES if EXPR_MAX_NODES % 2 == 1 else EXPR_MAX_NODES - 1

	tree := expr_gate(
		.Lt,
		expr_add(expr_const(1), expr_const(2)),
		expr_add(expr_const(3), expr_const(4)),
		expr_add(expr_const(5), expr_const(6)),
		expr_const(7),
	)

	testing.expect_value(t, tree.count, largest)
	testing.expect_value(t, expr_eval(tree, Expr_Context{}), 11)
}

@(test)
the_deepest_tree_the_bound_admits_evaluates :: proc(t: ^testing.T) {
	// The other worst case the bound covers is recursion depth. The deepest shape
	// is the narrowest interior node nested as far as the budget allows: each
	// nesting spends its own node plus a leaf, so the chain runs until fewer than
	// two nodes are left. Depth needs no bound of its own because this is where
	// the node bound already stops it.
	tree := expr_const(10)
	depth := 1
	for tree.count + 2 <= EXPR_MAX_NODES {
		tree = expr_sub(tree, expr_const(1))
		depth += 1
	}

	testing.expect_value(t, depth, 6)
	testing.expect_value(t, tree.count, 11)
	testing.expect_value(t, expr_eval(tree, Expr_Context{}), 5)
}

@(test)
the_node_bound_rejects_a_tree_that_overruns_it :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}
	// A Gate over four three-node branches is 13, one clear of the bound.
	branch := expr_add(expr_const(1), expr_const(1))
	testing.expect_assert(t, "expression tree exceeds the node bound")
	_ = expr_gate(.Lt, branch, branch, branch, branch)
}
