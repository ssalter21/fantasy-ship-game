package sim

import "../combat"
import "../voyage"
import "../ship"
import "../testutil"
import "core:math/rand"
import "core:testing"

// Two ways to put a ship in front of the thing under test, and the choice between them is
// what most of these scenarios turn on:
//
//   - **Seat it** (sim_seat_at_stage) — the default. The scenario names the exact recipe it
//     means to face and the node it faces it on, so it asserts about the stage and nothing
//     else. Everything downstream of the arrival is real: the walk picks the phase, the tick
//     tail raises awaiting_decision.
//   - **Sail to it** (the Auto_Pilot below, over a fixed seed) — for the scenarios that are
//     about routing itself: it drives run_session by choosing at each step from the legal
//     options the Sim emits on Event_Travel_Options (issue #83), steering by a battle policy.
//
// **A seed names a map, not a scenario.** voyage_map_create bakes each encounter's content off
// the same generator it then builds the graph's edges with, so any change to what a stage draws
// at generation reshapes every seed's map. A sailed scenario whose premise stops holding ("this
// route meets no battles") is re-pointed at a seed where it holds again, not evidence of a
// regression. Assert on the premise, never on a number a particular map happened to produce —
// and where the premise is "the ship is facing an X", seat it rather than hunt a seed for it.

// first_stage_is reports whether e's stage under the cursor is primitive T — how the sailed
// scenarios ask "what does this node do", given a node holds an ordered stage list rather than
// one kind tag (ADR-0014).
first_stage_is :: proc(e: voyage.Encounter, $T: typeid) -> bool {
	stage, ok := voyage.voyage_encounter_current(e)
	if !ok {
		return false
	}
	_, is_t := stage.(T)
	return is_t
}

is_battle_node :: proc(m: voyage.Map, id: Node_ID) -> bool {
	enc, ok := m.nodes[id].encounter.?
	if !ok {
		return false
	}
	return first_stage_is(enc, voyage.Stage_Fight)
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
	m:             voyage.Map,
	current:       Node_ID,
	options:       []Node_ID,
	policy:        Travel_Policy,
	battles_taken: int,
	battle_cmd:    combat.Command,
	may_press:     bool,
	events:        [dynamic]Event,
}

// auto_pilot_battle_command answers a round with the policy's standing order, downgraded to
// Hold when that order is a Press the battle's ration no longer allows (Event_Battle_Menu
// carries what is left). A standing order is a scenario knob, not a tactic, so it repeats
// for as long as it is legal.
auto_pilot_battle_command :: proc(pilot: ^Auto_Pilot) -> combat.Command {
	if _, is_press := pilot.battle_cmd.(combat.Command_Press); is_press && !pilot.may_press {
		return combat.Command_Hold{}
	}
	return pilot.battle_cmd
}

auto_pilot_choice :: proc(data: rawptr, awaiting: Phase) -> Command {
	pilot := cast(^Auto_Pilot)data
	switch awaiting {
	case .Awaiting_Travel_Choice:
		return Command(Command_Travel_To{node_id = auto_pilot_next(pilot)})
	case .Awaiting_Battle_Command:
		return Command(Command_Battle_Choice{combat_command = auto_pilot_battle_command(pilot)})
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
		panic("auto pilot asked for a choice after the voyage ended")
	}
	panic("unreachable")
}

// auto_pilot_next chooses the next travel destination from the Sim's emitted
// options: among the forward (deeper-layer) options it prefers one whose stage
// matches the policy's current battle preference, falling back to the first
// forward option, and finally to the first option of any stage (never reached
// before Haven, since every non-Haven node has a forward edge). Preferring
// forward keeps the route progressing toward Haven instead of retracing.
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
// the fields get_captain_choice plans from — the current node, the Sim's latest
// emitted travel options, and whether the current battle's Press is still in hand.
// A #partial switch: a recording sink only cares about those variants and
// correctly ignores the rest.
auto_pilot_dispatch :: proc(data: rawptr, event: Event) {
	pilot := cast(^Auto_Pilot)data
	append(&pilot.events, event)
	#partial switch e in event {
	case Event_Arrived_At_Node:
		pilot.current = e.node.id
	case Event_Travel_Options:
		pilot.options = e.options
	case Event_Battle_Menu:
		pilot.may_press = e.may_press
	}
}

// Pilot_Result captures the outcome fields a scenario asserts on, read out
// before the Sim's arena is torn down.
Pilot_Result :: struct {
	status:      voyage.Voyage_Status,
	hull:        int,
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

	// An unmasked twin of the Sim's map: voyage_map_create is deterministic per
	// seed, so its node ids line up with the Sim's, but its encounter stages are
	// unmasked so the pilot can classify the options it is offered.
	m := voyage.voyage_map_create(seed)
	defer voyage.voyage_map_destroy(&m)

	pilot := Auto_Pilot{m = m, policy = policy, battle_cmd = battle_cmd}
	defer delete(pilot.events)
	input := Input_Source{data = &pilot, get_captain_choice = auto_pilot_choice}
	sink := Event_Sink{data = &pilot, dispatch = auto_pilot_dispatch}

	run_session(&sim, input, sink)

	res := Pilot_Result {
		status = sim.status,
		hull   = sim.player.hull,
		speed  = sim.player.speed,
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

PRESS_FIRE :: combat.Command_Press{phase = .Fire}
HOLD :: combat.Command_Hold{}

@(test)
a_battle_free_route_reaches_the_haven_and_wins :: proc(t: ^testing.T) {
	// The graph forces a route through some node per layer, but dodging battles
	// at every emitted option gets the ship to Haven unscathed — the redesign's
	// "travel to Haven wins" over a real graph.
	//
	// Re-pinned from seed 9 to seed 17 by the zero-crossing generator (#346): where
	// #135/#136/#138 were content draws sitting *upstream* of edge generation, #346
	// rewrote edge generation itself (monotone forward blocks, adjacent-only
	// laterals), so every seed's routes — and thus which encounters a policy can
	// dodge — reshaped, and a scenario pinned to one seed had to be re-pinned. The
	// scarcity the catalog introduced still holds: a battle-free route to Haven
	// survives on only a handful of seeds. Seed 17 is the lowest that keeps this
	// pair — a battle-free route *and* a winnable first fight (below).
	res := drive_policy(17, .Avoid_Battles, combat.Command(PRESS_FIRE))
	testing.expect_value(t, res.status, voyage.Voyage_Status.Won)
	testing.expect_value(t, res.hull, ship.STARTING_HULL) // untouched: no battle fought
}

@(test)
fighting_a_coastal_ship_battle_can_be_won :: proc(t: ^testing.T) {
	// Fight the first (shallow, Coastal) battle the pilot reaches and press
	// Fire, then dodge the rest: the fresh ship wins it and sails on to
	// Haven, taking some damage along the way.
	//
	// Re-pointed from seed 11 by the hostile roster (#135), then from seed 2 by the
	// recipe catalog (#138), and now from seed 9 to seed 17 by the zero-crossing
	// generator (#346), which #136 called: a new draw sits at or above edge
	// generation, so every seed's map reshapes and a scenario pinned to one has to be
	// re-pinned. Seed 17's first battle is a shallow Coastal one this fresh ship wins
	// for a few Hull (100 -> 96), and seed 17 is deliberately the same map
	// a_battle_free_route_reaches_the_haven_and_wins sails: one map that both permits
	// a route around every fight and rewards taking the first one is a better pair of
	// scenarios than two unrelated seeds.
	res := drive_policy(17, .First_Battle_Then_Avoid, combat.Command(PRESS_FIRE))
	testing.expect_value(t, res.status, voyage.Voyage_Status.Won)
	testing.expect(t, res.battles_won >= 1)
	testing.expect(t, res.hull < ship.STARTING_HULL) // a real fight cost some Hull
}

@(test)
routing_through_every_battle_can_lose_the_voyage :: proc(t: ^testing.T) {
	// Seeking every battle walks into fight after fight; a starting ship bleeds
	// out before Haven — permadeath at 0 Hull, unchanged. Seed 1's map has a
	// battle-seeking course long enough to be lethal.
	res := drive_policy(1, .Seek_Battles, combat.Command(HOLD))
	testing.expect_value(t, res.status, voyage.Voyage_Status.Lost)
	testing.expect_value(t, res.hull, 0)
}

@(test)
skipping_item_offers_on_the_route_leaves_the_loadout_unchanged :: proc(t: ^testing.T) {
	// The battle-dodging route passes through Item Offers; the Auto_Pilot skips
	// each (a nil Command_Choose_Option), so no Refit opens and the starting Gun Deck
	// still sits in its Large exposed slot at Haven — the retired auto-replace path
	// would have swapped it.
	//
	// Re-pointed from seed 4 to seed 9 with the battle-free route above (#138), and
	// now to seed 17 by the zero-crossing generator (#346). The premise was checked
	// rather than assumed on the way: seed 17's dodging route is presented six option
	// lists, so there is something here to skip.
	res := drive_policy(17, .Avoid_Battles, combat.Command(PRESS_FIRE))
	testing.expect_value(t, res.status, voyage.Voyage_Status.Won)
}

// --- Trade: accept / reject (issue #136) ------------------------------------

// presented_trade returns the bargain from the last Event_Trade_Presented in
// events — what the Sim put on screen for the captain to answer.
presented_trade :: proc(events: []Event) -> (trade: voyage.Stage_Trade, ok: bool) {
	for event in events {
		if e, is_trade := event.(Event_Trade_Presented); is_trade {
			trade, ok = e.trade, true
		}
	}
	return
}

// Arriving at a Trade does not apply it (issue #136): the Sim presents the bargain and
// waits.
@(test)
arriving_at_a_trade_presents_the_bargain_instead_of_applying_it :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	before := sim.player
	// The cargo lives in the layout (ADR-0020), which `before` aliases — so snapshot it as
	// an int to assert it genuinely did not move.
	cargo_before := ship.ship_cargo(sim.player)
	sim_seat_at_stage(&sim, 1, &events, trade_stage_costing(TRADE_COST))

	testing.expect_value(t, sim.phase, Phase.Awaiting_Trade_Choice)
	trade, presented := presented_trade(events[:])
	testing.expect(t, presented)
	testing.expect(t, len(trade.name) > 0)

	// Nothing is paid or granted until the captain answers.
	testing.expect_value(t, sim.player.max_hull, before.max_hull)
	testing.expect_value(t, sim.player.speed, before.speed)
	testing.expect_value(t, sim.player.hull, before.hull)
	testing.expect_value(t, ship.ship_cargo(sim.player), cargo_before)
}

// Accepting pays the cost. The gain side's arithmetic (caps, floors, ordering)
// is core/voyage's business and is covered there; what this asserts is the wiring —
// that an accept reaches voyage_apply_trade at all. The cost stat is the roster-
// independent half: every axis's cost is paid in full, never capped.
@(test)
accepting_a_trade_pays_its_cost :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_seat_at_stage(&sim, 1, &events, trade_stage_costing(TRADE_COST))
	trade, presented := presented_trade(events[:])
	testing.expect(t, presented)

	cost_before := voyage.voyage_trade_stat_reading(&sim.player, trade.cost.stat)
	testing.expect(t, voyage.voyage_trade_can_accept(&sim.player, trade))

	sim_submit_captain_choice(&sim, Command(Command_Trade_Choice{accept = true}))
	tick_travel_options(&sim, &events)

	testing.expect_value(t, voyage.voyage_trade_stat_reading(&sim.player, trade.cost.stat), cost_before - trade.cost.amount)
	testing.expect(t, sim.resolved[1])
}

// Rejecting halts the encounter: nothing is paid, nothing is granted, and the
// node still resolves — a rejected bargain is not offered again on a retrace.
@(test)
rejecting_a_trade_changes_nothing_and_still_resolves_the_node :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_seat_at_stage(&sim, 1, &events, trade_stage_costing(TRADE_COST))
	before := sim.player
	cargo_before := ship.ship_cargo(sim.player) // the cargo aliases via `before`; snapshot the int

	sim_submit_captain_choice(&sim, Command(Command_Trade_Choice{accept = false}))
	tick_travel_options(&sim, &events)

	testing.expect_value(t, sim.player.hull, before.hull)
	testing.expect_value(t, sim.player.max_hull, before.max_hull)
	testing.expect_value(t, sim.player.speed, before.speed)
	testing.expect_value(t, ship.ship_cargo(sim.player), cargo_before)
	testing.expect(t, sim.resolved[1])
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
}

