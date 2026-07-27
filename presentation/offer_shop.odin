#+private
package presentation

import "core:fmt"
import cutaway "./cutaway"
import voyage "../core/voyage"
import ship "../core/ship"
import sim "../core/sim"
import rl "vendor:raylib"

// The Offer and Shop stages (#312, #304, ADR-0024, #476): both are the Build surface — the
// player's own galleon, drawn by the same painters as the ship screen — with a shelf of the
// stage's items beside her. You install by dragging a card leftward out of the shelf and onto a
// berth, one gesture. That single gesture spans two Sim phases: dropping on a berth answers the
// Awaiting_Option_Choice with a Command_Choose_Option and remembers the berth
// (state.pending_shelf_install), and the Refit that choice opens then installs there and
// finishes on its own (build_surface_loop's shelf-drag bridge). So the Sim keeps its
// choose-then-refit path unchanged — the spine only collapses it in presentation.
//
// **The stage is the ship screen under a different camera** (ADR-0032): the real galleon, same
// sky, sea, hull, rooms, ornament, rig and waterline, drawn dead broadside under an orthographic
// projection and panned to port, with the stock beside her as one aligned column of parchment.
// Entering the stage does not cut to that framing — it **travels** there from the framing the
// player is already looking at (offer_shop_travel).
//
// The column is the same for both stages, because the only thing that differs between an Offer
// and a Shop is whether an option carries a price. A Shop reads its cost three ways: the price
// on the card, an unaffordable card dimmed and undraggable, and a live cargo projection in the
// stat line the moment a priced card is picked up.
//
// Split composition (draw_offer_shop) from polling (offer_shop_loop) like the Build surface,
// so --capture photographs it (#277).

// ---------------------------------------------------------------------------
// Coming alongside
// ---------------------------------------------------------------------------

// How long the travel takes. Long enough to read as a move the eye can follow round her, short
// enough that a captain who has seen it forty times is not waiting on it.
OFFER_SHOP_TRAVEL_SECONDS :: f32(0.9)

// The column is held back to the last stretch of the move and slides in from off the right edge.
// Held rather than travelling with the camera: paper arriving while the ship is still swinging
// gives the eye two things moving in different directions at once.
OFFER_SHOP_COLUMN_HELD :: f32(0.45)
OFFER_SHOP_COLUMN_THROW :: f32(440)

// offer_shop_ease is smootherstep — zero first *and* second derivative at both ends. A camera
// that leaves or arrives with non-zero acceleration reads as a jolt on a move this short, and
// plain smoothstep still kicks at the ends.
offer_shop_ease :: proc(t: f32) -> f32 {
	x := clamp(t, 0, 1)
	return x * x * x * (x * (x * 6 - 15) + 10)
}

// Offer_Shop_Travel is where the move has got to, as everything one frame is composed against:
// the framing to draw and hit-test the ship through, and how far in the column has come. Built
// once a frame and handed to the draw *and* to the berth hit-test, so the two cannot disagree
// about where a berth is (ADR-0032).
Offer_Shop_Travel :: struct {
	framing: Ship_Framing,
	arrival: f32,
}

// offer_shop_travel is the stage at raw progress `t`: 0 is the ship screen the player came from,
// 1 is the stage at rest.
offer_shop_travel :: proc(t: f32) -> Offer_Shop_Travel {
	return Offer_Shop_Travel {
		framing = ship_framing_travelling(offer_shop_ease(t)),
		arrival = offer_shop_ease((t - OFFER_SHOP_COLUMN_HELD) / (1 - OFFER_SHOP_COLUMN_HELD)),
	}
}

// offer_shop_alongside is the stage at rest — the framing every still of it is composed in.
offer_shop_alongside :: proc() -> Offer_Shop_Travel {
	return offer_shop_travel(1)
}

// ---------------------------------------------------------------------------
// The column
//
// Opaque parchment on the sea with no panel behind it, so the ship's own water runs between the
// cards and the screen is the ship screen with paper on it rather than the ship screen with a
// wall on it. Every edge lines up: card left, card right, and the full-width control that closes
// the block on the same two edges it opened on. Prices scan down one straight line.
// ---------------------------------------------------------------------------

OFFER_SHOP_COL_X :: f32(820)
OFFER_SHOP_COL_W :: f32(392)
OFFER_SHOP_COL_Y0 :: f32(72) // clear of the shared stat line in the top-right corner
OFFER_SHOP_CARD_H :: f32(92)
OFFER_SHOP_PITCH :: f32(104) // sized so a Shop's full five-card shelf still clears the chart tab
OFFER_SHOP_LEAVE_GAP :: f32(16)
OFFER_SHOP_LEAVE_H :: f32(40)

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

