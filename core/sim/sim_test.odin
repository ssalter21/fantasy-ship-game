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

is_battle_node :: proc(m: run.Map, id: Node_ID) -> bool {
	enc, ok := m.nodes[id].encounter.?
	if !ok {
		return false
	}
	_, is_battle := enc.(run.Encounter_Ship_Battle)
	return is_battle
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
// policy. It reads node kinds/layers off m — a kind-visible copy of the same
// seed's map (a test privilege; the Sim's own public map hides kinds) — only to
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
	case .Awaiting_Refit:
		// A skipped Item Offer never opens a refit, so the Auto_Pilot reaches this
		// only if some other channel (#98 Port shop) ever does; the Phase switch is
		// exhaustive, so finish immediately rather than leaving the case unhandled.
		return Command(Command_Refit{command = Refit_Finish{}})
	case .Ended:
		panic("auto pilot asked for a choice after the run ended")
	}
	panic("unreachable")
}

// auto_pilot_next chooses the next travel destination from the Sim's emitted
// options: among the forward (deeper-layer) options it prefers one whose kind
// matches the policy's current battle preference, falling back to the first
// forward option, and finally to the first option of any kind (never reached
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

	// A kind-visible twin of the Sim's map: run_map_create is deterministic per
	// seed, so its node ids line up with the Sim's, but its encounter kinds are
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
	res := drive_policy(3, .Avoid_Battles, combat.Command(BOOST_OFFENSIVE))
	testing.expect_value(t, res.status, run.Run_Status.Won)
	testing.expect_value(t, res.hp, 20) // untouched: no battle fought
}

@(test)
fighting_a_coastal_ship_battle_can_be_won :: proc(t: ^testing.T) {
	// Fight the first (shallow, Coastal) battle the pilot reaches and boost
	// Offensive, then dodge the rest: the fresh ship wins it and sails on to
	// Goal, taking some damage along the way.
	res := drive_policy(23, .First_Battle_Then_Avoid, combat.Command(BOOST_OFFENSIVE))
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
	res := drive_policy(3, .Avoid_Battles, combat.Command(BOOST_OFFENSIVE))
	testing.expect_value(t, res.status, run.Run_Status.Won)
}

@(test)
stat_trades_on_the_route_permanently_change_stats :: proc(t: ^testing.T) {
	// The battle-dodging route passes through Stat Trades, each applied on arrival
	// with no decision: Durability rises above its starting 2, Speed falls below
	// its starting 4.
	res := drive_policy(3, .Avoid_Battles, combat.Command(BOOST_OFFENSIVE))
	testing.expect_value(t, res.status, run.Run_Status.Won)
	testing.expect(t, res.durability > 2)
	testing.expect(t, res.speed < 4)
}

@(test)
revisiting_a_resolved_encounter_does_not_retrigger_it :: proc(t: ^testing.T) {
	// Retrace is a legal, free routing tool driven straight off the emitted
	// options: arrive at a Stat Trade, retrace to the already-visited Start (the
	// Sim offers it as a backward option), then step forward onto that Stat Trade
	// again. The second arrival must be a no-op, so durability is unchanged by
	// the revisit.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	opts := tick_travel_options(&sim, &events) // run start

	// A layer-1 Stat Trade is a Start neighbor, so it appears in the first
	// emitted option set, and retrace to Start (id 0) and back to it is legal.
	trade := Node_ID(-1)
	for o in opts {
		node := sim.run_map.nodes[o]
		if node.layer != 1 {
			continue
		}
		if enc, ok := node.encounter.?; ok {
			if _, is_trade := enc.(run.Encounter_Stat_Trade); is_trade {
				trade = o
				break
			}
		}
	}
	testing.expect(t, trade >= 0)

	submit_travel(&sim, trade)
	opts = tick_travel_options(&sim, &events) // arrive at the trade; it fires once
	dur_after_trade := sim.player.durability
	testing.expect(t, dur_after_trade > 2) // the trade did fire
	testing.expect(t, node_id_in(opts, 0)) // Start offered as a backward retrace

	submit_travel(&sim, 0)
	opts = tick_travel_options(&sim, &events) // retrace to Start
	testing.expect(t, node_id_in(opts, trade)) // the trade offered again, forward

	submit_travel(&sim, trade)
	tick_travel_options(&sim, &events) // step onto the resolved trade again

	// Re-arriving over the resolved trade changed nothing.
	testing.expect_value(t, sim.player.durability, dur_after_trade)
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
	// Every unvisited Encounter's kind is withheld; landmarks are unaffected.
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
