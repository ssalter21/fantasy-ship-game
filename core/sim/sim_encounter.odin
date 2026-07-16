package sim

import "../combat"
import "../run"
import "../ship"

// The generic encounter stage walk (issue #131, ADR-0014) — the Sim's single path
// through *any* encounter, and the file that replaces the per-kind sim_item_offer.odin
// and sim_shop.odin.
//
// An Encounter is an ordered stage list plus a cursor (core/run/stage.odin), and
// walking it is the whole of the Sim's encounter control flow: enter the stage under
// the cursor, let that stage resolve to completed or halted, advance or stop. There
// is no phase graph per encounter kind, because there are no encounter kinds — a
// recipe's stages are drawn from one closed primitive alphabet, and the walk asks
// each primitive what it needs rather than knowing in advance what shape the
// encounter has.
//
// What that buys, concretely: adding a stage primitive means adding an arm to the
// two switches below and (if it presents an option list) nothing else. Adding an
// *encounter* — the common case — means adding a catalog entry and touching this
// file not at all.
//
// The four procs are the whole walk:
//   - sim_walk_encounter  — present the stage under the cursor, or finish the encounter
//   - sim_enter_stage     — start one stage: park in its phase, or resolve it outright
//   - sim_advance_stage   — record a stage's outcome and move the cursor off it
//   - sim_process_option_choice — answer the one decision two primitives share
//
// Everything that resolves a stage — a battle ending (sim_battle.odin), an option
// chosen here, a Refit finishing (sim_refit.odin) — comes back through
// sim_walk_encounter rather than reaching for a travel choice itself. That is why
// "what happens after this stage" has exactly one answer: whatever the cursor is on.

// Stock_Position identifies a card by its position in a Shop stage's baked stock
// (ADR-0011: distinct from a plain int so a stock position can't be silently swapped
// with an Option_Index — the shelf-slot index into the *same* shop — or any other
// index). It indexes run.Stage_Shop.stock; the shop the ship is currently in tracks
// its shelf by it (Shop_Visit).
Stock_Position :: distinct int

// Shop_Visit is the working state of the Shop stage under the cursor: `slots` holds
// the stock position currently shown in each shelf slot (nil once the stock behind
// the shelf runs out), `next_draw` is the next stock position to draw when a slot
// refills after a buy, and `purchases` counts the buys made at this shop so far,
// driving the depth surcharge (issue #124, shop_visit_price). `open` is false until
// the cursor lands on a Shop and sim_deal_shop_visit deals its shelf.
//
// A nil slot used to be the "graceful short-deck case, unreachable at the real
// roster size" — a shop's stock was the whole 50-item roster, so nothing could
// empty one. Issue #137 made it **reachable and deliberate**: a shop's stock is its
// pool's authored depth, and a narrow merchant hold (six cards against a shelf of
// five) can be bought out inside one visit. Running a shop dry is now content, not
// a defensive branch.
//
// It is **one visit, not a row per node** — the change that retires ADR-0013's
// cross-visit persistence (issue #131). The old port_shelves array kept every Port's
// shelf, cursor, and purchase count alive for the rest of the voyage so a revisit could
// resume it; under the generic walk an encounter is walked once and marked resolved,
// so no arrival can ever read that state a second time. Rather than keep a per-node
// array that nothing could reach, the state shrinks to the shop actually being stood
// in, and sim_advance_stage discards it as the cursor leaves. A recipe holding two
// Shop stages therefore deals each a fresh shelf, which is the honest reading of two
// shops.
//
// The multi-buy loop *within* a visit is untouched: buying refills the slot in place
// and the Refit's finish re-enters this same stage. (#137 owns the stock-pool rework,
// re-examining whether the deck-plus-window shape still earns its keep, and recording
// the ADR-0013 supersession.)
Shop_Visit :: struct {
	slots:     [run.SHOP_SHELF_SIZE]Maybe(Stock_Position),
	next_draw: Stock_Position,
	purchases: int,
	open:      bool,
}

// SHOP_DEPTH_SURCHARGE_STEP is the per-purchase shop price surcharge (issue #124,
// ADR-0013): each successive buy at a given shop costs this much more than the last,
// so digging one shop deep is expensive and the player is pushed to check shop
// against shop rather than draining the nearest one. Additive and depth-linear (see
// shop_visit_price), with the first buy at the plain tier price. A single placeholder
// constant, isolated here from the deck/refill logic so it can move in playtest
// without touching it — the leading shape is not committed (ADR-0012's
// placeholder-economy convention).
SHOP_DEPTH_SURCHARGE_STEP :: 5

