package sim

import "../combat"
import "../run"
import "../ship"
import "core:math/rand"
import "core:mem"
import "core:mem/virtual"

// Phase is what kind of captain decision Sim is (or is about to be) awaiting
// (issue #24 — wiring core/run/core/combat under the shared run_session
// loop, ADR-0002). run_session passes sim.phase into
// Input_Source.get_captain_choice (issue #39) so adapters route to the
// right decision UI directly instead of re-deriving it from the Event
// stream themselves.
Phase :: enum {
	Awaiting_Travel_Choice,
	Awaiting_Battle_Command,
	// Awaiting_Item_Choice is the Item Offer decision (issue #96, ADR-0012): the
	// ship arrived at an Item Offer node and is choosing one of the offered
	// distinct roster items to place — or skipping. Picking one opens a Refit
	// (Awaiting_Refit) to place or swap it; skipping resolves the encounter and
	// returns to a travel choice. Repurposes the old Awaiting_Upgrade_Choice.
	Awaiting_Item_Choice,
	// Awaiting_Refit is the manual-loadout mode (issue #95, ADR-0012): the ship
	// is rearranged through install / move / remove commands, ended by a finish
	// command. Opened by sim_open_refit — which the acquisition channels (#96
	// Item Offer, #98 Port shop) will call once they pick/buy an item.
	Awaiting_Refit,
	Ended,
}

// Node_ID identifies a node in run_map.nodes by position (issue #54:
// distinct from a plain int so a node id can't be passed where a slot index
// or upgrade option index belongs, e.g. via Command_Travel_To).
Node_ID :: distinct int

// Option_Index identifies one of an Item Offer's presented options by position
// (issue #54: distinct from a plain int for the same reason as Node_ID, so an
// option index can't be passed where a node id or slot index belongs). Indexes
// into the offered items the Sim stages in item_offer_options.
Option_Index :: distinct int

Sim :: struct {
	// rng is kept per ADR-0001 ("Sim owns its own seeded RNG... for
	// deterministic replay"); nothing in this vertical slice's domain logic
	// is actually random yet (map layout and combat resolution are both
	// fully deterministic), but the field/seed stays since ADR-0001 commits
	// to it as Sim's shape, not something this ticket revisits.
	rng:               rand.Default_Random_State,
	run_map:           run.Map,
	// public_nodes is the encounter-kind-masked view of run_map.nodes the
	// Sim broadcasts at run start (the hiding contract): a copy that nils every
	// Encounter's kind while preserving graph shape and landmarks, so
	// presentation cannot leak what kind of encounter a node holds before the
	// ship arrives. Kind is revealed per-node on arrival via
	// Event_Arrived_At_Node, which carries the full Node. The edges it pairs
	// with are shared (borrowed) from run_map.
	public_nodes:      []run.Node,
	player:            ship.Ship,
	current:           Node_ID, // index into run_map.nodes; Start is always 0
	// resolved is parallel to run_map.nodes; true once an Encounter node
	// has fired. Deliberately []bool rather than bit_set (issue #54): bit_set
	// needs a compile-time-bounded index, but resolved is indexed by Node_ID,
	// sized at runtime off run_map_create's generated node count.
	resolved:          []bool,
	// visited is parallel to run_map.nodes; true once the ship has been at a
	// node (Start counts as visited from the outset). Distinct from resolved —
	// landmarks get visited but never resolved — and it is what
	// run_travel_options consults to decide which backward-retrace moves are
	// legal, so the Sim's travel gate reads it every travel choice.
	visited:           []bool,
	// travel_options stages the legal travel destinations the Sim broadcasts on
	// Event_Travel_Options every time it begins awaiting a travel choice (issue
	// #83): run-scoped arena storage (created under the arena in sim_create),
	// cleared and refilled from run_travel_options once per travel decision and
	// borrowed by the emitted event, so adapters and tests consume the moves the
	// Sim already computed instead of re-deriving legality off a shadow map.
	travel_options:    [dynamic]Node_ID,
	steps:             int, // Ghost_Snapshot progress counter, +1 per travel
	status:            run.Run_Status,
	phase:             Phase,
	awaiting_decision: bool,
	pending_command:   Maybe(Command),
	battle:            combat.Battle,
	active_encounter:  run.Encounter_Ship_Battle,
	// item_offer_options are the distinct roster items the current Item Offer is
	// presenting (issue #96): staged from the arrived node's Encounter_Item_Offer
	// and broadcast on Event_Item_Offer_Presented, then indexed by a
	// Command_Pick_Item's Option_Index to know which item to open a Refit with.
	item_offer_options: [run.ITEM_OFFER_OPTION_COUNT]ship.Fitting,
	// refit_pending is the incoming fitting an open Refit (Awaiting_Refit) was
	// opened to place (issue #95): set by sim_open_refit, consumed when a
	// Refit_Install lands it in a slot, and discarded (nil) when the refit
	// finishes without installing it — there is no inventory to hold it
	// (ADR-0012). nil for a rearrange-only refit or once the item is placed.
	refit_pending:     Maybe(ship.Fitting),
	// arena is the Sim's run-scoped allocator (issue #52): every allocation
	// that lives no longer than the Sim itself — the map's Nodes and each
	// Ship Battle opponent's layout, the player's own layout, resolved, the
	// current battle's jettisoned records, and every Ghost_Snapshot handed
	// out via Event_Encounter_Resolved — comes from here, so sim_destroy can
	// reclaim all of it in one call instead of a hand-written per-field
	// delete list.
	arena:             virtual.Arena,
}

