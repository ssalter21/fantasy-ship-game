package main

import "core:fmt"
import "core:strings"
import combat "../../core/combat"
import voyage "../../core/voyage"
import ship "../../core/ship"
import sim "../../core/sim"
import rl "vendor:raylib"

BEAT_MAX_SECONDS :: 1.2

// play_beat blocks in a short render loop showing overlay until the player
// clicks/presses a key or BEAT_MAX_SECONDS elapses (ADR-0002). It clones overlay
// first because callers commonly pass temp-allocator memory (fmt.tprintf/
// battle_event_text) and this loop's own draw_scene frees the temp allocator every
// frame, which would corrupt a borrowed overlay after the first frame.
play_beat :: proc(state: ^Game_State, overlay: string) {
	if !rl.IsWindowReady() {
		return
	}
	stable_overlay := strings.clone(overlay)
	defer delete(stable_overlay)

	elapsed: f32
	for !rl.WindowShouldClose() {
		elapsed += rl.GetFrameTime()
		draw_scene(state, stable_overlay)
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
	for !rl.WindowShouldClose() {
		draw_scene(state, "Click a highlighted node to travel there.")

		if rl.IsMouseButtonPressed(.LEFT) {
			mouse := rl.GetMousePosition()
			for dest in state.travel_options {
				if rl.CheckCollisionPointCircle(mouse, state.positions[dest], NODE_RADIUS) {
					return sim.Command(sim.Command_Travel_To{node_id = dest})
				}
			}
		}
	}
	// Window closing without a pick: return the first emitted option — a legal move that
	// winds the voyage down cleanly on quit. travel_options is always non-empty at a
	// travel decision (every non-Haven node has a forward edge); the assert makes that
	// invariant load-bearing rather than risking an out-of-bounds index.
	assert(len(state.travel_options) > 0, "travel_menu_loop reached a travel decision with no emitted options")
	return sim.Command(sim.Command_Travel_To{node_id = state.travel_options[0]})
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
// It owns its own frame loop (like option_menu_loop and refit_menu_loop) rather than
// delegating, because Reallocate takes two clicks — a source hold then a destination —
// and the menu shows a different button list in each mode. The half-made selection
// (reallocate_from) is a local, not a Game_State field: the loop blocks until one whole
// command is chosen, so unlike a Refit's move it never outlives the call. Buttons are
// rebuilt each frame in the temp allocator and the picked action is copied out before
// free_all, so the per-frame free draw_ship_panel relies on can't corrupt them.
battle_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		return sim.Command(sim.Command_Battle_Choice{combat_command = combat.Command(combat.Command_Hold{})})
	}

	reallocate_from: Maybe(ship.Slot_Index)

	for !rl.WindowShouldClose() {
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
		draw_scene_contents(state, prompt)
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
	return sim.Command(sim.Command_Battle_Choice{combat_command = combat.Command(combat.Command_Hold{})})
}

// ITEM_OFFER_BOX_* and the offer column origin size the Item Offer's option boxes: each
// is tall enough for a name line plus two detail lines, stacked under the ship panel.
ITEM_OFFER_BOX_W :: 340
ITEM_OFFER_BOX_H :: 62
ITEM_OFFER_Y0 :: 296

// option_menu_loop is the one option-list screen (issue #131): it blocks until the
// player takes a presented option or declines, then returns a Command_Choose_Option —
// an Option_Index for a take, or nil to decline. One loop serves both Item Offer and
// shop shelf, since the Sim presents a single list (Event_Options_Presented) that
// differs only in whether options carry prices.
//
// It reads what it's rendering off the options themselves: any priced option makes it a
// shop (show cargo, offer Leave); an unpriced list is an Offer (offer Skip). An
// unaffordable card is drawn dimmed but still clickable — the Sim owns affordability and
// bounces an unaffordable buy back as Event_Purchase_Rejected, so the menu never gates
// the click itself.
//
// A box index is its option's Option_Index, so an empty position is drawn as a
// non-clickable gap rather than skipped, keeping indices aligned with the Sim's list.
option_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): decline rather than take an option
		// and open a refit the test harness can't drive.
		return sim.Command(sim.Command_Choose_Option{selection = nil})
	}
	options := state.stage_options
	priced := option_list_is_priced(options)

	// One clickable box per option position, plus a trailing decline box. The boxes
	// are laid out once; rendering (rich multi-line text) and hit-testing both read
	// them.
	boxes: [sim.STAGE_OPTION_MAX + 1]rl.Rectangle
	for i in 0 ..< len(boxes) {
		boxes[i] = rl.Rectangle {
			x      = SHIP_PANEL_X,
			y      = f32(ITEM_OFFER_Y0 + i * (ITEM_OFFER_BOX_H + 6)),
			width  = ITEM_OFFER_BOX_W,
			height = ITEM_OFFER_BOX_H,
		}
	}
	decline_index := len(boxes) - 1

	header := "Choose an item to take, or skip."
	decline_label := "Skip (take nothing)"
	if priced {
		header = fmt.tprintf("Shop - cargo: %d. Buy an item, or leave.", ship.ship_cargo(state.player))
		decline_label = "Leave (buy nothing)"
	}

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		draw_scene_contents(state, header)
		for slot, i in options {
			if option, filled := slot.?; filled {
				draw_option_box(boxes[i], option, ship.ship_cargo(state.player))
			}
		}
		draw_labeled_box(boxes[decline_index], decline_label, "", "")
		rl.EndDrawing()
		free_all(context.temp_allocator)

		if rl.IsMouseButtonPressed(.LEFT) {
			mouse := rl.GetMousePosition()
			for box, i in boxes {
				if !rl.CheckCollisionPointRec(mouse, box) {
					continue
				}
				if i == decline_index {
					return sim.Command(sim.Command_Choose_Option{selection = nil})
				}
				// A click on an empty position takes nothing — the Sim has no option
				// there; ignore it so only real options and the decline are actionable.
				if _, filled := options[i].?; !filled {
					continue
				}
				return sim.Command(sim.Command_Choose_Option{selection = sim.Option_Index(i)})
			}
		}
	}
	// Window closing without a choice: decline cleanly.
	return sim.Command(sim.Command_Choose_Option{selection = nil})
}

