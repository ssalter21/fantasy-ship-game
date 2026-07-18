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

// play_stage_entry_beat announces a Reward stage (issue #139). Reward is the one stage
// primitive that parks on no screen of its own — a Fight, Offer, Shop, or Trade each
// present their own menu — so it pays out and the walk carries straight on, and without
// this beat its loot is cargo that grew silently. Exactly one beat, only for the stage
// with no screen.
play_stage_entry_beat :: proc(state: ^Game_State, e: sim.Event_Stage_Entered) {
	if e.kind != .Reward {
		return
	}
	stage, known := encounter_stage(state, e.index)
	if !known {
		return
	}
	reward, is_reward := stage.(voyage.Stage_Reward)
	if !is_reward {
		return
	}
	// The overflow (#157) the reward can't fit, named at the ship seam rather than by
	// capacity math in the render layer. It reads state.player pre-payout — a Reward
	// changes no slots, so current capacity is the real one — and predicts the loss,
	// because the beat runs before the stow (Event_Stage_Entered precedes it) and so
	// cannot read ship_stow_cargo's return.
	spilled := ship.ship_stow_spill(state.player, ship.ship_cargo(state.player) + reward.cargo)
	play_beat(state, fmt.tprintf("Salvage! You haul aboard %d cargo.%s", reward.cargo, spill_note(spilled)))
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
	case combat.Event_Damage_Dealt:
		return fmt.tprintf("%v takes %d damage!", e.target, e.final_damage)
	case combat.Event_Ship_Sunk:
		return fmt.tprintf("%v's ship is sunk!", e.side)
	case combat.Event_Cargo_Jettisoned:
		return fmt.tprintf("%v jettisons %s!", e.side, e.fitting.name)
	case combat.Event_Cargo_Reallocated:
		return fmt.tprintf("%v shifts %d cargo between holds.", e.side, e.amount)
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
// playback) is fight.odin, #315: battle_menu_loop and the round-beat batching moved there
// when the modal button list and the in-battle Reallocate retired. battle_event_text above
// stays here beside the other beat-text builders, reused by the Fight's Ship_Sunk /
// Break_Off / Battle_Ended and jettison beats.

// The travel screen (the between-encounters decision) is now Home — the persistent Build
// surface with the chart raised over it (build_surface.odin, #317, ADR-0024): the modal
// chart-as-Home retired into home_loop, which does free refit at anchor and offers the same
// node hit-test over the Sim's emitted travel options. get_captain_choice's
// Awaiting_Travel_Choice case now enters home_loop.

// ITEM_OFFER_BOX_* and the offer column origin size the Trade screen's two boxes: each is
// tall enough for a name line plus two detail lines, stacked under the ship panel. (They
// once sized the option-list boxes too, before that screen became the Offer/Shop Build
// surface in #312; the Trade screen is the remaining programmer-art holdout, #318's job.)
ITEM_OFFER_BOX_W :: 340
ITEM_OFFER_BOX_H :: 62
ITEM_OFFER_Y0 :: 296

// The option-list screen (issue #131) is now the Offer/Shop Build surface + shelf
// (offer_shop.odin, #312): the click-a-box list retired into the Cutaway ship with a
// right-side shelf you drag cards from. get_captain_choice's Awaiting_Option_Choice case
// now enters offer_shop_loop.

// trade_stat_label names a tradeable stat for the player (issue #136): the enum's own
// spelling (Max_Hull) isn't presentable.
trade_stat_label :: proc(stat: voyage.Trade_Stat) -> string {
	switch stat {
	case .Hull:
		return "Hull"
	case .Max_Hull:
		return "Max Hull"
	case .Durability:
		return "Durability"
	case .Cargo:
		return "cargo"
	}
	return "?"
}

// trade_term_line renders one side of a bargain as a signed, named quantity. A Trade_Term
// stores only the positive magnitude (the side it sits on carries the direction), so the
// sign is supplied here at the point the player reads it.
trade_term_line :: proc(term: voyage.Trade_Term, sign: string) -> string {
	return fmt.tprintf("%s%d %s", sign, term.amount, trade_stat_label(term.stat))
}

// trade_menu_loop is the Trade screen (issue #136, ADR-0014): it blocks until the player
// accepts or rejects the bargain, then returns a Command_Trade_Choice. Accepting applies
// the swap permanently and completes the stage; rejecting halts the encounter, changing
// nothing.
//
// An unaffordable accept (state.trade_can_accept, off Event_Trade_Presented) is drawn
// dimmed and is **not** clickable — the opposite of the shop's unaffordable card. A shop
// has an Event_Purchase_Rejected to say no with and stays open for another choice; a
// Trade's only other answer is to reject, so a Sim-side refusal would have nowhere to
// return to, and submitting one is a driver bug the Sim asserts on.
trade_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): reject rather than permanently
		// swap a stat the test harness never chose.
		return sim.Command(sim.Command_Trade_Choice{accept = false})
	}
	trade := state.active_trade

	boxes: [2]rl.Rectangle
	for i in 0 ..< len(boxes) {
		boxes[i] = rl.Rectangle {
			x      = SHIP_PANEL_X,
			y      = f32(ITEM_OFFER_Y0 + i * (ITEM_OFFER_BOX_H + 6)),
			width  = ITEM_OFFER_BOX_W,
			height = ITEM_OFFER_BOX_H,
		}
	}
	accept_index :: 0
	reject_index :: 1

	for {
		window_quit_if_closed()
		rl.BeginDrawing()
		draw_scene_contents(state, fmt.tprintf("%s - a permanent trade. Accept, or sail on.", trade.name), rl.Vector2{-1, -1})
		draw_trade_accept_box(boxes[accept_index], trade, state.trade_can_accept)
		draw_labeled_box(boxes[reject_index], "Reject (sail on)", "Nothing changes.", "")
		rl.EndDrawing()
		free_all(context.temp_allocator)

		if rl.IsMouseButtonPressed(.LEFT) {
			mouse := rl.GetMousePosition()
			if state.trade_can_accept && rl.CheckCollisionPointRec(mouse, boxes[accept_index]) {
				return sim.Command(sim.Command_Trade_Choice{accept = true})
			}
			if rl.CheckCollisionPointRec(mouse, boxes[reject_index]) {
				return sim.Command(sim.Command_Trade_Choice{accept = false})
			}
		}
	}
}

