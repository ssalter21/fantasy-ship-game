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
// variation on the main ship screen rather than a surface of its own?
//
// Settled in the first two rounds and no longer under test:
//   - the ship is **dead broadside**, yaw 0, so every bulkhead projects as a rectangle and
//     the berths read as squared-off compartments rather than as receding chambers;
//   - she is **panned left**, by sliding the camera along its own right axis, so she never
//     turns to make the room;
//   - the stock is **paper on the sea** — parchment, opaque, shadowed — in a single
//     **aligned** column with one left edge, one width and one rhythm.
//
// Under test here: four framings of that screen. Three vary only the camera, so the
// comparison between them is clean; the fourth varies the column instead.
//
//   1  Sheer draught — orthographic. The only one where the walls are square *exactly*.
//   2  One sheet     — the column's four cards fused into a single ruled sheet.
//   3  Alongside     — in close and low, the berth row at eye level.
//   4  Overlap       — no gutter: her stern runs in under the paper.
//
// A note on "square", because it decides whether 1 is the answer or a curiosity: yaw 0
// makes the ship broadside, but a *perspective* camera still converges toward its own
// centre, so a ship panned well off-axis shows a little of each berth's side wall — more
// the further from frame centre it sits. Orthographic has no convergence anywhere by
// construction. 1 is therefore the only framing where every wall is exactly square; 2, 3
// and 4 are square to the eye with a residue that grows with the pan.
//
// The ship is painted by the shipped painters — same sky, sea, hull, rooms, ornament, rig
// and waterline — under a camera this file reframed, so it is the real screen and not a
// mock of it. What is deliberately missing: hit-testing, dragging, buying, hover.

@(private)
SHOP_PROTO_VARIANTS :: 4

// shop_proto_variant is which framing the interactive run is showing. Prototype-global on
// purpose: the switcher writes it, the draw reads it, and nothing else exists.
@(private)
shop_proto_variant := 0

// Shop_Proto_Framing is one variant's camera. `pan` is in world units along the camera's
// right axis, so a positive pan walks the eye to starboard and the ship drifts to port of
// frame centre without turning. `ortho` is zero for a perspective camera and otherwise the
// **vertical extent of the view volume in world units** — raylib reads Camera3D.fovy that
// way under an orthographic projection, so one field says both "orthographic" and "how
// much of the world is in shot".
@(private)
Shop_Proto_Framing :: struct {
	eye:   cutaway.Eye,
	pan:   f32,
	ortho: f32,
}

// Every framing is yaw 0 — dead broadside, on the negative-z beam, which is the side her
// cutaway is opened on. What varies is the projection, how close she is, and how far left.
@(private)
shop_proto_framings := [SHOP_PROTO_VARIANTS]Shop_Proto_Framing {
	// 1 — Sheer draught. Orthographic: no convergence anywhere, so every bulkhead is a true
	// rectangle however far off-axis she sits. Under ortho `dist` no longer sets her size —
	// `ortho` does — and only has to keep her in front of the near plane. 8.5 units of
	// height is 15.1 of width at this aspect, which leaves her about 60% of the frame.
	// `height` must equal `look`, so the view axis is horizontal — see shop_proto_horizon.
	{eye = {yaw = 0, dist = 9.0, height = 1.05, look = 1.05, fov = 55.24}, pan = 3.00, ortho = 8.5},
	// 2 — One sheet. Her whole length, easy in frame, against the fused column.
	{eye = {yaw = 0, dist = 8.6, height = 0.15, look = 1.05, fov = 55.24}, pan = 3.30},
	// 3 — Alongside. In close and under her rail: bow and stern run off the frame and the
	// row of open berths is at eye level, which is the closest this screen gets to being
	// about the ship's insides rather than about her.
	{eye = {yaw = 0, dist = 5.4, height = -0.10, look = 0.75, fov = 55.24}, pan = 2.30},
	// 4 — Overlap. Barely panned, so there is no clean gutter between ship and shop: her
	// stern runs in under the paper and the two halves read as one picture. The cards keep
	// their cast shadow, which is what stops the overlap reading as a collision.
	{eye = {yaw = 0, dist = 6.6, height = 0.05, look = 1.00, fov = 55.24}, pan = 1.55},
}

