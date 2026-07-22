package main

import "core:fmt"
import "core:testing"
import combat "../../core/combat"
import ship "../../core/ship"

// The Fight screen's decision logic tested as pure functions the way build_drop_command and
// offer_shop_drop_command are — no window, so `odin test` exercises the action set, the escape
// readout, and the round-exchange batching without a render loop.

@(test)
fight_action_commands_offers_the_round_menu :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	actions, n := fight_action_commands(&state)

	presses, commits, jettisons, break_offs, holds, steps := 0, 0, 0, 0, 0, 0
	for a in actions[:n] {
		if a.kind == .Open_Targets {
			steps += 1 // Jettison, which opens its target step rather than submitting
			continue
		}
		switch c in a.command {
		case combat.Command_Press:
			presses += 1
		case combat.Command_Commit:
			commits += 1
		case combat.Command_Jettison_Cargo:
			jettisons += 1
		case combat.Command_Break_Off:
			break_offs += 1
		case combat.Command_Hold:
			holds += 1
		}
	}

	// The captain's whole order set, and nothing else: a Press per phase, Commit,
	// Jettison, Break Off, Hold. However laden the ship is, the row stays this length —
	// Jettison names its target in a second step, so no hold ever adds a button here.
	testing.expect(t, presses == len(ship.Phase)) // one Press per combat phase
	testing.expect(t, commits == 1)
	testing.expect(t, steps == 1) // the one Jettison
	testing.expect(t, jettisons == 0) // no slot index until the second step
	testing.expect(t, break_offs == 1)
	testing.expect(t, holds == 1)
	testing.expect(t, n == presses + commits + steps + break_offs + holds)
}

// Jettison's second step: the row becomes the ship's laden fittings, one button each, and
// clicking one submits the heave outright — picking the target *is* the confirmation, so
// nothing further is asked. Belay backs out, carrying no command like the Jettison that
// opened the step.
@(test)
fight_jettison_opens_a_target_step_of_the_laden_fittings :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	laden: [dynamic]int
	defer delete(laden)
	for layout_slot, i in state.player.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting && fitting.cargo_held > 0 {
			append(&laden, i)
		}
	}
	testing.expect(t, len(laden) > 0) // the starting ship sails laden

	state.jettison_targeting = true
	actions, n := fight_action_commands(&state)

	testing.expect_value(t, n, len(laden) + 1) // a target each, plus Belay
	for slot, i in laden {
		heave, is_heave := actions[i].command.(combat.Command_Jettison_Cargo)
		testing.expect(t, is_heave && actions[i].enabled && actions[i].kind == .Submit)
		testing.expect_value(t, int(heave.slot_index), slot)
	}
	testing.expect(t, actions[n - 1].kind == .Belay) // and a way back out that submits nothing
}

// With nothing aboard to throw over the side there is no heave to take, so the order is
// offered-but-dimmed rather than opening an empty target step.
@(test)
fight_jettison_is_untakeable_with_an_empty_hold :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	jettison_enabled :: proc(state: ^Game_State) -> (enabled: bool, found: bool) {
		actions, n := fight_action_commands(state)
		for a in actions[:n] {
			if a.kind == .Open_Targets {
				return a.enabled, true
			}
		}
		return false, false
	}

	enabled, found := jettison_enabled(&state)
	testing.expect(t, found && enabled)

	ship.ship_stow_cargo(state.player.layout, 0)
	enabled, found = jettison_enabled(&state)
	testing.expect(t, found && !enabled)
}

// The Press ration reads off the menu flag the Sim sends: the button stays on the row once
// spent — the order set is fixed — but stops being takeable.
@(test)
fight_press_is_offered_but_untakeable_once_the_battles_press_is_spent :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	press_enabled :: proc(state: ^Game_State) -> (offered: int, enabled: int) {
		actions, n := fight_action_commands(state)
		for a in actions[:n] {
			if _, is_press := a.command.(combat.Command_Press); !is_press {
				continue
			}
			offered += 1
			if a.enabled {
				enabled += 1
			}
		}
		return
	}

	state.may_press = true
	offered, enabled := press_enabled(&state)
	testing.expect(t, offered == len(ship.Phase) && enabled == offered)

	state.may_press = false
	offered, enabled = press_enabled(&state)
	testing.expect(t, offered == len(ship.Phase) && enabled == 0)
}

