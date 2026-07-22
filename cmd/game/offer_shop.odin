package main

import "core:fmt"
import cutaway "./cutaway"
import voyage "../../core/voyage"
import ship "../../core/ship"
import sim "../../core/sim"
import rl "vendor:raylib"

// The Offer and Shop stages (#312, #304, ADR-0024): both are the Build surface — the ship
// drawn as the same Cutaway as at Home (#302) — with a right-side shelf of the stage's
// items. You install by dragging a card leftward out of the shelf and onto a slot, one
// gesture. That single gesture spans two Sim phases: dropping on a berth answers the
// Awaiting_Option_Choice with a Command_Choose_Option and remembers the berth
// (state.pending_shelf_install), and the Refit that choice opens then installs there and
// finishes on its own (build_surface_loop's shelf-drag bridge). So the Sim keeps its
// choose-then-refit path unchanged — the spine only collapses it in presentation.
//
// The shelf cards are steel draggable options, not a row of ambers (the amber rule): an
// Offer's items are free, a Shop's are priced, and neither is "the one thing to act on".
// The one amber is the card in hand — the ghost under the cursor while a drag is in flight,
// exactly one at a time. A Shop reads its cost three ways: a price on each card, an
// unaffordable card dimmed and undraggable, and a live cargo projection in the stat line the
// moment a priced card is picked up.
//
// Split composition (draw_offer_shop) from polling (offer_shop_loop) like the Build surface,
// so --capture photographs it (#277).

// The encounter ship sits at a reduced scale so it can share the width with the shelf: the
// Home ship's deck row is nearly the full window, which leaves no room for a right panel.
// The size-language (Large > Medium > Small) is preserved — every card shrinks by the same
// factor — so a Large slot still reads as the biggest berth.
OFFER_SHOP_SCALE :: 0.8
OFFER_SHOP_SHIP_X :: 12
OFFER_SHOP_DECK_Y :: 116
OFFER_SHOP_WATERLINE_Y :: 248
OFFER_SHOP_HOLD_Y :: 262
OFFER_SHOP_KEEL_Y :: 404

OFFER_SHOP_SHELF_W :: 224
OFFER_SHOP_SHELF_X :: WINDOW_WIDTH - OFFER_SHOP_SHELF_W - 12
OFFER_SHOP_SHELF_PANEL_Y :: 84
OFFER_SHOP_SHELF_PANEL_H :: 512
OFFER_SHOP_SHELF_CARD_X :: OFFER_SHOP_SHELF_X + 12
OFFER_SHOP_SHELF_Y0 :: OFFER_SHOP_SHELF_PANEL_Y + 38 // below the panel's title
OFFER_SHOP_SHELF_GAP :: 12

// OFFER_SHOP_SHIP_W is the ship's region: from its left margin up to the gap before the
// shelf panel, so the two never overlap and the ship rows centre in what is left.
OFFER_SHOP_SHIP_W :: OFFER_SHOP_SHELF_X - OFFER_SHOP_SHIP_X - 12

// offer_shop_ship_region is the encounter ship's reduced-scale left region, spelled once so
// hull, cards and the slot hit-test read the same cross-section (#426).
offer_shop_ship_region :: proc() -> cutaway.Region {
	return cutaway.Region {
		x           = OFFER_SHOP_SHIP_X,
		w           = OFFER_SHOP_SHIP_W,
		deck_y      = OFFER_SHOP_DECK_Y,
		waterline_y = OFFER_SHOP_WATERLINE_Y,
		hold_y      = OFFER_SHOP_HOLD_Y,
		keel_y      = OFFER_SHOP_KEEL_Y,
		scale       = OFFER_SHOP_SCALE,
	}
}

// Shelf_Drag is a shelf card in flight — the same press-drag-release primitive the Build
// surface uses, but lifted from an option rather than a slot. It carries the option's index
// (what a drop answers Choose_Option with), its fitting (the ghost, and the size the legal
// berth is matched against), and its cost (nil for a free Offer item) for the live cargo
// projection.
Shelf_Drag :: struct {
	active:       bool,
	option_index: sim.Option_Index,
	fitting:      ship.Fitting,
	cost:         Maybe(int),
}

