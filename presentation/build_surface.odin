#+private
package presentation

import "core:fmt"
import "core:math/linalg"
import cutaway "./cutaway"
import ship "../core/ship"
import sim "../core/sim"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// The Build surface is the ship "always in refit" (#302, ADR-0024): the Cutaway that
// replaces the modal refit_menu_loop's programmer-art slot list. The ship is drawn as a
// three-quarter cutaway of the player's own galleon with her port side opened up
// (ship_cutaway.odin) — the exposed berths standing as her weather-deck structures, the
// concealed holds sharing one floor down in the belly — so geography carries the
// exposed/concealed split (ADR-0030) rather than a badge, and a hold's compartment length
// tracks its slot size so size reads without a number. Refit is drag-first:
// press-drag-release installs / moves / swaps, the exact-size fit rule left to the Sim (an
// illegal drop returns Event_Refit_Rejected and snaps back). Nothing on the surface is singled
// out by colour: the shelf item, the card in hand and the Done tag are all ordinary controls,
// and only the destructive drops reach for the reserved coral (BUILD_DANGER).
//
// Split composition (draw_build_surface) from polling (build_surface_loop) like the Chart
// Table, so --capture photographs it (#277, style guide).

// Chrome constants — the ledger, heading and shelf are the Build surface's own furniture.
// The ship's geometry is not: the cutaway module owns it (#426), and this surface asks
// galleon_rooms / galleon_room_at rather than keeping positions of its own.
BUILD_LEDGER_Y :: 650
BUILD_LEDGER_H :: 34
BUILD_HEADING_Y :: 28
BUILD_SHELF_Y :: 470

// BUILD_DANGER is the tone of the surface's destructive acts — the roster's reserved coral, and
// the only colour with a job on this screen. It reaches three places: the discard bin, an armed
// hold ledger, and the confirm gate's yes.
//
// The guide holds coral to one appearance per screen, and the bin and an armed ledger are both up
// during a laden drag. That is deliberate: the two are one signal, "a drop here destroys
// something", on the only two places it is true, and neither is on screen unless a fitting is
// already in hand. The rule guards against diluting a scarce colour across unrelated meanings,
// which is not what this is. The gate carries the same signal and cannot coincide with either —
// it only opens once the drag has ended and both drop targets are gone.
BUILD_DANGER :: COLOUR_CORAL

// Build_Drag is a press-drag-release in progress: the drag primitive #302 builds here for refit.
// (The Chart once reused it for a raise/lower swipe; #329 retired that for a click toggle, so the
// drag is refit-only again.) `from_slot` nil means the dragged
// fitting is the granted item lifted off the shelf (an Install/Replace when dropped);
// a slot index means an installed fitting being moved, dragged off to discard, or dragged
// onto the hold ledger to burn what it carries.
Build_Drag :: struct {
	active:    bool,
	from_slot: Maybe(ship.Slot_Index),
	fitting:   ship.Fitting,
}

// build_shelf_rect is where a granted item rests, centred below the holds. That placement is
// what marks it as the thing to act on: it sits in the way of everything else on the surface.
build_shelf_rect :: proc(incoming: ship.Fitting) -> rl.Rectangle {
	w, h := cutaway.cutaway_card_dims(incoming.size)
	return rl.Rectangle{x = (WINDOW_WIDTH - w) / 2, y = BUILD_SHELF_Y, width = w, height = h}
}

// build_done_rect is the "leave the refit" control — a Refit_Finish. Tucked into the heading
// row, out of the way: leaving is never what the surface is for, and the corner says so.
build_done_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle{x = WINDOW_WIDTH - 150, y = BUILD_HEADING_Y - 6, width = 130, height = 34}
}

// build_discard_rect is the "drag a fitting here to bin it" zone (no inventory, ADR-0012).
// Bottom-left, out of the ship, so a drop here reads as "overboard".
build_discard_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle{x = 30, y = 560, width = 200, height = 70}
}

// build_ledger_rect is the hold ledger's panel — the stats strip along the bottom, and the
// drop target for an out-of-combat burn (#401): dragging a laden fitting onto the ledger
// burns what it carries, which reads as "put this berth's cargo back on the books" rather
// than "throw the berth away". Deliberately *not* the discard bin, whose meaning stays "this
// thing leaves the ship".
build_ledger_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle{x = 40, y = BUILD_LEDGER_Y, width = WINDOW_WIDTH - 80, height = BUILD_LEDGER_H}
}

// build_confirm_yes_rect is the deliberate release-to-confirm for a destructive drop: a Wraith
// Cannon is never binned by a slip, and a misdrag onto the ledger costs the run's score (#302,
// #401), so drag-off opens this and only a click on it commits.
build_confirm_yes_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle{x = (WINDOW_WIDTH - 260) / 2, y = 360, width = 260, height = 44}
}

// Build_Confirm is a destructive drop waiting on the captain's second click. `burn` is which
// of the two it is: a burn empties the berth's cargo and leaves the fitting installed, a
// discard takes the whole fitting off the ship. One gate serves both, since both cost
// something there is no getting back.
Build_Confirm :: struct {
	slot: ship.Slot_Index,
	burn: bool,
}

