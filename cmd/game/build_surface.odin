package main

import "core:fmt"
import "core:math/linalg"
import ship "../../core/ship"
import sim "../../core/sim"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// The Build surface is the ship "always in refit" (#302, ADR-0024): the Cutaway that
// replaces the modal refit_menu_loop's programmer-art slot list. The ship is drawn as
// a cross-section — the 4 exposed stations ride the deck, the 4 holds sit in the belly
// below a drawn waterline — so geography carries the exposed/concealed split (ADR-0030)
// rather than a badge, and a card's footprint tracks its slot size so size reads without
// a number. Refit is drag-first: press-drag-release installs / moves / swaps, the
// exact-size fit rule left to the Sim (an illegal drop returns Event_Refit_Rejected and
// snaps back). The one amber on the screen is a granted item waiting on the shelf.
//
// Split composition (draw_build_surface) from polling (build_surface_loop) like the Chart
// Table, so --capture photographs it (#277, style guide).

// Layout constants. A pure function of the window and the slot sizes, hit-tested and
// drawn from one place (build_slot_rects) — the same no-layout-system idiom the Chart
// Table established.
BUILD_MAX_SLOTS :: 8
BUILD_SLOT_GAP :: 18
BUILD_DECK_Y :: 100
BUILD_WATERLINE_Y :: 290
BUILD_HOLD_Y :: 312
BUILD_LEDGER_Y :: 650
BUILD_LEDGER_H :: 34
BUILD_HEADING_Y :: 28
BUILD_SHELF_Y :: 470

// BUILD_DANGER is the discard zone's muted maroon — the Fight stage_tint's hue, the one
// warm the guide admits beside amber, pulled into the palette's register. Used only to
// mark "drop here to bin it", never as a fill that competes with the amber shelf card.
BUILD_DANGER :: rl.Color{166, 72, 90, 255}

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

// build_card_dims is a card's footprint by slot size — Large > Medium > Small — so size
// reads off the card's own size (#302), no number needed. `scale` shrinks the whole
// size-language uniformly, so the encounter stages (#312) can sit the same ship beside a
// shelf without re-deciding what a Large card is; Home draws it at scale 1.
build_card_dims :: proc(size: ship.Slot_Size, scale: f32 = 1) -> (w: f32, h: f32) {
	switch size {
	case .Small:
		return 140 * scale, 110 * scale
	case .Medium:
		return 190 * scale, 130 * scale
	case .Large:
		return 250 * scale, 150 * scale
	}
	return 140 * scale, 110 * scale
}

// build_slot_rects lays every slot out into two centred rows — exposed stations on the
// deck, concealed holds in the belly — in layout order within each row, card size
// tracking slot size. A pure function of the layout, so draw and hit-test both ask for it
// rather than sharing a local (the split that lets capture draw a screen it never clicks).
// Value array, no allocation; `n` is how many of the BUILD_MAX_SLOTS entries are live.
//
// The rows are centred within [area_x, area_x + area_w] rather than the whole window, and
// sized at `scale`, so the encounter stages (#312) can pin the ship to a left region and
// clear a right-hand shelf while Home keeps the full width at scale 1 (the defaults).
build_slot_rects :: proc(
	layout: []ship.Layout_Slot,
	area_x: f32 = 0,
	area_w: f32 = WINDOW_WIDTH,
	deck_y: f32 = BUILD_DECK_Y,
	hold_y: f32 = BUILD_HOLD_Y,
	scale: f32 = 1,
) -> (rects: [BUILD_MAX_SLOTS]rl.Rectangle, n: int) {
	n = min(len(layout), BUILD_MAX_SLOTS)
	gap := BUILD_SLOT_GAP * scale

	// A row is centred: sum its cards' widths and the gaps between them, then start it so
	// the whole run is centred in the area.
	row_width :: proc(layout: []ship.Layout_Slot, want: ship.Visibility, n: int, gap, scale: f32) -> f32 {
		total: f32 = 0
		count := 0
		for ls, i in layout {
			if i >= n || ls.slot.base_visibility != want {
				continue
			}
			w, _ := build_card_dims(ls.slot.size, scale)
			total += w
			count += 1
		}
		if count > 1 {
			total += f32(count - 1) * gap
		}
		return total
	}

	place_row :: proc(
		layout: []ship.Layout_Slot,
		rects: ^[BUILD_MAX_SLOTS]rl.Rectangle,
		want: ship.Visibility,
		row_y, area_x, area_w, gap, scale: f32,
		n: int,
	) {
		x := area_x + (area_w - row_width(layout, want, n, gap, scale)) / 2
		for ls, i in layout {
			if i >= n || ls.slot.base_visibility != want {
				continue
			}
			w, h := build_card_dims(ls.slot.size, scale)
			rects[i] = rl.Rectangle{x = x, y = row_y, width = w, height = h}
			x += w + gap
		}
	}

	place_row(layout, &rects, .Exposed, deck_y, area_x, area_w, gap, scale, n)
	place_row(layout, &rects, .Concealed, hold_y, area_x, area_w, gap, scale, n)
	return rects, n
}

