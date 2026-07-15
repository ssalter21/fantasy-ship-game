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

// seed_with_layer_one_stage finds a seed whose map puts primitive T on layer 1,
// and the node it put it on. Layer 1 is the whole of Start's fan-out (every
// layer-1 node is a Start neighbour by construction), so the returned node is
// reachable on the run's first travel choice — which is what a scenario needing
// "arrive at a Trade immediately" is really asking for.
//
// Hunted rather than hard-coded, because *which* recipe a seed deals a given node
// is a generation detail and not a fact a Sim test should depend on: #134's bucket
// draw moved it by baking a port's shop with its recipe instead of in a pass at
// the tail, and #138's catalog will move it again. A scenario that hard-codes the
// seed fails when generation shifts under it, having found nothing wrong.
seed_with_layer_one_stage :: proc($T: typeid) -> (seed: u64, id: Node_ID, ok: bool) {
	for candidate in u64(0) ..< 64 {
		m := run.run_map_create(candidate)
		defer run.run_map_destroy(&m)

		for p in m.nodes {
			if p.layer != 1 || p.kind != .Encounter {
				continue
			}
			if enc, has_encounter := p.encounter.?; has_encounter && first_stage_is(enc, T) {
				return candidate, p.id, true
			}
		}
	}
	return 0, 0, false
}

// seed_with_acceptable_layer_one_trade is seed_with_layer_one_stage narrowed to a
// Trade the *starting ship can actually pay for*, for the scenarios that accept one.
//
// Affordability has to be hunted for rather than assumed, because a Trade draws its
// axis from the roster (issue #136) and two of the six cost Durability — which the
// starting ship's 2 cannot cover at any zone's swing. An accept is all-or-nothing and
// sim_process_trade_choice asserts on a bargain the ship cannot pay, so a scenario
// that hunts only for "a Trade" and then accepts it is one unlucky seed away from
// failing on a premise it never meant to assert. Asking for the trade it needs is
// also the honest reading: these scenarios are about the accept path, not about
// which axes the roster happens to price out of reach (that's the tuning signal
// #136 left visible on purpose).
seed_with_acceptable_layer_one_trade :: proc() -> (seed: u64, id: Node_ID, ok: bool) {
	for candidate in u64(0) ..< 64 {
		m := run.run_map_create(candidate)
		defer run.run_map_destroy(&m)

		for p in m.nodes {
			if p.layer != 1 || p.kind != .Encounter {
				continue
			}
			enc, has_encounter := p.encounter.?
			if !has_encounter {
				continue
			}
			stage, has_stage := run.run_encounter_current(enc)
			if !has_stage {
				continue
			}
			trade, is_trade := stage.(run.Stage_Trade)
			if !is_trade {
				continue
			}
			starting := ship.ship_starting_ship()
			if run.run_trade_can_accept(&starting, trade) {
				return candidate, p.id, true
			}
		}
	}
	return 0, 0, false
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
	case .Awaiting_Option_Choice:
		// Decline every option list (issue #131) — skip an Offer's items, leave a
		// Shop's shelf. One case now covers both, since they are one decision: a nil
		// selection takes nothing, so the scenarios steer purely by travel/battle
		// policy without an item-and-refit detour muddying their assertions.
		return Command(Command_Choose_Option{selection = nil})
	case .Awaiting_Trade_Choice:
		// Reject every Trade (issue #136), for the same reason the pilot declines
		// option lists: accepting would swap a stat drawn from the axis roster, so the
		// ship a scenario ends with would depend on which bargains its route happened
		// to draw rather than on its travel/battle policy. Accepting is exercised
		// directly by the trade tests below.
		return Command(Command_Trade_Choice{accept = false})
	case .Awaiting_Refit:
		// The Auto_Pilot declines every option list, so it never opens a refit; the
		// Phase switch is exhaustive, so finish immediately rather than leaving the
		// case unhandled.
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
	// each (a nil Command_Choose_Option), so no Refit opens and the starting Gun Deck
	// still sits in its Large exposed slot at Goal — the retired auto-replace path
	// would have swapped it.
	res := drive_policy(4, .Avoid_Battles, combat.Command(BOOST_OFFENSIVE))
	testing.expect_value(t, res.status, run.Run_Status.Won)
}