// option_list_is_priced reports whether any option carries a price — how the menu tells
// a shop's shelf from an Offer's items without the Sim naming the primitive. Costs are
// per-option, so it asks the list rather than assuming the stage.
option_list_is_priced :: proc(options: [sim.STAGE_OPTION_MAX]Maybe(sim.Stage_Option)) -> bool {
	for slot in options {
		if option, filled := slot.?; filled {
			if _, has_cost := option.cost.?; has_cost {
				return true
			}
		}
	}
	return false
}

// draw_option_box renders one presented option as a titled box: its name (with the price
// alongside where it has one), then its size · phase · tags spec and effect-intent lines.
// A priced option costing more than `cargo` is dimmed so an unaffordable buy reads as
// such before the click; a free option is never dimmed.
draw_option_box :: proc(box: rl.Rectangle, option: sim.Stage_Option, cargo: int) {
	spec, intent := fitting_summary_lines(option.fitting)
	cost, priced := option.cost.?
	affordable := !priced || cost <= cargo

	title := option.fitting.name
	if priced {
		title = fmt.tprintf("%s  -  %d cargo", option.fitting.name, cost)
	}
	if affordable {
		draw_labeled_box(box, title, spec, intent)
		return
	}

	rl.DrawRectangleRec(box, rl.Color{210, 210, 210, 255})
	rl.DrawRectangleLinesEx(box, 1, rl.DARKGRAY)
	x := i32(box.x + 8)
	rl.DrawText(fmt.ctprintf("%s", title), x, i32(box.y + 6), 16, rl.GRAY)
	rl.DrawText(fmt.ctprintf("%s", spec), x, i32(box.y + 26), 12, rl.DARKGRAY)
	rl.DrawText(fmt.ctprintf("%s", intent), x, i32(box.y + 42), 12, rl.DARKGRAY)
}

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

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		draw_scene_contents(state, fmt.tprintf("%s - a permanent trade. Accept, or sail on.", trade.name))
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
	// Window closing without an answer: reject cleanly.
	return sim.Command(sim.Command_Trade_Choice{accept = false})
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

// refit_menu_loop is the manual-loadout screen (issue #96, ADR-0012's Refit): it blocks
// until the player commits one loadout operation, then returns that single Command_Refit —
// run_session ticks it and re-enters for the next, so a whole loadout edit is a sequence
// of these calls. The interaction:
//   - With an item pending (just picked from an Item Offer): click an empty slot to
//     Install it, or a filled slot to Replace its occupant (discarded — no inventory).
//   - With nothing pending (rearranging): click a filled slot to select it, then an empty
//     slot to Move it there (or the same slot again to cancel).
//   - Finish ends the refit (discarding any still-unplaced item).
// The exact-size fit rule is the Sim's, not the menu's to predict: the menu emits the
// Install/Replace/Move command and an illegal one comes back as Event_Refit_Rejected,
// leaving the layout untouched (issue #111).
refit_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		return sim.Command(sim.Command_Refit{command = sim.Refit_Finish{}})
	}

	slot_count := len(state.player.layout)
	// One box per slot, plus a trailing Finish box.
	boxes := make([]rl.Rectangle, slot_count + 1)
	defer delete(boxes)
	for i in 0 ..< len(boxes) {
		boxes[i] = rl.Rectangle {
			x      = SHIP_PANEL_X,
			y      = f32(300 + i * 30),
			width  = 300,
			height = 26,
		}
	}
	finish_index := slot_count

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		draw_scene_contents(state, refit_prompt(state))
		draw_refit_incoming(state)
		draw_refit_boxes(state, boxes, finish_index)
		rl.EndDrawing()
		free_all(context.temp_allocator)

		if rl.IsMouseButtonPressed(.LEFT) {
			mouse := rl.GetMousePosition()
			for box, i in boxes {
				if !rl.CheckCollisionPointRec(mouse, box) {
					continue
				}
				if cmd, ready := refit_click(state, i, finish_index); ready {
					return cmd
				}
			}
		}
	}
	return sim.Command(sim.Command_Refit{command = sim.Refit_Finish{}})
}