// offer_shop_in_hand recasts a shelf drag as the Build surface's own drag primitive. A shelf
// card *is* a drag with no source slot, which is the case build_is_legal_berth already resolves
// to ship_fitting_fits — the same rule offer_shop_legal_berth asks. So the ship is drawn by
// draw_ship_cutaway with its berths lit and dimmed exactly as they are at Home, rather than by a
// second copy of that steer that could drift from it.
offer_shop_in_hand :: proc(drag: Shelf_Drag) -> Build_Drag {
	return Build_Drag{active = drag.active, from_slot = nil, fitting = drag.fitting}
}

// offer_shop_kind names which primitive this screen is presenting — the header, its tint,
// and the Leave/Skip wording all read it. It is the kind the Sim announced on entry
// (Event_Stage_Entered, kept in state.stage_progress), not inferred from the options, so a
// Shop whose items happen to carry no cost still presents as a Shop (#430). The screen only
// runs while a stage is walked; nil stage_progress falls back to Offer, the humbler read.
offer_shop_kind :: proc(state: ^Game_State) -> voyage.Stage_Kind {
	if progress, walking := state.stage_progress.?; walking {
		return progress.kind
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

// offer_shop_shelf_rects lays the option cards down the column: one left edge, one width, one
// rhythm, so the block reads as a single stack rather than as a list of differently-sized
// things. A pure function of the list, so drawing and hit-testing both ask for it (the split
// that lets capture draw the shelf it never clicks). Only filled positions take a rect and
// advance the stack; a nil slot leaves a zero rect and no gap.
//
// These are the *resting* rects. The column slides in from the right over the back half of the
// travel, and the draw offsets by that — nothing is clickable until it has landed.
offer_shop_shelf_rects :: proc(options: [sim.STAGE_OPTION_MAX]Maybe(sim.Stage_Option)) -> [sim.STAGE_OPTION_MAX]rl.Rectangle {
	rects: [sim.STAGE_OPTION_MAX]rl.Rectangle
	y := OFFER_SHOP_COL_Y0
	for slot, i in options {
		if _, filled := slot.?; !filled {
			continue
		}
		rects[i] = rl.Rectangle{x = OFFER_SHOP_COL_X, y = y, width = OFFER_SHOP_COL_W, height = OFFER_SHOP_CARD_H}
		y += OFFER_SHOP_PITCH
	}
	return rects
}

// offer_shop_leave_rect is the "leave the stop" control, closing the column on its own two
// edges: a Shop's Leave (completes the stop) or an Offer's Skip (halts it), both a nil
// Choose_Option. Beneath the stock rather than among it — leaving is never the default, and
// here there is no default at all — and full width, so the block is a block.
offer_shop_leave_rect :: proc(options: [sim.STAGE_OPTION_MAX]Maybe(sim.Stage_Option)) -> rl.Rectangle {
	filled := 0
	for slot in options {
		if _, present := slot.?; present {
			filled += 1
		}
	}
	return rl.Rectangle {
		x = OFFER_SHOP_COL_X,
		y = OFFER_SHOP_COL_Y0 + f32(filled) * OFFER_SHOP_PITCH + OFFER_SHOP_LEAVE_GAP,
		width = OFFER_SHOP_COL_W,
		height = OFFER_SHOP_LEAVE_H,
	}
}

// offer_shop_ship_slot_at returns the ship slot whose room the point is over, or nil — asked of
// the cutaway module over the same framing the drawing was handed, so a drop lands in the berth
// the player was pointing into rather than in one projected through a different camera.
offer_shop_ship_slot_at :: proc(state: ^Game_State, stage: Offer_Shop_Travel, point: rl.Vector2) -> Maybe(ship.Slot_Index) {
	return cutaway.galleon_room_at(state.player.layout, point, stage.framing.view)
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
// option_menu_loop: it comes alongside, then renders the galleon and the column and returns a
// Command_Choose_Option when a drag lands on a berth (with the berth stashed for the refit), or
// a nil choice when the player leaves. run_session ticks that command; a Shop's buy re-enters
// this loop with a refilled shelf, an Offer's pick or a leave walks on.
offer_shop_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): decline rather than take an option and
		// open a refit the test harness can't drive — the same fallback option_menu_loop had.
		return sim.Command(sim.Command_Choose_Option{selection = nil})
	}
	// A fresh choice carries no berth from a previous one; the bridge sets and clears it
	// within one refit, but clear it here too so nothing stale survives into this stop.
	state.pending_shelf_install = nil

	// Once per stop, not once per call — see Game_State.stage_alongside.
	if !state.stage_alongside {
		offer_shop_come_alongside(state)
		state.stage_alongside = true
	}

	drag: Shelf_Drag

	for {
		window_quit_if_closed()
		mouse := rl.GetMousePosition()
		// One framing a frame, handed to the draw and to the hit-test alike.
		stage := offer_shop_alongside()

		// A drag in flight: the ghost follows the cursor until release, when where it lands
		// decides the choice (or a cancel back to the shelf).
		if drag.active {
			draw_offer_shop(state, stage, drag, mouse)
			if rl.IsMouseButtonReleased(.LEFT) {
				target := offer_shop_ship_slot_at(state, stage, mouse)
				cmd, ready, install := offer_shop_drop_command(state, drag, target)
				drag.active = false
				if ready {
					state.pending_shelf_install = install
					return cmd
				}
			}
			continue
		}

		// Resting: draw, then a press either leaves (Leave/Skip) or lifts a shelf card.
		draw_offer_shop(state, stage, drag, mouse)
		if rl.IsMouseButtonPressed(.LEFT) {
			if rl.CheckCollisionPointRec(mouse, offer_shop_leave_rect(state.stage_options)) {
				return sim.Command(sim.Command_Choose_Option{selection = nil})
			}
			if started, ok := offer_shop_begin_drag(state, mouse); ok {
				drag = started
			}
		}
	}
}