// build_shelf_rect is where a granted item rests, centred below the holds — the one thing
// on the surface to act on, so it takes the screen's single amber (#302, the amber rule).
build_shelf_rect :: proc(incoming: ship.Fitting) -> rl.Rectangle {
	w, h := build_card_dims(incoming.size)
	return rl.Rectangle{x = (WINDOW_WIDTH - w) / 2, y = BUILD_SHELF_Y, width = w, height = h}
}

// build_done_rect is the steel "leave the refit" control — a Refit_Finish. It is not
// amber: the amber is reserved for the granted item, and leaving is never the default.
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

// build_slot_at returns the slot whose card the point is over, or nil.
build_slot_at :: proc(state: ^Game_State, point: rl.Vector2) -> Maybe(ship.Slot_Index) {
	rects, n := build_slot_rects(state.player.layout)
	for i in 0 ..< n {
		if rl.CheckCollisionPointRec(point, rects[i]) {
			return ship.Slot_Index(i)
		}
	}
	return nil
}

// build_begin_drag decides whether a press starts a drag, and from where: the shelf item
// if the press is on it, else the filled slot under the press. An empty slot or open water
// starts nothing.
build_begin_drag :: proc(state: ^Game_State, point: rl.Vector2) -> (Build_Drag, bool) {
	if incoming, has_incoming := state.refit_incoming.?; has_incoming {
		if rl.CheckCollisionPointRec(point, build_shelf_rect(incoming)) {
			return Build_Drag{active = true, from_slot = nil, fitting = incoming}, true
		}
	}
	if slot, over := build_slot_at(state, point).?; over {
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

		// Confirm sub-state: a destructive drop is one deliberate click away from committing,
		// or a click anywhere else cancels it.
		if confirm, confirming := pending_confirm.?; confirming {
			draw_build_surface(state, Build_Drag{}, pending_confirm, mouse)
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
			draw_build_surface(state, drag, nil, mouse)
			if rl.IsMouseButtonReleased(.LEFT) {
				on_discard := rl.CheckCollisionPointRec(mouse, build_discard_rect())
				on_ledger := rl.CheckCollisionPointRec(mouse, build_ledger_rect())
				cmd, ready, wants := build_drop_command(state, drag, build_slot_at(state, mouse), on_discard, on_ledger)
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
		draw_build_surface(state, drag, nil, mouse)
		if rl.IsMouseButtonPressed(.LEFT) {
			if rl.CheckCollisionPointRec(mouse, build_done_rect()) {
				return sim.Command(sim.Command_Refit{command = sim.Refit_Finish{}})
			}
			if started, ok := build_begin_drag(state, mouse); ok {
				drag = started
			}
		}
	}
}

// draw_build_surface draws one whole frame of the Cutaway. Split from build_surface_loop so
// composing and polling are separate acts — the loop draws then polls, capture draws and
// never polls (#277). `drag` is the in-flight drag (its ghost drawn at `mouse`), `confirm`
// a pending discard's slot, `mouse` the cursor for hover and the ghost.
draw_build_surface :: proc(state: ^Game_State, drag: Build_Drag, confirm: Maybe(Build_Confirm), mouse: rl.Vector2) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	draw_build_surface_body(state, drag, confirm, mouse, false)
}

// draw_build_surface_body composes the Cutaway without owning the frame's Begin/EndDrawing, so
// Home (draw_home) can lay the raised chart over the same surface inside one drawing pair.
// `at_home` is the two Home/Refit differences: a granted Refit is titled "Refit" and shows a
// steel Done (Refit_Finish); Home is the persistent "At Anchor" ground and shows no Done — it
// leaves by sailing, not by finishing, so its Home wrapper draws a chart tab over this body
// instead. Everything else is shared, and the shelf block is naturally skipped at Home, where
// there is never a granted item.
draw_build_surface_body :: proc(state: ^Game_State, drag: Build_Drag, confirm: Maybe(Build_Confirm), mouse: rl.Vector2, at_home: bool) {
	rl.ClearBackground(COLOUR_DEEP)

	draw_build_hull()
	rects, n := build_slot_rects(state.player.layout)

	// A drag dims everything that is not a legal berth for it, so the eye is drawn to where
	// the fitting can land (#302). With no drag, nothing dims.
	incoming, has_incoming := state.refit_incoming.?
	dragging := drag.active

	draw_build_zone_label(rl.Vector2{45, 74}, "TOPSIDE", .Exposed)
	draw_build_zone_label(rl.Vector2{45, BUILD_WATERLINE_Y + 6}, "BELOW", .Concealed)

	for i in 0 ..< n {
		// The slot the drag was lifted from reads as empty while the fitting is in the air.
		layout_slot := state.player.layout[i]
		if dragging {
			if from, ok := drag.from_slot.?; ok && int(from) == i {
				layout_slot.fitting = nil
			}
		}
		legal := dragging && build_is_legal_berth(state, drag, ship.Slot_Index(i))
		draw_build_card(rects[i], layout_slot, dragging && !legal, legal)
	}

	// The ledger arms as a burn target only while a laden berth is in the air: nothing else
	// can be burned, so it stays an inert stats strip the rest of the time.
	burnable := dragging && slot_dragged(drag) && drag.fitting.cargo_held > 0
	draw_build_ledger(state, burnable, burnable && rl.CheckCollisionPointRec(mouse, build_ledger_rect()))
	if !at_home {
		draw_build_done(mouse)
	}

	// The shelf: a granted item at rest is the screen's one amber. While it is being
	// dragged the resting card gives way to the ghost, so there are never two.
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
	// At Home the parchment page brings its own torn edge as the frame (spec 0001 §2), so no
	// vignette here; Refit is a separate surface and keeps its own.
	if !at_home {
		draw_vignette()
	}
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
// rule). The hull spans [area_x, area_x + area_w] with its lines at the given heights, so
// the encounter stages (#312) can draw a narrower, higher cross-section beside a shelf
// while Home fills the window (the defaults).
draw_build_hull :: proc(
	area_x: f32 = 0,
	area_w: f32 = WINDOW_WIDTH,
	deck_top_y: f32 = BUILD_DECK_Y - 22,
	waterline_y: f32 = BUILD_WATERLINE_Y,
	keel_y: f32 = BUILD_LEDGER_Y - 40,
) {
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

// draw_build_heading names the screen, cream, top-left — the display tone, biggest thing in
// the corner it sits in (the guide's hierarchy: colour first). The word is the caller's: a
// granted Refit reads "Refit", the persistent Home "At Anchor".
draw_build_heading :: proc(title: string) {
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", title), rl.Vector2{45, BUILD_HEADING_Y}, UI_BODY_SIZE, 1, COLOUR_CREAM)
}

// draw_build_zone_label draws a zone's name with a supporting eye / eye-off glyph: what a
// scout can see (Exposed) and can't (Concealed) per ADR-0030. The glyph is supporting, not
// load-bearing — geography already carries the split — so it is small and dim.
draw_build_zone_label :: proc(pos: rl.Vector2, label: string, visibility: ship.Visibility) {
	eye_c := rl.Vector2{pos.x + 8, pos.y + 9}
	tint := rl.Fade(COLOUR_STEEL, 0.7)
	rl.DrawEllipseLines(i32(eye_c.x), i32(eye_c.y), 9, 5, tint)
	rl.DrawCircleV(eye_c, 2, tint)
	if visibility == .Concealed {
		// The eye struck through: a hold is what an opponent cannot see.
		rl.DrawLineEx(rl.Vector2{eye_c.x - 9, eye_c.y + 5}, rl.Vector2{eye_c.x + 9, eye_c.y - 5}, 2, tint)
	}
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", label), rl.Vector2{pos.x + 24, pos.y}, UI_BODY_SIZE, 1, tint)
}

// draw_build_card draws one slot: a filled fitting (steel-bordered, draggable), a bare
// hold (quieter recessive-blue border), or an empty slot (dashed steel outline). A legal
// berth for the current drag lights cyan; an illegal one while a drag is up is dimmed, so
// the surface points at where a fitting can go (#302).
draw_build_card :: proc(rect: rl.Rectangle, layout_slot: ship.Layout_Slot, dim: bool, legal: bool) {
	fitting, has_fitting := layout_slot.fitting.?
	is_hold := has_fitting && ship.ship_fitting_is_hold(fitting)

	// The card's role decides its border tone: steel for an interactive fitting, recessive
	// blue for inert cargo, dashed steel for an empty berth (framing: a 2px role border over
	// a translucent ground, never a filled box).
	if !has_fitting {
		draw_build_dashed_rect(rect, legal ? COLOUR_CYAN : COLOUR_STEEL)
	} else {
		rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, 0.55))
		border := is_hold ? COLOUR_BLUE_RECESSIVE : COLOUR_STEEL
		if legal {
			border = COLOUR_CYAN
		}
		rl.DrawRectangleLinesEx(rect, 2, border)
	}
	if legal {
		rl.DrawRectangleRec(rect, rl.Fade(COLOUR_CYAN, 0.12))
	}

	x := rect.x + 12
	// Name (cream), or the empty-slot note (dim steel, ADR-0004's size spelled out).
	if !has_fitting {
		rl.DrawTextEx(
			ui_font_body,
			fmt.ctprintf("(empty %v)", layout_slot.slot.size),
			rl.Vector2{x, rect.y + 10},
			UI_BODY_SIZE,
			1,
			rl.Fade(COLOUR_STEEL, 0.6),
		)
	} else {
		name_tone := is_hold ? rl.Fade(COLOUR_CREAM, 0.75) : COLOUR_CREAM
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", fitting.name), rl.Vector2{x, rect.y + 10}, UI_BODY_SIZE, 1, name_tone)

		if is_hold {
			rl.DrawTextEx(
				ui_font_body,
				fmt.ctprintf("holds %d", fitting.cargo_held),
				rl.Vector2{x, rect.y + 38},
				UI_BODY_SIZE,
				1,
				COLOUR_STEEL,
			)
		} else {
			// Phase is a steel chip (no new hue — the guide is silent on category colour
			// and #302 keeps it that way), the effect intent steel beside/under it.
			chip_w := draw_build_phase_chip(rl.Vector2{x, rect.y + 36}, fitting_phase_label(fitting))
			rl.DrawTextEx(
				ui_font_body,
				fmt.ctprintf("%s", fitting_effect_intent(fitting)),
				rl.Vector2{x + chip_w + 8, rect.y + 38},
				UI_BODY_SIZE,
				1,
				COLOUR_STEEL,
			)
		}
	}

	// The slot's name and size, recessive — present, never read first.
	rl.DrawTextEx(
		ui_font_body,
		fmt.ctprintf("%s %v", layout_slot.slot.name, layout_slot.slot.size),
		rl.Vector2{x, rect.y + rect.height - 26},
		UI_BODY_SIZE,
		1,
		COLOUR_BLUE_RECESSIVE,
	)

	if dim {
		rl.DrawRectangleRec(rect, rl.Fade(COLOUR_VIGNETTE, 0.55))
	}
}

// draw_build_phase_chip draws the phase chip — a steel-outlined tag, no fill, no new hue —
// and returns its width so the effect intent can sit beside it. Takes the label rather than
// a phase because an item may feed both (fitting_phase_label).
draw_build_phase_chip :: proc(pos: rl.Vector2, phases: string) -> f32 {
	label := fmt.ctprintf("%s", phases)
	text_w := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1).x
	chip := rl.Rectangle{x = pos.x, y = pos.y, width = text_w + 12, height = 24}
	rl.DrawRectangleLinesEx(chip, 1, rl.Fade(COLOUR_STEEL, 0.8))
	rl.DrawTextEx(ui_font_body, label, rl.Vector2{pos.x + 6, pos.y + 2}, UI_BODY_SIZE, 1, COLOUR_STEEL)
	return chip.width
}

