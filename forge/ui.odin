package forge

import "core:fmt"
import ship "../core/ship"
import rl "vendor:raylib"

// The widget layer: raygui controls wrapped in a focus ring so every form in the tool is
// operable from the keyboard.
//
// **Mouse-only is a failure state**, so focus is a first-class thing here rather than a
// raygui afterthought: widgets claim a sequential id in draw order, Tab and Shift+Tab walk
// that order, and the focused widget takes the arrow keys, Space and Enter itself. The
// ids are positional — the same form drawn the same way claims the same ids every frame —
// which is what lets an immediate-mode UI carry focus across frames with one int.
//
// Closed enums are edited with a **combo box rather than a dropdown**: a dropdown's open
// list is a popup that covers whatever is beneath it, and nothing important in this tool
// is allowed to disappear behind something else. A combo cycles in place, shows its
// position in the set, and takes Left/Right from the keyboard.

// Ui is the per-session widget state: where focus is, which control is taking text, and
// what the status bar should say about it.
Ui :: struct {
	next_id:     int,
	focus:       int,
	count:       int,
	// edit is which widget is taking text, absent when none is — the one control whose
	// keystrokes belong to it rather than to the focus walk.
	edit:        Maybe(int),
	hint:        string,
	refusal_buf: [192]u8,
	refusal_len: int,
}

ui_frame_begin :: proc(u: ^Ui) {
	u.next_id = 0
	u.hint = ""
}

// ui_is_editing reports whether `id` is the widget currently taking text.
ui_is_editing :: proc(u: ^Ui, id: int) -> bool {
	editing, taking := u.edit.?
	return taking && editing == id
}

// ui_toggle_edit hands the text focus to `id`, or takes it back if `id` already had it.
ui_toggle_edit :: proc(u: ^Ui, id: int) {
	u.edit = ui_is_editing(u, id) ? nil : Maybe(int)(id)
}

// ui_frame_end settles the frame's focus: Tab walks the ids the frame actually claimed,
// so a screen that drew fewer controls than the last one cannot leave focus past the end.
ui_frame_end :: proc(u: ^Ui) {
	u.count = u.next_id
	if u.count == 0 {
		return
	}
	if key_pressed(.TAB) {
		u.edit = nil
		step := (rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)) ? -1 : 1
		u.focus = (u.focus + step + u.count) % u.count
	}
	u.focus = clamp(u.focus, 0, u.count - 1)
}

// ui_reset_focus puts focus back at the top of the form. Called when the screen or the
// selected row changes, since the id order those controls sit in has changed with it.
ui_reset_focus :: proc(u: ^Ui) {
	u.focus = 0
	u.edit = nil
}

// ui_refuse records why an edit was not taken. The refusal names the rule rather than the
// failure, and it stays on the status bar until the next edit replaces it.
ui_refuse :: proc(u: ^Ui, fault: Edit_Fault) {
	if fault == .None {
		return
	}
	text := fmt.tprintf("refused: %s", EDIT_FAULT_REASON[fault])
	u.refusal_len = min(len(text), len(u.refusal_buf))
	copy(u.refusal_buf[:u.refusal_len], text[:u.refusal_len])
}

// ui_refusal is the last refusal as a string. It is held as bytes rather than as the
// formatted string it was built from, because the status bar reads it a frame later, after
// the temp allocator that built it has been reclaimed.
ui_refusal :: proc(u: ^Ui) -> string {
	return string(u.refusal_buf[:u.refusal_len])
}

@(private = "file")
ui_claim :: proc(u: ^Ui, bounds: rl.Rectangle, hint: string) -> (id: int, focused: bool) {
	id = u.next_id
	u.next_id += 1
	if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds) {
		u.focus = id
	}
	focused = id == u.focus
	if focused {
		u.hint = hint
		rl.DrawRectangleLinesEx(rect_inset(bounds, -2), 1, color_of(FORGE_ACCENT))
	}
	return
}

// ui_focus_region claims a focus id for something that draws itself — a table, a tree —
// rather than for a raygui control. The region takes the arrow keys while it holds focus,
// which is how a list is walked without touching the mouse.
ui_focus_region :: proc(u: ^Ui, bounds: rl.Rectangle, hint := "") -> (focused: bool) {
	_, focused = ui_claim(u, bounds, hint)
	return
}

