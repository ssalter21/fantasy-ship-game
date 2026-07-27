package presentation

import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import cutaway "./cutaway"
import ship "../core/ship"
import sim "../core/sim"
import voyage "../core/voyage"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// PROTOTYPE — THROWAWAY. Not production. Delete this file when the question below is answered.
//
// Settled over three rounds and no longer under test — the Shop screen is the ship screen
// reframed: an **orthographic** broadside elevation, panned left, with the stock as opaque
// parchment in one aligned column. Orthographic is the point of it, not a detail: it is the
// only projection with no convergence anywhere, so every bulkhead is a true rectangle
// however far off-axis she sits.
//
// Under test here: **the move**. Entering a Shop should not cut to that framing, it should
// travel to it from the ship screen the player is already looking at. Space replays it, the
// arrow keys scrub it by hand, and it plays once on launch.
//
// The hard part is that the two ends do not share a projection. The ship screen is a
// perspective camera at three-quarters; the Shop is an orthographic elevation on the beam.
// Lerping the eye and switching projection at the end pops: her square sails snap from
// visible to gone and every bulkhead straightens in one frame. So the **projection matrix
// itself is blended** — see shop_proto_projection. That is what makes the sails foreshorten
// away smoothly and the hull straighten as she swings, which is the whole effect.
//
// The ship is painted by the shipped painters — same sky, sea, hull, rooms, ornament, rig
// and waterline — so this is the real screen reframed and not a mock of it. What is
// deliberately missing: hit-testing, dragging, buying, hover.

@(private)
SHOP_PROTO_MOVE_SECONDS :: f32(0.9)

// shop_proto_t is where the move has got to: 0 is the ship screen, 1 is the Shop.
// Prototype-global on purpose — the loop writes it, the draw reads it, nothing else exists.
@(private)
shop_proto_t := f32(0)
@(private)
shop_proto_playing := true

// Shop_Proto_Framing is one end of the move. `pan` is in world units along the camera's
// right axis, so a positive pan walks the eye to starboard and the ship drifts to port of
// frame centre without turning. `ortho` is zero for a perspective camera and otherwise the
// **vertical extent of the view volume in world units** — raylib reads Camera3D.fovy that
// way under an orthographic projection.
@(private)
Shop_Proto_Framing :: struct {
	eye:   cutaway.Eye,
	pan:   f32,
	ortho: f32,
}

// Moored is the shipped ship screen, unmodified: the same eye draw_ship_cutaway uses, so
// the move starts from exactly the frame the player was already looking at.
@(private)
SHOP_PROTO_MOORED :: Shop_Proto_Framing{eye = cutaway.GALLEON_EYE, pan = 0, ortho = 0}

// Alongside is the Shop. Dead broadside on the negative-z beam — the side her cutaway is
// opened on — orthographic, and panned left to clear the column. Under ortho `dist` no
// longer sets her size (`ortho` does) and only has to keep her in front of the near plane;
// `height` must equal `look`, so the view axis is horizontal — see shop_proto_horizon.
@(private)
SHOP_PROTO_ALONGSIDE :: Shop_Proto_Framing {
	eye   = {yaw = 0, dist = 9.0, height = 1.05, look = 1.05, fov = 55.24},
	pan   = 3.00,
	ortho = 8.5,
}

// shop_proto_ease is smootherstep — zero first *and* second derivative at both ends. A
// camera that leaves or arrives with non-zero acceleration reads as a jolt on a move this
// short, and plain smoothstep still kicks at the ends.
@(private)
shop_proto_ease :: proc(t: f32) -> f32 {
	x := clamp(t, 0, 1)
	return x * x * x * (x * (x * 6 - 15) + 10)
}

@(private)
shop_proto_mix :: proc(a, b, k: f32) -> f32 {
	return a + (b - a) * k
}

