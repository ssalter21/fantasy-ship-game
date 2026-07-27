package presentation

import "core:fmt"
import "core:strings"
import "core:testing"
import ship "../core/ship"
import cutaway "./cutaway"
import sim "../core/sim"
import rl "vendor:raylib"

// The Offer/Shop screen's drag mapping, its column layout, its travel and its refit bridge,
// tested as pure functions the way build_drop_command is — no window, so `odin test` exercises
// the screen's decisions without a render loop.

// A full shelf: the widest a Shop ever presents (SHOP_SHELF_SIZE), which is the case the column
// has to fit rather than the three an Offer shows.
@(private = "file")
full_shelf :: proc() -> (options: [sim.STAGE_OPTION_MAX]Maybe(sim.Stage_Option)) {
	for i in 0 ..< sim.STAGE_OPTION_MAX {
		options[i] = sim.Stage_Option{fitting = ship.Fitting{name = "stock", size = .Medium}, cost = 4}
	}
	return
}

@(test)
the_column_is_one_aligned_block :: proc(t: ^testing.T) {
	// The settled read (#476): one left edge, one width, one rhythm, and a full-width control
	// closing the block on the same two edges it opened on. Nothing here is decoration — a
	// column of differently-sized cards is what the shelf used to be, and prices that do not
	// scan down a straight line are why.
	options := full_shelf()
	rects := offer_shop_shelf_rects(options)
	leave := offer_shop_leave_rect(options)

	previous_bottom := f32(0)
	for i in 0 ..< sim.STAGE_OPTION_MAX {
		testing.expectf(t, rects[i].x == rects[0].x, "card %d shares the column's left edge", i)
		testing.expectf(t, rects[i].width == rects[0].width, "card %d shares the column's width", i)
		testing.expectf(t, rects[i].height == rects[0].height, "card %d shares the column's height", i)
		if i > 0 {
			testing.expectf(t, rects[i].y - rects[i - 1].y == OFFER_SHOP_PITCH, "card %d keeps the rhythm", i)
			testing.expectf(t, rects[i].y > previous_bottom, "card %d clears the one above it", i)
		}
		previous_bottom = rects[i].y + rects[i].height
	}

	testing.expect_value(t, leave.x, rects[0].x)
	testing.expect_value(t, leave.width, rects[0].width)
	testing.expect(t, leave.y > previous_bottom, "the control sits below the stock")

	// And the whole block fits the frame at its widest, clear of the chart tab along the bottom.
	testing.expect(t, rects[0].y > 0, "the column starts on screen")
	testing.expect(t, leave.x + leave.width < WINDOW_WIDTH, "the column's right edge is on screen")
	testing.expect(t, leave.y + leave.height < encounter_chart_tab_rect().y, "a full shelf clears the chart tab")
}

@(test)
a_shorter_shelf_closes_up_under_its_last_card :: proc(t: ^testing.T) {
	// An Offer shows three where a Shop shows five, and the control follows the stock up rather
	// than parking at a fixed height with a hole above it. A nil position takes no rect and no
	// gap, so a gappy list still lays out as a run.
	options: [sim.STAGE_OPTION_MAX]Maybe(sim.Stage_Option)
	options[0] = sim.Stage_Option{fitting = ship.Fitting{size = .Small}}
	options[2] = sim.Stage_Option{fitting = ship.Fitting{size = .Small}}

	rects := offer_shop_shelf_rects(options)
	testing.expect_value(t, rects[1], rl.Rectangle{}) // no rect, and no gap left for one
	testing.expect_value(t, rects[2].y - rects[0].y, OFFER_SHOP_PITCH)

	leave := offer_shop_leave_rect(options)
	testing.expect_value(t, leave.y, rects[2].y + OFFER_SHOP_PITCH + OFFER_SHOP_LEAVE_GAP)
	testing.expect(t, leave.y > rects[2].y + rects[2].height, "the control clears the last card")
	testing.expect(t, leave.y < offer_shop_leave_rect(full_shelf()).y, "a shorter shelf closes up")
}

@(test)
only_an_affordable_card_lifts_into_a_drag :: proc(t: ^testing.T) {
	// Affordability is read *before* the drag, so a buy the hold cannot pay for never begins
	// (#312) — and the press has to land on the card's own rect, which is the same rect the
	// draw used.
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	cheap, _ := ship.ship_item_by_name("Long Nines")
	state.stage_options[0] = sim.Stage_Option{fitting = cheap.fitting, cost = 4}
	state.stage_options[1] = sim.Stage_Option{fitting = cheap.fitting, cost = 10_000}

	rects := offer_shop_shelf_rects(state.stage_options)
	centre :: proc(r: rl.Rectangle) -> rl.Vector2 {
		return {r.x + r.width / 2, r.y + r.height / 2}
	}

	drag, lifted := offer_shop_begin_drag(&state, centre(rects[0]))
	testing.expect(t, lifted, "an affordable card lifts")
	testing.expect_value(t, drag.option_index, sim.Option_Index(0))

	_, dear := offer_shop_begin_drag(&state, centre(rects[1]))
	testing.expect(t, !dear, "a card the hold cannot pay for is not draggable")

	_, water := offer_shop_begin_drag(&state, rl.Vector2{20, 600})
	testing.expect(t, !water, "a press in open water lifts nothing")
}