@(private)
shop_proto_names := [SHOP_PROTO_VARIANTS]string {
	"1 — Sheer draught (orthographic)",
	"2 — One sheet",
	"3 — Alongside",
	"4 — Overlap",
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
	if framing.ortho > 0 {
		view.camera.projection = .ORTHOGRAPHIC
		view.camera.fovy = framing.ortho
	}
	return view
}

// draw_shop_proto_ship paints the ship exactly as draw_ship_cutaway does — same sky, same
// sea, same hull, rooms, ornament, rig and waterline, from the same procs — under a view
// this file chose. What is dropped is everything that answers a cursor: the hover
// highlight and the description card, which belong to refit and not to a shop's backdrop.
// shop_proto_horizon is where the sea's edge crosses the screen for this framing.
//
// Under perspective that is the water plane's vanishing point, which galleon_horizon_y
// finds by projecting far down the view. **Under an orthographic projection there is no
// vanishing point**: parallel rays each meet the water plane exactly once, so a plane that
// is even slightly oblique to the view axis projects over the *entire* frame, and asking
// for its horizon is asking a question with no answer. That is not a raylib bug — it is
// what removing the perspective divide means, and the first pass of this variant came back
// with a flat blue screen and no sea in it at all.
//
// An elevation's view axis is horizontal by definition, which is the case that has an
// answer: with `height == look` the water plane is exactly edge-on and projects to a single
// line, world y maps linearly to screen y, and the waterline is wherever y = 0 lands.
@(private)
shop_proto_horizon :: proc(view: cutaway.View, framing: Shop_Proto_Framing) -> f32 {
	if framing.ortho <= 0 {
		return backdrop_floor(cutaway.galleon_horizon_y(view))
	}
	assert(framing.eye.height == framing.eye.look, "an orthographic framing needs a horizontal view axis")
	top := framing.eye.look + framing.ortho / 2 // world y at screen y = 0
	return backdrop_floor(top / framing.ortho * WINDOW_HEIGHT)
}

@(private)
draw_shop_proto_ship :: proc(state: ^Game_State, view: cutaway.View, framing: Shop_Proto_Framing) {
	horizon := shop_proto_horizon(view, framing)
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

	framing := shop_proto_framings[variant]
	draw_shop_proto_ship(state, shop_proto_view(framing), framing)

	options, n := shop_proto_options(state)
	// Three framings share the column so the camera is the only thing that differs between
	// them; only 2 swaps the column out, which is the one layout question still open.
	if variant == 1 {
		draw_shop_proto_sheet(state, options[:], n)
	} else {
		draw_shop_proto_column(state, options[:], n)
	}

	if bar {
		draw_shop_proto_switcher(variant)
	}
}

// ---------------------------------------------------------------------------
// The column — four discrete cards, aligned
//
// Paper on the sea with no panel behind it, so the ship's own water runs between the
// cards and the screen is the ship screen with paper on it rather than the ship screen
// with a wall on it. Every edge lines up: card left, card right, the heading above them
// and the control below. Four prices scan down one straight line.
// ---------------------------------------------------------------------------

@(private)
SHOP_PROTO_COL_X :: f32(820)
@(private)
SHOP_PROTO_COL_W :: f32(392)
@(private)
SHOP_PROTO_COL_CARD_H :: f32(108)
@(private)
SHOP_PROTO_COL_PITCH :: f32(120)
@(private)
SHOP_PROTO_COL_Y0 :: f32(104)