// shop_visit_price is the treasure a shelf card costs given how many items have
// already been bought at this shop (issue #124): its tier base plus the depth
// surcharge, `base + SHOP_DEPTH_SURCHARGE_STEP × purchases`. The one place the
// surcharge is applied — the shelf's presented prices and the charge at buy both read
// it off the staged option, so the two cannot disagree. purchases is 0 on the first
// buy, so it charges the plain tier base.
shop_visit_price :: proc(base_cost: int, purchases: int) -> int {
	return base_cost + SHOP_DEPTH_SURCHARGE_STEP * purchases
}

// shop_visit_draw_next hands out the next undrawn stock position and advances the
// cursor, or nil once the shop's stock is exhausted (issue #123) — the one place the
// draw-or-exhaust decision lives, shared by the opening deal and each buy's refill.
shop_visit_draw_next :: proc(visit: ^Shop_Visit, stock_count: int) -> Maybe(Stock_Position) {
	if int(visit.next_draw) >= stock_count {
		return nil
	}
	pos := visit.next_draw
	visit.next_draw += 1
	return pos
}

// sim_current_encounter returns a mutable pointer to the encounter held by the node
// the ship is standing at, or ok=false for a node that holds none (Start and Goal —
// landmarks by graph position, which no stage list can express). The pointer aims
// into the Sim's own private voyage_map, so advancing the cursor through it moves the
// real encounter; public_nodes is a separate masked copy and is unaffected.
sim_current_encounter :: proc(sim: ^Sim) -> (^run.Encounter, bool) {
	encounter, ok := &sim.voyage_map.nodes[sim.current].encounter.?
	return encounter, ok
}

// sim_current_site is the stakes of the node the ship is standing at (ADR-0014) —
// what the stage under the cursor was baked against, and what its resolution stamps
// onto its Ghost_Snapshot. A node holding an encounter always has a zone, so a
// missing one is a generation bug rather than a case to handle.
//
// Every stage that resolves at arrival needs this and none of them needs it
// differently, so it is asked here once rather than reassembled from node.zone and
// node.depth at each primitive's arm.
sim_current_site :: proc(sim: ^Sim) -> run.Scaling_Site {
	node := sim.voyage_map.nodes[sim.current]
	zone, has_zone := node.zone.?
	assert(has_zone, "an Encounter node must have a zone")
	return run.Scaling_Site{zone = zone, depth = node.depth}
}

// sim_walk_encounter presents the stage under the cursor, or finishes the encounter
// if the walk is over — the read half of complete-or-halt, and the single answer to
// "what happens next" that every resolution path routes back through.
//
// It loops rather than presenting one stage, because nothing guarantees a stage stops
// for the captain: one that resolves outright advances the cursor and the next stage is
// entered in the same tick. Reward is that stage (#133) — a boon has nothing to
// decline, so it pays out and the walk carries straight on to whatever follows it,
// which is how [Fight, Reward] resolves the node the moment the battle is won. Every
// other primitive parks. The loop ends the moment a stage parks in a decision phase, or
// the cursor runs off the end.
//
// Finishing marks the node resolved — **node-level, once**, exactly like every other
// encounter (ADR-0014). This is where Port repeatability dies: a Port is walked and
// resolved like anything else, because complete-or-halt has no revisit semantics and
// a repeatable encounter would be the only primitive with a lifecycle of its own.
// Halting finishes the walk too — voyage_encounter_resolve_stage jumps the cursor to the
// end — so a captain who flees a [Fight, Reward] never reaches the loot, with no
// authored gate saying so.
//
// Finishing is also where the node's Ghost_Snapshot is captured (issue #162,
// ADR-0008 as amended): a ghost is an opponent — the build a captain left this node
// with — so it is one per encounter, taken where the walk ends and the ship is
// whatever the whole node made of it. That the emit and `resolved` are set in the
// same breath is the point: Event_Encounter_Resolved's "resolved" and the Sim's are
// now one fact, where the retired per-apply-proc emits fired at three moments when
// this flag was still false. A **halt** emits — the cursor jumps to the end and
// lands here, and a fled ship is a real ship a lobby can serve. A **sinking** does
// not: the walk stops dead in sim_process_battle_round, the node is never resolved,
// and this branch is never reached (Event_Voyage_Ended already marks the death).
// Landmarks emit nothing — !has_encounter returns above, before the loop.
sim_walk_encounter :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	encounter, has_encounter := sim_current_encounter(sim)
	if !has_encounter {
		sim.phase = .Awaiting_Travel_Choice
		return
	}

	for {
		stage, walking := run.voyage_encounter_current(encounter^)
		if !walking {
			sim.resolved[sim.current] = true
			sim_emit_encounter_resolved(sim, events)
			sim.phase = .Awaiting_Travel_Choice
			return
		}

		// Where the cursor is, said out loud (issue #139) — the one thing about the walk
		// presentation cannot read off the Encounter it was handed at arrival. Emitted
		// here rather than in sim_enter_stage's arms so it is one site for all five
		// primitives, and *before* the stage presents, so "stage 2 of 3" is on screen by
		// the time its decision is.
		append(events, Event(Event_Stage_Entered{
			kind  = run.voyage_stage_kind(stage),
			index = encounter.cursor,
			count = encounter.count,
		}))

		outcome, resolved := sim_enter_stage(sim, stage, events).?
		if !resolved {
			return // the stage is awaiting a captain decision; answering it resumes the walk
		}
		sim_advance_stage(sim, outcome, events)
	}
}

