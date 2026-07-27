package presentation

import "core:fmt"
import "core:os"
import "core:slice"
import cutaway "./cutaway"
import ship "../core/ship"
import sim "../core/sim"
import voyage "../core/voyage"
import rl "vendor:raylib"

// PROTOTYPE — THROWAWAY. Not production. Delete this file when the question below is answered.
//
// The question: what should a Shop stage look like once every encounter screen is a
// variation on the main ship screen rather than a surface of its own? The brief is a
// fully side-on ship, pushed to the left, with the shop's options in the room that makes.
//
// Three variants, switchable with the left/right arrow keys on `--shop-proto`, or shot one
// at a time with `--shot shop-proto-a` (b, c). They disagree about one thing on purpose —
// **what kind of object the stock is** — because that is the decision the screen turns on:
//
//   A  Chandler's manifest — one opaque parchment board, the stock as equal ruled rows.
//   B  Dockside crates     — no panel at all; four pieces of paper floating on the sea.
//   C  The counter         — master/detail: one item is the subject, the rest are a picker.
//
// The ship is the same galleon `draw_ship_cutaway` paints, from the same painters, at a
// yaw of 0 — dead broadside, her cut port side square to the camera — and slid left by
// panning the camera along its own right axis. Each variant also frames her differently
// (distance, eye height, how far left), because "different perspectives of the ship" is
// the other half of the brief and the framing is not separable from the layout.
//
// What is deliberately missing: hit-testing, dragging, buying, the chart tab, hover. This
// answers what the screen looks like, not whether it works.

@(private)
SHOP_PROTO_VARIANTS :: 4

// shop_proto_variant is which variant the interactive run is showing. Prototype-global on
// purpose: the switcher writes it, the draw reads it, and nothing else exists.
@(private)
shop_proto_variant := 0

// shop_proto_selected is variant C's subject — the one item the detail card is about.
// Pinned to 1 ("Chain & Bar Shot") so the long effect string is the one under test.
@(private)
shop_proto_selected := 1

// Shop_Proto_Framing is one variant's camera: an eye, plus how far to slide her left.
// `pan` is in world units along the camera's right axis, so a positive pan walks the eye
// to starboard and the ship drifts to port of frame centre — she never turns.
@(private)
Shop_Proto_Framing :: struct {
	eye: cutaway.Eye,
	pan: f32,
}

// The three framings. Yaw is 0 in all three: that is what "fully side on" means here — the
// camera on the negative-z beam, which is the side her cutaway is opened on, so every berth
// reads square instead of foreshortened. What varies is how close she is and how much sky
// is over her.
//
// The distances are solved, not guessed. At fovy 55.24 in a 1244x700 frame the horizontal
// half-angle is ~42.9 degrees, so the visible width at distance d is ~1.86d; her hull plus
// bowsprit spans ~9 units. A carries the whole ship at ease, B crops her at the chains, C
// stands off far enough that she reads as a ship you are pulling alongside.
@(private)
shop_proto_framings := [SHOP_PROTO_VARIANTS]Shop_Proto_Framing {
	// A — the whole ship, comfortably, in the 64% of frame the board leaves her.
	{eye = {yaw = 0, dist = 8.6, height = 0.15, look = 1.05, fov = 55.24}, pan = 3.30},
	// B — in close. Bow and stern run off the frame and the open holds are the subject.
	{eye = {yaw = 0, dist = 5.9, height = 0.05, look = 0.95, fov = 55.24}, pan = 2.45},
	// C — stood off, low, with sky over her: the read from a boat approaching the port.
	{eye = {yaw = 0, dist = 10.0, height = -0.15, look = 1.35, fov = 55.24}, pan = 3.60},
	// D — A's board and A's distance, swung 32 degrees off the beam. Not a fourth design:
	// the control for what A, B and C all showed, and it comes back negative. Broadside,
	// the berths stop reading as rooms and the whole side is one wall of planking. That is
	// not an inset that wants widening — what makes a room read on the shipped screen is
	// **perspective convergence down her length**, and a side-on camera has none by
	// construction: the length axis is square to the view, so every bulkhead projects as a
	// flat rectangle. 12 degrees did nothing; 32 buys a little shadow under the deck and
	// costs the sails, which go edge-on and collapse to slivers. The three-quarter view's
	// 55.75 is doing real work, and no small swing off the beam approximates it.
	{eye = {yaw = 32, dist = 8.6, height = 0.15, look = 1.05, fov = 55.24}, pan = 3.30},
}