// --- Trade: accept / reject (issue #136) ------------------------------------

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
	seed, trade_node, found := seed_with_layer_one_stage(run.Stage_Trade)
	testing.expect(t, found)

	sim := sim_create(seed)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	opts := tick_travel_options(&sim, &events)
	testing.expect(t, node_id_in(opts, trade_node))

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
	// An acceptable trade specifically: this asserts the accept path, so a bargain
	// the ship cannot pay for would fail on the wrong premise.
	seed, trade_node, found := seed_with_acceptable_layer_one_trade()
	testing.expect(t, found)

	sim := sim_create(seed)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	opts := tick_travel_options(&sim, &events)
	testing.expect(t, node_id_in(opts, trade_node))

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
	seed, trade_node, found := seed_with_layer_one_stage(run.Stage_Trade)
	testing.expect(t, found)

	sim := sim_create(seed)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	opts := tick_travel_options(&sim, &events)
	testing.expect(t, node_id_in(opts, trade_node))

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
	//
	// The seed is hunted rather than named (#134): which recipe a seed deals a given
	// node is a generation detail, so a scenario that needs a Trade beside Start asks
	// for one instead of pinning a seed that happened to have one. It must be an
	// acceptable one, since the retrace is only proven a no-op by a trade that fired.
	seed, trade_node, found := seed_with_acceptable_layer_one_trade()
	testing.expect(t, found)

	sim := sim_create(seed)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	// A layer-1 Trade is a Start neighbour, so it appears in the first emitted
	// option set, and retrace to Start (id 0) and back to it is legal.
	opts := tick_travel_options(&sim, &events) // run start
	testing.expect(t, node_id_in(opts, trade_node))

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
the_run_start_broadcast_withholds_hidden_stages_and_reveals_on_arrival :: proc(t: ^testing.T) {
	// The hiding contract (ADR-0009), now asked of the stage list rather than of the
	// node kind (ADR-0014, issue #131): an encounter's stages are withheld from the
	// public map unless it holds a revealing stage. Withholding is a guaranteed data
	// property of the emitted event, not a presentation courtesy — a masked node's
	// stages are simply absent from the payload.
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

	// Compare the public map against the Sim's private one, node by node — the
	// private map is the truth about what is really there (a test privilege).
	revealing_seen := false
	hidden_seen := false
	for public, i in started.run_map.nodes {
		_, public_has := public.encounter.?
		private, private_has := sim.run_map.nodes[i].encounter.?
		if !private_has {
			testing.expect(t, !public_has) // Start/Goal carry no encounter to withhold
			continue
		}
		if run.run_encounter_reveals(private) {
			// A revealing encounter shows itself before arrival: this is a Port, and it
			// is visible because it holds a Shop stage, not because .Port is exempt.
			testing.expect(t, public_has)
			revealing_seen = true
		} else {
			testing.expect(t, !public_has) // stages withheld pre-arrival
			hidden_seen = true
		}
	}
	// Both branches are actually exercised by this seed's map, so neither assertion
	// above is passing vacuously.
	testing.expect(t, revealing_seen)
	testing.expect(t, hidden_seen)

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
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
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

// install_encounter installs `stages` as node `id`'s encounter (issue #131), so a
// test can put the ship in front of an exact recipe — including a multi-stage one no
// catalog entry authors yet (#138) — without navigating the whole map to a node that
// happens to hold the right thing. Mutating the arena-backed map directly is a
// white-box test privilege.
//
// It asserts the node has a zone, since stages read it as their stakes: a stage list
// planted on Start or Goal would fail deep inside a primitive rather than here.
install_encounter :: proc(sim: ^Sim, id: Node_ID, stages: ..run.Stage) {
	assert(len(stages) > 0 && len(stages) <= run.ENCOUNTER_MAX_STAGES, "test installed a stage list an Encounter cannot hold")
	_, zoned := sim.run_map.nodes[id].zone.?
	assert(zoned, "test installed an encounter on a node with no zone to scale it by")

	encounter := run.Encounter{count = len(stages)}
	for stage, i in stages {
		encounter.stages[i] = stage
	}
	sim.run_map.nodes[id].kind = .Encounter
	sim.run_map.nodes[id].encounter = encounter
	sim.resolved[id] = false
}

// arrive_at puts the ship on node `id` and walks whatever it holds, as
// sim_process_travel does on arrival. It sets awaiting_decision (the walk leaves that
// to sim_tick's tail, which isn't running here) so a test can submit the stage's
// decision next. events holds whatever the walk emitted.
arrive_at :: proc(sim: ^Sim, id: Node_ID, events: ^[dynamic]Event) {
	sim.current = id
	clear(events)
	sim_walk_encounter(sim, events)
	sim.awaiting_decision = true
}

// offer_stage bakes an Offer carrying the first ITEM_OFFER_OPTION_COUNT roster items
// in roster order, so a test knows exactly which fitting each option index holds and
// they are real, placeable fittings.
offer_stage :: proc() -> run.Stage_Offer {
	roster := ship.ship_item_roster()
	offer: run.Stage_Offer
	for i in 0 ..< run.ITEM_OFFER_OPTION_COUNT {
		offer.options[i] = roster[i].fitting
	}
	return offer
}

// arrive_at_offer puts the ship in front of an Offer at node 1 — the shorthand the
// Offer scenarios below open with.
arrive_at_offer :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	install_encounter(sim, 1, offer_stage())
	arrive_at(sim, 1, events)
}

// presented_options returns the option list carried by the last
// Event_Options_Presented in the batch (issue #131), so a test reads what the stage
// actually showed — an Offer's items or a re-staged shop's shelf alike.
presented_options :: proc(events: []Event) -> [STAGE_OPTION_MAX]Maybe(Stage_Option) {
	options: [STAGE_OPTION_MAX]Maybe(Stage_Option)
	for e in events {
		if presented, ok := e.(Event_Options_Presented); ok {
			options = presented.options
		}
	}
	return options
}

// option_name is the fitting name shown at option position i, or "" if nothing is on
// that position (a shelf slot past the deck's tail, or a slot past a narrower
// stage's count).
option_name :: proc(options: [STAGE_OPTION_MAX]Maybe(Stage_Option), i: int) -> string {
	if option, ok := options[i].?; ok {
		return option.fitting.name
	}
	return ""
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

	arrive_at_offer(&sim, &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(1)}))
	ev := refit_tick(&sim, &events)

	roster := ship.ship_item_roster()
	testing.expect_value(t, sim.phase, Phase.Awaiting_Refit)
	testing.expect(t, has_event(ev, Event_Refit_Started))
	incoming, pending := sim.refit_pending.?
	testing.expect(t, pending)
	testing.expect_value(t, incoming.name, roster[1].fitting.name) // the picked item is staged

	// The pick completed the Offer, so the one-stage encounter's walk is over — but
	// the node is marked resolved only once the Refit finishes and the walk resumes,
	// since that is the single place the walk can end.
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[sim.current])
}

