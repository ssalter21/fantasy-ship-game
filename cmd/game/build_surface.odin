package main

import "core:fmt"
import "core:math/linalg"
import ship "../../core/ship"
import sim "../../core/sim"
import rl "vendor:raylib"

// The Build surface is the ship "always in refit" (#302, ADR-0024): the Cutaway that
// replaces the modal refit_menu_loop's programmer-art slot list. The ship is drawn as
// a cross-section — the 4 exposed stations ride the deck, the 4 holds sit in the belly
// below a drawn waterline — so geography carries the exposed/concealed split (ADR-0005)
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

// Build_Drag is a press-drag-release in progress: the drag primitive #302 builds here and
// the Chart's swipe (#309/#303) is meant to reuse. `from_slot` nil means the dragged
// fitting is the granted item lifted off the shelf (an Install/Replace when dropped);
// a slot index means an installed fitting being moved or dragged off to discard.
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

// build_confirm_yes_rect is the deliberate release-to-confirm for a discard: a Wraith
// Cannon is never binned by a slip (#302), so drag-off opens this and only a click on it
// commits the Refit_Remove.
build_confirm_yes_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle{x = (WINDOW_WIDTH - 260) / 2, y = 360, width = 260, height = 44}
}

// build_drop_command maps a completed drag — its source and where it was released — to the
// loadout Command it commits, mirroring refit_click's pure mapping so the interaction is
// testable without a live window. The exact-size fit rule is the Sim's, not predicted here
// (ADR-0004): a wrong-size Move/Install/Replace is emitted anyway and bounces back as
// Event_Refit_Rejected. A discard doesn't commit directly — it asks for a confirm — so it
// returns `wants_discard` rather than a command.
build_drop_command :: proc(
	state: ^Game_State,
	drag: Build_Drag,
	target: Maybe(ship.Slot_Index),
	on_discard: bool,
) -> (
	cmd: sim.Command,
	ready: bool,
	wants_discard: Maybe(ship.Slot_Index),
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
	// it (after a confirm); back onto itself or into open water cancels.
	if on_discard {
		return {}, false, from_slot
	}
	slot, has_target := target.?
	if !has_target || slot == from_slot {
		return {}, false, nil
	}
	return sim.Command(sim.Command_Refit{command = sim.Refit_Move{from = from_slot, to = slot}}), true, nil
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
	confirm_discard: Maybe(ship.Slot_Index)

	for {
		window_quit_if_closed()
		mouse := rl.GetMousePosition()

		// Confirm sub-state: a discard is one deliberate click away from committing, or a
		// click anywhere else cancels it.
		if slot, confirming := confirm_discard.?; confirming {
			draw_build_surface(state, Build_Drag{}, confirm_discard, mouse)
			if rl.IsMouseButtonPressed(.LEFT) {
				if rl.CheckCollisionPointRec(mouse, build_confirm_yes_rect()) {
					return sim.Command(sim.Command_Refit{command = sim.Refit_Remove{slot = slot}})
				}
				confirm_discard = nil
			}
			continue
		}

		// A drag in flight: the ghost follows the cursor until release, when where it lands
		// decides the command (or a cancel).
		if drag.active {
			draw_build_surface(state, drag, nil, mouse)
			if rl.IsMouseButtonReleased(.LEFT) {
				on_discard := rl.CheckCollisionPointRec(mouse, build_discard_rect())
				cmd, ready, wants := build_drop_command(state, drag, build_slot_at(state, mouse), on_discard)
				drag.active = false
				if slot, discard := wants.?; discard {
					confirm_discard = slot
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
draw_build_surface :: proc(state: ^Game_State, drag: Build_Drag, confirm: Maybe(ship.Slot_Index), mouse: rl.Vector2) {
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
draw_build_surface_body :: proc(state: ^Game_State, drag: Build_Drag, confirm: Maybe(ship.Slot_Index), mouse: rl.Vector2, at_home: bool) {
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

	draw_build_ledger(state)
	if !at_home {
		draw_build_done(mouse)
	}

	// The shelf: a granted item at rest is the screen's one amber. While it is being
	// dragged the resting card gives way to the ghost, so there are never two.
	if has_incoming && !(dragging && !slot_dragged(drag)) {
		if !dragging {
			draw_build_shelf(incoming)
		}
	}

	if dragging {
		draw_build_discard_zone(rl.CheckCollisionPointRec(mouse, build_discard_rect()))
		draw_build_ghost(drag.fitting, mouse)
	}

	if slot, confirming := confirm.?; confirming {
		draw_build_discard_confirm(state, slot, mouse)
	}

	draw_build_heading(at_home ? "At Anchor" : "Refit")
	draw_vignette()
	draw_chart_table_version_stamp()
}

// slot_dragged reports whether the in-flight drag is a slot fitting (not the shelf item),
// which is what tells draw_build_surface whether the resting shelf card should still show.
slot_dragged :: proc(drag: Build_Drag) -> bool {
	_, ok := drag.from_slot.?
	return ok
}

// build_is_legal_berth is the UI's affordance hint only — same size, and empty for a slot
// move — highlighting where a fitting can land. It is not the fit rule's authority: the Sim
// still validates the emitted command (ADR-0004), so this only steers the eye, and a drop
// on an illegal berth is emitted and bounced rather than silently blocked here.
build_is_legal_berth :: proc(state: ^Game_State, drag: Build_Drag, slot: ship.Slot_Index) -> bool {
	if drag.fitting.size != state.player.layout[slot].slot.size {
		return false
	}
	from, dragging_slot := drag.from_slot.?
	if !dragging_slot {
		return true // the shelf item can install (empty) or swap (filled) into any same-size berth
	}
	if slot == from {
		return false
	}
	_, occupied := state.player.layout[slot].fitting.?
	return !occupied // a move needs an empty destination
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
// scout can see (Exposed) and can't (Concealed) per ADR-0005. The glyph is supporting, not
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

// draw_build_card draws one slot: a filled fitting (steel-bordered, draggable), a cargo
// filler (quieter recessive-blue border), or an empty slot (dashed steel outline). A legal
// berth for the current drag lights cyan; an illegal one while a drag is up is dimmed, so
// the surface points at where a fitting can go (#302).
draw_build_card :: proc(rect: rl.Rectangle, layout_slot: ship.Layout_Slot, dim: bool, legal: bool) {
	fitting, has_fitting := layout_slot.fitting.?
	is_cargo := has_fitting && fitting.is_cargo

	// The card's role decides its border tone: steel for an interactive fitting, recessive
	// blue for inert cargo, dashed steel for an empty berth (framing: a 2px role border over
	// a translucent ground, never a filled box).
	if !has_fitting {
		draw_build_dashed_rect(rect, legal ? COLOUR_CYAN : COLOUR_STEEL)
	} else {
		rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, 0.55))
		border := is_cargo ? COLOUR_BLUE_RECESSIVE : COLOUR_STEEL
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
		name_tone := is_cargo ? rl.Fade(COLOUR_CREAM, 0.75) : COLOUR_CREAM
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", fitting.name), rl.Vector2{x, rect.y + 10}, UI_BODY_SIZE, 1, name_tone)

		if is_cargo {
			rl.DrawTextEx(
				ui_font_body,
				fmt.ctprintf("holds %d", fitting.stack_count),
				rl.Vector2{x, rect.y + 38},
				UI_BODY_SIZE,
				1,
				COLOUR_STEEL,
			)
		} else {
			// Category is a steel chip (no new hue — the guide is silent on category colour
			// and #302 keeps it that way), the effect intent steel beside/under it.
			chip_w := draw_build_category_chip(rl.Vector2{x, rect.y + 36}, fitting.category)
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

// draw_build_category_chip draws the Muster / Brace / Fire chip — a steel-outlined tag, no
// fill, no new hue — and returns its width so the effect intent can sit beside it.
draw_build_category_chip :: proc(pos: rl.Vector2, category: ship.Category) -> f32 {
	label := fmt.ctprintf("%v", category)
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

// draw_build_ledger is the stats strip along the bottom, always visible: Hull · DUR · SPD ·
// Hold · Weight, the derived reads (ADR-0020) not the raw fields. A recessive-blue-bordered
// translucent panel — inert chrome, framed by its role tone.
draw_build_ledger :: proc(state: ^Game_State) {
	panel := rl.Rectangle{x = 40, y = BUILD_LEDGER_Y, width = WINDOW_WIDTH - 80, height = BUILD_LEDGER_H}
	rl.DrawRectangleRec(panel, rl.Fade(COLOUR_GROUND, 0.6))
	rl.DrawRectangleLinesEx(panel, 2, COLOUR_BLUE_RECESSIVE)

	s := &state.player
	text := fmt.ctprintf(
		"Hull %d/%d   ·   DUR %d   ·   SPD %d   ·   Hold %d/%d   ·   Weight %d",
		s.hull,
		s.max_hull,
		ship.ship_effective_durability(s),
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

// draw_build_discard_zone draws the "overboard" target, only while a drag is up. Muted
// maroon (the one warm the guide admits beside amber), brighter when the cursor is over it.
draw_build_discard_zone :: proc(hovered: bool) {
	rect := build_discard_rect()
	rl.DrawRectangleRec(rect, rl.Fade(BUILD_DANGER, hovered ? 0.35 : 0.18))
	rl.DrawRectangleLinesEx(rect, 2, BUILD_DANGER)
	rl.DrawTextEx(ui_font_body, "Jettison", rl.Vector2{rect.x + 14, rect.y + 12}, UI_BODY_SIZE, 1, COLOUR_STEEL)
	rl.DrawTextEx(ui_font_body, "drag off to bin", rl.Vector2{rect.x + 14, rect.y + 40}, UI_BODY_SIZE, 1, rl.Fade(COLOUR_STEEL, 0.7))
}

// draw_build_discard_confirm draws the release-to-confirm gate: a scrim over the surface and
// one amber "Discard" button — the deliberate second act that keeps a slip from binning a
// fitting (#302). This is the only moment discard shows the screen's amber, and there is no
// shelf item then, so the one-amber rule holds.
draw_build_discard_confirm :: proc(state: ^Game_State, slot: ship.Slot_Index, mouse: rl.Vector2) {
	rl.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, rl.Fade(COLOUR_VIGNETTE, 0.7))
	name := "this fitting"
	if fitting, filled := state.player.layout[slot].fitting.?; filled {
		name = fitting.name
	}
	prompt := fmt.ctprintf("Jettison %s? There is no getting it back.", name)
	size := rl.MeasureTextEx(ui_font_body, prompt, UI_BODY_SIZE, 1)
	rl.DrawTextEx(ui_font_body, prompt, rl.Vector2{(WINDOW_WIDTH - size.x) / 2, 320}, UI_BODY_SIZE, 1, COLOUR_CREAM)

	yes := build_confirm_yes_rect()
	rl.DrawRectangleRec(yes, COLOUR_AMBER)
	rl.DrawTextEx(ui_font_body, "Jettison it", rl.Vector2{yes.x + 16, yes.y + (yes.height - UI_BODY_SIZE) / 2}, UI_BODY_SIZE, 1, COLOUR_INK)
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
// a corner-tab raises the **chart** over the surface; a click on a reachable node there sails
// (Command_Travel_To). The tab is the shipped stand-in the map's fog names for the swipe, and it
// reuses the same press-drag-release primitive #302 built for refit.

// home_chart_tab_rect is the Home chart tab's slot: the shared bottom-centre flick position
// (encounter_chart_tab_rect, #304), lifted to sit just above Home's stats ledger. Home is the
// one place the flick tab and a bottom stats ledger coexist — an encounter frame carries its
// stats top-right — so the encounter tab sits flush to the edge while Home's clears its ledger.
home_chart_tab_rect :: proc() -> rl.Rectangle {
	rect := encounter_chart_tab_rect()
	rect.y = BUILD_LEDGER_Y - rect.height - 10
	return rect
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
	confirm_discard: Maybe(ship.Slot_Index)
	chart_raised := false

	for {
		window_quit_if_closed()
		mouse := rl.GetMousePosition()

		// Chart raised: the sailable overlay over the still-present Build surface. A click on a
		// reachable node sails; a click on the (now "lower") tab drops back to the surface. The
		// node hit-test is travel_menu_loop's, over the same emitted options the Sim gates on.
		if chart_raised {
			draw_home(state, Build_Drag{}, nil, mouse, true)
			if rl.IsMouseButtonPressed(.LEFT) {
				for dest in state.travel_options {
					if rl.CheckCollisionPointCircle(mouse, state.positions[dest], NODE_RADIUS) {
						return sim.Command(sim.Command_Travel_To{node_id = dest})
					}
				}
				if rl.CheckCollisionPointRec(mouse, home_chart_tab_rect()) {
					chart_raised = false
				}
			}
			continue
		}

		// Confirm sub-state: a discard is one deliberate click from committing, or a click
		// anywhere else cancels it (same as build_surface_loop).
		if slot, confirming := confirm_discard.?; confirming {
			draw_home(state, Build_Drag{}, confirm_discard, mouse, false)
			if rl.IsMouseButtonPressed(.LEFT) {
				if rl.CheckCollisionPointRec(mouse, build_confirm_yes_rect()) {
					return sim.Command(sim.Command_Refit{command = sim.Refit_Remove{slot = slot}})
				}
				confirm_discard = nil
			}
			continue
		}

		// A drag in flight: the ghost follows the cursor until release, when where it lands
		// decides the free-reallocation command (Move) or a cancel. With no shelf item at Home,
		// build_begin_drag only ever lifts a filled slot, so build_drop_command yields a Move or
		// a discard — never an Install/Replace.
		if drag.active {
			draw_home(state, drag, nil, mouse, false)
			if rl.IsMouseButtonReleased(.LEFT) {
				on_discard := rl.CheckCollisionPointRec(mouse, build_discard_rect())
				cmd, ready, wants := build_drop_command(state, drag, build_slot_at(state, mouse), on_discard)
				drag.active = false
				if slot, discard := wants.?; discard {
					confirm_discard = slot
				} else if ready {
					return cmd
				}
			}
			continue
		}

		// Resting: draw, then a press raises the chart (its tab) or lifts a fitting into a drag.
		draw_home(state, drag, nil, mouse, false)
		if rl.IsMouseButtonPressed(.LEFT) {
			if rl.CheckCollisionPointRec(mouse, home_chart_tab_rect()) {
				chart_raised = true
			} else if started, ok := build_begin_drag(state, mouse); ok {
				drag = started
			}
		}
	}
}

// draw_home draws one whole frame of Home: the Build surface body, then — when the chart is
// raised — a dimming scrim and the chart laid over it, and the corner tab on top either way.
// Split from home_loop so composing and polling are separate acts, so --capture photographs
// both the resting surface and the raised chart (#277). The chart draws over the surface (not
// beside it) because the tab stand-in is a raise/lower, not a split view — the swipe that
// replaces it (fog) will animate this same over-lay.
draw_home :: proc(state: ^Game_State, drag: Build_Drag, confirm: Maybe(ship.Slot_Index), mouse: rl.Vector2, chart_raised: bool) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	draw_build_surface_body(state, drag, confirm, mouse, true)

	if chart_raised {
		rl.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, rl.Fade(COLOUR_DEEP, 0.55))
		draw_map(state, mouse)
	}
	draw_home_chart_tab(chart_raised, mouse)
}

// draw_home_chart_tab draws the interactive chart tab at Home's bottom-centre slot
// (home_chart_tab_rect). Unlike the encounter's view-only twin it is a steel control whose
// scrim lifts on hover, and its caret points up to raise the chart or down to lower it. A
// shape, not a glyph, wound to survive raylib's clockwise cull.
draw_home_chart_tab :: proc(chart_raised: bool, mouse: rl.Vector2) {
	rect := home_chart_tab_rect()
	hovered := rl.CheckCollisionPointRec(mouse, rect)
	rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, hovered ? 0.75 : 0.55))
	draw_subpanel_border(rect, true)

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
