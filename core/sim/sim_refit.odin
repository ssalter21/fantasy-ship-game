package sim

import "../ship"

// sim_open_refit puts Sim into a Refit (ADR-0012's manual loadout): it stages
// `incoming` — the fitting to place, or nil for a rearrange-only refit — switches to
// the Awaiting_Refit phase, and emits Event_Refit_Started. Called from a stage's own
// resolution path once an item is picked or bought. Setting awaiting_decision is
// idempotent with sim_tick's tail, which re-affirms it when a refit opens from inside
// a tick.
sim_open_refit :: proc(sim: ^Sim, incoming: Maybe(ship.Fitting), events: ^[dynamic]Event) {
	sim.refit_pending = incoming
	sim.phase = .Awaiting_Refit
	append(events, Event(Event_Refit_Started{incoming = incoming}))
	sim.awaiting_decision = true
}

// sim_process_refit applies one submitted loadout operation. It consumes the pending
// Command_Refit and dispatches on the inner Refit_Command: Install / Replace / Move /
// Remove each apply the change and emit its event, or — when ADR-0004's fit rule
// refuses it — emit Event_Refit_Rejected and leave the layout untouched; all four
// keep Sim in Awaiting_Refit so a sequence of edits runs without re-opening. Finish
// discards any still-pending incoming fitting (no inventory — ADR-0012) and hands
// back to the stage walk, which presents whatever the cursor now points at.
sim_process_refit :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	cmd := sim_take_pending(sim, Command_Refit)

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

// sim_refit_install lands the pending incoming fitting in op.slot, routing the
// placement through ship_fit so ADR-0004's fit rule (exact size, empty slot) and
// cargo's stackable/effect-less invariant are enforced in one place. With nothing
// pending, or when ship_fit refuses the slot, it emits Event_Refit_Rejected and
// leaves both the layout and the pending fitting untouched. On success the pending
// fitting is consumed and the change announced.
sim_refit_install :: proc(sim: ^Sim, op: Refit_Install, events: ^[dynamic]Event) {
	sim_refit_assert_slot(sim, op.slot)
	incoming, has_incoming := sim.refit_pending.?
	cargo_before := ship.ship_cargo(sim.player)
	if !has_incoming || !ship.ship_fit(&sim.player.layout[op.slot], incoming) {
		sim_refit_reject(Refit_Command(op), events)
		return
	}
	sim.refit_pending = nil
	append(events, Event(Event_Fitting_Installed{slot = op.slot, fitting = incoming}))
	sim_refit_conserve_cargo(sim, incoming, cargo_before)
	sim_refit_ship_updated(sim, events)
}

// sim_refit_replace swaps the pending incoming fitting into op.slot, discarding
// whatever occupied it (no inventory — ADR-0012). Routes the placement through
// ship_replace_fitting, which checks ADR-0004's exact-size rule before clearing, so a
// size-mismatched incoming (or nothing pending) is refused with Event_Refit_Rejected
// and leaves both the layout and the pending fitting untouched. On success the
// displaced fitting is announced removed and the incoming installed in its place.
sim_refit_replace :: proc(sim: ^Sim, op: Refit_Replace, events: ^[dynamic]Event) {
	sim_refit_assert_slot(sim, op.slot)
	incoming, has_incoming := sim.refit_pending.?
	displaced, occupied := sim.player.layout[op.slot].fitting.?
	cargo_before := ship.ship_cargo(sim.player)
	if !has_incoming || !ship.ship_replace_fitting(&sim.player.layout[op.slot], incoming) {
		sim_refit_reject(Refit_Command(op), events)
		return
	}
	sim.refit_pending = nil
	if occupied {
		append(events, Event(Event_Fitting_Removed{slot = op.slot, fitting = displaced}))
	}
	append(events, Event(Event_Fitting_Installed{slot = op.slot, fitting = incoming}))
	sim_refit_conserve_cargo(sim, incoming, cargo_before)
	sim_refit_ship_updated(sim, events)
}