// offer_shop_come_alongside plays the travel and returns once she is on the beam. It swallows
// input for its duration on purpose: there is nothing to click on a screen still arriving, and a
// click that landed on a card sliding past would be a buy the player did not aim.
offer_shop_come_alongside :: proc(state: ^Game_State) {
	elapsed: f32 = 0
	for elapsed < OFFER_SHOP_TRAVEL_SECONDS {
		window_quit_if_closed()
		elapsed += rl.GetFrameTime()
		draw_offer_shop(state, offer_shop_travel(elapsed / OFFER_SHOP_TRAVEL_SECONDS), Shelf_Drag{}, NO_MOUSE)
	}
}

// draw_offer_shop draws one whole frame of the Offer/Shop screen: the galleon under this
// moment's framing, the column beside her, the drag ghost, and the shared encounter chrome over
// it all. Split from offer_shop_loop so composing and polling are separate acts — capture draws
// and never polls (#277), which is what makes a frame *through* the travel photographable.
draw_offer_shop :: proc(state: ^Game_State, stage: Offer_Shop_Travel, drag: Shelf_Drag, mouse: rl.Vector2) {
	frame_begin()
	defer frame_end()
	defer free_all(context.temp_allocator)

	kind := offer_shop_kind(state)
	dragging := drag.active

	// Her whole screen, from the same painters: sky, sea, wake, hull, rooms, ornament, rig,
	// waterline — and, while a card is in hand, every berth answering whether it will take it.
	// No hovered-berth description card: the Build surface has open water bottom-right to throw
	// one into, where this screen has the column standing in exactly that corner.
	draw_ship_cutaway(state, stage.framing, offer_shop_in_hand(drag), mouse, describe = false)

	if stage.arrival > 0 {
		draw_offer_shop_column(state, kind, drag, mouse, (1 - stage.arrival) * OFFER_SHOP_COLUMN_THROW)
	}

	if dragging {
		draw_build_ghost(drag.fitting, mouse)
	}

	// The chrome, with the Shop's live cargo projection swapped into the stat line while a
	// priced card is in hand: `Cargo 6/8 -> 2/8`, so the cost of the buy shows before it lands.
	stat_override := ""
	if dragging {
		if cost, priced := drag.cost.?; priced {
			stat_override = offer_shop_cargo_preview_text(&state.player, cost)
		}
	}
	draw_encounter_chrome(state, kind, stat_override, over_water = true)
}

// offer_shop_cargo_preview_text is the stat line with the cargo field ghosted forward to its
// post-buy figure — the third of the Shop's three cost reads. It composes over
// ship_stat_line so only the cargo term changes. The projection arrow is
// ASCII "->" rather than "→": Pixelify Sans carries no U+2192, so the glyph would render as a
// blank box (see UI_FONT_EXTRA_CODEPOINTS).
offer_shop_cargo_preview_text :: proc(s: ^ship.Ship, cost: int) -> string {
	return fmt.tprintf(
		"%s -> %d/%d",
		ship_stat_line(s),
		ship.ship_cargo(s^) - cost,
		ship.ship_cargo_capacity(s^),
	)
}