@(test)
revisiting_a_resolved_encounter_does_not_retrigger_it :: proc(t: ^testing.T) {
	// Retrace is a legal, free routing tool driven straight off the emitted options: seat in
	// front of a Trade, accept it, retrace to the already-visited Start (the Sim offers it as
	// a backward option), then step forward onto that Trade again. The second arrival must be
	// a no-op — no bargain presented, no stat touched.
	//
	// The retrace itself is sailed rather than seated, since a resolved node's *arrival* is
	// what is on trial here. It is only proven a no-op by a trade that fired, so the bargain
	// is priced and accepted.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_seat_at_stage(&sim, 1, &events, trade_stage_costing(TRADE_COST))
	trade, presented := presented_trade(events[:])
	testing.expect(t, presented)

	cost_before := voyage.voyage_trade_stat_reading(&sim.player, trade.cost.stat)
	sim_submit_captain_choice(&sim, Command(Command_Trade_Choice{accept = true}))
	opts := tick_travel_options(&sim, &events)

	ship_after_trade := sim.player
	cargo_after_trade := ship.ship_cargo(sim.player) // aliased via ship_after_trade; snapshot the int
	testing.expect(t, voyage.voyage_trade_stat_reading(&sim.player, trade.cost.stat) < cost_before) // the trade did fire
	testing.expect(t, node_id_in(opts, 0)) // Start offered as a backward retrace

	submit_travel(&sim, 0)
	opts = tick_travel_options(&sim, &events) // retrace to Start
	testing.expect(t, node_id_in(opts, 1)) // the trade offered again, forward

	submit_travel(&sim, 1)
	clear(&events)
	tick_travel_options(&sim, &events) // step onto the resolved trade again

	// Re-arriving over the resolved trade presented nothing and changed nothing.
	_, presented_again := presented_trade(events[:])
	testing.expect(t, !presented_again)
	testing.expect_value(t, sim.player.max_hull, ship_after_trade.max_hull)
	testing.expect_value(t, sim.player.speed, ship_after_trade.speed)
	testing.expect_value(t, sim.player.hull, ship_after_trade.hull)
	testing.expect_value(t, ship.ship_cargo(sim.player), cargo_after_trade)
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
	sim_tick(&sim, &events) // voyage start: awaiting a travel choice

	// Haven (the last, deepest node) is never adjacent to Start.
	illegal := Node_ID(len(sim.voyage_map.nodes) - 1)
	sim_submit_captain_choice(&sim, Command(Command_Travel_To{node_id = illegal}))

	testing.expect_assert(t, "not a legal neighbor")
	sim_tick(&sim, &events)
}

@(test)
the_voyage_start_broadcast_withholds_hidden_stages_and_reveals_on_arrival :: proc(t: ^testing.T) {
	// The hiding contract (ADR-0009), now asked of the stage list rather than of the
	// node kind (ADR-0014, issue #131): an encounter's stages are withheld from the
	// public map unless it holds a revealing stage. Withholding is a guaranteed data
	// property of the emitted event, not a presentation courtesy — a masked node's
	// stages are simply absent from the payload.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_tick(&sim, &events) // voyage start

	started: Event_Voyage_Started
	found := false
	for event in events {
		if s, ok := event.(Event_Voyage_Started); ok {
			started = s
			found = true
		}
	}
	testing.expect(t, found)

	// Graph shape is present: adjacency parallel to nodes.
	testing.expect_value(t, len(started.voyage_map.edges), len(started.voyage_map.nodes))

	// Compare the public map against the Sim's private one, node by node — the
	// private map is the truth about what is really there (a test privilege).
	revealing_seen := false
	hidden_seen := false
	for public, i in started.voyage_map.nodes {
		_, public_has := public.encounter.?
		private, private_has := sim.voyage_map.nodes[i].encounter.?
		if !private_has {
			testing.expect(t, !public_has) // Start/Haven carry no encounter to withhold
			continue
		}
		if voyage.voyage_encounter_reveals(private) {
			// A revealing encounter shows itself before arrival: this is a Port, and it
			// is visible because it **opens** on a Shop stage (ADR-0016), not because
			// .Port is exempt. A merchant carries a Shop too and stays masked below.
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
	for v in sim.voyage_map.edges[0] {
		if sim.voyage_map.nodes[v].kind == .Encounter {
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
a_command_that_does_not_match_the_awaited_phase_traps_on_the_next_tick :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)
	sim_tick(&sim, &events) // first tick: awaiting a travel choice

	// A mismatched Command is accepted at submit and trapped when the Phase's processor
	// unwraps it on the next tick (sim_take_pending) — not by a separate check at submit.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	testing.expect_assert(t, "the pending command does not match the phase awaiting it")
	sim_tick(&sim, &events)
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

// A vacated slot backfills with a hold rather than going empty, so "did this refit
// free the slot?" is asked as "does it carry nothing but a bare hold?".
slot_is_free :: proc(sim: ^Sim, slot: int) -> bool {
	fitting, ok := sim.player.layout[slot].fitting.?
	return ok && ship.ship_fitting_is_hold(fitting)
}

@(test)
a_refit_sequence_installs_moves_and_removes_fittings_and_enforces_the_fit_rule :: proc(t: ^testing.T) {
	// Drive a full loadout-editing sequence over the starting ship and assert
	// both the resulting layout and that every illegal placement is refused
	// without disturbing it (issue #95's acceptance test). Starting slots:
	//   0 top deck (M) Captain's Quarters   4 hold 1 (M) Cargo
	//   1 top crew (M) Top Crew             5 hold 2 (S) Cargo
	//   2 gun deck (L) Gun Deck             6 hold 3 (S) Cargo
	//   3 forecastle (L) empty (headroom)  7 hold 4 (S) Cargo
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

	// Install into an occupied same-size slot (Large slot 2 holds the Gun Deck): refused.
	submit_refit(&sim, Refit_Install{slot = 2})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Refit_Rejected))
	testing.expect_value(t, fitting_name_at(&sim, 2), "Gun Deck")

	// Move the Gun Deck (Large) from slot 2 into the Large forecastle (slot 3), which
	// carries a bare hold out of the starting stow. A hold is free and unowned, so it
	// is a legal destination — and the vacated slot 2 backfills with one in turn.
	submit_refit(&sim, Refit_Move{from = 2, to = 3})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Fitting_Moved))
	testing.expect(t, slot_is_free(&sim, 2))
	testing.expect_value(t, fitting_name_at(&sim, 3), "Gun Deck")

	// Land the pending Upgraded Gun Deck in the freed Large slot 2. It goes in as a
	// Replace, not an Install: the slot carries a backfilled hold, and Install still
	// refuses an occupied slot.
	submit_refit(&sim, Refit_Replace{slot = 2})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Fitting_Installed))
	testing.expect_value(t, fitting_name_at(&sim, 2), "Upgraded Gun Deck")
	_, pending_after_install := sim.refit_pending.?
	testing.expect(t, !pending_after_install) // consumed

	// With nothing pending, a placement is refused whatever the slot: no incoming item
	// is open outside a stage's grant (ADR-0012). Free a Small slot first — removing
	// its hold discards it (no inventory) and backfills a fresh one.
	submit_refit(&sim, Refit_Remove{slot = 5})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Fitting_Removed))
	testing.expect(t, slot_is_free(&sim, 5))
	submit_refit(&sim, Refit_Replace{slot = 5})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Refit_Rejected))
	testing.expect(t, slot_is_free(&sim, 5)) // nothing installed

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
a_refit_refuses_to_install_an_exposure_requiring_fitting_below_deck :: proc(t: ^testing.T) {
	// requires_exposed is a fit-legality check standing beside the size gate (#407): an
	// item that must be seen to work cannot be installed below deck, whatever its size.
	// That is what makes concealment scarce and contested — the captain who wants a
	// concealed build pays for it in the items they can no longer fly. Starting slots:
	// 0 top deck (M) Exposed, 4 hold 1 (M) Concealed.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	colors := ship.Fitting{name = "Flagship Colors", size = .Medium, bulk = 20, requires_exposed = true}
	sim_open_refit(&sim, colors, &events)

	// The concealed Medium hold: the size matches and the placement is still refused.
	submit_refit(&sim, Refit_Replace{slot = 4})
	ev := refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Refit_Rejected))
	testing.expect_value(t, fitting_name_at(&sim, 4), "Cargo")
	_, still_pending := sim.refit_pending.?
	testing.expect(t, still_pending)

	// The exposed Medium top deck: same item, same size, accepted.
	submit_refit(&sim, Refit_Replace{slot = 0})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Fitting_Installed))
	testing.expect_value(t, fitting_name_at(&sim, 0), "Flagship Colors")

	// And it cannot be smuggled below deck after the fact: a Move into the concealed
	// hold is refused on the same gate, leaving both slots as they stood.
	submit_refit(&sim, Refit_Move{from = 0, to = 4})
	ev = refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Refit_Rejected))
	testing.expect_value(t, fitting_name_at(&sim, 0), "Flagship Colors")
	testing.expect_value(t, fitting_name_at(&sim, 4), "Cargo")
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

// --- At anchor: free refit between encounters (#317) ------------------------
//
// The between-encounters await accepts a free Command_Refit as well as a Command_Travel_To
// over the one Awaiting_Travel_Choice phase (ADR-0020, ADR-0024's persistent Build at Home).
// These drive that Sim plumbing directly: seat nothing, just take the voyage-start tick to a
// travel choice and submit a refit against the starting layout in place.
//
// Starting slots (as the refit-sequence test above documents): 2 gun deck (L) Gun Deck,
// 3 forecastle (L) empty headroom, 5 hold 2 (S) Cargo.

@(test)
a_free_refit_move_at_anchor_applies_and_stays_awaiting_travel :: proc(t: ^testing.T) {
	// A Move rearranges the loadout in place with no incoming item, and the Sim comes right
	// back awaiting a travel choice with the destinations re-broadcast — the surface stays
	// live between encounters.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_tick(&sim, &events) // voyage start → at anchor, awaiting a travel choice
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)

	submit_refit(&sim, Refit_Move{from = 2, to = 3})
	ev := refit_tick(&sim, &events)

	testing.expect(t, has_event(ev, Event_Fitting_Moved))
	testing.expect(t, has_event(ev, Event_Ship_Updated))
	testing.expect(t, slot_is_free(&sim, 2))
	testing.expect_value(t, fitting_name_at(&sim, 3), "Gun Deck")
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, has_event(ev, Event_Travel_Options)) // options re-emitted: still at anchor
	testing.expect(t, sim.awaiting_decision)
}

@(test)
a_free_refit_remove_at_anchor_applies_and_stays_awaiting_travel :: proc(t: ^testing.T) {
	// A Remove discards a fitting (no inventory, ADR-0012) and likewise stays at anchor.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_tick(&sim, &events) // voyage start
	submit_refit(&sim, Refit_Remove{slot = 5})
	ev := refit_tick(&sim, &events)

	testing.expect(t, has_event(ev, Event_Fitting_Removed))
	testing.expect(t, slot_is_free(&sim, 5))
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, has_event(ev, Event_Travel_Options))
}

@(test)
a_free_refit_install_at_anchor_is_rejected :: proc(t: ^testing.T) {
	// With nothing to place, an Install at anchor is refused — the same "nothing pending"
	// rejection a granted Refit gives, since no incoming item is open outside a stage's grant
	// (ADR-0012). The layout is untouched and the Sim stays at anchor.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_tick(&sim, &events) // voyage start
	submit_refit(&sim, Refit_Replace{slot = 3}) // the Large forecastle's bare hold
	ev := refit_tick(&sim, &events)

	testing.expect(t, has_event(ev, Event_Refit_Rejected))
	testing.expect(t, slot_is_free(&sim, 3)) // nothing landed
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
}

