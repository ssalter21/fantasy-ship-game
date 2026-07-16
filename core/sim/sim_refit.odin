package sim

import "../ship"

// sim_open_refit puts Sim into a Refit (issue #95, ADR-0012's manual loadout):
// it stages `incoming` — the fitting the refit is opened to place, or nil for a
// rearrange-only refit — switches to the Awaiting_Refit phase, and emits
// Event_Refit_Started. Any stage that hands the player an item calls this from its
// own resolution path once the item is picked or bought. It sets awaiting_decision
// so the next refit command can be submitted straight away — idempotent with
// sim_tick's tail, which re-affirms it when a caller opens a refit from inside a
// tick.
//
// It takes no origin any more (issue #131). A Refit used to be told where to return
// — back to travel for an Offer's pick, back to the shop for a buy — but the cursor
// already knows: an Offer advances past itself before opening the Refit and a Shop
// does not, so "resume the walk" resolves to the next stage for one and to the
// re-presented shop for the other. One less thing to keep in sync with the stage it
// describes.
sim_open_refit :: proc(sim: ^Sim, incoming: Maybe(ship.Fitting), events: ^[dynamic]Event) {
	sim.refit_pending = incoming
	sim.phase = .Awaiting_Refit
	append(events, Event(Event_Refit_Started{incoming = incoming}))
	sim.awaiting_decision = true
}

// sim_process_refit applies one submitted loadout operation (issue #95). It
// consumes the pending Command_Refit and dispatches on the inner Refit_Command:
// Install / Replace / Move / Remove each apply the change and emit its event
// (plus a fresh Event_Ship_Updated) or, when ADR-0004's fit rule refuses it,
// emit Event_Refit_Rejected and leave the layout untouched; all four keep Sim in
// Awaiting_Refit so a sequence of edits runs without re-opening. Finish discards
// any still-pending incoming fitting (no inventory — ADR-0012) and hands back to the
// stage walk (issue #131), which presents whatever the cursor is now on: the stage
// after an Offer's pick (which advanced past itself before opening the refit), the
// same shop refilled after a buy (which didn't), or a travel choice once the walk is
// done — or at a node holding no encounter at all, for a bare rearrange.
sim_process_refit :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	pending, has_pending := sim.pending_command.?
	assert(has_pending, "sim_process_refit called without a pending command")
	cmd, ok := pending.(Command_Refit)
	assert(ok, "sim_process_refit called without a pending Command_Refit")
	sim.pending_command = nil

	switch op in cmd.command {
	case Refit_Install:
		sim_refit_install(sim, op, events)
	case Refit_Replace:
		sim_refit_replace(sim, op, events)
	case Refit_Move:
		sim_refit_move(sim, op, events)
	case Refit_Remove:
		sim_refit_remove(sim, op, events)
	case Refit_Finish:
		sim.refit_pending = nil
		append(events, Event(Event_Refit_Finished{}))
		sim_walk_encounter(sim, events)
	}
}

// sim_refit_install lands the refit's pending incoming fitting in op.slot,
// routing the placement through ship_fit so ADR-0004's fit rule (exact size,
// empty slot) — and cargo's stackable/effect-less invariant — are enforced in
// one place. With nothing pending, or when ship_fit refuses the slot, it emits
// Event_Refit_Rejected and leaves both the layout and the pending fitting
// untouched. On success the pending fitting is consumed (installed, no longer
// pending) and the change is announced.
sim_refit_install :: proc(sim: ^Sim, op: Refit_Install, events: ^[dynamic]Event) {
	sim_refit_assert_slot(sim, op.slot)
	incoming, has_incoming := sim.refit_pending.?
	treasure_before := ship.ship_treasure(sim.player)
	if !has_incoming || !ship.ship_fit(&sim.player.layout[op.slot], incoming) {
		sim_refit_reject(Refit_Command(op), events)
		return
	}
	sim.refit_pending = nil
	append(events, Event(Event_Fitting_Installed{slot = op.slot, fitting = incoming}))
	sim_refit_conserve_purse(sim, incoming, treasure_before)
	sim_refit_ship_updated(sim, events)
}

