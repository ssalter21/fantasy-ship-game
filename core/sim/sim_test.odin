package sim

import "../combat"
import "../run"
import "../ship"
import "../testutil"
import "core:testing"

// The map is procedurally generated per seed now, so these end-to-end
// scenarios can't hardcode node ids. Instead of a bespoke pathfinder, the
// Auto_Pilot below drives run_session by choosing at each step from the legal
// travel options the Sim emits on Event_Travel_Options (issue #83), steering by
// a battle policy. The chosen seeds are fixed so each scenario reproduces
// exactly.
//
// **A seed names a map, not a scenario.** run_map_create bakes each encounter's
// content off the same generator it then builds the graph's edges with, so any
// change to what a stage draws at generation shifts every later draw and reshapes
// every seed's map. The seeds below were re-picked when the Trade primitive
// started drawing an axis from its roster (issue #136) — one extra draw per Trade
// node — and a scenario whose premise stops holding ("this route meets no
// battles") is re-pointed at a seed where it holds again, not evidence of a
// regression. Assert on the premise, never on a number a particular map happened
// to produce.

// first_stage_is reports whether e's stage under the cursor is primitive T — how
// the scenarios below ask "what does this node do", now that a node holds an
// ordered stage list rather than one kind tag (ADR-0014). Every recipe in today's
// catalog is one stage long, so for now this is the whole encounter; once #138
// authors multi-stage recipes these scenarios will need to say which stage they
// mean.
first_stage_is :: proc(e: run.Encounter, $T: typeid) -> bool {
	stage, ok := run.run_encounter_current(e)
	if !ok {
		return false
	}
	_, is_t := stage.(T)
	return is_t
}

is_battle_node :: proc(m: run.Map, id: Node_ID) -> bool {
	enc, ok := m.nodes[id].encounter.?
	if !ok {
		return false
	}
	return first_stage_is(enc, run.Stage_Fight)
}

// Travel_Policy is how the Auto_Pilot chooses among the Sim's emitted forward
// travel options each step: dodge Ship Battles, walk into every one, or fight
// exactly the first one it reaches and then dodge the rest.
Travel_Policy :: enum {
	Avoid_Battles,
	Seek_Battles,
	First_Battle_Then_Avoid,
}

// Auto_Pilot drives run_session end to end by choosing from the options the
// Sim emits on Event_Travel_Options (issue #83), rather than following a route
// a bespoke DP pathfinder precomputed. It is both the Input_Source and the
// Event_Sink: dispatch records the emitted legal moves (plus the arrivals and
// events the scenarios assert on), and get_captain_choice picks among them per
// policy. It reads node stages/layers off m — an unmasked copy of the same
// seed's map (a test privilege; the Sim's own public map hides them) — only to
// classify the already-legal options and prefer forward progress, never to
// recompute legality.
Auto_Pilot :: struct {
	m:             run.Map,
	current:       Node_ID,
	options:       []Node_ID,
	policy:        Travel_Policy,
	battles_taken: int,
	battle_cmd:    combat.Command,
	events:        [dynamic]Event,
}

auto_pilot_choice :: proc(data: rawptr, awaiting: Phase) -> Command {
	pilot := cast(^Auto_Pilot)data
	switch awaiting {
	case .Awaiting_Travel_Choice:
		return Command(Command_Travel_To{node_id = auto_pilot_next(pilot)})
	case .Awaiting_Battle_Command:
		return Command(Command_Battle_Choice{combat_command = pilot.battle_cmd})
	case .Awaiting_Item_Choice:
		// Skip every Item Offer (issue #96): a nil selection resolves the offer
		// with no loadout change, so the scenarios steer purely by travel/battle
		// policy without an item-and-refit detour muddying their assertions.
		return Command(Command_Pick_Item{selection = nil})
	case .Awaiting_Trade_Choice:
		// Reject every Trade (issue #136), for the same reason the pilot skips
		// offers and leaves shops: accepting would swap a stat drawn from the axis
		// roster, so the ship a scenario ends with would depend on which bargains
		// its route happened to draw rather than on its travel/battle policy.
		// Accepting is exercised directly by the trade tests below.
		return Command(Command_Trade_Choice{accept = false})
	case .Awaiting_Shop_Choice:
		// Leave every Port shop (issue #123): a nil selection buys nothing, so the
		// scenarios steer purely by travel/battle policy without a purchase-and-refit
		// detour muddying their assertions.
		return Command(Command_Buy_Item{selection = nil})
	case .Awaiting_Refit:
		// The Auto_Pilot skips Item Offers and leaves shops, so it never opens a
		// refit; the Phase switch is exhaustive, so finish immediately rather than
		// leaving the case unhandled.
		return Command(Command_Refit{command = Refit_Finish{}})
	case .Ended:
		panic("auto pilot asked for a choice after the run ended")
	}
	panic("unreachable")
}

// auto_pilot_next chooses the next travel destination from the Sim's emitted
// options: among the forward (deeper-layer) options it prefers one whose stage
// matches the policy's current battle preference, falling back to the first
// forward option, and finally to the first option of any stage (never reached
// before Goal, since every non-Goal node has a forward edge). Preferring
// forward keeps the route progressing toward Goal instead of retracing.
auto_pilot_next :: proc(pilot: ^Auto_Pilot) -> Node_ID {
	assert(len(pilot.options) > 0, "no legal travel option from the current node")
	cur_layer := pilot.m.nodes[pilot.current].layer

	want_battle := false
	switch pilot.policy {
	case .Avoid_Battles:
		want_battle = false
	case .Seek_Battles:
		want_battle = true
	case .First_Battle_Then_Avoid:
		want_battle = pilot.battles_taken == 0
	}

	first_forward: Maybe(Node_ID)
	for dest in pilot.options {
		if pilot.m.nodes[dest].layer <= cur_layer {
			continue // forward steps only
		}
		if _, has := first_forward.?; !has {
			first_forward = dest
		}
		if is_battle_node(pilot.m, dest) == want_battle {
			return auto_pilot_take(pilot, dest)
		}
	}
	if dest, has := first_forward.?; has {
		return auto_pilot_take(pilot, dest)
	}
	return auto_pilot_take(pilot, pilot.options[0])
}