@(test)
travelling_from_anchor_still_sails :: proc(t: ^testing.T) {
	// A Command_Travel_To at anchor routes to the travel processor, not the refit one, so the
	// ship arrives at the chosen node — sailing is unchanged by widening the await.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	opts := tick_travel_options(&sim, &events) // voyage start → options
	testing.expect(t, len(opts) > 0)
	dest := opts[0]

	submit_travel(&sim, dest)
	clear(&events)
	sim_tick(&sim, &events)

	testing.expect(t, has_event(events[:], Event_Arrived_At_Node))
	testing.expect_value(t, sim.current, dest)
}

// offer_stage bakes an Offer carrying the first ITEM_OFFER_OPTION_COUNT roster items
// in roster order, so a test knows exactly which fitting each option index holds and
// they are real, placeable fittings.
offer_stage :: proc() -> voyage.Stage_Offer {
	roster := ship.ship_item_roster()
	offer: voyage.Stage_Offer
	for i in 0 ..< voyage.ITEM_OFFER_OPTION_COUNT {
		offer.options[i] = roster[i].fitting
	}
	return offer
}

// seat_at_offer seats the ship in front of an Offer at node 1 — the shorthand the Offer
// scenarios below open with.
seat_at_offer :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	sim_seat_at_stage(sim, 1, events, offer_stage())
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
// that position (a shelf slot past the stock's tail, or a slot past a narrower
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

	seat_at_offer(&sim, &events)
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

	seat_at_offer(&sim, &events)
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

	seat_at_offer(&sim, &events)
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

	seat_at_offer(&sim, &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(voyage.ITEM_OFFER_OPTION_COUNT)}))

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

	seat_at_offer(&sim, &events)

	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	options := presented_options(events[:])
	roster := ship.ship_item_roster()
	for i in 0 ..< voyage.ITEM_OFFER_OPTION_COUNT {
		option, filled := options[i].?
		testing.expect(t, filled)
		testing.expect_value(t, option.fitting.name, roster[i].fitting.name)
		_, priced := option.cost.?
		testing.expect(t, !priced) // free: no price to check
	}
	// Positions past the Offer's own count hold nothing.
	for i in voyage.ITEM_OFFER_OPTION_COUNT ..< STAGE_OPTION_MAX {
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
// plain Max Hull change that either happened or didn't — the clearest possible read
// on whether the walk reached a stage. It stands in for the Reward that #133 will
// build; "flee a [Fight, Reward] and get no loot" is the same property.

// trade_stage bakes a Trade with a known gain and a **free** cost, so a test reads
// "did the walk reach this stage" straight off the ship's Max Hull without the
// bargain's own affordability rule (voyage_trade_can_accept, issue #136) entering into
// it: a zero-amount cost is always payable, so accepting is always a legal answer and
// the probe measures the walk and nothing else.
TRADE_GAIN :: 3

// TRADE_COST is what trade_stage_costing charges, small enough that the starting ship's
// Max Hull covers it — the scenarios that assert the accept path pay a real price, and a
// bargain no ship could pay would fail them on the wrong premise.
TRADE_COST :: 2

trade_stage :: proc() -> voyage.Stage_Trade {
	return trade_stage_costing(0)
}

// trade_stage_costing is trade_stage priced: it charges `cost` of Hull, the axis a starting
// ship can always cover, so a scenario about accepting or rejecting names the price it wants
// rather than hunting a map whose generated bargain happens to be payable. The gain is Max
// Hull, which nothing else in a walk moves — unlike Hull (combat) or Cargo (loot), either of
// which would let an unrelated stage forge the "we got here" signal.
trade_stage_costing :: proc(cost: int) -> voyage.Stage_Trade {
	return voyage.Stage_Trade {
		name = "Test Bargain",
		gain = voyage.Trade_Term{stat = .Max_Hull, amount = TRADE_GAIN},
		cost = voyage.Trade_Term{stat = .Hull, amount = cost},
	}
}

// accept_trade answers the Trade the walk is parked on, taking the bargain (issue
// #136 gave Trade its accept/reject decision). It asserts the phase first, so a test
// whose walk never reached the Trade fails here — naming the stage it didn't reach —
// rather than further down on a Max Hull that silently never moved.
accept_trade :: proc(t: ^testing.T, sim: ^Sim, events: ^[dynamic]Event) {
	testing.expect_value(t, sim.phase, Phase.Awaiting_Trade_Choice)
	sim_submit_captain_choice(sim, Command(Command_Trade_Choice{accept = true}))
	refit_tick(sim, events)
}

// REWARD_PAYOUT is the cargo the tests' Reward stages grant. A round number
// unlike any real site's payout, so a cargo that moved by it moved because the
// Reward paid out and not because some other stage happened to land on the same
// figure.
REWARD_PAYOUT :: 37

reward_stage :: proc() -> voyage.Stage_Reward {
	return voyage.Stage_Reward{cargo = REWARD_PAYOUT}
}

// fight_stage bakes a Fight against a real PvE opponent the player can outrun and
// out-last, so a test can drive the battle to whichever ending it wants: a slow
// opponent (Break Off unlocks at the baseline round) with `hull` to choose between
// winning and fleeing. The opponent's layout is arena-backed like a generated one, so
// sim_destroy reclaims it.
//
// Which archetype the roster deals here (#135) doesn't matter — hull and speed are
// overridden below, so the draw only decides the loadout, and these scenarios are
// about the Sim's walk rather than the fight's numbers. A fixed seed keeps them from
// changing under a roster edit.
fight_stage :: proc(sim: ^Sim, hull: int) -> voyage.Stage_Fight {
	context.allocator = sim_arena_allocator(sim)
	state := rand.create(0)
	opponent := voyage.voyage_pve_opponent(voyage.Scaling_Site{zone = .Coastal, depth = 0}, rand.default_random_generator(&state))
	opponent.hull = hull
	opponent.max_hull = hull
	opponent.speed = 1 // slower than the player below, so escape unlocks once the baseline passes
	return voyage.Stage_Fight{opponent = opponent}
}

// ready_for_battle gives the player enough Hull to survive a long battle and enough
// Speed to outrun fight_stage's opponent, so a scenario ends the battle the way it
// means to rather than by sinking.
ready_for_battle :: proc(sim: ^Sim) {
	sim.player.hull = 10_000
	sim.player.max_hull = 10_000
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

	before := sim.player.max_hull

	// Seating enters stage 0, which parks on its bargain.
	sim_seat_at_stage(&sim, 1, &events, trade_stage(), offer_stage(), trade_stage())
	testing.expect(t, !sim.resolved[1]) // stages remain: the encounter is not over

	// Accepting completes the Trade, and the walk carries straight on to stage 1,
	// which stops for a decision of its own.
	accept_trade(t, &sim, &events)
	testing.expect_value(t, sim.player.max_hull, before + TRADE_GAIN)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	testing.expect(t, has_event(events[:], Event_Options_Presented))
	testing.expect(t, !sim.resolved[1])

	// Picking completes the Offer and opens a Refit; the walk resumes at its finish.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Refit)
	testing.expect_value(t, sim.player.max_hull, before + TRADE_GAIN) // stage 2 not reached yet

	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)

	// The walk reached the last stage, which parks like the first did.
	accept_trade(t, &sim, &events)

	// It ran off the end and resolved.
	testing.expect_value(t, sim.player.max_hull, before + 2 * TRADE_GAIN)
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

	before := sim.player.max_hull
	sim_seat_at_stage(&sim, 1, &events, offer_stage(), trade_stage())
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)

	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	refit_tick(&sim, &events)

	testing.expect_value(t, sim.player.max_hull, before) // the halt stopped the walk short
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1]) // halted encounters resolve too: the walk is over either way
}

// entered_stages collects every Event_Stage_Entered in the batch, in order — the walk's
// account of where its cursor went (issue #139).
entered_stages :: proc(events: []Event) -> [dynamic]Event_Stage_Entered {
	entered: [dynamic]Event_Stage_Entered
	for e in events {
		if stage, ok := e.(Event_Stage_Entered); ok {
			append(&entered, stage)
		}
	}
	return entered
}

// halt_event returns the batch's Event_Encounter_Halted, or ok=false if the walk did not
// halt in it.
halt_event :: proc(events: []Event) -> (halt: Event_Encounter_Halted, ok: bool) {
	for e in events {
		if h, is_halt := e.(Event_Encounter_Halted); is_halt {
			return h, true
		}
	}
	return {}, false
}

@(test)
the_walk_announces_its_cursor_at_every_stage :: proc(t: ^testing.T) {
	// Issue #139: presentation is handed the encounter's *shape* on arrival, but the walk
	// advances the Sim's private map, so where the cursor is has to be said out loud or a
	// multi-stage encounter reads as unrelated popups. [Offer, Trade] is walked all the
	// way through, so both stages must announce themselves with their own index.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_seat_at_stage(&sim, 1, &events, offer_stage(), trade_stage())

	first := entered_stages(events[:])
	defer delete(first)
	testing.expect_value(t, len(first), 1) // the walk parks on the Offer and says so
	testing.expect_value(t, first[0].kind, voyage.Stage_Kind.Offer)
	testing.expect_value(t, first[0].index, 0)
	testing.expect_value(t, first[0].count, 2)

	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	ev := refit_tick(&sim, &events)

	// The Refit's finish resumes the walk, which enters the Trade — the cursor moved, and
	// the event is the only way presentation could know it.
	second := entered_stages(ev)
	defer delete(second)
	testing.expect_value(t, len(second), 1)
	testing.expect_value(t, second[0].kind, voyage.Stage_Kind.Trade)
	testing.expect_value(t, second[0].index, 1)
	testing.expect_value(t, second[0].count, 2)
}

@(test)
a_halt_is_announced_and_a_completion_is_not :: proc(t: ^testing.T) {
	// Issue #139's asymmetry, which is the whole design of Event_Encounter_Halted: a
	// completion shows itself (the next stage arrives, or the map comes back), a halt is
	// the outcome with *nothing* to show — the stages behind it simply never happen. So
	// the same [Offer, Trade] must announce the skip and stay silent on the pick.
	skipped := sim_create(0)
	defer sim_destroy(&skipped)
	events: [dynamic]Event
	defer delete(events)

	sim_seat_at_stage(&skipped, 1, &events, offer_stage(), trade_stage())
	sim_submit_captain_choice(&skipped, Command(Command_Choose_Option{selection = nil}))
	ev := refit_tick(&skipped, &events)

	halt, halted := halt_event(ev)
	testing.expect(t, halted)
	testing.expect_value(t, halt.at, voyage.Stage_Kind.Offer)
	testing.expect_value(t, halt.index, 0) // index and count are what pick the forfeited
	testing.expect_value(t, halt.count, 2) // stages out: everything after 0, i.e. the Trade

	// And the Trade never announced itself, which is what "the halt cost you something"
	// means from presentation's side — there is nothing on screen to have shown it.
	entered := entered_stages(ev)
	defer delete(entered)
	testing.expect_value(t, len(entered), 0)

	taken := sim_create(0)
	defer sim_destroy(&taken)
	sim_seat_at_stage(&taken, 1, &events, offer_stage(), trade_stage())
	sim_submit_captain_choice(&taken, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&taken, &events)
	submit_refit(&taken, Refit_Finish{})
	ev = refit_tick(&taken, &events)

	_, completion_announced := halt_event(ev)
	testing.expect(t, !completion_announced)
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

	before := sim.player.max_hull
	sim_seat_at_stage(&sim, 1, &events, offer_stage(), trade_stage())

	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)

	// The walk reached the Trade — the thing under test — so answering it is what
	// turns "reached" into an observable Max Hull change.
	accept_trade(t, &sim, &events)

	testing.expect_value(t, sim.player.max_hull, before + TRADE_GAIN)
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

	sim_seat_at_stage(&sim, 1, &events, trade_stage(), offer_stage())
	testing.expect_value(t, sim.phase, Phase.Awaiting_Trade_Choice)

	sim_submit_captain_choice(&sim, Command(Command_Trade_Choice{accept = false}))
	ev := refit_tick(&sim, &events)

	// The halt stopped the walk short: the Offer behind the Trade was never presented.
	testing.expect(t, !has_event(ev, Event_Options_Presented))
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1]) // halted encounters resolve too: the walk is over either way
}