@(private)
draw_shop_proto_column :: proc(state: ^Game_State, options: []sim.Stage_Option, n: int) {
	draw_shop_proto_stat_line(state)
	// The heading starts on the column's own left edge rather than being centred over it:
	// a centred title above a left-aligned stack has nothing for the eye to run down.
	rl.DrawTextEx(ui_font_title, "Market", {SHOP_PROTO_COL_X, 44}, UI_TITLE_SIZE, 2, COLOUR_CREAM_BRIGHT)

	for i in 0 ..< n {
		option := options[i]
		card := rl.Rectangle {
			SHOP_PROTO_COL_X,
			SHOP_PROTO_COL_Y0 + f32(i) * SHOP_PROTO_COL_PITCH,
			SHOP_PROTO_COL_W,
			SHOP_PROTO_COL_CARD_H,
		}
		afford := voyage.voyage_option_can_afford(&state.player, option)

		// A cast shadow, not a glow: the sea is bright, so the only way paper sits above it
		// is to darken what is under the paper. It is also what keeps variant 4's overlap
		// reading as depth rather than as a collision.
		rl.DrawRectangleRec({card.x + 5, card.y + 6, card.width, card.height}, rl.Fade(COLOUR_SEA_DEEP, 0.45))
		// Paper is opaque. Dimming an unaffordable card by alpha was an early pass and it
		// let a hull-down island read straight through the card as a stain — translucency
		// costs a panel its own ground. Unaffordable is a duller sheet plus duller ink,
		// shaded down the one swatch rather than mixed toward anything.
		rl.DrawRectangleRec(card, afford ? COLOUR_PARCHMENT : colour_shade(COLOUR_PARCHMENT, 0.90))
		rl.DrawRectangleLinesEx(card, 2, afford ? COLOUR_SEA_DEEP : COLOUR_CLIFF)
		draw_shop_proto_entry(card, option, afford)
	}

	// The control takes the column's full width so the block closes on the same two edges
	// it opened on. No shadow — it is not another piece of stock.
	shop_proto_control(
		{SHOP_PROTO_COL_X, SHOP_PROTO_COL_Y0 + f32(n) * SHOP_PROTO_COL_PITCH + 16, SHOP_PROTO_COL_W, 40},
		"Leave",
		COLOUR_SEA_DEEP,
		COLOUR_PARCHMENT,
	)
}

// ---------------------------------------------------------------------------
// 2 — One sheet
//
// The same four entries on one piece of paper instead of four, ruled apart rather than
// bordered apart. Alignment taken as far as it goes: a single outline, a single ground,
// and the heading and the control brought inside it, so the shop is one object on the sea
// rather than a stack of them. What it gives up is the read of stock as separate goods —
// four things you could pick up become four lines you read.
// ---------------------------------------------------------------------------

@(private)
SHOP_PROTO_SHEET :: rl.Rectangle{x = 812, y = 76, width = 400, height = 548}
@(private)
SHOP_PROTO_SHEET_PAD :: f32(18)
@(private)
SHOP_PROTO_SHEET_ROW_Y :: f32(156)
@(private)
SHOP_PROTO_SHEET_PITCH :: f32(104)

@(private)
draw_shop_proto_sheet :: proc(state: ^Game_State, options: []sim.Stage_Option, n: int) {
	draw_shop_proto_stat_line(state)

	sheet := SHOP_PROTO_SHEET
	rl.DrawRectangleRec({sheet.x + 5, sheet.y + 6, sheet.width, sheet.height}, rl.Fade(COLOUR_SEA_DEEP, 0.45))
	rl.DrawRectangleRec(sheet, COLOUR_PARCHMENT)
	rl.DrawRectangleLinesEx(sheet, 2, COLOUR_SEA_DEEP)

	x := sheet.x + SHOP_PROTO_SHEET_PAD
	right := sheet.x + sheet.width - SHOP_PROTO_SHEET_PAD

	// The heading is ink here, not cream: it has parchment under it now, and cream is the
	// roster's tone for a heading placed over the sea.
	rl.DrawTextEx(ui_font_title, "Market", {x, sheet.y + 16}, UI_TITLE_SIZE, 2, COLOUR_INK_PRIMARY)
	rl.DrawLineEx({x, sheet.y + 68}, {right, sheet.y + 68}, 2, COLOUR_SAND)

	for i in 0 ..< n {
		option := options[i]
		y := SHOP_PROTO_SHEET_ROW_Y + f32(i) * SHOP_PROTO_SHEET_PITCH
		afford := voyage.voyage_option_can_afford(&state.player, option)
		draw_shop_proto_entry({x, y - 12, right - x, SHOP_PROTO_SHEET_PITCH - 12}, option, afford)
		// Rules go *between* entries, never after the last one: a trailing rule reads as a
		// fifth row that failed to draw.
		if i < n - 1 {
			rl.DrawLineEx({x, y + 80}, {right, y + 80}, 1, rl.Fade(COLOUR_SAND, 0.8))
		}
	}

	shop_proto_control(
		{x, sheet.y + sheet.height - 58, right - x, 38},
		"Leave",
		COLOUR_SEA_DEEP,
		rl.Fade(COLOUR_SAND, 0.35),
	)
}

