package run

import "../ship"
import "core:math/rand"

// The encounter stage model (ADR-0014). An Encounter is an ordered list of
// Stages plus a cursor; a Stage is one of five closed primitives carrying the
// content it was baked with; a Recipe is the named, authored stage set
// generation picks whole. This file owns that model and the per-stage content
// types. The Zone/Node/Map graph an Encounter hangs off lives in run.odin
// alongside the stakes scaling group, generation in generation.odin, the
// content each stage is baked with in content.odin, and arrival-time
// resolution in encounter.odin.
//
// This replaces the Encounter_Kind enum + parallel Encounter union that stood
// here since ADR-0007: one kind per node, mirrored end to end by per-kind Sim
// phases, Commands, Events, and files. The three kinds survive as one-stage
// recipes — Ship Battle is [Fight], Item Offer [Offer], Stat Trade [Trade].

// ENCOUNTER_MAX_STAGES is the hard cap on how many stages one encounter holds,
// set by the deepest rung of ADR-0014's zone -> stage-count mapping (Coastal 1,
// Open Sea 2, The Deep 3). The cap is what lets an Encounter store its stages
// inline as a fixed-size array: no owned heap, so run_map_destroy needs no
// per-encounter cleanup beyond the opponent layout a Fight already allocates.
ENCOUNTER_MAX_STAGES :: 3

// Stage_Kind is the closed primitive alphabet (ADR-0014): the authoring
// vocabulary a Recipe names its stages in, before generation bakes each one's
// content into a Stage. Deliberately closed — adding an encounter must never
// require adding a primitive, so a sixth value here is an ADR-sized decision
// rather than a content change.
//
// This is not the retired Encounter_Kind wearing a new name. That enum said what
// a whole node *was*, exactly one kind per node, and every consumer switched on
// it; this says what one *step* of an encounter is, and a node holds an ordered
// list of them. The primitive is also the trait — variance comes from each
// stage's own content roster, not an orthogonal modifier layer.
Stage_Kind :: enum {
	Fight,
	Offer,
	Trade,
	Shop,
	Reward,
}

// ITEM_OFFER_OPTION_COUNT is how many distinct roster items an Offer stage
// presents (ADR-0012's "presents a few distinct roster items"). The player picks
// one to place — or skips — so this is the "N" in that rule. Fixed here rather
// than varying per node, which is what keeps an Offer's options a small fixed
// array on the stage; must be <= ship.ITEM_ROSTER_SIZE so the pool can supply
// that many distinct items.
ITEM_OFFER_OPTION_COUNT :: 3

// SHOP_SHELF_SIZE is how many deck cards a Shop stage shows at once — the shelf
// window onto the top of the deck (ADR-0013's "a shelf of the top 5"). The deck
// itself is the full roster (Stage_Shop.deck); this is only how much of it is
// visible/buyable at any moment. Must stay <= ship.ITEM_ROSTER_SIZE so a full
// shelf can be drawn.
SHOP_SHELF_SIZE :: 5

// Shop_Item is one purchasable card in a Shop stage: the roster `fitting` on
// offer and its `cost` in treasure. Cost is stored as a plain int, priced once at
// generation from the item's Tier (ship.ship_item_cost) — tier itself doesn't
// ride along because nothing past pricing reads it, and a bare Fitting is what
// the Refit ultimately places. Buying deducts cost from the ship's
// starting_treasure and opens a Refit to place the fitting.
Shop_Item :: struct {
	fitting: ship.Fitting,
	cost:    int,
}

// Stage_Fight is a full battle against a baked opponent, resolved via
// core/combat's phased-round Battle (ADR-0006) — this package hands off to
// combat.combat_battle_create rather than reimplementing combat. Victory
// completes the stage, Leave Combat halts it, and sinking ends the run outright
// (permadeath), which is the whole of why [Fight, Reward] needs no authored gate.
// The opponent's stats are a stakes placeholder (run_make_opponent_ship); the
// hostile roster that retires the single template is issue #135.
Stage_Fight :: struct {
	// depth is this node's normalized depth-within-zone (0..DEPTH_STEPS),
	// retained so run_finish_ship_battle can recompute the node's original tuned
	// stakes without reading them off the battle-worn opponent.
	depth:    int,
	opponent: ship.Ship,
}