@(test)
skipping_an_item_offer_halts_the_encounter_without_opening_a_refit :: proc(t: ^testing.T) {
	// The "or a skip" half, now stated in complete-or-halt terms (ADR-0014): a nil
	// selection **halts** the encounter with no loadout change and returns straight to
	// a travel choice — no Refit, nothing pending. On a one-stage [Offer] a halt and a
	// completion look identical from the outside; what a halt actually costs is
	// asserted by skipping_an_offer_halts_before_a_later_stage below.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	arrive_at_offer(&sim, &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	ev := refit_tick(&sim, &events)

	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[sim.current]) // resolved even though nothing was taken
	testing.expect(t, !has_event(ev, Event_Refit_Started))
	_, pending := sim.refit_pending.?
	testing.expect(t, !pending)
	testing.expect(t, has_event(ev, Event_Travel_Options)) // back to a travel choice
}

@(test)
an_out_of_range_option_selection_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	arrive_at_offer(&sim, &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(STAGE_OPTION_MAX)}))

	testing.expect_assert(t, "Command_Choose_Option selection out of range")
	sim_tick(&sim, &events)
}

@(test)
selecting_a_position_an_offer_does_not_fill_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	// The option list is as wide as the widest stage (STAGE_OPTION_MAX), so an Offer
	// leaves the positions past its own count empty. Selecting one is in range but
	// holds nothing — a driver bug, since presentation is handed the Maybes.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	arrive_at_offer(&sim, &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(run.ITEM_OFFER_OPTION_COUNT)}))

	testing.expect_assert(t, "Command_Choose_Option selected a position with no option on it")
	sim_tick(&sim, &events)
}

@(test)
an_offers_options_are_presented_free :: proc(t: ^testing.T) {
	// An Offer and a Shop share one presented list, and the *only* thing that tells
	// them apart is whether an option carries a price (issue #131). An Offer's don't:
	// a nil cost is what makes sim_process_option_choice skip affordability entirely
	// rather than compare against a zero.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	arrive_at_offer(&sim, &events)

	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	options := presented_options(events[:])
	roster := ship.ship_item_roster()
	for i in 0 ..< run.ITEM_OFFER_OPTION_COUNT {
		option, filled := options[i].?
		testing.expect(t, filled)
		testing.expect_value(t, option.fitting.name, roster[i].fitting.name)
		_, priced := option.cost.?
		testing.expect(t, !priced) // free: no price to check
	}
	// Positions past the Offer's own count hold nothing.
	for i in run.ITEM_OFFER_OPTION_COUNT ..< STAGE_OPTION_MAX {
		_, filled := options[i].?
		testing.expect(t, !filled)
	}
}

// The generic stage walk (issue #131). The scenarios above drive one-stage
// encounters — every recipe in today's catalog is one stage long (catalog.odin), so
// they are also the whole of what the game currently generates. These drive the
// multi-stage recipes the primitives exist for, which #138 will author: the walk has
// to be right *before* there is content that depends on it, or the content lands on
// an untested path.
//
// They use a Trade as the downstream stage throughout, because a Trade's effect is a
// plain durability change that either happened or didn't — the clearest possible read
// on whether the walk reached a stage. It stands in for the Reward that #133 will
// build; "flee a [Fight, Reward] and get no loot" is the same property.

// trade_stage bakes a Trade with a known gain and a **free** cost, so a test reads
// "did the walk reach this stage" straight off the ship's durability without the
// bargain's own affordability rule (run_trade_can_accept, issue #136) entering into
// it: a zero-amount cost is always payable, so accepting is always a legal answer and
// the probe measures the walk and nothing else.
TRADE_GAIN :: 3

trade_stage :: proc() -> run.Stage_Trade {
	return run.Stage_Trade {
		name = "Test Bargain",
		gain = run.Trade_Term{stat = .Durability, amount = TRADE_GAIN},
		cost = run.Trade_Term{stat = .Speed, amount = 0},
	}
}

// accept_trade answers the Trade the walk is parked on, taking the bargain (issue
// #136 gave Trade its accept/reject decision). It asserts the phase first, so a test
// whose walk never reached the Trade fails here — naming the stage it didn't reach —
// rather than further down on a durability that silently never moved.
accept_trade :: proc(t: ^testing.T, sim: ^Sim, events: ^[dynamic]Event) {
	testing.expect_value(t, sim.phase, Phase.Awaiting_Trade_Choice)
	sim_submit_captain_choice(sim, Command(Command_Trade_Choice{accept = true}))
	refit_tick(sim, events)
}

// REWARD_PAYOUT is the treasure the tests' Reward stages grant. A round number
// unlike any real site's payout, so a purse that moved by it moved because the
// Reward paid out and not because some other stage happened to land on the same
// figure.
REWARD_PAYOUT :: 37

reward_stage :: proc() -> run.Stage_Reward {
	return run.Stage_Reward{treasure = REWARD_PAYOUT}
}

// fight_stage bakes a Fight against a real PvE opponent the player can outrun and
// out-last, so a test can drive the battle to whichever ending it wants: a slow
// opponent (Leave Combat unlocks at the baseline round) with `hp` to choose between
// winning and fleeing. The opponent's layout is arena-backed like a generated one, so
// sim_destroy reclaims it.
fight_stage :: proc(sim: ^Sim, hp: int) -> run.Stage_Fight {
	context.allocator = sim_arena_allocator(sim)
	opponent := run.run_pve_opponent(run.Scaling_Site{zone = .Coastal, depth = 0})
	opponent.hp = hp
	opponent.max_hp = hp
	opponent.speed = 1 // slower than the player below, so escape unlocks once the baseline passes
	return run.Stage_Fight{depth = 0, opponent = opponent}
}

