package presentation

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

// The workbench: `game.exe --workbench [screen]`. An entry beside --capture, --hull-sheet and
// the player session, and the answer to a fair question — whether there is a better way to
// shape this game's surfaces than editing a number, rebuilding, taking a screenshot and
// looking at it.
//
// There is, and it is this. Every hard defect so far has been a *diagnostic* failure rather
// than an expressive one: the loft could always describe a fine bow, but nothing showed that
// the last strip was doing all of the fining. So the workbench gives the two things that were
// missing. **Steering**: every number that decides a shape is a slider, and what it decides
// redraws under your hand. **Seeing**: for the hull, fly the camera off the shipped framing
// or paint her by which way each surface faces.
//
// It emits Odin rather than saving anything, exactly as the Forge does — drag until it looks
// right, press C, paste the literal back over the constant it came from. The tool never
// writes to the repo and the game never links a control from it.
//
// This file is the instrument the two modes share: the knobs, the panel that drags them, and
// the copy. What is being steered lives in the mode — the hull's loft in ship_workbench.odin,
// a screen's layout block in screen_workbench.odin — and the knobs point into it, so nothing
// here learns what it is tuning.

@(private)
WORKBENCH_PANEL_W :: f32(330)
@(private)
WORKBENCH_ROW :: f32(21)

// Workbench_Knob is one tunable number: where it lives, what it is called, and the range a
// slider may take it over. The range is the tool's whole opinion — wide enough to reach
// shapes worth seeing, narrow enough that a drag lands somewhere buildable.
//
// `field` is the struct field the number occupies, and is what the emitted literal names it
// by. A knob with no field steers the tool rather than the thing (the camera), and is not
// emitted. `heading`, when set, opens a new block in the panel above this row.
@(private)
Workbench_Knob :: struct {
	label:   string,
	field:   string,
	heading: string,
	value:   ^f32,
	lo, hi:  f32,
	// What the number held when the knob was added, which is its shipped value: the reset
	// target, and what the moved-from-shipped mark compares against. Captured rather than
	// looked up, so there is no second table of defaults to keep in step.
	shipped: f32,
}

// Workbench_Emit names the Odin constant a copy replaces, and its type — the two words a
// pasteable literal needs that the knobs cannot supply.
@(private)
Workbench_Emit :: struct {
	name: string,
	type: string,
}

@(private)
Workbench :: struct {
	knobs:  [dynamic]Workbench_Knob,
	held:   int, // index of the knob the mouse has hold of, -1 for none
	panel:  bool,
	copied: int,
	emit:   Workbench_Emit,
	// hint is the mode's own line in the panel's footer — the hull's view keys, and nothing
	// at all for a 2D screen, which has no second way of being looked at. nil for none.
	hint:   proc() -> string,
}

// workbench_add appends a knob, taking its shipped value off what the number holds now.
@(private)
workbench_add :: proc(
	w: ^Workbench,
	label: string,
	value: ^f32,
	lo, hi: f32,
	field := "",
	heading := "",
) {
	append(
		&w.knobs,
		Workbench_Knob {
			label = label,
			field = field,
			heading = heading,
			value = value,
			lo = lo,
			hi = hi,
			shipped = value^,
		},
	)
}

// workbench_requested reports whether the process was started as a workbench run.
workbench_requested :: proc() -> bool {
	return slice.contains(os.args[1:], WORKBENCH_FLAG)
}

@(private)
WORKBENCH_FLAG :: "--workbench"

// workbench_screen_requested reports the 2D screen the run named. A bare --workbench names
// none, which is the hull.
workbench_screen_requested :: proc() -> (name: string, named: bool) {
	value, _ := arg_value(os.args[1:], WORKBENCH_FLAG)
	return value, value != ""
}

// workbench_main picks the mode: a named 2D screen, or the hull.
workbench_main :: proc() -> bool {
	if name, named := workbench_screen_requested(); named {
		return screen_workbench_main(name)
	}
	hull_workbench_main()
	return true
}

// workbench_keys is the keyboard every mode shares: hide the panel, put everything back, copy.
// Deliberately small — anything that needs a value is a slider, and anything that needs a
// chord is a feature this tool does not have.
@(private)
workbench_keys :: proc(w: ^Workbench) {
	if rl.IsKeyPressed(.TAB) {
		w.panel = !w.panel
	}
	// R is the way back: every knob to what it ships at, whatever has been dragged. A tool you
	// can get lost in is one you stop trusting what you see in.
	if rl.IsKeyPressed(.R) {
		for &knob in w.knobs {
			knob.value^ = knob.shipped
		}
	}
	if rl.IsKeyPressed(.C) {
		source := workbench_emit(w)
		rl.SetClipboardText(fmt.ctprintf("%s", source))
		w.copied = len(source)
	}
}

