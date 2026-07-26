// Package forge is the Forge: the in-repo authoring tool for the game's content tables.
//
// It is a **third executable** (ADR-0003's pattern) linked against core and nothing else:
// it reads the live roster, catalog and rosters by calling their own accessors, checks an
// edit by calling roster_check, expr_peak and voyage_encounter_from_recipe, and emits Odin
// source for a human to paste back. No budget or bake arithmetic is restated here.
//
// **It never imports presentation/, and presentation/ never imports it.** The game's
// visual language and the tool's are different jobs, and the package split is what makes
// that a compile-time fact — editor widgets cannot leak into a game screen, and none of
// this is linked into the shipped exe.
package forge

import "core:fmt"
import "core:reflect"
import "core:strings"
import ship "../core/ship"
import rl "vendor:raylib"

FORGE_WINDOW_W :: 1440
FORGE_WINDOW_H :: 860
FORGE_MIN_W :: 1024
FORGE_MIN_H :: 640

// Screen is which surface the tool is showing. The two the tool exists for come first;
// the other content rosters and the read-only ship template follow, because balancing
// items and encounters without them is half a job.
Screen :: enum {
	Item_Workbench,
	Encounter_Builder,
	Rosters,
	Ship_And_Constants,
}

@(rodata)
SCREEN_LABEL := [Screen]string {
	.Item_Workbench     = "Item Workbench",
	.Encounter_Builder  = "Encounter Builder",
	.Rosters            = "Rosters",
	.Ship_And_Constants = "Ship & Constants",
}

// SPLITTER_W is the grab width of a pane divider. Panes are resizable and remember their
// split per screen, so an author who widens the budget panel finds it wide next time.
SPLITTER_W :: 5

// Forge is the whole session: the content under edit, its history, where focus is, and
// each surface's own view state. One heap-allocated value with no interior pointers but
// the name views, which is what lets the undo ring copy it wholesale.
Forge :: struct {
	screen:     Screen,
	content:    Content,
	undo:       Undo,
	ui:         Ui,
	split:      [Screen][2]f32,
	// drag is which pane divider the mouse has hold of, absent when none is.
	drag:       Maybe(int),
	workbench:  Workbench,
	builder:    Builder,
	rosters:    Roster_View,
	copied:     int,
}

// run is the tool, boot to quit. The window is genuinely resizable — a fixed canvas is
// the shape of a game, not of a tool — and every frame lays its panes out from the
// window's current size rather than from a designed one.
run :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(FORGE_WINDOW_W, FORGE_WINDOW_H, "The Forge")
	defer rl.CloseWindow()
	rl.SetWindowMinSize(FORGE_MIN_W, FORGE_MIN_H)
	rl.SetTargetFPS(60)
	// Escape leaves the field being edited; it is not a way out of the application.
	rl.SetExitKey(.KEY_NULL)
	style_init()

	f := new(Forge)
	defer free(f)
	forge_init(f)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(color_of(FORGE_SURFACE))
		forge_frame(f)
		rl.EndDrawing()
		free_all(context.temp_allocator)
	}
}

forge_init :: proc(f: ^Forge) {
	content_load(&f.content)
	undo_reset(&f.undo, f.content)
	for screen in Screen {
		f.split[screen] = {0.34, 0.70}
	}
	f.workbench = workbench_init()
	f.builder = builder_init()
}

// forge_frame draws one frame and settles what it changed. The order is the whole of the
// tool's edit model: restore first (so an undo is not itself recorded), snapshot, draw —
// every control writes straight into the content it is showing — then record a snapshot
// if anything moved. There is no apply button because there is nothing to apply.
forge_frame :: proc(f: ^Forge) {
	// Everything a frame allocates is scratch for that frame: a bake, an emitted line,
	// every formatted string. Scoping the allocator here makes that one decision rather
	// than a per-site one, and run's free_all at the end of the loop is the boundary that
	// reclaims it -- so nothing below hand-frees.
	context.allocator = context.temp_allocator

	ui_frame_begin(&f.ui)
	content_sync_names(&f.content)

	if forge_history_keys(f) {
		content_sync_names(&f.content)
	}
	before := f.content

	screen := f.screen
	forge_header(f)
	area := rl.Rectangle {
		0,
		FORGE_HEADER,
		f32(rl.GetScreenWidth()),
		f32(rl.GetScreenHeight()) - FORGE_HEADER - FORGE_STATUS,
	}
	switch f.screen {
	case .Item_Workbench:
		workbench_draw(f, area)
	case .Encounter_Builder:
		builder_draw(f, area)
	case .Rosters:
		rosters_draw(f, area)
	case .Ship_And_Constants:
		reference_draw(f, area)
	}
	forge_status(f)

	if f.screen != screen {
		ui_reset_focus(&f.ui)
	}
	if rl.IsKeyPressed(.ESCAPE) {
		f.ui.edit = nil
	}
	forge_copy_keys(f)
	ui_frame_end(&f.ui)

	if f.content != before {
		undo_commit(&f.undo, f.content)
	}
}