// draw_build_dashed_rect outlines an empty slot in dashes — raylib has no dash pattern, so
// the border is drawn as segments, the same technique as the Chart Table's route.
draw_build_dashed_rect :: proc(rect: rl.Rectangle, colour: rl.Color) {
	corners := [4]rl.Vector2 {
		{rect.x, rect.y},
		{rect.x + rect.width, rect.y},
		{rect.x + rect.width, rect.y + rect.height},
		{rect.x, rect.y + rect.height},
	}
	DASH :: 8
	tint := rl.Fade(colour, 0.7)
	for i in 0 ..< 4 {
		a, b := corners[i], corners[(i + 1) % 4]
		span := rl.Vector2Distance(a, b)
		steps := max(1, int(span / DASH))
		for s in 0 ..< steps {
			if s % 2 == 1 {
				continue
			}
			t0 := f32(s) / f32(steps)
			t1 := f32(s + 1) / f32(steps)
			rl.DrawLineEx(linalg.lerp(a, b, t0), linalg.lerp(a, b, t1), 2, tint)
		}
	}
}

// draw_build_shelf draws a granted item at rest — the screen's one amber (#302, the amber
// rule): amber-filled with ink text, the single thing on the surface to act on.
draw_build_shelf :: proc(incoming: ship.Fitting) {
	rect := build_shelf_rect(incoming)
	rl.DrawRectangleRec(rect, COLOUR_AMBER)
	x := rect.x + 12
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", incoming.name), rl.Vector2{x, rect.y + 10}, UI_BODY_SIZE, 1, COLOUR_INK)
	spec, intent := fitting_summary_lines(incoming)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", spec), rl.Vector2{x, rect.y + 38}, UI_BODY_SIZE, 1, COLOUR_INK)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", intent), rl.Vector2{x, rect.y + 62}, UI_BODY_SIZE, 1, COLOUR_INK)
	rl.DrawTextEx(
		ui_font_body,
		"drag me to a berth",
		rl.Vector2{rect.x, rect.y + rect.height + 6},
		UI_BODY_SIZE,
		1,
		COLOUR_CYAN_DIM,
	)
}