// ready_for_battle gives the player enough HP to survive a long battle and enough
// Speed to outrun fight_stage's opponent, so a scenario ends the battle the way it
// means to rather than by sinking.
ready_for_battle :: proc(sim: ^Sim) {
	sim.player.hp = 10_000
	sim.player.max_hp = 10_000
	sim.player.speed = 50
}

// fight_round holds for one round and returns whether the battle is still running.
fight_round :: proc(sim: ^Sim, events: ^[dynamic]Event) -> bool {
	sim_submit_captain_choice(sim, Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}}))
	refit_tick(sim, events)
	return !sim.battle.ended
}

@(test)
a_multi_stage_encounter_walks_every_stage_in_order_and_then_resolves :: proc(t: ^testing.T) {
	// The headline of the walk: an encounter is an ordered stage list, and completing a
	// stage advances the cursor to the next one until the list runs out — at which
	// point the *node* resolves, once. [Trade, Offer, Trade] exercises all of it: three
	// stages, each stopping for a different decision, so the cursor must carry the walk
	// across two resumptions — a Trade's accept and an Offer's pick-then-Refit — and
	// only then run off the end.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	before := sim.player.durability
	install_encounter(&sim, 1, trade_stage(), offer_stage(), trade_stage())

	// Arriving enters stage 0, which parks on its bargain.
	arrive_at(&sim, 1, &events)
	testing.expect(t, !sim.resolved[1]) // stages remain: the encounter is not over

	// Accepting completes the Trade, and the walk carries straight on to stage 1,
	// which stops for a decision of its own.
	accept_trade(t, &sim, &events)
	testing.expect_value(t, sim.player.durability, before + TRADE_GAIN)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	testing.expect(t, has_event(events[:], Event_Options_Presented))
	testing.expect(t, !sim.resolved[1])

	// Picking completes the Offer and opens a Refit; the walk resumes at its finish.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Refit)
	testing.expect_value(t, sim.player.durability, before + TRADE_GAIN) // stage 2 not reached yet

	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)

	// The walk reached the last stage, which parks like the first did.
	accept_trade(t, &sim, &events)

	// It ran off the end and resolved.
	testing.expect_value(t, sim.player.durability, before + 2 * TRADE_GAIN)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1])
	testing.expect(t, has_event(events[:], Event_Travel_Options))
}

@(test)
skipping_an_offer_halts_before_a_later_stage :: proc(t: ^testing.T) {
	// Offer's halt condition (ADR-0014): skipping halts, so nothing downstream of the
	// Offer is reached. On the one-stage [Offer] the scenarios above drive, a halt and
	// a completion are indistinguishable; [Offer, Trade] is what makes the difference
	// observable — the captain who wants none of the items gets none of the Trade
	// either.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	before := sim.player.durability
	install_encounter(&sim, 1, offer_stage(), trade_stage())
	arrive_at(&sim, 1, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)

	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	refit_tick(&sim, &events)

	testing.expect_value(t, sim.player.durability, before) // the halt stopped the walk short
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1]) // halted encounters resolve too: the walk is over either way
}

@(test)
picking_from_an_offer_completes_it_and_the_walk_reaches_the_next_stage :: proc(t: ^testing.T) {
	// The other side of the halt above: a pick **completes** the Offer, so the same
	// [Offer, Trade] does pay out. Together these two are what "the primitive defines
	// completion" means — nothing in the recipe says which of them happens.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	before := sim.player.durability
	install_encounter(&sim, 1, offer_stage(), trade_stage())
	arrive_at(&sim, 1, &events)

	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)

	// The walk reached the Trade — the thing under test — so answering it is what
	// turns "reached" into an observable durability change.
	accept_trade(t, &sim, &events)

	testing.expect_value(t, sim.player.durability, before + TRADE_GAIN)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1])
}

@(test)
rejecting_a_trade_halts_before_a_later_stage :: proc(t: ^testing.T) {
	// Trade's halt condition (ADR-0014): rejecting halts, so nothing downstream of the
	// bargain is reached. #136 gave Trade its accept/reject decision and named this
	// outcome pair, but could not yet enforce it — it predated the cursor, so it marked
	// the node resolved itself and every recipe was one stage long, which made a halt
	// and a completion indistinguishable. [Trade, Offer] is what makes the difference
	// observable, and it is the property #136's own note pointed at: a rejected
	// [Trade, Reward] must not pay out the Reward.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	install_encounter(&sim, 1, trade_stage(), offer_stage())
	arrive_at(&sim, 1, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Trade_Choice)

	sim_submit_captain_choice(&sim, Command(Command_Trade_Choice{accept = false}))
	ev := refit_tick(&sim, &events)

	// The halt stopped the walk short: the Offer behind the Trade was never presented.
	testing.expect(t, !has_event(ev, Event_Options_Presented))
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1]) // halted encounters resolve too: the walk is over either way
}