@(private)
shop_proto_names := [SHOP_PROTO_VARIANTS]string {
	"A — Chandler's manifest",
	"B — Dockside crates",
	"C — The counter",
	"D — Manifest, 32 deg off the beam",
}

// shop_proto_view builds the variant's camera. It starts from the shipped galleon view so
// the ship is framed by the same code the ship screen uses, then slides eye and target
// together along the camera's right axis. Moving both is what makes it a pan rather than a
// turn: the view direction is untouched, so a broadside stays a broadside however far she
// slides.
@(private)
shop_proto_view :: proc(framing: Shop_Proto_Framing) -> cutaway.View {
	view := cutaway.galleon_view_from(framing.eye, WINDOW_WIDTH, WINDOW_HEIGHT)
	forward := view.camera.target - view.camera.position
	right := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, view.camera.up))
	offset := right * framing.pan
	view.camera.position += offset
	view.camera.target += offset
	return view
}

// draw_shop_proto_ship paints the ship exactly as draw_ship_cutaway does — same sky, same
// sea, same hull, rooms, ornament, rig and waterline, from the same procs — under a view
// this file chose. What is dropped is everything that answers a cursor: the hover
// highlight and the description card, which belong to refit and not to a shop's backdrop.
@(private)
draw_shop_proto_ship :: proc(state: ^Game_State, view: cutaway.View) {
	horizon := backdrop_floor(cutaway.galleon_horizon_y(view))
	draw_ship_sky(horizon)
	draw_ship_sea(horizon)
	draw_ship_wake(view, horizon)

	rooms, n := cutaway.galleon_rooms(state.player.layout)

	ship_paint_view(view.camera)
	rl.BeginMode3D(view.camera)
	draw_ship_hull()
	for i in 0 ..< n {
		draw_ship_room(rooms[i], ship_room_timber(rooms[i].kind))
	}
	draw_ship_ornament(rooms, n)
	draw_ship_rig()
	rl.EndMode3D()

	draw_ship_waterline(view, horizon)
}

// shop_proto_options flattens the staged shelf to the options actually present, so every
// variant lays out against a count rather than skipping holes in the array.
@(private)
shop_proto_options :: proc(state: ^Game_State) -> (out: [sim.STAGE_OPTION_MAX]sim.Stage_Option, n: int) {
	for slot in state.stage_options {
		if option, filled := slot.?; filled {
			out[n] = option
			n += 1
		}
	}
	return
}

// draw_shop_prototype is the one entry both the interactive run and capture go through, so
// a shot and the window are the same screen. `bar` is the switcher, drawn only for the
// window — a shot wants clean pixels to judge, not the tool that took it.
@(private)
draw_shop_prototype :: proc(state: ^Game_State, variant: int, bar: bool) {
	frame_begin()
	defer frame_end()
	defer free_all(context.temp_allocator)

	draw_shop_proto_ship(state, shop_proto_view(shop_proto_framings[variant]))

	options, n := shop_proto_options(state)
	switch variant {
	case 0:
		draw_shop_proto_manifest(state, options[:], n)
	case 1:
		draw_shop_proto_crates(state, options[:], n)
	case 2:
		draw_shop_proto_counter(state, options[:], n)
	case 3:
		// D reuses A's board on purpose: the only thing that differs is the yaw, so the pair
		// is a controlled test of the camera and not a fourth layout to like or dislike.
		draw_shop_proto_manifest(state, options[:], n)
	}

	if bar {
		draw_shop_proto_switcher(variant)
	}
}