// draw_build_ghost draws the fitting under the cursor while it is dragged — a translucent
// amber card centred on the mouse, so the thing in hand reads as the thing to place.
draw_build_ghost :: proc(fitting: ship.Fitting, mouse: rl.Vector2) {
	w, h := build_card_dims(fitting.size)
	rect := rl.Rectangle{x = mouse.x - w / 2, y = mouse.y - h / 2, width = w, height = h}
	rl.DrawRectangleRec(rect, rl.Fade(COLOUR_AMBER, 0.85))
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", fitting.name), rl.Vector2{rect.x + 12, rect.y + 10}, UI_BODY_SIZE, 1, COLOUR_INK)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%v", fitting.size), rl.Vector2{rect.x + 12, rect.y + 38}, UI_BODY_SIZE, 1, COLOUR_INK)
}

// draw_build_ledger is the stats strip along the bottom, always visible: Hull · SPD ·
// Hold · Weight, the derived reads (ADR-0020) not the raw fields. A recessive-blue-bordered
// translucent panel — inert chrome, framed by its role tone.
//
// `armed` turns it into the burn target (#401): with a laden berth in the air the border
// takes the danger tone and the strip names what a drop would do, brightening on `hovered`.
// The two reads sit on one panel because burning is what *changes* the numbers on it — the
// ledger is both what the burn costs and where it is paid.
draw_build_ledger :: proc(state: ^Game_State, armed: bool = false, hovered: bool = false) {
	panel := build_ledger_rect()
	rl.DrawRectangleRec(panel, rl.Fade(COLOUR_GROUND, armed && hovered ? 0.8 : 0.6))
	rl.DrawRectangleLinesEx(panel, 2, armed ? BUILD_DANGER : COLOUR_BLUE_RECESSIVE)
	if armed {
		rl.DrawRectangleRec(panel, rl.Fade(BUILD_DANGER, hovered ? 0.28 : 0.12))
		hint := fmt.ctprint("drop to burn this cargo")
		size := rl.MeasureTextEx(ui_font_body, hint, UI_BODY_SIZE, 1)
		rl.DrawTextEx(
			ui_font_body,
			hint,
			rl.Vector2{panel.x + panel.width - size.x - 14, panel.y + (BUILD_LEDGER_H - UI_BODY_SIZE) / 2},
			UI_BODY_SIZE,
			1,
			COLOUR_CREAM,
		)
	}

	s := &state.player
	text := fmt.ctprintf(
		"Hull %d/%d   ·   SPD %d   ·   Hold %d/%d   ·   Weight %d",
		s.hull,
		s.max_hull,
		ship.ship_effective_speed(s),
		ship.ship_cargo(s^),
		ship.ship_cargo_capacity(s^),
		ship.ship_weight(s^),
	)
	rl.DrawTextEx(ui_font_body, text, rl.Vector2{panel.x + 14, panel.y + (BUILD_LEDGER_H - UI_BODY_SIZE) / 2}, UI_BODY_SIZE, 1, COLOUR_STEEL)
}