@(test)
breaking_off_halts_before_a_later_stage :: proc(t: ^testing.T) {
	// Fight's halt condition (ADR-0014): **Break Off halts** — ADR-0006's
	// Speed-gated escape ends the encounter, not just the battle. This is the property
	// the whole stage model was built to express, and it is now stated in the terms it
	// was always meant to be: **no payout for escaping**. The Trade stood in here until
	// #133 built the Reward; the real [Fight, Reward] is the literal case.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	before := ship.ship_cargo(sim.player)
	sim_seat_at_stage(&sim, 1, &events, fight_stage(&sim, 10_000), reward_stage()) // too tough to sink quickly
	testing.expect_value(t, sim.phase, Phase.Awaiting_Battle_Command)

	// Hold until the Speed-gated escape unlocks (ADR-0006: not before the baseline
	// round, and only for the strictly-faster side), then take it.
	for combat.BASELINE_ROUND_COUNT * 2 > sim.battle.round {
		if combat.combat_may_break_off(&sim.battle, .A) {
			break
		}
		testing.expect(t, fight_round(&sim, &events)) // the battle must not end on its own
	}
	testing.expect(t, combat.combat_may_break_off(&sim.battle, .A))

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = combat.Command_Break_Off{}}))
	ev := refit_tick(&sim, &events)

	testing.expect(t, sim.battle.ended)
	testing.expect_value(t, ship.ship_cargo(sim.player), before) // fled: no payout for escaping
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1])

	// And the escape is **said out loud** (issue #139). The cargo above is the model
	// working; this is the captain being able to tell that it worked. Without it, fleeing
	// a [Fight, Reward] is indistinguishable from a plain [Fight] ending — the Reward just
	// silently never happens — which is the difference between learning the rule and
	// filing a bug. index/count are what let presentation name the Loot as forfeited.
	halt, halted := halt_event(ev)
	testing.expect(t, halted)
	testing.expect_value(t, halt.at, voyage.Stage_Kind.Fight)
	testing.expect_value(t, halt.index, 0)
	testing.expect_value(t, halt.count, 2)

	// The Reward never announced itself either, which is the same fact from the other
	// side: there was no stage for presentation to have drawn.
	entered := entered_stages(ev)
	defer delete(entered)
	testing.expect_value(t, len(entered), 0)
}

@(test)
a_reward_pays_out_and_completes_without_stopping_for_the_captain :: proc(t: ^testing.T) {
	// The Reward primitive whole (#132, #133): a bare [Reward] — drifting salvage — is
	// a legal encounter, its cargo lands in the cargo, and it never parks. Every
	// other primitive stops for a decision; a boon has nothing to decline, so arriving
	// *is* the interaction and the walk runs off the end in the same tick.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	before := ship.ship_cargo(sim.player)
	sim_seat_at_stage(&sim, 1, &events, reward_stage())

	testing.expect_value(t, ship.ship_cargo(sim.player), before + REWARD_PAYOUT)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice) // never parked
	testing.expect(t, sim.resolved[1])

	// Presentation learns the cargo moved only through Events (ADR-0001). The node's
	// ghost rides along here because a bare [Reward] *is* the whole encounter — its
	// payout and the walk's end are the same tick — not because the payout emits one;
	// the cadence tests above are where that distinction is asked properly.
	testing.expect(t, has_event(events[:], Event_Ship_Updated))
	testing.expect(t, has_event(events[:], Event_Encounter_Resolved))
}

@(test)
winning_a_fight_completes_it_and_the_reward_behind_it_pays_out :: proc(t: ^testing.T) {
	// The other side of breaking_off_halts_before_a_later_stage, and the encounter
	// the whole model exists to express: [Fight, Reward] means "win, then loot" with no
	// authored gate saying so. Victory completes the Fight, so the walk carries on to
	// the Reward, which pays out and resolves the node without a further decision.
	//
	// The Fight now *also* pays the wreck's hold (#159), so a real [Fight, Reward] pays
	// twice — accepted, and left to #127's tuning fog. Here the wreck is emptied so this
	// stays about the walk and the Reward; the wreck payout has its own test below.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	before := ship.ship_cargo(sim.player)
	fight := fight_stage(&sim, 1) // 1 Hull: sinks in a round
	ship.ship_stow_cargo(fight.opponent.layout, 0) // broke wreck: isolate the Reward as the only payout
	sim_seat_at_stage(&sim, 1, &events, fight, reward_stage())
	testing.expect_value(t, sim.phase, Phase.Awaiting_Battle_Command)

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = PRESS_FIRE}))
	refit_tick(&sim, &events)

	testing.expect(t, sim.battle.ended)
	testing.expect_value(t, ship.ship_cargo(sim.player), before + REWARD_PAYOUT)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1])
}

@(test)
winning_a_fight_pays_the_sunk_opponents_hold_into_the_player :: proc(t: ^testing.T) {
	// #159's paying case, end to end: sinking a ship gives you its hold. A bare [Fight]
	// with no Reward behind it isolates the payout to the wreck itself — the Fight, not
	// a loot stage, is what pays — and the cargo rises by the cargo that was aboard.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	before := ship.ship_cargo(sim.player) // 50 of a 90 capacity: room for the hold below with no overflow
	fight := fight_stage(&sim, 1) // 1 Hull: sinks in a round
	WRECK_HOLD :: 20
	ship.ship_stow_cargo(fight.opponent.layout, WRECK_HOLD) // a controlled hold within the player's headroom
	sim_seat_at_stage(&sim, 1, &events, fight)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Battle_Command)

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = PRESS_FIRE}))
	refit_tick(&sim, &events)

	testing.expect(t, sim.battle.ended)
	testing.expect_value(t, ship.ship_cargo(sim.player), before + WRECK_HOLD) // looted the wreck, within capacity
	testing.expect(t, has_event(events[:], Event_Ship_Updated)) // presentation learns the cargo moved (ADR-0001)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1]) // a bare [Fight] resolves the node on victory
}

@(test)
winning_a_fight_surfaces_the_wreck_cargo_that_overflows_the_hold :: proc(t: ^testing.T) {
	// #201's payout-overflow surfacing: a wreck richer than the player's remaining
	// headroom pays only what fits (#157), and Event_Wreck_Looted carries both the gross
	// haul and the part that fell overboard so presentation can say so rather than let it
	// vanish silently. The player starts at 50 of 90 (40 of headroom), so a wreck filled
	// to the ceiling overflows — the mainline case once a hold is near full (#196).
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	before := ship.ship_cargo(sim.player)
	capacity := ship.ship_cargo_capacity(sim.player)
	fight := fight_stage(&sim, 1) // 1 Hull: sinks in a round, before it could jettison
	ship.ship_stow_cargo(fight.opponent.layout, capacity) // a hold larger than the player's headroom
	gross := ship.ship_cargo(fight.opponent) // what the wreck actually holds after the stow
	sim_seat_at_stage(&sim, 1, &events, fight)

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = PRESS_FIRE}))
	refit_tick(&sim, &events)

	testing.expect(t, sim.battle.ended)
	testing.expect_value(t, ship.ship_cargo(sim.player), capacity) // filled to the ceiling, no further
	kept := capacity - before // what the headroom could take

	found := false
	for event in events {
		looted, ok := event.(Event_Wreck_Looted)
		if !ok {
			continue
		}
		found = true
		testing.expect_value(t, looted.gross, gross) // the whole wreck hold is named
		testing.expect_value(t, looted.spilled, gross - kept) // the rest went overboard
	}
	testing.expect(t, found) // the overflow is surfaced, not silent
}

// battle_menu picks the last Event_Battle_Menu out of a batch — the flags the Fight screen
// is holding when it asks for the next round's order. Asserts rather than reporting absence:
// a batch that asked for no decision is a scenario that didn't set itself up.
battle_menu :: proc(events: []Event) -> (menu: Event_Battle_Menu) {
	found := false
	for e in events {
		if m, ok := e.(Event_Battle_Menu); ok {
			menu, found = m, true
		}
	}
	assert(found, "the batch carries no Event_Battle_Menu")
	return
}

// battle_events collects the combat Events of variant T wrapped in this batch, in the
// order the round emitted them — the seam a battle scenario asserts on (ADR-0001: what
// presentation learns is the stream, not the hull field).
battle_events :: proc(events: []Event, $T: typeid) -> (found: [dynamic]T) {
	for e in events {
		wrapped, is_battle := e.(Event_Battle_Event)
		if !is_battle {
			continue
		}
		if inner, is_t := wrapped.inner.(T); is_t {
			append(&found, inner)
		}
	}
	return
}

// battle_event_index is where variant T first appears in the batch, or -1 if it never
// does — how a scenario asserts on the *order* two facts were said in.
battle_event_index :: proc(events: []Event, $T: typeid) -> int {
	for e, i in events {
		wrapped, is_battle := e.(Event_Battle_Event)
		if !is_battle {
			continue
		}
		if _, is_t := wrapped.inner.(T); is_t {
			return i
		}
	}
	return -1
}

// damage_to is what `side` lost to the round's guns: a round emits one hit per side, so
// a scenario about the player's hull must name which of the two it is reading.
damage_to :: proc(hits: []combat.Event_Damage_Dealt, side: combat.Side) -> int {
	for hit in hits {
		if hit.target == side {
			return hit.damage
		}
	}
	return 0
}

// arm_with_repair installs a Brace fitting repairing `magnitude` Hull a round into the
// player's Large forecastle (slot 3, which carries a bare hold out of the starting
// stow) — the shape the roster's defensive items are authored in. It **replaces**
// rather than installs: no slot is ever empty, so ship_fit would refuse every one.
arm_with_repair :: proc(sim: ^Sim, magnitude: int) {
	// bulk 40: its own machinery fills the slot, so an armed forecastle carries nothing.
	fitting := ship.ship_fitting_with_effects(
		ship.Fitting{name = "Shipwright's Kit", size = .Large, bulk = 40},
		ship.effect_repair(ship.expr_const(magnitude)),
	)
	ship.ship_replace_fitting(&sim.player.layout[3], fitting)
}

@(test)
a_repair_lands_before_the_guns_and_saves_a_ship_that_would_have_sunk :: proc(t: ^testing.T) {
	// The whole of what makes Brace a phase rather than a summing pass (#397): repair
	// resolves **inside Brace, ahead of Fire**, and that ordering is consumed by exactly
	// one thing — the death check. The player is left holding exactly the round's incoming
	// damage, so without the repair the round sinks them. Every claim is read off the
	// stream: the repair is said before the damage, and neither a sinking nor an ending
	// is said at all.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	sim_seat_at_stage(&sim, 1, &events, fight_stage(&sim, 10_000)) // durable: the battle outlives the round

	arm_with_repair(&sim, 5)
	incoming := combat.combat_phase_output_this_round(&sim.battle, .B, .Fire)
	testing.expect(t, incoming > 0)
	sim.player.hull = incoming // one round's damage and not a point more

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}}))
	ev := refit_tick(&sim, &events)

	repaired_at := battle_event_index(ev, combat.Event_Hull_Repaired)
	damaged_at := battle_event_index(ev, combat.Event_Damage_Dealt)
	testing.expect(t, repaired_at >= 0)
	testing.expect(t, damaged_at >= 0)
	testing.expect(t, repaired_at < damaged_at) // repair ahead of Fire, in the stream itself

	// The repair covered the gap, so the round the captain would have gone down on ends
	// with the battle still running.
	testing.expect_value(t, battle_event_index(ev, combat.Event_Ship_Sunk), -1)
	testing.expect_value(t, battle_event_index(ev, combat.Event_Battle_Ended), -1)
}

