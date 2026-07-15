package main

import "core:fmt"
import "core:strings"
import combat "../../core/combat"
import run "../../core/run"
import ship "../../core/ship"
import sim "../../core/sim"
import rl "vendor:raylib"

BEAT_MAX_SECONDS :: 1.2

// play_beat runs a short blocking render loop showing overlay until the
// player clicks/presses a key or a short timer elapses (ADR-0002's "UI
// plays this back with animation" — the minimal version: a readable pause
// rather than a frame-by-frame animation). Clones overlay into a
// persistent-allocator copy up front: callers commonly pass a
// fmt.tprintf/battle_event_text result (temp-allocator memory), and this
// loop's own draw_scene call frees the temp allocator every frame, which
// would otherwise corrupt overlay after the first frame.
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

// battle_event_text renders one core/combat Event as a human-readable beat.
battle_event_text :: proc(event: combat.Event) -> string {
	switch e in event {
	case combat.Event_Damage_Dealt:
		return fmt.tprintf("%v takes %d damage!", e.target, e.final_damage)
	case combat.Event_Ship_Sunk:
		return fmt.tprintf("%v's ship is sunk!", e.side)
	case combat.Event_Cargo_Jettisoned:
		return fmt.tprintf("%v jettisons %s!", e.side, e.fitting.name)
	case combat.Event_Battle_Ended:
		switch e.reason {
		case .Destroyed:
			return "The battle ends in destruction."
		case .Left_Combat:
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

// button_menu_loop blocks, drawing prompt and buttons each frame, until the
// player clicks one of buttons or the window closes. Returns the picked
// index, or -1 if the window closed without a pick. Used by battle_menu_loop;
// the Item Offer and Refit screens draw richer multi-line boxes and run their
// own loops instead.
button_menu_loop :: proc(state: ^Game_State, prompt: string, buttons: []Button) -> int {
	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		draw_scene_contents(state, prompt)
		draw_buttons(buttons)
		rl.EndDrawing()
		free_all(context.temp_allocator)

		picked := clicked_button(buttons)
		if picked >= 0 {
			return picked
		}
	}
	return -1
}

// travel_menu_loop blocks until the player clicks one of the currently-legal
// destination nodes (the ones draw_map rings and numbers), then returns a
// Command_Travel_To (ADR-0002). Clicks on non-reachable nodes are ignored, so
// the graph's connectivity is the actual constraint on movement — the UI
// offers exactly the moves the Sim emitted on Event_Travel_Options
// (state.travel_options), the same set the Sim gates travel on (issues #71,
// #83), no longer re-derived here.
travel_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): the specific id isn't
		// submitted to a real gated session, so any emitted option is a safe
		// placeholder; fall back to option 0 when none were recorded.
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
	// The window is closing without a pick. state.travel_options is the Sim's
	// emitted legal set for the current node — always non-empty at a travel
	// decision (every non-Goal node has a forward edge) — so return its first
	// entry: a legal move that winds the run down cleanly on quit, not the old
	// illegal self-move. The assert makes that invariant load-bearing rather
	// than risking an out-of-bounds index if it were ever violated.
	assert(len(state.travel_options) > 0, "travel_menu_loop reached a travel decision with no emitted options")
	return sim.Command(sim.Command_Travel_To{node_id = state.travel_options[0]})
}

// battle_menu_loop blocks until the player picks a battle action (Boost one
// of the three phases, Man the Sails, Jettison a cargo slot, or Leave
// Combat if may_leave — ADR-0006's one-decision-per-round menu), then
// returns a Command_Battle_Choice.
battle_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		return sim.Command(sim.Command_Battle_Choice{combat_command = combat.Command(combat.Command_Hold{})})
	}
	// Button labels are heap-allocated (fmt.aprintf, context.allocator) and
	// explicitly freed below, not built with fmt.tprintf: this loop calls
	// free_all(context.temp_allocator) once per frame (draw_ship_panel's own
	// per-frame labels rely on that), which would otherwise silently
	// corrupt these buttons' labels after the first frame, since they're
	// built once before the loop starts but read on every frame after.
	buttons := make([dynamic]Button)
	defer {
		for b in buttons {
			delete(b.label)
		}
		delete(buttons)
	}
	combat_commands := make([dynamic]combat.Command)
	defer delete(combat_commands)

	y : f32 = 440
	for category in ship.Category {
		append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = fmt.aprintf("Boost %v", category)})
		append(&combat_commands, combat.Command(combat.Command_Boost{phase = category}))
		y += 34
	}

	append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = fmt.aprintf("Man the Sails")})
	append(&combat_commands, combat.Command(combat.Command_Man_The_Sails{}))
	y += 34

	for layout_slot, i in state.player.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting || !fitting.is_cargo {
			continue
		}
		append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = fmt.aprintf("Jettison %s", fitting.name)})
		append(&combat_commands, combat.Command(combat.Command_Jettison_Cargo{slot_index = ship.Slot_Index(i)}))
		y += 34
	}

	if state.may_leave {
		append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = fmt.aprintf("Leave Combat")})
		append(&combat_commands, combat.Command(combat.Command_Leave_Combat{}))
		y += 34
	}

	picked := button_menu_loop(state, "Choose your captain's command.", buttons[:])
	if picked >= 0 {
		return sim.Command(sim.Command_Battle_Choice{combat_command = combat_commands[picked]})
	}
	return sim.Command(sim.Command_Battle_Choice{combat_command = combat.Command(combat.Command_Hold{})})
}