// sim_refit_move relocates an installed fitting between slots via ship_move,
// which enforces the fit rule and leaves the layout untouched on refusal
// (empty source, occupied destination, or size mismatch), reported as
// Event_Refit_Rejected.
sim_refit_move :: proc(sim: ^Sim, op: Refit_Move, events: ^[dynamic]Event) {
	sim_refit_assert_slot(sim, op.from)
	sim_refit_assert_slot(sim, op.to)
	cargo_before := ship.ship_cargo(sim.player)
	fitting, moved := ship.ship_move(&sim.player.layout[op.from], &sim.player.layout[op.to])
	if !moved {
		sim_refit_reject(Refit_Command(op), events)
		return
	}
	append(events, Event(Event_Fitting_Moved{from = op.from, to = op.to, fitting = fitting}))
	sim_refit_restow(sim, cargo_before)
	sim_refit_ship_updated(sim, events)
}

// sim_refit_remove discards the fitting in op.slot via ship_remove — nothing
// holds it afterward (no inventory — ADR-0012), and the vacated slot backfills with
// a hold. Removing an already-empty slot is rejected.
sim_refit_remove :: proc(sim: ^Sim, op: Refit_Remove, events: ^[dynamic]Event) {
	sim_refit_assert_slot(sim, op.slot)
	cargo_before := ship.ship_cargo(sim.player)
	fitting, removed := ship.ship_remove(&sim.player.layout[op.slot])
	if !removed {
		sim_refit_reject(Refit_Command(op), events)
		return
	}
	append(events, Event(Event_Fitting_Removed{slot = op.slot, fitting = fitting}))
	sim_refit_restow(sim, cargo_before)
	sim_refit_ship_updated(sim, events)
}

// sim_refit_assert_slot bounds-checks a refit slot index. An out-of-range slot is a
// driver bug (a UI offers only real slots), asserted rather than softly rejected; a
// fit-rule violation on an in-range slot is the soft-rejection case instead.
sim_refit_assert_slot :: proc(sim: ^Sim, slot: ship.Slot_Index) {
	assert(slot >= 0 && int(slot) < len(sim.player.layout), "refit slot index out of range")
}

// sim_refit_reject announces a refused loadout command, echoing the command so
// presentation can explain what was refused. The layout is unchanged by the time this
// is called — every caller returns before mutating.
sim_refit_reject :: proc(command: Refit_Command, events: ^[dynamic]Event) {
	append(events, Event(Event_Refit_Rejected{command = command}))
}

// sim_refit_ship_updated re-broadcasts the player's ship after a successful loadout
// change: the specific change event says what happened, this carries the whole
// updated ship so a sink refreshes its own copy (Event_Ship_Updated's contract).
sim_refit_ship_updated :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	append(events, Event(Event_Ship_Updated{ship = sim.player}))
}

// sim_refit_conserve_cargo reconciles the hold after a fitting lands in a slot: the
// surviving cargo is re-stowed into whatever capacity the layout now has, so
// everything still under the ceiling is conserved and only genuine overflow above it
// is lost (ADR-0020). `cargo_before` is snapshotted *before* the placement, so cargo
// the incoming fitting displaced flows into the remaining fittings rather than being
// destroyed.
//
// An incoming that arrives already laden is left alone rather than re-stowed, which
// would double-count what it brought. Nothing does today — a shop or offer fitting is
// authored, and authored fittings carry no cargo — so this is a guard on the seam,
// not a live branch.
sim_refit_conserve_cargo :: proc(sim: ^Sim, incoming: ship.Fitting, cargo_before: int) {
	if incoming.cargo_held > 0 {
		return
	}
	sim_refit_restow(sim, cargo_before)
}

// sim_refit_restow re-derives the whole hold from one scalar total, which is the only
// arrangement concept there is: capacity is a property of the installed fittings, so
// every refit move can change it and the answer is always to pour `cargo_before` back
// in (ship_stow_cargo) and let the water-fill settle it. Move and Remove need it as
// much as Install does now that they displace holds — a Move can land on a laden one
// and a Remove can take one out, and neither should burn the cargo in it.
sim_refit_restow :: proc(sim: ^Sim, cargo_before: int) {
	ship.ship_stow_cargo(sim.player.layout, cargo_before)
}