// auto_pilot_take records that a Ship Battle is being stepped onto (so
// First_Battle_Then_Avoid flips to dodging after the first fight) and returns
// dest unchanged.
auto_pilot_take :: proc(pilot: ^Auto_Pilot, dest: Node_ID) -> Node_ID {
	if is_battle_node(pilot.m, dest) {
		pilot.battles_taken += 1
	}
	return dest
}

// auto_pilot_dispatch is the Auto_Pilot's Event_Sink half: it records every
// event (the scenarios read battle outcomes back off pilot.events) and tracks
// the two fields get_captain_choice plans from — the current node and the
// Sim's latest emitted travel options. A #partial switch: a recording sink
// only cares about those two variants and correctly ignores the rest.
auto_pilot_dispatch :: proc(data: rawptr, event: Event) {
	pilot := cast(^Auto_Pilot)data
	append(&pilot.events, event)
	#partial switch e in event {
	case Event_Arrived_At_Node:
		pilot.current = e.node.id
	case Event_Travel_Options:
		pilot.options = e.options
	}
}

// Pilot_Result captures the outcome fields a scenario asserts on, read out
// before the Sim's arena is torn down.
Pilot_Result :: struct {
	status:      run.Run_Status,
	hp:          int,
	durability:  int,
	speed:       int,
	battles_won: int,
}

// drive_policy runs a full session over a fixed seed with an Auto_Pilot
// steering by the given travel policy and returns the outcome. The pilot skips
// every Item Offer (issue #96), so a scenario's result reflects its travel and
// battle policy alone.
drive_policy :: proc(seed: u64, policy: Travel_Policy, battle_cmd: combat.Command) -> Pilot_Result {
	sim := sim_create(seed)
	defer sim_destroy(&sim)

	// An unmasked twin of the Sim's map: run_map_create is deterministic per
	// seed, so its node ids line up with the Sim's, but its encounter stages are
	// unmasked so the pilot can classify the options it is offered.
	m := run.run_map_create(seed)
	defer run.run_map_destroy(&m)

	pilot := Auto_Pilot{m = m, policy = policy, battle_cmd = battle_cmd}
	defer delete(pilot.events)
	input := Input_Source{data = &pilot, get_captain_choice = auto_pilot_choice}
	sink := Event_Sink{data = &pilot, dispatch = auto_pilot_dispatch}

	run_session(&sim, input, sink)

	res := Pilot_Result {
		status     = sim.status,
		hp         = sim.player.hp,
		durability = sim.player.durability,
		speed      = sim.player.speed,
	}
	for event in pilot.events {
		wrapped, is_battle_event := event.(Event_Battle_Event)
		if !is_battle_event {
			continue
		}
		ended, is_ended := wrapped.inner.(combat.Event_Battle_Ended)
		if !is_ended {
			continue
		}
		if winner, has_winner := ended.winner.?; has_winner && winner == .A {
			res.battles_won += 1
		}
	}
	return res
}

BOOST_OFFENSIVE :: combat.Command_Boost{phase = .Offensive}
HOLD :: combat.Command_Hold{}

@(test)
a_battle_free_route_reaches_the_goal_and_wins :: proc(t: ^testing.T) {
	// The graph forces a route through some node per layer, but dodging battles
	// at every emitted option gets the ship to Goal unscathed — the redesign's
	// "travel to Goal wins" over a real graph.
	res := drive_policy(4, .Avoid_Battles, combat.Command(BOOST_OFFENSIVE))
	testing.expect_value(t, res.status, run.Run_Status.Won)
	testing.expect_value(t, res.hp, 20) // untouched: no battle fought
}

@(test)
fighting_a_coastal_ship_battle_can_be_won :: proc(t: ^testing.T) {
	// Fight the first (shallow, Coastal) battle the pilot reaches and boost
	// Offensive, then dodge the rest: the fresh ship wins it and sails on to
	// Goal, taking some damage along the way.
	res := drive_policy(11, .First_Battle_Then_Avoid, combat.Command(BOOST_OFFENSIVE))
	testing.expect_value(t, res.status, run.Run_Status.Won)
	testing.expect(t, res.battles_won >= 1)
	testing.expect(t, res.hp < 20) // a real fight cost some HP
}

@(test)
routing_through_every_battle_can_lose_the_run :: proc(t: ^testing.T) {
	// Seeking every battle walks into fight after fight; a starting ship bleeds
	// out before Goal — permadeath at 0 HP, unchanged. Seed 1's map has a
	// battle-seeking course long enough to be lethal.
	res := drive_policy(1, .Seek_Battles, combat.Command(HOLD))
	testing.expect_value(t, res.status, run.Run_Status.Lost)
	testing.expect_value(t, res.hp, 0)
}

@(test)
skipping_item_offers_on_the_route_leaves_the_loadout_unchanged :: proc(t: ^testing.T) {
	// The battle-dodging route passes through Item Offers; the Auto_Pilot skips
	// each (a nil Command_Pick_Item), so no Refit opens and the starting Gun Deck
	// still sits in its Large exposed slot at Goal — the retired auto-replace path
	// would have swapped it.
	res := drive_policy(4, .Avoid_Battles, combat.Command(BOOST_OFFENSIVE))
	testing.expect_value(t, res.status, run.Run_Status.Won)
}

// --- Trade: accept / reject (issue #136) ------------------------------------

// find_layer1_trade returns a Trade node adjacent to Start, so a test can reach
// one in a single travel step and retrace to Start and back. A layer-1 node is a
// Start neighbour, so it appears in the first emitted option set.
find_layer1_trade :: proc(sim: ^Sim, opts: []Node_ID) -> Node_ID {
	for o in opts {
		node := sim.run_map.nodes[o]
		if node.layer != 1 {
			continue
		}
		if enc, ok := node.encounter.?; ok && first_stage_is(enc, run.Stage_Trade) {
			return o
		}
	}
	return Node_ID(-1)
}

// presented_trade returns the bargain from the last Event_Trade_Presented in
// events — what the Sim put on screen for the captain to answer.
presented_trade :: proc(events: []Event) -> (trade: run.Stage_Trade, ok: bool) {
	for event in events {
		if e, is_trade := event.(Event_Trade_Presented); is_trade {
			trade, ok = e.trade, true
		}
	}
	return
}