// build_drop_command maps a completed drag — its source and where it was released — to the
// loadout Command it commits, mirroring refit_click's pure mapping so the interaction is
// testable without a live window. The exact-size fit rule is the Sim's, not predicted here
// (ADR-0004): a wrong-size Move/Install/Replace is emitted anyway and bounces back as
// Event_Refit_Rejected. The two destructive drops don't commit directly — each asks for a
// confirm — so they return a `confirm` rather than a command.
//
// The two destructive targets carry different meanings and must not be confused: the discard
// bin is "this thing leaves the ship", the hold ledger "burn what this berth is carrying"
// (#401). Keeping them apart is what stops a laden gun from being unremovable — the bin still
// takes the whole fitting, load and all.
build_drop_command :: proc(
	state: ^Game_State,
	drag: Build_Drag,
	target: Maybe(ship.Slot_Index),
	on_discard: bool,
	on_ledger: bool,
) -> (
	cmd: sim.Command,
	ready: bool,
	confirm: Maybe(Build_Confirm),
) {
	from_slot, dragging_slot := drag.from_slot.?

	if !dragging_slot {
		// Dragging the granted shelf item: a berth installs it (empty) or swaps into it
		// (filled). Released anywhere else, it returns to the shelf.
		slot, has_target := target.?
		if !has_target {
			return {}, false, nil
		}
		if _, occupied := state.player.layout[slot].fitting.?; occupied {
			return sim.Command(sim.Command_Refit{command = sim.Refit_Replace{slot = slot}}), true, nil
		}
		return sim.Command(sim.Command_Refit{command = sim.Refit_Install{slot = slot}}), true, nil
	}

	// Dragging an installed fitting: onto another slot moves it; over the discard zone bins
	// it and over the hold ledger burns its cargo (each after a confirm); back onto itself or
	// into open water cancels. A fitting carrying nothing has nothing to burn, so the ledger
	// is inert under it.
	if on_discard {
		return {}, false, Build_Confirm{slot = from_slot, burn = false}
	}
	if on_ledger {
		if drag.fitting.cargo_held == 0 {
			return {}, false, nil
		}
		return {}, false, Build_Confirm{slot = from_slot, burn = true}
	}
	slot, has_target := target.?
	if !has_target || slot == from_slot {
		return {}, false, nil
	}
	return sim.Command(sim.Command_Refit{command = sim.Refit_Move{from = from_slot, to = slot}}), true, nil
}

// build_confirm_command is the Command a confirmed destructive drop commits — the one place
// the burn/discard split becomes two different loadout operations, so both surfaces' loops
// commit it the same way.
build_confirm_command :: proc(confirm: Build_Confirm) -> sim.Command {
	if confirm.burn {
		return sim.Command(sim.Command_Refit{command = sim.Refit_Jettison_Cargo{slot = confirm.slot}})
	}
	return sim.Command(sim.Command_Refit{command = sim.Refit_Remove{slot = confirm.slot}})
}

// build_slot_at returns the slot whose room the point is over, or nil — asked of the cutaway
// module over the *caller's* framing, which is the same one the draw was handed, so the click
// resolves against the rooms the eye is actually looking at (#476). The view inside a framing is
// built at the logical frame size, which is what keeps picking in the same coordinate system as
// the mouse in the borderless-fullscreen build (cutaway.View).
build_slot_at :: proc(state: ^Game_State, framing: Ship_Framing, point: rl.Vector2) -> Maybe(ship.Slot_Index) {
	return cutaway.galleon_room_at(state.player.layout, point, framing.view)
}

// build_begin_drag decides whether a press starts a drag, and from where: the shelf item
// if the press is on it, else the filled slot under the press. An empty slot or open water
// starts nothing.
build_begin_drag :: proc(state: ^Game_State, framing: Ship_Framing, point: rl.Vector2) -> (Build_Drag, bool) {
	if incoming, has_incoming := state.refit_incoming.?; has_incoming {
		if rl.CheckCollisionPointRec(point, build_shelf_rect(incoming)) {
			return Build_Drag{active = true, from_slot = nil, fitting = incoming}, true
		}
	}
	if slot, over := build_slot_at(state, framing, point).?; over {
		if fitting, filled := state.player.layout[slot].fitting.?; filled {
			return Build_Drag{active = true, from_slot = slot, fitting = fitting}, true
		}
	}
	return {}, false
}

// build_surface_loop is the Build screen's blocking loop, the drag-first successor to
// refit_menu_loop: it renders the Cutaway and returns one loadout Command when a drag
// completes on a target, when a discard is confirmed, or when Done is clicked. run_session
// ticks that command and re-enters for the next, so a whole refit is a sequence of these
// calls — the same shape refit_menu_loop had, now driven by drags rather than clicks.
build_surface_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		return sim.Command(sim.Command_Refit{command = sim.Refit_Finish{}})
	}

	// Shelf-drag bridge (#312): an Offer/Shop shelf drop committed a Choose_Option and
	// remembered the berth it landed on, so the Refit that choice opened installs there and
	// finishes with no second gesture — the spine collapsing "choose option → refit" into one
	// drag. build_shelf_bridge_command drives that to completion without ever polling, so the
	// auto refit is invisible: the player's one drag is the whole gesture. Nil the rest of the
	// time, when this is a Home refit the player drives by hand.
	if cmd, bridging := build_shelf_bridge_command(state); bridging {
		return cmd
	}

	drag: Build_Drag
	pending_confirm: Maybe(Build_Confirm)

	for {
		window_quit_if_closed()
		mouse := rl.GetMousePosition()
		// One framing a frame, handed to the draw and to the hit-test alike: the Build surface
		// only ever looks at her moored (#476).
		framing := ship_framing_moored()

		// Confirm sub-state: a destructive drop is one deliberate click away from committing,
		// or a click anywhere else cancels it.
		if confirm, confirming := pending_confirm.?; confirming {
			draw_build_surface(state, framing, Build_Drag{}, pending_confirm, mouse)
			if rl.IsMouseButtonPressed(.LEFT) {
				if rl.CheckCollisionPointRec(mouse, build_confirm_yes_rect()) {
					return build_confirm_command(confirm)
				}
				pending_confirm = nil
			}
			continue
		}

		// A drag in flight: the ghost follows the cursor until release, when where it lands
		// decides the command (or a cancel).
		if drag.active {
			draw_build_surface(state, framing, drag, nil, mouse)
			if rl.IsMouseButtonReleased(.LEFT) {
				on_discard := rl.CheckCollisionPointRec(mouse, build_discard_rect())
				on_ledger := rl.CheckCollisionPointRec(mouse, build_ledger_rect())
				target := build_slot_at(state, framing, mouse)
				cmd, ready, wants := build_drop_command(state, drag, target, on_discard, on_ledger)
				drag.active = false
				if confirm, asked := wants.?; asked {
					pending_confirm = confirm
				} else if ready {
					return cmd
				}
			}
			continue
		}

		// Resting: draw, then a press either leaves (Done) or lifts a fitting into a drag.
		draw_build_surface(state, framing, drag, nil, mouse)
		if rl.IsMouseButtonPressed(.LEFT) {
			if rl.CheckCollisionPointRec(mouse, build_done_rect()) {
				return sim.Command(sim.Command_Refit{command = sim.Refit_Finish{}})
			}
			if started, ok := build_begin_drag(state, framing, mouse); ok {
				drag = started
			}
		}
	}
}