key_pressed :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}

// ui_enum is the control every closed set is edited through: a combo box over `options`,
// a semicolon-joined list, cycling with the mouse or with Left/Right. Returns whether the
// value moved.
ui_enum :: proc(u: ^Ui, bounds: rl.Rectangle, options: string, value: ^int, count: int, hint := "") -> bool {
	_, focused := ui_claim(u, bounds, hint)

	before := value^
	if focused && count > 1 {
		if key_pressed(.RIGHT) {
			value^ = (value^ + 1) % count
		}
		if key_pressed(.LEFT) {
			value^ = (value^ - 1 + count) % count
		}
	}

	active := i32(value^)
	rl.GuiComboBox(bounds, fmt.ctprintf("%s", options), &active)
	value^ = clamp(int(active), 0, max(count - 1, 0))

	return value^ != before
}

// ui_value is an integer field with a hard range: typed into after Enter, nudged with the
// arrow keys, and clamped to [lo, hi] on the way out. The clamp is an edit-time refusal —
// a bulk outside its slot is not a value the tool lets an author reach.
ui_value :: proc(u: ^Ui, bounds: rl.Rectangle, value: ^int, lo: int, hi: int, hint := "") -> bool {
	id, focused := ui_claim(u, bounds, hint)

	before := value^
	if focused {
		if key_pressed(.UP) {
			value^ += 1
		}
		if key_pressed(.DOWN) {
			value^ -= 1
		}
		if key_pressed(.PAGE_UP) {
			value^ += 10
		}
		if key_pressed(.PAGE_DOWN) {
			value^ -= 10
		}
		if rl.IsKeyPressed(.ENTER) {
			ui_toggle_edit(u, id)
		}
	}

	boxed := i32(clamp(value^, lo, hi))
	if rl.GuiValueBox(bounds, nil, &boxed, i32(lo), i32(hi), ui_is_editing(u, id)) != 0 {
		ui_toggle_edit(u, id)
		u.focus = id
	}
	value^ = clamp(int(boxed), lo, hi)

	return value^ != before
}

ui_check :: proc(u: ^Ui, bounds: rl.Rectangle, text: string, value: ^bool, hint := "") -> bool {
	_, focused := ui_claim(u, bounds, hint)

	before := value^
	if focused && rl.IsKeyPressed(.SPACE) {
		value^ = !value^
	}
	rl.GuiCheckBox(bounds, fmt.ctprintf("%s", text), value)

	return value^ != before
}

// ui_tag_set is the multi-select a bit_set is edited through: one checkbox per member,
// laid out along one row. An item's families and a stock pool's filter are the same
// control over the same set, so they are the same control.
ui_tag_set :: proc(u: ^Ui, bounds: rl.Rectangle, tags: ^bit_set[ship.Tag], hint: string) {
	x := bounds.x
	for tag in ship.Tag {
		held := tag in tags^
		label := fmt.tprintf("%v", tag)
		if ui_check(u, {x, bounds.y + 2, 12, 12}, label, &held, hint) {
			if held {
				tags^ += {tag}
			} else {
				tags^ -= {tag}
			}
		}
		x += 20 + text_width(label)
	}
}

// Reorder is what a row's reorder controls asked for. Order is authoring in both places
// this appears — a recipe's stages and an archetype's item list — so the caller does the
// move itself against whatever it is ordering.
Reorder :: enum {
	None,
	Up,
	Down,
	Remove,
}

REORDER_WIDTH :: 74

ui_reorder :: proc(u: ^Ui, bounds: rl.Rectangle, index: int, count: int, up_hint: string, down_hint: string) -> Reorder {
	action := Reorder.None
	if index > 0 && ui_button(u, {bounds.x, bounds.y, 22, bounds.height}, "up", up_hint) {
		action = .Up
	}
	if index < count - 1 && ui_button(u, {bounds.x + 26, bounds.y, 22, bounds.height}, "dn", down_hint) {
		action = .Down
	}
	if ui_button(u, {bounds.x + 52, bounds.y, 22, bounds.height}, "x", "remove this row") {
		action = .Remove
	}
	return action
}