// shop_proto_framing_at is the camera partway through the move. Everything the eye carries
// interpolates; the projection does not, and is handled separately.
@(private)
shop_proto_framing_at :: proc(k: f32) -> Shop_Proto_Framing {
	a := SHOP_PROTO_MOORED
	b := SHOP_PROTO_ALONGSIDE
	return Shop_Proto_Framing {
		eye = {
			yaw = shop_proto_mix(a.eye.yaw, b.eye.yaw, k),
			dist = shop_proto_mix(a.eye.dist, b.eye.dist, k),
			height = shop_proto_mix(a.eye.height, b.eye.height, k),
			look = shop_proto_mix(a.eye.look, b.eye.look, k),
			fov = a.eye.fov,
		},
		pan = shop_proto_mix(a.pan, b.pan, k),
		ortho = b.ortho,
	}
}

// shop_proto_view builds the camera. It starts from the shipped galleon view so the ship is
// framed by the same code the ship screen uses, then slides eye and target together along
// the camera's right axis. Moving both is what makes it a pan rather than a turn: the view
// direction is untouched, so a broadside stays a broadside however far she slides.
//
// `orthographic` is passed rather than read off the framing because mid-move the camera
// stays perspective and the *matrix* carries the blend; only the resting Shop is a genuine
// orthographic camera.
@(private)
shop_proto_view :: proc(framing: Shop_Proto_Framing, orthographic: bool) -> cutaway.View {
	view := cutaway.galleon_view_from(framing.eye, WINDOW_WIDTH, WINDOW_HEIGHT)
	forward := view.camera.target - view.camera.position
	right := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, view.camera.up))
	offset := right * framing.pan
	view.camera.position += offset
	view.camera.target += offset
	if orthographic {
		view.camera.projection = .ORTHOGRAPHIC
		view.camera.fovy = framing.ortho
	}
	return view
}

// shop_proto_projection is the blended projection, and the reason the move reads as one
// continuous thing rather than a pan followed by a snap.
//
// A perspective matrix divides by -z (its w row is `0 0 -1 0`); an orthographic one does
// not (`0 0 0 1`). Blending the two component-wise gives a valid projective transform whose
// convergence falls off smoothly with `k` — so as the camera swings to the beam, her
// bulkheads straighten and her square sails foreshorten away instead of vanishing in one
// frame. Both ends are exact: k=0 is the shipped perspective, k=1 the Shop's orthographic.
@(private)
shop_proto_projection :: proc(k: f32) -> rl.Matrix {
	aspect := f32(WINDOW_WIDTH) / f32(WINDOW_HEIGHT)
	near :: f32(rlgl.CULL_DISTANCE_NEAR)
	far :: f32(rlgl.CULL_DISTANCE_FAR)

	persp := rl.MatrixPerspective(math.to_radians(SHOP_PROTO_MOORED.eye.fov), aspect, near, far)
	top := SHOP_PROTO_ALONGSIDE.ortho / 2
	ortho := rl.MatrixOrtho(-top * aspect, top * aspect, -top, top, near, far)

	out: rl.Matrix
	for r in 0 ..< 4 {
		for c in 0 ..< 4 {
			out[r, c] = persp[r, c] * (1 - k) + ortho[r, c] * k
		}
	}
	return out
}