@(test)
leaving_combat_halts_before_a_later_stage :: proc(t: ^testing.T) {
	// Fight's halt condition (ADR-0014): **Leave Combat halts** — ADR-0006's
	// Speed-gated escape ends the encounter, not just the battle. This is the property
	// the whole stage model was built to express, and it is now stated in the terms it
	// was always meant to be: **no payout for escaping**. The Trade stood in here until
	// #133 built the Reward; the real [Fight, Reward] is the literal case.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	before := sim.player.starting_treasure
	install_encounter(&sim, 1, fight_stage(&sim, 10_000), reward_stage()) // too tough to sink quickly
	arrive_at(&sim, 1, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Battle_Command)

	// Hold until the Speed-gated escape unlocks (ADR-0006: not before the baseline
	// round, and only for the strictly-faster side), then take it.
	for combat.BASELINE_ROUND_COUNT * 2 > sim.battle.round {
		if combat.combat_may_leave(&sim.battle, .A) {
			break
		}
		testing.expect(t, fight_round(&sim, &events)) // the battle must not end on its own
	}
	testing.expect(t, combat.combat_may_leave(&sim.battle, .A))

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = combat.Command_Leave_Combat{}}))
	refit_tick(&sim, &events)

	testing.expect(t, sim.battle.ended)
	testing.expect_value(t, sim.player.starting_treasure, before) // fled: no payout for escaping
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1])
}

@(test)
a_reward_pays_out_and_completes_without_stopping_for_the_captain :: proc(t: ^testing.T) {
	// The Reward primitive whole (#132, #133): a bare [Reward] — drifting salvage — is
	// a legal encounter, its treasure lands in the purse, and it never parks. Every
	// other primitive stops for a decision; a boon has nothing to decline, so arriving
	// *is* the interaction and the walk runs off the end in the same tick.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	before := sim.player.starting_treasure
	install_encounter(&sim, 1, reward_stage())
	arrive_at(&sim, 1, &events)

	testing.expect_value(t, sim.player.starting_treasure, before + REWARD_PAYOUT)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice) // never parked
	testing.expect(t, sim.resolved[1])

	// Presentation learns the purse moved only through Events (ADR-0001), and a Reward
	// is a resolution like any other, so it snapshots too.
	testing.expect(t, has_event(events[:], Event_Ship_Updated))
	testing.expect(t, has_event(events[:], Event_Encounter_Resolved))
}

@(test)
winning_a_fight_completes_it_and_the_reward_behind_it_pays_out :: proc(t: ^testing.T) {
	// The other side of leaving_combat_halts_before_a_later_stage, and the encounter
	// the whole model exists to express: [Fight, Reward] means "win, then loot" with no
	// authored gate saying so. Victory completes the Fight, so the walk carries on to
	// the Reward, which pays out and resolves the node without a further decision.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	before := sim.player.starting_treasure
	install_encounter(&sim, 1, fight_stage(&sim, 1), reward_stage()) // 1 HP: sinks in a round
	arrive_at(&sim, 1, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Battle_Command)

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = BOOST_OFFENSIVE}))
	refit_tick(&sim, &events)

	testing.expect(t, sim.battle.ended)
	testing.expect_value(t, sim.player.starting_treasure, before + REWARD_PAYOUT)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1])
}

@(test)
a_reward_pays_out_behind_a_stage_that_is_not_a_fight :: proc(t: ^testing.T) {
	// #132's "a Reward reads its own node, never its neighbours", made observable:
	// [Offer, Reward] — the Derelict — pays out with no opponent anywhere in the
	// encounter to have looted. Had the payout been derived from the beaten ship's
	// "Spoils" cargo (which the naming invites), this recipe would have nothing to read
	// and the primitive would only work behind a Fight, which is exactly the coupling
	// composable stages exist to avoid.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	before := sim.player.starting_treasure
	install_encounter(&sim, 1, offer_stage(), reward_stage())
	arrive_at(&sim, 1, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	testing.expect_value(t, sim.player.starting_treasure, before) // stage 1 not reached yet

	// Picking completes the Offer and opens a Refit; the walk resumes at its finish and
	// runs through the Reward without stopping again.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)

	testing.expect_value(t, sim.player.starting_treasure, before + REWARD_PAYOUT)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1])
}

@(test)
winning_a_fight_completes_it_and_the_walk_reaches_the_next_stage :: proc(t: ^testing.T) {
	// Victory completes (ADR-0014) — the paying half of [Fight, Reward], and the
	// counterpart to leaving combat above. A one-HP opponent goes down in the first
	// round, so the walk advances onto the Trade.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	before := sim.player.durability
	install_encounter(&sim, 1, fight_stage(&sim, 1), trade_stage())
	arrive_at(&sim, 1, &events)

	for fight_round(&sim, &events) {
		// hold until the opponent goes down
	}

	testing.expect(t, !(.A in sim.battle.escaped)) // won it rather than fled it

	// Victory advanced the cursor onto the Trade; accepting is what makes reaching it
	// visible on the ship.
	accept_trade(t, &sim, &events)
	testing.expect_value(t, sim.player.durability, before + TRADE_GAIN)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1])
}

@(test)
sinking_ends_the_run_without_walking_on_to_a_later_stage :: proc(t: ^testing.T) {
	// Sinking is neither outcome (ADR-0014): it ends the run by permadeath, so the
	// walk stops rather than completing the Fight. Without this the loser of a
	// [Fight, Reward] would be paid on the way down — sim_tick's status check ends the
	// run *after* the round is processed, so the walk would already have applied the
	// next stage to a sunk ship.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	before := sim.player.durability
	sim.player.hp = 1 // goes down in the first round
	sim.player.speed = 50
	install_encounter(&sim, 1, fight_stage(&sim, 10_000), trade_stage())
	arrive_at(&sim, 1, &events)

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}}))
	ev := refit_tick(&sim, &events)

	testing.expect(t, sim.player.hp <= 0)
	testing.expect_value(t, sim.player.durability, before) // sank: the Trade was never reached
	testing.expect_value(t, sim.status, run.Run_Status.Lost)
	testing.expect_value(t, sim.phase, Phase.Ended)
	testing.expect(t, has_event(ev, Event_Run_Ended))
}

