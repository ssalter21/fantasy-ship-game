package presentation

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import cutaway "./cutaway"
import sim "../core/sim"
import rl "vendor:raylib"

// The hull workbench: `game.exe --workbench`. A fourth entry beside --capture and the player
// session, and the answer to a fair question — whether there is a better way to model this ship
// than editing a number, rebuilding, taking a screenshot and looking at it.
//
// There is, and it is this. Every hard defect on the ship screen so far has been a *diagnostic*
// failure rather than an expressive one: the loft could always describe a fine bow, but nothing
// showed that the last strip was doing all of the fining; the cut could always close at the
// right station, but nothing showed it was opening onto empty bow. Finding them meant sampling
// pixels and solving colours backwards through the lighting. So the workbench gives the two
// things that were missing. **Steering**: every curve in the loft is a slider, and the ship
// redraws under your hand. **Seeing**: fly the camera off the shipped framing, turn the ship
// into its own wireframe, or paint it by which way each surface faces.
//
// It emits Odin rather than saving anything, exactly as the Forge does — drag until she looks
// right, press C, paste GALLEON_LOFT back into cutaway/galleon.odin. The tool never writes to
// the repo and the game never links a control from it.
//
// Why it is not in the Forge: the Forge is a separate executable that **never imports
// presentation/**, on purpose and in writing. Everything that paints this hull lives in
// presentation. Putting the workbench there means first extracting the galleon's painter and
// the palette into packages both can share, which is a real refactor and a separate decision.

@(private)
WORKBENCH_PANEL_W :: f32(330)
@(private)
WORKBENCH_ROW :: f32(21)

// Knob is one tunable number: where it lives, what it is called, and the range a slider may
// take it over. The range is the tool's whole opinion — wide enough to reach shapes worth
// seeing, narrow enough that a drag lands somewhere buildable rather than folding the hull
// inside out.
@(private)
Workbench_Knob :: struct {
	label:    string,
	value:    ^f32,
	lo, hi:   f32,
	emitted:  bool, // whether it belongs in the emitted Loft literal
}

@(private)
Workbench :: struct {
	eye:     cutaway.Eye,
	loft:    cutaway.Loft,
	knobs:   [dynamic]Workbench_Knob,
	held:    int, // index of the knob the mouse has hold of, -1 for none
	panel:   bool,
	copied:  int,
	game:    Game_State,
}

// workbench_requested reports whether the process was started as a workbench run.
workbench_requested :: proc() -> bool {
	return slice.contains(os.args[1:], "--workbench")
}

// workbench_main is the tool, boot to quit. It composes the real draw_ship_cutaway into the
// real logical frame, so what is on screen is the shipped screen and not a preview of it — a
// workbench that draws its own approximation of the ship is a workbench that lies.
workbench_main :: proc() {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Fantasy Ship Game — hull workbench")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL)

	ui_fonts_load()
	defer ui_fonts_unload()
	art_load()
	defer art_unload()

	w := Workbench {
		eye   = cutaway.GALLEON_EYE,
		loft  = cutaway.GALLEON_LOFT,
		held  = -1,
		panel = true,
	}
	defer delete(w.knobs)
	workbench_knobs(&w)

	// A ship to look at: one tick of a throwaway Sim dispatched into a fresh state, which is how
	// --capture gets a populated Home without walking a voyage.
	s := sim.sim_create(VOYAGE_SEED)
	defer sim.sim_destroy(&s)
	defer delete(w.game.visited)
	defer delete(w.game.positions)
	defer delete(w.game.voyage_map.nodes)
	events: [dynamic]sim.Event
	defer delete(events)
	sim.sim_tick(&s, &events)
	for e in events {
		dispatch(&w.game, e)
	}

	for !rl.WindowShouldClose() {
		workbench_keys(&w)
		cutaway.galleon_loft = w.loft
		ship_debug_eye = w.eye

		rl.BeginDrawing()
		draw_ship_cutaway(&w.game, Build_Drag{}, rl.GetMousePosition())
		workbench_panel(&w)
		rl.EndDrawing()
		free_all(context.temp_allocator)
	}

	// Left as the game leaves them, so nothing this tool did outlives it.
	cutaway.galleon_loft = cutaway.GALLEON_LOFT
	ship_debug_eye = nil
	ship_debug_normals = false
	ship_debug_wires = false
}