// draw_build_done draws the steel "leave the refit" control, its scrim lifting on hover
// (hover is carried by the scrim, not by amber — the amber rule).
draw_build_done :: proc(mouse: rl.Vector2) {
	rect := build_done_rect()
	hovered := rl.CheckCollisionPointRec(mouse, rect)
	rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, hovered ? 0.75 : 0.55))
	rl.DrawRectangleLinesEx(rect, 2, COLOUR_STEEL)
	rl.DrawTextEx(ui_font_body, "Done", rl.Vector2{rect.x + 44, rect.y + (rect.height - UI_BODY_SIZE) / 2}, UI_BODY_SIZE, 1, COLOUR_STEEL)
}

// draw_build_discard_zone draws the "this thing leaves the ship" target, only while a drag is
// up. Muted maroon (the one warm the guide admits beside amber), brighter when the cursor is
// over it. It is named for what it does to the *fitting* — the word Jettison belongs to cargo
// (ADR-0028), which is the ledger's drop, so the two destructive targets never share a name.
draw_build_discard_zone :: proc(hovered: bool) {
	rect := build_discard_rect()
	rl.DrawRectangleRec(rect, rl.Fade(BUILD_DANGER, hovered ? 0.35 : 0.18))
	rl.DrawRectangleLinesEx(rect, 2, BUILD_DANGER)
	rl.DrawTextEx(ui_font_body, "Over the Side", rl.Vector2{rect.x + 14, rect.y + 12}, UI_BODY_SIZE, 1, COLOUR_STEEL)
	rl.DrawTextEx(ui_font_body, "drag off to bin", rl.Vector2{rect.x + 14, rect.y + 40}, UI_BODY_SIZE, 1, rl.Fade(COLOUR_STEEL, 0.7))
}