// draw_build_surface draws one whole frame of the Cutaway. Split from build_surface_loop so
// composing and polling are separate acts — the loop draws then polls, capture draws and
// never polls (#277). `drag` is the in-flight drag (its ghost drawn at `mouse`), `confirm`
// a pending discard's slot, `mouse` the cursor for hover and the ghost.
draw_build_surface :: proc(
	state: ^Game_State,
	framing: Ship_Framing,
	drag: Build_Drag,
	confirm: Maybe(Build_Confirm),
	mouse: rl.Vector2,
) {
	frame_begin()
	defer frame_end()
	defer free_all(context.temp_allocator)

	draw_build_surface_body(state, framing, drag, confirm, mouse, false)
}

// draw_build_surface_body composes the Cutaway without owning the frame's Begin/EndDrawing, so
// Home (draw_home) can lay the raised chart over the same surface inside one drawing pair.
// `at_home` is the two Home/Refit differences: a granted Refit is titled "Refit" and shows a
// Done control (Refit_Finish); Home is the persistent "At Anchor" ground and shows no Done — it
// leaves by sailing, not by finishing, so its Home wrapper draws a chart tab over this body
// instead. Everything else is shared, and the shelf block is naturally skipped at Home, where
// there is never a granted item.
draw_build_surface_body :: proc(
	state: ^Game_State,
	framing: Ship_Framing,
	drag: Build_Drag,
	confirm: Maybe(Build_Confirm),
	mouse: rl.Vector2,
	at_home: bool,
) {
	// The ship herself, and everything that reads off her rooms: the hover highlight and its
	// description card, and — while a drag is up — the berths the fitting in hand may land in
	// lit and the rest dimmed (#302).
	draw_ship_cutaway(state, framing, drag, mouse, describe = true)

	incoming, has_incoming := state.refit_incoming.?
	dragging := drag.active

	// The ledger arms as a burn target only while a laden berth is in the air: nothing else
	// can be burned, so it stays an inert stats strip the rest of the time.
	burnable := dragging && slot_dragged(drag) && drag.fitting.cargo_held > 0
	draw_build_ledger(state, burnable, burnable && rl.CheckCollisionPointRec(mouse, build_ledger_rect()))
	if !at_home {
		draw_build_done(mouse)
	}

	// The shelf: a granted item at rest. While it is being dragged the resting card gives way to
	// the ghost, so there is one card to follow rather than two.
	if has_incoming && !dragging {
		draw_build_shelf(incoming)
	}

	if dragging {
		draw_build_discard_zone(rl.CheckCollisionPointRec(mouse, build_discard_rect()))
		draw_build_ghost(drag.fitting, mouse)
	}

	if pending, confirming := confirm.?; confirming {
		draw_build_confirm(state, pending, mouse)
	}

	draw_build_heading(at_home ? "At Anchor" : "Refit")
	draw_chart_table_version_stamp()
}

// slot_dragged reports whether the in-flight drag is a slot fitting (not the shelf item),
// which is what tells draw_build_surface whether the resting shelf card should still show.
slot_dragged :: proc(drag: Build_Drag) -> bool {
	_, ok := drag.from_slot.?
	return ok
}

// build_is_legal_berth is the UI's affordance hint only — what the fit rule admits
// (ship_fitting_fits: matching size, and exposed if the fitting requires it), plus free for a
// slot move — highlighting where a fitting can land. It is not the fit rule's authority: the
// Sim still validates the emitted command, so this only steers the eye, and a drop on an
// illegal berth is emitted and bounced rather than silently blocked here. It asks the rule
// rather than restating it, so the hint cannot drift from what the Sim will accept.
build_is_legal_berth :: proc(state: ^Game_State, drag: Build_Drag, slot: ship.Slot_Index) -> bool {
	if !ship.ship_fitting_fits(state.player.layout[slot].slot, drag.fitting) {
		return false
	}
	from, dragging_slot := drag.from_slot.?
	if !dragging_slot {
		return true // the shelf item can install (empty) or swap (filled) into any same-size berth
	}
	if slot == from {
		return false
	}
	// A move needs a free destination, and free means empty *or* carrying nothing but a
	// bare hold — every vacated slot backfills one, so an empty berth is unreachable and
	// an empty-only rule would leave nothing draggable-to.
	dest, occupied := state.player.layout[slot].fitting.?
	return !occupied || ship.ship_fitting_is_hold(dest)
}