// draw_trade_accept_box renders the bargain's accept option — what it gives against what
// it takes — dimmed when the ship can't pay the cost. Mirrors the shop card's
// affordable/unaffordable treatment, so "you can't pay for this" looks the same wherever
// the player meets it.
draw_trade_accept_box :: proc(box: rl.Rectangle, trade: voyage.Stage_Trade, can_accept: bool) {
	fill := can_accept ? rl.LIGHTGRAY : rl.Color{210, 210, 210, 255}
	rl.DrawRectangleRec(box, fill)
	rl.DrawRectangleLinesEx(box, 1, rl.DARKGRAY)

	title := can_accept ? "Accept" : "Accept (you can't pay this)"
	text := can_accept ? rl.BLACK : rl.GRAY
	x := i32(box.x + 8)
	rl.DrawText(fmt.ctprintf("%s", title), x, i32(box.y + 6), 16, text)
	rl.DrawText(fmt.ctprintf("Gain %s", trade_term_line(trade.gain, "+")), x, i32(box.y + 26), 12, rl.DARKGRAY)
	rl.DrawText(fmt.ctprintf("Cost %s", trade_term_line(trade.cost, "-")), x, i32(box.y + 42), 12, rl.DARKGRAY)
}

// draw_labeled_box draws a bordered box with a title line and up to two smaller detail
// lines, shared by the Item Offer options and the Skip box. Empty detail strings are skipped.
draw_labeled_box :: proc(box: rl.Rectangle, title: string, line1: string, line2: string) {
	rl.DrawRectangleRec(box, rl.LIGHTGRAY)
	rl.DrawRectangleLinesEx(box, 1, rl.DARKGRAY)
	x := i32(box.x + 8)
	rl.DrawText(fmt.ctprintf("%s", title), x, i32(box.y + 6), 16, rl.BLACK)
	if len(line1) > 0 {
		rl.DrawText(fmt.ctprintf("%s", line1), x, i32(box.y + 26), 12, rl.DARKGRAY)
	}
	if len(line2) > 0 {
		rl.DrawText(fmt.ctprintf("%s", line2), x, i32(box.y + 42), 12, rl.DARKGRAY)
	}
}

// The Refit screen has moved to the drag-first Build surface (build_surface.odin, #302):
// the modal click-a-slot loop retired into a persistent Cutaway the player drags fittings
// around. get_captain_choice's Awaiting_Refit case now enters build_surface_loop.