// workbench_knobs spells the panel: the camera first, because flying round her is what answers
// "is this solid", then the loft in the order a shipwright would fair it — keel, sheer, the
// waterline plan, and finally the shape of a frame.
@(private)
workbench_knobs :: proc(w: ^Workbench) {
	add :: proc(w: ^Workbench, label: string, value: ^f32, lo, hi: f32, emitted := true) {
		append(&w.knobs, Workbench_Knob{label = label, value = value, lo = lo, hi = hi, emitted = emitted})
	}
	add(w, "cam yaw", &w.eye.yaw, -180, 180, false)
	add(w, "cam dist", &w.eye.dist, 2, 22, false)
	add(w, "cam height", &w.eye.height, -3, 6, false)
	add(w, "cam look", &w.eye.look, -1, 3, false)
	add(w, "cam fov", &w.eye.fov, 15, 100, false)

	add(w, "keel camber", &w.loft.keel_camber, 0, 4)
	add(w, "keel low", &w.loft.keel_low, 0.2, 0.8)
	add(w, "sheer rise", &w.loft.sheer_rise, 0, 0.6)
	add(w, "sheer camber", &w.loft.sheer_camber, 0, 2)
	add(w, "entry start", &w.loft.entry_start, 0.2, 0.9)
	add(w, "entry power", &w.loft.entry_power, 0.4, 4)
	add(w, "run fill", &w.loft.run_fill, 0.2, 1)
	add(w, "run span", &w.loft.run_span, 0.05, 0.8)
	add(w, "run power", &w.loft.run_power, 0.2, 3)
	add(w, "wale height", &w.loft.wale_t, 0.3, 0.95)
	add(w, "garboard", &w.loft.garboard, 0, 0.6)
	add(w, "bilge power", &w.loft.rise_power, 0.2, 2)
	add(w, "tumblehome", &w.loft.tumblehome, 0, 0.6)
}

// workbench_keys is the whole keyboard. Deliberately small: three view toggles, a reset, and
// the copy. Anything that needs a value is a slider, and anything that needs a chord is a
// feature this tool does not have.
@(private)
workbench_keys :: proc(w: ^Workbench) {
	if rl.IsKeyPressed(.N) {
		ship_debug_normals = !ship_debug_normals
	}
	if rl.IsKeyPressed(.M) {
		ship_debug_wires = !ship_debug_wires
	}
	if rl.IsKeyPressed(.TAB) {
		w.panel = !w.panel
	}
	// R is the way back: the shipped framing and the shipped hull, whatever has been dragged.
	// A tool you can get lost in is one you stop trusting what you see in.
	if rl.IsKeyPressed(.R) {
		w.eye, w.loft = cutaway.GALLEON_EYE, cutaway.GALLEON_LOFT
	}
	if rl.IsKeyPressed(.C) {
		source := workbench_emit(w)
		rl.SetClipboardText(fmt.ctprintf("%s", source))
		w.copied = len(source)
	}
	// The mouse wheel dollies, because reaching for a slider to get closer to a thing you are
	// already looking at is the one interaction that would be used constantly.
	if scroll := rl.GetMouseWheelMove(); scroll != 0 {
		w.eye.dist = clamp(w.eye.dist - scroll * 0.4, 2, 22)
	}
}