// forge_header is the tab bar and the one place a surface is switched. Tabs are also
// reachable as Ctrl+1..Ctrl+4, since the whole tool is meant to be driven from the
// keyboard.
@(private = "file")
forge_header :: proc(f: ^Forge) {
	bar := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), FORGE_HEADER}
	rl.DrawRectangleRec(bar, color_of(FORGE_PANEL_ALT))
	rl.DrawLineV({0, FORGE_HEADER}, {bar.width, FORGE_HEADER}, color_of(FORGE_LINE))

	x := f32(FORGE_PAD)
	for screen in Screen {
		label := SCREEN_LABEL[screen]
		w := text_width(label) + 2 * FORGE_PAD
		tab := rl.Rectangle{x, 2, w, FORGE_HEADER - 4}
		selected := screen == f.screen
		if selected {
			rl.DrawRectangleRec(tab, color_of(FORGE_PANEL))
			rl.DrawRectangleRec({tab.x, tab.y + tab.height - 2, tab.width, 2}, color_of(FORGE_ACCENT))
		}
		if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(), tab) {
			f.screen = screen
		}
		draw_text(label, tab.x + FORGE_PAD, tab.y + 7, color_of(selected ? FORGE_TEXT : FORGE_TEXT_DIM))
		x += w + FORGE_GAP
	}

	if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) {
		for screen, index in Screen {
			if rl.IsKeyPressed(rl.KeyboardKey(int(rl.KeyboardKey.ONE) + index)) {
				f.screen = screen
			}
		}
	}
}

// forge_status is the bottom line: what the focused control does, or why the last edit
// was refused, plus how deep the session's history goes.
@(private = "file")
forge_status :: proc(f: ^Forge) {
	bar := rl.Rectangle {
		0,
		f32(rl.GetScreenHeight()) - FORGE_STATUS,
		f32(rl.GetScreenWidth()),
		FORGE_STATUS,
	}
	rl.DrawRectangleRec(bar, color_of(FORGE_PANEL_ALT))
	rl.DrawLineV({0, bar.y}, {bar.width, bar.y}, color_of(FORGE_LINE))

	message, color := f.ui.hint, FORGE_TEXT_DIM
	if refusal := ui_refusal(&f.ui); len(refusal) > 0 {
		message, color = refusal, FORGE_FAULT
	}
	if f.copied > 0 {
		message, color = fmt.tprintf("copied %d bytes of Odin to the clipboard", f.copied), FORGE_PASS
	}
	draw_text(message, FORGE_PAD, bar.y + 6, color_of(color))

	right := fmt.tprintf(
		"Ctrl+C copy as Odin   Ctrl+Z undo (%d)   Ctrl+Y redo (%d)   Tab moves   %d fps",
		f.undo.pos,
		f.undo.len - f.undo.pos - 1,
		rl.GetFPS(),
	)
	draw_text(right, bar.width - text_width(right) - FORGE_PAD, bar.y + 6, color_of(FORGE_TEXT_DIM))
}

// forge_history_keys answers Ctrl+Z / Ctrl+Y. Undo is what makes every edit in the tool
// reversible, and reversible is what buys the absence of confirm dialogs.
@(private = "file")
forge_history_keys :: proc(f: ^Forge) -> (restored: bool) {
	if !(rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)) {
		return false
	}
	shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
	if rl.IsKeyPressed(.Z) && !shift {
		if state, ok := undo_undo(&f.undo); ok {
			f.content = state
			return true
		}
	}
	if rl.IsKeyPressed(.Y) || (rl.IsKeyPressed(.Z) && shift) {
		if state, ok := undo_redo(&f.undo); ok {
			f.content = state
			return true
		}
	}
	return false
}

// forge_copy_keys is the accelerator every surface ends in: Ctrl+C puts the current row's
// Odin source on the clipboard. Which row that is depends on the screen, so each surface
// answers forge_emit for itself.
@(private = "file")
forge_copy_keys :: proc(f: ^Forge) {
	if !(rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)) || !rl.IsKeyPressed(.C) {
		return
	}
	source := forge_emit(f)
	rl.SetClipboardText(fmt.ctprintf("%s", source))
	f.copied = len(source)
}

