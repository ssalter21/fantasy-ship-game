package sim

import "../combat"
import "../run"
import "../ship"
import "core:math/rand"

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

Sim :: struct {
	// rng is kept per ADR-0001 ("Sim owns its own seeded RNG... for
	// deterministic replay"); nothing in this vertical slice's domain logic
	// is actually random yet (map layout and combat resolution are both
	// fully deterministic), but the field/seed stays since ADR-0001 commits
	// to it as Sim's shape, not something this ticket revisits.
	rng:               rand.Default_Random_State,
	run_map:           run.Map,
	player:            ship.Ship,
	current:           int, // index into run_map.points; Start is always 0
	resolved:          []bool, // parallel to run_map.points; true once an Encounter point has fired
	steps:             int, // Ghost_Snapshot progress counter, +1 per travel
	status:            run.Run_Status,
	phase:             Phase,
	awaiting_decision: bool,
	pending_command:   Maybe(Command),
	battle:            combat.Battle,
	active_encounter:  run.Encounter_Ship_Battle,
	upgrade_options:   [3]ship.Fitting,
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
	point_id: int,
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
	option_index: int,
}

// Event is the only way presentation learns what happened inside the Sim
// (ADR-0001).
Event :: union {
	Event_Run_Started,
	Event_Arrived_At_Point,
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
// call. map carries every Point's full data (including each Ship Battle's
// opponent ship) so the UI can draw the static map ahead of time — this
// slice's map has "no fog of war" (ADR-0007) and a hand-authored PvE
// opponent has no privacy stakeholder to protect from its own renderer, so
// there's no data-hiding contract being broken here. ADR-0005's effective
// visibility is a presentation convention applied at the point of scouting
// (Event_Ship_Battle_Sighted), not a guarantee that data is withheld before
// then.
Event_Run_Started :: struct {
	run_map: run.Map,
	ship:    ship.Ship,
}

Event_Arrived_At_Point :: struct {
	point: run.Point,
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

// Event_Encounter_Resolved forwards run.Event_Encounter_Resolved's
// Ghost_Snapshot (ADR-0008) through Sim's own Event boundary. Per
// run_ghost_snapshot_capture's own ownership contract, the recipient
// (Event_Sink) owns snapshot.ship.layout once dispatched and must
// delete(...) it when done — Sim does not retain or free it itself.
Event_Encounter_Resolved :: struct {
	snapshot: run.Ghost_Snapshot,
}

Event_Run_Ended :: struct {
	status: run.Run_Status,
}

sim_create :: proc(seed: u64) -> Sim {
	s: Sim
	s.rng = rand.create_u64(seed)
	s.run_map = run.run_map_create()
	s.player = ship.ship_starting_ship()
	s.resolved = make([]bool, len(s.run_map.points))
	s.status = .In_Progress
	s.phase = .Awaiting_Travel_Choice
	return s
}

// sim_destroy frees every allocation sim_create made, plus whatever the run
// accumulated along the way (the map's Ship Battle opponents' layouts, the
// player's own layout, and the current battle's jettisoned-cargo records, if
// a battle is in progress when destroyed).
sim_destroy :: proc(sim: ^Sim) {
	delete(sim.battle.jettisoned[.A])
	delete(sim.battle.jettisoned[.B])
	delete(sim.player.layout)
	delete(sim.resolved)
	run.run_map_destroy(&sim.run_map)
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

	sim.status = run.run_status(&sim.player, sim.run_map.points[sim.current])
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

// sim_forward_encounter_resolved forwards every run.Event_Encounter_Resolved
// found in run_events (the only variant run.Event currently has) into sim's
// own Event stream.
sim_forward_encounter_resolved :: proc(run_events: [dynamic]run.Event, events: ^[dynamic]Event) {
	for e in run_events {
		if resolved, ok := e.(run.Event_Encounter_Resolved); ok {
			append(events, Event(Event_Encounter_Resolved{snapshot = resolved.snapshot}))
		}
	}
}