// ---------------------------------------------------------------------------
// Shared marks
// ---------------------------------------------------------------------------

// draw_shop_proto_entry lays one item out inside `rect`, which is a card in the column and
// a ruled band on the sheet. One proc so the two columns cannot drift apart in wording,
// spacing or tone while the framings around them are being judged.
@(private)
draw_shop_proto_entry :: proc(rect: rl.Rectangle, option: sim.Stage_Option, afford: bool) {
	name_tone := afford ? COLOUR_INK_PRIMARY : COLOUR_INK_MUTED
	spec, intent := fitting_summary_lines(option.fitting)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", option.fitting.name), {rect.x + 14, rect.y + 12}, UI_BODY_SIZE, 1, name_tone)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", intent), {rect.x + 14, rect.y + 40}, UI_BODY_SIZE, 1, COLOUR_INK_MUTED)
	rl.DrawTextEx(
		ui_font_body,
		fmt.ctprintf("%s", spec),
		{rect.x + 14, rect.y + 70},
		UI_BODY_SIZE,
		1,
		rl.Fade(COLOUR_INK_MUTED, 0.7),
	)
	if cost, priced := option.cost.?; priced {
		shop_proto_price_right(rect.x + rect.width - 14, rect.y + 12, cost, name_tone)
	}
}

// draw_shop_proto_stat_line puts the ship's readout over the sea, top left, away from the
// shop: what you have is a fact about the ship, not a line of the market's.
@(private)
draw_shop_proto_stat_line :: proc(state: ^Game_State) {
	rl.DrawTextEx(
		ui_font_body,
		fmt.ctprintf("%s", ship_stat_line(&state.player)),
		{40, 28},
		UI_BODY_SIZE,
		1,
		COLOUR_CREAM_BRIGHT,
	)
}

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

// shop_proto_stage builds the world every variant draws from: the real starting ship and
// the same four-item shelf capture's own `shop` shot stages, so a variant is judged
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

// The capture entries. Appended to the end of `capture_shots` so no shipped shot
// renumbers; they add four names to the manifest and move nothing.
@(private)
capture_stage_shop_proto :: proc(scene: ^Capture_Scene) {
	shop_proto_stage(&scene.game, &scene.player)
}

@(private)
capture_frame_shop_proto_1 :: proc(scene: ^Capture_Scene) -> bool {
	draw_shop_prototype(&scene.game, 0, false)
	return true
}

@(private)
capture_frame_shop_proto_2 :: proc(scene: ^Capture_Scene) -> bool {
	draw_shop_prototype(&scene.game, 1, false)
	return true
}

@(private)
capture_frame_shop_proto_3 :: proc(scene: ^Capture_Scene) -> bool {
	draw_shop_prototype(&scene.game, 2, false)
	return true
}

@(private)
capture_frame_shop_proto_4 :: proc(scene: ^Capture_Scene) -> bool {
	draw_shop_prototype(&scene.game, 3, false)
	return true
}

// shop_proto_requested reports whether the process was started as a prototype run.
shop_proto_requested :: proc() -> bool {
	return slice.contains(os.args[1:], "--shop-proto")
}

// shop_proto_main is the interactive run: one window, the four framings under the arrow
// keys. No Sim — nothing here needs one.
//
// It boots borderless fullscreen the same way `run` does, because a variant judged in a
// 1244x700 window is not the variant the player sees: the session composes into a render
// texture and blits it, and that path is the only place translucency reads true (the
// style guide's "a render texture loses alpha"). Every card shadow, faded rule and dimmed
// ink on these screens is translucent, so this is the run that tells the truth about them
// — and the one `--shot` structurally cannot photograph.
shop_proto_main :: proc() {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Fantasy Ship Game — shop prototype")
	defer rl.CloseWindow()
	fullscreen_init()
	defer fullscreen_shutdown()
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
		// F11 drops back to a window and returns. fullscreen_active stays true either way:
		// frame_end letterboxes against whatever GetScreenWidth reports, so the texture path
		// — and with it the honest alpha — is in play at both sizes.
		if rl.IsKeyPressed(.F11) {
			rl.ToggleBorderlessWindowed()
		}
		draw_shop_prototype(&state, shop_proto_variant, true)
	}

	shop_proto_variant = 0
}