// shop_proto_horizon is where the sea's edge crosses the screen.
//
// Under perspective that is the water plane's vanishing point, which galleon_horizon_y finds
// by projecting far down the view. **Under an orthographic projection there is no vanishing
// point**: parallel rays each meet the water plane exactly once, so a plane even slightly
// oblique to the view axis projects over the *entire* frame, and asking for its horizon is a
// question with no answer. That is not a raylib bug — it is what removing the perspective
// divide means, and the first pass of this framing came back a flat blue screen with no sea
// in it at all. An elevation's view axis is horizontal by definition, which *is* the case
// that has an answer: with `height == look` the plane is exactly edge-on, world y maps
// linearly to screen y, and the waterline is wherever y = 0 lands.
//
// Mid-move the two are blended in screen space rather than derived from the blended matrix.
// It is an approximation, but a monotone one that is exact at both ends, and the horizon
// only has to travel plausibly for the ~0.9s the camera is moving.
@(private)
shop_proto_horizon :: proc(k: f32) -> f32 {
	moored := shop_proto_view(SHOP_PROTO_MOORED, false)
	from := cutaway.galleon_horizon_y(moored)
	assert(
		SHOP_PROTO_ALONGSIDE.eye.height == SHOP_PROTO_ALONGSIDE.eye.look,
		"an orthographic framing needs a horizontal view axis",
	)
	top := SHOP_PROTO_ALONGSIDE.eye.look + SHOP_PROTO_ALONGSIDE.ortho / 2 // world y at screen y = 0
	to := top / SHOP_PROTO_ALONGSIDE.ortho * WINDOW_HEIGHT
	return backdrop_floor(shop_proto_mix(from, to, k))
}

// draw_shop_proto_ship paints the ship as draw_ship_cutaway does — same sky, same sea, same
// hull, rooms, ornament, rig and waterline, from the same procs — under this file's camera.
// Dropped is everything that answers a cursor: the hover highlight and the description card
// belong to refit, not to a shop's backdrop.
@(private)
draw_shop_proto_ship :: proc(state: ^Game_State, k: f32) {
	resting := k >= 1
	view := shop_proto_view(shop_proto_framing_at(k), resting)
	horizon := shop_proto_horizon(k)

	draw_ship_sky(horizon)
	draw_ship_sea(horizon)

	// The wake and the waterline foam are the one thing this prototype drops mid-move, and
	// the reason is worth keeping: both project world points through `view.camera`, which
	// knows nothing about the blended matrix the hull is actually being drawn with, so they
	// would sit detached from her planking by tens of pixels at the middle of the swing.
	// Drawing them only at rest is a prototype shortcut — the real fix is to project them
	// through the same matrix, which means a projection seam in the cutaway package that is
	// not worth opening to answer whether the move feels right.
	if resting {
		draw_ship_wake(view, horizon)
	}

	rooms, n := cutaway.galleon_rooms(state.player.layout)

	ship_paint_view(view.camera)
	rl.BeginMode3D(view.camera)
	// Overriding after BeginMode3D is deliberate: BeginMode3D pushes the projection stack and
	// sets a matrix from the camera, and this replaces the one rlgl will actually draw the
	// queued batch with. EndMode3D pops the stack, so nothing leaks past this block.
	if !resting {
		rlgl.SetMatrixProjection(shop_proto_projection(k))
	}
	draw_ship_hull()
	for i in 0 ..< n {
		draw_ship_room(rooms[i], ship_room_timber(rooms[i].kind))
	}
	draw_ship_ornament(rooms, n)
	draw_ship_rig()
	rl.EndMode3D()

	if resting {
		draw_ship_waterline(view, horizon)
	}
}

// shop_proto_options flattens the staged shelf to the options actually present, so the
// column lays out against a count rather than skipping holes in the array.
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
draw_shop_prototype :: proc(state: ^Game_State, t: f32, bar: bool) {
	frame_begin()
	defer frame_end()
	defer free_all(context.temp_allocator)

	k := shop_proto_ease(t)
	draw_shop_proto_ship(state, k)

	// The ship's readout is hers, not the market's, so it is on screen for the whole move.
	// Drawing it with the column popped it into existence partway through the swing.
	rl.DrawTextEx(
		ui_font_body,
		fmt.ctprintf("%s", ship_stat_line(&state.player)),
		{40, 28},
		UI_BODY_SIZE,
		1,
		COLOUR_CREAM_BRIGHT,
	)

	// The column comes in over the back half of the move and slides from off the right edge.
	// Held back rather than travelling with the camera: paper arriving while the ship is
	// still swinging gives the eye two things moving in different directions at once.
	arrival := shop_proto_ease(clamp((t - 0.45) / 0.55, 0, 1))
	if arrival > 0 {
		options, n := shop_proto_options(state)
		draw_shop_proto_column(state, options[:], n, (1 - arrival) * 440)
	}

	if bar {
		draw_shop_proto_readout(t)
	}
}