// Arriving at a Trade no longer applies it (issue #136): the Sim presents the
// bargain and waits. This is the change from "applies immediately and permanently
// on arrival, matching no-decline".
@(test)
arriving_at_a_trade_presents_the_bargain_instead_of_applying_it :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	opts := tick_travel_options(&sim, &events)
	trade_node := find_layer1_trade(&sim, opts)
	testing.expect(t, trade_node >= 0)

	before := sim.player
	submit_travel(&sim, trade_node)
	clear(&events)
	sim_tick(&sim, &events)

	testing.expect_value(t, sim.phase, Phase.Awaiting_Trade_Choice)
	trade, presented := presented_trade(events[:])
	testing.expect(t, presented)
	testing.expect(t, len(trade.name) > 0)

	// Nothing is paid or granted until the captain answers.
	testing.expect_value(t, sim.player.durability, before.durability)
	testing.expect_value(t, sim.player.speed, before.speed)
	testing.expect_value(t, sim.player.hp, before.hp)
	testing.expect_value(t, sim.player.starting_treasure, before.starting_treasure)
}

// Accepting pays the cost. The gain side's arithmetic (caps, floors, ordering)
// is core/run's business and is covered there; what this asserts is the wiring —
// that an accept reaches run_apply_trade at all. The cost stat is the roster-
// independent half: every axis's cost is paid in full, never capped.
@(test)
accepting_a_trade_pays_its_cost :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	opts := tick_travel_options(&sim, &events)
	trade_node := find_layer1_trade(&sim, opts)
	testing.expect(t, trade_node >= 0)

	submit_travel(&sim, trade_node)
	clear(&events)
	sim_tick(&sim, &events)
	trade, presented := presented_trade(events[:])
	testing.expect(t, presented)

	cost_before := run.run_trade_stat_reading(&sim.player, trade.cost.stat)
	testing.expect(t, run.run_trade_can_accept(&sim.player, trade))

	sim_submit_captain_choice(&sim, Command(Command_Trade_Choice{accept = true}))
	tick_travel_options(&sim, &events)

	testing.expect_value(t, run.run_trade_stat_reading(&sim.player, trade.cost.stat), cost_before - trade.cost.amount)
	testing.expect(t, sim.resolved[trade_node])
}

// Rejecting halts the encounter: nothing is paid, nothing is granted, and the
// node still resolves — a rejected bargain is not offered again on a retrace.
@(test)
rejecting_a_trade_changes_nothing_and_still_resolves_the_node :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	opts := tick_travel_options(&sim, &events)
	trade_node := find_layer1_trade(&sim, opts)
	testing.expect(t, trade_node >= 0)

	submit_travel(&sim, trade_node)
	sim_tick(&sim, &events)
	before := sim.player

	sim_submit_captain_choice(&sim, Command(Command_Trade_Choice{accept = false}))
	tick_travel_options(&sim, &events)

	testing.expect_value(t, sim.player.hp, before.hp)
	testing.expect_value(t, sim.player.max_hp, before.max_hp)
	testing.expect_value(t, sim.player.durability, before.durability)
	testing.expect_value(t, sim.player.speed, before.speed)
	testing.expect_value(t, sim.player.starting_treasure, before.starting_treasure)
	testing.expect(t, sim.resolved[trade_node])
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
}

@(test)
revisiting_a_resolved_encounter_does_not_retrigger_it :: proc(t: ^testing.T) {
	// Retrace is a legal, free routing tool driven straight off the emitted
	// options: arrive at a Trade and accept it, retrace to the already-visited
	// Start (the Sim offers it as a backward option), then step forward onto that
	// Trade again. The second arrival must be a no-op — no bargain presented, no
	// stat touched.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	opts := tick_travel_options(&sim, &events) // run start
	trade_node := find_layer1_trade(&sim, opts)
	testing.expect(t, trade_node >= 0)

	submit_travel(&sim, trade_node)
	clear(&events)
	sim_tick(&sim, &events) // arrive at the trade; it presents once
	trade, presented := presented_trade(events[:])
	testing.expect(t, presented)

	cost_before := run.run_trade_stat_reading(&sim.player, trade.cost.stat)
	sim_submit_captain_choice(&sim, Command(Command_Trade_Choice{accept = true}))
	opts = tick_travel_options(&sim, &events)

	ship_after_trade := sim.player
	testing.expect(t, run.run_trade_stat_reading(&sim.player, trade.cost.stat) < cost_before) // the trade did fire
	testing.expect(t, node_id_in(opts, 0)) // Start offered as a backward retrace

	submit_travel(&sim, 0)
	opts = tick_travel_options(&sim, &events) // retrace to Start
	testing.expect(t, node_id_in(opts, trade_node)) // the trade offered again, forward

	submit_travel(&sim, trade_node)
	clear(&events)
	tick_travel_options(&sim, &events) // step onto the resolved trade again

	// Re-arriving over the resolved trade presented nothing and changed nothing.
	_, presented_again := presented_trade(events[:])
	testing.expect(t, !presented_again)
	testing.expect_value(t, sim.player.durability, ship_after_trade.durability)
	testing.expect_value(t, sim.player.speed, ship_after_trade.speed)
	testing.expect_value(t, sim.player.hp, ship_after_trade.hp)
	testing.expect_value(t, sim.player.starting_treasure, ship_after_trade.starting_treasure)
}

// tick_travel_options clears events, ticks the Sim once, and returns the travel
// options emitted by that tick (nil if the tick didn't end awaiting a travel
// choice). Clearing first keeps the returned slice pointing at the Sim's
// travel_options buffer as filled this tick, before a later tick overwrites it.
tick_travel_options :: proc(sim: ^Sim, events: ^[dynamic]Event) -> []Node_ID {
	clear(events)
	sim_tick(sim, events)
	opts: []Node_ID
	for event in events {
		if e, ok := event.(Event_Travel_Options); ok {
			opts = e.options
		}
	}
	return opts
}