// sim_enter_stage starts the stage under the cursor: it presents whatever the
// primitive shows and parks the Sim in the phase that primitive's decision needs.
// Returns that stage's outcome when it resolves with nothing to ask the captain, or
// nil when it has parked and the walk must wait — the Maybe *is* the "does this stage
// stop for the player" question, asked of the primitive instead of assumed.
//
// The switch is exhaustive over the closed primitive set, so a sixth primitive is a
// compile error here rather than a stage the walk silently skips.
sim_enter_stage :: proc(sim: ^Sim, stage: run.Stage, events: ^[dynamic]Event) -> Maybe(run.Stage_Outcome) {
	switch s in stage {
	case run.Stage_Fight:
		// The battle borrows the opponent for as long as it runs, so the stage is
		// copied somewhere with a stable address rather than pointed at through the
		// node's Maybe. Its outcome lands in sim_process_battle_round.
		sim.active_encounter = s
		sim.battle = run.voyage_start_battle(&sim.player, &sim.active_encounter)
		append(events, Event(Event_Ship_Battle_Sighted{opponent = sim.active_encounter.opponent}))
		append(events, Event(Event_Battle_Menu{may_leave = combat.combat_may_leave(&sim.battle, .A)}))
		sim.phase = .Awaiting_Battle_Command
		return nil

	case run.Stage_Offer:
		sim_stage_offer_options(sim, s)
		append(events, Event(Event_Options_Presented{options = sim.stage_options}))
		sim.phase = .Awaiting_Option_Choice
		return nil

	case run.Stage_Shop:
		// Deal the shelf only on the cursor's arrival: a Refit's finish re-enters this
		// same stage to re-present the refilled shelf, and must resume the visit rather
		// than deal over it. sim_advance_stage clears `open` as the cursor leaves, so
		// the next Shop reached always deals fresh.
		if !sim.shop_visit.open {
			sim_deal_shop_visit(&sim.shop_visit, s)
		}
		sim_stage_shop_options(sim, s)
		append(events, Event(Event_Options_Presented{options = sim.stage_options}))
		sim.phase = .Awaiting_Option_Choice
		return nil

	case run.Stage_Trade:
		// The bargain is staged here because the answer arrives a tick later, so the
		// stage's baked content has to outlive the entry. can_accept is measured now,
		// against the ship as it stands.
		sim.active_trade = s
		append(events, Event(Event_Trade_Presented{
			trade      = sim.active_trade,
			can_accept = run.voyage_trade_can_accept(&sim.player, sim.active_trade),
		}))
		sim.phase = .Awaiting_Trade_Choice
		return nil

	case run.Stage_Reward:
		// The one primitive that parks nowhere (#132, #133): a boon has nothing to
		// decline, so it pays out and hands back .Completed in the same breath, and
		// sim_walk_encounter's loop carries straight on to whatever follows it. This is
		// the case that loop was built for — every other primitive stops for a decision.
		//
		// Event_Ship_Updated is how presentation learns the purse moved (ADR-0001 — it
		// learns nothing except through Events), and it is the *only* event a payout
		// owes: the node's ghost is captured once, where the walk ends, so a Reward
		// mid-recipe no longer emits one of its own (issue #162). Same as an accepted
		// Trade, the other stage that grants on resolution.
		run.voyage_apply_reward(&sim.player, s)
		append(events, Event(Event_Ship_Updated{ship = sim.player}))
		return .Completed
	}
	unreachable()
}

