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

// play_battle_event_beat plays one combat round event's beat and, once the
// battle has ended, clears the in-battle UI state.
play_battle_event_beat :: proc(state: ^Game_State, event: combat.Event) {
	if !rl.IsWindowReady() {
		return
	}
	play_beat(state, battle_event_text(event))
	if _, ended := event.(combat.Event_Battle_Ended); ended {
		state.in_battle = false
		state.sighted_opponent = nil
	}
}

Button :: struct {
	rect:    rl.Rectangle,
	label:   string,
}

// clicked_button returns the index of the first button the mouse clicked
// this frame, or -1.
clicked_button :: proc(buttons: []Button) -> int {
	if !rl.IsMouseButtonPressed(.LEFT) {
		return -1
	}
	mouse := rl.GetMousePosition()
	for b, i in buttons {
		if rl.CheckCollisionPointRec(mouse, b.rect) {
			return i
		}
	}
	return -1
}

draw_buttons :: proc(buttons: []Button) {
	for b in buttons {
		rl.DrawRectangleRec(b.rect, rl.LIGHTGRAY)
		rl.DrawRectangleLinesEx(b.rect, 1, rl.DARKGRAY)
		rl.DrawText(fmt.ctprintf("%s", b.label), i32(b.rect.x + 8), i32(b.rect.y + 8), 14, rl.BLACK)
	}
}

// travel_menu_loop blocks until the player clicks one of the currently-legal
// destination nodes (the ones draw_map rings and numbers), then returns a
// Command_Travel_To (ADR-0002). Clicks on non-reachable nodes are ignored: the UI
// offers exactly the moves the Sim emitted on Event_Travel_Options
// (state.travel_options), the same set the Sim gates travel on.
travel_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): the session isn't gated, so any
		// emitted option is a safe placeholder; fall back to the current node when none.
		if len(state.travel_options) > 0 {
			return sim.Command(sim.Command_Travel_To{node_id = state.travel_options[0]})
		}
		return sim.Command(sim.Command_Travel_To{node_id = state.current_node_id})
	}
	for {
		window_quit_if_closed()
		draw_scene(state, "Click a highlighted node to travel there.", rl.GetMousePosition())

		if rl.IsMouseButtonPressed(.LEFT) {
			mouse := rl.GetMousePosition()
			for dest in state.travel_options {
				if rl.CheckCollisionPointCircle(mouse, state.positions[dest], NODE_RADIUS) {
					return sim.Command(sim.Command_Travel_To{node_id = dest})
				}
			}
		}
	}
}

// Battle_Menu_Action is what clicking a battle-menu button does: submit a finished
// combat command, or drive the two-click Reallocate selection (pick a source hold, or
// cancel back to the command list). Reallocate is the one battle command needing two
// clicks, so a click can change the menu's mode instead of returning a command.
Battle_Menu_Action_Kind :: enum {
	Submit,
	Select_Source,
	Cancel_Reallocate,
}

Battle_Menu_Action :: struct {
	kind:    Battle_Menu_Action_Kind,
	command: combat.Command, // meaningful when kind == .Submit
	slot:    ship.Slot_Index, // the source, meaningful when kind == .Select_Source
}

// battle_reallocate_can_receive reports whether cargo can be poured into slot `i`.
// Mirrors combat_apply_reallocate's destination rule so the battle menu offers only
// destinations that would move cargo — the combat layer then asserts rather than validates.
battle_reallocate_can_receive :: proc(s: ship.Ship, i: ship.Slot_Index) -> bool {
	layout_slot := s.layout[i]
	fitting, has_fitting := layout_slot.fitting.?
	if !has_fitting {
		return true
	}
	if !fitting.is_cargo {
		return false
	}
	return fitting.stack_count < ship.ship_cargo_slot_contribution(layout_slot.slot.size)
}

// battle_reallocate_can_give reports whether slot `i` can be a Reallocate source: it
// holds cargo and some other slot can receive it, so offering it always leads to a legal
// move rather than a dead-end selection.
battle_reallocate_can_give :: proc(s: ship.Ship, i: ship.Slot_Index) -> bool {
	fitting, has_fitting := s.layout[i].fitting.?
	if !has_fitting || !fitting.is_cargo || fitting.stack_count < 1 {
		return false
	}
	for _, j in s.layout {
		to := ship.Slot_Index(j)
		if to != i && battle_reallocate_can_receive(s, to) {
			return true
		}
	}
	return false
}