// forge_emit is the source the current surface would hand over. Split from the copy key so
// each surface can also render it, which is what makes the emit inspectable rather than a
// clipboard the author has to paste somewhere to read.
forge_emit :: proc(f: ^Forge) -> string {
	switch f.screen {
	case .Item_Workbench:
		return workbench_emit(f)
	case .Encounter_Builder:
		return builder_emit(f)
	case .Rosters:
		return rosters_emit(f)
	case .Ship_And_Constants:
		return "// the ship template and the balance constants are read-only in the Forge"
	}
	unreachable()
}

// forge_columns lays a screen's area out as two or three resizable panes and handles the
// dividers between them. The split is stored per screen as fractions, so it survives a
// window resize as a proportion rather than as a pixel column.
forge_columns :: proc(f: ^Forge, area: rl.Rectangle, count: int) -> (cols: [3]rl.Rectangle) {
	split := &f.split[f.screen]
	if count == 2 {
		split[1] = 1
	}

	edges: [2]f32
	for i in 0 ..< count - 1 {
		split[i] = clamp(split[i], 0.15, 0.85)
		if i > 0 {
			split[i] = max(split[i], split[i - 1] + 0.1)
		}
		edges[i] = area.x + area.width * split[i]
	}

	left := area.x
	for i in 0 ..< count {
		right := i < count - 1 ? edges[i] : area.x + area.width
		cols[i] = rl.Rectangle{left, area.y, right - left - (i < count - 1 ? SPLITTER_W : 0), area.height}
		left = right + (i < count - 1 ? SPLITTER_W : 0)
	}

	dragging, is_dragging := f.drag.?
	for i in 0 ..< count - 1 {
		handle := rl.Rectangle{edges[i] - SPLITTER_W, area.y, SPLITTER_W * 2, area.height}
		hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), handle)
		if hovered && rl.IsMouseButtonPressed(.LEFT) {
			f.drag, dragging, is_dragging = i, i, true
		}
		if is_dragging && dragging == i {
			split[i] = clamp((rl.GetMousePosition().x - area.x) / area.width, 0.15, 0.85)
		}
		rl.DrawRectangleRec(
			{edges[i] - SPLITTER_W, area.y, SPLITTER_W, area.height},
			color_of((is_dragging && dragging == i) || hovered ? FORGE_ACCENT : FORGE_LINE),
		)
	}
	if rl.IsMouseButtonReleased(.LEFT) {
		f.drag = nil
	}
	return
}

// forge_rows splits a pane into two stacked panes at a fixed proportion. Used where a
// surface has a subordinate read-out (an emit preview, a bake result) that belongs under
// its editor rather than behind a tab.
forge_rows :: proc(area: rl.Rectangle, top_fraction: f32) -> (top: rl.Rectangle, bottom: rl.Rectangle) {
	height := area.height * top_fraction
	top = rl.Rectangle{area.x, area.y, area.width, height - FORGE_GAP}
	bottom = rl.Rectangle{area.x, area.y + height, area.width, area.height - height}
	return
}

// forge_rows_bottom splits a pane into a stretchy top and a fixed-height bottom. Used
// where the lower pane's content has a known size (an emit read-out is a handful of
// lines) and every pixel above it is worth more to the panel that stretches.
forge_rows_bottom :: proc(area: rl.Rectangle, bottom_height: f32) -> (top: rl.Rectangle, bottom: rl.Rectangle) {
	height := min(bottom_height, area.height)
	top = rl.Rectangle{area.x, area.y, area.width, area.height - height - FORGE_GAP}
	bottom = rl.Rectangle{area.x, area.y + area.height - height, area.width, height}
	return
}

// verdict_color is the tool's one mapping from an authored row's standing to a colour:
// clean is pass, anything roster_check names is fault. There is no third state, because
// the check reports one fault or none.
verdict_color :: proc(verdict: ship.Roster_Verdict) -> u32 {
	return verdict.fault == .None ? FORGE_PASS : FORGE_FAULT
}

// enum_options joins an enum's member names into the semicolon-separated list a combo box
// reads, so no screen transcribes a member list that the compiler already knows.
enum_options :: proc(T: typeid) -> (options: string, count: int) {
	names := reflect.enum_field_names(T)
	b := strings.builder_make(context.temp_allocator)
	for name, index in names {
		if index > 0 {
			strings.write_byte(&b, ';')
		}
		strings.write_string(&b, name)
	}
	return strings.to_string(b), len(names)
}