// draw_build_confirm draws the release-to-confirm gate: a scrim over the surface and one amber
// button — the deliberate second act that keeps a slip from binning a fitting or burning a
// berth's cargo (#302, #401). The wording is the whole difference between the two: a discard
// loses the fitting, a burn loses the cargo and keeps the fitting. This is the only moment a
// destructive drop shows the screen's amber, and there is no shelf item then, so the one-amber
// rule holds.
draw_build_confirm :: proc(state: ^Game_State, confirm: Build_Confirm, mouse: rl.Vector2) {
	rl.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, rl.Fade(COLOUR_VIGNETTE, 0.7))
	name := "this fitting"
	cargo := 0
	if fitting, filled := state.player.layout[confirm.slot].fitting.?; filled {
		name = fitting.name
		cargo = fitting.cargo_held
	}

	prompt := fmt.ctprintf("Put %s over the side? There is no getting it back.", name)
	label := fmt.ctprint("Over the side")
	if confirm.burn {
		// The berth, not the fitting: a bare hold is named "Cargo", so "the cargo in Cargo"
		// says nothing, where the slot's name points at the card on screen.
		prompt = fmt.ctprintf(
			"Jettison the %d cargo in %s? That is score, gone for good.",
			cargo,
			state.player.layout[confirm.slot].slot.name,
		)
		label = fmt.ctprint("Jettison it")
	}
	size := rl.MeasureTextEx(ui_font_body, prompt, UI_BODY_SIZE, 1)
	rl.DrawTextEx(ui_font_body, prompt, rl.Vector2{(WINDOW_WIDTH - size.x) / 2, 320}, UI_BODY_SIZE, 1, COLOUR_CREAM)

	yes := build_confirm_yes_rect()
	rl.DrawRectangleRec(yes, COLOUR_AMBER)
	rl.DrawTextEx(ui_font_body, label, rl.Vector2{yes.x + 16, yes.y + (yes.height - UI_BODY_SIZE) / 2}, UI_BODY_SIZE, 1, COLOUR_INK)
	rl.DrawTextEx(
		ui_font_body,
		"click anywhere else to keep it",
		rl.Vector2{(WINDOW_WIDTH - 260) / 2, yes.y + yes.height + 10},
		UI_BODY_SIZE,
		1,
		COLOUR_CYAN_DIM,
	)
}