// workbench_panel draws the controls and reads the mouse. Immediate mode throughout: a slider
// is a rectangle, a fill and a hit test, and the value it edits is the one the next draw call
// uses. There is no apply and no commit — what is under the panel *is* the state.
@(private)
workbench_panel :: proc(w: ^Workbench) {
	if !w.panel {
		workbench_text("Tab  panel", 10, WINDOW_HEIGHT - 24, COLOUR_FOAM)
		return
	}

	headings := 0
	for knob in w.knobs {
		if knob.heading != "" {
			headings += 1
		}
	}
	height := f32(len(w.knobs)) * WORKBENCH_ROW + f32(headings) * WORKBENCH_ROW + 96
	panel := rl.Rectangle{8, 8, WORKBENCH_PANEL_W, height}
	rl.DrawRectangleRec(panel, rl.Fade(COLOUR_INK_PRIMARY, 0.86))
	rl.DrawRectangleLinesEx(panel, 1, COLOUR_SEA_DEEP)

	mouse := rl.GetMousePosition()
	if rl.IsMouseButtonReleased(.LEFT) {
		w.held = -1
	}

	y := panel.y + 8
	for &knob, index in w.knobs {
		if knob.heading != "" {
			y += 6
			rl.DrawRectangleRec({panel.x + 10, y, panel.width - 20, 1}, COLOUR_SEA_DEEP)
			y += 5
			workbench_text(knob.heading, panel.x + 10, y, rl.Fade(COLOUR_SEA_SHALLOW, 0.8))
			y += WORKBENCH_ROW
		}

		// The readout is inside the panel, not spilling off it: the track gives up the width.
		track := rl.Rectangle{panel.x + 112, y + 5, panel.width - 112 - 60, 9}
		if rl.IsMouseButtonPressed(.LEFT) &&
		   rl.CheckCollisionPointRec(mouse, {track.x - 4, y, track.width + 8, WORKBENCH_ROW}) {
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
		// wandered is visible without comparing every number by eye. The mark is brightness, not
		// hue — a moved label at full foam, an untouched one faded — which ranks state the way
		// the roster does and spends no second tone on it.
		moved := abs(knob.value^ - knob.shipped) > 0.0005
		workbench_text(knob.label, panel.x + 10, y + 2, moved ? COLOUR_FOAM : rl.Fade(COLOUR_FOAM, 0.55))
		workbench_text(fmt.tprintf("%.3f", knob.value^), panel.x + panel.width - 54, y + 2, COLOUR_SEA_SHALLOW)
		y += WORKBENCH_ROW
	}

	y += 8
	if w.hint != nil {
		workbench_text(w.hint(), panel.x + 10, y, COLOUR_SEA_SHALLOW)
		y += 18
	}
	workbench_text(
		fmt.tprintf("R reset    C copy %s as Odin    Tab hide", w.emit.name),
		panel.x + 10,
		y,
		COLOUR_FOAM,
	)
	if w.copied > 0 {
		// A readout of what the copy did, in the tone the panel gives its other readouts.
		workbench_text(fmt.tprintf("copied %d bytes", w.copied), panel.x + 10, y + 18, COLOUR_SEA_SHALLOW)
	}
}

// workbench_emit is the tuned block as the Odin literal that would replace the constant it
// came from. Composed off the knob table, so a knob that exists is a field that is emitted
// and there is no second list to fall out of step with.
@(private)
workbench_emit :: proc(w: ^Workbench) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "%s :: %s {{\n", w.emit.name, w.emit.type)

	width := 0
	for knob in w.knobs {
		if knob.field != "" {
			width = max(width, len(knob.field))
		}
	}
	for knob in w.knobs {
		if knob.field == "" {
			continue
		}
		padded := strings.left_justify(knob.field, width, " ", context.temp_allocator)
		fmt.sbprintf(&b, "\t%s = %.4f,\n", padded, knob.value^)
	}
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

// arg_value reads `--flag <value>` (or `--flag=<value>`) out of a command line. A bare flag is
// a request naming nothing, which every caller answers by listing what can be asked for.
@(private)
arg_value :: proc(args: []string, flag: string) -> (value: string, present: bool) {
	for arg, i in args {
		if strings.has_prefix(arg, flag) && len(arg) > len(flag) && arg[len(flag)] == '=' {
			return arg[len(flag) + 1:], true
		}
		if arg == flag {
			// A following flag is the next request, not this one's value — `--shot --capture`
			// names nothing rather than asking for a screen called "--capture".
			if i + 1 < len(args) && !strings.has_prefix(args[i + 1], "--") {
				return args[i + 1], true
			}
			return "", true
		}
	}
	return "", false
}