// draw_offer_shop_column draws the stock and the control that closes it. `dx` slides the whole
// block in from off the right edge during the travel and is zero at rest. The card being dragged
// gives way to the ghost, so there are never two.
draw_offer_shop_column :: proc(state: ^Game_State, kind: voyage.Stage_Kind, drag: Shelf_Drag, mouse: rl.Vector2, dx: f32) {
	rects := offer_shop_shelf_rects(state.stage_options)
	for slot, i in state.stage_options {
		option, filled := slot.?
		if !filled {
			continue
		}
		if drag.active && int(drag.option_index) == i {
			continue // lifted into the ghost
		}
		card := rects[i]
		card.x += dx
		draw_offer_shop_card(card, option, voyage.voyage_option_can_afford(&state.player, option))
	}

	leave := offer_shop_leave_rect(state.stage_options)
	leave.x += dx
	// A Shop's Leave completes the stop, an Offer's Skip halts it. Hover is carried by the
	// ground, never by a change of colour.
	hovered := dx == 0 && rl.CheckCollisionPointRec(mouse, leave)
	draw_offer_shop_control(leave, kind == .Shop ? "Leave" : "Skip", hovered)
}

// draw_offer_shop_card renders one option on opaque parchment: its name, what it is for, its
// spec, and — a Shop card — its price scanning down the same right-hand line as every other.
//
// Unaffordable dims **by tone, never by alpha**: over a bright sea, translucency costs a panel
// its own ground and the hull-down islands read through the card as stains (ADR-0032).
draw_offer_shop_card :: proc(rect: rl.Rectangle, option: sim.Stage_Option, affordable: bool) {
	// A cast shadow, not a glow: the sea is bright, so the only way paper sits above it is to
	// darken what is under the paper.
	rl.DrawRectangleRec({rect.x + 5, rect.y + 6, rect.width, rect.height}, rl.Fade(COLOUR_SEA_DEEP, 0.45))
	rl.DrawRectangleRec(rect, affordable ? COLOUR_PARCHMENT : colour_shade(COLOUR_PARCHMENT, 0.90))
	rl.DrawRectangleLinesEx(rect, 2, affordable ? COLOUR_SEA_DEEP : COLOUR_CLIFF)

	name_tone := affordable ? COLOUR_INK_PRIMARY : COLOUR_INK_MUTED
	spec, intent := fitting_summary_lines(option.fitting)
	x := rect.x + 14
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", option.fitting.name), {x, rect.y + 10}, UI_BODY_SIZE, 1, name_tone)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", intent), {x, rect.y + 36}, UI_BODY_SIZE, 1, COLOUR_INK_MUTED)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", spec), {x, rect.y + 62}, UI_BODY_SIZE, 1, rl.Fade(COLOUR_INK_MUTED, 0.7))

	// An Offer's items are free and carry no price at all — the one thing that differs between
	// the two stages, and the whole of it.
	if cost, priced := option.cost.?; priced {
		draw_offer_shop_price(rect.x + rect.width - 14, rect.y + 10, cost, name_tone)
	}
}

// draw_offer_shop_price lays a crate-and-number price flush to `right`, measured rather than
// guessed so a three-digit price does not walk off the edge a two-digit one fitted. The crate is
// drawn as shapes rather than as a glyph — the style guide will not let a codepoint above
// Latin-1 be depended on, and "cargo" is a picture here, not a word.
draw_offer_shop_price :: proc(right, y: f32, cost: int, tone: rl.Color) {
	text := fmt.ctprintf("%d", cost)
	w := rl.MeasureTextEx(ui_font_body, text, UI_BODY_SIZE, 1).x
	rl.DrawTextEx(ui_font_body, text, {right - w, y}, UI_BODY_SIZE, 1, tone)

	// A bound bale: a crate with a cross through it, so it reads as goods rather than an empty
	// square.
	S :: f32(14)
	box := rl.Rectangle{right - w - 20, y + 1, S, S}
	rl.DrawRectangleLinesEx(box, 1, tone)
	rl.DrawLineEx({box.x + S / 2, box.y}, {box.x + S / 2, box.y + S}, 1, tone)
	rl.DrawLineEx({box.x, box.y + S / 2}, {box.x + S, box.y + S / 2}, 1, tone)
}

// draw_offer_shop_control is the column's one control: a ground, a 2px border in the tone that
// states its role, and a label in the same tone. No fill marks it as the default action — the
// guide holds that controls do not have a signal colour, and leaving is not the default anyway.
draw_offer_shop_control :: proc(rect: rl.Rectangle, label: string, hovered: bool) {
	text := fmt.ctprintf("%s", label)
	rl.DrawRectangleRec(rect, hovered ? colour_shade(COLOUR_PARCHMENT, 1.06) : COLOUR_PARCHMENT)
	rl.DrawRectangleLinesEx(rect, 2, COLOUR_SEA_DEEP)
	size := rl.MeasureTextEx(ui_font_body, text, UI_BODY_SIZE, 1)
	rl.DrawTextEx(
		ui_font_body,
		text,
		{rect.x + (rect.width - size.x) / 2, rect.y + (rect.height - size.y) / 2},
		UI_BODY_SIZE,
		1,
		COLOUR_SEA_DEEP,
	)
}