// draw_build_hull sketches the ship's cross-section behind the cards: a faint hull outline
// and the waterline that splits deck from belly. Kept quiet (low-alpha steel) — it frames
// the split, it must never outshine the cards or the chrome (the guide's world-vs-chrome
// rule). Where the lines sit is the region's answer (the cutaway module); this proc only
// paints them, which is why it stays in this package with the palette.
draw_build_hull :: proc(region: cutaway.Region) {
	area_x := region.x
	area_w := region.w
	deck_top_y := region.deck_y - 22
	waterline_y := region.waterline_y
	keel_y := region.keel_y
	area_r := area_x + area_w

	// The belly reads a shade deeper than the deck's air, so "below the waterline" is a
	// darker, concealed place at a glance.
	rl.DrawRectangleRec(
		rl.Rectangle{x = area_x, y = waterline_y, width = area_w, height = WINDOW_HEIGHT - waterline_y},
		rl.Fade(COLOUR_VIGNETTE, 0.45),
	)

	// A hull silhouette: deck line across, sides sloping into a keel, so the belly cards sit
	// inside a ship rather than in an open box. The keel is inset a fifth of the width from
	// each side, so it stays a hull whatever the area's width.
	inset := area_w * 0.19
	deck_l := rl.Vector2{area_x + 60, deck_top_y}
	deck_r := rl.Vector2{area_r - 60, deck_top_y}
	keel_l := rl.Vector2{area_x + inset, keel_y}
	keel_r := rl.Vector2{area_r - inset, keel_y}
	hull := rl.Fade(COLOUR_STEEL, 0.16)
	rl.DrawLineEx(deck_l, deck_r, 2, hull)
	rl.DrawLineEx(deck_l, keel_l, 2, hull)
	rl.DrawLineEx(deck_r, keel_r, 2, hull)
	rl.DrawLineEx(keel_l, keel_r, 2, hull)

	// The waterline itself: a dim-cyan rule with a row of ticks, the sea's surface.
	water := rl.Fade(COLOUR_CYAN_DIM, 0.5)
	rl.DrawLineEx(
		rl.Vector2{area_x + 40, waterline_y},
		rl.Vector2{area_r - 40, waterline_y},
		2,
		water,
	)
	for x := area_x + 60; x < area_r - 60; x += 26 {
		rl.DrawLineEx(rl.Vector2{x, waterline_y}, rl.Vector2{x + 8, waterline_y + 4}, 1, rl.Fade(COLOUR_CYAN_DIM, 0.3))
	}
}

// draw_build_heading names the screen, cream, top-left — the display tone at the display size.
// The word is the caller's: a granted Refit reads "Refit", the persistent Home "At Anchor".
//
// At body size it was the same 16px as the version stamp opposite it and the ledger below, and a
// screen title that is the same size as everything else is not a title — it read as a caption
// mislaid in the corner. The guide's first hierarchy level is a heading at the display size,
// cream where it is placed over the sea, which is exactly where this one is.
draw_build_heading :: proc(title: string) {
	ui_heading({45, BUILD_HEADING_Y, WINDOW_WIDTH - 90, UI_TITLE_SIZE}, title, .Title, .Water)
}

// draw_fitting_card lays down the paper a fitting is written up on. A ui_card carries the
// parchment, the border and — at Floating — the cast shadow, so this is now only the choice
// of elevation: a card at rest sits on the surface, a card in hand is off it. The berth cards
// (draw_ship_slot_card) are the same object drawn the same way; keep the two in step.
draw_fitting_card :: proc(rect: rl.Rectangle, elevation := Ui_Elevation.Flush) {
	ui_card(rect, .Primary, elevation)
}

// BUILD_CARD_INSET is the margin a card's writing keeps off its own edge, and BUILD_CARD_ROW
// the step between its lines — both off the named scale, so the shelf, the ghost and the
// berth cards share one rhythm rather than three copies of the same numbers.
BUILD_CARD_INSET :: Ui_Space.Base
BUILD_CARD_ROW :: Ui_Space.Loose

// build_card_row is where one of a card's lines runs: the full inset width, stepped down by
// the scale. One derivation, so a card's lines cannot disagree about its margins.
build_card_row :: proc(rect: rl.Rectangle, row: int) -> rl.Rectangle {
	inset := ui_space(BUILD_CARD_INSET)
	return rl.Rectangle {
		x = rect.x + inset,
		y = rect.y + inset - ui_space(.Hair) + f32(row) * ui_space(BUILD_CARD_ROW),
		width = rect.width - 2 * inset,
		height = UI_BODY_SIZE,
	}
}

// draw_build_shelf draws a granted item at rest. Nothing about the card singles it out — no
// colour on the roster means "act here" (style guide, "Controls do not have a signal colour")
// — so the caption under it is what says to drag it, and the caption is therefore load-bearing
// rather than decorative. It sits over open water, which is what cream is for on the roster.
draw_build_shelf :: proc(incoming: ship.Fitting) {
	rect := build_shelf_rect(incoming)
	draw_fitting_card(rect)

	spec, intent := fitting_summary_lines(incoming)
	for text, row in ([?]string{incoming.name, spec, intent}) {
		ui_text(build_card_row(rect, row), text, .Body, .Parchment)
	}

	ui_text(
		{rect.x, rect.y + rect.height + ui_space(.Hair), rect.width, UI_BODY_SIZE},
		"drag me to a berth",
		.Body,
		.Water,
	)
}

// draw_build_ghost draws the fitting under the cursor while it is dragged: the resting card,
// translucent and centred on the mouse. What says "this is in your hand" is that it follows the
// cursor, so it needs no tone of its own. draw_build_surface_body hides the shelf for the
// duration of the drag, so there is only ever one of these cards on screen.
draw_build_ghost :: proc(fitting: ship.Fitting, mouse: rl.Vector2) {
	w, h := cutaway.cutaway_card_dims(fitting.size)
	rect := rl.Rectangle{x = mouse.x - w / 2, y = mouse.y - h / 2, width = w, height = h}
	// Floating rather than faded: a card in hand is one that has been lifted *off* the
	// surface, and over a bright sea translucency costs it its own ground (ADR-0032). The
	// shadow says lifted; following the cursor says in hand.
	draw_fitting_card(rect, .Floating)
	ui_text(build_card_row(rect, 0), fitting.name, .Body, .Parchment)
	ui_text(build_card_row(rect, 1), fmt.tprintf("%v", fitting.size), .Body, .Parchment, .Secondary)
}