// offer_shop_kind names which primitive this list is, read off the prices — a priced list
// is a Shop, an unpriced one an Offer — so the header, its tint, and the Leave/Skip wording
// all come from the same tell the old option screen used. Costs are per-option, so it asks
// the list rather than assuming the stage.
offer_shop_kind :: proc(options: [sim.STAGE_OPTION_MAX]Maybe(sim.Stage_Option)) -> voyage.Stage_Kind {
	for slot in options {
		if option, filled := slot.?; filled {
			if _, has_cost := option.cost.?; has_cost {
				return .Shop
			}
		}
	}
	return .Offer
}

// offer_shop_legal_berth is the drag's affordance rule: a shelf card can land on any berth
// the fit rule admits — installing into an empty one, swapping into a filled one — mirroring
// the Build surface's shelf-item rule (build_is_legal_berth). It is a hint, not the fit
// authority: the Sim still validates the emitted Refit, but because the drop is gated on
// this the install never bounces, which is what lets the bridge auto-finish. That is why it
// asks ship_fitting_fits rather than comparing sizes itself — a second copy of the rule
// would go stale against the Sim's and start bouncing drops the UI promised.
offer_shop_legal_berth :: proc(fitting: ship.Fitting, layout_slot: ship.Layout_Slot) -> bool {
	return ship.ship_fitting_fits(layout_slot.slot, fitting)
}

// offer_shop_shelf_rects lays the option cards into a vertical stack down the shelf panel,
// each card's footprint tracking its slot size so size reads on the shelf the same way it
// reads on the ship. A pure function of the list, so drawing and hit-testing both ask for it
// (the split that lets capture draw the shelf it never clicks). Only filled positions take a
// rect and advance the stack; a nil slot leaves a zero rect and no gap.
offer_shop_shelf_rects :: proc(options: [sim.STAGE_OPTION_MAX]Maybe(sim.Stage_Option)) -> [sim.STAGE_OPTION_MAX]rl.Rectangle {
	rects: [sim.STAGE_OPTION_MAX]rl.Rectangle
	y := f32(OFFER_SHOP_SHELF_Y0)
	for slot, i in options {
		option, filled := slot.?
		if !filled {
			continue
		}
		w, h := cutaway.cutaway_card_dims(option.fitting.size, OFFER_SHOP_SCALE)
		rects[i] = rl.Rectangle{x = OFFER_SHOP_SHELF_CARD_X, y = y, width = w, height = h}
		y += h + OFFER_SHOP_SHELF_GAP
	}
	return rects
}

// offer_shop_shelf_panel_rect is the recessive-blue container the cards sit in — a source,
// not your ship (#304), so it takes the inert role tone, never a steel one.
offer_shop_shelf_panel_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle {
		x      = OFFER_SHOP_SHELF_X,
		y      = OFFER_SHOP_SHELF_PANEL_Y,
		width  = OFFER_SHOP_SHELF_W,
		height = OFFER_SHOP_SHELF_PANEL_H,
	}
}

// offer_shop_leave_rect is the steel "leave the stop" control, beneath the shelf: a Shop's
// Leave (completes the stop) or an Offer's Skip (halts it), both a nil Choose_Option. Not
// amber — leaving is never the default (the amber rule), and here there is no default at all.
offer_shop_leave_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle {
		x      = OFFER_SHOP_SHELF_X,
		y      = OFFER_SHOP_SHELF_PANEL_Y + OFFER_SHOP_SHELF_PANEL_H + 8,
		width  = OFFER_SHOP_SHELF_W,
		height = 38,
	}
}

// offer_shop_ship_slot_at returns the ship slot whose card the point is over, or nil —
// asked of the cutaway module over the same region the drawing uses.
offer_shop_ship_slot_at :: proc(state: ^Game_State, point: rl.Vector2) -> Maybe(ship.Slot_Index) {
	return cutaway.cutaway_slot_at(state.player.layout, offer_shop_ship_region(), point)
}