@(test)
a_shelf_card_in_hand_is_the_build_surfaces_own_drag :: proc(t: ^testing.T) {
	// The stage lights and dims berths through draw_ship_cutaway rather than through a second
	// copy of that steer, which only holds if a shelf card really is a drag with no source
	// slot: build_is_legal_berth must then agree with offer_shop_legal_berth on every berth.
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	item, ok := ship.ship_item_by_name("Long Nines")
	testing.expect(t, ok)
	drag := Shelf_Drag{active = true, fitting = item.fitting}
	in_hand := offer_shop_in_hand(drag)
	testing.expect(t, in_hand.active)
	_, from_slot := in_hand.from_slot.?
	testing.expect(t, !from_slot, "a shelf card is lifted from no berth")

	for _, i in state.player.layout {
		slot := ship.Slot_Index(i)
		testing.expectf(
			t,
			build_is_legal_berth(&state, in_hand, slot) == offer_shop_legal_berth(item.fitting, state.player.layout[slot]),
			"berth %d reads the same to the drop gate and to the highlight",
			i,
		)
	}
}

@(test)
the_travel_starts_at_the_ship_screen_and_settles_alongside :: proc(t: ^testing.T) {
	// Entering a stage travels rather than cuts (#476), so the first frame must be exactly the
	// framing the player was already looking at and the last exactly the stage's — a move that
	// misses either end is a pop at that end.
	start := offer_shop_travel(0)
	testing.expect_value(t, start.framing.view, ship_framing_moored().view)
	testing.expect_value(t, start.framing.furl, 0)
	testing.expect_value(t, start.arrival, 0)

	rest := offer_shop_alongside()
	testing.expect_value(t, rest.framing.view, cutaway.galleon_view_from(cutaway.GALLEON_ALONGSIDE_EYE, WINDOW_WIDTH, WINDOW_HEIGHT))
	testing.expect_value(t, rest.framing.furl, 1)
	testing.expect_value(t, rest.arrival, 1)

	// The column is held back to the last stretch: paper travelling while the ship is still
	// swinging gives the eye two things moving in different directions at once.
	testing.expect_value(t, offer_shop_travel(OFFER_SHOP_COLUMN_HELD).arrival, 0)
	testing.expect(t, offer_shop_travel(0.9).arrival > 0, "the column is on its way in by the end")

	// And nothing doubles back: the camera rises and the canvas comes in monotonically.
	previous := start
	for step in 1 ..= 20 {
		now := offer_shop_travel(f32(step) / 20)
		testing.expect(t, now.framing.furl >= previous.framing.furl, "the canvas is only ever handed further")
		testing.expect(t, now.arrival >= previous.arrival, "the column only ever comes further in")
		testing.expect(t, now.framing.view.camera.position.y >= previous.framing.view.camera.position.y, "the eye only rises")
		previous = now
	}
}

@(test)
a_new_stop_travels_afresh_and_a_buy_does_not :: proc(t: ^testing.T) {
	// The travel plays once per stop. A Shop re-enters its loop after every buy with a refilled
	// shelf (Event_Options_Presented), and swinging the camera round again each time would put
	// 0.9 seconds of scenery between a captain and their second purchase. Only entering a stage
	// clears the flag.
	state: Game_State
	state.stage_alongside = true

	dispatch(&state, sim.Event_Options_Presented{})
	testing.expect(t, state.stage_alongside, "a refilled shelf is the same stop")

	dispatch(&state, sim.Event_Stage_Entered{kind = .Shop, index = 0, count = 1})
	testing.expect(t, !state.stage_alongside, "a new stage comes alongside again")
}

@(test)
offer_shop_kind_reads_the_stage_entered_event :: proc(t: ^testing.T) {
	state: Game_State

	// Between stages (nil stage_progress — never a live screen) the fallback is Offer.
	testing.expect(t, offer_shop_kind(&state) == .Offer)

	// A costless Shop still presents as a Shop: the kind is the Event's, not a price scan.
	state.stage_progress = sim.Event_Stage_Entered{kind = .Shop, index = 0, count = 1}
	state.stage_options[0] = sim.Stage_Option{} // no cost
	testing.expect(t, offer_shop_kind(&state) == .Shop)

	// And an Offer never presents as one, whatever its options carry.
	state.stage_progress = sim.Event_Stage_Entered{kind = .Offer, index = 0, count = 1}
	state.stage_options[0] = sim.Stage_Option{cost = 3}
	testing.expect(t, offer_shop_kind(&state) == .Offer)
}

