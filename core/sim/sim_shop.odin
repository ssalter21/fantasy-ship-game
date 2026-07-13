package sim

import "../run"

// SHELF_SLOT_EMPTY marks a shelf slot that has no card because the Port's deck
// ran out (issue #123). Only reachable if a deck were drawn down below the shelf
// size — unreachable at the real roster size against a fixed purse, but handled so
// a nearly-drained shop shows fewer cards rather than misbehaving.
SHELF_SLOT_EMPTY :: -1

// Port_Shelf is one Port's persistent shop state (issue #123, ADR-0013): `slots`
// holds the deck position currently shown in each shelf slot (or SHELF_SLOT_EMPTY
// past the deck's tail), and `next_draw` is the next deck position to draw when a
// slot refills after a buy. `opened` is false until the Port's first arrival deals
// its shelf (sim_deal_shelf); thereafter the shelf and cursor persist for the rest
// of the run, so a revisit resumes exactly where it was left. Kept per-Port in
// sim.port_shelves; the deck itself is immutable baked content on the Node.
Port_Shelf :: struct {
	slots:     [run.SHOP_SHELF_SIZE]int,
	next_draw: int,
	opened:    bool,
}

// sim_open_shop opens the Port shop the ship is at (issue #123, ADR-0013): it
// deals that Port's shelf on first arrival (else resumes the persisted one),
// broadcasts the shelf's cards with Event_Shop_Presented, and switches to the
// Awaiting_Shop_Choice phase. A Port is a revisitable landmark whose deck is drawn
// down over the run, so this re-presents the shelf every time — on arrival and on
// each return from a buy's Refit — reflecting what has already been drawn. A
// shopless port — only Start, which is a .Start node rather than .Port — no-ops
// back to the caller with the ship still awaiting a travel choice, so Start stays a
// pure waypoint. Called from sim_process_travel (on arrival) and from a Refit's
// finish (on return); sim_tick's tail re-affirms awaiting_decision.
sim_open_shop :: proc(sim: ^Sim, node: run.Node, events: ^[dynamic]Event) {
	shop, has_shop := node.shop.?
	if !has_shop {
		return
	}
	ps := &sim.port_shelves[node.id]
	if !ps.opened {
		sim_deal_shelf(ps, shop)
	}

	shelf: [run.SHOP_SHELF_SIZE]Maybe(run.Shop_Item)
	for pos, i in ps.slots {
		if pos != SHELF_SLOT_EMPTY {
			shelf[i] = shop.deck[pos]
		}
	}
	append(events, Event(Event_Shop_Presented{shelf = shelf}))
	sim.phase = .Awaiting_Shop_Choice
}

// sim_deal_shelf lays out a Port's opening shelf (issue #123): the top
// SHOP_SHELF_SIZE cards off the deck, one per slot, with next_draw pointing at the
// first still-undrawn card. A deck shorter than the shelf (never at the real roster
// size) leaves the tail slots empty. Called once per Port, on its first arrival.
sim_deal_shelf :: proc(ps: ^Port_Shelf, shop: run.Shop) {
	draw := 0
	for i in 0 ..< run.SHOP_SHELF_SIZE {
		if draw < len(shop.deck) {
			ps.slots[i] = draw
			draw += 1
		} else {
			ps.slots[i] = SHELF_SLOT_EMPTY
		}
	}
	ps.next_draw = draw
	ps.opened = true
}

// sim_process_shop_choice applies a submitted Command_Buy_Item (issue #123,
// ADR-0013), resolving one Port-shop decision. A nil selection leaves the shop
// with no purchase and returns to a travel choice — the only exit to travel; the
// Port is never marked resolved, so retracing to it re-opens the shop where it was
// left. A selection buys that shelf card: an unaffordable one (cost above the
// current starting_treasure) is refused with Event_Purchase_Rejected and the shop
// stays open — ADR-0012's preserved "an unaffordable item cannot be bought" — while
// an affordable one deducts its cost from starting_treasure (the minimal spend
// economy: fixed budget, offers free, shop purchases paid), refills the bought slot
// in place from the next deck card (advancing the draw cursor), and opens a Refit
// staged with the item and flagged .Shop so the Refit's finish returns to this shop
// (now refilled) rather than to travel — the multi-buy loop. Resolving the buy here
// (not on the Refit's finish) keeps the Refit a pure, reusable sub-mode, matching
// sim_process_item_choice.
sim_process_shop_choice :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	assert(has_pending, "sim_process_shop_choice called without a pending command")
	cmd, ok := pending.(Command_Buy_Item)
	assert(ok, "sim_process_shop_choice called without a pending Command_Buy_Item")
	sim.pending_command = nil

	selection, bought := cmd.selection.?
	if !bought {
		sim.phase = .Awaiting_Travel_Choice
		return
	}

	ps := &sim.port_shelves[sim.current]
	assert(selection >= 0 && int(selection) < len(ps.slots), "Command_Buy_Item selection out of range")
	deck_pos := ps.slots[selection]
	assert(deck_pos != SHELF_SLOT_EMPTY, "Command_Buy_Item selected an empty shelf slot")

	// We are at this Port's shop (Awaiting_Shop_Choice), so its Node carries the deck.
	shop := sim.run_map.nodes[sim.current].shop.?
	card := shop.deck[deck_pos]
	if card.cost > sim.player.starting_treasure {
		append(events, Event(Event_Purchase_Rejected{item = card}))
		return
	}

	sim.player.starting_treasure -= card.cost
	// Refill the bought slot in place with the next deck card (or empty it at the
	// deck's tail), advancing the cursor — the persistent draw-down.
	if ps.next_draw < len(shop.deck) {
		ps.slots[selection] = ps.next_draw
		ps.next_draw += 1
	} else {
		ps.slots[selection] = SHELF_SLOT_EMPTY
	}

	// Broadcast the spent purse before the Refit opens, so the deduction is visible
	// even if the buyer discards the item in the Refit without installing it (no
	// refund — no inventory, ADR-0012). The Refit's own install emits another.
	append(events, Event(Event_Ship_Updated{ship = sim.player}))
	sim_open_refit(sim, card.fitting, events, .Shop)
}
