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

// SHOP_SHELF_SIZE is how many cards a Shop stage shows at once — the window onto
// the top of its stock (ADR-0013's "a shelf of the top 5"). This is only how much
// of the stock is visible/buyable at any moment; buying refills the slot from the
// stock behind it.
//
// **The window survives the loss of cross-visit persistence** (issue #137), which
// is not obvious — ADR-0013's original reason for it was draw-down *across* visits,
// and #131 retired that. It earns its place for a different reason now: #124's depth
// surcharge, which charges more for each successive buy at one shop, only means
// something if buying reveals something new. Show the whole stock at once and the
// surcharge degenerates into a flat "buying more costs more" tax on a menu the
// captain has already read. Behind a window it is the price of *digging* — spend a
// little to see what else is in the hold — which is the decision the shop is for.
//
// A constant rather than a per-pool authored knob: how much of any shop you can take
// in at a glance is a property of looking at shops, not of which shop it is. What
// varies per pool is what is behind the window (Stock.depth).
SHOP_SHELF_SIZE :: 5

// SHOP_STOCK_MAX is the hard cap on how many cards one Shop stage holds — the
// deepest hold any authored pool asks for (content.odin's stock_pools), checked
// against that table by test the way ENCOUNTER_MAX_STAGES is checked against the
// recipes. The cap is what lets a Stage_Shop store its stock inline: no owned heap,
// so a Map full of shops frees with its nodes.
//
// This is what is left of ADR-0013's **deck**, and the shrink is the point (issue
// #137). The deck was the *entire* ITEM_ROSTER_SIZE roster, sized that way because
// a Port's draw-down persisted across every visit in the run and so had a whole run
// to chew through it. Walked-once encounters (#131) killed that: one visit reaches
// SHOP_SHELF_SIZE cards plus one per purchase, and the purse caps purchases in the
// low teens, so ~37 of those 50 cards were baked into every shop on every map and
// could never be looked at. A shop's stock is now what a shop actually has.
//
// Must stay >= SHOP_SHELF_SIZE so the deepest pool can fill a shelf.
SHOP_STOCK_MAX :: 12

// Shop_Item is one purchasable card in a Shop stage: the roster `fitting` on
// offer and its `cost` in treasure. Cost is stored as a plain int, priced once at
// generation from the item's Tier (ship.ship_item_cost) — tier itself doesn't
// ride along because nothing past pricing reads it, and a bare Fitting is what
// the Refit ultimately places. Buying deducts cost from the ship's hold
// (ship_treasure / ship_stow_treasure, ADR-0020) and opens a Refit to place the
// fitting.
Shop_Item :: struct {
	fitting: ship.Fitting,
	cost:    int,
}

