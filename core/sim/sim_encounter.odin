package sim

import "../combat"
import "../voyage"
import "../ship"

// The generic encounter stage walk (issue #131, ADR-0014) — the Sim's single path
// through *any* encounter. An Encounter is an ordered stage list plus a cursor
// (core/voyage/stage.odin), and walking it is the whole of the Sim's encounter control
// flow: enter the stage under the cursor, let it resolve to completed or halted, advance
// or stop. There is no phase graph per encounter kind, because there are no encounter
// kinds — a recipe's stages are drawn from one closed primitive alphabet, and the walk
// asks each primitive what it needs rather than knowing the encounter's shape in advance.
// So adding a stage primitive means adding an arm to the two switches below; adding an
// encounter means adding a catalog entry and touching this file not at all.
//
// Everything that resolves a stage — a battle ending (sim_battle.odin), an option chosen
// here, a Refit finishing (sim_refit.odin) — comes back through sim_walk_encounter rather
// than reaching for a travel choice itself, so "what happens after this stage" has exactly
// one answer: whatever the cursor is on.

// Stock_Position indexes a card in a Shop stage's baked stock (voyage.Stage_Shop.stock).
// distinct from a plain int (ADR-0011) so it can't be silently swapped with an
// Option_Index — the shelf-slot index into the *same* shop — or any other index.
Stock_Position :: distinct int

// Shop_Visit is the working state of the Shop stage under the cursor: `slots` holds the
// stock position shown in each shelf slot (nil once the stock behind it runs out),
// `next_draw` is the next stock position to draw when a slot refills after a buy,
// `purchases` counts the buys made here so far (driving the depth surcharge,
// shop_visit_price), and `open` is false until the cursor lands on a Shop and
// sim_deal_shop_visit deals its shelf.
//
// A nil slot is a bought-out or short-decked shelf (issue #137): a shop's stock is its
// pool's authored depth, and a narrow hold can be emptied inside one visit — content, not
// a defensive branch.
//
// The state is one visit, not a row per node: an encounter is walked once and marked
// resolved, so no arrival reads it a second time, and sim_advance_stage discards it as the
// cursor leaves. A recipe holding two Shop stages therefore deals each a fresh shelf.
Shop_Visit :: struct {
	slots:     [voyage.SHOP_SHELF_SIZE]Maybe(Stock_Position),
	next_draw: Stock_Position,
	purchases: int,
	open:      bool,
}

// SHOP_DEPTH_SURCHARGE_STEP is the per-purchase shop price surcharge (issue #124): each
// successive buy at a shop costs this much more than the last (additive and depth-linear,
// see shop_visit_price), so digging one shop deep is expensive and the player is pushed to
// compare shop against shop. A placeholder magnitude, not committed (ADR-0012).
SHOP_DEPTH_SURCHARGE_STEP :: 5

// shop_visit_price is the cargo a shelf card costs: its tier base plus the depth surcharge,
// `base + SHOP_DEPTH_SURCHARGE_STEP × purchases` (issue #124). The one place the surcharge
// is applied — the shelf's presented prices and the charge at buy both read it off the
// staged option, so the two cannot disagree.
shop_visit_price :: proc(base_cost: int, purchases: int) -> int {
	return base_cost + SHOP_DEPTH_SURCHARGE_STEP * purchases
}

// shop_visit_draw_next hands out the next undrawn stock position and advances the cursor,
// or nil once the shop's stock is exhausted — the one place the draw-or-exhaust decision
// lives, shared by the opening deal and each buy's refill.
shop_visit_draw_next :: proc(visit: ^Shop_Visit, stock_count: int) -> Maybe(Stock_Position) {
	if int(visit.next_draw) >= stock_count {
		return nil
	}
	pos := visit.next_draw
	visit.next_draw += 1
	return pos
}

// sim_current_encounter returns a mutable pointer to the encounter held by the node
// the ship is standing at, or ok=false for a node that holds none (Start and Haven —
// landmarks by graph position, which no stage list can express). The pointer aims
// into the Sim's own private voyage_map, so advancing the cursor through it moves the
// real encounter; public_nodes is a separate masked copy and is unaffected.
sim_current_encounter :: proc(sim: ^Sim) -> (^voyage.Encounter, bool) {
	encounter, ok := &sim.voyage_map.nodes[sim.current].encounter.?
	return encounter, ok
}

// sim_current_site is the stakes of the node the ship is standing at (ADR-0014) — what
// the stage under the cursor was baked against, and what its resolution stamps onto its
// Ghost_Snapshot. A node holding an encounter always has a zone, so a missing one is a
// generation bug, not a case to handle. Asked here once rather than reassembled from
// node.zone and node.depth at each primitive's arm.
sim_current_site :: proc(sim: ^Sim) -> voyage.Scaling_Site {
	node := sim.voyage_map.nodes[sim.current]
	zone, has_zone := node.zone.?
	assert(has_zone, "an Encounter node must have a zone")
	return voyage.Scaling_Site{zone = zone, depth = node.depth}
}