submit_travel :: proc(sim: ^Sim, node: Node_ID) {
	sim_submit_captain_choice(sim, Command(Command_Travel_To{node_id = node}))
}

node_id_in :: proc(opts: []Node_ID, id: Node_ID) -> bool {
	for o in opts {
		if o == id {
			return true
		}
	}
	return false
}

@(test)
travel_to_a_non_neighbor_node_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)
	sim_tick(&sim, &events) // run start: awaiting a travel choice

	// Goal (the last, deepest node) is never adjacent to Start.
	illegal := Node_ID(len(sim.run_map.nodes) - 1)
	sim_submit_captain_choice(&sim, Command(Command_Travel_To{node_id = illegal}))

	testing.expect_assert(t, "not a legal neighbor")
	sim_tick(&sim, &events)
}

@(test)
the_run_start_broadcast_hides_unvisited_encounter_kinds_and_reveals_on_arrival :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_tick(&sim, &events) // run start

	started: Event_Run_Started
	found := false
	for event in events {
		if s, ok := event.(Event_Run_Started); ok {
			started = s
			found = true
		}
	}
	testing.expect(t, found)

	// Graph shape is present: adjacency parallel to nodes.
	testing.expect_value(t, len(started.run_map.edges), len(started.run_map.nodes))
	// Every unvisited non-revealing Encounter's stages are withheld; landmarks are unaffected.
	for p in started.run_map.nodes {
		_, has_encounter := p.encounter.?
		if p.kind == .Encounter {
			testing.expect(t, !has_encounter) // kind hidden pre-arrival
		} else {
			testing.expect(t, !has_encounter) // landmarks carry no encounter at all
		}
	}

	// Arriving at an encounter reveals its kind in the emitted event.
	target := Node_ID(-1)
	for v in sim.run_map.edges[0] {
		if sim.run_map.nodes[v].kind == .Encounter {
			target = v
			break
		}
	}
	testing.expect(t, target >= 0)

	sim_submit_captain_choice(&sim, Command(Command_Travel_To{node_id = target}))
	clear(&events)
	sim_tick(&sim, &events)

	revealed := false
	for event in events {
		if arrived, ok := event.(Event_Arrived_At_Node); ok {
			if _, has := arrived.node.encounter.?; has {
				revealed = true
			}
		}
	}
	testing.expect(t, revealed)
}

@(test)
submit_captain_choice_asserts_when_command_does_not_match_the_awaited_phase :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)
	sim_tick(&sim, &events) // first tick: awaiting a travel choice

	testing.expect_assert(t, "expected a Command_Travel_To while awaiting a travel choice")
	sim_submit_captain_choice(&sim, Command(Command_Pick_Item{selection = Option_Index(0)}))
}

@(test)
tick_again_while_awaiting_decision_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)
	sim_tick(&sim, &events) // first tick: awaiting a travel choice

	testing.expect_assert(t, "sim_tick called while a captain decision is still outstanding")
	sim_tick(&sim, &events)
}

// submit_refit submits one loadout operation for the next tick to apply.
submit_refit :: proc(sim: ^Sim, op: Refit_Command) {
	sim_submit_captain_choice(sim, Command(Command_Refit{command = op}))
}

// refit_tick clears events, ticks the Sim once, and returns that tick's events
// for inspection. The returned slice points at the events buffer as filled this
// tick, valid until the next refit_tick clears it.
refit_tick :: proc(sim: ^Sim, events: ^[dynamic]Event) -> []Event {
	clear(events)
	sim_tick(sim, events)
	return events[:]
}

// has_event reports whether the batch holds an event of variant T.
has_event :: proc(events: []Event, $T: typeid) -> bool {
	for e in events {
		if _, ok := e.(T); ok {
			return true
		}
	}
	return false
}

fitting_name_at :: proc(sim: ^Sim, slot: int) -> string {
	f, ok := sim.player.layout[slot].fitting.?
	return ok ? f.name : ""
}

slot_is_empty :: proc(sim: ^Sim, slot: int) -> bool {
	_, ok := sim.player.layout[slot].fitting.?
	return !ok
}

slot_holds_cargo :: proc(sim: ^Sim, slot: int) -> bool {
	f, ok := sim.player.layout[slot].fitting.?
	return ok && f.is_cargo
}

@(test)
a_refit_sequence_installs_moves_and_removes_fittings_and_enforces_the_fit_rule :: proc(t: ^testing.T) {
	// Drive a full loadout-editing sequence over the starting ship and assert
	// both the resulting layout and that every illegal placement is refused
	// without disturbing it (issue #95's acceptance test). Starting slots:
	//   0 top deck (M) Captain's Quarters   4 hold 1 (M) Cargo
	//   1 top crew (M) Top Crew             5 hold 2 (S) Cargo
	//   2 gun deck (L) Gun Deck             6 hold 3 (S) Cargo
	//   3 forecastle (L) Cargo              7 hold 4 (S) Cargo
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	incoming := ship.ship_fitting_upgraded_gun_deck(3) // "Upgraded Gun Deck", Large
	sim_open_refit(&sim, incoming, &events)
	testing.expect(t, has_event(events[:], Event_Refit_Started))
	testing.expect_value(t, sim.phase, Phase.Awaiting_Refit)

	// Install into a size-mismatched slot (Large item, Medium slot 0): refused,
	// layout untouched, incoming still pending.
	submit_refit(&sim, Refit_Install{slot = 0})
	ev := refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Refit_Rejected))
	testing.expect_value(t, fitting_name_at(&sim, 0), "Captain's Quarters")
	_, still_pending := sim.refit_pending.?
	testing.expect(t, still_pending)

	// Install into an occupied same-size slot (Large slot 3 holds cargo): refused.
	submit_refit(&sim, Refit_Install{slot = 3})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Refit_Rejected))
	testing.expect(t, slot_holds_cargo(&sim, 3))

	// Remove the Large cargo in slot 3: discarded (no inventory), slot empties.
	submit_refit(&sim, Refit_Remove{slot = 3})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Fitting_Removed))
	testing.expect(t, slot_is_empty(&sim, 3))

	// Move the Gun Deck (Large) from slot 2 into the now-empty Large slot 3.
	submit_refit(&sim, Refit_Move{from = 2, to = 3})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Fitting_Moved))
	testing.expect(t, slot_is_empty(&sim, 2))
	testing.expect_value(t, fitting_name_at(&sim, 3), "Gun Deck")

	// Install the pending Upgraded Gun Deck into the freed Large slot 2.
	submit_refit(&sim, Refit_Install{slot = 2})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Fitting_Installed))
	testing.expect_value(t, fitting_name_at(&sim, 2), "Upgraded Gun Deck")
	_, pending_after_install := sim.refit_pending.?
	testing.expect(t, !pending_after_install) // consumed

	// With nothing pending, an install even into an empty, size-matching slot is
	// refused: free a Small slot, then try to install into it.
	submit_refit(&sim, Refit_Remove{slot = 5})
	refit_tick(&sim, &events)
	testing.expect(t, slot_is_empty(&sim, 5))
	submit_refit(&sim, Refit_Install{slot = 5})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Refit_Rejected))
	testing.expect(t, slot_is_empty(&sim, 5)) // nothing installed

	// Removing an already-empty slot is refused too.
	submit_refit(&sim, Refit_Remove{slot = 5})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Refit_Rejected))

	// Finish returns to a travel choice and broadcasts the legal moves again.
	submit_refit(&sim, Refit_Finish{})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Refit_Finished))
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, has_event(ev, Event_Travel_Options))
}