// sim_advance_stage records the outcome of the stage under the cursor and moves the
// cursor off it, discarding that stage's working state.
//
// It deliberately does **not** present what comes next — sim_walk_encounter does, once
// the caller is ready for it. That split is what the multi-buy loop and an Offer's
// pick are both built out of: a pick advances the cursor and *then* opens a Refit, so
// the Refit's finish walks on to the next stage; a buy opens a Refit without
// advancing, so the same finish re-enters the shop. Which of those happens is read
// off the cursor at that point, which is why neither needs a remembered origin.
//
// A **halt** is announced on the way through (issue #139); a completion is not. This is
// the only place both facts are in hand — voyage_encounter_resolve_stage takes the outcome
// and the cursor still names the stage it applies to — and the asymmetry is
// Event_Encounter_Halted's, not this proc's: a completion shows itself by what happens
// next, a halt is the outcome with nothing to show.
sim_advance_stage :: proc(sim: ^Sim, outcome: run.Stage_Outcome, events: ^[dynamic]Event) {
	encounter, has_encounter := sim_current_encounter(sim)
	assert(has_encounter, "resolved a stage at a node that holds no encounter")

	if outcome == .Halted {
		stage, walking := run.voyage_encounter_current(encounter^)
		assert(walking, "halted a stage on an encounter whose walk already finished")
		append(events, Event(Event_Encounter_Halted{
			at    = run.voyage_stage_kind(stage),
			index = encounter.cursor,
			count = encounter.count,
		}))
	}

	run.voyage_encounter_resolve_stage(encounter, outcome)
	sim.shop_visit = {} // the cursor is leaving; a stage's working state dies with it
}

// sim_process_option_choice applies a submitted Command_Choose_Option — the one
// decision an Offer and a Shop share (issue #131), and the whole of what
// sim_item_offer.odin and sim_shop.odin used to do apart.
//
// Taking an option is uniform: bounds-check it, charge it if it carries a price, and
// open a Refit to place it (the acquisition channel owns resolving its own stage, so
// the Refit stays a pure reusable sub-mode). What differs is what taking or declining
// means to the *stage*, which is the primitive's business (ADR-0014) and is asked of
// it below rather than baked into the phase.
sim_process_option_choice :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	assert(has_pending, "sim_process_option_choice called without a pending command")
	cmd, is_choice := pending.(Command_Choose_Option)
	assert(is_choice, "sim_process_option_choice called without a pending Command_Choose_Option")
	sim.pending_command = nil

	encounter, has_encounter := sim_current_encounter(sim)
	assert(has_encounter, "an option choice was answered at a node that holds no encounter")
	stage, walking := run.voyage_encounter_current(encounter^)
	assert(walking, "an option choice was answered after the encounter's walk had finished")

	selection, took := cmd.selection.?
	if !took {
		sim_advance_stage(sim, sim_stage_decline_outcome(stage), events)
		sim_walk_encounter(sim, events)
		return
	}

	assert(selection >= 0 && int(selection) < len(sim.stage_options), "Command_Choose_Option selection out of range")
	option, on_offer := sim.stage_options[selection].?
	assert(on_offer, "Command_Choose_Option selected a position with no option on it")

	// A priced option is paid for before it changes hands; a free one has no price to
	// check, so it skips the whole question rather than comparing against a zero cost.
	if cost, priced := option.cost.?; priced {
		if cost > ship.ship_treasure(sim.player) {
			// ADR-0012's "an unaffordable item cannot be bought": nothing is spent, no
			// Refit opens, and the stage stays open for another choice.
			append(events, Event(Event_Purchase_Rejected{option = option}))
			return
		}
		// Spending comes out of the hold now (ADR-0020): re-stow the purse at its
		// reduced total. The affordability check above guarantees purse >= cost.
		ship.ship_stow_treasure(sim.player.layout, ship.ship_treasure(sim.player) - cost)
		// Broadcast the spent purse before the Refit opens, so the deduction is visible
		// even if the buyer discards the item in the Refit without installing it (no
		// refund — no inventory, ADR-0012). The Refit's own install emits another.
		append(events, Event(Event_Ship_Updated{ship = sim.player}))
	}

	switch s in stage {
	case run.Stage_Offer:
		// Picking completes the Offer. The cursor moves off it now, so the Refit's
		// finish resumes the walk at whatever comes next.
		sim_advance_stage(sim, .Completed, events)

	case run.Stage_Shop:
		// A buy does *not* resolve the Shop: the cursor stays put, so the Refit's finish
		// re-enters this same stage and re-presents it refilled — the multi-buy loop,
		// now a property of where the cursor is rather than of a remembered origin.
		sim.shop_visit.purchases += 1 // this shop is one item deeper; the next buy here costs more
		sim.shop_visit.slots[selection] = shop_visit_draw_next(&sim.shop_visit, s.count)

	case run.Stage_Fight, run.Stage_Trade, run.Stage_Reward:
		panic("an option was taken from a stage that presents no option list")
	}

	sim_open_refit(sim, option.fitting, events)
}

