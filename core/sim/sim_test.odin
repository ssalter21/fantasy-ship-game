package sim

import "../combat"
import "../run"
import "../testutil"
import "core:testing"

@(test)
traveling_directly_to_goal_skips_every_encounter_and_wins :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)

	// Start=0, Coastal Port=1, Open_Sea Port=6, Deep Port=11, Goal=16 — free
	// travel has no adjacency gating (ADR-0007), so this skips every
	// Encounter point entirely.
	input_state := Scripted_Input_State{
		choices = []Command{
			Command(Command_Travel_To{point_id = 1}),
			Command(Command_Travel_To{point_id = 6}),
			Command(Command_Travel_To{point_id = 11}),
			Command(Command_Travel_To{point_id = 16}),
		},
	}
	input := Input_Source{data = &input_state, get_captain_choice = scripted_input_get_captain_choice}

	sink_state := Recording_Sink_State{}
	defer recording_sink_destroy(&sink_state)
	sink := Event_Sink{data = &sink_state, dispatch = recording_sink_dispatch}

	run_session(&sim, input, sink)

	testing.expect_value(t, sim.status, run.Run_Status.Won)
	last := sink_state.events[len(sink_state.events)-1]
	ended, ok := last.(Event_Run_Ended)
	testing.expect(t, ok)
	testing.expect_value(t, ended.status, run.Run_Status.Won)
}

@(test)
boosting_offensive_wins_the_first_coastal_ship_battle_and_the_run_continues_to_goal :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)

	// Point 2 is the first Coastal Encounter (Ship_Battle, port_closeness=3
	// per zone_encounter_kinds). Boosting Offensive 3 rounds straight sinks
	// the opponent (hp 16 -> 9 -> 2 -> -5) while the player survives
	// (hp 20 -> 14 -> 8 -> 2), hand-computed from run_pve_opponent/
	// ship_starting_ship's fixed placeholder constants.
	input_state := Scripted_Input_State{
		choices = []Command{
			Command(Command_Travel_To{point_id = 2}),
			Command(Command_Battle_Choice{combat_command = combat.Command_Boost{phase = .Offensive}}),
			Command(Command_Battle_Choice{combat_command = combat.Command_Boost{phase = .Offensive}}),
			Command(Command_Battle_Choice{combat_command = combat.Command_Boost{phase = .Offensive}}),
			Command(Command_Travel_To{point_id = 16}),
		},
	}
	input := Input_Source{data = &input_state, get_captain_choice = scripted_input_get_captain_choice}

	sink_state := Recording_Sink_State{}
	defer recording_sink_destroy(&sink_state)
	sink := Event_Sink{data = &sink_state, dispatch = recording_sink_dispatch}

	run_session(&sim, input, sink)

	testing.expect_value(t, sim.status, run.Run_Status.Won)
	testing.expect_value(t, sim.player.hp, 2)

	battle_ended_found := false
	for event in sink_state.events {
		wrapped, is_battle_event := event.(Event_Battle_Event)
		if !is_battle_event {
			continue
		}
		ended, is_ended := wrapped.inner.(combat.Event_Battle_Ended)
		if !is_ended {
			continue
		}
		battle_ended_found = true
		testing.expect_value(t, ended.reason, combat.End_Reason.Destroyed)
		winner, has_winner := ended.winner.?
		testing.expect(t, has_winner)
		testing.expect_value(t, winner, combat.Side.A)
	}
	testing.expect(t, battle_ended_found)
}

@(test)
picking_the_gun_deck_upgrade_option_replaces_the_gun_deck_fitting :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)

	// Point 4 is Coastal's Upgrade_Offer point (quality = 1*15 = 15, bonus =
	// 15/5 = 3, so option 2's Gun Deck upgrade carries magnitude 5+3=8).
	input_state := Scripted_Input_State{
		choices = []Command{
			Command(Command_Travel_To{point_id = 4}),
			Command(Command_Pick_Upgrade{option_index = 2}),
			Command(Command_Travel_To{point_id = 16}),
		},
	}
	input := Input_Source{data = &input_state, get_captain_choice = scripted_input_get_captain_choice}

	sink_state := Recording_Sink_State{}
	defer recording_sink_destroy(&sink_state)
	sink := Event_Sink{data = &sink_state, dispatch = recording_sink_dispatch}

	run_session(&sim, input, sink)

	testing.expect_value(t, sim.status, run.Run_Status.Won)
	gun_deck, has_fitting := sim.player.layout[2].fitting.?
	testing.expect(t, has_fitting)
	testing.expect_value(t, gun_deck.name, "Upgraded Gun Deck")
	active, has_active := gun_deck.active.?
	testing.expect(t, has_active)
	testing.expect_value(t, active.magnitude, 8)
}

