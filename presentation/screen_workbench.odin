package presentation

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// The 2D mode of the workbench (workbench.odin): `game.exe --workbench shop`.
//
// The hull mode proved the pattern and its own header says why — every hard defect on the
// ship screen was a diagnostic failure, and the fix was steering plus seeing. The same is
// true of every 2D screen, and the whole of the instrument is already written. What is left
// is saying which numbers a screen will let you drag.
//
// The point is not convenience. It moves tuning out of the model's context entirely: a human
// tunes by eye at zero token cost, and the model only ever writes structure.
//
// A screen is a **capture shot plus a knob list**. Capture already knows how to stage every
// screen the game draws and how to compose one frame of it, so this mode borrows both rather
// than growing a second staging path that could drift from the one the shots are taken
// through — what is under the panel is the screen a capture would photograph. Adding a screen
// is therefore one registry row and one knob proc, and nothing here is welded to the Shop.

// Workbench_Screen is one steerable 2D screen: the capture shot that stages and draws it, the
// knobs its layout block offers, and the constant a copy replaces.
@(private)
Workbench_Screen :: struct {
	name:  string, // also the capture_shots entry this stages and draws through
	knobs: proc(w: ^Workbench),
	emit:  Workbench_Emit,
}

@(private)
OFFER_SHOP_EMIT :: Workbench_Emit {
	name = "OFFER_SHOP_LAYOUT",
	type = "Offer_Shop_Layout",
}

@(private)
workbench_screens := [?]Workbench_Screen {
	{name = "shop", knobs = workbench_offer_shop_knobs, emit = OFFER_SHOP_EMIT},
	// The Offer is the same column with unpriced stock, so it steers the same block — a second
	// screen costs the row that names it.
	{name = "offer", knobs = workbench_offer_shop_knobs, emit = OFFER_SHOP_EMIT},
}

@(private)
workbench_screen_for :: proc(name: string) -> (screen: Workbench_Screen, ok: bool) {
	for candidate in workbench_screens {
		if candidate.name == name {
			return candidate, true
		}
	}
	return {}, false
}

// screen_workbench_bench is the panel the frame overlay draws, set for exactly as long as the
// loop below runs. The screens compose and present their own frame (frame_begin/frame_end), so
// a tool drawing *over* one has to be let in rather than sequenced after it.
@(private = "file")
screen_workbench_bench: ^Workbench

@(private = "file")
screen_workbench_overlay :: proc() {
	if screen_workbench_bench != nil {
		workbench_panel(screen_workbench_bench)
	}
}

// screen_workbench_main opens one named screen with its slider panel and returns when the
// window closes. Reports whether the name was one this mode knows.
@(private)
screen_workbench_main :: proc(name: string) -> bool {
	screen, known := workbench_screen_for(name)
	if !known {
		names: [len(workbench_screens)]string
		for candidate, i in workbench_screens {
			names[i] = candidate.name
		}
		fmt.eprintfln(
			"workbench: no screen named %q.\n  screens: %s\n" +
			"  A bare --workbench opens the hull.",
			name,
			strings.join(names[:], ", ", context.temp_allocator),
		)
		return false
	}

	// A registry row names a capture shot, so a row whose name is not one is a wiring mistake
	// rather than anything a run could recover from.
	shot, _, staged := capture_shot_for(screen.name)
	assert(staged, "a workbench screen names a capture shot")

	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, fmt.ctprintf("Fantasy Ship Game — %s workbench", name))
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL)

	ui_fonts_load()
	defer ui_fonts_unload()
	art_load()
	defer art_unload()

	// The scene is staged once and drawn every frame, which is the split capture already makes:
	// staging allocates, composing does not.
	scene := Capture_Scene{}
	defer capture_scene_destroy(&scene)
	if shot.stage != nil {
		shot.stage(&scene)
	}

	w := Workbench {
		held = -1,
		panel = true,
		emit = screen.emit,
	}
	defer delete(w.knobs)
	screen.knobs(&w)

	screen_workbench_bench = &w
	frame_overlay = screen_workbench_overlay
	defer {
		frame_overlay = nil
		screen_workbench_bench = nil
	}

	for !rl.WindowShouldClose() {
		workbench_keys(&w)
		shot.frame(&scene)
		free_all(context.temp_allocator)
	}
	return true
}

// workbench_offer_shop_knobs points the panel at the layout the screen actually draws from.
// The registry holds this; the block it steers is named one line below rather than reached for
// throughout, so the knob list can also be spelled over a layout that is not the live one.
@(private)
workbench_offer_shop_knobs :: proc(w: ^Workbench) {
	workbench_offer_shop_knobs_into(w, &offer_shop_layout)
}

// workbench_offer_shop_knobs_into is the Offer/Shop column, in the order a designer moves it:
// where the block sits and how wide, then the rhythm down it, then what a single card is made
// of.
//
// The ranges are the tool's opinion. The column may not leave the right-hand half of the frame
// (it shares the screen with the ship, and a column crossing her is not a layout worth
// reaching), and no inset may exceed the card it insets.
@(private)
workbench_offer_shop_knobs_into :: proc(w: ^Workbench, l: ^Offer_Shop_Layout) {
	workbench_add(w, "column x", &l.col_x, 620, 1000, "col_x", "column")
	workbench_add(w, "column w", &l.col_w, 240, 460, "col_w")
	workbench_add(w, "column top", &l.col_y0, 24, 200, "col_y0")
	workbench_add(w, "card height", &l.card_h, 56, 160, "card_h")
	workbench_add(w, "card pitch", &l.pitch, 56, 180, "pitch")
	workbench_add(w, "leave gap", &l.leave_gap, 0, 60, "leave_gap")
	workbench_add(w, "leave height", &l.leave_h, 24, 72, "leave_h")

	workbench_add(w, "inset", &l.card_inset, 4, 40, "card_inset", "card")
	workbench_add(w, "border", &l.card_border, 1, 6, "card_border")
	workbench_add(w, "shadow x", &l.shadow_dx, 0, 16, "shadow_dx")
	workbench_add(w, "shadow y", &l.shadow_dy, 0, 16, "shadow_dy")
	workbench_add(w, "name y", &l.name_y, 2, 40, "name_y")
	workbench_add(w, "intent y", &l.intent_y, 12, 70, "intent_y")
	workbench_add(w, "spec y", &l.spec_y, 24, 100, "spec_y")
	workbench_add(w, "name size", &l.name_size, 12, 48, "name_size")
	workbench_add(w, "body size", &l.body_size, 12, 32, "body_size")
	workbench_add(w, "price box", &l.price_box, 8, 24, "price_box")
	workbench_add(w, "price gap", &l.price_gap, 8, 48, "price_gap")
}