// sim_walk_encounter presents the stage under the cursor, or finishes the encounter
// if the walk is over — the read half of complete-or-halt, and the single answer to
// "what happens next" that every resolution path routes back through.
//
// It loops rather than presenting a single stage: nothing guarantees a stage stops for
// the captain — one that resolves outright advances the cursor and the next is entered in
// the same tick (a Reward has nothing to decline, so [Fight, Reward] resolves the node the
// moment the battle is won). The loop ends when a stage parks in a decision phase or the
// cursor runs off the end.
//
// Finishing marks the node resolved — node-level, once (ADR-0014): a Port is walked and
// resolved like anything else, so complete-or-halt has no revisit semantics. Halting
// finishes the walk too (voyage_encounter_resolve_stage jumps the cursor to the end), so a
// captain who flees a [Fight, Reward] never reaches the loot, with no authored gate.
//
// Finishing is also where the node's Ghost_Snapshot is captured (issue #162, ADR-0008 as
// amended): a ghost is the build a captain left this node with, so it is one per encounter,
// taken where the walk ends. The emit and `resolved` are set in the same breath, so
// Event_Encounter_Resolved's "resolved" and the Sim's are one fact. A **halt** reaches
// here (the cursor jumps to the end) and emits — a fled ship is a real ship a lobby can
// serve. A **sinking** does not: the walk stops dead in sim_process_battle_round, the node
// is never resolved, and Event_Voyage_Ended already marks the death. Landmarks emit
// nothing — !has_encounter returns above, before the loop.
sim_walk_encounter :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	encounter, has_encounter := sim_current_encounter(sim)
	if !has_encounter {
		sim.phase = .Awaiting_Travel_Choice
		return
	}

	for {
		stage, walking := voyage.voyage_encounter_current(encounter^)
		if !walking {
			sim.resolved[sim.current] = true
			sim_emit_encounter_resolved(sim, events)
			sim.phase = .Awaiting_Travel_Choice
			return
		}

		// Where the cursor is, said out loud (issue #139) — emitted here rather than in
		// sim_enter_stage's arms so it is one site for all primitives, and *before* the
		// stage presents, so "stage 2 of 3" is on screen by the time its decision is.
		append(events, Event(Event_Stage_Entered{
			kind  = voyage.voyage_stage_kind(stage),
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

// sim_enter_stage starts the stage under the cursor: it presents whatever the primitive
// shows and parks the Sim in the phase that decision needs. Returns the stage's outcome
// when it resolves with nothing to ask the captain, or nil when it has parked — the Maybe
// *is* the "does this stage stop for the player" question, asked of the primitive rather
// than assumed. The switch is exhaustive, so a new primitive is a compile error here
// rather than a stage the walk silently skips.
sim_enter_stage :: proc(sim: ^Sim, stage: voyage.Stage, events: ^[dynamic]Event) -> Maybe(voyage.Stage_Outcome) {
	switch s in stage {
	case voyage.Stage_Fight:
		// The battle borrows the opponent for as long as it runs, so the stage is
		// copied somewhere with a stable address rather than pointed at through the
		// node's Maybe. Its outcome lands in sim_process_battle_round.
		sim.active_encounter = s
		sim.battle = voyage.voyage_start_battle(&sim.player, &sim.active_encounter)
		append(events, Event(Event_Ship_Battle_Sighted{opponent = sim.active_encounter.opponent}))
		append(events, Event(Event_Battle_Menu{may_break_off = combat.combat_may_break_off(&sim.battle, .A)}))
		sim.phase = .Awaiting_Battle_Command
		return nil

	case voyage.Stage_Offer:
		sim_stage_offer_options(sim, s)
		append(events, Event(Event_Options_Presented{options = sim.stage_options}))
		sim.phase = .Awaiting_Option_Choice
		return nil

	case voyage.Stage_Shop:
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

	case voyage.Stage_Trade:
		// The bargain is staged here because the answer arrives a tick later, so the
		// stage's baked content has to outlive the entry. can_accept is measured now,
		// against the ship as it stands.
		sim.active_trade = s
		append(events, Event(Event_Trade_Presented{
			trade      = sim.active_trade,
			can_accept = voyage.voyage_trade_can_accept(&sim.player, sim.active_trade),
		}))
		sim.phase = .Awaiting_Trade_Choice
		return nil

	case voyage.Stage_Reward:
		// The one primitive that parks nowhere (#132, #133): a boon has nothing to
		// decline, so it pays out and hands back .Completed in the same breath, and
		// sim_walk_encounter's loop carries straight on to whatever follows. Event_Ship_Updated
		// is how presentation learns the cargo moved (ADR-0001 — it learns nothing except
		// through Events) and the only event a payout owes: the node's ghost is captured
		// once where the walk ends, not here (same as an accepted Trade).
		voyage.voyage_apply_reward(&sim.player, s)
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
// A **halt** is announced on the way through (issue #139); a completion is not — this is
// the only place both facts are in hand (the outcome, and the cursor still naming the
// stage it applies to). A completion shows itself by what happens next; a halt is the
// outcome with nothing else to show.
sim_advance_stage :: proc(sim: ^Sim, outcome: voyage.Stage_Outcome, events: ^[dynamic]Event) {
	encounter, has_encounter := sim_current_encounter(sim)
	assert(has_encounter, "resolved a stage at a node that holds no encounter")

	if outcome == .Halted {
		stage, walking := voyage.voyage_encounter_current(encounter^)
		assert(walking, "halted a stage on an encounter whose walk already finished")
		append(events, Event(Event_Encounter_Halted{
			at    = voyage.voyage_stage_kind(stage),
			index = encounter.cursor,
			count = encounter.count,
		}))
	}

	voyage.voyage_encounter_resolve_stage(encounter, outcome)
	sim.shop_visit = {} // the cursor is leaving; a stage's working state dies with it
}

// sim_process_option_choice applies a submitted Command_Choose_Option — the one decision
// an Offer and a Shop share (issue #131). Taking an option is uniform: bounds-check it,
// charge it if it carries a price, and open a Refit to place it (the Refit stays a pure
// reusable sub-mode that owns resolving its own stage). What taking or declining means to
// the *stage* is the primitive's business (ADR-0014), asked of it below rather than baked
// into the phase.
sim_process_option_choice :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	cmd := sim_take_pending(sim, Command_Choose_Option)

	encounter, has_encounter := sim_current_encounter(sim)
	assert(has_encounter, "an option choice was answered at a node that holds no encounter")
	stage, walking := voyage.voyage_encounter_current(encounter^)
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
		if cost > ship.ship_cargo(sim.player) {
			// ADR-0012's "an unaffordable item cannot be bought": nothing is spent, no
			// Refit opens, and the stage stays open for another choice.
			append(events, Event(Event_Purchase_Rejected{option = option}))
			return
		}
		// Spending comes out of the hold now (ADR-0020): re-stow the cargo at its
		// reduced total. The affordability check above guarantees cargo >= cost.
		ship.ship_stow_cargo(sim.player.layout, ship.ship_cargo(sim.player) - cost)
		// Broadcast the spent cargo before the Refit opens, so the deduction is visible
		// even if the buyer discards the item in the Refit without installing it (no
		// refund — no inventory, ADR-0012). The Refit's own install emits another.
		append(events, Event(Event_Ship_Updated{ship = sim.player}))
	}

	switch s in stage {
	case voyage.Stage_Offer:
		// Picking completes the Offer. The cursor moves off it now, so the Refit's
		// finish resumes the walk at whatever comes next.
		sim_advance_stage(sim, .Completed, events)

	case voyage.Stage_Shop:
		// A buy does *not* resolve the Shop: the cursor stays put, so the Refit's finish
		// re-enters this same stage and re-presents it refilled — the multi-buy loop, a
		// property of where the cursor is rather than a remembered origin.
		sim.shop_visit.purchases += 1 // this shop is one item deeper; the next buy here costs more
		sim.shop_visit.slots[selection] = shop_visit_draw_next(&sim.shop_visit, s.count)

	case voyage.Stage_Fight, voyage.Stage_Trade, voyage.Stage_Reward:
		panic("an option was taken from a stage that presents no option list")
	}

	sim_open_refit(sim, option.fitting, events)
}

// sim_stage_decline_outcome is what declining an option list does to the encounter — the
// primitive's own definition of completion (ADR-0014), asked of the stage rather than
// assumed by the phase they share. Skipping an Offer **halts**, so a captain who wants
// none of the items gets nothing downstream of it either; leaving a Shop **completes**,
// because a shop cannot be failed — Shop is the one primitive with no halt. Exhaustive
// rather than "halt unless Shop": a new option-list primitive must state its own answer
// here, not inherit one by falling through.
sim_stage_decline_outcome :: proc(stage: voyage.Stage) -> voyage.Stage_Outcome {
	switch _ in stage {
	case voyage.Stage_Offer:
		return .Halted
	case voyage.Stage_Shop:
		return .Completed
	case voyage.Stage_Fight, voyage.Stage_Trade, voyage.Stage_Reward:
		panic("declined a stage that presents no option list")
	}
	unreachable()
}

// sim_stage_offer_options stages an Offer's items as the presented option list: the
// distinct roster items it was baked with (ADR-0012), each free — an Offer's cost is
// the halt it takes to refuse, not cargo. Slots past the Offer's own count stay
// nil, since the shared list is as wide as the widest stage.
sim_stage_offer_options :: proc(sim: ^Sim, offer: voyage.Stage_Offer) {
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
sim_stage_shop_options :: proc(sim: ^Sim, shop: voyage.Stage_Shop) {
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
// leaves the tail slots nil. Called once per Shop stage, as the cursor lands on it.
sim_deal_shop_visit :: proc(visit: ^Shop_Visit, shop: voyage.Stage_Shop) {
	for i in 0 ..< voyage.SHOP_SHELF_SIZE {
		visit.slots[i] = shop_visit_draw_next(visit, shop.count)
	}
	visit.open = true
}
