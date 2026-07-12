package sim

import "../combat"
import "../run"
import "../testutil"
import "core:testing"

// The map is procedurally generated per seed now, so these end-to-end
// scenarios can't hardcode node ids. Instead they build the same map the Sim
// will (run_map_create is deterministic per seed), compute a legal forward
// route through it with the path helpers below, and drive it with Auto_Pilot.
// The chosen seeds are fixed so each scenario reproduces exactly.

is_battle_node :: proc(m: run.Map, id: int) -> bool {
	enc, ok := m.nodes[id].encounter.?
	if !ok {
		return false
	}
	_, is_battle := enc.(run.Encounter_Ship_Battle)
	return is_battle
}

// forward_route returns the travel targets (excluding the starting node) of a
// forward Start-to-Goal path from `from`, choosing at each step the forward
// neighbor that minimizes (or, when maximize, maximizes) the number of Ship
// Battle nodes stepped on. A battle-minimizing route from Start is battle-free
// whenever the graph admits one; a battle-maximizing route deliberately walks
// into every fight. Caller owns the returned slice.
forward_route :: proc(m: run.Map, from: int, maximize: bool) -> []int {
	n := len(m.nodes)
	goal := -1
	for p in m.nodes {
		if p.kind == .Goal {
			goal = p.id
		}
	}

	best := make([]int, n)
	next_node := make([]int, n)
	defer delete(best)
	defer delete(next_node)
	for i in 0 ..< n {
		next_node[i] = -1
	}

	// DP over layers, deepest first: best[u] = battles on the chosen route
	// from u onward.
	for layer := m.nodes[goal].layer; layer >= 0; layer -= 1 {
		for p in m.nodes {
			if p.layer != layer {
				continue
			}
			if p.id == goal {
				best[p.id] = 0
				continue
			}
			chosen := -1
			chosen_cost := 0
			for v in m.edges[p.id] {
				if m.nodes[v].layer <= p.layer {
					continue // forward edges only
				}
				better := chosen < 0 || (maximize ? best[v] > chosen_cost : best[v] < chosen_cost)
				if better {
					chosen = v
					chosen_cost = best[v]
				}
			}
			best[p.id] = (is_battle_node(m, p.id) ? 1 : 0) + chosen_cost
			next_node[p.id] = chosen
		}
	}

	route: [dynamic]int
	cur := from
	for cur != goal {
		cur = next_node[cur]
		append(&route, cur)
	}
	return route[:]
}

// route_through_first_coastal_battle steps first into a layer-1 (Coastal,
// shallowest) Ship Battle neighbor of Start, then takes the battle-minimizing
// route onward — a route that fights exactly one shallow battle and then
// coasts to Goal. Returns nil if Start has no layer-1 battle neighbor for this
// seed. Caller owns the returned slice.
route_through_first_coastal_battle :: proc(m: run.Map) -> []int {
	first := -1
	for v in m.edges[0] {
		if m.nodes[v].layer == 1 && is_battle_node(m, v) {
			first = v
			break
		}
	}
	if first < 0 {
		return nil
	}
	tail := forward_route(m, first, false)
	defer delete(tail)
	route := make([]int, 1 + len(tail))
	route[0] = first
	copy(route[1:], tail)
	return route
}

// Auto_Pilot drives run_session from a precomputed travel route: it feeds the
// route's node ids one per travel prompt, replies to every battle prompt with
// battle_cmd, and picks upgrade_index at every Upgrade Offer. The route ends
// at Goal, so run_session stops asking for travel exactly when the route runs
// out.
Auto_Pilot :: struct {
	route:         []int,
	index:         int,
	battle_cmd:    combat.Command,
	upgrade_index: Option_Index,
}