// ---------------------------------------------------------------------------
// A — Chandler's manifest
//
// One opaque parchment board, full-bleed down the right edge, and the stock ruled onto it
// as equal rows. The guide's "parchment is where words live" taken at its word: the shop is
// a written thing, and the ship is what you see past it. Every line is worth the same, so
// the eye reads down rather than landing anywhere.
// ---------------------------------------------------------------------------

@(private)
SHOP_PROTO_A_PANEL :: rl.Rectangle{x = 796, y = 0, width = 448, height = 700}
@(private)
SHOP_PROTO_A_GUTTER :: f32(32) // ink margin inside the board
@(private)
SHOP_PROTO_A_ROW_Y :: f32(148)
@(private)
SHOP_PROTO_A_ROW_H :: f32(96)

@(private)
draw_shop_proto_manifest :: proc(state: ^Game_State, options: []sim.Stage_Option, n: int) {
	panel := SHOP_PROTO_A_PANEL
	rl.DrawRectangleRec(panel, COLOUR_PARCHMENT)
	// The board's left edge, built up out of the warm neutrals so it reads as a thickness
	// rather than a cut: sand for the lit face of the batten, cliff for its shadowed edge.
	rl.DrawRectangleRec({panel.x, panel.y, 4, panel.height}, COLOUR_SAND)
	rl.DrawRectangleRec({panel.x - 3, panel.y, 3, panel.height}, COLOUR_CLIFF)

	x := panel.x + SHOP_PROTO_A_GUTTER
	right := panel.x + panel.width - SHOP_PROTO_A_GUTTER

	rl.DrawTextEx(ui_font_title, "Chandlery", {x, 44}, UI_TITLE_SIZE, 2, COLOUR_INK_PRIMARY)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", ship_stat_line(&state.player)), {x, 92}, UI_BODY_SIZE, 1, COLOUR_INK_MUTED)
	rl.DrawLineEx({x, 124}, {right, 124}, 2, COLOUR_SAND)

	for i in 0 ..< n {
		option := options[i]
		y := SHOP_PROTO_A_ROW_Y + f32(i) * SHOP_PROTO_A_ROW_H
		afford := voyage.voyage_option_can_afford(&state.player, option)
		// Unaffordable drops a whole level of the hierarchy rather than changing hue: the
		// guide keeps coral for danger, and "you cannot pay for this" is not damage.
		name_tone := afford ? COLOUR_INK_PRIMARY : COLOUR_INK_MUTED
		body_tone := afford ? COLOUR_INK_MUTED : rl.Fade(COLOUR_INK_MUTED, 0.55)

		spec, intent := fitting_summary_lines(option.fitting)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", option.fitting.name), {x, y}, UI_BODY_SIZE, 1, name_tone)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", intent), {x, y + 26}, UI_BODY_SIZE, 1, body_tone)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", spec), {x, y + 48}, UI_BODY_SIZE, 1, rl.Fade(COLOUR_INK_MUTED, 0.7))

		if cost, priced := option.cost.?; priced {
			shop_proto_price_right(right, y, cost, name_tone)
		}
		rl.DrawLineEx({x, y + 74}, {right, y + 74}, 1, rl.Fade(COLOUR_SAND, 0.8))
	}

	shop_proto_control({x, 608, 180, 40}, "Leave", COLOUR_SEA_DEEP, rl.Fade(COLOUR_SAND, 0.35))
}

// ---------------------------------------------------------------------------
// B — Dockside crates
//
// No panel. Four pieces of paper on the sea, staggered and shadowed so they read as goods
// laid out rather than as a list rendered. The guide's "let the world read through" pushed
// as far as it goes: the ship's own water runs between the cards, and the heading is cream
// over the sea because there is no parchment under it to be ink on.
// ---------------------------------------------------------------------------