// Command is the only way presentation may mutate the Sim (ADR-0001). Which
// variant is valid depends on Sim's current Phase; sim_submit_captain_choice
// asserts the submitted Command matches.
Command :: union {
	Command_Travel_To,
	Command_Battle_Choice,
	Command_Pick_Item,
	Command_Refit,
}

Command_Travel_To :: struct {
	node_id: Node_ID,
}

Command_Battle_Choice :: struct {
	combat_command: combat.Command,
}

// Command_Pick_Item resolves an Item Offer (issue #96, ADR-0012), valid only
// while Sim is in the Awaiting_Item_Choice phase. `selection` is the offered
// item the captain picked (an Option_Index into item_offer_options), or nil to
// **skip** the offer entirely — the "or a skip" half of the acceptance
// criteria. A pick opens a Refit to place or swap that item; a skip resolves the
// encounter with no loadout change. Modeled as a Maybe rather than a sentinel
// index so "skip" is a distinct, unmistakable value.
Command_Pick_Item :: struct {
	selection: Maybe(Option_Index),
}

// Command_Refit carries one loadout operation during a Refit (issue #95,
// ADR-0012), valid only while Sim is in the Awaiting_Refit phase. The inner
// Refit_Command says which operation. Wrapped as a single Command variant
// (rather than four) so the Sim's Command/Phase vocabulary — and every
// exhaustive switch over it — gains one case, not four, mirroring
// Command_Battle_Choice, which likewise carries an inner (combat) union.
Command_Refit :: struct {
	command: Refit_Command,
}

// Refit_Command is the closed set of loadout operations a Refit accepts (issue
// #95). Install places the refit's pending incoming fitting into an empty slot
// and Replace swaps it into a filled one; Move and Remove act on already-
// installed fittings; Finish ends the refit. Every operation enforces ADR-0004's
// exact-size fit rule and is rejected without disturbing the layout
// (Event_Refit_Rejected) when it cannot apply.
Refit_Command :: union {
	Refit_Install,
	Refit_Replace,
	Refit_Move,
	Refit_Remove,
	Refit_Finish,
}

