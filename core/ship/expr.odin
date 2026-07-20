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

// Node_Kind is a node's operation. Arity is fixed per kind (EXPR_NODE_ARITY), which
// is what lets prefix order alone imply a tree's structure: no node stores a child
// index.
Node_Kind :: enum u8 {
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
Quantity :: enum u8 {
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
Compare_Op :: enum u8 {
	Eq,
	Ne,
	Lt,
	Lte,
	Gt,
	Gte,
}

// Count_Side is whose census a Count node reads. Own is the zero value, so the
// default reading is the ship the effect is installed on; the opponent's census is
// the scouting report (Expr_Context.opponent), never their layout.
Count_Side :: enum u8 {
	Own,
	Opponent,
}

// Node is one entry of a prefix-ordered tree. Each payload field is read only by
// the kind that owns it (`value` by Const, `quantity` by Quantity, `selector` and
// `side` by Count, `compare` by Gate) and is inert otherwise; the authoring helpers
// below set them, so no caller assembles the meaningless combinations. The zero Node
// is a Const 0, so a zero-filled array is valid, inert data rather than a trap.
//
// Its fields are the **narrowest types that hold them, ordered widest-first**, which is
// load-bearing rather than fussy: a Node is multiplied by the tree bound, then by a
// fitting's effects, then by a ship's slots, on every layout copy, every roster and every
// Ghost_Snapshot — and a padding byte between the i32 and the single-byte fields costs
// exactly what a real one does. A literal magnitude is an i32 because the whole game is
// denominated in Hull, which is authored around 100.
Node :: struct {
	value:    i32,
	selector: Selector,
	kind:     Node_Kind,
	quantity: Quantity,
	side:     Count_Side,
	compare:  Compare_Op,
}

// Expr is a whole authored tree: its nodes in prefix order, plus how many of them
// are live. Inline POD — it copies by assignment and allocates nothing.
Expr :: struct {
	nodes: [EXPR_MAX_NODES]Node,
	count: int,
}

// Expr_Context is everything a tree may read, flattened to plain data: one scalar
// per Quantity, the census a Count selects over, and the opponent's — which arrives
// already filtered to what concealment leaves visible (ship_scouting_report). It
// holds no Ship, layout or Battle, which is what keeps the evaluator pure arithmetic
// and is why no tree can ever reach past the scouting report into the other ship.
Expr_Context :: struct {
	quantities: [Quantity]int,
	counts:     Count_Table,
	opponent:   Count_Table,
}

// Count_Table is the pre-counted fitting census a Count node reads, one array per
// Selector axis. Counting is the caller's job, so the evaluator never walks a
// layout.
Count_Table :: struct {
	tag:        [Tag]int,
	size:       [Slot_Size]int,
	visibility: [Visibility]int,
}

// EXPR_NODE_ARITY is how many child subtrees a kind consumes, and the single
// statement of that: evaluation reads its children through this, so prefix
// structure has one source of truth. Gate's four are lhs, rhs, then and else — its
// comparison op rides on the node itself. A new kind that names no arity here is a
// compile error, the same coverage an exhaustive switch would give.
@(rodata)
EXPR_NODE_ARITY := [Node_Kind]int {
	.Const    = 0,
	.Quantity = 0,
	.Count    = 0,
	.Add      = 2,
	.Sub      = 2,
	.Mul      = 2,
	.Min      = 2,
	.Max      = 2,
	.Pct      = 2,
	.Gate     = 4,
}

// Gate_Mode is how a walk answers a Gate: by comparing (Compared — a real round), by
// taking its open branch outright (Open — the item-card reading, expr_showcase), or by
// taking its larger branch (Peak — the pricing reading, expr_peak). It is the *only*
// difference between the three walks, which is why there is one walker.
Gate_Mode :: enum {
	Compared,
	Open,
	Peak,
}

// expr_eval resolves `e` against `ctx`. Pure: it reads only its arguments, writes
// nothing, and allocates nothing. An empty tree evaluates to 0.
expr_eval :: proc(e: Expr, ctx: Expr_Context) -> int {
	return expr_walk(e, ctx, .Compared)
}

// expr_walk is expr_eval with the Gate answer left to the caller. Both readings of a tree
// go through it, so a change to the language's arithmetic cannot be made in one and
// forgotten in the other.
@(private = "file")
expr_walk :: proc(e: Expr, ctx: Expr_Context, gates: Gate_Mode) -> int {
	if e.count == 0 {
		return 0
	}
	assert(e.count <= EXPR_MAX_NODES, "expression tree exceeds the node bound")
	nodes := e.nodes
	value, next := expr_eval_node(nodes[:e.count], ctx, 0, gates)
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
expr_eval_node :: proc(nodes: []Node, ctx: Expr_Context, index: int, gates := Gate_Mode.Compared) -> (value: int, next: int) {
	assert(index < len(nodes), "expression tree is truncated: a node is missing a child")
	node := nodes[index]
	next = index + 1

	children: [EXPR_MAX_ARITY]int
	for i in 0 ..< EXPR_NODE_ARITY[node.kind] {
		children[i], next = expr_eval_node(nodes, ctx, next, gates)
	}

	switch node.kind {
	case .Const:
		return int(node.value), next
	case .Quantity:
		return ctx.quantities[node.quantity], next
	case .Count:
		census := node.side == .Own ? ctx.counts : ctx.opponent
		return expr_selector_count(census, node.selector), next
	case .Add, .Sub, .Mul, .Min, .Max, .Pct:
		return expr_apply(node.kind, children[0], children[1]), next
	case .Gate:
		if gates == .Peak {
			return max(children[2], children[3]), next
		}
		if gates == .Open || expr_compare(node.compare, children[0], children[1]) {
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
	}
	return 0
}

// Authoring helpers. Composing these is how a tree is written: arity lives in a
// helper's signature, so a tree of the wrong shape — a Gate missing a branch, a Sub
// with one operand — is a compile error at the call site rather than a runtime
// surprise. Composition splices whole subtrees, so the node budget is spent as the
// tree is built and an overrun asserts here, at authoring time.

expr_const :: proc(value: int) -> Expr {
	return expr_leaf(Node{kind = .Const, value = i32(value)})
}

expr_quantity :: proc(quantity: Quantity) -> Expr {
	return expr_leaf(Node{kind = .Quantity, quantity = quantity})
}

// expr_count counts the owning ship's own installed fittings matching `selector`.
// There is no "empty slots" criterion to count, here or in Quantity: removing a
// fitting backfills a hold (ship_remove), so an empty slot is unreachable in play and
// `count(empty slots)` and `count(Tag.Cargo)` were always the same fact. Its absence
// from Selector is the rejection — an author cannot spell it.
expr_count :: proc(selector: Selector) -> Expr {
	return expr_leaf(Node{kind = .Count, selector = selector})
}

// expr_count_opponent counts the *opponent's* matching fittings as the scouting
// report saw them (ship_scouting_report): concealed fittings are not in the census at
// all, so concealment is a real counter to being read rather than a check somewhere
// downstream. Outside a battle there is no report and every count reads 0.
expr_count_opponent :: proc(selector: Selector) -> Expr {
	return expr_leaf(Node{kind = .Count, selector = selector, side = .Opponent})
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
//
// **Ordering comparisons on the captain's order are rejected here**, at authoring
// time. Captains_Order is one ordinal quantity rather than four boolean-valued ones
// — four would reintroduce the two-spellings-at-two-prices arbitrage through the
// quantity door — but an ordinal is only an encoding, not a scale: "at least Press
// Fire" is a sentence about integers, not about orders. Equality is the whole of what
// the encoding means, so `<`, `<=`, `>` and `>=` over it are a compile-time-authored
// mistake and assert rather than resolve.
expr_gate :: proc(op: Compare_Op, lhs: Expr, rhs: Expr, then_expr: Expr, else_expr: Expr) -> Expr {
	expr_assert_order_is_only_matched(op, lhs)
	expr_assert_order_is_only_matched(op, rhs)

	result: Expr
	expr_push(&result, Node{kind = .Gate, compare = op})
	expr_splice(&result, lhs)
	expr_splice(&result, rhs)
	expr_splice(&result, then_expr)
	expr_splice(&result, else_expr)
	return result
}

// expr_assert_order_is_only_matched holds the captain's order to the one thing its
// encoding means. A comparand that reads it must be **the bare reading and nothing else**,
// matched with Eq or Ne: `order == Commit` is a sentence about orders, while
// `order >= Press_Fire` is a sentence about the integers they happen to be numbered with,
// and `max(order, 2) == 2` is the same sentence through the arithmetic door. Guarding only
// the comparison operator would leave that door open (expr_binary shuts it from the
// other side).
@(private = "file")
expr_assert_order_is_only_matched :: proc(op: Compare_Op, comparand: Expr) {
	if !expr_reads_quantity(comparand, .Captains_Order) {
		return
	}
	assert(
		op == .Eq || op == .Ne,
		"the captain's order is an ordinal encoding, not a scale: match it with Eq or Ne",
	)
	assert(
		comparand.count == 1,
		"the captain's order is an ordinal encoding, not a scale: match the reading itself, not arithmetic over it",
	)
}

// expr_subtree lifts the subtree rooted at `index` out of `e` as a tree of its own, and
// reports the index just past it. The span is found the same way evaluation finds a
// sibling — by arity, one node at a time — so prefix order stays the only thing that
// records structure.
expr_subtree :: proc(e: Expr, index: int) -> (sub: Expr, next: int) {
	pending := 1
	next = index
	for pending > 0 {
		assert(next < e.count, "expression tree is truncated: a node is missing a child")
		pending += EXPR_NODE_ARITY[e.nodes[next].kind] - 1
		next += 1
	}
	for i in index ..< next {
		expr_push(&sub, e.nodes[i])
	}
	return sub, next
}

// expr_gate_parts decomposes a Gate-rooted tree back into the four subtrees it was
// authored from. Asserts the root is a Gate, so a caller that has not checked cannot get a
// meaningless answer.
expr_gate_parts :: proc(e: Expr) -> (op: Compare_Op, lhs: Expr, rhs: Expr, then_expr: Expr, else_expr: Expr) {
	assert(e.count > 0 && e.nodes[0].kind == .Gate, "expr_gate_parts wants a Gate-rooted tree")
	op = e.nodes[0].compare
	next := 1
	lhs, next = expr_subtree(e, next)
	rhs, next = expr_subtree(e, next)
	then_expr, next = expr_subtree(e, next)
	else_expr, _ = expr_subtree(e, next)
	return
}

// Tree readers. A tree is a flat array, so a question about what it *says* is a scan
// rather than a walk — no recursion, and the reading is the same whatever shape the
// nodes were composed into.

// expr_reads_quantity reports whether `e` reads `quantity` anywhere. It is how the
// layering rule is enforced at authoring time (effect_modify_speed) rather than as a
// runtime zero: a fallback that quietly resolves a forbidden read to 0 is exactly the
// dead-conditions defect this work exists to delete.
expr_reads_quantity :: proc(e: Expr, quantity: Quantity) -> bool {
	for i in 0 ..< e.count {
		if e.nodes[i].kind == .Quantity && e.nodes[i].quantity == quantity {
			return true
		}
	}
	return false
}

// expr_is_conditional reports whether `e` contains a Gate — whether what it yields
// depends on anything. Presentation reads it to say an item's strength is conditional
// without rendering the tree (fitting_effect_intent).
expr_is_conditional :: proc(e: Expr) -> bool {
	for i in 0 ..< e.count {
		if e.nodes[i].kind == .Gate {
			return true
		}
	}
	return false
}

// expr_showcase is the tree read **as an item card, not as a round**: every Gate takes
// its open branch and every Count reads 1, so the answer is what the item is worth when
// what it asks for is true. Presentation and the content tests need a number for an item
// held in the hand, where there is no ship, round or opponent to resolve against — and a
// context of zeroes would answer that question with every gate shut, which reads as "this
// item does nothing".
//
// It is a reading of the tree, never an evaluation of a round: nothing in combat calls it.
expr_showcase :: proc(e: Expr) -> int {
	ctx: Expr_Context
	for tag in Tag {
		ctx.counts.tag[tag] = 1
		ctx.opponent.tag[tag] = 1
	}
	for size in Slot_Size {
		ctx.counts.size[size] = 1
		ctx.opponent.size[size] = 1
	}
	for visibility in Visibility {
		ctx.counts.visibility[visibility] = 1
		ctx.opponent.visibility[visibility] = 1
	}
	return expr_walk(e, ctx, .Open)
}

// expr_peak is the tree read **as the most it can ever yield**: every Count reads the
// peak census the ship layout admits (ship_count_peaks) and every Gate takes its larger
// branch, so a conditional prices at what it pays when its condition holds. It is the
// magnitude the power budget charges for (ship_effect_cost), and it is a reading of the
// tree rather than of a round — nothing in combat calls it.
//
// Min, Max and Pct need no special answer: evaluated over peak inputs they already
// yield the peak. A tree that reads a **quantity** as its magnitude rather than inside a
// gate's comparands peaks at 0 here and so prices at nothing — the budget has no bound
// to charge such a tree against, so an item wanting one is a finding, not an authoring.
expr_peak :: proc(e: Expr, peaks: Count_Table) -> int {
	return expr_walk(e, Expr_Context{counts = peaks, opponent = peaks}, .Peak)
}

// Composed shapes: the tree an item writes when it wants one of the readings the roster
// leans on, written once here rather than fifty times as raw trees. Each is an ordinary
// composition of the primitives above — a Gate with the
// item's magnitude on the open branch and nothing on the other — not a closed set an author must pick
// from: an item wanting something outside these writes its own tree and costs the nodes it
// costs. Nothing in the evaluator knows they exist.
//
// Both branches are authored as constants, so a bonus applied to the item later
// (ship_fitting_scaled) lands outside the gate — see that proc for what that means.

// expr_below_hull_percent is the "desperate" shape: full magnitude while the owner's Hull
// is strictly below `percent` percent of its maximum, nothing above it. Written as a
// cross-multiplication rather than as a percentage of max Hull, so the comparison is exact
// at every max-Hull value instead of resting on where a division truncates.
expr_below_hull_percent :: proc(percent: int, magnitude: int) -> Expr {
	return expr_gate(
		.Lt,
		expr_mul(expr_quantity(.Own_Hull), expr_const(100)),
		expr_mul(expr_quantity(.Own_Max_Hull), expr_const(percent)),
		expr_const(magnitude),
		expr_const(0),
	)
}

// expr_from_round is the "warms up" shape: nothing until battle `round`, full magnitude
// from it on. Round is 1-based, matching Battle.round.
expr_from_round :: proc(round: int, magnitude: int) -> Expr {
	return expr_gate(.Gte, expr_quantity(.Round), expr_const(round), expr_const(magnitude), expr_const(0))
}

// expr_while_concealed is the "hidden" shape: full magnitude while the slot the effect
// sits in is Concealed, nothing while it is Exposed.
// Visibility is an ordinal quantity, so the gate is an equality against its value.
expr_while_concealed :: proc(magnitude: int) -> Expr {
	return expr_gate(
		.Eq,
		expr_quantity(.Own_Visibility),
		expr_const(int(Visibility.Concealed)),
		expr_const(magnitude),
		expr_const(0),
	)
}

// expr_while_opponent_faster / _slower are the "chase" shapes: full magnitude while the
// opponent's effective Speed is strictly greater / less than the owner's. Both speeds are
// pass-two quantities, so these are only authorable on effects resolved in a phase — a
// Modify_Speed item reading them is rejected at authoring time (effect_modify_speed).
expr_while_opponent_faster :: proc(magnitude: int) -> Expr {
	return expr_gate(
		.Gt,
		expr_quantity(.Opponent_Speed),
		expr_quantity(.Own_Speed),
		expr_const(magnitude),
		expr_const(0),
	)
}

expr_while_opponent_slower :: proc(magnitude: int) -> Expr {
	return expr_gate(
		.Lt,
		expr_quantity(.Opponent_Speed),
		expr_quantity(.Own_Speed),
		expr_const(magnitude),
		expr_const(0),
	)
}

// expr_with_bonus is effect_with_bonus's rule as arithmetic: down a Gate's open branch,
// recursively (so a nested gate is followed to the end), and at the root of anything else.
// It asks whether the **root** is a Gate, not whether the tree contains one — a gate
// buried under a Mul is part of that tree's arithmetic, not a branch to choose between.
expr_with_bonus :: proc(e: Expr, bonus: int) -> Expr {
	if e.count == 0 || e.nodes[0].kind != .Gate {
		return expr_add(e, expr_const(bonus))
	}
	op, lhs, rhs, then_expr, else_expr := expr_gate_parts(e)
	return expr_gate(op, lhs, rhs, expr_with_bonus(then_expr, bonus), else_expr)
}

@(private = "file")
expr_leaf :: proc(node: Node) -> Expr {
	result: Expr
	expr_push(&result, node)
	return result
}

@(private = "file")
expr_binary :: proc(kind: Node_Kind, lhs: Expr, rhs: Expr) -> Expr {
	// The other half of the captain's-order ruling: arithmetic over the encoding is how
	// an ordering comparison would be spelled without an ordering operator, so no binary
	// node may take it as an operand at all. It leaves the Gate as its only reader.
	assert(
		!expr_reads_quantity(lhs, .Captains_Order) && !expr_reads_quantity(rhs, .Captains_Order),
		"the captain's order is an ordinal encoding, not a scale: no arithmetic reads it",
	)
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
