package ship

// The expression language an Effect's magnitude is written in: a bounded,
// allocation-free, POD arithmetic language (see CONTEXT.md for the vocabulary and
// the rulings behind the node set). A tree is a *value* — an inline fixed array, no
// pool and no pointers — so a Ghost_Snapshot (ADR-0008) carries one for its bytes.
//
// The evaluator is pure: it reads its nodes and an Expr_Context and nothing else —
// no Ship, no layout, no Battle. That is what lets the language be answered as
// arithmetic. It has no division outside Pct, no boolean value, and no RNG.

// EXPR_MAX_NODES bounds a single effect's tree. Depth needs no separate bound: it
// cannot exceed node count.
//
// Every arity is even, so every well-formed tree has an odd node count — a leaf is
// 1, and an interior node adds itself to an even number of odd-sized children. The
// largest tree this bound admits is therefore 11 nodes, not 12.
EXPR_MAX_NODES :: 12

// EXPR_MAX_ARITY is the widest node's child count, and so the size of the scratch a
// single evaluation step needs.
EXPR_MAX_ARITY :: 4

// Node_Kind is a node's operation. Arity is fixed per kind (expr_node_arity), which
// is what lets prefix order alone imply a tree's structure: no node stores a child
// index.
Node_Kind :: enum {
	Const,
	Quantity,
	Count,
	Add,
	Sub,
	Mul,
	Min,
	Max,
	Pct,
	Gate,
}

// Quantity is the closed set of scalars a tree may read off the round. Values
// arrive flat in Expr_Context.quantities; filling them is the resolution wiring's
// job, not the evaluator's. Captains_Order and Own_Visibility are ordinals, so a
// Gate compares them like any other quantity.
Quantity :: enum {
	Own_Hull,
	Own_Max_Hull,
	Own_Speed,
	Opponent_Speed,
	Round,
	Captains_Order,
	Damage_Taken_Last_Round,
	Own_Visibility,
}

// Compare_Op is the comparison a Gate selects on. Comparisons appear nowhere else:
// with no boolean value in the language, one cannot escape the Gate that made it.
Compare_Op :: enum {
	Eq,
	Ne,
	Lt,
	Lte,
	Gt,
	Gte,
}

// Node is one entry of a prefix-ordered tree. Each payload field is read only by
// the kind that owns it (`value` by Const, `quantity` by Quantity, `selector` by
// Count, `compare` by Gate) and is inert otherwise; the authoring helpers below set
// them, so no caller assembles the meaningless combinations. The zero Node is a
// Const 0, so a zero-filled array is valid, inert data rather than a trap.
Node :: struct {
	kind:     Node_Kind,
	value:    int,
	quantity: Quantity,
	selector: Selector,
	compare:  Compare_Op,
}

// Expr is a whole authored tree: its nodes in prefix order, plus how many of them
// are live. Inline POD — it copies by assignment and allocates nothing.
Expr :: struct {
	nodes: [EXPR_MAX_NODES]Node,
	count: int,
}

// Expr_Context is everything a tree may read, flattened to plain data: one scalar
// per Quantity, and the census a Count selects over. It holds no Ship, layout or
// Battle, which is what keeps the evaluator pure arithmetic.
Expr_Context :: struct {
	quantities: [Quantity]int,
	counts:     Count_Table,
}

// Count_Table is the pre-counted fitting census a Count node reads, one array per
// Selector axis. Counting is the caller's job, so the evaluator never walks a
// layout.
Count_Table :: struct {
	tag:        [Tag]int,
	size:       [Slot_Size]int,
	visibility: [Visibility]int,
	category:   [Category]int,
}

// expr_node_arity is how many child subtrees a kind consumes, and the single
// statement of that: evaluation reads its children through this, so prefix
// structure has one source of truth. Gate's four are lhs, rhs, then and else — its
// comparison op rides on the node itself.
expr_node_arity :: proc(kind: Node_Kind) -> int {
	switch kind {
	case .Const, .Quantity, .Count:
		return 0
	case .Add, .Sub, .Mul, .Min, .Max, .Pct:
		return 2
	case .Gate:
		return 4
	}
	unreachable()
}

// expr_eval resolves `e` against `ctx`. Pure: it reads only its arguments, writes
// nothing, and allocates nothing. An empty tree evaluates to 0.
expr_eval :: proc(e: Expr, ctx: Expr_Context) -> int {
	if e.count == 0 {
		return 0
	}
	assert(e.count <= EXPR_MAX_NODES, "expression tree exceeds the node bound")
	nodes := e.nodes
	value, next := expr_eval_node(nodes[:e.count], ctx, 0)
	assert(next == e.count, "expression tree is not a single well-formed tree")
	return value
}

// expr_eval_node evaluates the subtree rooted at `index`, returning its value and
// the index just past it — which is how a prefix walk finds its next sibling.
// Recursion depth is bounded by node count, hence by EXPR_MAX_NODES.
//
// A node's children are evaluated before its kind is dispatched on, so a Gate
// evaluates both branches and selects between them. The language has no side
// effects, so that is indistinguishable from taking one branch.
expr_eval_node :: proc(nodes: []Node, ctx: Expr_Context, index: int) -> (value: int, next: int) {
	assert(index < len(nodes), "expression tree is truncated: a node is missing a child")
	node := nodes[index]
	next = index + 1

	children: [EXPR_MAX_ARITY]int
	for i in 0 ..< expr_node_arity(node.kind) {
		children[i], next = expr_eval_node(nodes, ctx, next)
	}

	switch node.kind {
	case .Const:
		return node.value, next
	case .Quantity:
		return ctx.quantities[node.quantity], next
	case .Count:
		return expr_selector_count(ctx.counts, node.selector), next
	case .Add, .Sub, .Mul, .Min, .Max, .Pct:
		return expr_apply(node.kind, children[0], children[1]), next
	case .Gate:
		if expr_compare(node.compare, children[0], children[1]) {
			return children[2], next
		}
		return children[3], next
	}
	unreachable()
}