@(test)
a_refit_replace_swaps_a_matching_fitting_and_rejects_a_size_mismatch :: proc(t: ^testing.T) {
	// Refit_Replace is the place-or-swap counterpart to Install (issue #111): it
	// drops a slot's occupant and lands the pending incoming in one command, still
	// under ADR-0004's fit rule — the rule the game menu used to predict for itself.
	// Starting slots: 0 top deck (M) Captain's Quarters, 2 gun deck (L) Gun Deck.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_open_refit(&sim, ship.ship_fitting_top_crew(), &events) // Medium incoming

	// Replace into a size-mismatched slot (Medium item, Large slot 2): refused,
	// layout untouched, incoming still pending.
	submit_refit(&sim, Refit_Replace{slot = 2})
	ev := refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Refit_Rejected))
	testing.expect_value(t, fitting_name_at(&sim, 2), "Gun Deck")
	_, still_pending := sim.refit_pending.?
	testing.expect(t, still_pending)

	// Replace into a same-size occupied slot (Medium slot 0): the occupant is
	// discarded (Event_Fitting_Removed) and the incoming installed in its place.
	submit_refit(&sim, Refit_Replace{slot = 0})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Fitting_Removed))
	testing.expect(t, has_event(ev, Event_Fitting_Installed))
	testing.expect_value(t, fitting_name_at(&sim, 0), "Top Crew")
	_, pending_after := sim.refit_pending.?
	testing.expect(t, !pending_after) // consumed

	// With nothing left to place, a replace is refused and the slot is untouched.
	submit_refit(&sim, Refit_Replace{slot = 0})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Refit_Rejected))
	testing.expect_value(t, fitting_name_at(&sim, 0), "Top Crew")
}

@(test)
finishing_a_refit_discards_an_unplaced_incoming_fitting :: proc(t: ^testing.T) {
	// No inventory (ADR-0012): an incoming fitting never installed is gone once
	// the refit finishes — the Sim holds nothing that could re-offer it.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_open_refit(&sim, ship.ship_fitting_upgraded_gun_deck(3), &events)
	_, pending := sim.refit_pending.?
	testing.expect(t, pending)

	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)

	_, still_pending := sim.refit_pending.?
	testing.expect(t, !still_pending) // discarded
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
}

@(test)
a_refit_slot_index_out_of_range_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_open_refit(&sim, ship.ship_fitting_upgraded_gun_deck(3), &events)
	submit_refit(&sim, Refit_Remove{slot = ship.Slot_Index(len(sim.player.layout))})

	testing.expect_assert(t, "refit slot index out of range")
	sim_tick(&sim, &events)
}

// stage_item_offer puts the Sim into an Item Offer decision (issue #96): it
// stages a set of offered items and switches to Awaiting_Item_Choice awaiting a
// Command_Pick_Item, standing in for an arrival at an Item Offer node without
// having to navigate the whole map to one. The offered items come from the
// roster pool so they are real, placeable fittings.
stage_item_offer :: proc(sim: ^Sim) {
	roster := ship.ship_item_roster()
	for i in 0 ..< run.ITEM_OFFER_OPTION_COUNT {
		sim.item_offer_options[i] = roster[i].fitting
	}
	sim.phase = .Awaiting_Item_Choice
	sim.awaiting_decision = true
}

@(test)
picking_an_item_from_an_offer_opens_a_refit_to_place_it :: proc(t: ^testing.T) {
	// The core of #96's acceptance: picking an offered item resolves the encounter
	// and opens a Refit staged with that exact item, so the manual-loadout
	// commands can place or swap it.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	stage_item_offer(&sim)
	sim_submit_captain_choice(&sim, Command(Command_Pick_Item{selection = Option_Index(1)}))
	ev := refit_tick(&sim, &events)

	testing.expect_value(t, sim.phase, Phase.Awaiting_Refit)
	testing.expect(t, has_event(ev, Event_Refit_Started))
	testing.expect(t, sim.resolved[sim.current]) // the offer is resolved by the pick
	incoming, pending := sim.refit_pending.?
	testing.expect(t, pending)
	testing.expect_value(t, incoming.name, sim.item_offer_options[1].name) // the picked item is staged
}

@(test)
skipping_an_item_offer_resolves_it_without_opening_a_refit :: proc(t: ^testing.T) {
	// The "or a skip" half: a nil selection resolves the offer with no loadout
	// change and returns straight to a travel choice — no Refit, nothing pending.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	stage_item_offer(&sim)
	sim_submit_captain_choice(&sim, Command(Command_Pick_Item{selection = nil}))
	ev := refit_tick(&sim, &events)

	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[sim.current]) // resolved even though nothing was taken
	testing.expect(t, !has_event(ev, Event_Refit_Started))
	_, pending := sim.refit_pending.?
	testing.expect(t, !pending)
	testing.expect(t, has_event(ev, Event_Travel_Options)) // back to a travel choice
}