// Refit_Install places the refit's pending incoming fitting into `slot` (issue
// #95). Rejected if there is no pending fitting, the slot is occupied, or the
// sizes differ (ADR-0004).
Refit_Install :: struct {
	slot: ship.Slot_Index,
}

// Refit_Replace swaps the refit's pending incoming fitting into `slot`,
// discarding whatever occupied it (no inventory — ADR-0012). It is the
// place-or-swap counterpart to Refit_Install: Install targets an empty slot,
// Replace a filled one, so presentation names the operation by the slot's state
// without re-checking the fit itself (issue #111). Rejected — layout untouched —
// if there is no pending fitting or the sizes differ (ADR-0004).
Refit_Replace :: struct {
	slot: ship.Slot_Index,
}

// Refit_Move relocates the fitting in `from` into the empty, same-size `to`
// (issue #95, ADR-0004's fit rule). Rejected without disturbing the layout
// when the source is empty, the destination is occupied, or the sizes differ.
Refit_Move :: struct {
	from: ship.Slot_Index,
	to:   ship.Slot_Index,
}

// Refit_Remove discards the fitting in `slot` (issue #95) — there is no
// inventory, so a removed fitting is gone (ADR-0012). Rejected if the slot is
// already empty.
Refit_Remove :: struct {
	slot: ship.Slot_Index,
}

// Refit_Finish ends the refit and returns Sim to awaiting a travel choice
// (issue #95). Any pending incoming fitting still unplaced is discarded.
Refit_Finish :: struct {}

// Event is the only way presentation learns what happened inside the Sim
// (ADR-0001).
Event :: union {
	Event_Run_Started,
	Event_Travel_Options,
	Event_Arrived_At_Node,
	Event_Ship_Battle_Sighted,
	Event_Battle_Menu,
	Event_Battle_Event,
	Event_Ship_Updated,
	Event_Item_Offer_Presented,
	Event_Refit_Started,
	Event_Fitting_Installed,
	Event_Fitting_Moved,
	Event_Fitting_Removed,
	Event_Refit_Rejected,
	Event_Refit_Finished,
	Event_Encounter_Resolved,
	Event_Run_Ended,
}

// Event_Run_Started is dispatched exactly once, on the very first sim_tick
// call. run_map carries the full graph shape (nodes, edges, zones, layer/lane
// layout) and the always-visible landmarks (Start/Port/Goal), but its
// Encounter nodes have their *kind* withheld — run_map.nodes is the Sim's
// masked public_nodes, not its private run_map. This is the hiding contract
// (ADR-0009): what kind of encounter
// a node holds is a surprise revealed only on arrival, via
// Event_Arrived_At_Node carrying that node's full Node. Withholding is a
// guaranteed data property of the emitted event, not a presentation courtesy.
Event_Run_Started :: struct {
	run_map: run.Map,
	ship:    ship.Ship,
}

// Event_Travel_Options is dispatched every time the Sim begins awaiting a
// travel choice (run start, and after each arrival/encounter that returns to
// Awaiting_Travel_Choice): options carries the Node_IDs legally reachable from
// the current position. This is the travel analogue of Event_Battle_Menu's
// may_leave — the legal-move set is state the Sim already computes
// (run_travel_options, once per travel decision) that presentation and tests
// otherwise have to re-derive off a shadow map/visited set they maintain
// themselves (issue #83, ADR-0001's "presentation learns only through Events").
// The slice borrows the Sim's run-scoped travel_options buffer: valid across
// this tick's whole dispatch batch, overwritten only at the next travel
// decision, so a sink that needs it past then must copy it out.
Event_Travel_Options :: struct {
	options: []Node_ID,
}

Event_Arrived_At_Node :: struct {
	node: run.Node,
}

// Event_Ship_Battle_Sighted is dispatched once, when a Ship Battle starts:
// the opponent's full ship data (issue #24: the UI applies
// ship.ship_effective_visibility per slot itself when rendering it — see
// Event_Run_Started's doc comment for why Sim doesn't gate this itself).
Event_Ship_Battle_Sighted :: struct {
	opponent: ship.Ship,
}

