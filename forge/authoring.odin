package forge

import ship "../core/ship"

// The edit-time authoring rules, as pure functions over the data the editor is about to
// commit.
//
// Every rule here is an **assert in core's authoring helpers**: expr_gate and expr_binary
// hold the captain's order to its encoding, effect_modify_speed refuses a tree that reads
// a speed, effect_with_timing refuses a timing on Modify_Speed and an incoherent cadence,
// and expr_push refuses a tree past the node bound. A tool that let a user assemble one of
// those and only found out on emit would crash on their work, so the editor asks here
// first and keeps the old value when the answer is no.
//
// The check is always taken of the **whole candidate tree**, never of the node being
// touched: an edit deep in a tree can make an ancestor illegal (a Const swapped for a
// Captains_Order reading turns the Mul above it into arithmetic over the order), so there
// is no local rule to apply.

// Edit_Fault is why an edit was refused, `.None` when it was taken. It is the authoring
// half of ship.Roster_Fault: the faults a helper would have asserted on, plus the two
// timing parameters whose coherence effect_with_timing makes.
Edit_Fault :: enum {
	None,
	Node_Bound_Overrun,
	Speed_Reads_Speed,
	Order_Is_Not_A_Scale,
	Speed_Carries_A_Timing,
	Peak_Output_Over_Cap,
	Cadence_Not_Positive,
	Charge_Not_Positive,
}

// EDIT_FAULT_REASON is what the editor says when it refuses, one line per fault, phrased
// as the rule rather than as the failure — an author who reads it should know what to
// author instead.
@(rodata)
EDIT_FAULT_REASON := [Edit_Fault]string {
	.None                   = "",
	.Node_Bound_Overrun     = "the tree is bounded at EXPR_MAX_NODES, and every arity is even, so 11 nodes is the largest well-formed tree",
	.Speed_Reads_Speed      = "a Modify_Speed tree reads no speed: Speed is the layer it is an input to",
	.Order_Is_Not_A_Scale   = "the captain's order is an encoding: match the bare reading with Eq or Ne, and do no arithmetic over it",
	.Speed_Carries_A_Timing = "a Modify_Speed effect is Always: its consumer is read off the battlefield, where no counter exists",
	.Peak_Output_Over_Cap   = "a gated effect's peak output is capped: a gate discounts the price without shrinking the number that lands",
	.Cadence_Not_Positive   = "Timing_Every_N wants a cadence of at least one round",
	.Charge_Not_Positive    = "Timing_Charge wants a positive cost and a positive gain",
}

// expr_edit_fault is the tree half of the contract: what core's helpers would have
// asserted on had this tree been composed through them for `verb`.
expr_edit_fault :: proc(e: ship.Expr, verb: ship.Verb) -> Edit_Fault {
	if e.count <= 0 || e.count > ship.EXPR_MAX_NODES {
		return .Node_Bound_Overrun
	}
	if ship.expr_scales_the_captains_order(e) {
		return .Order_Is_Not_A_Scale
	}
	if order_is_scaled_inside_a_comparand(e) {
		return .Order_Is_Not_A_Scale
	}
	if verb == .Modify_Speed {
		if ship.expr_reads_quantity(e, .Own_Speed) || ship.expr_reads_quantity(e, .Opponent_Speed) {
			return .Speed_Reads_Speed
		}
	}
	return .None
}

// order_is_scaled_inside_a_comparand is the half of expr_gate's ruling that reading an
// assembled tree does not catch. expr_scales_the_captains_order looks for arithmetic over
// the order and for an ordering comparison on it, but expr_gate refuses a third thing: a
// comparand that reads the order must be the **bare reading**, even under Eq. `max(order,
// 2) == 2` is the same sentence through the arithmetic door, and a Gate nested inside a
// Gate's comparand is the way an editor can reach one.
@(private = "file")
order_is_scaled_inside_a_comparand :: proc(e: ship.Expr) -> bool {
	for i in 0 ..< e.count {
		if e.nodes[i].kind != .Gate {
			continue
		}
		lhs, rhs, _ := ship.expr_gate_comparands(e, i)
		op := e.nodes[i].compare
		for comparand in ([]ship.Expr{lhs, rhs}) {
			if !ship.expr_reads_quantity(comparand, .Captains_Order) {
				continue
			}
			if op != .Eq && op != .Ne {
				return true
			}
			if comparand.count != 1 {
				return true
			}
		}
	}
	return false
}