@(test)
a_repair_never_heals_past_the_ships_maximum :: proc(t: ^testing.T) {
	// Repair restores the *gap*, never its own magnitude: a repair into a full hull is a
	// no-op that says nothing, and one into a damaged hull stops at the ceiling. This is
	// what gives Max Hull a value raising it never had on its own — a repair larger than
	// any wound still cannot take the hull above its maximum. The fitting offers 10,000
	// and the stream reports exactly the wound the round before it opened.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim) // full hull
	sim_seat_at_stage(&sim, 1, &events, fight_stage(&sim, 10_000))

	arm_with_repair(&sim, 10_000) // far larger than any gap a round can open

	// Round one: nothing to restore, so the repair is a no-op and emits nothing.
	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}}))
	ev := refit_tick(&sim, &events)
	testing.expect_value(t, battle_event_index(ev, combat.Event_Hull_Repaired), -1)
	first_hits := battle_events(ev, combat.Event_Damage_Dealt)
	defer delete(first_hits)
	wound := damage_to(first_hits[:], .A)
	testing.expect(t, wound > 0)

	// Round two: it fills that wound and stops there.
	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}}))
	ev = refit_tick(&sim, &events)
	repairs := battle_events(ev, combat.Event_Hull_Repaired)
	defer delete(repairs)
	testing.expect_value(t, len(repairs), 1)
	testing.expect_value(t, repairs[0].side, combat.Side.A)
	testing.expect_value(t, repairs[0].amount, wound) // the gap, not the magnitude
}

@(test)
jettisoning_sheds_less_every_time_and_never_empties_the_slot :: proc(t: ^testing.T) {
	// Jettison end to end at the seam presentation actually reads (#400). Three heaves
	// of the *same* slot, each one asserted off the stream: the event names what went
	// over the side, the ship the round hands back still has every fitting installed,
	// and each heave sheds no more than the last because the remainder is re-stowed.
	// That last property is the whole of what makes the escape window close as it is
	// used — a captain cannot buy Speed at a flat price per round.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	sim_seat_at_stage(&sim, 1, &events, fight_stage(&sim, 10_000)) // durable: the battle outlives the heaves

	laden := -1
	for layout_slot, i in sim.player.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting && fitting.cargo_held > 0 {
			laden = i
			break
		}
	}
	testing.expect(t, laden >= 0) // the starting ship sails laden

	// The opening cargo and Speed are the scenario's setup; every claim after this comes
	// off the stream.
	carrying := ship.ship_cargo(sim.player)
	speed := ship.ship_effective_speed(&sim.player)
	heave := Command(
		Command_Battle_Choice {
			combat_command = combat.Command_Jettison_Cargo{slot_index = ship.Slot_Index(laden)},
		},
	)

	previous := max(int)
	for _ in 0 ..< 3 {
		sim_submit_captain_choice(&sim, heave)
		ev := refit_tick(&sim, &events)

		heaves := battle_events(ev, combat.Event_Cargo_Jettisoned)
		defer delete(heaves)
		testing.expect_value(t, len(heaves), 1)
		testing.expect_value(t, heaves[0].side, combat.Side.A)

		shed := heaves[0].fitting.cargo_held // the event names what went over the side
		testing.expect(t, shed > 0)
		testing.expect(t, shed <= previous) // self-flattening: never more than the last heave
		previous = shed

		// The ship the round hands back is lighter by exactly the heave and no more — the
		// Speed is the lost weight, never a granted bonus — and still carries the fitting
		// that was heaved, which is carrying again because the remainder was re-stowed.
		updated, told := last_updated_ship(ev)
		testing.expect(t, told)
		testing.expect_value(t, ship.ship_cargo(updated), carrying - shed)
		testing.expect(t, ship.ship_effective_speed(&updated) > speed)
		carrying, speed = ship.ship_cargo(updated), ship.ship_effective_speed(&updated)

		emptied, still_occupied := updated.layout[laden].fitting.?
		testing.expect(t, still_occupied)
		testing.expect(t, emptied.cargo_held > 0)
	}

	testing.expect(t, previous < 10) // the last heave shed less than a full starting hold
}

// last_updated_ship is the player's ship as of the end of the batch, read off the stream
// rather than out of the Sim: an assertion about what presentation was *told* has to come
// from the events it was handed (ADR-0001).
last_updated_ship :: proc(events: []Event) -> (s: ship.Ship, found: bool) {
	for e in events {
		if updated, ok := e.(Event_Ship_Updated); ok {
			s, found = updated.ship, true
		}
	}
	return
}

@(test)
a_press_spends_the_battles_one_press_and_the_menu_stops_offering_it :: proc(t: ^testing.T) {
	// The ration end to end: the Fight menu event carries may_press, so presentation is
	// told the Press is gone rather than counting its own clicks. A second Press asserts
	// in core/combat, which is only reachable if this flag is ignored.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	sim_seat_at_stage(&sim, 1, &events, fight_stage(&sim, 10_000)) // durable: the battle outlives the round
	testing.expect_value(t, sim.phase, Phase.Awaiting_Battle_Command)
	testing.expect(t, battle_menu(events[:]).may_press) // in hand at the opening decision

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = combat.Command_Press{phase = .Fire}}))
	ev := refit_tick(&sim, &events)

	testing.expect(t, !sim.battle.ended) // a Press is not an ending
	testing.expect(t, !battle_menu(ev).may_press)

	// It does not come back on a later round.
	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}}))
	ev = refit_tick(&sim, &events)
	testing.expect(t, !battle_menu(ev).may_press)
}

@(test)
committing_in_battle_multiplies_the_repair_and_lands_no_damage :: proc(t: ^testing.T) {
	// Commit end to end: the round's repair is multiplied and the round's damage is
	// nothing, so the stream carries a Hull_Repaired for the player and a Damage_Dealt
	// only against them. The battle carries on — Commit is a stance, not an ending.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	sim_seat_at_stage(&sim, 1, &events, fight_stage(&sim, 10_000))

	arm_with_repair(&sim, 5)
	sim.player.hull = 100 // room for the repair to land in full
	// The whole Brace phase is what Commit multiplies, not just the fitting armed above.
	unpressed_repair := combat.combat_phase_output_this_round(&sim.battle, .A, .Brace)
	testing.expect(t, unpressed_repair > 0)

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = combat.Command_Commit{}}))
	ev := refit_tick(&sim, &events)

	testing.expect(t, !sim.battle.ended)

	repairs := battle_events(ev, combat.Event_Hull_Repaired)
	defer delete(repairs)
	testing.expect_value(t, len(repairs), 1)
	testing.expect_value(t, repairs[0].amount, unpressed_repair * combat.COMMIT_MULTIPLIER)

	// The opponent is struck for nothing: the guns were the price of the repair.
	hits := battle_events(ev, combat.Event_Damage_Dealt)
	defer delete(hits)
	testing.expect_value(t, damage_to(hits[:], .B), 0)
	testing.expect(t, damage_to(hits[:], .A) > 0) // theirs still land
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

	before := ship.ship_cargo(sim.player)
	sim_seat_at_stage(&sim, 1, &events, offer_stage(), reward_stage())
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	testing.expect_value(t, ship.ship_cargo(sim.player), before) // stage 1 not reached yet

	// Picking completes the Offer and opens a Refit; the walk resumes at its finish and
	// runs through the Reward without stopping again.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)

	testing.expect_value(t, ship.ship_cargo(sim.player), before + REWARD_PAYOUT)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1])
}

@(test)
winning_a_fight_completes_it_and_the_walk_reaches_the_next_stage :: proc(t: ^testing.T) {
	// Victory completes (ADR-0014) — the paying half of [Fight, Reward], and the
	// counterpart to breaking off above. A one-Hull opponent goes down in the first
	// round, so the walk advances onto the Trade.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	before := sim.player.max_hull
	sim_seat_at_stage(&sim, 1, &events, fight_stage(&sim, 1), trade_stage())

	for fight_round(&sim, &events) {
		// hold until the opponent goes down
	}

	testing.expect(t, !(.A in sim.battle.escaped)) // won it rather than fled it

	// Victory advanced the cursor onto the Trade; accepting is what makes reaching it
	// visible on the ship.
	accept_trade(t, &sim, &events)
	testing.expect_value(t, sim.player.max_hull, before + TRADE_GAIN)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, sim.resolved[1])
}

@(test)
sinking_ends_the_voyage_without_walking_on_to_a_later_stage :: proc(t: ^testing.T) {
	// Sinking is neither outcome (ADR-0014): it ends the voyage by permadeath, so the
	// walk stops rather than completing the Fight. Without this the loser of a
	// [Fight, Reward] would be paid on the way down — sim_tick's status check ends the
	// run *after* the round is processed, so the walk would already have applied the
	// next stage to a sunk ship.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	before := sim.player.max_hull
	sim.player.hull = 1 // goes down in the first round
	sim.player.speed = 50
	sim_seat_at_stage(&sim, 1, &events, fight_stage(&sim, 10_000), trade_stage())

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}}))
	ev := refit_tick(&sim, &events)

	testing.expect(t, sim.player.hull <= 0)
	testing.expect_value(t, sim.player.max_hull, before) // sank: the Trade was never reached
	testing.expect_value(t, sim.status, voyage.Voyage_Status.Lost)
	testing.expect_value(t, sim.phase, Phase.Ended)
	testing.expect(t, has_event(ev, Event_Voyage_Ended))
}

// --- Ghost capture cadence: one snapshot per encounter (issue #162) ---------
//
// These count Event_Encounter_Resolved rather than merely asking whether one is
// present, because the **count** is the contract (ADR-0008 as amended): one per
// node's walk. Asking "was there a snapshot" is what let the retired cadence pass
// unnoticed — it fired from the three run-side procs that happened to return one, so
// a [Fight, Reward] emitted twice and an Offer, which is the stage that actually
// changes the build, emitted not at all.

// resolved_snapshots collects every Event_Encounter_Resolved's snapshot in the batch,
// in order.
resolved_snapshots :: proc(events: []Event) -> [dynamic]voyage.Ghost_Snapshot {
	snaps: [dynamic]voyage.Ghost_Snapshot
	for e in events {
		if resolved, ok := e.(Event_Encounter_Resolved); ok {
			append(&snaps, resolved.snapshot)
		}
	}
	return snaps
}

// snapshot_holds reports whether a captured ship has a fitting of this name aboard —
// "did the ghost record what the captain took on at this node", which is the question
// the Offer and Shop stages had no way to answer at all before #162.
snapshot_holds :: proc(snap: voyage.Ghost_Snapshot, name: string) -> bool {
	for slot in snap.ship.layout {
		if fitting, filled := slot.fitting.?; filled && fitting.name == name {
			return true
		}
	}
	return false
}

@(test)
one_encounter_emits_one_snapshot_however_many_stages_resolve :: proc(t: ^testing.T) {
	// The cadence itself, on the encounter that exposed it: [Fight, Reward] is on every
	// seed's Open Sea (#138), and both of its stages used to emit a ghost of their own.
	// One node, one ghost — and it is taken **post-loot**, because it is the ship the
	// captain leaves the node with rather than a timeline of the ship inside it.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	before := ship.ship_cargo(sim.player)
	fight := fight_stage(&sim, 1) // 1 Hull: sinks in a round
	ship.ship_stow_cargo(fight.opponent.layout, 0) // broke wreck: this test is about the ghost cadence, not the payout
	sim_seat_at_stage(&sim, 1, &events, fight, reward_stage())

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = PRESS_FIRE}))
	ev := refit_tick(&sim, &events)

	snaps := resolved_snapshots(ev)
	defer delete(snaps)
	testing.expect_value(t, len(snaps), 1)
	testing.expect_value(t, ship.ship_cargo(snaps[0].ship), before + REWARD_PAYOUT)

	// The node's own stakes ride along (ADR-0014), asked of the node the walk ended on
	// rather than reconstructed by a stage — which is what retired Stage_Fight.depth and
	// sim.active_trade_site, the two copies of this that a late-resolving stage carried
	// so it could stamp a snapshot of its own.
	testing.expect_value(t, snaps[0].progress.site, sim_current_site(&sim))
}

