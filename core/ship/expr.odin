package ship

// The expression language an Effect's magnitude is written in: a bounded,
// allocation-free, POD arithmetic language of ten node kinds. A tree is a *value* —
// an inline fixed array, no pool, no pointers — so it costs a Ghost_Snapshot
// (ADR-0008) nothing beyond its bytes.
//
// The evaluator is pure and reads nothing but its nodes and an Expr_Context: no
// Ship, no layout, no Battle. Everything a tree may read arrives pre-flattened in
// that context, which is what lets the language be tested as arithmetic.
//
// There is no division, no boolean value and no RNG. Comparison exists only inside
// Gate, so "multiply by a comparison" and "select on a comparison" cannot be the
// same item at two prices.

// EXPR_MAX_NODES bounds a single effect's tree. There is no separate depth bound:
// depth cannot exceed node count, so one rule locks the door. Evaluation's worst
// case — recursion depth and the node budget a helper proc may spend — is measured
// against this constant rather than a literal.
//
// Every arity is even, so every well-formed tree has an odd node count (a leaf is
// 1; an interior node adds itself to an even number of odd children). The largest
// tree this bound admits is therefore 11 nodes, not 12.
EXPR_MAX_NODES :: 12

// Node_Kind is the closed set of ten. Arity is fixed per kind (expr_node_arity), so
// prefix order alone implies a tree's structure and no child indices are stored.
//
// Deliberately absent: Div (a subtree divisor can be zero, and truncation makes it
// non-associative, so calibration would be against a rounding artifact — Pct
// replaces it with the divisor pinned at a literal 100); Clamp, Sat_Sub, Abs and
// Sign (each saves a node or two and costs a permanent calibration row plus a
// second spelling of one intent).
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

// Quantity is the closed set of scalars a tree may read off the round. Values are
// supplied flat in Expr_Context.quantities; what fills them is the resolution
// wiring's business, not the evaluator's.
//
// Captains_Order is a single ordinal (Hold = 0, Press_Brace = 1, Press_Fire = 2,
// Commit = 3), never four boolean-valued quantities — those would spell one intent
// twice at two prices. Own_Visibility is likewise an ordinal, matching Visibility's
// own member order.
Quantity_Kind :: enum {
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
// there is no boolean value in the language, so an op cannot escape its Gate.
Compare_Op :: enum {
	Eq,
	Ne,
	Lt,
	Lte,
	Gt,
	Gte,
}

// Node is one entry of a prefix-ordered tree. Its payload fields are read only by
// the kinds that own them (`value` by Const, `quantity` by Quantity, `selector` by
// Count, `compare` by Gate) and are inert otherwise; the helper procs below are the
// only way to set them, so no caller sees the unused combinations. The zero Node is
// a Const 0, so a zero-filled array is a valid, meaningless tree rather than a trap.
Node :: struct {
	kind:     Node_Kind,
	value:    int,
	quantity: Quantity_Kind,
	selector: Selector,
	compare:  Compare_Op,
}

// Expr is a whole authored tree: nodes in prefix order plus how many of them are
// live. Inline POD, so it copies by assignment and allocates nothing.
Expr :: struct {
	nodes: [EXPR_MAX_NODES]Node,
	count: int,
}

// Expr_Context is everything a tree may read, flattened: scalar quantities and the
// counts a Count node selects over. No Ship, no layout, no Battle — every field is
// plain data a caller fills in, which is what makes the evaluator pure arithmetic.
Expr_Context :: struct {
	quantities: [Quantity_Kind]int,
	counts:     Count_Table,
}

// Count_Table is the pre-counted fitting census a Count node reads, one array per
// Selector axis. Counting is the caller's job precisely so the evaluator never
// walks a layout.
Count_Table :: struct {
	tag:        [Tag]int,
	size:       [Slot_Size]int,
	visibility: [Visibility]int,
	category:   [Category]int,
}

// expr_node_arity is how many child subtrees a kind consumes. Gate takes four —
// lhs, rhs, then, else — with its comparison op stored on the node itself.
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

// expr_eval resolves `e` against `ctx`. Pure: it reads nothing but its arguments,
// writes nothing, and allocates nothing. An empty tree evaluates to 0.
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

// expr_eval_node evaluates the subtree rooted at `index` and returns its value
// together with the index just past it, which is how a prefix walk finds its next
// sibling. Recursion depth is bounded by node count, hence by EXPR_MAX_NODES.
//
// A Gate evaluates both branches and selects between them. The language has no side
// effects, so evaluating the untaken branch is indistinguishable from skipping it,
// and skipping would need a second walk that duplicates this one's arity rules.
expr_eval_node :: proc(nodes: []Node, ctx: Expr_Context, index: int) -> (value: int, next: int) {
	assert(index < len(nodes), "expression tree is truncated: a node is missing a child")
	node := nodes[index]
	next = index + 1

	switch node.kind {
	case .Const:
		return node.value, next
	case .Quantity:
		return ctx.quantities[node.quantity], next
	case .Count:
		return expr_selector_count(ctx.counts, node.selector), next
	case .Add, .Sub, .Mul, .Min, .Max, .Pct:
		lhs, rhs: int
		lhs, next = expr_eval_node(nodes, ctx, next)
		rhs, next = expr_eval_node(nodes, ctx, next)
		return expr_apply(node.kind, lhs, rhs), next
	case .Gate:
		lhs, rhs, then_value, else_value: int
		lhs, next = expr_eval_node(nodes, ctx, next)
		rhs, next = expr_eval_node(nodes, ctx, next)
		then_value, next = expr_eval_node(nodes, ctx, next)
		else_value, next = expr_eval_node(nodes, ctx, next)
		if expr_compare(node.compare, lhs, rhs) {
			return then_value, next
		}
		return else_value, next
	}
	unreachable()
}

// expr_apply is the arithmetic of the six binary kinds. Pct multiplies by a percent
// whose divisor is a pinned literal 100 — the language's only division, and the
// reason no subtree can ever be a divisor. It truncates toward zero, the single
// rounding rule in the language.
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

// expr_compare answers a Gate's comparison. Its result is consumed on the spot and
// never becomes a value, so the language stays boolean-free.
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

// Authoring helpers. Every tree shape is built by composing these, so a tree of the
// wrong arity — a Gate missing a branch, a Sub with one operand — is a compile
// error at the call site rather than a runtime surprise. They are the only writers
// of Node's payload fields.
//
// Composition splices whole subtrees, so the node budget is spent as the tree is
// built and overrunning EXPR_MAX_NODES asserts here, at authoring time.

expr_const :: proc(value: int) -> Expr {
	return expr_leaf(Node{kind = .Const, value = value})
}

expr_quantity :: proc(quantity: Quantity_Kind) -> Expr {
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

// expr_pct is `value` taken to `percent` percent: the divisor is a pinned literal
// 100 and cannot be authored.
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