// timing_edit_fault is the timing half: the pairing effect_with_timing refuses outright,
// and the two settings the union's shape cannot rule out.
timing_edit_fault :: proc(timing: ship.Timing, verb: ship.Verb) -> Edit_Fault {
	switch t in timing {
	case ship.Timing_Always:
		return .None
	case ship.Timing_Once_Per_Battle, ship.Timing_Ramp:
	case ship.Timing_Every_N:
		if t.n <= 0 {
			return .Cadence_Not_Positive
		}
	case ship.Timing_Charge:
		if t.cost <= 0 || t.per_round <= 0 {
			return .Charge_Not_Positive
		}
	}
	if verb == .Modify_Speed {
		return .Speed_Carries_A_Timing
	}
	return .None
}

// effect_edit_fault is the whole of what one effect may be refused for. It calls core's
// own effect_fault for the rules stated in the budget and adds the timing parameters,
// which effect_fault does not see because a Timing that reached it was already made
// coherent where it was authored.
effect_edit_fault :: proc(effect: ship.Effect, peaks: ship.Count_Table) -> Edit_Fault {
	if fault := timing_edit_fault(effect.timing, effect.verb); fault != .None {
		return fault
	}
	switch ship.effect_fault(effect, peaks) {
	case .Node_Bound_Overrun:
		return .Node_Bound_Overrun
	case .Speed_Reads_Speed:
		return .Speed_Reads_Speed
	case .Order_Is_Not_A_Scale:
		return .Order_Is_Not_A_Scale
	case .Speed_Carries_A_Timing:
		return .Speed_Carries_A_Timing
	case .Peak_Output_Over_Cap:
		return .Peak_Output_Over_Cap
	case .None, .Unnamed, .Weight_Off_Band, .Bulk_Outside_Slot, .Effect_Count_Off_Band, .Under_Band, .Over_Band:
	}
	return .None
}

// Tree editing. A tree is prefix-ordered with arity fixed per kind, so every operation
// below is "find the span of the subtree at `index`, splice a different span in its
// place" — the same walk expr_subtree does, which is what keeps prefix order the only
// thing recording structure.

// expr_children lifts the subtrees a node's arity consumes, so an edit that changes a
// node's kind can carry the work already done in its children across.
expr_children :: proc(e: ship.Expr, index: int) -> (children: [ship.EXPR_MAX_ARITY]ship.Expr, count: int) {
	next := index + 1
	count = ship.EXPR_NODE_ARITY[e.nodes[index].kind]
	for i in 0 ..< count {
		children[i], next = ship.expr_subtree(e, next)
	}
	return
}

// expr_graft returns `e` with the subtree at `index` replaced by `sub`. It is the one
// structural mutation the editor makes; everything else composes it.
expr_graft :: proc(e: ship.Expr, index: int, sub: ship.Expr) -> (out: ship.Expr, ok: bool) {
	assert(index >= 0 && index < e.count, "expr_graft wants an index inside the tree")
	_, after := ship.expr_subtree(e, index)
	if index + sub.count + (e.count - after) > ship.EXPR_MAX_NODES {
		return {}, false
	}
	for i in 0 ..< index {
		out = expr_pushed(out, e.nodes[i])
	}
	for i in 0 ..< sub.count {
		out = expr_pushed(out, sub.nodes[i])
	}
	for i in after ..< e.count {
		out = expr_pushed(out, e.nodes[i])
	}
	return out, true
}

// expr_with_kind rebuilds the node at `index` as `kind`, keeping the children the new
// arity still has room for and filling the rest with a zero constant. Re-kinding is the
// editor's main move — a slot is picked from the kind dropdown and the tree grows or
// shrinks to the arity that names — so carrying the children across is what makes the
// dropdown an edit rather than a reset.
expr_with_kind :: proc(e: ship.Expr, index: int, kind: ship.Node_Kind) -> (out: ship.Expr, ok: bool) {
	children, child_count := expr_children(e, index)

	node := e.nodes[index]
	node.kind = kind
	if kind == .Count {
		if _, authored := node.selector.(ship.Tag); !authored {
			if _, sized := node.selector.(ship.Slot_Size); !sized {
				if _, seen := node.selector.(ship.Visibility); !seen {
					node.selector = ship.Tag.Crew
				}
			}
		}
	}

	sub: ship.Expr
	sub = expr_pushed(sub, node)
	for i in 0 ..< ship.EXPR_NODE_ARITY[kind] {
		child := i < child_count ? children[i] : ship.expr_const(0)
		if sub.count + child.count > ship.EXPR_MAX_NODES {
			return {}, false
		}
		for k in 0 ..< child.count {
			sub = expr_pushed(sub, child.nodes[k])
		}
	}
	return expr_graft(e, index, sub)
}