// draw_build_ledger is the stats strip along the bottom, always visible: the shared
// ship_stat_line (#428) with its Weight term, the derived reads (ADR-0020) not the raw
// fields. Words live on parchment (the guide's two grounds), which is also what keeps the
// numbers legible over open water.
//
// `armed` turns it into the burn target (#401): with a laden berth in the air the border
// takes the danger tone and the strip names what a drop would do, brightening on `hovered`.
// The two reads sit on one panel because burning is what *changes* the numbers on it — the
// ledger is both what the burn costs and where it is paid.
draw_build_ledger :: proc(state: ^Game_State, armed: bool = false, hovered: bool = false) {
	panel := build_ledger_rect()
	ui_panel(panel, .Flush)
	baseline := panel.y + (BUILD_LEDGER_H - UI_BODY_SIZE) / 2

	// Armed, the bar stops being a readout and becomes a target. The stats give way to the one
	// instruction, centred: a cargo is already in the air, and what the captain needs off this
	// strip at that moment is what a release here would cost, not her weight.
	if armed {
		ui_alarm(panel, hovered)
		// Left, where the stats read from — not centred. The card in hand is opaque and centred
		// on the cursor, and a cursor over this strip is a cursor over its middle, so a centred
		// instruction is an instruction under the very thing it is instructing about.
		ui_text(
			{panel.x + ui_space(BUILD_CARD_INSET), baseline, panel.width, UI_BODY_SIZE},
			"drop to burn this cargo",
			.Body,
			.Parchment,
		)
		return
	}

	// At rest: the readout's terms laid out in columns across the bar, each divided from the
	// next. The bar is the full width of the screen and the line is a fifth of it, so set as one
	// sentence it left the other four fifths as empty parchment — width the strip was spending
	// and not using. In columns the width is what separates one term from the next.
	//
	// Label muted, number primary. Almost everything a captain weighs on this screen is a number,
	// so the number is what has to come off the bar first, and the guide ranks by colour.
	// Each term gets exactly the width it needs, and the slack is shared out equally as the
	// gutter between them. Cutting the bar into equal columns instead put every term at the left
	// edge of a cell it filled about a third of, so each one was followed by a long ragged gap
	// and the divider that should separate it from the next stood a hundred pixels clear of
	// both. Measured columns give the row one rhythm, and each rule falls midway between the two
	// terms it divides.
	fields := ship_stat_fields(s = &state.player, weight = true)
	inset := ui_space(BUILD_CARD_INSET)
	widths := make([]f32, len(fields), context.temp_allocator)
	packed := f32(0)
	for field, i in fields {
		widths[i] = ui_text_size(fmt.tprintf("%s %s", field.label, field.value), .Body).x
		packed += widths[i]
	}
	gutter := (panel.width - inset * 2 - packed) / f32(max(len(fields) - 1, 1))
	x := panel.x + inset
	for field, i in fields {
		if i > 0 {
			ui_divider(
				{x - gutter / 2, panel.y + ui_space(.Snug), UI_WEIGHT_PX[.Hair], BUILD_LEDGER_H - 2 * ui_space(.Snug)},
				.Hair,
				.Parchment,
			)
		}
		gap := ui_text_size(fmt.tprintf("%s ", field.label), .Body).x
		row := rl.Rectangle{x, baseline, widths[i], UI_BODY_SIZE}
		ui_text(row, field.label, .Body, .Parchment, .Secondary)
		ui_text({row.x + gap, row.y, row.width - gap, row.height}, field.value, .Body, .Parchment)
		x += widths[i] + gutter
	}
}

// draw_build_done draws the "leave the refit" control: a sea-deep-outlined parchment tag, its
// ground lifting on hover (hover is carried by the ground, never by a change of colour).
draw_build_done :: proc(mouse: rl.Vector2) {
	rect := build_done_rect()
	ui_button(rect, "Done", rl.CheckCollisionPointRec(mouse, rect) ? .Hover : .Rest)
}

// draw_build_discard_zone draws the "this thing leaves the ship" target, only while a drag is
// up: a parchment panel washed in the danger tone, deepening when the cursor is over it. It is
// named for what it does to the *fitting* — the word Jettison belongs to cargo (ADR-0028),
// which is the ledger's drop, so the two destructive targets never share a name.
draw_build_discard_zone :: proc(hovered: bool) {
	rect := build_discard_rect()
	ui_card(rect, .Primary, .Flush)
	ui_alarm(rect, hovered)
	ui_text(build_card_row(rect, 0), "Over the Side", .Body, .Parchment)
	ui_text(build_card_row(rect, 1), "drag off to bin", .Body, .Parchment, .Secondary)
}

// draw_build_confirm draws the release-to-confirm gate: a scrim over the surface and one button
// — the deliberate second act that keeps a slip from binning a fitting or burning a berth's
// cargo (#302, #401). The wording is the whole difference between the two: a discard loses the
// fitting, a burn loses the cargo and keeps the fitting.
//
// The yes takes the danger tone, in the discard bin's treatment, because it is the bin's second
// half — the guide's "no colour means act here" governs the *default action*, and a destructive
// confirmation is not one. See BUILD_DANGER for why coral reaching here stays scarce.
draw_build_confirm :: proc(state: ^Game_State, confirm: Build_Confirm, mouse: rl.Vector2) {
	rl.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, rl.Fade(COLOUR_VIGNETTE, 0.7))
	name := "this fitting"
	cargo := 0
	if fitting, filled := state.player.layout[confirm.slot].fitting.?; filled {
		name = fitting.name
		cargo = fitting.cargo_held
	}

	prompt := fmt.tprintf("Put %s over the side? There is no getting it back.", name)
	label := "Over the side"
	if confirm.burn {
		// The berth, not the fitting: a bare hold is named "Cargo", so "the cargo in Cargo"
		// says nothing, where the slot's name points at the card on screen.
		prompt = fmt.tprintf(
			"Jettison the %d cargo in %s? That is score, gone for good.",
			cargo,
			state.player.layout[confirm.slot].slot.name,
		)
		label = "Jettison it"
	}
	ui_text({0, 320, WINDOW_WIDTH, UI_BODY_SIZE}, prompt, .Body, .Water, .Primary, .Centre)

	yes := build_confirm_yes_rect()
	ui_card(yes, .Primary, .Flush)
	ui_alarm(yes, false)
	ui_text(yes, label, .Body, .Parchment, .Primary, .Centre)
	ui_text(
		{0, yes.y + yes.height + ui_space(.Snug), WINDOW_WIDTH, UI_BODY_SIZE},
		"click anywhere else to keep it",
		.Body,
		.Water,
		.Muted,
		.Centre,
	)
}