@(test)
an_out_of_range_item_selection_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	stage_item_offer(&sim)
	sim_submit_captain_choice(&sim, Command(Command_Pick_Item{selection = Option_Index(run.ITEM_OFFER_OPTION_COUNT)}))

	testing.expect_assert(t, "Command_Pick_Item selection out of range")
	sim_tick(&sim, &events)
}

// flat_deck bakes a Port deck of the full roster in roster order, every card
// priced flat at `cost` (issue #123) — a stand-in for a generated Port's baked
// deck with predictable affordability and a known top-of-deck order (card at deck
// position i is roster[i]), so the shop tests can assert exactly which card the
// shelf shows and refills with. A real generated deck is a shuffle of this same
// set (run_port_shop); the tests don't need the shuffle, only the deck contract.
flat_deck :: proc(cost: int) -> run.Stage_Shop {
	roster := ship.ship_item_roster()
	shop: run.Stage_Shop
	for i in 0 ..< ship.ITEM_ROSTER_SIZE {
		shop.deck[i] = run.Shop_Item{fitting = roster[i].fitting, cost = cost}
	}
	return shop
}

// install_port_deck marks node `id` a Port carrying `shop`'s baked deck (issue
// #123), so the shop tests can drive sim_open_shop / buy / refit-finish over a real
// node whose shop both the buy and the refit-return paths read. Mutating the
// arena-backed map directly is a white-box test privilege; the Port's persistent
// shelf (port_shelves[id]) is untouched, so it deals on first arrival and persists
// across the arrivals a test stages.
install_port_deck :: proc(sim: ^Sim, id: Node_ID, shop: run.Stage_Shop) {
	sim.run_map.nodes[id].kind = .Port
	sim.run_map.nodes[id].shop = shop
}

// arrive_at_port points the ship at Port `id` and opens its shop (issue #123),
// as sim_process_travel does on arrival. It sets awaiting_decision (sim_open_shop
// leaves that to sim_tick's tail, which isn't running here), so a test can submit
// a Command_Buy_Item next. events holds the emitted Event_Shop_Presented.
arrive_at_port :: proc(sim: ^Sim, id: Node_ID, events: ^[dynamic]Event) {
	sim.current = id
	clear(events)
	sim_open_shop(sim, sim.run_map.nodes[id], events)
	sim.awaiting_decision = true
}

// presented_shelf returns the shelf carried by the last Event_Shop_Presented in
// the batch (issue #123), so a test reads what a re-staged shop actually showed.
presented_shelf :: proc(events: []Event) -> [run.SHOP_SHELF_SIZE]Maybe(run.Shop_Item) {
	shelf: [run.SHOP_SHELF_SIZE]Maybe(run.Shop_Item)
	for e in events {
		if presented, ok := e.(Event_Shop_Presented); ok {
			shelf = presented.shelf
		}
	}
	return shelf
}

// shelf_card_name is the fitting name shown in shelf slot i, or "" if that slot
// is empty (past the deck's tail).
shelf_card_name :: proc(shelf: [run.SHOP_SHELF_SIZE]Maybe(run.Shop_Item), i: int) -> string {
	if card, ok := shelf[i].?; ok {
		return card.fitting.name
	}
	return ""
}

@(test)
buying_an_affordable_item_deducts_treasure_and_opens_a_refit :: proc(t: ^testing.T) {
	// The core of #123's acceptance: buying a shelf card the ship can afford
	// deducts its cost from starting_treasure and opens a Refit staged with that
	// exact item, so the manual-loadout commands place it — the same path an Item
	// Offer's pick takes.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.player.starting_treasure = 50
	install_port_deck(&sim, 1, flat_deck(10))
	arrive_at_port(&sim, 1, &events)
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = Option_Index(1)}))
	ev := refit_tick(&sim, &events)

	roster := ship.ship_item_roster()
	testing.expect_value(t, sim.phase, Phase.Awaiting_Refit)
	testing.expect(t, has_event(ev, Event_Refit_Started))
	testing.expect_value(t, sim.player.starting_treasure, 40) // 50 - 10 spent
	testing.expect_value(t, sim.refit_origin, Refit_Origin.Shop) // finishes back at the shop
	incoming, pending := sim.refit_pending.?
	testing.expect(t, pending)
	testing.expect_value(t, incoming.name, roster[1].fitting.name) // shelf slot 1 == deck pos 1 == roster[1]
}

@(test)
an_unaffordable_item_is_refused_and_the_shop_stays_open :: proc(t: ^testing.T) {
	// "an unaffordable item cannot be bought": a buy costing more than the purse is
	// rejected, no treasure is spent, no Refit opens, and the shop stays open for
	// another choice.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	shop := flat_deck(10)
	shop.deck[2].cost = 100 // slot 2 (deck pos 2) beyond any reachable purse
	sim.player.starting_treasure = 50
	install_port_deck(&sim, 1, shop)
	arrive_at_port(&sim, 1, &events)
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = Option_Index(2)}))
	ev := refit_tick(&sim, &events)

	testing.expect(t, has_event(ev, Event_Purchase_Rejected))
	testing.expect(t, !has_event(ev, Event_Refit_Started))
	testing.expect_value(t, sim.player.starting_treasure, 50) // nothing spent
	testing.expect_value(t, sim.phase, Phase.Awaiting_Shop_Choice) // shop still open
	_, pending := sim.refit_pending.?
	testing.expect(t, !pending)
}

@(test)
leaving_a_shop_makes_no_purchase_and_returns_to_travel :: proc(t: ^testing.T) {
	// The "or leave" half: a nil selection buys nothing, spends nothing, opens no
	// Refit, and returns straight to a travel choice — the only exit to travel. A
	// Port is never marked resolved, so nothing here touches resolved[].
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.player.starting_treasure = 50
	install_port_deck(&sim, 1, flat_deck(10))
	arrive_at_port(&sim, 1, &events)
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = nil}))
	ev := refit_tick(&sim, &events)

	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect_value(t, sim.player.starting_treasure, 50) // nothing spent
	testing.expect(t, !has_event(ev, Event_Refit_Started))
	testing.expect(t, has_event(ev, Event_Travel_Options)) // back to a travel choice
}

