package sim

import "../run"

// sim_open_shop opens the Port shop the ship just arrived at (issue #98,
// ADR-0012): it stages the Port's stock, broadcasts it with the current purse on
// Event_Shop_Presented, and switches to the Awaiting_Shop_Choice phase. A Port is
// a revisitable landmark whose stock never depletes, so unlike an Item Offer this
// marks nothing resolved and re-stages the stock on every visit. A shopless port
// — only Start, which is a .Start node rather than .Port — no-ops back to the
// caller with the ship still awaiting a travel choice, so Start stays a pure
// waypoint. Called from sim_process_travel inside a tick; sim_tick's tail
// re-affirms awaiting_decision.
sim_open_shop :: proc(sim: ^Sim, node: run.Node, events: ^[dynamic]Event) {
	shop, has_shop := node.shop.?
	if !has_shop {
		return
	}
	sim.shop_stock = shop.stock
	append(events, Event(Event_Shop_Presented{stock = sim.shop_stock}))
	sim.phase = .Awaiting_Shop_Choice
}

// sim_process_shop_choice applies a submitted Command_Buy_Item (issue #98,
// ADR-0012), resolving one Port-shop decision. A nil selection leaves the shop
// with no purchase and returns to a travel choice; the Port is never marked
// resolved, so retracing to it re-opens the shop. A selection buys that stocked
// item: an unaffordable one (cost above the current starting_treasure) is refused
// with Event_Purchase_Rejected and the shop stays open — the acceptance criteria's
// "an unaffordable item cannot be bought" — while an affordable one deducts its
// cost from starting_treasure (the minimal spend economy: fixed budget, offers
// free, shop purchases paid) and opens a Refit staged with the item, so the same
// manual-loadout commands that place an Item Offer's pick place a purchase too.
// Resolving the buy here (not on the Refit's finish) keeps the Refit a pure,
// reusable sub-mode, matching sim_process_item_choice.
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

	assert(selection >= 0 && int(selection) < len(sim.shop_stock), "Command_Buy_Item selection out of range")
	item := sim.shop_stock[selection]
	if item.cost > sim.player.starting_treasure {
		append(events, Event(Event_Purchase_Rejected{item = item}))
		return
	}

	sim.player.starting_treasure -= item.cost
	// Broadcast the spent purse before the Refit opens, so the deduction is visible
	// even if the buyer discards the item in the Refit without installing it (no
	// refund — no inventory, ADR-0012). The Refit's own install emits another.
	append(events, Event(Event_Ship_Updated{ship = sim.player}))
	sim_open_refit(sim, item.fitting, events)
}