// flat_deck bakes a shop deck of the full roster in roster order, every card priced
// flat at `cost` (issue #123) — a stand-in for a generated shop's baked deck with
// predictable affordability and a known top-of-deck order (card at deck position i is
// roster[i]), so the shop tests can assert exactly which card the shelf shows and
// refills with. A real generated deck is a shuffle of this same set (run_port_shop);
// the tests don't need the shuffle, only the deck contract.
flat_deck :: proc(cost: int) -> run.Stage_Shop {
	roster := ship.ship_item_roster()
	shop: run.Stage_Shop
	for i in 0 ..< ship.ITEM_ROSTER_SIZE {
		shop.deck[i] = run.Shop_Item{fitting = roster[i].fitting, cost = cost}
	}
	return shop
}

// arrive_at_shop puts the ship in front of a [Shop] encounter at node `id` — what a
// Port is now (ADR-0014), and the shorthand the shop scenarios below open with.
arrive_at_shop :: proc(sim: ^Sim, id: Node_ID, shop: run.Stage_Shop, events: ^[dynamic]Event) {
	install_encounter(sim, id, shop)
	arrive_at(sim, id, events)
}

// option_cost is the price shown at option position i. It asserts the position is
// filled and priced, so a shop test that silently stopped pricing fails here rather
// than passing on a zero.
option_cost :: proc(options: [STAGE_OPTION_MAX]Maybe(Stage_Option), i: int) -> int {
	option, filled := options[i].?
	assert(filled, "expected an option at this position")
	cost, priced := option.cost.?
	assert(priced, "expected a shop's option to carry a price")
	return cost
}

@(test)
arriving_at_a_generated_port_opens_its_baked_shop :: proc(t: ^testing.T) {
	// The shop tests below stage their own deck (arrive_at_shop) so they can
	// assert exact cards; this one takes a Port straight from the generator and
	// travels to it, because that path is what #134 rewired: a port's stock used to
	// be hung on the Node by a stocking pass at the end of generation, and is now
	// baked as its [Shop] stage's content when its recipe is dealt. Nothing else
	// here checks that a *generated* port still opens a shop, and a fold that
	// dropped the deck would leave every other test passing.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	// Any generated Port will do, and it is reached with arrive_at's white-box jump
	// rather than by travel: no port sits on a zone's entrance layer, so none is a
	// Start neighbour and getting to one honestly would mean pathfinding a scenario
	// this test isn't about. arrive_at makes the same sim_walk_encounter call
	// sim_process_travel's arrival makes.
	//
	// The node is found by kind, which is the one thing .Port still says (#134): how
	// the node was placed. What it *holds* is asked of its stage list, exactly as
	// the walk asks it — the assertions below never mention the kind again.
	port := Node_ID(-1)
	for p in sim.run_map.nodes {
		if p.kind == .Port {
			port = p.id
			break
		}
	}
	testing.expect(t, port >= 0)

	arrive_at(&sim, port, &events)

	// A Shop parks the walk in the option-list decision every option-bearing stage
	// shares (#131), so the deck arrives as presented options rather than a shelf of
	// its own.
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	options := presented_options(events[:])
	filled := 0
	for option in options {
		if _, ok := option.?; ok {
			filled += 1
		}
	}
	testing.expectf(t, filled == run.SHOP_SHELF_SIZE, "generated port %d dealt %d shelf cards, want %d", port, filled, run.SHOP_SHELF_SIZE)
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
	arrive_at_shop(&sim, 1, flat_deck(10), &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(1)}))
	ev := refit_tick(&sim, &events)

	roster := ship.ship_item_roster()
	testing.expect_value(t, sim.phase, Phase.Awaiting_Refit)
	testing.expect(t, has_event(ev, Event_Refit_Started))
	testing.expect_value(t, sim.player.starting_treasure, 40) // 50 - 10 spent
	incoming, pending := sim.refit_pending.?
	testing.expect(t, pending)
	testing.expect_value(t, incoming.name, roster[1].fitting.name) // shelf slot 1 == deck pos 1 == roster[1]

	// A buy leaves the cursor on the Shop, which is the whole of what makes the
	// Refit's finish come back here rather than go to travel (issue #131 retired the
	// remembered Refit_Origin in favour of reading the cursor).
	encounter, _ := sim_current_encounter(&sim)
	testing.expect_value(t, encounter.cursor, 0)
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
	arrive_at_shop(&sim, 1, shop, &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(2)}))
	ev := refit_tick(&sim, &events)

	testing.expect(t, has_event(ev, Event_Purchase_Rejected))
	testing.expect(t, !has_event(ev, Event_Refit_Started))
	testing.expect_value(t, sim.player.starting_treasure, 50) // nothing spent
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice) // shop still open
	_, pending := sim.refit_pending.?
	testing.expect(t, !pending)
}

