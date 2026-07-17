package voyage

import "../ship"
import "core:math/rand"

// The encounter stage model (ADR-0014). An Encounter is an ordered list of
// Stages plus a cursor; a Stage is one of five closed primitives carrying the
// content it was baked with; a Recipe is the named, authored stage set
// generation picks whole. This file owns that model and the per-stage content
// types. The Zone/Node/Map graph an Encounter hangs off lives in voyage.odin,
// generation in generation.odin, per-stage content in content.odin, and
// arrival-time resolution in encounter.odin.

// ENCOUNTER_MAX_STAGES caps how many stages one encounter holds — the deepest
// rung of ADR-0014's zone -> stage-count mapping (Coastal 1, Open Sea 2, The
// Deep 3). The cap lets an Encounter store its stages inline as a fixed-size
// array: no owned heap, so voyage_map_destroy needs no per-encounter cleanup
// beyond the opponent layout a Fight allocates.
ENCOUNTER_MAX_STAGES :: 3

// Stage_Kind is the closed primitive alphabet (ADR-0014): the authoring
// vocabulary a Recipe names its stages in, before generation bakes each one's
// content into a Stage. Deliberately closed — adding an encounter must never
// require adding a primitive, so a sixth value here is an ADR-sized decision,
// not a content change. The primitive is also the trait: variance comes from
// each stage's own content roster, not an orthogonal modifier layer.
Stage_Kind :: enum {
	Fight,
	Offer,
	Trade,
	Shop,
	Reward,
}

// ITEM_OFFER_OPTION_COUNT is how many distinct roster items an Offer stage
// presents (ADR-0012) — the player picks one to place, or skips. Fixed rather
// than per-node, which keeps an Offer's options a small fixed array; must be
// <= ship.ITEM_ROSTER_SIZE so the pool can supply that many distinct items.
ITEM_OFFER_OPTION_COUNT :: 3

// SHOP_SHELF_SIZE is how many cards a Shop stage shows at once — the window onto
// the top of its stock (ADR-0013). Only how much of the stock is visible/buyable
// at any moment; buying refills the slot from the stock behind it.
//
// The window earns its place through the depth surcharge (#124): each successive
// buy at one shop costs more, which only means something if buying reveals
// something new. Show the whole stock at once and the surcharge degenerates into
// a flat tax on a menu already read; behind a window it is the price of digging
// — spend a little to see what else is in the hold, which is the decision the
// shop is for.
//
// A constant rather than a per-pool knob: how much of any shop you take in at a
// glance is a property of looking at shops, not of which shop it is. What varies
// per pool is what is behind the window (Stock.depth).
SHOP_SHELF_SIZE :: 5

// SHOP_STOCK_MAX caps how many cards one Shop stage holds — the deepest hold any
// authored pool asks for (content.odin's stock_pools), checked against that
// table by test the way ENCOUNTER_MAX_STAGES is checked against the recipes. The
// cap lets a Stage_Shop store its stock inline: no owned heap, so a Map full of
// shops frees with its nodes. Must stay >= SHOP_SHELF_SIZE so the deepest pool
// can fill a shelf.
SHOP_STOCK_MAX :: 12

// Stage_Option is one line of an option-list stage's presented list: the `fitting` on
// offer and what it `cost`s in cargo, nil when the option is free. A nil cost is not a
// magic zero — it says there is no price to check, so voyage_option_can_afford answers
// yes outright rather than comparing against 0.
//
// The one priced shape: voyage_shop_option and voyage_offer_option are the only two
// makers, and it crosses the Sim's Event seam and into presentation unchanged, so the
// price a shelf card shows is the price its buy charges by construction. A `cost` here
// is always the **full** price (voyage_shop_price), never a base awaiting a surcharge.
//
// Not a Stage variant, despite the family name — it is what an option-list stage
// presents, like Stage_Kind is which primitive a stage is and Stage_Outcome is how one
// resolved.
Stage_Option :: struct {
	fitting: ship.Fitting,
	cost:    Maybe(int),
}