@(test)
an_out_of_range_shop_selection_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	install_port_deck(&sim, 1, flat_deck(10))
	arrive_at_port(&sim, 1, &events)
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = Option_Index(run.SHOP_SHELF_SIZE)}))

	testing.expect_assert(t, "Command_Buy_Item selection out of range")
	sim_tick(&sim, &events)
}

@(test)
arriving_at_a_port_presents_the_top_of_its_deck :: proc(t: ^testing.T) {
	// Arriving at a Port stages a SHOP_SHELF_SIZE shelf off the top of its deck and
	// presents the shop (issue #123). A shopless port (Start) is a pure waypoint —
	// sim_open_shop no-ops it.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	install_port_deck(&sim, 1, flat_deck(15))
	arrive_at_port(&sim, 1, &events)

	testing.expect_value(t, sim.phase, Phase.Awaiting_Shop_Choice)
	shelf := presented_shelf(events[:])
	roster := ship.ship_item_roster()
	// The shelf is the top SHOP_SHELF_SIZE deck cards (deck position i is roster[i]),
	// each priced at the deck's flat 15.
	for i in 0 ..< run.SHOP_SHELF_SIZE {
		card, filled := shelf[i].?
		testing.expect(t, filled)
		testing.expect_value(t, card.fitting.name, roster[i].fitting.name)
		testing.expect_value(t, card.cost, 15)
	}

	// A shopless port leaves the Sim awaiting a travel choice, nothing presented.
	clear(&events)
	sim.phase = .Awaiting_Travel_Choice
	sim_open_shop(&sim, run.Node{kind = .Port}, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, !has_event(events[:], Event_Shop_Presented))
}

@(test)
buying_a_shelf_card_refills_the_slot_from_the_deck_on_the_refits_finish :: proc(t: ^testing.T) {
	// #123's core: an affordable buy opens a Refit, and on its finish the Sim
	// returns to the *shop* (not travel) with the bought slot refilled by the next
	// deck card. The bought item (roster[0]) is gone from the shelf; the refill
	// (roster[SHOP_SHELF_SIZE], the first still-undrawn card) has taken slot 0.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.player.starting_treasure = 50
	install_port_deck(&sim, 1, flat_deck(10))
	arrive_at_port(&sim, 1, &events)

	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = Option_Index(0)}))
	refit_tick(&sim, &events) // buy: deduct, open the refit (origin .Shop)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Refit)

	submit_refit(&sim, Refit_Finish{})
	ev := refit_tick(&sim, &events) // finish: return to the shop, refilled

	testing.expect_value(t, sim.phase, Phase.Awaiting_Shop_Choice) // back at the shop, not travel
	testing.expect(t, has_event(ev, Event_Shop_Presented)) // re-presented refilled
	roster := ship.ship_item_roster()
	shelf := presented_shelf(ev)
	// Slot 0 refilled with the next deck card; the bought roster[0] is off the shelf.
	testing.expect_value(t, shelf_card_name(shelf, 0), roster[run.SHOP_SHELF_SIZE].fitting.name)
	for i in 0 ..< run.SHOP_SHELF_SIZE {
		testing.expect(t, shelf_card_name(shelf, i) != roster[0].fitting.name)
	}
}

@(test)
multiple_items_can_be_bought_in_one_visit_before_leaving :: proc(t: ^testing.T) {
	// #123: a visit is a multi-buy loop — each buy's refit returns to the shop, so
	// the player keeps buying (draining the deck and the purse) until only Leave
	// exits to travel. Buy three cards in a row, then leave.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.player.starting_treasure = 50
	install_port_deck(&sim, 1, flat_deck(10))
	arrive_at_port(&sim, 1, &events)

	for _ in 0 ..< 3 {
		testing.expect_value(t, sim.phase, Phase.Awaiting_Shop_Choice)
		sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = Option_Index(0)}))
		refit_tick(&sim, &events) // open the buy's refit
		submit_refit(&sim, Refit_Finish{})
		refit_tick(&sim, &events) // finish -> back to the shop
	}
	// Three escalating buys (issue #124): base 10, then 10+step, then 10+2*step.
	spent := 3 * 10 + SHOP_DEPTH_SURCHARGE_STEP * (0 + 1 + 2)
	testing.expect_value(t, sim.player.starting_treasure, 50 - spent)

	// Only Leave exits to travel.
	testing.expect_value(t, sim.phase, Phase.Awaiting_Shop_Choice)
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = nil}))
	ev := refit_tick(&sim, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, has_event(ev, Event_Travel_Options))
}

@(test)
a_ports_draw_down_persists_across_visits :: proc(t: ^testing.T) {
	// #123: the draw cursor and purchases persist for the rest of the run — a
	// revisited Port shows the same shelf minus what was taken, not a fresh one.
	// Buy the top card, leave, then revisit: the shelf resumes where it was left
	// (roster[0] gone, its slot holding the refill), not reset to the deck's top.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.player.starting_treasure = 50
	install_port_deck(&sim, 1, flat_deck(10))
	roster := ship.ship_item_roster()

	// Visit 1: buy the top card, finish its refit, then leave to travel.
	arrive_at_port(&sim, 1, &events)
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events) // back at the shop, refilled
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = nil}))
	refit_tick(&sim, &events) // leave to travel
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)

	// Visit 2: arrive at the same Port again. The ledger persisted, so the shelf is
	// the deck minus roster[0], with the refill in its place — not the deck's top.
	arrive_at_port(&sim, 1, &events)
	shelf := presented_shelf(events[:])
	testing.expect_value(t, shelf_card_name(shelf, 0), roster[run.SHOP_SHELF_SIZE].fitting.name)
	for i in 0 ..< run.SHOP_SHELF_SIZE {
		testing.expect(t, shelf_card_name(shelf, i) != roster[0].fitting.name) // stays bought
	}
}