// ---------------------------------------------------------------------------
// The column — four discrete cards, aligned
//
// Paper on the sea with no panel behind it, so the ship's own water runs between the cards
// and the screen is the ship screen with paper on it rather than the ship screen with a wall
// on it. Every edge lines up: card left, card right, the heading above them and the control
// below. Four prices scan down one straight line. `dx` slides the whole block in from the
// right during the move and is zero at rest.
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
draw_shop_proto_column :: proc(state: ^Game_State, options: []sim.Stage_Option, n: int, dx: f32) {
	x := SHOP_PROTO_COL_X + dx

	// The heading starts on the column's own left edge rather than being centred over it: a
	// centred title above a left-aligned stack has nothing for the eye to run down.
	rl.DrawTextEx(ui_font_title, "Market", {x, 44}, UI_TITLE_SIZE, 2, COLOUR_CREAM_BRIGHT)

	for i in 0 ..< n {
		option := options[i]
		card := rl.Rectangle {
			x,
			SHOP_PROTO_COL_Y0 + f32(i) * SHOP_PROTO_COL_PITCH,
			SHOP_PROTO_COL_W,
			SHOP_PROTO_COL_CARD_H,
		}
		afford := voyage.voyage_option_can_afford(&state.player, option)

		// A cast shadow, not a glow: the sea is bright, so the only way paper sits above it
		// is to darken what is under the paper.
		rl.DrawRectangleRec({card.x + 5, card.y + 6, card.width, card.height}, rl.Fade(COLOUR_SEA_DEEP, 0.45))
		// Paper is opaque. Dimming an unaffordable card by alpha was an early pass and it let
		// a hull-down island read straight through the card as a stain — translucency costs a
		// panel its own ground. Unaffordable is a duller sheet plus duller ink, shaded down
		// the one swatch rather than mixed toward anything.
		rl.DrawRectangleRec(card, afford ? COLOUR_PARCHMENT : colour_shade(COLOUR_PARCHMENT, 0.90))
		rl.DrawRectangleLinesEx(card, 2, afford ? COLOUR_SEA_DEEP : COLOUR_CLIFF)
		draw_shop_proto_entry(card, option, afford)
	}

	// The control takes the column's full width so the block closes on the same two edges it
	// opened on. No shadow — it is not another piece of stock.
	shop_proto_control(
		{x, SHOP_PROTO_COL_Y0 + f32(n) * SHOP_PROTO_COL_PITCH + 16, SHOP_PROTO_COL_W, 40},
		"Leave",
		COLOUR_SEA_DEEP,
		COLOUR_PARCHMENT,
	)
}

// ---------------------------------------------------------------------------
// Shared marks
// ---------------------------------------------------------------------------

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

// shop_proto_control is every control here: a 2px border in the tone that states its role, a
// ground, and a label in the same tone. No fill marks the default action — the guide retired
// that accent and this prototype does not reopen it.
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

// draw_shop_proto_readout is the prototype's own furniture and is drawn to look like it: the
// retired navy ramp, hard edges, nothing off the bright roster. It must never be mistaken for
// part of the design being judged. It shows where the move has got to, because scrubbing by
// hand is useless without a number to scrub against.
@(private)
draw_shop_proto_readout :: proc(t: f32) {
	bar := rl.Rectangle{(WINDOW_WIDTH - 460) / 2, 652, 460, 34}
	rl.DrawRectangleRec(bar, rl.Fade(COLOUR_VIGNETTE, 0.92))
	rl.DrawRectangleLinesEx(bar, 1, COLOUR_STEEL)

	// A progress rule along the bar's foot: the number says where it is, this says how far.
	rl.DrawRectangleRec({bar.x + 1, bar.y + bar.height - 3, (bar.width - 2) * clamp(t, 0, 1), 2}, COLOUR_CYAN)

	label := fmt.ctprintf("t %.2f  ·  Space replays  ·  arrows scrub", t)
	size := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1)
	rl.DrawTextEx(
		ui_font_body,
		label,
		{bar.x + (bar.width - size.x) / 2, bar.y + bar.height / 2 - size.y / 2 - 1},
		UI_BODY_SIZE,
		1,
		COLOUR_CREAM,
	)
}