@(test)
a_halted_encounter_emits_a_snapshot_of_the_ship_that_walked_away :: proc(t: ^testing.T) {
	// A halt emits: the cursor jumps to the end, so it lands in the same branch that
	// resolves any other walk, and a fled ship is a real ship a lobby can serve. Fleeing
	// a [Fight, Reward] is the case where a *stage-level* cadence and a node-level one
	// visibly disagree — the ghost is one, and the Reward it names is unpaid.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ready_for_battle(&sim)
	before := ship.ship_cargo(sim.player)
	sim_seat_at_stage(&sim, 1, &events, fight_stage(&sim, 10_000), reward_stage()) // too tough to sink quickly

	// Hold until the Speed-gated escape unlocks (ADR-0006), then take it.
	for combat.BASELINE_ROUND_COUNT * 2 > sim.battle.round {
		if combat.combat_may_break_off(&sim.battle, .A) {
			break
		}
		testing.expect(t, fight_round(&sim, &events))
	}
	testing.expect(t, combat.combat_may_break_off(&sim.battle, .A))

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = combat.Command_Break_Off{}}))
	ev := refit_tick(&sim, &events)

	snaps := resolved_snapshots(ev)
	defer delete(snaps)
	testing.expect(t, sim.resolved[1])
	testing.expect_value(t, len(snaps), 1)
	testing.expect_value(t, ship.ship_cargo(snaps[0].ship), before) // fled: the ghost is unpaid too
}

@(test)
a_sinking_emits_no_snapshot :: proc(t: ^testing.T) {
	// The one encounter in a voyage that leaves no ghost, and a **behavior change** from
	// the retired cadence, which emitted on the way down (sim_battle's per-proc emit
	// fired before the status check). The walk stops dead, so the node is never
	// resolved — and Event_Encounter_Resolved's "resolved" is now the Sim's `resolved`,
	// which makes an emit here a contradiction rather than a courtesy. Nothing is lost:
	// the build is whatever the last node's ghost already recorded, and Event_Voyage_Ended
	// is what marks the death.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.player.hull = 1 // goes down in the first round
	sim.player.speed = 50
	sim_seat_at_stage(&sim, 1, &events, fight_stage(&sim, 10_000), reward_stage())

	sim_submit_captain_choice(&sim, Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}}))
	ev := refit_tick(&sim, &events)

	snaps := resolved_snapshots(ev)
	defer delete(snaps)
	testing.expect(t, sim.player.hull <= 0)
	testing.expect_value(t, len(snaps), 0)
	testing.expect(t, !sim.resolved[1]) // the walk stopped: the node never resolved
	testing.expect(t, has_event(ev, Event_Voyage_Ended))
}

@(test)
the_snapshot_carries_the_fitting_an_offer_put_aboard :: proc(t: ^testing.T) {
	// **The hole #162 was filed to close**, and there was no test for it because it had
	// never been true: an Offer is the stage that changes the *build*, and it emitted
	// nothing at all — it is not one of the three procs that happened to return a
	// snapshot. A ghost is a build, so this is the ghost's whole job.
	//
	// The timing lands for free: an Offer's pick advances the cursor and *then* opens
	// the Refit, so the Refit's finish routes back through the walk and the capture is
	// post-install by construction rather than by an ordering someone has to maintain.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	seat_at_offer(&sim, &events) // option 0 is the roster's first item, "Deckhands" (Small)

	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Replace{slot = 5}) // hold 2, a Small slot holding cargo
	refit_tick(&sim, &events)
	testing.expect_value(t, fitting_name_at(&sim, 5), "Deckhands")

	submit_refit(&sim, Refit_Finish{})
	ev := refit_tick(&sim, &events)

	snaps := resolved_snapshots(ev)
	defer delete(snaps)
	testing.expect_value(t, len(snaps), 1)
	testing.expect(t, snapshot_holds(snaps[0], "Deckhands"))
	// The item the captain *didn't* pick is not aboard — so the assertion above is the
	// pick being recorded, not the roster leaking into the ghost through the offer.
	testing.expect(t, !snapshot_holds(snaps[0], "Swivel Guns")) // option 1, declined
}

@(test)
the_snapshot_carries_every_purchase_made_at_a_shop :: proc(t: ^testing.T) {
	// The same hole from the other end, and the larger one: a Port is a [Shop] recipe
	// (#134) and the multi-buy loop is the single biggest build change in the game —
	// three fittings aboard in one visit, recorded by nothing. It is also the case that
	// makes "at the end of the walk" load-bearing rather than incidental: a Shop keeps
	// the cursor across each buy's Refit, so any capture pinned to a *stage* resolving
	// would have to pick a buy to fire on.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ship.ship_stow_cargo(sim.player.layout, 90) // afford the visit outright; the hull's full capacity (ADR-0020)
	seat_at_shop(&sim, 1, flat_stock(.Splash), &events) // stock position i is roster[i]

	// Buy option 0 ("Deckhands"), install it, and return to the refilled shelf.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Replace{slot = 5})
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)

	// Buy option 1 ("Swivel Guns") at the same shop — the second turn of the loop.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(1)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Replace{slot = 6})
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)

	// Leaving completes the Shop (it is the one primitive with no halt) and ends the walk.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	ev := refit_tick(&sim, &events)

	snaps := resolved_snapshots(ev)
	defer delete(snaps)
	testing.expect_value(t, len(snaps), 1)
	testing.expect(t, snapshot_holds(snaps[0], "Deckhands"))
	testing.expect(t, snapshot_holds(snaps[0], "Swivel Guns"))
}

@(test)
a_resolved_node_emits_no_second_snapshot_when_the_ship_returns :: proc(t: ^testing.T) {
	// One per node holds across a *voyage*, not just within one walk: an encounter is
	// walked once, so retracing to a resolved node re-emits nothing. Driven through the
	// real arrival path rather than the walk directly, because the guard that makes this
	// true lives there (sim_process_travel's already_resolved) — calling the walk would
	// prove a different, easier thing.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	before := ship.ship_cargo(sim.player)
	sim_seat_at_stage(&sim, 1, &events, reward_stage())

	first := resolved_snapshots(events[:])
	defer delete(first)
	testing.expect_value(t, len(first), 1)
	testing.expect(t, sim.resolved[1])

	sim.current = 0 // retrace: node 1 is a neighbour of Start on this seed
	sim_submit_captain_choice(&sim, Command(Command_Travel_To{node_id = 1}))
	clear(&events)
	sim_tick(&sim, &events)

	again := resolved_snapshots(events[:])
	defer delete(again)
	testing.expect_value(t, len(again), 0)
	testing.expect_value(t, ship.ship_cargo(sim.player), before + REWARD_PAYOUT) // and paid once
}

// flat_stock bakes a shop stocked to `count` cards in roster order, every card re-tiered
// to `tier` (issue #123) — a stand-in for a generated shop's baked stock with predictable
// affordability and a known order (the card at stock position i is roster[i]), so the
// shop tests can assert exactly which card the shelf shows and refills with. A real
// generated shop shuffles its pool's candidates and cuts them at the pool's authored
// depth (voyage_bake_shop, #137); the tests don't need the shuffle, only the stock
// contract.
//
// A **tier**, not a price: a card's price is voyage_shop_price's to say, and one tier
// across the stock is the closest a test gets to the flat shelf it wants. That the
// cheapest shelf a test can lay out costs ship_item_cost(.Splash) is the real economy's
// floor, not a limit of this helper — a scenario that needs a cheaper card is asking for
// a price the game cannot quote.
//
// `count` is a parameter because a shop's depth is authored per stock pool rather than
// being the whole roster, so how deep a shop is *is* something the tests need to vary —
// a Chandlery you cannot empty and a merchant's hold you can are the same code path with
// a different count.
flat_stock :: proc(tier: ship.Tier, count := voyage.SHOP_STOCK_MAX) -> voyage.Stage_Shop {
	assert(count <= voyage.SHOP_STOCK_MAX, "a shop cannot stock more than SHOP_STOCK_MAX cards")
	roster := ship.ship_item_roster()
	shop := voyage.Stage_Shop{count = count}
	for i in 0 ..< count {
		shop.stock[i] = ship.Roster_Item{fitting = roster[i].fitting, tier = tier}
	}
	return shop
}

// seat_at_shop seats the ship in front of a [Shop] encounter at node `id` — what a Port is
// (ADR-0014), and the shorthand the shop scenarios below open with.
seat_at_shop :: proc(sim: ^Sim, id: Node_ID, shop: voyage.Stage_Shop, events: ^[dynamic]Event) {
	sim_seat_at_stage(sim, id, events, shop)
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
	// The shop tests below plant their own stock so they can assert exact cards; this one
	// takes a Port straight from the generator, so it is the only cover that a *generated*
	// port still bakes its stock into its [Shop] stage's content. A fold that dropped the
	// stock would leave every other shop test passing.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	// Any generated Port will do, and it is seated at rather than sailed to: no port sits on
	// a zone's entrance layer, so none is a Start neighbour and reaching one honestly would
	// mean pathfinding a scenario this test isn't about. Seating with no stages leaves the
	// node's own generated content in place — the point here.
	//
	// The node is found by **what it opens with** — there is no kind left to find it
	// by, since #137 retired Node_Kind.Port. That is the same question the walk, the
	// Sim's mask and the map view all ask, so this test reaches its port the way the
	// production code does. Since ADR-0016 the question also cannot pick up a merchant
	// by mistake: revealing ⟺ opening on a Shop ⟺ being a Port.
	port := Node_ID(-1)
	for p in sim.voyage_map.nodes {
		encounter, has_encounter := p.encounter.?
		if !has_encounter {
			continue
		}
		if voyage.voyage_encounter_reveals(encounter) {
			port = p.id
			break
		}
	}
	testing.expect(t, port >= 0)

	sim_seat_at_stage(&sim, port, &events)

	// A Shop parks the walk in the option-list decision every option-bearing stage
	// shares (#131), so the stock arrives as presented options rather than a shelf of
	// its own.
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	options := presented_options(events[:])
	filled := 0
	for option in options {
		if _, ok := option.?; ok {
			filled += 1
		}
	}
	testing.expectf(t, filled == voyage.SHOP_SHELF_SIZE, "generated port %d dealt %d shelf cards, want %d", port, filled, voyage.SHOP_SHELF_SIZE)
}

@(test)
buying_an_affordable_item_deducts_cargo_and_opens_a_refit :: proc(t: ^testing.T) {
	// The core of #123's acceptance: buying a shelf card the ship can afford
	// deducts its cost from the hold and opens a Refit staged with that
	// exact item, so the manual-loadout commands place it — the same path an Item
	// Offer's pick takes.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ship.ship_stow_cargo(sim.player.layout, 50)
	seat_at_shop(&sim, 1, flat_stock(.Splash), &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(1)}))
	ev := refit_tick(&sim, &events)

	roster := ship.ship_item_roster()
	testing.expect_value(t, sim.phase, Phase.Awaiting_Refit)
	testing.expect(t, has_event(ev, Event_Refit_Started))
	testing.expect_value(t, ship.ship_cargo(sim.player), 40) // 50 - 10 spent
	incoming, pending := sim.refit_pending.?
	testing.expect(t, pending)
	testing.expect_value(t, incoming.name, roster[1].fitting.name) // shelf slot 1 == stock pos 1 == roster[1]

	// A buy leaves the cursor on the Shop, which is the whole of what makes the
	// Refit's finish come back here rather than go to travel (issue #131 retired the
	// remembered Refit_Origin in favour of reading the cursor).
	encounter, _ := sim_current_encounter(&sim)
	testing.expect_value(t, encounter.cursor, 0)
}