// workbench_panel draws the controls and reads the mouse. Immediate mode throughout: a slider
// is a rectangle, a fill and a hit test, and the value it edits is the one the next draw call
// uses. There is no apply and no commit — the ship under the panel *is* the state.
@(private)
workbench_panel :: proc(w: ^Workbench) {
	if !w.panel {
		workbench_text("Tab  panel", 10, WINDOW_HEIGHT - 24, COLOUR_FOAM)
		return
	}

	rows := f32(len(w.knobs))
	height := rows * WORKBENCH_ROW + 96
	panel := rl.Rectangle{8, 8, WORKBENCH_PANEL_W, height}
	rl.DrawRectangleRec(panel, rl.Fade(COLOUR_INK_PRIMARY, 0.86))
	rl.DrawRectangleLinesEx(panel, 1, COLOUR_SEA_DEEP)

	mouse := rl.GetMousePosition()
	if rl.IsMouseButtonReleased(.LEFT) {
		w.held = -1
	}

	y := panel.y + 8
	for &knob, index in w.knobs {
		// The camera block and the loft block are different kinds of thing — one is where you
		// are standing, the other is what you are looking at — so the panel says so.
		if index == 5 {
			y += 6
			rl.DrawRectangleRec({panel.x + 10, y, panel.width - 20, 1}, COLOUR_SEA_DEEP)
			y += 7
		}
		// The readout is inside the panel, not spilling off it: the track gives up the width.
		track := rl.Rectangle{panel.x + 112, y + 5, panel.width - 112 - 60, 9}
		if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, {track.x - 4, y, track.width + 8, WORKBENCH_ROW}) {
			w.held = index
		}
		if w.held == index {
			f := clamp((mouse.x - track.x) / track.width, 0, 1)
			knob.value^ = knob.lo + (knob.hi - knob.lo) * f
		}

		fill := clamp((knob.value^ - knob.lo) / (knob.hi - knob.lo), 0, 1)
		rl.DrawRectangleRec(track, rl.Fade(COLOUR_SEA_DEEP, 0.7))
		rl.DrawRectangleRec({track.x, track.y, track.width * fill, track.height}, COLOUR_SEA_SHALLOW)
		rl.DrawRectangleRec({track.x + track.width * fill - 2, track.y - 3, 4, track.height + 6}, COLOUR_FOAM)

		// A knob standing away from its shipped value is worth saying, so a session that has
		// wandered is visible without comparing thirteen numbers by eye.
		moved := index < 5 ? false : abs(knob.value^ - workbench_shipped(w, index)) > 0.0005
		workbench_text(knob.label, panel.x + 10, y + 2, moved ? COLOUR_AMBER : COLOUR_FOAM)
		workbench_text(fmt.tprintf("%.3f", knob.value^), panel.x + panel.width - 54, y + 2, COLOUR_SEA_SHALLOW)
		y += WORKBENCH_ROW
	}

	y += 8
	views := fmt.tprintf(
		"N normals %s    M wires %s",
		ship_debug_normals ? "on" : "off",
		ship_debug_wires ? "on" : "off",
	)
	workbench_text(views, panel.x + 10, y, COLOUR_SEA_SHALLOW)
	workbench_text("R reset    C copy Loft as Odin    Tab hide", panel.x + 10, y + 18, COLOUR_FOAM)
	if w.copied > 0 {
		workbench_text(fmt.tprintf("copied %d bytes", w.copied), panel.x + 10, y + 36, COLOUR_AMBER)
	}
}

// workbench_shipped is a knob's value in the shipped loft, for the moved-from-default mark.
@(private)
workbench_shipped :: proc(w: ^Workbench, index: int) -> f32 {
	shipped := cutaway.GALLEON_LOFT
	// The knob list holds pointers into w.loft, so the same offset into a copy of the shipped
	// loft is the shipped value of that knob — no second table of defaults to keep in step.
	offset := uintptr(w.knobs[index].value) - uintptr(&w.loft)
	return (^f32)(uintptr(&shipped) + offset)^
}

// workbench_emit is the tuned loft as the Odin literal that would replace GALLEON_LOFT. The
// same hand-back the Forge does: the tool never edits the repo, it hands a human the source.
@(private)
workbench_emit :: proc(w: ^Workbench) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "GALLEON_LOFT :: Loft {\n")
	fmt.sbprintf(&b, "\tkeel_camber  = %.4f,\n", w.loft.keel_camber)
	fmt.sbprintf(&b, "\tkeel_low     = %.4f,\n", w.loft.keel_low)
	fmt.sbprintf(&b, "\tsheer_rise   = %.4f,\n", w.loft.sheer_rise)
	fmt.sbprintf(&b, "\tsheer_camber = %.4f,\n", w.loft.sheer_camber)
	fmt.sbprintf(&b, "\tentry_start  = %.4f,\n", w.loft.entry_start)
	fmt.sbprintf(&b, "\tentry_power  = %.4f,\n", w.loft.entry_power)
	fmt.sbprintf(&b, "\trun_fill     = %.4f,\n", w.loft.run_fill)
	fmt.sbprintf(&b, "\trun_span     = %.4f,\n", w.loft.run_span)
	fmt.sbprintf(&b, "\trun_power    = %.4f,\n", w.loft.run_power)
	fmt.sbprintf(&b, "\twale_t       = %.4f,\n", w.loft.wale_t)
	fmt.sbprintf(&b, "\tgarboard     = %.4f,\n", w.loft.garboard)
	fmt.sbprintf(&b, "\trise_power   = %.4f,\n", w.loft.rise_power)
	fmt.sbprintf(&b, "\ttumblehome   = %.4f,\n", w.loft.tumblehome)
	strings.write_string(&b, "}\n")
	return strings.to_string(b)
}

// workbench_text is the workbench's only text call. The tool draws in the game's body face
// because it is drawn *over* the game's frame and a second typeface in the same window would
// be one more thing to read past.
@(private)
workbench_text :: proc(text: string, x, y: f32, colour: rl.Color) {
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", text), rl.Vector2{x, y}, UI_BODY_SIZE, 1, colour)
}