// Stage_Fight is a full battle against a baked opponent, resolved via
// core/combat's phased-round Battle (ADR-0006) — this package hands off to
// combat.combat_battle_create rather than reimplementing combat. Victory
// completes the stage, Leave Combat halts it, and sinking ends the run outright
// (permadeath), which is the whole of why [Fight, Reward] needs no authored gate.
// The opponent is baked at generation from two independent axes (#135): one
// archetype drawn from the hostile roster (content.odin's Hostile_Archetype) for
// its loadout and speed, scaled at this node's stakes for its hp, durability and
// offensive output.
Stage_Fight :: struct {
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

// Trade_Stat is the closed set of ship stats a Trade may put on either side of
// its swap (issue #136) — the parameterization that unwelds the axis. Plain data
// naming a stat, never a pointer to a proc that applies it (ADR-0012), so a
// baked Trade stays copyable into a Ghost_Snapshot like every other stage's
// content.
//
// Closed at four because these are the ship stats a trade can move and have the
// move *mean* something. **Speed is deliberately absent** (ADR-0020, #180): Speed
// is a derived read-out of a ship's weight now, not a stored stat, so a Trade
// cannot pay it out of a field or bank it into one — a Speed axis has no home. It
// returns later as fittings that modify Speed, traded as fittings, not raw stats.
// **Cargo capacity is likewise absent**: ship_cargo_capacity is structural, so
// both halves of a cargo-capacity trade would be no-ops. Treasure carries
// "stat-for-cargo" — the resource a Shop spends and a Reward grants (#132), which
// #143 made *be* the cargo in the holds (ship_treasure).
Trade_Stat :: enum {
	HP,
	Max_HP,
	Durability,
	Treasure,
}

// Trade_Term is one side of a trade: which stat moves, and by how much. `amount`
// is always the positive magnitude — which direction it moves is the term's
// position in Stage_Trade (gain or cost), not a sign — so a term can never
// contradict the side it sits on by carrying a negative.
Trade_Term :: struct {
	stat:   Trade_Stat,
	amount: int,
}

// Stage_Trade is a permanent stat-for-stat trade-off, baked from one roster entry
// (content.odin's Trade_Axis) at generation. Accepting completes the stage,
// rejecting halts it.
//
// The +Durability/-Speed axis this used to weld into its two field *names* is now
// just one roster entry among several (Braced Bulkheads); what stays fixed is the
// shape — every trade gains exactly one stat and costs exactly one stat. Both
// magnitudes are stakes-scaled off the same zone (run_trade_swing), so a Deep
// trade is a bigger swing on both sides. `name` is the authored entry's name,
// carried so presentation can say which bargain this is without reverse-looking-up
// the roster from a stat pair (two entries could share one).
Stage_Trade :: struct {
	name: string,
	gain: Trade_Term,
	cost: Trade_Term,
}

// Stage_Shop sells from a seed-baked stock, each card priced by tier
// (run_bake_shop), against the ship's starting treasure. Leaving completes the
// stage — a shop cannot be failed, so Shop is the one primitive with no halt. It is
// its own primitive rather than Offer-with-a-price precisely so the Item Offer can
// be redesigned later without dragging Shop along.
//
// Shop is the one **revealing** primitive (run_stage_kind_reveals): an encounter
// that *opens* with one is visible on the map before arrival (ADR-0016). That is
// what makes a Port just the [Shop] recipe, and a merchant vessel at sea — which
// puts a stage in front of its Shop — a hidden encounter that happens to carry one:
// same primitive, placed differently, and stocked differently because the recipe
// names its pool (Stage_Spec.stock, issue #137).
//
// `count` is how many cards this shop's pool actually stocked and `stock` is
// fixed-size to SHOP_STOCK_MAX — the same count-plus-inline-array shape as Encounter,
// and for the same reason: no owned heap. Slots from count to the cap are unused. A
// shop whose count is small enough can be **bought out** within a single visit, which
// is the whole mechanical difference between a merchant's hold and a Port's warehouse.
Stage_Shop :: struct {
	stock: [SHOP_STOCK_MAX]Shop_Item,
	count: int,
}

// Stage_Reward grants treasure outright and always completes — the "then loot it"
// half of [Fight, Reward], and the reason a halt has to keep what earlier stages
// already granted.
//
// **Treasure, and only treasure** (issue #132). Not items: that is Offer's job, and
// a Reward that could grant one would leave [Fight, Reward] and [Fight, Offer]
// differing only in whether the captain got to choose — a distinction Offer already
// expresses. Not cargo-as-a-separate-thing either: money takes space, so treasure
// and cargo are one thing rather than two candidates; #143 is where the purse
// becomes literal slots, and Reward ships against the plain int until then.
//
// `treasure` is baked at generation from the node's own Scaling_Site
// (run_reward_treasure) — a plain int, so it needs no runtime RNG, holds no
// function pointer, and copies into a Ghost_Snapshot like every other stage's
// content (ADR-0012).
//
// Reward is a **boon**: it has nothing to decline, so it is the one primitive that
// resolves without stopping for the captain (sim_enter_stage returns .Completed for
// it outright). That is why a bare [Reward] — drifting salvage, free treasure — is
// a coherent recipe rather than an encounter with no interaction: the interaction
// is arriving.
Stage_Reward :: struct {
	treasure: int,
}

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

// Stage_Spec is one authored step of a Recipe: a primitive, plus whatever that
// primitive needs *authored* rather than drawn. It is the alphabet a recipe is
// written in — Stage_Kind is the letter, this is the letter as written down.
//
// This widens ADR-0014's "a recipe is a name plus an order over primitives"
// (issue #137). A bare Stage_Kind could not express the one thing a Shop needs
// from its recipe: **which stock pool it sells from**. Every other primitive draws
// its content freely — a Fight's archetype, a Trade's axis and an Offer's items are
// all sampled off the map RNG with no regard to the recipe carrying them — but a
// Port and a merchant vessel must not stock alike (Stock_Pool says why at length),
// and nothing about a Shop stage on its own knows which of the two it is in.
//
// `stock` is a **Maybe**, and the Maybe is doing real work: it is set on a Shop spec
// and nil on every other, so a pool is explicitly absent rather than accidentally
// the zero pool. `{kind = .Fight}` cannot be read as "a Fight that sells a chandlery's
// wares"; it carries no pool at all. run_bake_stage asserts both directions, and
// every_stage_spec_authors_a_pool_iff_it_is_a_shop checks the catalog against it.
//
// It stays deliberately narrow. This is *not* the orthogonal trait-modifier layer
// ADR-0014 ruled out, and it is not an invitation for every primitive to grow an
// authoring knob: a field belongs here only when a primitive genuinely cannot draw
// the thing for itself, which so far is one field on one primitive.
Stage_Spec :: struct {
	kind:  Stage_Kind,
	stock: Maybe(Stock_Pool),
}

// Recipe is the authored unit of encounter content (ADR-0014): a name plus the
// ordered stages it is written as. `Sea Battle = [Fight, Reward]`. Generation picks
// a whole recipe and bakes each stage's content from that stage's own roster — it
// never composes a stage list, because mix-and-match is a developer authoring tool,
// not a runtime generative system.
//
// `stages` holds authored specs, not baked Stages: a recipe is static authored data
// reused by every node that draws it, while the content is per-node. Which bucket a
// recipe belongs to is **derived** from its stage count and never authored — there is
// deliberately no bucket field, so a recipe cannot be filed in the wrong bucket
// because it isn't filed at all.
Recipe :: struct {
	name:   string,
	stages: []Stage_Spec,
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
	for spec, i in r.stages {
		e.stages[i] = run_bake_stage(spec, site, gen)
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

// run_encounter_opening returns the stage an encounter **opens** with — stage 0,
// regardless of where the cursor has walked to — or ok=false for an encounter with
// no stages at all (which generation never bakes; run_encounter_from_recipe asserts
// a recipe authors at least one).
//
// The opening stage is what an encounter *is* from the outside, and it is asked for
// from two directions that must never diverge: whether the encounter reveals itself
// on the map (run_encounter_reveals, below) and what a revealed or walked node is
// **labelled** as (cmd/game's node_appearance). Both are properties of the whole
// encounter as seen from the map, not of the step the captain happens to be on, so
// both ask this rather than run_encounter_current — which answers a different
// question (where is the walk now) and only coincided with this one while the cursor
// sat at 0.
run_encounter_opening :: proc(e: Encounter) -> (stage: Stage, ok: bool) {
	if e.count == 0 {
		return nil, false
	}
	return e.stages[0], true
}

// run_encounter_reveals reports whether an encounter shows itself on the map
// before arrival: true iff its **first** stage reveals (ADR-0016). This is what
// replaces asking a node whether it is a Port — visibility is a question asked of
// the stage list, never a node fact, so a Port is just the [Shop] recipe and a
// merchant vessel at sea is a hidden encounter carrying a Shop stage.
//
// First stage, not any stage. A revealed node is one the captain can **route to**,
// and what you would be routing to is what the encounter opens with; a Shop behind
// a fight is a windfall you meet, not a market you plan for (#154). Scanning the
// whole list instead revealed every merchant carrying a Shop anywhere, which made
// a *visible* Battle marker a tell that a market waited behind the fight.
run_encounter_reveals :: proc(e: Encounter) -> bool {
	opening, ok := run_encounter_opening(e)
	if !ok {
		return false
	}
	return run_stage_kind_reveals(run_stage_kind(opening))
}