// Home is the Build surface made the persistent between-encounters screen (#317, ADR-0024):
// the same Cutaway as a granted Refit, but the player's own resting ground rather than a modal
// the Sim hands them. There is no granted item, so no amber and no shelf — drags do free
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
			draw_home(state, Build_Drag{}, nil, mouse, 1)
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
			draw_home(state, Build_Drag{}, nil, mouse, 1)
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
			draw_home(state, Build_Drag{}, nil, mouse, chart_raise)
			continue
		}

		// From here the chart is fully lowered: the Build surface is the live screen.

		// Confirm sub-state: a destructive drop is one deliberate click from committing, or a
		// click anywhere else cancels it (same as build_surface_loop).
		if confirm, confirming := pending_confirm.?; confirming {
			draw_home(state, Build_Drag{}, pending_confirm, mouse, 0)
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
			draw_home(state, drag, nil, mouse, 0)
			if rl.IsMouseButtonReleased(.LEFT) {
				on_discard := rl.CheckCollisionPointRec(mouse, build_discard_rect())
				on_ledger := rl.CheckCollisionPointRec(mouse, build_ledger_rect())
				cmd, ready, wants := build_drop_command(state, drag, build_slot_at(state, mouse), on_discard, on_ledger)
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
		draw_home(state, drag, nil, mouse, 0)
		if rl.IsMouseButtonPressed(.LEFT) {
			if rl.CheckCollisionPointRec(mouse, home_chart_tab_rect()) {
				chart_target = 1
			} else if started, ok := build_begin_drag(state, mouse); ok {
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
draw_home :: proc(state: ^Game_State, drag: Build_Drag, confirm: Maybe(Build_Confirm), mouse: rl.Vector2, raise: f32) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	draw_build_surface_body(state, drag, confirm, mouse, true)

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
// (home_chart_tab_rect). Unlike the encounter's view-only twin it is a steel control whose
// scrim lifts on hover, and its caret points up to raise the chart or down to lower it, flipping
// once the chart passes its midpoint. A shape, not a glyph, wound to survive raylib's clockwise
// cull.
draw_home_chart_tab :: proc(raise: f32, mouse: rl.Vector2) {
	rect := home_chart_tab_rect()
	hovered := rl.CheckCollisionPointRec(mouse, rect)
	rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, hovered ? 0.75 : 0.55))
	draw_subpanel_border(rect, true)

	// Past the midpoint the tab reads "Lower" and its caret points down; at rest raise is 0 or 1,
	// so this tracks chart_target, and mid-flip it turns over as the chart crosses halfway.
	chart_raised := raise >= 0.5
	label := chart_raised ? fmt.ctprint("Lower") : fmt.ctprint("Chart")
	lsize := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1)
	CARET := f32(16)
	GAP := f32(6)
	group_x := rect.x + (rect.width - (CARET + GAP + lsize.x)) / 2
	caret_cx := group_x + CARET / 2
	cy := rect.y + rect.height / 2
	if chart_raised {
		rl.DrawTriangle(
			rl.Vector2{caret_cx - 7, cy - 4},
			rl.Vector2{caret_cx, cy + 6},
			rl.Vector2{caret_cx + 7, cy - 4},
			COLOUR_STEEL,
		)
	} else {
		rl.DrawTriangle(
			rl.Vector2{caret_cx - 7, cy + 4},
			rl.Vector2{caret_cx + 7, cy + 4},
			rl.Vector2{caret_cx, cy - 6},
			COLOUR_STEEL,
		)
	}
	rl.DrawTextEx(
		ui_font_body,
		label,
		rl.Vector2{group_x + CARET + GAP, rect.y + (rect.height - UI_BODY_SIZE) / 2},
		UI_BODY_SIZE,
		1,
		COLOUR_STEEL,
	)
}
