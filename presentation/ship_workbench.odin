package presentation

import "core:fmt"
import cutaway "./cutaway"
import sim "../core/sim"
import rl "vendor:raylib"

// The hull mode of the workbench (workbench.odin): `game.exe --workbench`, with no screen
// named. Where the contact sheet (hull_sheet.odin) finds the surface that is wrong from six
// fixed eyes in one PNG, this is where you go to see why — the one you *steer*.
//
// It adds two things to the shared instrument, and both are about a shape rather than a
// layout. A **camera** the shipped screens do not have: the eye is a knob block of its own,
// flown off the moored framing and dollied on the wheel. And **paints** that answer questions
// shading cannot: turn her into her own wireframe, or colour her by which way each surface
// faces.
//
// Why it is not in the Forge: the Forge is a separate executable that **never imports
// presentation/**, on purpose and in writing. Everything that paints this hull lives in
// presentation. Putting the workbench there means first extracting the galleon's painter and
// the palette into packages both can share, which is a real refactor and a separate decision.

@(private)
Hull_Workbench :: struct {
	bench: Workbench,
	eye:   cutaway.Eye,
	loft:  cutaway.Loft,
	game:  Game_State,
}

// hull_workbench_main is the hull mode, boot to quit. It composes the real draw_ship_cutaway
// into the real logical frame, so what is on screen is the shipped screen and not a preview of
// it — a workbench that draws its own approximation of the ship is a workbench that lies.
@(private)
hull_workbench_main :: proc() {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Fantasy Ship Game — hull workbench")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL)

	ui_fonts_load()
	defer ui_fonts_unload()
	art_load()
	defer art_unload()

	h := Hull_Workbench {
		eye = cutaway.GALLEON_EYE,
		loft = cutaway.GALLEON_LOFT,
		bench = Workbench {
			held = -1,
			panel = true,
			emit = {name = "GALLEON_LOFT", type = "Loft"},
			hint = hull_workbench_hint,
		},
	}
	defer delete(h.bench.knobs)
	hull_workbench_knobs(&h)

	// A ship to look at: one tick of a throwaway Sim dispatched into a fresh state, which is how
	// --capture gets a populated Home without walking a voyage.
	s := sim.sim_create(VOYAGE_SEED)
	defer sim.sim_destroy(&s)
	defer delete(h.game.visited)
	defer delete(h.game.positions)
	defer delete(h.game.voyage_map.nodes)
	events: [dynamic]sim.Event
	defer delete(events)
	sim.sim_tick(&s, &events)
	for e in events {
		dispatch(&h.game, e)
	}

	for !rl.WindowShouldClose() {
		workbench_keys(&h.bench)
		hull_workbench_keys(&h)
		cutaway.galleon_loft = h.loft

		rl.BeginDrawing()
		// The tool's own eye, handed in as an ordinary framing: the shipped view is not something
		// this can move, it simply asks for a different one (#476).
		flown := ship_framing_from(cutaway.galleon_view_from(h.eye, WINDOW_WIDTH, WINDOW_HEIGHT))
		draw_ship_cutaway(&h.game, flown, Build_Drag{}, rl.GetMousePosition(), describe = true)
		workbench_panel(&h.bench)
		rl.EndDrawing()
		free_all(context.temp_allocator)
	}

	// Left as the game leaves them, so nothing this tool did outlives it.
	cutaway.galleon_loft = cutaway.GALLEON_LOFT
	ship_debug_paint = .Shaded
}

// hull_workbench_knobs spells the panel: the camera first, because flying round her is what
// answers "is this solid", then the loft in the order a shipwright would fair it — keel, sheer,
// the waterline plan, and finally the shape of a frame.
@(private)
hull_workbench_knobs :: proc(h: ^Hull_Workbench) {
	w := &h.bench
	workbench_add(w, "cam yaw", &h.eye.yaw, -180, 180)
	workbench_add(w, "cam dist", &h.eye.dist, 2, 22)
	workbench_add(w, "cam height", &h.eye.height, -3, 6)
	workbench_add(w, "cam look", &h.eye.look, -1, 3)
	workbench_add(w, "cam fov", &h.eye.fov, 15, 100)

	// The camera block and the loft block are different kinds of thing — one is where you are
	// standing, the other is what you are looking at — so the panel says so.
	workbench_add(w, "keel camber", &h.loft.keel_camber, 0, 4, "keel_camber", "loft")
	workbench_add(w, "keel low", &h.loft.keel_low, 0.2, 0.8, "keel_low")
	workbench_add(w, "sheer rise", &h.loft.sheer_rise, 0, 0.6, "sheer_rise")
	workbench_add(w, "sheer camber", &h.loft.sheer_camber, 0, 2, "sheer_camber")
	workbench_add(w, "entry start", &h.loft.entry_start, 0.2, 0.9, "entry_start")
	workbench_add(w, "entry power", &h.loft.entry_power, 0.4, 4, "entry_power")
	workbench_add(w, "run fill", &h.loft.run_fill, 0.2, 1, "run_fill")
	workbench_add(w, "run span", &h.loft.run_span, 0.05, 0.8, "run_span")
	workbench_add(w, "run power", &h.loft.run_power, 0.2, 3, "run_power")
	workbench_add(w, "wale height", &h.loft.wale_t, 0.3, 0.95, "wale_t")
	workbench_add(w, "garboard", &h.loft.garboard, 0, 0.6, "garboard")
	workbench_add(w, "bilge power", &h.loft.rise_power, 0.2, 2, "rise_power")
	workbench_add(w, "tumblehome", &h.loft.tumblehome, 0, 0.6, "tumblehome")
}

// hull_workbench_keys is what this mode adds to the shared keyboard: the two view toggles, and
// the wheel. The wheel dollies because reaching for a slider to get closer to a thing you are
// already looking at is the one interaction that would be used constantly.
@(private)
hull_workbench_keys :: proc(h: ^Hull_Workbench) {
	if rl.IsKeyPressed(.N) {
		ship_debug_paint = workbench_paint(ship_debug_paint, .Normals)
	}
	if rl.IsKeyPressed(.M) {
		ship_debug_paint = workbench_paint(ship_debug_paint, .Wires)
	}
	if scroll := rl.GetMouseWheelMove(); scroll != 0 {
		h.eye.dist = clamp(h.eye.dist - scroll * 0.4, 2, 22)
	}
}

// hull_workbench_hint is this mode's footer line: the view keys and which paint is in force.
@(private)
hull_workbench_hint :: proc() -> string {
	return fmt.tprintf("N normals    M wires    painting %s", ship_debug_paint_name(ship_debug_paint))
}

// workbench_paint is the mode a view key asks for: the one it names, or back to the shipped
// shading when that mode is the one already in force. Pressing a diagnosis off has to land
// somewhere, and the shipped paint is the only view that is not a question.
@(private)
workbench_paint :: proc(current, asked: Ship_Paint) -> Ship_Paint {
	return current == asked ? .Shaded : asked
}