@(test)
fight_break_off_is_enabled_only_when_escape_eligible :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	fight_break_off_enabled :: proc(state: ^Game_State) -> (enabled: bool, found: bool) {
		actions, n := fight_action_commands(state)
		for a in actions[:n] {
			if _, is_break := a.command.(combat.Command_Break_Off); is_break {
				return a.enabled, true
			}
		}
		return false, false
	}

	state.may_break_off = false
	enabled, found := fight_break_off_enabled(&state)
	testing.expect(t, found && !enabled) // offered but not takeable before escape opens

	state.may_break_off = true
	enabled, found = fight_break_off_enabled(&state)
	testing.expect(t, found && enabled)
}

@(test)
fight_escape_text_reads_the_escape_window :: proc(t: ^testing.T) {
	state := Game_State{}

	state.may_break_off = true
	testing.expect(t, fight_escape_text(&state) == "Break off ready")

	// Before the baseline round, a countdown to when escape opens.
	state.may_break_off = false
	state.battle_round = 0
	testing.expect(t, fight_escape_text(&state) == fmt.tprintf("escape opens in %d", combat.BASELINE_ROUND_COUNT))

	state.battle_round = combat.BASELINE_ROUND_COUNT - 1
	testing.expect(t, fight_escape_text(&state) == "escape opens in 1")

	// Past the baseline but not yet faster: nudge to win the speed edge.
	state.battle_round = combat.BASELINE_ROUND_COUNT
	testing.expect(t, fight_escape_text(&state) == "outpace them to break off")
}

@(test)
fight_exchange_batches_a_round_and_lands_hulls_from_the_round_report :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)
	opponent := ship.ship_starting_ship()
	defer delete(opponent.layout)
	state.sighted_opponent = opponent
	state.in_battle = true

	player_hull_before := state.player.hull
	opp_hull_before := opponent.hull

	// A round's two hits accumulate into one pending exchange — and move no hull. The
	// deltas are playback numbers only; the hulls land from the round's report (#429),
	// so presentation never re-derives or re-clamps a hull from a hit.
	dispatch_battle_event(&state, combat.Event(combat.Event_Damage_Dealt{target = .B, damage = 10}))
	dispatch_battle_event(&state, combat.Event(combat.Event_Damage_Dealt{target = .A, damage = 6}))

	testing.expect(t, state.exchange_active)
	testing.expect(t, state.pending_exchange[.A] == 6)
	testing.expect(t, state.pending_exchange[.B] == 10)
	testing.expect(t, state.player.hull == player_hull_before)
	opp, ok := state.sighted_opponent.?
	testing.expect(t, ok && opp.hull == opp_hull_before)

	// The round report writes both hulls as the Event states them — the opponent's, which
	// no Event_Ship_Updated carries, and the player's, kept in step until one re-lands it.
	report := combat.Event_Round_Resolved {
		round = 1,
		hull  = {.A = player_hull_before - 6, .B = opp_hull_before - 10},
	}
	dispatch_battle_event(&state, combat.Event(report))
	testing.expect(t, state.player.hull == player_hull_before - 6)
	opp, ok = state.sighted_opponent.?
	testing.expect(t, ok && opp.hull == opp_hull_before - 10)

	// The round boundary flushes the exchange (the beat itself is a no-op without a window),
	// clearing the pending damage so the next round starts fresh.
	fight_flush_exchange(&state)
	testing.expect(t, !state.exchange_active)
	testing.expect(t, state.pending_exchange[.A] == 0 && state.pending_exchange[.B] == 0)
}

// A repair plays as its own beat ahead of the round's guns (ADR-0027), so its event states
// the hull it leaves and the screen shows that number — not a locally-added delta (#429).
@(test)
fight_repair_beat_shows_the_hull_the_event_states :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)
	opponent := ship.ship_starting_ship()
	defer delete(opponent.layout)
	state.sighted_opponent = opponent
	state.in_battle = true

	dispatch_battle_event(&state, combat.Event(combat.Event_Hull_Repaired{side = .B, amount = 4, hull = 17}))
	opp, ok := state.sighted_opponent.?
	testing.expect(t, ok)
	testing.expect_value(t, opp.hull, 17)

	dispatch_battle_event(&state, combat.Event(combat.Event_Hull_Repaired{side = .A, amount = 2, hull = 9}))
	testing.expect_value(t, state.player.hull, 9)
}

@(test)
fight_battle_ended_event_tears_down_in_battle_state :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)
	opponent := ship.ship_starting_ship()
	defer delete(opponent.layout)
	state.sighted_opponent = opponent
	state.in_battle = true

	dispatch_battle_event(&state, combat.Event(combat.Event_Battle_Ended{reason = .Destroyed, winner = combat.Side.A}))

	testing.expect(t, !state.in_battle)
	_, still_sighted := state.sighted_opponent.?
	testing.expect(t, !still_sighted)
}