// Home is the Build surface made the persistent between-encounters screen (#317, ADR-0024):
// the same Cutaway as a granted Refit, but the player's own resting ground rather than a modal
// the Sim hands them. There is no granted item, so no shelf — drags do free
// reallocation (a slot Move, or a drag-off-to-Jettison Remove), each a Command_Refit the Sim
// applies in place and stays at anchor (sim_process_anchor_refit). In place of the Refit's Done,
// the **chart** flips up over the surface on a click of the bottom-centre tab; a click on a
// reachable node there sails (Command_Travel_To), and a click on the raised tab lowers it. #324's
// press-drag-release swipe was the stand-in this retires (#329) — a plain click toggle instead.
//
// The chart's elevation is still a continuous `raise` in [0, 1] (0 lowered, 1 raised): a tab click
// flips `chart_target` between the ends and chart_settle tweens chart_raise there, so the click
// reads as one continuous slide rather than a snap. draw_home composes the surface with the chart
// laid over it at any `raise`, so --capture and the run-game skill can shoot a mid-flip frame (#277).

// CHART_RISE_TRAVEL is the on-screen distance the chart slides: a full window height, so at
// raise 0 the chart sits entirely below the visible area and rises into place as raise → 1.
CHART_RISE_TRAVEL :: f32(WINDOW_HEIGHT)
// CHART_SETTLE_SPEED is the flip animation's rate in raise-units per second: after a tab click
// the chart tweens to its end (~1/8 s for a full span) rather than snapping, so the flip reads
// as one continuous motion.
CHART_SETTLE_SPEED :: f32(8)

// chart_settle steps a chart_raise one frame toward its toggle target, snapping to the target
// once within a frame's step — the tween that carries a clicked flip to its end. A no-op when
// already at rest (raise == target), so a lowered, un-touched chart costs nothing.
chart_settle :: proc(raise, target: f32) -> f32 {
	if raise == target {
		return raise
	}
	step := CHART_SETTLE_SPEED * rl.GetFrameTime()
	if raise < target {
		return min(raise + step, target)
	}
	return max(raise - step, target)
}

// chart_offset is the on-screen translation the raised chart is drawn under: centred horizontally
// over the Home surface (MAP_AREA is left-pinned so it can pair with the beat-background ship panel
// elsewhere — the centre is applied here at Home only), and slid down by the un-raised fraction of
// its travel so the chart rises from below as raise → 1. draw_home translates by this and un-shifts
// the hover cursor by it; home_loop un-shifts the node hit-test by it, so clicks land on the mark
// the eye sees.
chart_offset :: proc(raise: f32) -> rl.Vector2 {
	return rl.Vector2{(WINDOW_WIDTH - MAP_AREA.width) / 2 - MAP_AREA.x, (1 - raise) * CHART_RISE_TRAVEL}
}

// home_chart_tab_rect is the Home chart tab's slot: the shared bottom-centre flick position
// (encounter_chart_tab_rect, #304), lifted to sit just above Home's stats ledger. Home is the
// one place the flick tab and a bottom stats ledger coexist — an encounter frame carries its
// stats top-right — so the encounter tab sits flush to the edge while Home's clears its ledger.
home_chart_tab_rect :: proc() -> rl.Rectangle {
	rect := encounter_chart_tab_rect()
	rect.y = BUILD_LEDGER_Y - rect.height - 10
	return rect
}

// home_chart_page_rect is the parchment page's on-screen slot at a given raise: MAP_AREA carried
// through the same chart_offset draw_map_page is drawn under, so a hit-test asks about the page
// the eye sees. The page is the torn sheet itself (view.odin:247) — everything outside it is the
// darkened Build surface showing through, the four-sided cutaway that frames the map (spec §1).
// This is the sheet's *bounding box*, so the torn rim's transparent corners fall just inside it
// and read as margin without dismissing (measured: MAP_AREA's corner is Build navy, not
// parchment). That way round on purpose — the alternative, insetting to the rim, would let a
// click on visible parchment near the edge roll the map away under a player aiming at a node.
home_chart_page_rect :: proc(raise: f32) -> rl.Rectangle {
	offset := chart_offset(raise)
	rect := MAP_AREA
	rect.x += offset.x
	rect.y += offset.y
	return rect
}

// home_chart_roll_down reports whether a click on the fully-unfurled chart is a "leave" gesture:
// the two-state toggle's exits are a re-tap of the chart tab, or a click anywhere on the visible
// Build margin around the page (spec §1 — click-outside dismiss). The tab sits *inside* the page
// rect at Home (it clears the stats ledger, home_chart_tab_rect), so the two are disjoint and both
// roll the map down. A click on the page that isn't the tab is left to the node hit-test: the map
// stays up, since only the margin dismisses. Pure over the window's rects, so it tests without one.
home_chart_roll_down :: proc(mouse: rl.Vector2) -> bool {
	if rl.CheckCollisionPointRec(mouse, home_chart_tab_rect()) {
		return true
	}
	return !rl.CheckCollisionPointRec(mouse, home_chart_page_rect(1))
}