// expr_apply is the arithmetic of the binary kinds. Pct multiplies by a percent
// against a divisor pinned to the literal 100 — the language's only division, so no
// subtree can ever be a divisor. It truncates toward zero, which is the language's
// one rounding rule.
expr_apply :: proc(kind: Node_Kind, lhs: int, rhs: int) -> int {
	switch kind {
	case .Add:
		return lhs + rhs
	case .Sub:
		return lhs - rhs
	case .Mul:
		return lhs * rhs
	case .Min:
		return min(lhs, rhs)
	case .Max:
		return max(lhs, rhs)
	case .Pct:
		return lhs * rhs / 100
	case .Const, .Quantity, .Count, .Gate:
		unreachable()
	}
	unreachable()
}

// expr_compare answers a Gate's comparison. Its result is consumed where it is
// made and never becomes a value, which is what keeps the language boolean-free.
expr_compare :: proc(op: Compare_Op, lhs: int, rhs: int) -> bool {
	switch op {
	case .Eq:
		return lhs == rhs
	case .Ne:
		return lhs != rhs
	case .Lt:
		return lhs < rhs
	case .Lte:
		return lhs <= rhs
	case .Gt:
		return lhs > rhs
	case .Gte:
		return lhs >= rhs
	}
	unreachable()
}

// expr_selector_count reads the pre-counted census for `selector`'s axis.
expr_selector_count :: proc(counts: Count_Table, selector: Selector) -> int {
	switch criterion in selector {
	case Tag:
		return counts.tag[criterion]
	case Slot_Size:
		return counts.size[criterion]
	case Visibility:
		return counts.visibility[criterion]
	case Category:
		return counts.category[criterion]
	}
	return 0
}

// Authoring helpers. Composing these is how a tree is written: arity lives in a
// helper's signature, so a tree of the wrong shape — a Gate missing a branch, a Sub
// with one operand — is a compile error at the call site rather than a runtime
// surprise. Composition splices whole subtrees, so the node budget is spent as the
// tree is built and an overrun asserts here, at authoring time.

expr_const :: proc(value: int) -> Expr {
	return expr_leaf(Node{kind = .Const, value = value})
}

expr_quantity :: proc(quantity: Quantity) -> Expr {
	return expr_leaf(Node{kind = .Quantity, quantity = quantity})
}

expr_count :: proc(selector: Selector) -> Expr {
	return expr_leaf(Node{kind = .Count, selector = selector})
}

expr_add :: proc(lhs: Expr, rhs: Expr) -> Expr {
	return expr_binary(.Add, lhs, rhs)
}

expr_sub :: proc(lhs: Expr, rhs: Expr) -> Expr {
	return expr_binary(.Sub, lhs, rhs)
}

expr_mul :: proc(lhs: Expr, rhs: Expr) -> Expr {
	return expr_binary(.Mul, lhs, rhs)
}

expr_min :: proc(lhs: Expr, rhs: Expr) -> Expr {
	return expr_binary(.Min, lhs, rhs)
}

expr_max :: proc(lhs: Expr, rhs: Expr) -> Expr {
	return expr_binary(.Max, lhs, rhs)
}

// expr_pct is `value` taken to `percent` percent. The divisor cannot be authored.
expr_pct :: proc(value: Expr, percent: Expr) -> Expr {
	return expr_binary(.Pct, value, percent)
}

// expr_gate is the language's only conditional and its only comparison: it yields
// `then_expr` while `lhs op rhs` holds and `else_expr` otherwise. `and` is nesting;
// `or` costs a duplicated branch.
expr_gate :: proc(op: Compare_Op, lhs: Expr, rhs: Expr, then_expr: Expr, else_expr: Expr) -> Expr {
	result: Expr
	expr_push(&result, Node{kind = .Gate, compare = op})
	expr_splice(&result, lhs)
	expr_splice(&result, rhs)
	expr_splice(&result, then_expr)
	expr_splice(&result, else_expr)
	return result
}

@(private = "file")
expr_leaf :: proc(node: Node) -> Expr {
	result: Expr
	expr_push(&result, node)
	return result
}

@(private = "file")
expr_binary :: proc(kind: Node_Kind, lhs: Expr, rhs: Expr) -> Expr {
	result: Expr
	expr_push(&result, Node{kind = kind})
	expr_splice(&result, lhs)
	expr_splice(&result, rhs)
	return result
}

@(private = "file")
expr_push :: proc(e: ^Expr, node: Node) {
	assert(e.count < EXPR_MAX_NODES, "expression tree exceeds the node bound")
	e.nodes[e.count] = node
	e.count += 1
}

@(private = "file")
expr_splice :: proc(e: ^Expr, sub: Expr) {
	for i in 0 ..< sub.count {
		expr_push(e, sub.nodes[i])
	}
}
