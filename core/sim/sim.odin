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
	Awaiting_Upgrade_Choice,
	Ended,
}

// Node_ID identifies a node in run_map.nodes by position (issue #54:
// distinct from a plain int so a node id can't be passed where a slot index
// or upgrade option index belongs, e.g. via Command_Travel_To).
Node_ID :: distinct int

// Option_Index identifies one of Command_Pick_Upgrade's 3 fixed Upgrade
// Offer options by position (issue #54: distinct from a plain int for the
// same reason as Node_ID).
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
	steps:             int, // Ghost_Snapshot progress counter, +1 per travel
	status:            run.Run_Status,
	phase:             Phase,
	awaiting_decision: bool,
	pending_command:   Maybe(Command),
	battle:            combat.Battle,
	active_encounter:  run.Encounter_Ship_Battle,
	upgrade_options:   [3]ship.Fitting,
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
	Command_Pick_Upgrade,
}

Command_Travel_To :: struct {
	node_id: Node_ID,
}

Command_Battle_Choice :: struct {
	combat_command: combat.Command,
}

// Command_Pick_Upgrade picks one of the 3 fixed Upgrade Offer options
// (option_index into the order run.run_upgrade_offer_options returns:
// 0 = Top Crew/Buff, 1 = Captain's Quarters/Defensive, 2 = Gun Deck/Offensive).
// The picked option's own Fitting.category says which starting slot it
// replaces — no separate index-to-category table needed.
Command_Pick_Upgrade :: struct {
	option_index: Option_Index,
}

// Event is the only way presentation learns what happened inside the Sim
// (ADR-0001).
Event :: union {
	Event_Run_Started,
	Event_Arrived_At_Node,
	Event_Ship_Battle_Sighted,
	Event_Battle_Menu,
	Event_Battle_Event,
	Event_Ship_Updated,
	Event_Upgrade_Offer_Presented,
	Event_Upgrade_Applied,
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

Event_Upgrade_Offer_Presented :: struct {
	options: [3]ship.Fitting,
}

Event_Upgrade_Applied :: struct {
	fitting: ship.Fitting,
}

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
	case .Awaiting_Upgrade_Choice:
		sim_process_upgrade_choice(sim, events)
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

	sim.awaiting_decision = true
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
	case .Awaiting_Upgrade_Choice:
		_, ok := cmd.(Command_Pick_Upgrade)
		assert(ok, "expected a Command_Pick_Upgrade while awaiting an upgrade choice")
	case .Ended:
		assert(false, "submitted a captain choice after the run ended")
	}

	sim.pending_command = cmd
	sim.awaiting_decision = false
}

// sim_emit_encounter_resolved is the single place the Sim captures a resolved
// encounter's Ghost_Snapshot onto its run-scoped arena and emits it (issue
// #82, ADR-0008). The run-side resolution procs (run_apply_stat_trade,
// run_finish_ship_battle, run_apply_upgrade_offer) return a borrowed-layout
// snapshot whose progress/difficulty_rating this proc reads back; capturing
// from sim.player under the arena clones the layout so it outlives the tick
// (issue #52) and lives as long as the Sim. Concentrating the
// arena/temp-allocator ritual here is why the per-encounter make-scratch /
// scope-arena / forward dance no longer repeats at each resolution site.
sim_emit_encounter_resolved :: proc(sim: ^Sim, snap: run.Ghost_Snapshot, events: ^[dynamic]Event) {
	context.allocator = sim_arena_allocator(sim)
	captured := run.run_ghost_snapshot_capture(
		&sim.player,
		snap.progress.steps,
		snap.progress.zone,
		snap.progress.difficulty_rating,
	)
	append(events, Event(Event_Encounter_Resolved{snapshot = captured}))
}