// home_loop is the between-encounters blocking loop, the Awaiting_Travel_Choice successor to
// travel_menu_loop: it renders the Build surface as Home and returns either a Command_Refit when
// a free reallocation drag completes, or a Command_Travel_To when a node is clicked on the raised
// chart. run_session ticks that command and re-enters, so a run of free refits between two sails
// is a sequence of these calls — the same shape build_surface_loop has, minus a shelf and a
// Finish.
home_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): sail a legal option as a harmless
		// placeholder, matching travel_menu_loop's retired fallback; the current node when none.
		if len(state.travel_options) > 0 {
			return sim.Command(sim.Command_Travel_To{node_id = state.travel_options[0]})
		}
		return sim.Command(sim.Command_Travel_To{node_id = state.current_node_id})
	}

	drag: Build_Drag
	pending_confirm: Maybe(Build_Confirm)
	chart_raise: f32 = 0 // 0 lowered .. 1 raised, the chart's live elevation
	chart_target: f32 = 0 // 0 or 1: the end a tab click is flipping the chart toward

	for {
		window_quit_if_closed()
		mouse := rl.GetMousePosition()
		// One framing a frame, handed to the draw and to the hit-test alike (#476).
		framing := ship_framing_moored()
		map_width_set(state, MAP_HOME_W) // the raised chart owns this screen — full-width page

		// The chart eases toward its toggle target each frame. A lowered, un-touched chart is
		// already at its target, so this is a no-op on the resting Build surface.
		chart_raise = chart_settle(chart_raise, chart_target)

		// Sailing: a destination is chosen but not yet committed, so the ship is out on the leg
		// and every other input is swallowed. A click or Space snaps to arrival — the sail is
		// never a forced wait (spec §5) — and only on arrival does the Sim hear the move.
		// Draw before polling, as the raised chart does: raylib refreshes the pressed edge in
		// EndDrawing, so a skip tested ahead of the frame's draw would still see the very click
		// that set the sail going and snap it to arrival on its first frame.
		if dest, sailing := state.sail_pending.?; sailing {
			draw_home(state, framing, Build_Drag{}, nil, mouse, 1)
			skipped := rl.IsMouseButtonPressed(.LEFT) || rl.IsKeyPressed(.SPACE)

			// Landed. The ship holds on the node it reached while the arrival's ink sets (spec
			// §6), and only then does the Sim hear the move. The hold is what makes the bloom
			// exist at all: Command_Travel_To hands the screen straight to the encounter the node
			// opens, so without it the frame after arrival is not the chart and the ripple plays
			// to nobody. Measured in the running game — the first cut recorded the bloom and left
			// immediately, and it was never once visible. The skip covers the hold too, so travel
			// is still never a forced wait.
			if state.sail_progress >= 1 {
				bloom, setting := state.arrival_bloom.?
				if !setting {
					// The moment the *sprite* touches the node — the same moment for a skipped
					// sail, whose progress was forced to 1. The bloom is a flourish on the
					// motion, not on the Sim's bookkeeping, so it starts here and not on the
					// Sim's arrival event.
					state.arrival_bloom = Ink_Bloom{node = dest, started = rl.GetTime()}
					continue
				}
				if skipped || rl.GetTime() - bloom.started >= INK_BLOOM_LIFE {
					state.sail_pending = nil
					state.sail_progress = 0
					return sim.Command(sim.Command_Travel_To{node_id = dest})
				}
				continue
			}

			if skipped {
				state.sail_progress = 1
			} else {
				state.sail_progress = sail_advance(state.sail_progress, rl.GetFrameTime())
			}
			continue
		}

		// Chart raised and at rest: the sailable overlay over the still-present Build surface. A
		// click on a reachable node sets the ship sailing toward it; a click on the tab or on the
		// Build margin framing the page rolls the chart back down (home_chart_roll_down). The node
		// hit-test is travel_menu_loop's, over the same emitted options the Sim gates on, with the
		// cursor un-shifted by the chart's centre/rise offset so it lands on the mark the eye sees.
		if chart_raise >= 1 && chart_target >= 1 {
			draw_home(state, framing, Build_Drag{}, nil, mouse, 1)
			if rl.IsMouseButtonPressed(.LEFT) {
				offset := chart_offset(1)
				hit := rl.Vector2{mouse.x - offset.x, mouse.y - offset.y}
				for dest in state.travel_options {
					if rl.CheckCollisionPointCircle(hit, state.positions[dest], NODE_RADIUS) {
						state.sail_pending = dest
						state.sail_progress = 0
						// Clear the last landing's ripple as this leg begins: the arrival hold
						// above reads the field to tell "this sail has landed" from "still under
						// way", so a bloom left over from the previous arrival would make the new
						// sail look like it had already finished setting and skip its own hold.
						state.arrival_bloom = nil
						break
					}
				}
				if state.sail_pending == nil && home_chart_roll_down(mouse) {
					chart_target = 0
				}
			}
			continue
		}

		// Mid-flip: the chart is animating up or down but not yet at rest. Draw the frame and
		// swallow input so a click never lands on a half-raised chart — the tab only toggles at
		// rest, so neither the surface nor a node is live until the flip settles.
		if chart_raise > 0 || chart_target > 0 {
			draw_home(state, framing, Build_Drag{}, nil, mouse, chart_raise)
			continue
		}

		// From here the chart is fully lowered: the Build surface is the live screen.

		// Confirm sub-state: a destructive drop is one deliberate click from committing, or a
		// click anywhere else cancels it (same as build_surface_loop).
		if confirm, confirming := pending_confirm.?; confirming {
			draw_home(state, framing, Build_Drag{}, pending_confirm, mouse, 0)
			if rl.IsMouseButtonPressed(.LEFT) {
				if rl.CheckCollisionPointRec(mouse, build_confirm_yes_rect()) {
					return build_confirm_command(confirm)
				}
				pending_confirm = nil
			}
			continue
		}

		// A drag in flight: the ghost follows the cursor until release, when where it lands
		// decides the free-reallocation command (Move) or a cancel. With no shelf item at Home,
		// build_begin_drag only ever lifts a filled slot, so build_drop_command yields a Move, a
		// discard or a cargo burn — never an Install/Replace.
		if drag.active {
			draw_home(state, framing, drag, nil, mouse, 0)
			if rl.IsMouseButtonReleased(.LEFT) {
				on_discard := rl.CheckCollisionPointRec(mouse, build_discard_rect())
				on_ledger := rl.CheckCollisionPointRec(mouse, build_ledger_rect())
				target := build_slot_at(state, framing, mouse)
				cmd, ready, wants := build_drop_command(state, drag, target, on_discard, on_ledger)
				drag.active = false
				if confirm, asked := wants.?; asked {
					pending_confirm = confirm
				} else if ready {
					return cmd
				}
			}
			continue
		}

		// Resting: draw, then a click on the chart tab flips it up, or a press lifts a fitting
		// into a refit drag.
		draw_home(state, framing, drag, nil, mouse, 0)
		if rl.IsMouseButtonPressed(.LEFT) {
			if rl.CheckCollisionPointRec(mouse, home_chart_tab_rect()) {
				chart_target = 1
			} else if started, ok := build_begin_drag(state, framing, mouse); ok {
				drag = started
			}
		}
	}
}