@(test)
offer_shop_drop_onto_a_same_size_berth_takes_that_option :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	// Slot 2 (gun deck) is a Large berth; a Large card dropped on it is a legal landing.
	drag := Shelf_Drag{active = true, option_index = sim.Option_Index(1), fitting = ship.Fitting{size = .Large}}
	cmd, ready, install := offer_shop_drop_command(&state, drag, ship.Slot_Index(2))

	testing.expect(t, ready)
	choice, ok := cmd.(sim.Command_Choose_Option)
	testing.expect(t, ok)
	selection, took := choice.selection.?
	testing.expect(t, took && selection == sim.Option_Index(1))
	slot, has := install.?
	testing.expect(t, has && slot == ship.Slot_Index(2))
}

@(test)
offer_shop_drop_onto_a_wrong_size_berth_takes_nothing :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	// Slot 5 (hold 2) is a Small berth; a Large card cannot land there, so nothing commits.
	drag := Shelf_Drag{active = true, option_index = sim.Option_Index(0), fitting = ship.Fitting{size = .Large}}
	_, ready, install := offer_shop_drop_command(&state, drag, ship.Slot_Index(5))

	testing.expect(t, !ready)
	_, has := install.?
	testing.expect(t, !has)
}

@(test)
offer_shop_drop_in_open_water_takes_nothing :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	drag := Shelf_Drag{active = true, option_index = sim.Option_Index(0), fitting = ship.Fitting{size = .Large}}
	_, ready, _ := offer_shop_drop_command(&state, drag, nil)

	testing.expect(t, !ready)
}

@(test)
offer_shop_cargo_preview_projects_the_post_buy_hold :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	cargo := ship.ship_cargo(state.player)
	capacity := ship.ship_cargo_capacity(state.player)
	text := offer_shop_cargo_preview_text(&state.player, 18)

	// The cargo term reads current -> post-buy against an unchanged capacity, so the cost of
	// a buy shows before it lands.
	projection := fmt.tprintf("Cargo %d/%d -> %d/%d", cargo, capacity, cargo - 18, capacity)
	testing.expect(t, strings.contains(text, projection))
}

@(test)
build_shelf_bridge_installs_then_finishes_a_shelf_drop :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	granted := ship.Fitting{name = "test cannon", size = .Large}
	state.refit_incoming = granted
	state.pending_shelf_install = ship.Slot_Index(3) // the Large forecastle's bare hold

	// While the item is in hand it lands in the remembered berth. The bridge re-reads
	// occupancy, so a berth carrying a backfilled hold takes a Replace, not an Install.
	cmd, bridging := build_shelf_bridge_command(&state)
	testing.expect(t, bridging)
	refit, ok := cmd.(sim.Command_Refit)
	testing.expect(t, ok)
	replace, is_replace := refit.command.(sim.Refit_Replace)
	testing.expect(t, is_replace && replace.slot == ship.Slot_Index(3))

	// Once the Sim reports it installed (refit_incoming cleared), the bridge finishes and
	// releases the berth.
	state.refit_incoming = nil
	cmd, bridging = build_shelf_bridge_command(&state)
	testing.expect(t, bridging)
	refit, ok = cmd.(sim.Command_Refit)
	testing.expect(t, ok)
	_, is_finish := refit.command.(sim.Refit_Finish)
	testing.expect(t, is_finish)
	_, still_pending := state.pending_shelf_install.?
	testing.expect(t, !still_pending)
}

@(test)
build_shelf_bridge_swaps_into_an_occupied_berth :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	// Slot 2 (gun deck) starts filled by the starting loadout; a Large grant dropped on it
	// swaps rather than installs.
	granted := ship.Fitting{name = "test cannon", size = .Large}
	state.refit_incoming = granted
	state.pending_shelf_install = ship.Slot_Index(2)

	cmd, bridging := build_shelf_bridge_command(&state)
	testing.expect(t, bridging)
	refit, ok := cmd.(sim.Command_Refit)
	testing.expect(t, ok)
	replace, is_replace := refit.command.(sim.Refit_Replace)
	testing.expect(t, is_replace && replace.slot == ship.Slot_Index(2))
}

@(test)
build_shelf_bridge_is_dormant_without_a_pending_drop :: proc(t: ^testing.T) {
	state := Game_State{player = ship.ship_starting_ship()}
	defer delete(state.player.layout)

	_, bridging := build_shelf_bridge_command(&state)
	testing.expect(t, !bridging) // a Home refit is driven by hand, not the bridge
}