// offer_shop_begin_drag lifts the affordable shelf card under a press into a drag, or starts
// nothing. An unaffordable priced card is not draggable — affordability is read before the
// drag, so a buy you can't make never begins (Event_Purchase_Rejected stays the rare edge,
// not the teacher, #312).
offer_shop_begin_drag :: proc(state: ^Game_State, point: rl.Vector2) -> (Shelf_Drag, bool) {
	rects := offer_shop_shelf_rects(state.stage_options)
	for slot, i in state.stage_options {
		option, filled := slot.?
		if !filled {
			continue
		}
		if !voyage.voyage_option_can_afford(&state.player, option) {
			continue
		}
		if rl.CheckCollisionPointRec(point, rects[i]) {
			return Shelf_Drag {
					active = true,
					option_index = sim.Option_Index(i),
					fitting = option.fitting,
					cost = option.cost,
				},
				true
		}
	}
	return {}, false
}

// offer_shop_drop_command maps a completed shelf drag — the card and the slot it was released
// over — to the Command_Choose_Option it answers with, mirroring build_drop_command's pure
// mapping so the gesture is testable without a live window. A drop on a same-size berth
// commits the choice and hands back the berth as `install_slot` (which the caller stashes in
// state.pending_shelf_install for the refit to complete); a drop on a wrong-size slot or in
// open water commits nothing, so the card snaps back to the shelf.
offer_shop_drop_command :: proc(
	state: ^Game_State,
	drag: Shelf_Drag,
	target: Maybe(ship.Slot_Index),
) -> (
	cmd: sim.Command,
	ready: bool,
	install_slot: Maybe(ship.Slot_Index),
) {
	slot, has_target := target.?
	if !has_target || !offer_shop_legal_berth(drag.fitting, state.player.layout[slot]) {
		return {}, false, nil
	}
	return sim.Command(sim.Command_Choose_Option{selection = drag.option_index}), true, slot
}

// build_shelf_bridge_command drives the auto-refit an Offer/Shop shelf drop opened (#312):
// while the granted item is still in hand it installs into the remembered berth — Replace if
// that berth is now occupied, Install if empty, occupancy re-read here so drift can't bounce
// the command — and once installed it finishes and clears the berth. `bridging` is false when
// no shelf drop set a berth, which is how build_surface_loop tells a collapsed Offer/Shop
// refit from a Home refit the player drives by hand. Pure over Game_State, so the
// install-then-finish sequence is unit-tested without a window.
build_shelf_bridge_command :: proc(state: ^Game_State) -> (cmd: sim.Command, bridging: bool) {
	slot, has := state.pending_shelf_install.?
	if !has {
		return {}, false
	}
	if _, still_incoming := state.refit_incoming.?; still_incoming {
		if _, occupied := state.player.layout[slot].fitting.?; occupied {
			return sim.Command(sim.Command_Refit{command = sim.Refit_Replace{slot = slot}}), true
		}
		return sim.Command(sim.Command_Refit{command = sim.Refit_Install{slot = slot}}), true
	}
	// The install landed (refit_incoming cleared); the collapsed gesture is done.
	state.pending_shelf_install = nil
	return sim.Command(sim.Command_Refit{command = sim.Refit_Finish{}}), true
}

// offer_shop_loop is the Offer/Shop screen's blocking loop, the drag-first successor to
// option_menu_loop: it renders the Cutaway ship and the option shelf and returns a
// Command_Choose_Option when a drag lands on a berth (with the berth stashed for the refit),
// or a nil choice when the player leaves. run_session ticks that command; a Shop's buy
// re-enters this loop with a refilled shelf, an Offer's pick or a leave walks on.
offer_shop_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): decline rather than take an option and
		// open a refit the test harness can't drive — the same fallback option_menu_loop had.
		return sim.Command(sim.Command_Choose_Option{selection = nil})
	}
	// A fresh choice carries no berth from a previous one; the bridge sets and clears it
	// within one refit, but clear it here too so nothing stale survives into this stop.
	state.pending_shelf_install = nil

	drag: Shelf_Drag

	for {
		window_quit_if_closed()
		mouse := rl.GetMousePosition()

		// A drag in flight: the ghost follows the cursor until release, when where it lands
		// decides the choice (or a cancel back to the shelf).
		if drag.active {
			draw_offer_shop(state, drag, mouse)
			if rl.IsMouseButtonReleased(.LEFT) {
				cmd, ready, install := offer_shop_drop_command(state, drag, offer_shop_ship_slot_at(state, mouse))
				drag.active = false
				if ready {
					state.pending_shelf_install = install
					return cmd
				}
			}
			continue
		}

		// Resting: draw, then a press either leaves (Leave/Skip) or lifts a shelf card.
		draw_offer_shop(state, drag, mouse)
		if rl.IsMouseButtonPressed(.LEFT) {
			if rl.CheckCollisionPointRec(mouse, offer_shop_leave_rect()) {
				return sim.Command(sim.Command_Choose_Option{selection = nil})
			}
			if started, ok := offer_shop_begin_drag(state, mouse); ok {
				drag = started
			}
		}
	}
}