@(test)
buying_a_fitting_over_a_cargo_hold_conserves_the_displaced_cargo :: proc(t: ^testing.T) {
	// #198's double-swing, the conserving half: money *is* the cargo (ADR-0020), so a
	// bought fitting placed over a cargo hold displaces real cargo. Reallocation is
	// free outside battle (#157), so that cargo is not destroyed — it re-stows into
	// whatever capacity remains, and only genuine overflow above the reduced ceiling is
	// lost. Here the ceiling stays well above the cargo, so nothing overflows: the buy
	// costs exactly its price and not a coin more, even though the fitting lands on a
	// full hold.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ship.ship_stow_cargo(sim.player.layout, 50) // the starting cargo: holds full, forecastle empty
	seat_at_shop(&sim, 1, flat_stock(.Splash), &events)

	// Buy option 0 (Deckhands, Small, cost 10): the spend re-stows the cargo to 40.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	testing.expect_value(t, ship.ship_cargo(sim.player), 40)

	// Place it over a full Small hold (slot 5). That slot becomes a gun, but the empty
	// capacity elsewhere (the Medium hold and the empty forecastle) absorbs the displaced
	// 10, so the cargo stays 40 — the displaced cargo conserved, not burned.
	submit_refit(&sim, Refit_Replace{slot = 5})
	refit_tick(&sim, &events)

	testing.expect_value(t, fitting_name_at(&sim, 5), "Deckhands")
	testing.expect_value(t, ship.ship_cargo(sim.player), 40) // conserved: only the 10 cost is gone
	testing.expect(t, ship.ship_cargo(sim.player) <= ship.ship_cargo_capacity(sim.player))
}

@(test)
buying_a_fitting_that_overflows_the_hold_loses_only_the_true_overflow :: proc(t: ^testing.T) {
	// #198's double-swing, the overflow half: when placing the bought fitting shrinks
	// capacity below the cargo, the surviving cargo re-stows to the new ceiling and
	// only what will not fit is lost (ADR-0020, #157) — never the whole displaced hold,
	// and never left in the impossible state of a cargo over capacity. A rich ship buys
	// a Medium fitting and lands it on a Medium hold: capacity drops by the Medium's 20
	// and the cargo is capped there, 10 falling overboard rather than the full displaced 20.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ship.ship_stow_cargo(sim.player.layout, 90) // brim-full: the whole 90-capacity hull laden
	seat_at_shop(&sim, 1, flat_stock(.Splash), &events)

	// Buy option 2 (Deck Cannon, Medium, a Splash card's 10): the spend re-stows the
	// cargo to 80.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(2)}))
	refit_tick(&sim, &events)
	testing.expect_value(t, ship.ship_cargo(sim.player), 80)

	// Land it on a Medium hold (slot 4), turning that slot from cargo into a gun. The
	// ceiling drops by 20 (to 70) and the cargo — 80 with the slot now gone — re-stows
	// to exactly 70. Only the 10 that no longer fits is lost; naive burning of the
	// displaced slot would have destroyed the full 20, leaving 60.
	submit_refit(&sim, Refit_Replace{slot = 4})
	refit_tick(&sim, &events)

	testing.expect_value(t, fitting_name_at(&sim, 4), "Deck Cannon")
	testing.expect_value(t, ship.ship_cargo_capacity(sim.player), 70)
	testing.expect_value(t, ship.ship_cargo(sim.player), 70) // capped at capacity: only 10 lost, not 20
	testing.expect(t, ship.ship_cargo(sim.player) <= ship.ship_cargo_capacity(sim.player)) // never over capacity
}

@(test)
an_unaffordable_item_is_refused_and_the_shop_stays_open :: proc(t: ^testing.T) {
	// "an unaffordable item cannot be bought": a buy costing more than the cargo is
	// rejected, no cargo is spent, no Refit opens, and the shop stays open for
	// another choice.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	// A Splash shelf with one Deep card at slot 2: the cargo covers the cheap cards and
	// not that one, so the refusal is the price talking and not an empty hold.
	shop := flat_stock(.Splash)
	shop.stock[2].tier = .Deep
	ship.ship_stow_cargo(sim.player.layout, ship.ship_item_cost(.Deep) - 1)
	seat_at_shop(&sim, 1, shop, &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(2)}))
	ev := refit_tick(&sim, &events)

	testing.expect(t, has_event(ev, Event_Purchase_Rejected))
	testing.expect(t, !has_event(ev, Event_Refit_Started))
	testing.expect_value(t, ship.ship_cargo(sim.player), ship.ship_item_cost(.Deep) - 1) // nothing spent
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

	ship.ship_stow_cargo(sim.player.layout, 50)
	seat_at_shop(&sim, 1, flat_stock(.Splash), &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	ev := refit_tick(&sim, &events)

	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect_value(t, ship.ship_cargo(sim.player), 50) // nothing spent
	testing.expect(t, !has_event(ev, Event_Refit_Started))
	testing.expect(t, has_event(ev, Event_Travel_Options)) // back to a travel choice

	// Completed, not halted: the cursor stepped off the Shop onto the end of the
	// list, rather than being jumped there by a halt. Indistinguishable on a
	// one-stage recipe, which is why sim_stage_decline_outcome is asserted directly.
	testing.expect_value(t, sim_stage_decline_outcome(voyage.Stage(flat_stock(.Splash))), voyage.Stage_Outcome.Completed)
	testing.expect_value(t, sim_stage_decline_outcome(voyage.Stage(offer_stage())), voyage.Stage_Outcome.Halted)
}

@(test)
arriving_at_a_shop_presents_the_top_of_its_stock :: proc(t: ^testing.T) {
	// Arriving at a [Shop] stages a SHOP_SHELF_SIZE shelf off the top of its stock and
	// presents it (issue #123), through the same option list an Offer uses — priced,
	// which is the only difference.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	seat_at_shop(&sim, 1, flat_stock(.Shallow), &events)

	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	options := presented_options(events[:])
	roster := ship.ship_item_roster()
	// The shelf is the top SHOP_SHELF_SIZE stock cards (stock position i is roster[i]),
	// each at its tier's price — no buy made yet, so the surcharge adds nothing.
	for i in 0 ..< voyage.SHOP_SHELF_SIZE {
		testing.expect_value(t, option_name(options, i), roster[i].fitting.name)
		testing.expect_value(t, option_cost(options, i), ship.ship_item_cost(.Shallow))
	}
}

@(test)
a_node_holding_no_encounter_leaves_the_ship_at_a_travel_choice :: proc(t: ^testing.T) {
	// Start and Haven are landmarks by graph position, which no stage list can express
	// (ADR-0014) — so they hold no encounter, and the walk asks nothing about what
	// kind of node it is: finding nothing to walk *is* how a pure waypoint works.
	// This is what lets sim_process_travel hand every arrival to the walk unasked.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim.phase = .Awaiting_Option_Choice // anything but travel, so the walk has to set it
	sim_seat_at_stage(&sim, 0, &events) // node 0 is Start

	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, !has_event(events[:], Event_Options_Presented))
	testing.expect(t, !sim.resolved[0]) // nothing was walked, so nothing resolved
}

@(test)
buying_a_shelf_card_refills_the_slot_from_the_deck_on_the_refits_finish :: proc(t: ^testing.T) {
	// #123's core: an affordable buy opens a Refit, and on its finish the Sim
	// returns to the *shop* (not travel) with the bought slot refilled by the next
	// stock card. The bought item (roster[0]) is gone from the shelf; the refill
	// (roster[SHOP_SHELF_SIZE], the first still-undrawn card) has taken slot 0.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ship.ship_stow_cargo(sim.player.layout, 50)
	seat_at_shop(&sim, 1, flat_stock(.Splash), &events)

	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events) // buy: deduct, open the refit (cursor stays on the Shop)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Refit)

	submit_refit(&sim, Refit_Finish{})
	ev := refit_tick(&sim, &events) // finish: the walk re-enters the Shop, refilled

	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice) // back at the shop, not travel
	testing.expect(t, has_event(ev, Event_Options_Presented)) // re-presented refilled
	roster := ship.ship_item_roster()
	options := presented_options(ev)
	// Slot 0 refilled with the next stock card; the bought roster[0] is off the shelf.
	testing.expect_value(t, option_name(options, 0), roster[voyage.SHOP_SHELF_SIZE].fitting.name)
	for i in 0 ..< voyage.SHOP_SHELF_SIZE {
		testing.expect(t, option_name(options, i) != roster[0].fitting.name)
	}
}

@(test)
multiple_items_can_be_bought_in_one_visit_before_leaving :: proc(t: ^testing.T) {
	// #123: a visit is a multi-buy loop — each buy's refit returns to the shop, so
	// the player keeps buying (draining the stock and the cargo) until only Leave
	// exits to travel. Buy three cards in a row, then leave.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ship.ship_stow_cargo(sim.player.layout, 50)
	seat_at_shop(&sim, 1, flat_stock(.Splash), &events)

	for _ in 0 ..< 3 {
		testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
		sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
		refit_tick(&sim, &events) // open the buy's refit
		submit_refit(&sim, Refit_Finish{})
		refit_tick(&sim, &events) // finish -> back to the shop
	}
	// Three escalating buys (issue #124): base, then base+step, then base+2*step.
	base := ship.ship_item_cost(.Splash)
	spent := 3 * base + voyage.SHOP_DEPTH_SURCHARGE_STEP * (0 + 1 + 2)
	testing.expect_value(t, ship.ship_cargo(sim.player), 50 - spent)

	// Only Leave exits to travel.
	testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	ev := refit_tick(&sim, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, has_event(ev, Event_Travel_Options))
}

// filled_option_count is how many of the presented option positions actually hold an
// option — for a shop, how many cards the shelf is showing. Since #137 gave stock
// pools an authored depth this can fall below SHOP_SHELF_SIZE mid-visit, which is
// what a shop running dry looks like.
filled_option_count :: proc(options: [STAGE_OPTION_MAX]Maybe(Stage_Option)) -> (n: int) {
	for option in options {
		if _, filled := option.?; filled {
			n += 1
		}
	}
	return
}

// buy_first_available buys whatever the shelf's leftmost filled slot is offering, or
// reports ok=false once the shelf is bare. Buying always at slot *0* would test the
// wrong thing — a slot bares when the stock behind the shelf runs out, so hammering
// one slot drains that slot's refills while the other four still hold cards.
buy_first_available :: proc(sim: ^Sim, events: ^[dynamic]Event) -> (ok: bool) {
	for slot, i in sim.stage_options {
		option, on_offer := slot.?
		if !on_offer {
			continue
		}
		cost, priced := option.cost.?
		assert(priced, "a shop's option must carry a price")
		if cost > ship.ship_cargo(sim.player) {
			return false // the cargo gave out, not the shop
		}
		sim_submit_captain_choice(sim, Command(Command_Choose_Option{selection = Option_Index(i)}))
		refit_tick(sim, events) // open the buy's refit
		submit_refit(sim, Refit_Finish{})
		refit_tick(sim, events) // finish -> back to the shop
		return true
	}
	return false
}

// buy_with_a_full_hold refills the hold to the hull's capacity and then buys, so a test
// measuring the *stock* running out is never stopped by the money instead. No reachable
// cargo buys a shop out at real prices — the cheapest six-card run costs
// 10+15+20+25+30+35 against a 90-capacity hull — so a bought-out shelf is only observable
// with the hold topped up between buys.
//
// The refits it finishes install nothing, so capacity never moves and every top-up is to
// the same ceiling.
buy_with_a_full_hold :: proc(sim: ^Sim, events: ^[dynamic]Event) -> bool {
	ship.ship_stow_cargo(sim.player.layout, ship.ship_cargo_capacity(sim.player))
	return buy_first_available(sim, events)
}