// ---------------------------------------------------------------------------
// Staging and the interactive run
// ---------------------------------------------------------------------------

// shop_proto_stage builds the world the screen draws from: the real starting ship and the
// same four-item shelf capture's own `shop` shot stages, so this is judged against the stock
// the shipped screen is judged against.
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

// The capture entries. Appended to the end of `capture_shots` so no shipped shot renumbers.
// Three of the four are frames *through* the move: a move is the one thing a still cannot
// judge, but stills along it are what say whether the blend is monotone and whether anything
// tears halfway.
@(private)
capture_stage_shop_proto :: proc(scene: ^Capture_Scene) {
	shop_proto_stage(&scene.game, &scene.player)
}

@(private)
capture_frame_shop_proto :: proc(scene: ^Capture_Scene) -> bool {
	draw_shop_prototype(&scene.game, 1, false)
	return true
}

@(private)
capture_frame_shop_proto_move_25 :: proc(scene: ^Capture_Scene) -> bool {
	draw_shop_prototype(&scene.game, 0.25, false)
	return true
}

@(private)
capture_frame_shop_proto_move_50 :: proc(scene: ^Capture_Scene) -> bool {
	draw_shop_prototype(&scene.game, 0.50, false)
	return true
}

@(private)
capture_frame_shop_proto_move_75 :: proc(scene: ^Capture_Scene) -> bool {
	draw_shop_prototype(&scene.game, 0.75, false)
	return true
}

// shop_proto_requested reports whether the process was started as a prototype run.
shop_proto_requested :: proc() -> bool {
	return slice.contains(os.args[1:], "--shop-proto")
}

// shop_proto_main is the interactive run. No Sim — nothing here needs one.
//
// It boots borderless fullscreen the same way `run` does, because a screen judged in a
// 1244x700 window is not the screen the player sees: the session composes into a render
// texture and blits it, and that path is the only place translucency reads true (the style
// guide's "a render texture loses alpha"). Every card shadow, faded rule and dimmed ink here
// is translucent, so this is the run that tells the truth about them — and the one `--shot`
// structurally cannot photograph.
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
		if rl.IsKeyPressed(.SPACE) {
			shop_proto_t = 0
			shop_proto_playing = true
		}
		// Scrubbing takes the move off the clock: holding an arrow is how you sit inside the
		// middle of the swing, which is where a blend goes wrong and where 60fps never lets
		// you look.
		if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.LEFT) {
			shop_proto_playing = false
			step := rl.GetFrameTime() / SHOP_PROTO_MOVE_SECONDS
			shop_proto_t = clamp(shop_proto_t + (rl.IsKeyDown(.RIGHT) ? step : -step), 0, 1)
		}
		if shop_proto_playing {
			shop_proto_t = clamp(shop_proto_t + rl.GetFrameTime() / SHOP_PROTO_MOVE_SECONDS, 0, 1)
			if shop_proto_t >= 1 {
				shop_proto_playing = false
			}
		}
		// F11 drops back to a window and returns. fullscreen_active stays true either way:
		// frame_end letterboxes against whatever GetScreenWidth reports, so the texture path —
		// and with it the honest alpha — is in play at both sizes.
		if rl.IsKeyPressed(.F11) {
			rl.ToggleBorderlessWindowed()
		}
		draw_shop_prototype(&state, shop_proto_t, true)
	}

	shop_proto_t = 0
	shop_proto_playing = true
}