// draw_offer_shop draws one whole frame of the Offer/Shop screen: the Cutaway ship in its
// left region, the shelf on the right, the Leave/Skip control, the drag ghost, and the
// shared encounter chrome over it all. Split from offer_shop_loop so composing and polling
// are separate acts — capture draws and never polls (#277).
draw_offer_shop :: proc(state: ^Game_State, drag: Shelf_Drag, mouse: rl.Vector2) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	rl.ClearBackground(COLOUR_DEEP)

	kind := offer_shop_kind(state.stage_options)
	dragging := drag.active

	region := offer_shop_ship_region()
	draw_build_hull(region)

	// The ship's slots, at the encounter scale. A drag dims every berth that is not a legal
	// landing for it and lights the ones that are, exactly as the Build surface does — the
	// same draw_build_card, so a slot reads identically here and at Home.
	rects, n := cutaway.cutaway_slot_rects(state.player.layout, region)
	for i in 0 ..< n {
		legal := dragging && offer_shop_legal_berth(drag.fitting, state.player.layout[i])
		draw_build_card(rects[i], state.player.layout[i], dragging && !legal, legal)
	}

	draw_offer_shop_shelf(state, kind, drag)
	draw_offer_shop_leave(kind, mouse)

	if dragging {
		draw_build_ghost(drag.fitting, mouse)
	}

	// The chrome, with the Shop's live cargo projection swapped into the stat line while a
	// priced card is in hand: `Cargo 6/8 → 2/8`, so the cost of the buy shows before it lands.
	stat_override := ""
	if dragging {
		if cost, priced := drag.cost.?; priced {
			stat_override = offer_shop_cargo_preview_text(&state.player, cost)
		}
	}
	draw_encounter_chrome(state, kind, stat_override)
}

// offer_shop_cargo_preview_text is the stat line with the cargo field ghosted forward to its
// post-buy figure — the third of the Shop's three cost reads. It mirrors
// encounter_stat_line_text's layout so only the cargo term changes. The projection arrow is
// ASCII "->" rather than "→": Pixelify Sans carries no U+2192, so the glyph would render as a
// blank box (see UI_FONT_EXTRA_CODEPOINTS).
offer_shop_cargo_preview_text :: proc(s: ^ship.Ship, cost: int) -> string {
	return fmt.tprintf(
		"%s -> %d/%d",
		encounter_stat_line_text(s),
		ship.ship_cargo(s^) - cost,
		ship.ship_cargo_capacity(s^),
	)
}

// draw_offer_shop_shelf draws the right-side panel and its option cards. The panel is a
// recessive-blue container (it is a source of items, not your ship); its title takes the
// stage's own tint, the same colour the header and the map marker carry. The card being
// dragged gives way to the ghost, so there are never two.
draw_offer_shop_shelf :: proc(state: ^Game_State, kind: voyage.Stage_Kind, drag: Shelf_Drag) {
	panel := offer_shop_shelf_panel_rect()
	rl.DrawRectangleRec(panel, rl.Fade(COLOUR_GROUND, 0.5))
	draw_subpanel_border(panel, false)

	title := kind == .Shop ? "Market" : "On offer"
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", title), rl.Vector2{panel.x + 12, panel.y + 8}, UI_BODY_SIZE, 1, stage_tint(kind))

	rects := offer_shop_shelf_rects(state.stage_options)
	for slot, i in state.stage_options {
		option, filled := slot.?
		if !filled {
			continue
		}
		if drag.active && int(drag.option_index) == i {
			continue // lifted into the ghost
		}
		affordable := voyage.voyage_option_can_afford(&state.player, option)
		draw_offer_shop_shelf_card(rects[i], option, affordable)
	}
}