// Event_Battle_Menu is dispatched every time a battle command decision is
// about to be asked for (battle start, and after every round that doesn't
// end the battle): may_leave is genuinely Battle-internal state (depends on
// this-round's not-yet-reset temp Speed bonuses) the UI has no other way to
// derive, unlike which slots are cargo (derivable from Event_Ship_Updated's
// own ship copy).
Event_Battle_Menu :: struct {
	may_leave: bool,
}

// Event_Battle_Event wraps one event emitted by core/combat's
// combat_resolve_round for a single round (Event_Damage_Dealt,
// Event_Ship_Sunk, Event_Cargo_Jettisoned, Event_Battle_Ended) — the
// canonical ADR-0002 "UI plays this batch back with animation" case.
Event_Battle_Event :: struct {
	inner: combat.Event,
}

// Event_Ship_Updated carries a plain (non-ghost) copy of the player's ship,
// dispatched at run start and whenever its stats/layout change (after a
// combat round, a Stat Trade, or an Upgrade applied). Needed because
// Ghost_Snapshot always resets hp to max_hp on capture (ADR-0008), which
// makes Event_Encounter_Resolved's snapshot unsuitable for an accurate live
// HP readout.
Event_Ship_Updated :: struct {
	ship: ship.Ship,
}

// Event_Item_Offer_Presented carries the distinct roster items an Item Offer is
// presenting (issue #96, ADR-0012), dispatched when the ship arrives at an Item
// Offer node. Presentation renders each item's tags, phase, size, and effect
// intent and offers a pick-or-skip choice; picking one opens a Refit
// (Event_Refit_Started). Replaces Event_Upgrade_Offer_Presented — there is no
// Event_Upgrade_Applied successor: a pick's placement is announced by the
// Refit's own Event_Fitting_Installed, not a separate apply event.
Event_Item_Offer_Presented :: struct {
	options: [run.ITEM_OFFER_OPTION_COUNT]ship.Fitting,
}

// Event_Refit_Started brackets the opening of a Refit (issue #95): `incoming`
// is the fitting the refit was opened to place (from an Item Offer or Port
// shop — #96/#98), or nil for a rearrange-only refit. Presentation opens its
// loadout-editing menu on this and closes it on Event_Refit_Finished.
Event_Refit_Started :: struct {
	incoming: Maybe(ship.Fitting),
}

// Event_Fitting_Installed / _Moved / _Removed each describe one applied loadout
// change during a Refit (issue #95). _Removed's fitting is discarded (no
// inventory — ADR-0012); it is carried here only so presentation can name what
// was dropped, not because anything still holds it.
Event_Fitting_Installed :: struct {
	slot:    ship.Slot_Index,
	fitting: ship.Fitting,
}

Event_Fitting_Moved :: struct {
	from:    ship.Slot_Index,
	to:      ship.Slot_Index,
	fitting: ship.Fitting,
}

Event_Fitting_Removed :: struct {
	slot:    ship.Slot_Index,
	fitting: ship.Fitting,
}

// Event_Refit_Rejected reports a loadout command that violated the fit rule
// (ADR-0004) and was refused without disturbing the layout (issue #95): a size
// mismatch, an occupied or empty target, or an install with nothing pending.
// `command` echoes the refused operation so presentation can explain it.
Event_Refit_Rejected :: struct {
	command: Refit_Command,
}

// Event_Refit_Finished brackets the close of a Refit (issue #95): Sim returns
// to awaiting a travel choice and any still-unplaced incoming fitting is
// discarded.
Event_Refit_Finished :: struct {}