// draw_home draws one whole frame of Home at a given chart elevation: the Build surface body,
// then — when `raise` is above 0 — a scrim that deepens with the raise and the chart slid up
// from below and centred over the screen (chart_offset), and the tab on top either way. Split from
// home_loop so composing and polling are separate acts: home_loop passes the live chart_raise, and
// --capture passes a fixed raise to photograph the surface, a mid-flip frame, or the raised chart
// without ever polling (#277). The chart draws over the surface (not beside it) because the flip is
// a raise/lower, not a split view; the rlgl translate slides the whole chart as one, so draw_map
// keeps drawing at its fixed MAP_AREA positions and only the hover mouse is un-shifted back into
// chart space.
draw_home :: proc(
	state: ^Game_State,
	framing: Ship_Framing,
	drag: Build_Drag,
	confirm: Maybe(Build_Confirm),
	mouse: rl.Vector2,
	raise: f32,
) {
	frame_begin()
	defer frame_end()
	defer free_all(context.temp_allocator)

	draw_build_surface_body(state, framing, drag, confirm, mouse, true)

	if raise > 0 {
		rl.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, rl.Fade(COLOUR_DEEP, 0.55 * raise))
		offset := chart_offset(raise)
		rlgl.PushMatrix()
		rlgl.Translatef(offset.x, offset.y, 0)
		// draw_map hit-tests hover against the cursor; the chart is drawn shifted by `offset`, so
		// the cursor is un-shifted by the same amount to keep hover over the mark the eye sees.
		draw_map(state, rl.Vector2{mouse.x - offset.x, mouse.y - offset.y})
		rlgl.PopMatrix()
	}
	draw_home_chart_tab(raise, mouse)
}

// draw_home_chart_tab draws the interactive chart tab at Home's bottom-centre slot
// (home_chart_tab_rect). Unlike the encounter's view-only twin it is a live control whose
// parchment lifts on hover, and its caret points up to raise the chart or down to lower it,
// flipping once the chart passes its midpoint. A shape, not a glyph, wound to survive raylib's
// clockwise cull.
draw_home_chart_tab :: proc(raise: f32, mouse: rl.Vector2) {
	rect := home_chart_tab_rect()
	hovered := rl.CheckCollisionPointRec(mouse, rect)

	// Past the midpoint the tab reads "Lower" and its caret points down; at rest raise is 0 or 1,
	// so this tracks chart_target, and mid-flip it turns over as the chart crosses halfway.
	chart_raised := raise >= 0.5
	label := chart_raised ? "Lower" : "Chart"

	// The frame carries the ground and the hover; only the caret beside the label is this
	// control's own, so the label is placed against the space the caret leaves rather than
	// against the whole tab.
	CARET :: Ui_Space.Wide
	caret := ui_space(CARET)
	gap := ui_space(.Hair) * 3
	group := caret + gap + ui_text_size(label, .Body).x
	group_x := rect.x + (rect.width - group) / 2

	ui_button(rect, "", hovered ? .Hover : .Rest)
	ui_text(
		{group_x + caret + gap, rect.y, rect.width, rect.height},
		label,
		.Body,
		.Parchment,
	)
	draw_home_chart_caret({group_x, rect.y + (rect.height - caret) / 2, caret, caret}, chart_raised)
}

// draw_home_chart_caret points the tab's caret up to raise the chart or down to lower it.
// ui_icon's caret points right — it is the marker in a menu row's margin — and this one turns
// through a quarter, so the shape is wound here rather than growing a rotation axis on an icon
// that has one job everywhere else.
draw_home_chart_caret :: proc(rect: rl.Rectangle, chart_raised: bool) {
	if !ui_drawable() {
		return
	}
	box := ui_pixel_rect(rect)
	cx := box.x + box.width / 2
	tone := ui_ink(.Parchment, .Primary)
	// Vertex order is raylib's counter-clockwise requirement — reverse it and the triangle is
	// culled, drawing nothing at all.
	if chart_raised {
		rl.DrawTriangle({box.x, box.y}, {cx, box.y + box.height}, {box.x + box.width, box.y}, tone)
	} else {
		rl.DrawTriangle({box.x, box.y + box.height}, {box.x + box.width, box.y + box.height}, {cx, box.y}, tone)
	}
}