@(private)
SHOP_PROTO_B_CARD_W :: f32(392)
@(private)
SHOP_PROTO_B_CARD_H :: f32(108)
@(private)
SHOP_PROTO_B_PITCH :: f32(126)
@(private)
SHOP_PROTO_B_Y0 :: f32(112)

@(private)
draw_shop_proto_crates :: proc(state: ^Game_State, options: []sim.Stage_Option, n: int) {
	rl.DrawTextEx(ui_font_title, "Market", {816, 44}, UI_TITLE_SIZE, 2, COLOUR_CREAM_BRIGHT)
	rl.DrawTextEx(
		ui_font_body,
		fmt.ctprintf("%s", ship_stat_line(&state.player)),
		{40, 28},
		UI_BODY_SIZE,
		1,
		COLOUR_CREAM_BRIGHT,
	)

	for i in 0 ..< n {
		option := options[i]
		// The stagger is the whole reason these read as objects: four cards on one x are a
		// list however they are bordered.
		x := f32(i % 2 == 0 ? 812 : 832)
		card := rl.Rectangle{x, SHOP_PROTO_B_Y0 + f32(i) * SHOP_PROTO_B_PITCH, SHOP_PROTO_B_CARD_W, SHOP_PROTO_B_CARD_H}
		afford := voyage.voyage_option_can_afford(&state.player, option)

		// A cast shadow, not a glow: the sea is bright, so the only way paper sits above it
		// is to darken what is under the paper.
		rl.DrawRectangleRec({card.x + 5, card.y + 6, card.width, card.height}, rl.Fade(COLOUR_SEA_DEEP, 0.45))
		// Paper is opaque. Dimming an unaffordable card by alpha was the first pass and it
		// let a hull-down island read straight through the card as a stain — translucency
		// costs a panel its own ground. Unaffordable is a duller sheet plus duller ink,
		// shaded down the one swatch rather than mixed toward anything.
		rl.DrawRectangleRec(card, afford ? COLOUR_PARCHMENT : colour_shade(COLOUR_PARCHMENT, 0.90))
		rl.DrawRectangleLinesEx(card, 2, afford ? COLOUR_SEA_DEEP : COLOUR_CLIFF)

		name_tone := afford ? COLOUR_INK_PRIMARY : COLOUR_INK_MUTED
		spec, intent := fitting_summary_lines(option.fitting)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", option.fitting.name), {card.x + 14, card.y + 12}, UI_BODY_SIZE, 1, name_tone)
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", intent), {card.x + 14, card.y + 40}, UI_BODY_SIZE, 1, COLOUR_INK_MUTED)
		rl.DrawTextEx(
			ui_font_body,
			fmt.ctprintf("%s", spec),
			{card.x + 14, card.y + 70},
			UI_BODY_SIZE,
			1,
			rl.Fade(COLOUR_INK_MUTED, 0.7),
		)

		if cost, priced := option.cost.?; priced {
			shop_proto_price_right(card.x + card.width - 14, card.y + 12, cost, name_tone)
		}
	}

	shop_proto_control({816, 628, 180, 40}, "Leave", COLOUR_SEA_DEEP, COLOUR_PARCHMENT)
}

// ---------------------------------------------------------------------------
// C — The counter
//
// Master/detail. One item is the subject, at a size the other two variants never give
// anything, and the rest of the stock is a four-chip picker under it. The disagreement
// with A and B is about rank: here the screen has an answer to "what am I looking at",
// and browsing costs a click.
// ---------------------------------------------------------------------------

@(private)
SHOP_PROTO_C_CARD :: rl.Rectangle{x = 812, y = 72, width = 412, height = 292}
@(private)
SHOP_PROTO_C_CHIP_W :: f32(200)
@(private)
SHOP_PROTO_C_CHIP_H :: f32(84)
@(private)
SHOP_PROTO_C_CHIP_GAP :: f32(12)
@(private)
SHOP_PROTO_C_CHIP_Y :: f32(392)