// ITEM_OFFER_BOX_H / _W and the offer column origin size the Item Offer's
// option boxes (issue #96): each item gets a box tall enough for a name line
// plus two detail lines, stacked under the ship panel with a Skip box last.
ITEM_OFFER_BOX_W :: 340
ITEM_OFFER_BOX_H :: 62
ITEM_OFFER_Y0 :: 296

// item_offer_menu_loop blocks until the player picks one of the offered roster
// items or skips (issue #96, ADR-0012), then returns a Command_Pick_Item — a
// selected Option_Index for a pick, or a nil selection for a skip. Each item box
// shows the item's size, phase, tags, and effect intent (the acceptance
// criteria's "tags, phase, size, and effect intent"), so the choice is informed.
// A pick opens a Refit (the Sim's response); this loop only reports the choice.
item_offer_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): skip rather than open a refit
		// the test harness can't drive.
		return sim.Command(sim.Command_Pick_Item{selection = nil})
	}
	options := state.item_offer_options

	// One clickable box per option, plus a trailing Skip box. The boxes are laid
	// out once; rendering (rich multi-line text) and hit-testing both read them.
	boxes: [run.ITEM_OFFER_OPTION_COUNT + 1]rl.Rectangle
	for i in 0 ..< len(boxes) {
		boxes[i] = rl.Rectangle {
			x      = SHIP_PANEL_X,
			y      = f32(ITEM_OFFER_Y0 + i * (ITEM_OFFER_BOX_H + 6)),
			width  = ITEM_OFFER_BOX_W,
			height = ITEM_OFFER_BOX_H,
		}
	}
	skip_index := len(boxes) - 1

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		draw_scene_contents(state, "Choose an item to take, or skip.")
		for option, i in options {
			draw_item_offer_box(boxes[i], option)
		}
		draw_labeled_box(boxes[skip_index], "Skip (take nothing)", "", "")
		rl.EndDrawing()
		free_all(context.temp_allocator)

		if rl.IsMouseButtonPressed(.LEFT) {
			mouse := rl.GetMousePosition()
			for box, i in boxes {
				if !rl.CheckCollisionPointRec(mouse, box) {
					continue
				}
				if i == skip_index {
					return sim.Command(sim.Command_Pick_Item{selection = nil})
				}
				return sim.Command(sim.Command_Pick_Item{selection = sim.Option_Index(i)})
			}
		}
	}
	// Window closing without a pick: skip cleanly.
	return sim.Command(sim.Command_Pick_Item{selection = nil})
}

// draw_item_offer_box renders one offered item as a titled box with its spec
// (size · phase · tags) and effect-intent detail lines (issue #96).
draw_item_offer_box :: proc(box: rl.Rectangle, f: ship.Fitting) {
	spec, intent := fitting_summary_lines(f)
	draw_labeled_box(box, f.name, spec, intent)
}