@(test)
a_narrow_hold_shrinks_as_it_is_bought_and_can_be_emptied :: proc(t: ^testing.T) {
	// The behaviour a stock pool's authored depth buys (#137), and the reason "how deep
	// is this shop" is content rather than a constant: a merchant's hold can be cleaned
	// out, a Port's Chandlery is not worth trying to.
	//
	// Six cards against a shelf of five is the specialist pools' authored depth, so the
	// reserve behind the shelf is *one*: the second buy of a visit already leaves a bare
	// slot, and the shop visibly shrinks as it is emptied. Before #137 this was
	// unreachable — a shop's stock was the whole 50-item roster, so
	// shop_visit_draw_next's nil branch was, in its own words, a "graceful short-deck
	// case, unreachable at the real roster size". It is content now.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	// Every buy is made with the hold topped up (buy_with_a_full_hold), so what runs out
	// is the *stock* and never the money — the point is that the shelf empties.
	seat_at_shop(&sim, 1, flat_stock(.Splash, 6), &events)
	testing.expect_value(t, filled_option_count(sim.stage_options), voyage.SHOP_SHELF_SIZE)

	// One buy: the lone reserve card refills the slot, so the shelf is still full.
	testing.expect(t, buy_with_a_full_hold(&sim, &events))
	testing.expect_value(t, filled_option_count(sim.stage_options), voyage.SHOP_SHELF_SIZE)

	// The second buy has nothing behind it, so the shelf starts shrinking — the whole
	// difference between a hold and a warehouse, visible on the second purchase rather
	// than at exhaustion.
	testing.expect(t, buy_with_a_full_hold(&sim, &events))
	testing.expect_value(t, filled_option_count(sim.stage_options), voyage.SHOP_SHELF_SIZE - 1)

	bought := 2
	for buy_with_a_full_hold(&sim, &events) {
		bought += 1
		testing.expectf(t, bought <= 6, "bought %d cards from a 6-card hold: it is refilling from nothing", bought)
	}

	// All six sold and the shelf bare — a slot with nothing behind it stays empty
	// rather than re-offering a card already bought.
	testing.expect_value(t, bought, 6)
	testing.expect_value(t, filled_option_count(sim.stage_options), 0)

	// An emptied shop is still a shop, not a stuck walk: Leave completes it (Shop is
	// the one primitive with no halt) and the encounter resolves like any other.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	ev := refit_tick(&sim, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, has_event(ev, Event_Travel_Options))
	testing.expect(t, sim.resolved[1])
}

@(test)
a_chandlerys_reserve_outlasts_the_cargo_a_captain_brings :: proc(t: ^testing.T) {
	// The other half of the depth knob (#137), and the promise the Port bucket's
	// guaranteed placement makes: routing to a Port is worth planning because a Port
	// still has things to sell when you leave it.
	//
	// A Chandlery is **not** infinite — 12 cards can be bought out, and at the cheapest
	// tier against #124's escalating surcharge that costs 10+15+…+65 = 450, nine times
	// the cargo a voyage starts with. The claim the depth has to support is the reachable
	// one: spend the *starting* cargo at the cheapest prices in the game and the shelf
	// is still full when the money runs out. The shop outlasts the captain, so what
	// ends a visit is the cargo.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ship.ship_stow_cargo(sim.player.layout, ship.STARTING_CARGO + ship.CAPTAIN_STARTING_CARGO)
	seat_at_shop(&sim, 1, flat_stock(.Splash, voyage.voyage_stock_pool(.Chandlery).depth), &events)

	bought := 0
	for buy_first_available(&sim, &events) {
		bought += 1
	}

	// The cargo is what stopped it, and the shelf never thinned: every slot the captain
	// bought from was refilled out of the reserve behind it.
	testing.expect(t, bought > 0)
	testing.expect_value(t, filled_option_count(sim.stage_options), voyage.SHOP_SHELF_SIZE)
	testing.expect(t, ship.ship_cargo(sim.player) < ship.ITEM_COST[.Splash])
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
	// Port-exclusive any more, so the answer to "I have cargo now" is meeting
	// another Shop, not returning to this one.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ship.ship_stow_cargo(sim.player.layout, 50)
	seat_at_shop(&sim, 1, flat_stock(.Splash), &events)

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
	// stock's top.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	ship.ship_stow_cargo(sim.player.layout, 50)
	roster := ship.ship_item_roster()

	seat_at_shop(&sim, 1, flat_stock(.Splash), &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	refit_tick(&sim, &events)

	// Shop 2 is untouched: its shelf opens on its stock's top card at the plain tier
	// price, with the previous shop's purchase count discarded rather than carried in.
	seat_at_shop(&sim, 2, flat_stock(.Splash), &events)
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

	ship.ship_stow_cargo(sim.player.layout, 50)
	roster := ship.ship_item_roster()
	sim_seat_at_stage(&sim, 1, &events, flat_stock(.Splash), flat_stock(.Splash))

	// Shop 1: buy the top card, then leave to complete it.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	ev := refit_tick(&sim, &events)

	// The walk advanced onto the second Shop, which dealt fresh: its top card is the
	// stock's top again (not the first shop's refill) at the plain tier price (not the
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
	// (purchases == 0); each later buy climbs by voyage.SHOP_DEPTH_SURCHARGE_STEP, and the
	// price shown on the re-presented shelf is exactly the price charged.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	base := ship.ship_item_cost(.Splash) // the cheapest card the roster prices
	ship.ship_stow_cargo(sim.player.layout, 90) // the hull's full capacity — the ceiling a cargo can reach (ADR-0020)
	seat_at_shop(&sim, 1, flat_stock(.Splash), &events)

	cargo := 90
	for n in 0 ..< 3 {
		want_price := base + voyage.SHOP_DEPTH_SURCHARGE_STEP * n

		// The re-presented shelf displays the surcharged price for this depth, so the
		// buyer sees the escalation before committing.
		testing.expect_value(t, option_cost(presented_options(events[:]), 0), want_price)

		testing.expect_value(t, sim.phase, Phase.Awaiting_Option_Choice)
		sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
		refit_tick(&sim, &events) // buy: charge want_price, open the refit
		cargo -= want_price
		testing.expect_value(t, ship.ship_cargo(sim.player), cargo) // charged the shown price

		submit_refit(&sim, Refit_Finish{})
		refit_tick(&sim, &events) // finish -> back to the shop, re-presented one depth deeper
	}
	// base + (base+step) + (base+2*step) spent across the three escalating buys.
	testing.expect_value(t, ship.ship_cargo(sim.player), 90 - (3 * base + voyage.SHOP_DEPTH_SURCHARGE_STEP * (0 + 1 + 2)))
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

	base := ship.ship_item_cost(.Splash) // the cheapest card the roster prices
	ship.ship_stow_cargo(sim.player.layout, 90) // the hull's full capacity (ADR-0020)
	seat_at_shop(&sim, 1, flat_stock(.Splash), &events)

	// One buy at the plain tier price, then leave.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)
	// Still in the same visit, so the next buy is already one step deeper.
	testing.expect_value(t, option_cost(presented_options(events[:]), 0), base + voyage.SHOP_DEPTH_SURCHARGE_STEP)

	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = nil}))
	refit_tick(&sim, &events)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect_value(t, ship.ship_cargo(sim.player), 90 - base) // one buy at tier price

	// A different shop starts at the plain tier price: the depth was this visit's, not
	// the voyage's.
	seat_at_shop(&sim, 2, flat_stock(.Splash), &events)
	testing.expect_value(t, option_cost(presented_options(events[:]), 0), base)
}

@(test)
a_surcharge_can_make_a_buy_unaffordable_and_the_shop_stays_open :: proc(t: ^testing.T) {
	// #124: a buy the cargo can't cover *once the surcharge is applied* is refused
	// exactly like any other unaffordable buy — nothing spent, no Refit — and the
	// shop stays open. Size the cargo so the first buy (tier price) fits but the
	// second (tier + step) does not.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	base := ship.ship_item_cost(.Splash) // the cheapest card the roster prices
	// Covers one buy at base with a little to spare, but not base + step for the next.
	ship.ship_stow_cargo(sim.player.layout, base + (base + voyage.SHOP_DEPTH_SURCHARGE_STEP) - 1)
	seat_at_shop(&sim, 1, flat_stock(.Splash), &events)

	// First buy at the plain tier price succeeds.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	refit_tick(&sim, &events)
	submit_refit(&sim, Refit_Finish{})
	refit_tick(&sim, &events)
	remaining := ship.ship_cargo(sim.player)
	testing.expect_value(t, remaining, base + voyage.SHOP_DEPTH_SURCHARGE_STEP - 1)

	// Second buy: base + step now exceeds the remaining cargo, so the surcharge alone
	// refuses it and the shop stays open.
	sim_submit_captain_choice(&sim, Command(Command_Choose_Option{selection = Option_Index(0)}))
	ev := refit_tick(&sim, &events)
	testing.expect(t, has_event(ev, Event_Purchase_Rejected))
	testing.expect(t, !has_event(ev, Event_Refit_Started))
	testing.expect_value(t, ship.ship_cargo(sim.player), remaining) // nothing spent
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


@(test)
a_burn_at_anchor_empties_one_fitting_and_leaves_it_installed :: proc(t: ^testing.T) {
	// The out-of-combat burn (#401): a captain lightens deliberately before sailing into
	// hidden water. The named fitting's cargo dies, the fitting itself stays in its slot,
	// and the Sim comes right back at anchor with the ship re-broadcast.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_tick(&sim, &events) // voyage start → at anchor
	before := ship.ship_cargo(sim.player)
	laden, _ := sim.player.layout[5].fitting.? // hold 2 (S), stowed at the start
	testing.expect(t, laden.cargo_held > 0)

	submit_refit(&sim, Refit_Jettison_Cargo{slot = 5})
	ev := refit_tick(&sim, &events)

	testing.expect(t, has_event(ev, Event_Cargo_Jettisoned))
	testing.expect(t, has_event(ev, Event_Ship_Updated))
	testing.expect(t, ship.ship_cargo(sim.player) < before) // the run's score really fell
	_, still_installed := sim.player.layout[5].fitting.?
	testing.expect(t, still_installed) // the fitting snaps back to its slot
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
	testing.expect(t, has_event(ev, Event_Travel_Options)) // still at anchor, still live
}

@(test)
a_burn_at_anchor_re_stows_what_is_left_and_repeats :: proc(t: ^testing.T) {
	// The burn is free and repeatable out of anchor, and the survivors re-stow after each
	// one — so a second burn on the same berth sheds strictly less than the first, exactly
	// as the in-battle heave does.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_tick(&sim, &events)

	submit_refit(&sim, Refit_Jettison_Cargo{slot = 5})
	refit_tick(&sim, &events)
	after_first := ship.ship_cargo(sim.player)
	refilled, _ := sim.player.layout[5].fitting.?
	testing.expect(t, refilled.cargo_held > 0) // the remainder water-filled back into it

	submit_refit(&sim, Refit_Jettison_Cargo{slot = 5})
	ev := refit_tick(&sim, &events)

	testing.expect(t, has_event(ev, Event_Cargo_Jettisoned))
	testing.expect(t, ship.ship_cargo(sim.player) < after_first)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Travel_Choice)
}

@(test)
a_burn_of_a_fitting_carrying_nothing_is_rejected :: proc(t: ^testing.T) {
	// A fitting with no load weighs nothing extra, so there is nothing to burn: refused
	// with the layout untouched, the same soft rejection the fit rule gives.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_tick(&sim, &events)
	empty, _ := sim.player.layout[2].fitting.? // the Gun Deck: all bulk, so no room to carry
	testing.expect_value(t, empty.cargo_held, 0)
	before := ship.ship_cargo(sim.player)

	submit_refit(&sim, Refit_Jettison_Cargo{slot = 2})
	ev := refit_tick(&sim, &events)

	testing.expect(t, has_event(ev, Event_Refit_Rejected))
	testing.expect(t, !has_event(ev, Event_Cargo_Jettisoned))
	testing.expect_value(t, ship.ship_cargo(sim.player), before)
}

@(test)
a_burn_inside_a_granted_refit_applies_and_stays_in_the_refit :: proc(t: ^testing.T) {
	// The burn is available on both surfaces (#401), so a granted Refit takes it too and
	// stays open for the next edit like every other loadout operation.
	sim := sim_create(0)
	defer sim_destroy(&sim)
	events: [dynamic]Event
	defer delete(events)

	sim_tick(&sim, &events)
	sim_open_refit(&sim, ship.ship_fitting_top_crew(), &events)
	before := ship.ship_cargo(sim.player)

	submit_refit(&sim, Refit_Jettison_Cargo{slot = 5})
	ev := refit_tick(&sim, &events)

	testing.expect(t, has_event(ev, Event_Cargo_Jettisoned))
	testing.expect(t, ship.ship_cargo(sim.player) < before)
	testing.expect_value(t, sim.phase, Phase.Awaiting_Refit)
}