// ui_name edits an authored name in place. The draft's byte buffer *is* raygui's edit
// buffer, so what the control writes is what content_sync_names re-reads as the name.
ui_name :: proc(u: ^Ui, bounds: rl.Rectangle, n: ^Name, hint := "") -> bool {
	id, focused := ui_claim(u, bounds, hint)

	if focused && rl.IsKeyPressed(.ENTER) {
		ui_toggle_edit(u, id)
	}

	n.len = clamp(n.len, 0, FORGE_NAME_MAX - 1)
	n.buf[n.len] = 0
	if rl.GuiTextBox(bounds, cstring(&n.buf[0]), FORGE_NAME_MAX, ui_is_editing(u, id)) {
		ui_toggle_edit(u, id)
		u.focus = id
	}

	length := 0
	for length < FORGE_NAME_MAX && n.buf[length] != 0 {
		length += 1
	}
	changed := length != n.len
	n.len = length
	name_sync(n)
	return changed
}

ui_button :: proc(u: ^Ui, bounds: rl.Rectangle, text: string, hint := "") -> bool {
	_, focused := ui_claim(u, bounds, hint)
	pressed := rl.GuiButton(bounds, fmt.ctprintf("%s", text))
	if focused && rl.IsKeyPressed(.ENTER) {
		pressed = true
	}
	return pressed
}

// ui_derived draws a field that is **not the author's to set**, with the reason attached.
// A derived or rule-locked field renders rather than disappearing: an absent field says
// nothing, and one that silently ignores input says something false.
ui_derived :: proc(bounds: rl.Rectangle, value: string, reason: string) {
	rl.DrawRectangleRec(bounds, color_of(FORGE_PANEL))
	rl.DrawRectangleLinesEx(bounds, 1, color_of(FORGE_LINE))
	draw_text(value, bounds.x + 4, bounds.y + 5, color_of(FORGE_DERIVED))
	if len(reason) > 0 {
		draw_text(reason, bounds.x + bounds.width + FORGE_GAP, bounds.y + 5, color_of(FORGE_DERIVED))
	}
}

// Form is the layout cursor a pane's fields are laid out on: one column of label/field
// rows on the shared grid, so every form in the tool has its fields in the same places.
Form :: struct {
	bounds: rl.Rectangle,
	y:      f32,
}

form_begin :: proc(bounds: rl.Rectangle) -> Form {
	return Form{bounds = bounds, y = bounds.y}
}

form_row :: proc(f: ^Form) -> rl.Rectangle {
	r := rl.Rectangle{f.bounds.x, f.y, f.bounds.width, FORGE_ROW - 2}
	f.y += FORGE_ROW
	return r
}

// form_field draws a row's caption and hands back the rectangle its control occupies.
form_field :: proc(f: ^Form, label: string, width: f32 = 0) -> rl.Rectangle {
	row := form_row(f)
	draw_text(label, row.x, row.y + 5, color_of(FORGE_TEXT_DIM))
	field := rl.Rectangle{row.x + FORGE_LABEL_W, row.y, row.width - FORGE_LABEL_W, row.height}
	if width > 0 {
		field.width = width
	}
	return field
}

// form_line rules a separator across the form, naming the group it opens.
form_line :: proc(f: ^Form, label: string) {
	f.y += FORGE_GAP
	row := form_row(f)
	rl.GuiLine(row, fmt.ctprintf("%s", label))
}

// form_note writes one line of prose at the cursor — a reason, a finding, a warning.
form_note :: proc(f: ^Form, text: string, color: u32) {
	row := form_row(f)
	draw_text_clipped(text, row.x, row.y + 5, row.width, color_of(color))
}

// form_remaining is what is left of the pane below the cursor, for the one control per
// pane that wants to fill it (a list, a tree, an emit read-out).
form_remaining :: proc(f: ^Form) -> rl.Rectangle {
	return rl.Rectangle{f.bounds.x, f.y, f.bounds.width, max(f.bounds.y + f.bounds.height - f.y, 0)}
}
