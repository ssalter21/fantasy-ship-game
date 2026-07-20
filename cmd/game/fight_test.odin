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

	presses, sails, jettisons, break_offs, reallocs := 0, 0, 0, 0, 0
	laden_holds := 0
	for layout_slot in state.player.layout {
		if fitting, has := layout_slot.fitting.?; has && fitting.cargo_held > 0 {
			laden_holds += 1
		}
	}
	for a in actions[:n] {
		switch c in a.command {
		case combat.Command_Press:
			presses += 1
		case combat.Command_Man_The_Sails:
			sails += 1
		case combat.Command_Jettison_Cargo:
			jettisons += 1
		case combat.Command_Break_Off:
			break_offs += 1
		case combat.Command_Reallocate:
			reallocs += 1
		case combat.Command_Hold:
		// not offered on the captain's menu
		}
	}

	testing.expect(t, presses == len(ship.Category)) // one Press per combat phase
	testing.expect(t, sails == 1)
	testing.expect(t, jettisons == laden_holds) // one Jettison per laden hold
	testing.expect(t, break_offs == 1)
	testing.expect(t, reallocs == 0) // in-battle Reallocate retired (#305)
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
fight_exchange_batches_a_round_and_drains_both_hulls :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)
	opponent := ship.ship_starting_ship()
	defer delete(opponent.layout)
	state.sighted_opponent = opponent
	state.in_battle = true

	player_hull_before := state.player.hull
	opp_hull_before := opponent.hull

	// A round's two hits accumulate into one pending exchange and drain each struck hull as
	// they land — the opponent's, which no Event_Ship_Updated carries, and the player's.
	dispatch_battle_event(&state, combat.Event(combat.Event_Damage_Dealt{target = .B, damage = 10}))
	dispatch_battle_event(&state, combat.Event(combat.Event_Damage_Dealt{target = .A, damage = 6}))

	testing.expect(t, state.exchange_active)
	testing.expect(t, state.pending_exchange[.A] == 6)
	testing.expect(t, state.pending_exchange[.B] == 10)
	testing.expect(t, state.player.hull == player_hull_before - 6)
	opp, ok := state.sighted_opponent.?
	testing.expect(t, ok && opp.hull == opp_hull_before - 10)

	// The round boundary flushes the exchange (the beat itself is a no-op without a window),
	// clearing the pending damage so the next round starts fresh.
	fight_flush_exchange(&state)
	testing.expect(t, !state.exchange_active)
	testing.expect(t, state.pending_exchange[.A] == 0 && state.pending_exchange[.B] == 0)
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