// sim_refit_replace swaps the refit's pending incoming fitting into op.slot,
// discarding whatever occupied it (no inventory — ADR-0012). Like install it
// routes the placement through the ship layer — here ship_replace_fitting, which
// checks ADR-0004's exact-size rule before clearing, so a size-mismatched
// incoming (or nothing pending) is refused with Event_Refit_Rejected and leaves
// both the layout and the pending fitting untouched. On success the displaced
// fitting is announced removed and the incoming installed in its place (the
// place-or-swap counterpart to sim_refit_install), then the whole updated ship.
sim_refit_replace :: proc(sim: ^Sim, op: Refit_Replace, events: ^[dynamic]Event) {
	sim_refit_assert_slot(sim, op.slot)
	incoming, has_incoming := sim.refit_pending.?
	displaced, occupied := sim.player.layout[op.slot].fitting.?
	treasure_before := ship.ship_treasure(sim.player)
	if !has_incoming || !ship.ship_replace_fitting(&sim.player.layout[op.slot], incoming) {
		sim_refit_reject(Refit_Command(op), events)
		return
	}
	sim.refit_pending = nil
	if occupied {
		append(events, Event(Event_Fitting_Removed{slot = op.slot, fitting = displaced}))
	}
	append(events, Event(Event_Fitting_Installed{slot = op.slot, fitting = incoming}))
	sim_refit_conserve_purse(sim, incoming, treasure_before)
	sim_refit_ship_updated(sim, events)
}

// sim_refit_move relocates an installed fitting between slots via ship_move,
// which enforces the fit rule and leaves the layout untouched on refusal
// (empty source, occupied destination, or size mismatch), reported as
// Event_Refit_Rejected.
sim_refit_move :: proc(sim: ^Sim, op: Refit_Move, events: ^[dynamic]Event) {
	sim_refit_assert_slot(sim, op.from)
	sim_refit_assert_slot(sim, op.to)
	fitting, moved := ship.ship_move(&sim.player.layout[op.from], &sim.player.layout[op.to])
	if !moved {
		sim_refit_reject(Refit_Command(op), events)
		return
	}
	append(events, Event(Event_Fitting_Moved{from = op.from, to = op.to, fitting = fitting}))
	sim_refit_ship_updated(sim, events)
}

// sim_refit_remove discards the fitting in op.slot via ship_remove — nothing
// holds it afterward (no inventory — ADR-0012). Removing an already-empty slot
// is rejected.
sim_refit_remove :: proc(sim: ^Sim, op: Refit_Remove, events: ^[dynamic]Event) {
	sim_refit_assert_slot(sim, op.slot)
	fitting, removed := ship.ship_remove(&sim.player.layout[op.slot])
	if !removed {
		sim_refit_reject(Refit_Command(op), events)
		return
	}
	append(events, Event(Event_Fitting_Removed{slot = op.slot, fitting = fitting}))
	sim_refit_ship_updated(sim, events)
}

// sim_refit_assert_slot bounds-checks a refit slot index. An out-of-range slot
// is a driver bug (a UI offers only real slots), asserted rather than softly
// rejected — matching combat_apply_jettison's own slot_index guard. A fit-rule
// violation on an in-range slot is the soft-rejection case instead.
sim_refit_assert_slot :: proc(sim: ^Sim, slot: ship.Slot_Index) {
	assert(slot >= 0 && int(slot) < len(sim.player.layout), "refit slot index out of range")
}

// sim_refit_reject announces a refused loadout command, echoing the command so
// presentation can explain what was refused (issue #95). The layout is
// unchanged by the time this is called — every caller returns before mutating.
sim_refit_reject :: proc(command: Refit_Command, events: ^[dynamic]Event) {
	append(events, Event(Event_Refit_Rejected{command = command}))
}

// sim_refit_ship_updated re-broadcasts the player's ship after a successful
// loadout change, matching the upgrade path: the specific change event says
// what happened, this carries the whole updated ship so a sink refreshes its
// own copy (Event_Ship_Updated's contract).
sim_refit_ship_updated :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	append(events, Event(Event_Ship_Updated{ship = sim.player}))
}

// sim_refit_conserve_purse reconciles the hold after a fitting lands in a slot
// (issue #198, the Shop-buy double-swing). Installing a non-cargo fitting is the
// only refit move that can *shrink* ship_cargo_capacity — its slot stops
// counting toward the hold — and a Replace can drop a cargo slot outright, so
// the surviving treasure is re-stowed into whatever capacity remains: everything
// still under the reduced ceiling is conserved (reallocation is free outside
// battle, #157) and only genuine overflow above it is lost (ADR-0020, #157). A
// Move is capacity-neutral (its exact-size fit rule frees and fills equal
// contributions) and a Remove only *grows* capacity, so neither can strand
// treasure and neither re-stows.
//
// `treasure_before` is the purse snapshotted *before* the placement, so a hold
// a Replace displaces has its treasure flow into the remaining slots rather than
// be destroyed — the difference between conserving what fits and burning the
// whole displaced slot. The re-stow is scoped to non-cargo fittings: cargo never
// reaches a refit (it is stowed by ship_stow_treasure, not fitted), and re-laying
// treasure_before would double-count a cargo incoming's own stack.
sim_refit_conserve_purse :: proc(sim: ^Sim, incoming: ship.Fitting, treasure_before: int) {
	if incoming.is_cargo {
		return
	}
	ship.ship_stow_treasure(sim.player.layout, treasure_before)
}