// battle_menu_loop blocks until the player picks a battle action, then returns a
// Command_Battle_Choice (ADR-0006's one-decision-per-round menu).
//
// It owns its own frame loop (like offer_shop_loop and build_surface_loop) rather than
// delegating, because Reallocate takes two clicks — a source hold then a destination —
// and the menu shows a different button list in each mode. The half-made selection
// (reallocate_from) is a local, not a Game_State field: the loop blocks until one whole
// command is chosen, so unlike a Refit's move it never outlives the call. Buttons are
// rebuilt each frame in the temp allocator and the picked action is copied out before
// free_all, so the per-frame free draw_ship_panel relies on can't corrupt them.
battle_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		// The Hold is built through a local rather than inlined into the literal:
		// dev-2026-06 folds a fully-constant *nested* union literal to a nil inner
		// tag, so the inlined form returns a Command_Battle_Choice whose
		// combat_command is nil. Same lb_const_value fault as the ci.yml pin
		// comment describes, but silent here where dev-2026-07 panics. A local
		// makes the value non-constant and the tag survives. Inline it again once
		// the pin moves to a nightly that folds this correctly.
		hold := combat.Command(combat.Command_Hold{})
		return sim.Command(sim.Command_Battle_Choice{combat_command = hold})
	}

	reallocate_from: Maybe(ship.Slot_Index)

	for {
		window_quit_if_closed()
		buttons := make([dynamic]Button, context.temp_allocator)
		actions := make([dynamic]Battle_Menu_Action, context.temp_allocator)
		prompt: string
		y: f32 = 440

		if from, selecting := reallocate_from.?; selecting {
			// Destination-selection mode: one button per legal destination, then Cancel.
			prompt = fmt.tprintf("Reallocating from %s: click a hold to pour it into, or Cancel.", state.player.layout[from].slot.name)
			for layout_slot, i in state.player.layout {
				to := ship.Slot_Index(i)
				if to == from || !battle_reallocate_can_receive(state.player, to) {
					continue
				}
				append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = fmt.tprintf("Pour into %s", layout_slot.slot.name)})
				append(&actions, Battle_Menu_Action{kind = .Submit, command = combat.Command(combat.Command_Reallocate{from = from, to = to})})
				y += 34
			}
			append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = "Cancel"})
			append(&actions, Battle_Menu_Action{kind = .Cancel_Reallocate})
		} else {
			// Command mode: the one-decision-per-round action list.
			prompt = "Choose your captain's command."
			for category in ship.Category {
				append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = fmt.tprintf("Press %v", category)})
				append(&actions, Battle_Menu_Action{kind = .Submit, command = combat.Command(combat.Command_Press{phase = category})})
				y += 34
			}

			append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = "Man the Sails"})
			append(&actions, Battle_Menu_Action{kind = .Submit, command = combat.Command(combat.Command_Man_The_Sails{})})
			y += 34

			for layout_slot, i in state.player.layout {
				fitting, has_fitting := layout_slot.fitting.?
				if !has_fitting || !fitting.is_cargo {
					continue
				}
				append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = fmt.tprintf("Jettison %s", fitting.name)})
				append(&actions, Battle_Menu_Action{kind = .Submit, command = combat.Command(combat.Command_Jettison_Cargo{slot_index = ship.Slot_Index(i)})})
				y += 34
			}

			// Reallocate: one entry per hold that can give (has cargo and somewhere to
			// pour it), selecting that hold as the source and entering destination mode.
			for layout_slot, i in state.player.layout {
				src_slot := ship.Slot_Index(i)
				if !battle_reallocate_can_give(state.player, src_slot) {
					continue
				}
				append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = fmt.tprintf("Reallocate from %s", layout_slot.slot.name)})
				append(&actions, Battle_Menu_Action{kind = .Select_Source, slot = src_slot})
				y += 34
			}

			if state.may_break_off {
				append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = "Break Off"})
				append(&actions, Battle_Menu_Action{kind = .Submit, command = combat.Command(combat.Command_Break_Off{})})
				y += 34
			}
		}

		rl.BeginDrawing()
		draw_scene_contents(state, prompt, rl.Vector2{-1, -1})
		draw_buttons(buttons[:])
		rl.EndDrawing()

		picked := clicked_button(buttons[:])
		picked_action: Maybe(Battle_Menu_Action)
		if picked >= 0 {
			picked_action = actions[picked]
		}
		free_all(context.temp_allocator)

		if act, ok := picked_action.?; ok {
			switch act.kind {
			case .Submit:
				return sim.Command(sim.Command_Battle_Choice{combat_command = act.command})
			case .Select_Source:
				reallocate_from = act.slot
			case .Cancel_Reallocate:
				reallocate_from = nil
			}
		}
	}
}

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