// Stage_Offer presents a few distinct roster items to place by hand (ADR-0012) —
// the repurposed Upgrade Offer. `options` are the concrete items on offer, drawn
// from the roster pool and stakes-scaled at generation time
// (run_item_offer_options), so an Offer carries its items as baked content the
// way a Fight carries its opponent rather than a bare quality number resolved
// later. Picking one completes the stage and opens a Refit to place or swap it;
// skipping halts. A fixed-size array — no owned heap.
Stage_Offer :: struct {
	options: [ITEM_OFFER_OPTION_COUNT]ship.Fitting,
}

// Stage_Trade is a permanent stat-for-stat/cargo trade-off (example:
// +Durability for -Speed). Accepting completes the stage, rejecting halts it.
// Both magnitudes are stakes-scaled. The single hand-authored axis modeled here
// is one roster entry among several once issue #136 unwelds it.
Stage_Trade :: struct {
	gain_durability: int,
	cost_speed:      int,
}

// Stage_Shop sells from a seed-baked deck of the full roster, each card priced by
// tier (run_port_shop), against the ship's starting treasure. Leaving completes
// the stage — a shop cannot be failed, so Shop is the one primitive with no halt.
// It is its own primitive rather than Offer-with-a-price precisely so the Item
// Offer can be redesigned later without dragging Shop along.
//
// Shop is the one **revealing** primitive (run_stage_kind_reveals): an encounter
// holding one is visible on the map before arrival. That is what makes a Port
// just the [Shop] recipe and a merchant vessel at sea a hidden encounter that
// happens to carry a Shop stage — same primitive, placed differently. A
// fixed-size array: no owned heap.
Stage_Shop :: struct {
	deck: [ship.ITEM_ROSTER_SIZE]Shop_Item,
}

// Stage_Reward grants something outright and always completes — the "then loot
// it" half of [Fight, Reward], and the reason a halt has to keep what earlier
// stages already granted. It carries no content yet: **what** a Reward grants is
// still open (issue #132), and the primitive that spends that answer is issue
// #133. The arm exists here because the primitive set is closed and this ticket
// fixes it; its payload lands with the decision.
Stage_Reward :: struct {}

// Stage is one step of an encounter: a primitive plus the content it was baked
// with. A closed union (ADR-0014's closed alphabet) — every consumer switches
// exhaustively, so a sixth primitive is a compile error at each site rather than
// a silently-skipped case.
//
// The nil state means "no stage here": it is what fills an Encounter's unused
// array slots past its stage count, and is never a stage the cursor visits.
Stage :: union {
	Stage_Fight,
	Stage_Offer,
	Stage_Trade,
	Stage_Shop,
	Stage_Reward,
}

// run_stage_kind reports which primitive a baked Stage is — the inverse of
// run_bake_stage, mapping content back to the authoring alphabet. Consumers that
// need the content itself should switch on the Stage directly; this is for the
// ones that only need to ask what kind of step this is (visibility, presentation
// labels, a recipe round-trip).
run_stage_kind :: proc(s: Stage) -> Stage_Kind {
	switch _ in s {
	case Stage_Fight:
		return .Fight
	case Stage_Offer:
		return .Offer
	case Stage_Trade:
		return .Trade
	case Stage_Shop:
		return .Shop
	case Stage_Reward:
		return .Reward
	}
	unreachable()
}

// Stage_Outcome is the whole of an encounter's control flow (ADR-0014): the two
// values every stage resolves to, shared by all five primitives. Completed
// advances the cursor to the next stage; Halted ends the encounter where it
// stands, keeping whatever earlier stages already granted.
//
// There are no authored gates — a Recipe never says "advance only if the player
// won". The primitive that just resolved decides which outcome it hands in: Fight
// completes on victory and halts on Leave Combat; Offer completes on a pick and
// halts on a skip; Trade completes on accept and halts on reject; Shop completes
// on leaving; Reward always completes. That is what makes [Fight, Reward] mean
// the obvious thing with no authoring — flee the blockade and the loot stage is
// never reached.
Stage_Outcome :: enum {
	Completed,
	Halted,
}

// Encounter is what a non-landmark node holds and what fires on first arrival
// (no decline once arrived): an ordered list of stages plus the cursor walking
// them. There is exactly one Encounter type — the interaction a node presents is
// its stage list, not a kind tag.
//
// Storage is inline and fixed-size, bounded by ENCOUNTER_MAX_STAGES: an
// Encounter owns no heap, so a Map full of them frees with its nodes and
// run_map_destroy only has to reach the opponent layout inside a Fight. `count`
// is the authored length — slots from there to the cap are nil — and `cursor` is
// the walk position, run_encounter_is_finished once it reaches count. A halt
// finishes the walk by jumping the cursor to count rather than by a separate
// flag, so "is there another stage" has exactly one answer to read.
Encounter :: struct {
	stages: [ENCOUNTER_MAX_STAGES]Stage,
	count:  int,
	cursor: int,
}