// shop_menu_loop is the Port shop screen (issue #123, ADR-0013): it blocks until
// the player buys one shelf card or leaves, then returns a Command_Buy_Item — a
// selected Option_Index for a buy, or a nil selection to leave. The shelf is a
// window onto the Port's persistent deck; buying opens a Refit and, on its finish,
// the Sim returns here with the shelf refilled (a fresh Event_Shop_Presented), so
// a player keeps buying until they Leave. Each card box shows the same size / phase
// / tags / effect intent as an Item Offer plus the card's price; a card the player
// can't currently afford is drawn dimmed but still clickable — the Sim owns
// affordability and bounces an unaffordable buy back as Event_Purchase_Rejected (a
// beat), so the menu never has to gate the click itself. A box index is its shelf
// slot's Option_Index, so an empty tail slot (nil card, only past the deck's end —
// never at the real roster size) is drawn as a non-clickable gap to keep indices
// aligned with the Sim's shelf.
shop_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): leave rather than buy a card and
		// open a refit the test harness can't drive.
		return sim.Command(sim.Command_Buy_Item{selection = nil})
	}
	shelf := state.shop_shelf

	// One box per shelf slot, plus a trailing Leave box — laid out once, read by
	// both rendering and hit-testing (mirrors item_offer_menu_loop).
	boxes: [run.SHOP_SHELF_SIZE + 1]rl.Rectangle
	for i in 0 ..< len(boxes) {
		boxes[i] = rl.Rectangle {
			x      = SHIP_PANEL_X,
			y      = f32(ITEM_OFFER_Y0 + i * (ITEM_OFFER_BOX_H + 6)),
			width  = ITEM_OFFER_BOX_W,
			height = ITEM_OFFER_BOX_H,
		}
	}
	leave_index := len(boxes) - 1

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		draw_scene_contents(state, fmt.tprintf("Port shop — treasure: %d. Buy an item, or leave.", state.player.starting_treasure))
		for slot, i in shelf {
			if card, filled := slot.?; filled {
				draw_shop_item_box(boxes[i], card, card.cost <= state.player.starting_treasure)
			}
		}
		draw_labeled_box(boxes[leave_index], "Leave (buy nothing)", "", "")
		rl.EndDrawing()
		free_all(context.temp_allocator)

		if rl.IsMouseButtonPressed(.LEFT) {
			mouse := rl.GetMousePosition()
			for box, i in boxes {
				if !rl.CheckCollisionPointRec(mouse, box) {
					continue
				}
				if i == leave_index {
					return sim.Command(sim.Command_Buy_Item{selection = nil})
				}
				// A click on an empty tail slot buys nothing — the Sim has no card
				// there; ignore it so only real cards and Leave are actionable.
				if _, filled := shelf[i].?; !filled {
					continue
				}
				return sim.Command(sim.Command_Buy_Item{selection = sim.Option_Index(i)})
			}
		}
	}
	// Window closing without a pick: leave cleanly.
	return sim.Command(sim.Command_Buy_Item{selection = nil})
}

// draw_shop_item_box renders one stocked item as a titled box (issue #98): the
// name and price on the title line, then the same size · phase · tags spec and
// effect-intent lines an Item Offer shows. `affordable` dims the whole box when
// the item costs more than the current purse, so an unaffordable buy reads as such
// before the click (the Sim still enforces it).
draw_shop_item_box :: proc(box: rl.Rectangle, item: run.Shop_Item, affordable: bool) {
	spec, intent := fitting_summary_lines(item.fitting)
	fill := affordable ? rl.LIGHTGRAY : rl.Color{210, 210, 210, 255}
	rl.DrawRectangleRec(box, fill)
	rl.DrawRectangleLinesEx(box, 1, rl.DARKGRAY)
	text := affordable ? rl.BLACK : rl.GRAY
	x := i32(box.x + 8)
	rl.DrawText(fmt.ctprintf("%s  —  %d treasure", item.fitting.name, item.cost), x, i32(box.y + 6), 16, text)
	rl.DrawText(fmt.ctprintf("%s", spec), x, i32(box.y + 26), 12, rl.DARKGRAY)
	rl.DrawText(fmt.ctprintf("%s", intent), x, i32(box.y + 42), 12, rl.DARKGRAY)
}

// trade_stat_label names a tradeable stat for the player (issue #136). The enum's
// own spelling is close but not presentable (Max_HP), and a Trade is the first
// screen that shows a stat by name rather than as a labeled row of the ship panel.
trade_stat_label :: proc(stat: run.Trade_Stat) -> string {
	switch stat {
	case .HP:
		return "HP"
	case .Max_HP:
		return "Max HP"
	case .Durability:
		return "Durability"
	case .Speed:
		return "Speed"
	case .Treasure:
		return "treasure"
	}
	return "?"
}