// Event_Encounter_Resolved carries a resolved encounter's Ghost_Snapshot
// (ADR-0008) out through Sim's own Event boundary. The snapshot (including its
// cloned layout) is allocated from the Sim's own run-scoped arena (issue #52):
// valid for as long as the Sim itself and reclaimed in one shot by
// sim_destroy, not owned or freed per-recipient. A sink that needs a snapshot
// to outlive the Sim must copy it out explicitly.
Event_Encounter_Resolved :: struct {
	snapshot: run.Ghost_Snapshot,
}

Event_Run_Ended :: struct {
	status: run.Run_Status,
}

sim_create :: proc(seed: u64) -> Sim {
	s: Sim
	arena_err := virtual.arena_init_growing(&s.arena)
	assert(arena_err == nil, "failed to initialize the Sim's run-scoped arena")
	context.allocator = virtual.arena_allocator(&s.arena)

	s.rng = rand.create_u64(seed)
	s.run_map = run.run_map_create(seed)
	s.public_nodes = sim_mask_encounter_kinds(s.run_map.nodes)
	s.player = ship.ship_starting_ship()
	s.resolved = make([]bool, len(s.run_map.nodes))
	s.visited = make([]bool, len(s.run_map.nodes))
	s.visited[0] = true // the ship starts at Start (id 0), so retrace to it is legal from the outset.
	s.travel_options = make([dynamic]Node_ID, 0, 8) // arena-backed (context.allocator is the arena here); reused every travel decision.
	s.status = .In_Progress
	s.phase = .Awaiting_Travel_Choice
	return s
}

// sim_mask_encounter_kinds builds the encounter-kind-masked view of nodes
// (the hiding contract): a fresh copy in which every Encounter node's kind is
// withheld (encounter = nil), while Start/Port/Goal landmarks — which carry
// no hidden kind — pass through fully described. Graph shape (zone, layer,
// lane, id) is preserved on every node. Allocated from whatever allocator is
// in scope (the Sim's run-scoped arena at sim_create time).
sim_mask_encounter_kinds :: proc(nodes: []run.Node) -> []run.Node {
	masked := make([]run.Node, len(nodes))
	for p, i in nodes {
		masked[i] = p
		if p.kind == .Encounter {
			masked[i].encounter = nil
		}
	}
	return masked
}

// sim_destroy tears down the Sim's run-scoped arena in one call (issue #52):
// every run-lifetime allocation — the map's Nodes and each Ship Battle
// opponent's layout, the player's own layout, resolved, the current battle's
// jettisoned-cargo records, and any outstanding Ghost_Snapshot — lives in it,
// so there's nothing left to free by hand.
sim_destroy :: proc(sim: ^Sim) {
	virtual.arena_destroy(&sim.arena)
}

// sim_arena_allocator is the Sim's run-scoped allocator (issue #52), shared
// by every sim_process_* call site that scopes context.allocator to it
// around one arena-backed allocation (a Ghost_Snapshot capture, a
// lazily-allocated jettisoned dynamic array).
sim_arena_allocator :: proc(sim: ^Sim) -> mem.Allocator {
	return virtual.arena_allocator(&sim.arena)
}

// sim_tick resolves one unit of work and batch-emits the resulting events.
// What that unit of work is depends on Phase: applying a just-submitted
// travel choice (which may itself trigger an encounter), resolving one
// battle round, or applying an upgrade pick. Calling sim_tick again while
// still awaiting a decision is a driver bug (ADR-0001), same as before.
sim_tick :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	assert(!sim.awaiting_decision, "sim_tick called while a captain decision is still outstanding")

	switch sim.phase {
	case .Awaiting_Travel_Choice:
		sim_process_travel(sim, events)
	case .Awaiting_Battle_Command:
		sim_process_battle_round(sim, events)
	case .Awaiting_Item_Choice:
		sim_process_item_choice(sim, events)
	case .Awaiting_Refit:
		sim_process_refit(sim, events)
	case .Ended:
		assert(false, "sim_tick called after the run already ended")
	}

	if sim.phase == .Ended {
		return
	}

	sim.status = run.run_status(&sim.player, sim.run_map.nodes[sim.current])
	if sim.status != .In_Progress {
		sim.phase = .Ended
		append(events, Event(Event_Run_Ended{status = sim.status}))
		return
	}

	// Whatever unit of work just ran, if the Sim is now awaiting a travel choice
	// (run start, or a battle/upgrade/trade that returned to it) broadcast the
	// legal destinations so consumers pick from what the Sim computed, not a
	// re-derivation (issue #83). Concentrating the emit here — rather than at
	// each phase-transition site — is why every path back to a travel choice
	// carries the options with no per-site repetition.
	if sim.phase == .Awaiting_Travel_Choice {
		sim_emit_travel_options(sim, events)
	}

	sim.awaiting_decision = true
}