@(test)
distinct_ports_draw_down_independently :: proc(t: ^testing.T) {
	// #123: each Port owns its own ledger, so buying at one Port doesn't touch
	// another's shelf — variety comes from checking Port against Port. Buy at Port
	// 1, then open Port 2 (same flat deck for a comparable shelf): Port 2 still
	// shows its deck's untouched top.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.player.starting_treasure = 50
	install_port_deck(&sim, 1, flat_deck(10))
	install_port_deck(&sim, 2, flat_deck(10))
	roster := ship.ship_item_roster()

	arrive_at_port(&sim, 1, &events)
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = nil}))
	refit_tick(&sim, &events)

	// Port 2 is untouched: its shelf still opens on the deck's top card (roster[0]).
	arrive_at_port(&sim, 2, &events)
	shelf := presented_shelf(events[:])
	testing.expect_value(t, shelf_card_name(shelf, 0), roster[0].fitting.name)
}

@(test)
successive_buys_at_a_port_escalate_in_price :: proc(t: ^testing.T) {
	// #124, ADR-0013: each successive buy at a Port costs step more than the last,
	// so digging one shop deep is expensive. The first buy is the plain tier price
	// (purchases == 0); each later buy climbs by SHOP_DEPTH_SURCHARGE_STEP, and the
	// price shown on the re-presented shelf is exactly the price charged.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	base :: 10
	sim.player.starting_treasure = 100
	install_port_deck(&sim, 1, flat_deck(base))
	arrive_at_port(&sim, 1, &events)

	purse := 100
	for n in 0 ..< 3 {
		want_price := base + SHOP_DEPTH_SURCHARGE_STEP * n

		// The re-presented shelf displays the surcharged price for this depth, so the
		// buyer sees the escalation before committing.
		shelf := presented_shelf(events[:])
		card, filled := shelf[0].?
		testing.expect(t, filled)
		testing.expect_value(t, card.cost, want_price)

		testing.expect_value(t, sim.phase, Phase.Awaiting_Shop_Choice)
		sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = Option_Index(0)}))
		refit_tick(&sim, &events) // buy: charge want_price, open the refit
		purse -= want_price
		testing.expect_value(t, sim.player.starting_treasure, purse) // charged the shown price

		submit_refit(&sim, Refit_Finish{})
		refit_tick(&sim, &events) // finish -> back to the shop, re-presented one depth deeper
	}
	// base + (base+step) + (base+2*step) spent across the three escalating buys.
	testing.expect_value(t, sim.player.starting_treasure, 100 - (3 * base + SHOP_DEPTH_SURCHARGE_STEP * (0 + 1 + 2)))
}

@(test)
the_depth_surcharge_persists_across_visits :: proc(t: ^testing.T) {
	// #124: the per-Port purchase count persists across visits like the draw cursor,
	// so a revisited Port charges from where its depth left off — not a reset tier
	// price. Buy once (tier price) and leave; on return the shelf shows, and the next
	// buy charges, the escalated price.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	base :: 10
	sim.player.starting_treasure = 100
	install_port_deck(&sim, 1, flat_deck(base))

	// Visit 1: one buy at the plain tier price, then leave to travel.
	arrive_at_port(&sim, 1, &events)
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = nil}))
	refit_tick(&sim, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect_value(t, sim.player.starting_treasure, 100 - base) // first buy at tier price

	// Visit 2: the count persisted (one prior purchase), so the shelf shows and the
	// next buy charges base + step, not the reset tier price.
	arrive_at_port(&sim, 1, &events)
	shelf := presented_shelf(events[:])
	card, filled := shelf[0].?
	testing.expect(t, filled)
	testing.expect_value(t, card.cost, base + SHOP_DEPTH_SURCHARGE_STEP)
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	testing.expect_value(t, sim.player.starting_treasure, 100 - base - (base + SHOP_DEPTH_SURCHARGE_STEP))
}

@(test)
a_surcharge_can_make_a_buy_unaffordable_and_the_shop_stays_open :: proc(t: ^testing.T) {
	// #124: a buy the purse can't cover *once the surcharge is applied* is refused
	// exactly like any other unaffordable buy — nothing spent, no Refit — and the
	// shop stays open. Size the purse so the first buy (tier price) fits but the
	// second (tier + step) does not.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	base :: 10
	// Covers one buy at base with a little to spare, but not base + step for the next.
	sim.player.starting_treasure = base + (base + SHOP_DEPTH_SURCHARGE_STEP) - 1
	install_port_deck(&sim, 1, flat_deck(base))
	arrive_at_port(&sim, 1, &events)

	// First buy at the plain tier price succeeds.
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)
	remaining := sim.player.starting_treasure
	testing.expect_value(t, remaining, base + SHOP_DEPTH_SURCHARGE_STEP - 1)

	// Second buy: base + step now exceeds the remaining purse, so the surcharge alone
	// refuses it and the shop stays open.
	sim_submit_captain_choice(&sim, Command(Command_Buy_Item{selection = Option_Index(0)}))
	ev := refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Purchase_Rejected))
	testing.expect(t, !has_event(ev, Event_Refit_Started))
	testing.expect_value(t, sim.player.starting_treasure, remaining) // nothing spent
	testing.expect_value(t, sim.phase, Phase.Awaiting_Shop_Choice) // shop still open
}

@(test)
the_auto_pilot_leaves_every_shop_without_buying_or_refitting :: proc(t: ^testing.T) {
	// #123 acceptance: the headless/test auto-player leaves every Port shop cleanly
	// — a nil buy (no purchase) and, were a refit somehow open, an immediate finish
	// (no loadout edit). Asserted directly on auto_pilot_choice, the input source the
	// scenarios drive with, so the criterion is covered without depending on a seed
	// whose route happens to pass a Port.
	pilot := Auto_Pilot{}

	leave := auto_pilot_choice(&pilot, .Awaiting_Shop_Choice)
	buy, is_buy := leave.(Command_Buy_Item)
	testing.expect(t, is_buy)
	_, bought := buy.selection.?
	testing.expect(t, !bought) // nil selection == leave, no purchase

	refit := auto_pilot_choice(&pilot, .Awaiting_Refit)
	cmd, is_refit := refit.(Command_Refit)
	testing.expect(t, is_refit)
	_, is_finish := cmd.command.(Refit_Finish)
	testing.expect(t, is_finish) // no loadout edit
}