@(test)
arriving_at_a_stat_trade_point_applies_it_immediately_with_no_decision :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)

	// Point 5 is Coastal's Stat_Trade point (gain_durability = 1*8 = 8,
	// cost_speed = 1*1 = 1) — applies on arrival, no captain decision.
	input_state := Scripted_Input_State{
		choices = []Command{
			Command(Command_Travel_To{point_id = 5}),
			Command(Command_Travel_To{point_id = 16}),
		},
	}
	input := Input_Source{data = &input_state, get_captain_choice = scripted_input_get_captain_choice}

	sink_state := Recording_Sink_State{}
	defer recording_sink_destroy(&sink_state)
	sink := Event_Sink{data = &sink_state, dispatch = recording_sink_dispatch}

	run_session(&sim, input, sink)

	testing.expect_value(t, sim.status, run.Run_Status.Won)
	testing.expect_value(t, sim.player.durability, 2+8)
	testing.expect_value(t, sim.player.speed, 4-1)
}

@(test)
revisiting_a_resolved_encounter_point_does_not_retrigger_it :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)

	// Free travel has no adjacency gating (ADR-0007), so nothing stops
	// traveling back to point 5 (Stat_Trade) after already resolving it —
	// but its effect must fire only once (issue #24 design decision).
	input_state := Scripted_Input_State{
		choices = []Command{
			Command(Command_Travel_To{point_id = 5}),
			Command(Command_Travel_To{point_id = 1}),
			Command(Command_Travel_To{point_id = 5}),
			Command(Command_Travel_To{point_id = 16}),
		},
	}
	input := Input_Source{data = &input_state, get_captain_choice = scripted_input_get_captain_choice}

	sink_state := Recording_Sink_State{}
	defer recording_sink_destroy(&sink_state)
	sink := Event_Sink{data = &sink_state, dispatch = recording_sink_dispatch}

	run_session(&sim, input, sink)

	testing.expect_value(t, sim.status, run.Run_Status.Won)
	testing.expect_value(t, sim.player.durability, 2+8)
	testing.expect_value(t, sim.player.speed, 4-1)
}

@(test)
holding_every_round_against_a_tough_opponent_can_lose_the_run :: proc(t: ^testing.T) {
	sim := sim_create(0)
	defer sim_destroy(&sim)

	// Point 2 (first Coastal Ship_Battle, port_closeness=3) deals 6 dmg/round
	// to a Holding player (raw 13 vs durability 2 + defense 5) while the
	// player's own Hold deals 0 (raw 8 vs durability 4 + defense 5) — hand
	// computed from run_pve_opponent/ship_starting_ship's fixed placeholder
	// constants. Player hp 20 -> 14 -> 8 -> 2 -> -4 (0): sunk on round 4.
	input_state := Scripted_Input_State{
		choices = []Command{
			Command(Command_Travel_To{point_id = 2}),
			Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}}),
			Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}}),
			Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}}),
			Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}}),
		},
	}
	input := Input_Source{data = &input_state, get_captain_choice = scripted_input_get_captain_choice}

	sink_state := Recording_Sink_State{}
	defer recording_sink_destroy(&sink_state)
	sink := Event_Sink{data = &sink_state, dispatch = recording_sink_dispatch}

	run_session(&sim, input, sink)

	testing.expect_value(t, sim.status, run.Run_Status.Lost)
	testing.expect_value(t, sim.player.hp, 0)
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

Scripted_Input_State :: struct {
	choices: []Command,
	index:   int,
}

scripted_input_get_captain_choice :: proc(data: rawptr, awaiting: Phase) -> Command {
	state := cast(^Scripted_Input_State)data
	assert(state.index < len(state.choices), "scripted input exhausted its scripted choices")
	cmd := state.choices[state.index]
	state.index += 1
	return cmd
}

unreachable_get_captain_choice :: proc(data: rawptr, awaiting: Phase) -> Command {
	panic("input source should not be asked for a decision when the run ends without needing one")
}