// draw_offer_shop_shelf_card renders one option: name, then a price row (a Shop card) or a
// category chip (a free Offer item), then the effect intent. A steel-bordered draggable
// option when affordable; a priced card the ship can't pay is dimmed to recessive-blue —
// undraggable, so affordability reads before the drag (#312).
draw_offer_shop_shelf_card :: proc(rect: rl.Rectangle, option: sim.Stage_Option, affordable: bool) {
	rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, 0.55))
	rl.DrawRectangleLinesEx(rect, 2, affordable ? COLOUR_STEEL : COLOUR_BLUE_RECESSIVE)

	x := rect.x + 10
	name_tone := affordable ? COLOUR_CREAM : rl.Fade(COLOUR_CREAM, 0.5)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", option.fitting.name), rl.Vector2{x, rect.y + 8}, UI_BODY_SIZE, 1, name_tone)

	if cost, priced := option.cost.?; priced {
		draw_cargo_price(rl.Vector2{x, rect.y + 34}, cost, affordable)
	} else {
		draw_build_phase_chip(rl.Vector2{x, rect.y + 32}, fitting_phase_label(option.fitting))
	}

	intent_tone := affordable ? COLOUR_STEEL : rl.Fade(COLOUR_STEEL, 0.5)
	rl.DrawTextEx(
		ui_font_body,
		fmt.ctprintf("%s", fitting_effect_intent(option.fitting)),
		rl.Vector2{x, rect.y + rect.height - 26},
		UI_BODY_SIZE,
		1,
		intent_tone,
	)
}

// draw_cargo_price draws a price as a small crate glyph and a number — a shape, not the word
// "cargo" (the guide: glyphs are shapes). Cream when affordable, dimmed steel when not, so
// the price itself carries the affordability read alongside the border.
draw_cargo_price :: proc(pos: rl.Vector2, cost: int, affordable: bool) {
	tone := affordable ? COLOUR_CREAM : rl.Fade(COLOUR_STEEL, 0.6)
	box := rl.Rectangle{x = pos.x, y = pos.y + 2, width = 16, height = 16}
	rl.DrawRectangleLinesEx(box, 2, tone)
	// A cross through the crate — a bound bale — so it reads as goods, not an empty square.
	rl.DrawLineEx(rl.Vector2{box.x, box.y + box.height / 2}, rl.Vector2{box.x + box.width, box.y + box.height / 2}, 1, tone)
	rl.DrawLineEx(rl.Vector2{box.x + box.width / 2, box.y}, rl.Vector2{box.x + box.width / 2, box.y + box.height}, 1, tone)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%d", cost), rl.Vector2{pos.x + 24, pos.y}, UI_BODY_SIZE, 1, tone)
}

// draw_offer_shop_leave draws the steel Leave/Skip control, its scrim lifting on hover (hover
// carried by the scrim, not by amber — the amber rule). Its word is the primitive's: a Shop's
// Leave completes the stop, an Offer's Skip halts it.
draw_offer_shop_leave :: proc(kind: voyage.Stage_Kind, mouse: rl.Vector2) {
	rect := offer_shop_leave_rect()
	hovered := rl.CheckCollisionPointRec(mouse, rect)
	rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, hovered ? 0.75 : 0.55))
	rl.DrawRectangleLinesEx(rect, 2, COLOUR_STEEL)

	label := kind == .Shop ? "Leave" : "Skip"
	size := rl.MeasureTextEx(ui_font_body, fmt.ctprintf("%s", label), UI_BODY_SIZE, 1)
	rl.DrawTextEx(
		ui_font_body,
		fmt.ctprintf("%s", label),
		rl.Vector2{rect.x + (rect.width - size.x) / 2, rect.y + (rect.height - UI_BODY_SIZE) / 2},
		UI_BODY_SIZE,
		1,
		COLOUR_STEEL,
	)
}