// shop_proto_c_chip is the picker's grid: two across, two down, under the detail card.
@(private)
shop_proto_c_chip :: proc(i: int) -> rl.Rectangle {
	col := f32(i % 2)
	row := f32(i / 2)
	return {
		SHOP_PROTO_C_CARD.x + col * (SHOP_PROTO_C_CHIP_W + SHOP_PROTO_C_CHIP_GAP),
		SHOP_PROTO_C_CHIP_Y + row * (SHOP_PROTO_C_CHIP_H + SHOP_PROTO_C_CHIP_GAP),
		SHOP_PROTO_C_CHIP_W,
		SHOP_PROTO_C_CHIP_H,
	}
}

@(private)
draw_shop_proto_counter :: proc(state: ^Game_State, options: []sim.Stage_Option, n: int) {
	rl.DrawTextEx(
		ui_font_body,
		fmt.ctprintf("%s", ship_stat_line(&state.player)),
		{40, 28},
		UI_BODY_SIZE,
		1,
		COLOUR_CREAM_BRIGHT,
	)
	rl.DrawTextEx(ui_font_title, "Chandlery", {816, 24}, UI_TITLE_SIZE, 2, COLOUR_CREAM_BRIGHT)

	if n == 0 {
		return
	}
	selected := clamp(shop_proto_selected, 0, n - 1)
	subject := options[selected]
	afford := voyage.voyage_option_can_afford(&state.player, subject)

	card := SHOP_PROTO_C_CARD
	rl.DrawRectangleRec(card, COLOUR_PARCHMENT)
	rl.DrawRectangleLinesEx(card, 2, COLOUR_SEA_DEEP)

	spec, intent := fitting_summary_lines(subject.fitting)
	rl.DrawTextEx(ui_font_title, fmt.ctprintf("%s", subject.fitting.name), {card.x + 20, card.y + 20}, UI_TITLE_SIZE, 1, COLOUR_INK_PRIMARY)
	rl.DrawLineEx({card.x + 20, card.y + 68}, {card.x + card.width - 20, card.y + 68}, 2, COLOUR_SAND)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", intent), {card.x + 20, card.y + 88}, UI_BODY_SIZE, 1, COLOUR_INK_PRIMARY)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", spec), {card.x + 20, card.y + 114}, UI_BODY_SIZE, 1, COLOUR_INK_MUTED)

	if cost, priced := subject.cost.?; priced {
		// The subject's price is the one number the screen is built around, so it is given
		// the detail card's own line rather than being tucked against an edge.
		shop_proto_crate({card.x + 20, card.y + 156}, COLOUR_INK_PRIMARY)
		rl.DrawTextEx(
			ui_font_title,
			fmt.ctprintf("%d", cost),
			{card.x + 46, card.y + 148},
			UI_TITLE_SIZE,
			1,
			afford ? COLOUR_INK_PRIMARY : COLOUR_INK_MUTED,
		)
	}

	label: cstring = afford ? "Take aboard" : "Not enough cargo"
	shop_proto_control(
		{card.x + 20, card.y + card.height - 58, 220, 38},
		label,
		afford ? COLOUR_SEA_DEEP : COLOUR_INK_MUTED,
		rl.Fade(COLOUR_SAND, 0.35),
	)

	for i in 0 ..< n {
		option := options[i]
		chip := shop_proto_c_chip(i)
		lit := i == selected
		// Opaque for the same reason B's cards are: an unselected chip at low alpha showed
		// the island behind it and read as a smear, not as a quieter chip.
		rl.DrawRectangleRec(chip, lit ? COLOUR_PARCHMENT : colour_shade(COLOUR_PARCHMENT, 0.90))
		rl.DrawRectangleLinesEx(chip, 2, lit ? COLOUR_SEA_DEEP : COLOUR_CLIFF)
		if lit {
			draw_caret({chip.x + 14, chip.y + 22}, COLOUR_SEA_DEEP)
		}
		tone := i == selected ? COLOUR_INK_PRIMARY : COLOUR_INK_MUTED
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", option.fitting.name), {chip.x + 26, chip.y + 14}, UI_BODY_SIZE, 1, tone)
		if cost, priced := option.cost.?; priced {
			shop_proto_crate({chip.x + 26, chip.y + 48}, tone)
			rl.DrawTextEx(ui_font_body, fmt.ctprintf("%d", cost), {chip.x + 52, chip.y + 44}, UI_BODY_SIZE, 1, tone)
		}
	}

	shop_proto_control({SHOP_PROTO_C_CARD.x, 600, 180, 38}, "Leave", COLOUR_SEA_DEEP, COLOUR_PARCHMENT)
}