// sim_emit_travel_options computes the legal destinations from the current
// node — run_travel_options, the single legality predicate, called once per
// travel decision (issue #83) — stages them (as Node_IDs) in the Sim's
// run-scoped travel_options buffer, and emits them on Event_Travel_Options.
// run_travel_options' own returned slice is short-lived scratch, freed here
// immediately; the reused buffer is what the event borrows, so the emitted
// payload survives the tick's whole dispatch batch yet isn't a fresh arena
// allocation per decision (which would pile up unreclaimed until sim_destroy).
sim_emit_travel_options :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	options := run.run_travel_options(sim.run_map, int(sim.current), sim.visited)
	defer delete(options)

	clear(&sim.travel_options)
	for id in options {
		append(&sim.travel_options, Node_ID(id))
	}
	append(events, Event(Event_Travel_Options{options = sim.travel_options[:]}))
}

// sim_submit_captain_choice validates cmd against Sim's current Phase (the
// same assert-and-store shape as before, just per-phase now) and stores it
// for the next sim_tick call to consume.
sim_submit_captain_choice :: proc(sim: ^Sim, cmd: Command) {
	assert(sim.awaiting_decision, "submitted a captain choice while the sim wasn't awaiting one")

	switch sim.phase {
	case .Awaiting_Travel_Choice:
		_, ok := cmd.(Command_Travel_To)
		assert(ok, "expected a Command_Travel_To while awaiting a travel choice")
	case .Awaiting_Battle_Command:
		_, ok := cmd.(Command_Battle_Choice)
		assert(ok, "expected a Command_Battle_Choice while awaiting a battle command")
	case .Awaiting_Item_Choice:
		_, ok := cmd.(Command_Pick_Item)
		assert(ok, "expected a Command_Pick_Item while awaiting an item choice")
	case .Awaiting_Refit:
		_, ok := cmd.(Command_Refit)
		assert(ok, "expected a Command_Refit while awaiting a refit command")
	case .Ended:
		assert(false, "submitted a captain choice after the run ended")
	}

	sim.pending_command = cmd
	sim.awaiting_decision = false
}

// sim_emit_encounter_resolved is the single place the Sim captures a resolved
// encounter's Ghost_Snapshot onto its run-scoped arena and emits it (issue
// #82, ADR-0008). The run-side resolution procs (run_apply_stat_trade,
// run_finish_ship_battle, run_apply_stat_trade) return a borrowed-layout
// snapshot; run_ghost_snapshot_capture clones that snapshot's layout under the
// arena so it outlives the tick (issue #52) and lives as long as the Sim.
// Concentrating the arena/temp-allocator ritual here is why the per-encounter
// make-scratch / scope-arena / forward dance no longer repeats at each
// resolution site.
sim_emit_encounter_resolved :: proc(sim: ^Sim, snap: run.Ghost_Snapshot, events: ^[dynamic]Event) {
	context.allocator = sim_arena_allocator(sim)
	captured := run.run_ghost_snapshot_capture(snap)
	append(events, Event(Event_Encounter_Resolved{snapshot = captured}))
}