// sim_stage_decline_outcome is what declining an option list does to the encounter —
// the primitive's own definition of completion (ADR-0014), asked of the stage rather
// than assumed by the phase they share. Skipping an Offer **halts**, so a captain who
// wants none of the items gets nothing downstream of it either; leaving a Shop
// **completes**, because a shop cannot be failed — Shop is the one primitive with no
// halt.
//
// Exhaustive rather than "halt unless Shop": a sixth option-list primitive must state
// its own answer here, not inherit one by falling through.
sim_stage_decline_outcome :: proc(stage: run.Stage) -> run.Stage_Outcome {
	switch _ in stage {
	case run.Stage_Offer:
		return .Halted
	case run.Stage_Shop:
		return .Completed
	case run.Stage_Fight, run.Stage_Trade, run.Stage_Reward:
		panic("declined a stage that presents no option list")
	}
	unreachable()
}

// sim_stage_offer_options stages an Offer's items as the presented option list: the
// distinct roster items it was baked with (ADR-0012), each free — an Offer's cost is
// the halt it takes to refuse, not treasure. Slots past the Offer's own count stay
// nil, since the shared list is as wide as the widest stage.
sim_stage_offer_options :: proc(sim: ^Sim, offer: run.Stage_Offer) {
	sim.stage_options = {}
	for fitting, i in offer.options {
		sim.stage_options[i] = Stage_Option{fitting = fitting}
	}
}

// sim_stage_shop_options stages the visit's live shelf as the presented option list,
// each card at its depth-surcharged price (issue #124) so the price shown is exactly
// the price charged. Called on every entry to the stage — the cursor's arrival and
// each return from a buy's Refit — so it always reflects what has already been drawn
// and bought. A slot past the deck's tail has no card and stays nil.
sim_stage_shop_options :: proc(sim: ^Sim, shop: run.Stage_Shop) {
	sim.stage_options = {}
	for slot, i in sim.shop_visit.slots {
		pos, filled := slot.?
		if !filled {
			continue
		}
		card := shop.stock[pos]
		sim.stage_options[i] = Stage_Option {
			fitting = card.fitting,
			cost    = shop_visit_price(card.cost, sim.shop_visit.purchases),
		}
	}
}

// sim_deal_shop_visit lays out a shop's opening shelf (issue #123): the top
// SHOP_SHELF_SIZE cards of its stock, one per slot, with next_draw left pointing at
// the first still-undrawn card. A shop stocking fewer cards than the shelf shows
// leaves the tail slots nil — reachable since #137 gave pools an authored depth,
// though no pool authors one that shallow today. Called once per Shop stage, as the
// cursor lands on it.
sim_deal_shop_visit :: proc(visit: ^Shop_Visit, shop: run.Stage_Shop) {
	for i in 0 ..< run.SHOP_SHELF_SIZE {
		visit.slots[i] = shop_visit_draw_next(visit, shop.count)
	}
	visit.open = true
}