// ---------------------------------------------------------------------------
// Shared marks
// ---------------------------------------------------------------------------

// shop_proto_crate is the cargo mark: a crate, drawn as shapes because the guide will not
// let a glyph above Latin-1 be depended on. `pos` is its top-left; it occupies 14x14.
@(private)
shop_proto_crate :: proc(pos: rl.Vector2, tone: rl.Color) {
	S :: f32(14)
	rl.DrawRectangleLinesEx({pos.x, pos.y, S, S}, 1, tone)
	rl.DrawLineEx({pos.x + S / 2, pos.y}, {pos.x + S / 2, pos.y + S}, 1, tone)
	rl.DrawLineEx({pos.x, pos.y + S / 2}, {pos.x + S, pos.y + S / 2}, 1, tone)
}

// shop_proto_price_right lays a crate-and-number price flush to `right`, measured rather
// than guessed so a three-digit price does not walk off the edge a two-digit one fitted.
@(private)
shop_proto_price_right :: proc(right, y: f32, cost: int, tone: rl.Color) {
	text := fmt.ctprintf("%d", cost)
	w := rl.MeasureTextEx(ui_font_body, text, UI_BODY_SIZE, 1).x
	rl.DrawTextEx(ui_font_body, text, {right - w, y}, UI_BODY_SIZE, 1, tone)
	shop_proto_crate({right - w - 20, y + 1}, tone)
}

// shop_proto_control is every control on every variant: a 2px border in the tone that
// states its role, a translucent ground, and a label in the same tone. No fill marks the
// default action — the guide retired that accent and this prototype does not reopen it.
@(private)
shop_proto_control :: proc(rect: rl.Rectangle, label: cstring, tone: rl.Color, ground: rl.Color) {
	rl.DrawRectangleRec(rect, ground)
	rl.DrawRectangleLinesEx(rect, 2, tone)
	size := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1)
	rl.DrawTextEx(
		ui_font_body,
		label,
		{rect.x + (rect.width - size.x) / 2, rect.y + (rect.height - size.y) / 2},
		UI_BODY_SIZE,
		1,
		tone,
	)
}

// draw_shop_proto_switcher is the prototype's own furniture and is drawn to look like it:
// the retired navy ramp, hard edges, nothing off the bright roster. It must never be
// mistaken for part of the design being judged.
@(private)
draw_shop_proto_switcher :: proc(variant: int) {
	bar := rl.Rectangle{(WINDOW_WIDTH - 420) / 2, 652, 420, 34}
	rl.DrawRectangleRec(bar, rl.Fade(COLOUR_VIGNETTE, 0.92))
	rl.DrawRectangleLinesEx(bar, 1, COLOUR_STEEL)

	mid := bar.y + bar.height / 2
	// Left arrow: the caret's mirror. Vertex order is raylib's counter-clockwise
	// requirement — reverse it and the triangle is culled to nothing.
	rl.DrawTriangle({bar.x + 22, mid - 6}, {bar.x + 12, mid}, {bar.x + 22, mid + 6}, COLOUR_STEEL)
	draw_caret({bar.x + bar.width - 17, mid}, COLOUR_STEEL)

	label := fmt.ctprintf("%s", shop_proto_names[variant])
	size := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1)
	rl.DrawTextEx(ui_font_body, label, {bar.x + (bar.width - size.x) / 2, mid - size.y / 2}, UI_BODY_SIZE, 1, COLOUR_CREAM)
}