auto_pilot_choice :: proc(data: rawptr, awaiting: Phase) -> Command {
	pilot := cast(^Auto_Pilot)data
	switch awaiting {
	case .Awaiting_Travel_Choice:
		target := pilot.route[pilot.index]
		pilot.index += 1
		return Command(Command_Travel_To{node_id = Node_ID(target)})
	case .Awaiting_Battle_Command:
		return Command(Command_Battle_Choice{combat_command = pilot.battle_cmd})
	case .Awaiting_Upgrade_Choice:
		return Command(Command_Pick_Upgrade{option_index = pilot.upgrade_index})
	case .Ended:
		panic("auto pilot asked for a choice after the run ended")
	}
	panic("unreachable")
}

// Pilot_Result captures the outcome fields a scenario asserts on, read out
// before the Sim's arena is torn down.
Pilot_Result :: struct {
	status:        run.Run_Status,
	hp:            int,
	durability:    int,
	speed:         int,
	gun_deck_name: string,
	battles_won:   int,
}

// drive_route runs a full session over a fixed seed with an Auto_Pilot on the
// given route and returns the outcome.
drive_route :: proc(seed: u64, route: []int, battle_cmd: combat.Command, upgrade_index: int) -> Pilot_Result {
	sim := sim_create(seed)
	defer sim_destroy(&sim)

	pilot := Auto_Pilot{route = route, battle_cmd = battle_cmd, upgrade_index = Option_Index(upgrade_index)}
	input := Input_Source{data = &pilot, get_captain_choice = auto_pilot_choice}

	sink_state := Recording_Sink_State{}
	defer recording_sink_destroy(&sink_state)
	sink := Event_Sink{data = &sink_state, dispatch = recording_sink_dispatch}

	run_session(&sim, input, sink)

	res := Pilot_Result {
		status     = sim.status,
		hp         = sim.player.hp,
		durability = sim.player.durability,
		speed      = sim.player.speed,
	}
	if gun_deck, ok := sim.player.layout[2].fitting.?; ok {
		res.gun_deck_name = gun_deck.name
	}
	for event in sink_state.events {
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
	// The graph forces a route through some node per layer, but a
	// battle-minimizing course dodges every fight, so the ship reaches Goal
	// unscathed — the redesign's "travel to Goal wins" over a real graph.
	m := run.run_map_create(0)
	defer run.run_map_destroy(&m)
	route := forward_route(m, 0, false)
	defer delete(route)

	res := drive_route(0, route, combat.Command(BOOST_OFFENSIVE), 2)
	testing.expect_value(t, res.status, run.Run_Status.Won)
	testing.expect_value(t, res.hp, 20) // untouched: no battle fought
}

@(test)
fighting_a_coastal_ship_battle_can_be_won :: proc(t: ^testing.T) {
	// Route into one shallow Coastal battle and boost Offensive: the fresh
	// ship wins it and sails on to Goal, taking some damage along the way.
	m := run.run_map_create(2)
	defer run.run_map_destroy(&m)
	route := route_through_first_coastal_battle(m)
	testing.expect(t, route != nil)
	defer delete(route)

	res := drive_route(2, route, combat.Command(BOOST_OFFENSIVE), 2)
	testing.expect_value(t, res.status, run.Run_Status.Won)
	testing.expect(t, res.battles_won >= 1)
	testing.expect(t, res.hp < 20) // a real fight cost some HP
}

@(test)
routing_through_every_battle_can_lose_the_run :: proc(t: ^testing.T) {
	// A battle-maximizing course walks into fight after fight; a starting ship
	// bleeds out before Goal — permadeath at 0 HP, unchanged. Seed 1's map has
	// a battle-max route long enough to be lethal (seed 0's is survivable).
	m := run.run_map_create(1)
	defer run.run_map_destroy(&m)
	route := forward_route(m, 0, true)
	defer delete(route)

	res := drive_route(1, route, combat.Command(HOLD), 0)
	testing.expect_value(t, res.status, run.Run_Status.Lost)
	testing.expect_value(t, res.hp, 0)
}

@(test)
picking_the_gun_deck_upgrade_on_the_route_upgrades_the_gun_deck :: proc(t: ^testing.T) {
	// The battle-free route passes through Upgrade Offers; picking option 2 at
	// each replaces the Gun Deck fitting with its upgraded variant.
	m := run.run_map_create(0)
	defer run.run_map_destroy(&m)
	route := forward_route(m, 0, false)
	defer delete(route)

	res := drive_route(0, route, combat.Command(BOOST_OFFENSIVE), 2)
	testing.expect_value(t, res.status, run.Run_Status.Won)
	testing.expect_value(t, res.gun_deck_name, "Upgraded Gun Deck")
}

@(test)
stat_trades_on_the_route_permanently_change_stats :: proc(t: ^testing.T) {
	// The battle-free route passes through Stat Trades, each applied on arrival
	// with no decision: Durability rises above its starting 2, Speed falls
	// below its starting 4.
	m := run.run_map_create(0)
	defer run.run_map_destroy(&m)
	route := forward_route(m, 0, false)
	defer delete(route)

	res := drive_route(0, route, combat.Command(BOOST_OFFENSIVE), 2)
	testing.expect_value(t, res.status, run.Run_Status.Won)
	testing.expect(t, res.durability > 2)
	testing.expect(t, res.speed < 4)
}

@(test)
revisiting_a_resolved_encounter_does_not_retrigger_it :: proc(t: ^testing.T) {
	// Retrace is a legal, free routing tool: arrive at a Stat Trade, retrace to
	// the already-visited Start, then step forward onto that Stat Trade again.
	// The second arrival must be a no-op, so the run ends in exactly the same
	// ship state as one that never retraced.
	m := run.run_map_create(0)
	defer run.run_map_destroy(&m)

	// A layer-1 Stat Trade is a Start neighbor, so retrace to Start (id 0) and
	// back to it is legal.
	trade := -1
	for v in m.edges[0] {
		if m.nodes[v].layer != 1 {
			continue
		}
		if enc, ok := m.nodes[v].encounter.?; ok {
			if _, is_trade := enc.(run.Encounter_Stat_Trade); is_trade {
				trade = v
				break
			}
		}
	}
	testing.expect(t, trade >= 0)

	tail := forward_route(m, trade, false)
	defer delete(tail)

	straight := make([]int, 1 + len(tail))
	straight[0] = trade
	copy(straight[1:], tail)
	defer delete(straight)

	// Same route, but with a retrace to Start and back inserted before the tail.
	retraced := make([]int, 3 + len(tail))
	retraced[0] = trade
	retraced[1] = 0
	retraced[2] = trade
	copy(retraced[3:], tail)
	defer delete(retraced)

	baseline := drive_route(0, straight, combat.Command(BOOST_OFFENSIVE), 0)
	revisited := drive_route(0, retraced, combat.Command(BOOST_OFFENSIVE), 0)

	testing.expect_value(t, revisited.status, run.Run_Status.Won)
	testing.expect(t, revisited.durability > 2) // the trade did fire once
	// Retracing over the resolved trade changed nothing.
	testing.expect_value(t, revisited.durability, baseline.durability)
	testing.expect_value(t, revisited.speed, baseline.speed)
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
	target := -1
	for v in sim.run_map.edges[0] {
		if sim.run_map.nodes[v].kind == .Encounter {
			target = v
			break
		}
	}
	testing.expect(t, target >= 0)

	sim_submit_captain_choice(&sim, Command(Command_Travel_To{node_id = Node_ID(target)}))
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
	sim_submit_captain_choice(&sim, Command(Command_Pick_Upgrade{option_index = 0}))
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

Recording_Sink_State :: struct {
	events: [dynamic]Event,
}

recording_sink_dispatch :: proc(data: rawptr, event: Event) {
	state := cast(^Recording_Sink_State)data
	append(&state.events, event)
}

// recording_sink_destroy frees the recorded events slice itself.
// Event_Encounter_Resolved.snapshot needs no per-event cleanup: it lives in
// the Sim's own run-scoped arena, still alive here since every test defers
// this call before its own defer sim_destroy(&sim) (issue #52) — the arena
// itself is only reclaimed once that later-registered defer runs.
recording_sink_destroy :: proc(state: ^Recording_Sink_State) {
	delete(state.events)
}