// expr_rebuild reassembles a tree by **calling the expr_* authoring helpers** for every
// node, bottom up. It is what makes an ill-formed tree unrepresentable rather than
// rejected: arity comes from each helper's signature, so the tree the editor commits is a
// tree core's own composition could have produced.
//
// The helpers assert on the authoring rules, so a caller runs expr_edit_fault first —
// expr_commit is the pairing of the two and the only way the editor writes a tree.
expr_rebuild :: proc(e: ship.Expr, index: int = 0) -> (sub: ship.Expr, next: int) {
	node := e.nodes[index]
	next = index + 1

	children: [ship.EXPR_MAX_ARITY]ship.Expr
	for i in 0 ..< ship.EXPR_NODE_ARITY[node.kind] {
		children[i], next = expr_rebuild(e, next)
	}

	switch node.kind {
	case .Const:
		return ship.expr_const(int(node.value)), next
	case .Quantity:
		return ship.expr_quantity(node.quantity), next
	case .Count:
		if node.side == .Opponent {
			return ship.expr_count_opponent(node.selector), next
		}
		return ship.expr_count(node.selector), next
	case .Add:
		return ship.expr_add(children[0], children[1]), next
	case .Sub:
		return ship.expr_sub(children[0], children[1]), next
	case .Mul:
		return ship.expr_mul(children[0], children[1]), next
	case .Min:
		return ship.expr_min(children[0], children[1]), next
	case .Max:
		return ship.expr_max(children[0], children[1]), next
	case .Pct:
		return ship.expr_pct(children[0], children[1]), next
	case .Gate:
		return ship.expr_gate(node.compare, children[0], children[1], children[2], children[3]), next
	}
	unreachable()
}

// expr_commit is the editor's one write path: check the candidate against the authoring
// rules, and only then reassemble it through the helpers. A refused candidate is dropped
// and the caller keeps what it had.
expr_commit :: proc(candidate: ship.Expr, verb: ship.Verb) -> (out: ship.Expr, fault: Edit_Fault) {
	if fault = expr_edit_fault(candidate, verb); fault != .None {
		return candidate, fault
	}
	out, _ = expr_rebuild(candidate)
	return out, .None
}

// expr_peaks_at_nothing flags the trap expr_peak documents: a tree whose magnitude is a
// **quantity** read outside a gate's comparands peaks at 0, so the budget has no bound to
// charge it against, so the budget charges nothing for an item that pays out every round.
// That is a finding, not an authoring, and the panel says so loudly. It is the pairing of
// the two readings that identifies it: a tree that reads no quantity and peaks at 0 is
// simply an item authored to do nothing, which the band catches instead.
expr_peaks_at_nothing :: proc(e: ship.Expr, peaks: ship.Count_Table) -> bool {
	if e.count == 0 || ship.expr_peak(e, peaks) > 0 {
		return false
	}
	for i in 0 ..< e.count {
		if e.nodes[i].kind == .Quantity {
			return true
		}
	}
	return false
}

// Composed shapes. expr.odin writes five trees the roster leans on; the editor offers
// each as a preset that drops a pre-built, still-editable subtree. They are a convenience
// and not a closed set — a tree outside them is authored node by node and costs the nodes
// it costs.
Preset :: enum {
	Below_Hull_Percent,
	From_Round,
	While_Concealed,
	While_Opponent_Faster,
	While_Opponent_Slower,
}

@(rodata)
PRESET_LABEL := [Preset]string {
	.Below_Hull_Percent    = "desperate: below N% hull",
	.From_Round            = "warms up: from round N",
	.While_Concealed       = "hidden: while concealed",
	.While_Opponent_Faster = "chase: opponent faster",
	.While_Opponent_Slower = "chase: opponent slower",
}

// preset_takes_threshold reports whether a preset reads its first parameter at all — the
// two chase shapes and the concealment shape carry only a magnitude.
preset_takes_threshold :: proc(preset: Preset) -> bool {
	return preset == .Below_Hull_Percent || preset == .From_Round
}

preset_expr :: proc(preset: Preset, threshold: int, magnitude: int) -> ship.Expr {
	switch preset {
	case .Below_Hull_Percent:
		return ship.expr_below_hull_percent(threshold, magnitude)
	case .From_Round:
		return ship.expr_from_round(threshold, magnitude)
	case .While_Concealed:
		return ship.expr_while_concealed(magnitude)
	case .While_Opponent_Faster:
		return ship.expr_while_opponent_faster(magnitude)
	case .While_Opponent_Slower:
		return ship.expr_while_opponent_slower(magnitude)
	}
	unreachable()
}

// expr_pushed appends one node, the editor's own bounded push — core's is file-private,
// and the editor needs a push that reports an overrun instead of asserting on it. Callers
// check the bound before building; this clamps rather than corrupts if one forgets.
@(private = "file")
expr_pushed :: proc(e: ship.Expr, node: ship.Node) -> ship.Expr {
	out := e
	if out.count >= ship.EXPR_MAX_NODES {
		return out
	}
	out.nodes[out.count] = node
	out.count += 1
	return out
}