// Stage_Fight is a full battle against a baked opponent, resolved via
// core/combat's phased-round Battle (ADR-0006) — this package hands off to
// combat.combat_battle_create rather than reimplementing combat. Victory
// completes the stage, Break Off halts it, and sinking ends the voyage outright
// (permadeath), which is why [Fight, Reward] needs no authored gate. The
// opponent is baked at generation from two independent axes: an archetype drawn
// from the hostile roster for its loadout — from whose weight its Speed derives
// (ADR-0020) — scaled at this node's stakes for its hull, durability and fire.
Stage_Fight :: struct {
	opponent: ship.Ship,
}

// Stage_Offer presents a few distinct roster items to place by hand (ADR-0012).
// `options` are the concrete items on offer, drawn from the roster pool and
// stakes-scaled at generation (voyage_item_offer_options), so an Offer carries
// its items as baked content the way a Fight carries its opponent. Picking one
// completes the stage and opens a Refit to place or swap it; skipping halts. A
// fixed-size array — no owned heap.
Stage_Offer :: struct {
	options: [ITEM_OFFER_OPTION_COUNT]ship.Fitting,
}

// Trade_Stat is the closed set of ship stats a Trade may put on either side of
// its swap. Plain data naming a stat, never a pointer to a proc that applies it
// (ADR-0012), so a baked Trade stays copyable into a Ghost_Snapshot like every
// other stage's content.
//
// Closed at four: these are the stats a trade can move and have the move mean
// something. Speed is absent (ADR-0020) — it is a derived read-out of a ship's
// weight, not a stored stat, so a Trade cannot pay it out of a field or bank it
// into one. Cargo capacity is absent too: ship_cargo_capacity is structural, so
// both halves of a cargo-capacity trade would be no-ops. Cargo itself carries
// the stat-for-cargo axis — the resource a Shop spends and a Reward grants.
Trade_Stat :: enum {
	Hull,
	Max_Hull,
	Durability,
	Cargo,
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
// rejecting halts it. The shape is fixed: every trade gains exactly one stat and
// costs exactly one, both magnitudes stakes-scaled off the same zone
// (voyage_trade_swing), so a Deep trade is a bigger swing on both sides. `name`
// is the authored entry's name, carried so presentation can say which bargain
// this is without reverse-looking-up the roster from a stat pair (two entries
// could share one).
Stage_Trade :: struct {
	name: string,
	gain: Trade_Term,
	cost: Trade_Term,
}

// Stage_Shop sells from a seed-baked stock (voyage_bake_shop) against the ship's cargo.
// Leaving completes the stage — a shop cannot be failed, so Shop is the one primitive
// with no halt. Its own primitive rather than Offer-with-a-price, so the Item Offer can
// be redesigned later without dragging Shop along.
//
// Shop is the one **revealing** primitive (voyage_stage_kind_reveals): an
// encounter that *opens* with one is visible on the map before arrival
// (ADR-0016). That is what makes a Port just the [Shop] recipe, and a merchant
// vessel at sea — which puts a stage in front of its Shop — a hidden encounter
// that happens to carry one: same primitive, placed differently, and stocked
// differently because the recipe names its pool (Stage_Spec.stock).
//
// `count` is how many cards this shop's pool stocked; `stock` is fixed-size to
// SHOP_STOCK_MAX — the same count-plus-inline-array shape as Encounter, and for
// the same reason: no owned heap. A shop whose count is small enough can be
// **bought out** in a single visit, the mechanical difference between a
// merchant's hold and a Port's warehouse.
//
// A card is a bare ship.Roster_Item — the item and the Tier it was authored at, carrying
// no price. A card's price depends on how deep into *this visit* the buyer already is
// (voyage_shop_price), which generation cannot know, so the stock keeps the tier and the
// price is assembled once, at presentation, where the whole of it is knowable.
Stage_Shop :: struct {
	stock: [SHOP_STOCK_MAX]ship.Roster_Item,
	count: int,
}

// Stage_Reward grants cargo outright and always completes — the "then loot it"
// half of [Fight, Reward], and the reason a halt has to keep what earlier stages
// already granted.
//
// **Cargo, and only cargo.** Not items: that is Offer's job, and a Reward that
// could grant one would leave [Fight, Reward] and [Fight, Offer] differing only
// in whether the captain got to choose — a distinction Offer already expresses.
// `cargo` is baked at generation from the node's own Scaling_Site
// (voyage_reward_cargo) — a plain int, so it needs no runtime RNG, holds no
// function pointer, and copies into a Ghost_Snapshot like every other stage's
// content (ADR-0012).
//
// Reward is a **boon**: it has nothing to decline, so it is the one primitive
// that resolves without stopping for the captain (sim_enter_stage returns
// .Completed for it outright). That is why a bare [Reward] is a coherent recipe
// rather than an encounter with no interaction: the interaction is arriving.
Stage_Reward :: struct {
	cargo: int,
}

// Stage is one step of an encounter: a primitive plus the content it was baked
// with. A closed union (ADR-0014's closed alphabet) — every consumer switches
// exhaustively, so a sixth primitive is a compile error at each site rather than
// a silently-skipped case. The nil state means "no stage here": it fills an
// Encounter's unused array slots past its stage count, and is never a stage the
// cursor visits.
Stage :: union {
	Stage_Fight,
	Stage_Offer,
	Stage_Trade,
	Stage_Shop,
	Stage_Reward,
}

// voyage_stage_kind reports which primitive a baked Stage is — the inverse of
// voyage_bake_stage, mapping content back to the authoring alphabet. Consumers
// that need the content itself switch on the Stage directly; this is for the
// ones that only need to ask what kind of step this is (visibility, presentation
// labels, a recipe round-trip).
voyage_stage_kind :: proc(s: Stage) -> Stage_Kind {
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
// won". The primitive that just resolved decides which outcome it hands in
// (Fight completes on victory and halts on Break Off; Reward always completes),
// which is what makes [Fight, Reward] mean the obvious thing with no authoring —
// flee the blockade and the loot stage is never reached.
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
// voyage_map_destroy only has to reach the opponent layout inside a Fight.
// `count` is the authored length — slots from there to the cap are nil — and
// `cursor` is the walk position, voyage_encounter_is_finished once it reaches
// count. A halt finishes the walk by jumping the cursor to count rather than by
// a separate flag, so "is there another stage" has exactly one answer to read.
Encounter :: struct {
	stages: [ENCOUNTER_MAX_STAGES]Stage,
	count:  int,
	cursor: int,
}

// Stage_Spec is one authored step of a Recipe: a primitive, plus whatever that
// primitive needs *authored* rather than drawn. It is the alphabet a recipe is
// written in — Stage_Kind is the letter, this is the letter as written down.
//
// A bare Stage_Kind could not express the one thing a Shop needs from its
// recipe: **which stock pool it sells from**. Every other primitive draws its
// content freely off the map RNG — a Fight's archetype, a Trade's axis, an
// Offer's items — but a Port and a merchant vessel must not stock alike
// (Stock_Pool says why at length), and a Shop stage on its own knows nothing of
// which of the two it is in.
//
// `stock` is a **Maybe** doing real work: set on a Shop spec, nil on every
// other, so a pool is explicitly absent rather than accidentally the zero pool.
// voyage_bake_stage asserts both directions, and
// every_stage_spec_authors_a_pool_iff_it_is_a_shop checks the catalog against it.
//
// It stays deliberately narrow — *not* the orthogonal trait-modifier layer
// ADR-0014 ruled out. A field belongs here only when a primitive genuinely
// cannot draw the thing for itself, which so far is one field on one primitive.
Stage_Spec :: struct {
	kind:  Stage_Kind,
	stock: Maybe(Stock_Pool),
}

// Recipe is the authored unit of encounter content (ADR-0014): a name plus the
// ordered stages it is written as. `Sea Battle = [Fight, Reward]`. Generation
// picks a whole recipe and bakes each stage's content from that stage's own
// roster — it never composes a stage list, because mix-and-match is a developer
// authoring tool, not a runtime generative system.
//
// `stages` holds authored specs, not baked Stages: a recipe is static authored
// data reused by every node that draws it, while the content is per-node. Which
// bucket a recipe belongs to is **derived** from its stage count and never
// authored — there is deliberately no bucket field, so a recipe cannot be filed
// in the wrong bucket because it isn't filed at all.
Recipe :: struct {
	name:   string,
	stages: []Stage_Spec,
}

// voyage_encounter_from_recipe bakes one authored recipe into a node's Encounter:
// each of the recipe's primitives rolls its own content at this node's
// Scaling_Site, in order. Takes `gen` so the stages that sample the roster (an
// Offer's items, a Shop's deck) draw reproducibly from the map generator's RNG —
// nothing rolls on arrival (ADR-0013's no-runtime-RNG property).
voyage_encounter_from_recipe :: proc(r: Recipe, site: Scaling_Site, gen: rand.Generator) -> Encounter {
	assert(len(r.stages) > 0, "a recipe must author at least one stage")
	assert(len(r.stages) <= ENCOUNTER_MAX_STAGES, "a recipe authored more stages than an Encounter can hold")

	e := Encounter{count = len(r.stages)}
	for spec, i in r.stages {
		e.stages[i] = voyage_bake_stage(spec, site, gen)
	}
	return e
}

// voyage_encounter_current returns the stage the cursor is on, or ok=false once
// the walk has finished (the last stage completed, or any stage halted). This is
// the read half of the generic stage walk; voyage_encounter_resolve_stage is the
// write half.
voyage_encounter_current :: proc(e: Encounter) -> (stage: Stage, ok: bool) {
	if voyage_encounter_is_finished(e) {
		return nil, false
	}
	return e.stages[e.cursor], true
}

// voyage_encounter_is_finished reports whether the walk is over — the cursor has
// passed the last stage, either by completing it or because a halt jumped it
// there.
voyage_encounter_is_finished :: proc(e: Encounter) -> bool {
	return e.cursor >= e.count
}

// voyage_encounter_resolve_stage records the outcome of the stage under the
// cursor and moves the encounter on (ADR-0014's complete-or-halt): Completed
// advances to the next stage, Halted ends the encounter where it stands. Returns
// whether a further stage is now pending, so the caller's walk is `for stage in
// ...` rather than a per-primitive phase graph.
//
// Resolving a stage on an already-finished encounter is a driver bug, not a
// runtime rejection — the caller asks voyage_encounter_current first and gets
// ok=false.
voyage_encounter_resolve_stage :: proc(e: ^Encounter, outcome: Stage_Outcome) -> (more: bool) {
	assert(!voyage_encounter_is_finished(e^), "resolved a stage on an encounter whose walk already finished")

	switch outcome {
	case .Completed:
		e.cursor += 1
	case .Halted:
		e.cursor = e.count
	}
	return !voyage_encounter_is_finished(e^)
}

// voyage_stage_kind_reveals reports whether a primitive shows its whole encounter
// on the map before the ship arrives (ADR-0014). Today only Shop reveals: a shop
// you cannot see is a shop you cannot route to, which is the entire point of a
// Port's map presence. Every other primitive stays a surprise until arrival
// (ADR-0009's hiding contract).
voyage_stage_kind_reveals :: proc(kind: Stage_Kind) -> bool {
	return kind == .Shop
}

// voyage_encounter_opening returns the stage an encounter **opens** with — stage
// 0, regardless of where the cursor has walked to — or ok=false for an encounter
// with no stages at all (which generation never bakes; voyage_encounter_from_recipe
// asserts a recipe authors at least one).
//
// The opening stage is what an encounter *is* from the outside — asked both by
// whether the encounter reveals itself (voyage_encounter_reveals) and by what a
// node is **labelled** as (cmd/game's node_appearance). Both are properties of
// the whole encounter, not of the step the cursor is on, so both ask this rather
// than voyage_encounter_current — which answers where the walk is now, and only
// coincided with this while the cursor sat at 0.
voyage_encounter_opening :: proc(e: Encounter) -> (stage: Stage, ok: bool) {
	if e.count == 0 {
		return nil, false
	}
	return e.stages[0], true
}

// voyage_encounter_reveals reports whether an encounter shows itself on the map
// before arrival: true iff its **first** stage reveals (ADR-0016). This is what
// replaces asking a node whether it is a Port — visibility is a question asked of
// the stage list, never a node fact, so a Port is just the [Shop] recipe and a
// merchant vessel at sea is a hidden encounter carrying a Shop stage.
//
// First stage, not any stage: a revealed node is one the captain can **route
// to**, and what you would be routing to is what the encounter opens with. A Shop
// behind a fight is a windfall you meet, not a market you plan for — revealing on
// any stage would make every merchant carrying a Shop visible and turn a Battle
// marker into a tell that a market waited behind the fight.
voyage_encounter_reveals :: proc(e: Encounter) -> bool {
	opening, ok := voyage_encounter_opening(e)
	if !ok {
		return false
	}
	return voyage_stage_kind_reveals(voyage_stage_kind(opening))
}