// trade_term_line renders one side of a bargain as a signed, named quantity —
// "+8 Durability", "-1 Speed". A Trade_Term stores only the positive magnitude
// (the side it sits on carries the direction), so the sign is supplied here at
// the point the player reads it.
trade_term_line :: proc(term: run.Trade_Term, sign: string) -> string {
	return fmt.tprintf("%s%d %s", sign, term.amount, trade_stat_label(term.stat))
}

// trade_menu_loop is the Trade screen (issue #136, ADR-0014): it blocks until the
// player accepts or rejects the bargain, then returns a Command_Trade_Choice.
// Accepting applies the swap permanently and completes the stage; rejecting halts
// the encounter, changing nothing. Both sides are rendered as signed named
// quantities so the swap is legible before it is permanent.
//
// An accept the ship can't pay for (state.trade_can_accept, straight off
// Event_Trade_Presented) is drawn dimmed and is **not** clickable. This is the
// opposite of the shop's unaffordable card, which stays clickable and bounces off
// the Sim as a rejected purchase: a shop has an Event_Purchase_Rejected to say no
// with and stays open for another choice, whereas a Trade's only other answer is
// to reject it — so a Sim-side refusal would have nowhere to return to, and
// submitting one is a driver bug the Sim asserts on rather than a rejection it
// reports.
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
		draw_scene_contents(state, fmt.tprintf("%s — a permanent trade. Accept, or sail on.", trade.name))
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

// draw_trade_accept_box renders the bargain's accept option: what it gives against
// what it takes, dimmed when the ship can't pay the cost (issue #136). Mirrors
// draw_shop_item_box's affordable/unaffordable treatment, so "you can't pay for
// this" looks the same wherever the player meets it.
draw_trade_accept_box :: proc(box: rl.Rectangle, trade: run.Stage_Trade, can_accept: bool) {
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

// draw_labeled_box draws a bordered box with a bold-ish title line and up to two
// smaller detail lines (issue #96) — shared by the Item Offer options and the
// Skip box. Empty detail strings are skipped.
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

// refit_menu_loop is the manual-loadout screen (issue #96, ADR-0012's Refit): it
// blocks until the player commits one loadout operation, then returns that
// single Command_Refit — run_session ticks it and re-enters this loop for the
// next, so a whole loadout edit is a sequence of these calls. The interaction:
//   - With an item pending (just picked from an Item Offer): click an empty slot
//     to Install it there, or a filled slot to Replace its occupant (the swapped-
//     out fitting is discarded, no inventory) — the place-or-swap path.
//   - With nothing pending (rearranging): click a filled slot to select it, then
//     an empty slot to Move it there (or the same slot again to cancel).
//   - Finish ends the refit (discarding any still-unplaced item — no inventory).
// The exact-size fit rule is the Sim's to enforce, not the menu's to predict: the
// menu emits the Install/Replace/Move command and an illegal one comes back as
// Event_Refit_Rejected (a beat), leaving the layout untouched (issue #111).
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

// refit_click maps a click on slot box `i` (or the Finish box) to the loadout
// operation it commits, or updates the in-progress move selection and reports
// "not ready" so refit_menu_loop keeps blocking (issue #96). See refit_menu_loop
// for the interaction rules this encodes.
refit_click :: proc(state: ^Game_State, i: int, finish_index: int) -> (sim.Command, bool) {
	if i == finish_index {
		return sim.Command(sim.Command_Refit{command = sim.Refit_Finish{}}), true
	}

	slot := ship.Slot_Index(i)
	_, occupied := state.player.layout[i].fitting.?

	if _, has_incoming := state.refit_incoming.?; has_incoming {
		// Placing an item: an empty slot installs it, a filled slot swaps it in
		// (Refit_Replace, discarding the occupant — no inventory). Whether the item
		// actually fits the slot is the Sim's call, not the menu's: it routes both
		// commands through ADR-0004's fit rule and bounces a size mismatch back as
		// Event_Refit_Rejected. The menu only names the slot and picks the operation
		// from whether it is filled — it never re-checks the fit here (issue #111).
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

// refit_prompt is the one-line instruction at the bottom of the refit screen,
// reflecting what the next click will do given the current mode (issue #96).
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

// draw_refit_incoming draws the pending item's details above the slot list, so
// the player can see the tags/phase/size/effect intent of what they are placing
// (issue #96); nothing is drawn during a rearrange-only refit.
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

// draw_refit_boxes draws the clickable slot rows and the Finish box (issue #96),
// highlighting a slot currently selected as a move source.
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