@(test)
leaving_a_shop_completes_it_and_returns_to_travel :: proc(t: ^testing.T) {
	// The "or leave" half: a nil selection buys nothing, spends nothing, opens no
	// Refit, and returns straight to a travel choice — the only exit to travel.
	// Leaving **completes** the Shop rather than halting it (ADR-0014): a shop cannot
	// be failed, so it is the one primitive with no halt, and a [Shop, Reward] would
	// still pay out to a captain who bought nothing.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.player.starting_treasure = 50
	arrive_at_shop(&sim, 1, flat_deck(10), &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	ev := refit_tick(&sim, &events)

	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect_value(t, sim.player.starting_treasure, 50) // nothing spent
	testing.expect(t, !has_event(ev, Event_Refit_Started))
	testing.expect(t, has_event(ev, Event_Travel_Options)) // back to a travel choice

	// Completed, not halted: the cursor stepped off the Shop onto the end of the
	// list, rather than being jumped there by a halt. Indistinguishable on a
	// one-stage recipe, which is why sim_stage_decline_outcome is asserted directly.
	testing.expect_value(t, sim_stage_decline_outcome(run.Stage(flat_deck(10))), run.Stage_Outcome.Completed)
	testing.expect_value(t, sim_stage_decline_outcome(run.Stage(offer_stage())), run.Stage_Outcome.Halted)
}

@(test)
arriving_at_a_shop_presents_the_top_of_its_deck :: proc(t: ^testing.T) {
	// Arriving at a [Shop] stages a SHOP_SHELF_SIZE shelf off the top of its deck and
	// presents it (issue #123), through the same option list an Offer uses — priced,
	// which is the only difference.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	arrive_at_shop(&sim, 1, flat_deck(15), &events)

	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	options := presented_options(events[:])
	roster := ship.ship_item_roster()
	// The shelf is the top SHOP_SHELF_SIZE deck cards (deck position i is roster[i]),
	// each priced at the deck's flat 15.
	for i in 0 ..< run.SHOP_SHELF_SIZE {
		testing.expect_value(t, option_name(options, i), roster[i].fitting.name)
		testing.expect_value(t, option_cost(options, i), 15)
	}
}

@(test)
a_node_holding_no_encounter_leaves_the_ship_at_a_travel_choice :: proc(t: ^testing.T) {
	// Start and Goal are landmarks by graph position, which no stage list can express
	// (ADR-0014) — so they hold no encounter, and the walk asks nothing about what
	// kind of node it is: finding nothing to walk *is* how a pure waypoint works.
	// This is what lets sim_process_travel hand every arrival to the walk unasked.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.phase = .Awaiting_Option_Choice // anything but travel, so the walk has to set it
	arrive_at(&sim, 0, &events) // node 0 is Start

	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, !has_event(events[:], Event_Options_Presented))
	testing.expect(t, !sim.resolved[0]) // nothing was walked, so nothing resolved
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
	arrive_at_shop(&sim, 1, flat_deck(10), &events)

	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events) // buy: deduct, open the refit (cursor stays on the Shop)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Refit)

	submit_refit(&sim, Refit_Finish{})
	ev := refit_tick(&sim, &events) // finish: the walk re-enters the Shop, refilled

	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice) // back at the shop, not travel
	testing.expect(t, has_event(ev, Event_Options_Presented)) // re-presented refilled
	roster := ship.ship_item_roster()
	options := presented_options(ev)
	// Slot 0 refilled with the next deck card; the bought roster[0] is off the shelf.
	testing.expect_value(t, option_name(options, 0), roster[run.SHOP_SHELF_SIZE].fitting.name)
	for i in 0 ..< run.SHOP_SHELF_SIZE {
		testing.expect(t, option_name(options, i) != roster[0].fitting.name)
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
	arrive_at_shop(&sim, 1, flat_deck(10), &events)

	for _ in 0 ..< 3 {
		testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
		sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
		refit_tick(&sim, &events) // open the buy's refit
		submit_refit(&sim, Refit_Finish{})
		refit_tick(&sim, &events) // finish -> back to the shop
	}
	// Three escalating buys (issue #124): base 10, then 10+step, then 10+2*step.
	spent := 3 * 10 + SHOP_DEPTH_SURCHARGE_STEP * (0 + 1 + 2)
	testing.expect_value(t, sim.player.starting_treasure, 50 - spent)

	// Only Leave exits to travel.
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	ev := refit_tick(&sim, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, has_event(ev, Event_Travel_Options))
}

@(test)
a_shop_is_walked_once_and_resolves_like_any_other_encounter :: proc(t: ^testing.T) {
	// Port repeatability is dropped (#127, ADR-0014), and this is the test that used
	// to say the opposite — a_ports_draw_down_persists_across_visits asserted a
	// revisited Port resumed its shelf, cursor, and purchase count.
	//
	// The generic walk forces the change: an encounter is walked once and marked
	// resolved, so a Shop has no second visit for a draw-down to persist into. A
	// repeatable Port would be the only primitive with a lifecycle of its own —
	// exactly the special-casing the stage model deletes — and Shops aren't
	// Port-exclusive any more, so the answer to "I have treasure now" is meeting
	// another Shop, not returning to this one.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.player.starting_treasure = 50
	arrive_at_shop(&sim, 1, flat_deck(10), &events)

	// Buy the top card, finish its refit, then leave.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events) // back at the shop, refilled
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	refit_tick(&sim, &events) // leave: the Shop completes, the walk finishes
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)

	// The node is resolved, node-level and once — so a retrace back to it re-opens
	// nothing. This is the property that makes the persistence question moot rather
	// than answered: there is no second visit to persist into.
	testing.expect(t, sim.resolved[1])

	// Prove it end to end through the real arrival path rather than the walk directly:
	// re-arriving at a resolved node presents nothing and leaves the ship at travel.
	sim.awaiting_decision = true
	sim.current = 0
	sim_submit_captain_choice(&sim, Command(Command_Travel_To{node_id = 1}))
	clear(&events)
	sim_tick(&sim, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, !has_event(events[:], Event_Options_Presented)) // no shop re-opened
}