// refit_click maps a click on slot box `i` (or the Finish box) to the loadout operation
// it commits, or updates the in-progress move selection and reports "not ready" so
// refit_menu_loop keeps blocking. See refit_menu_loop for the interaction rules.
refit_click :: proc(state: ^Game_State, i: int, finish_index: int) -> (sim.Command, bool) {
	if i == finish_index {
		return sim.Command(sim.Command_Refit{command = sim.Refit_Finish{}}), true
	}

	slot := ship.Slot_Index(i)
	_, occupied := state.player.layout[i].fitting.?

	if _, has_incoming := state.refit_incoming.?; has_incoming {
		// Placing an item: an empty slot installs it, a filled slot swaps it in
		// (Refit_Replace, discarding the occupant — no inventory). Fit is the Sim's call,
		// not the menu's (ADR-0004); the menu picks the operation from whether the slot is
		// filled and never re-checks the fit here.
		if occupied {
			return sim.Command(sim.Command_Refit{command = sim.Refit_Replace{slot = slot}}), true
		}
		return sim.Command(sim.Command_Refit{command = sim.Refit_Install{slot = slot}}), true
	}

	// Rearranging: first click selects a filled source, second click moves it to
	// an empty slot (or the same slot again cancels the selection).
	from, selecting := state.refit_move_from.?
	if !selecting {
		if occupied {
			state.refit_move_from = slot
		}
		return {}, false
	}
	if slot == from {
		state.refit_move_from = nil // cancel
		return {}, false
	}
	if occupied {
		state.refit_move_from = slot // reselect a different source
		return {}, false
	}
	state.refit_move_from = nil
	return sim.Command(sim.Command_Refit{command = sim.Refit_Move{from = from, to = slot}}), true
}

// refit_prompt is the one-line instruction at the bottom of the refit screen, reflecting
// what the next click will do in the current mode.
refit_prompt :: proc(state: ^Game_State) -> string {
	if incoming, has_incoming := state.refit_incoming.?; has_incoming {
		return fmt.tprintf("Placing %s: click an empty %v slot to install, or a filled %v slot to swap.", incoming.name, incoming.size, incoming.size)
	}
	if from, selecting := state.refit_move_from.?; selecting {
		name := state.player.layout[from].slot.name
		return fmt.tprintf("Moving from %s: click an empty same-size slot, or %s again to cancel.", name, name)
	}
	return "Refit: click a filled slot to move it, or Finish."
}

// draw_refit_incoming draws the pending item's details (tags/phase/size/effect intent)
// above the slot list; nothing is drawn during a rearrange-only refit.
draw_refit_incoming :: proc(state: ^Game_State) {
	incoming, has_incoming := state.refit_incoming.?
	if !has_incoming {
		return
	}
	spec, intent := fitting_summary_lines(incoming)
	x := i32(SHIP_PANEL_X)
	rl.DrawText(fmt.ctprintf("Placing: %s", incoming.name), x, 262, 16, rl.MAROON)
	rl.DrawText(fmt.ctprintf("%s   %s", spec, intent), x, 282, 12, rl.DARKGRAY)
}

// draw_refit_boxes draws the clickable slot rows and the Finish box, highlighting a slot
// currently selected as a move source.
draw_refit_boxes :: proc(state: ^Game_State, boxes: []rl.Rectangle, finish_index: int) {
	for box, i in boxes {
		if i == finish_index {
			rl.DrawRectangleRec(box, rl.BEIGE)
			rl.DrawRectangleLinesEx(box, 1, rl.DARKGRAY)
			rl.DrawText("Finish refit", i32(box.x + 8), i32(box.y + 6), 14, rl.BLACK)
			continue
		}
		selected := false
		if from, selecting := state.refit_move_from.?; selecting {
			selected = i == int(from)
		}
		fill := selected ? rl.GOLD : rl.LIGHTGRAY
		rl.DrawRectangleRec(box, fill)
		rl.DrawRectangleLinesEx(box, 1, rl.DARKGRAY)

		layout_slot := state.player.layout[i]
		label: string
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
			label = fmt.tprintf("%s: %s (%v)", layout_slot.slot.name, fitting.name, layout_slot.slot.size)
		} else {
			label = fmt.tprintf("%s: (empty, %v)", layout_slot.slot.name, layout_slot.slot.size)
		}
		rl.DrawText(fmt.ctprintf("%s", label), i32(box.x + 8), i32(box.y + 6), 14, rl.BLACK)
	}
}