// ---------------------------------------------------------------------------
// Staging and the interactive run
// ---------------------------------------------------------------------------

// shop_proto_stage builds the world all three variants draw from: the real starting ship
// and the same four-item shelf capture's own `shop` shot stages, so a variant is judged
// against the stock the shipped screen is judged against.
@(private)
shop_proto_stage :: proc(state: ^Game_State, player: ^ship.Ship) {
	player^ = ship.ship_starting_ship()
	state.player = player^
	state.stage_progress = sim.Event_Stage_Entered{kind = .Shop, index = 0, count = 1}
	names := [?]string{"Long Nines", "Chain & Bar Shot", "Titan's Heart", "Outriggers"}
	costs := [?]int{18, 34, 120, 26} // the 120 sits above the starting hold, so it dims
	for name, i in names {
		if item, ok := ship.ship_item_by_name(name); ok {
			state.stage_options[i] = sim.Stage_Option{fitting = item.fitting, cost = costs[i]}
		}
	}
}

// The capture entries. Appended to the end of `capture_shots` so no shipped shot renumbers;
// they add three names to the manifest and move nothing. Each shoots one variant with the
// switcher off, which is the frame worth judging.
@(private)
capture_stage_shop_proto :: proc(scene: ^Capture_Scene) {
	shop_proto_stage(&scene.game, &scene.player)
}

@(private)
capture_frame_shop_proto_a :: proc(scene: ^Capture_Scene) -> bool {
	draw_shop_prototype(&scene.game, 0, false)
	return true
}

@(private)
capture_frame_shop_proto_b :: proc(scene: ^Capture_Scene) -> bool {
	draw_shop_prototype(&scene.game, 1, false)
	return true
}

@(private)
capture_frame_shop_proto_c :: proc(scene: ^Capture_Scene) -> bool {
	draw_shop_prototype(&scene.game, 2, false)
	return true
}

@(private)
capture_frame_shop_proto_d :: proc(scene: ^Capture_Scene) -> bool {
	draw_shop_prototype(&scene.game, 3, false)
	return true
}

// shop_proto_requested reports whether the process was started as a prototype run.
shop_proto_requested :: proc() -> bool {
	return slice.contains(os.args[1:], "--shop-proto")
}

// shop_proto_main is the interactive run: one window, the three variants under the arrow
// keys, and up/down moving variant C's subject. No Sim — nothing here needs one.
shop_proto_main :: proc() {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Fantasy Ship Game — shop prototype")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL)

	ui_fonts_load()
	defer ui_fonts_unload()
	art_load()
	defer art_unload()

	state: Game_State
	player: ship.Ship
	shop_proto_stage(&state, &player)

	for !rl.WindowShouldClose() {
		if rl.IsKeyPressed(.RIGHT) {
			shop_proto_variant = (shop_proto_variant + 1) % SHOP_PROTO_VARIANTS
		}
		if rl.IsKeyPressed(.LEFT) {
			shop_proto_variant = (shop_proto_variant + SHOP_PROTO_VARIANTS - 1) % SHOP_PROTO_VARIANTS
		}
		if rl.IsKeyPressed(.DOWN) {
			shop_proto_selected = (shop_proto_selected + 1) % sim.STAGE_OPTION_MAX
		}
		if rl.IsKeyPressed(.UP) {
			shop_proto_selected = (shop_proto_selected + sim.STAGE_OPTION_MAX - 1) % sim.STAGE_OPTION_MAX
		}
		draw_shop_prototype(&state, shop_proto_variant, true)
	}

	shop_proto_variant = 0
	shop_proto_selected = 1
}