@(test)
each_shop_deals_its_own_fresh_shelf :: proc(t: ^testing.T) {
	// Buying at one shop doesn't touch another's shelf — variety comes from checking
	// shop against shop. Under per-visit state (issue #131 retired the per-node
	// port_shelves array) this holds because a visit's working state is discarded as
	// the cursor leaves the stage, so the next Shop reached always deals from its own
	// deck's top.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.player.starting_treasure = 50
	roster := ship.ship_item_roster()

	arrive_at_shop(&sim, 1, flat_deck(10), &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	refit_tick(&sim, &events)

	// Shop 2 is untouched: its shelf opens on its deck's top card at the plain tier
	// price, with the previous shop's purchase count discarded rather than carried in.
	arrive_at_shop(&sim, 2, flat_deck(10), &events)
	options := presented_options(events[:])
	testing.expect_value(t, option_name(options, 0), roster[0].fitting.name)
	testing.expect_value(t, option_cost(options, 0), 10)
}

@(test)
two_shops_in_one_recipe_each_deal_fresh :: proc(t: ^testing.T) {
	// The per-visit state is keyed to the *stage under the cursor*, not to the node —
	// so a recipe holding two Shops deals each its own shelf, which is the honest
	// reading of two shops. Nothing authors [Shop, Shop] yet (#138); this pins the
	// behaviour the cursor-scoped state already gives, so a later catalog entry can't
	// silently resume the first shop's draw-down in the second.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.player.starting_treasure = 100
	roster := ship.ship_item_roster()
	install_encounter(&sim, 1, flat_deck(10), flat_deck(10))
	arrive_at(&sim, 1, &events)

	// Shop 1: buy the top card, then leave to complete it.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	ev := refit_tick(&sim, &events)

	// The walk advanced onto the second Shop, which dealt fresh: its top card is the
	// deck's top again (not the first shop's refill) at the plain tier price (not the
	// first shop's escalated one).
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	options := presented_options(ev)
	testing.expect_value(t, option_name(options, 0), roster[0].fitting.name)
	testing.expect_value(t, option_cost(options, 0), 10)
	testing.expect(t, !sim.resolved[1]) // the encounter isn't over: a stage is still open
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
	arrive_at_shop(&sim, 1, flat_deck(base), &events)

	purse := 100
	for n in 0 ..< 3 {
		want_price := base + SHOP_DEPTH_SURCHARGE_STEP * n

		// The re-presented shelf displays the surcharged price for this depth, so the
		// buyer sees the escalation before committing.
		testing.expect_value(t, option_cost(presented_options(events[:]), 0), want_price)

		testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
		sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
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
the_depth_surcharge_is_scoped_to_one_visit :: proc(t: ^testing.T) {
	// #124's surcharge deepens **within a visit** and no further — the counterpart to
	// a_shop_is_walked_once_and_resolves_like_any_other_encounter, and the other test
	// that used to say the opposite (the_depth_surcharge_persists_across_visits
	// asserted a revisited Port charged from where its depth left off).
	//
	// With repeatability dropped there is no revisit to carry a count into, so the
	// count lives on the visit. What remains true, and is what the surcharge was for
	// (#124): digging *one* shop deep gets expensive, pushing the player to check shop
	// against shop.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	base :: 10
	sim.player.starting_treasure = 100
	arrive_at_shop(&sim, 1, flat_deck(base), &events)

	// One buy at the plain tier price, then leave.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)
	// Still in the same visit, so the next buy is already one step deeper.
	testing.expect_value(t, option_cost(presented_options(events[:]), 0), base + SHOP_DEPTH_SURCHARGE_STEP)

	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	refit_tick(&sim, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect_value(t, sim.player.starting_treasure, 100 - base) // one buy at tier price

	// A different shop starts at the plain tier price: the depth was this visit's, not
	// the run's.
	arrive_at_shop(&sim, 2, flat_deck(base), &events)
	testing.expect_value(t, option_cost(presented_options(events[:]), 0), base)
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
	arrive_at_shop(&sim, 1, flat_deck(base), &events)

	// First buy at the plain tier price succeeds.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)
	remaining := sim.player.starting_treasure
	testing.expect_value(t, remaining, base + SHOP_DEPTH_SURCHARGE_STEP - 1)

	// Second buy: base + step now exceeds the remaining purse, so the surcharge alone
	// refuses it and the shop stays open.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	ev := refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Purchase_Rejected))
	testing.expect(t, !has_event(ev, Event_Refit_Started))
	testing.expect_value(t, sim.player.starting_treasure, remaining) // nothing spent
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice) // shop still open
}

@(test)
the_auto_pilot_declines_every_option_list_without_refitting :: proc(t: ^testing.T) {
	// #123 acceptance: the headless/test auto-player leaves every shop cleanly — a nil
	// selection (no purchase) and, were a refit somehow open, an immediate finish (no
	// loadout edit). Asserted directly on auto_pilot_choice, the input source the
	// scenarios drive with, so the criterion is covered without depending on a seed
	// whose route happens to pass a shop.
	pilot := Auto_Pilot{}

	leave := auto_pilot_choice(&pilot, .Awaiting_Option_Choice)
	choice, is_choice := leave.(Command_Choose_Option)
	testing.expect(t, is_choice)
	_, took := choice.selection.?
	testing.expect(t, !took) // nil selection == decline, no purchase

	refit := auto_pilot_choice(&pilot, .Awaiting_Refit)
	cmd, is_refit := refit.(Command_Refit)
	testing.expect(t, is_refit)
	_, is_finish := cmd.command.(Refit_Finish)
	testing.expect(t, is_finish) // no loadout edit
}

