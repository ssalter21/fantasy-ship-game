package main

import "core:fmt"
import "core:strings"
import combat "../../core/combat"
import voyage "../../core/voyage"
import ship "../../core/ship"
import sim "../../core/sim"
import rl "vendor:raylib"

BEAT_MAX_SECONDS :: 1.2

// play_beat blocks in a short render loop rendering the shared playback overlay (#304)
// over the current stage until the player clicks/presses a key or BEAT_MAX_SECONDS elapses
// (ADR-0002). It clones the headline first because callers commonly pass temp-allocator
// memory (fmt.tprintf/battle_event_text) and this loop's own draw_beat frees the temp
// allocator every frame, which would corrupt a borrowed headline after the first frame.
play_beat :: proc(state: ^Game_State, headline: string) {
	if !rl.IsWindowReady() {
		return
	}
	stable_headline := strings.clone(headline)
	defer delete(stable_headline)

	elapsed: f32
	for {
		window_quit_if_closed()
		elapsed += rl.GetFrameTime()
		draw_beat(state, stable_headline)
		if elapsed > BEAT_MAX_SECONDS || rl.IsKeyPressed(.SPACE) || rl.IsMouseButtonPressed(.LEFT) {
			return
		}
	}
}

// reward_beat_text renders a Reward stage's payout beat (issue #139): Reward is the one
// stage primitive that parks on no screen of its own — a Fight, Offer, Shop, or Trade
// each present their own menu — so without this beat its loot is cargo that grew
// silently. `gross` and `spilled` come off Event_Reward_Paid, the stow's own outcome.
reward_beat_text :: proc(gross: int, spilled: int) -> string {
	return fmt.tprintf("Salvage! You haul aboard %d cargo.%s", gross, spill_note(spilled))
}

// spill_note is the clause a payout beat appends when a full hold sent cargo overboard
// (#157); empty when nothing spilled.
spill_note :: proc(spilled: int) -> string {
	if spilled <= 0 {
		return ""
	}
	return fmt.tprintf(" %d spills overboard — your hold is full.", spilled)
}

// wreck_loot_beat_text renders a won Fight's payout beat (issue #201): `gross` is the
// wreck's whole hold, `spilled` (from Event_Wreck_Looted) the part that overflowed the
// player's capacity.
wreck_loot_beat_text :: proc(gross: int, spilled: int) -> string {
	return fmt.tprintf("You loot the wreck: %d cargo.%s", gross, spill_note(spilled))
}

// halt_beat_text renders a halt as its consequence (issue #139, ADR-0014): what the
// captain did to halt, and the downstream stages it forfeited. Naming the forfeited
// stages is the point — complete-or-halt has no "no loot if you run" gate (the Reward
// stage is simply never reached), so a fled `[Fight, Reward]` would otherwise read
// identically to a plain `[Fight]` ending. The stages are those behind the cursor, which
// the Sim's event picks out with index and count.
halt_beat_text :: proc(state: ^Game_State, e: sim.Event_Encounter_Halted) -> string {
	forfeited := forfeited_stages_label(state, e)
	if len(forfeited) == 0 {
		return fmt.tprintf("%s The encounter ends here.", halt_verb(e.at))
	}
	return fmt.tprintf("%s You leave behind: %s.", halt_verb(e.at), forfeited)
}

// halt_verb says what the captain did to halt, in that primitive's own terms (issue
// #139). Shop and Reward can't halt — a shop can't be failed, a Reward has nothing to
// decline — so reaching them here is a Sim-side impossibility, panicked on rather than
// given words.
halt_verb :: proc(at: voyage.Stage_Kind) -> string {
	switch at {
	case .Fight:
		return "You break off and slip away."
	case .Offer:
		return "You take nothing."
	case .Trade:
		return "You turn the bargain down."
	case .Shop, .Reward:
		panic("an encounter halted on a primitive that has no halt")
	}
	unreachable()
}

// forfeited_stages_label names the stages a halt never reached — everything behind the
// cursor — as a comma-separated list, or "" when the halt was on the last stage.
forfeited_stages_label :: proc(state: ^Game_State, e: sim.Event_Encounter_Halted) -> string {
	label := ""
	for i in e.index + 1 ..< e.count {
		kind, known := encounter_stage_kind(state, i)
		if !known {
			continue
		}
		if len(label) == 0 {
			label = stage_kind_label(kind)
		} else {
			label = fmt.tprintf("%s, %s", label, stage_kind_label(kind))
		}
	}
	return label
}

// battle_event_text renders one core/combat Event as a human-readable beat.
battle_event_text :: proc(event: combat.Event) -> string {
	switch e in event {
	case combat.Event_Hull_Repaired:
		return fmt.tprintf("%v repairs %d hull.", e.side, e.amount)
	case combat.Event_Damage_Dealt:
		return fmt.tprintf("%v takes %d damage!", e.target, e.damage)
	case combat.Event_Round_Resolved:
		// The round's closing hull report is render state, not a beat: dispatch_battle_event
		// lands it silently, so it has no line.
		return ""
	case combat.Event_Ship_Sunk:
		return fmt.tprintf("%v's ship is sunk!", e.side)
	case combat.Event_Cargo_Jettisoned:
		return fmt.tprintf("%v jettisons %s!", e.side, e.fitting.name)
	case combat.Event_Battle_Ended:
		switch e.reason {
		case .Destroyed:
			return "The battle ends in destruction."
		case .Broke_Off:
			return "A ship flees the battle."
		case .Round_Cap:
			return "The battle ends in a stalemate."
		}
	}
	return ""
}

// The Fight screen (facing cutaways, the captain action-row, and per-round-exchange
// playback) is fight.odin, #315. battle_event_text above stays here beside the other
// beat-text builders, reused by the Fight's Ship_Sunk / Break_Off / Battle_Ended and
// jettison beats.