// Recipe is the authored unit of encounter content (ADR-0014): a name plus the
// ordered primitives its stages are drawn from. `Sea Battle = [Fight, Reward]`.
// Generation picks a whole recipe and bakes each stage's content from that
// stage's own roster — it never composes a stage list, because mix-and-match is a
// developer authoring tool, not a runtime generative system.
//
// `stages` holds primitives, not baked Stages: a recipe is static authored data
// reused by every node that draws it, while the content is per-node. Which bucket
// a recipe belongs to is **derived** from its stage count and never authored —
// there is deliberately no bucket field, so a recipe cannot be filed in the wrong
// bucket because it isn't filed at all.
Recipe :: struct {
	name:   string,
	stages: []Stage_Kind,
}

// run_encounter_from_recipe bakes one authored recipe into a node's Encounter:
// each of the recipe's primitives rolls its own content at this node's
// Scaling_Site, in order. Takes `gen` so the stages that sample the roster (an
// Offer's items, a Shop's deck) draw reproducibly from the map generator's RNG —
// an encounter's stages and content are baked here at generation time and nothing
// rolls on arrival (ADR-0013's no-runtime-RNG property, now covering every stage).
run_encounter_from_recipe :: proc(r: Recipe, site: Scaling_Site, gen: rand.Generator) -> Encounter {
	assert(len(r.stages) > 0, "a recipe must author at least one stage")
	assert(len(r.stages) <= ENCOUNTER_MAX_STAGES, "a recipe authored more stages than an Encounter can hold")

	e := Encounter{count = len(r.stages)}
	for kind, i in r.stages {
		e.stages[i] = run_bake_stage(kind, site, gen)
	}
	return e
}

// run_encounter_current returns the stage the cursor is on, or ok=false once the
// walk has finished (the last stage completed, or any stage halted). This is the
// read half of the generic stage walk; run_encounter_resolve_stage is the write
// half.
run_encounter_current :: proc(e: Encounter) -> (stage: Stage, ok: bool) {
	if run_encounter_is_finished(e) {
		return nil, false
	}
	return e.stages[e.cursor], true
}

// run_encounter_is_finished reports whether the walk is over — the cursor has
// passed the last stage, either by completing it or because a halt jumped it
// there.
run_encounter_is_finished :: proc(e: Encounter) -> bool {
	return e.cursor >= e.count
}

// run_encounter_resolve_stage records the outcome of the stage under the cursor
// and moves the encounter on (ADR-0014's complete-or-halt): Completed advances to
// the next stage, Halted ends the encounter where it stands. Returns whether a
// further stage is now pending, so the caller's walk is `for stage in ...` rather
// than a per-primitive phase graph.
//
// Resolving a stage on an already-finished encounter is a driver bug, not a
// runtime rejection — the caller asks run_encounter_current first and gets ok=false.
run_encounter_resolve_stage :: proc(e: ^Encounter, outcome: Stage_Outcome) -> (more: bool) {
	assert(!run_encounter_is_finished(e^), "resolved a stage on an encounter whose walk already finished")

	switch outcome {
	case .Completed:
		e.cursor += 1
	case .Halted:
		e.cursor = e.count
	}
	return !run_encounter_is_finished(e^)
}

// run_stage_kind_reveals reports whether a primitive shows its whole encounter on
// the map before the ship arrives (ADR-0014). Today only Shop reveals: a shop you
// cannot see is a shop you cannot route to, which is the entire point of a Port's
// map presence. Every other primitive stays a surprise until arrival (ADR-0009's
// hiding contract).
run_stage_kind_reveals :: proc(kind: Stage_Kind) -> bool {
	return kind == .Shop
}

// run_encounter_reveals reports whether an encounter shows itself on the map
// before arrival: true iff it contains a revealing stage. This is what replaces
// asking a node whether it is a Port — visibility is a question asked of the
// stage list, never a node fact, so a Port is just the [Shop] recipe and a
// merchant vessel at sea is a hidden encounter carrying a Shop stage.
run_encounter_reveals :: proc(e: Encounter) -> bool {
	for i in 0 ..< e.count {
		if run_stage_kind_reveals(run_stage_kind(e.stages[i])) {
			return true
		}
	}
	return false
}
