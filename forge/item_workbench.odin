package forge

import "core:fmt"
import ship "../core/ship"
import rl "vendor:raylib"

// Surface 1: the Item Workbench. The roster as a table, one item's whole authored field
// set beside it, and the power budget beside that — all three visible at once, because
// balancing is comparing an item against its neighbours and against its allowance at the
// same time.
//
// The `Fitting` field set is **closed**, so this pane exposes exactly those fields and
// nothing else. `cargo_held` is the fitting's one mutable instance field and is not
// authored, so it does not appear here at all.

// Workbench is the surface's own view state: which row is selected, what the roster list
// is filtered to, and where the effect and expression editors have their cursors.
Workbench :: struct {
	selected:    int,
	scroll:      int,
	filter:      Name,
	tier:        int,
	size:        int,
	tag:         int,
	verb:        int,
	sort:        int,
	faults_only: bool,
	effect:      int,
	node:        int,
	preset:      int,
	threshold:   int,
	magnitude:   int,
	probe:       Probe,
}

workbench_init :: proc() -> Workbench {
	return Workbench{probe = probe_default()}
}

workbench_draw :: proc(f: ^Forge, area: rl.Rectangle) {
	cols := forge_columns(f, area, 3)

	roster_pane(f, cols[0])

	detail, effects := forge_rows(cols[1], 0.42)
	item_pane(f, detail)
	effect_pane(f, effects)

	budget, rest := forge_rows(cols[2], 0.52)
	readings, emit := forge_rows_bottom(rest, 88)
	budget_pane(f, budget)
	readings_pane(f, readings)
	emit_pane(f, emit, workbench_emit(f))
}

workbench_emit :: proc(f: ^Forge) -> string {
	if f.workbench.selected >= f.content.item_count {
		return ""
	}
	draft := f.content.items[f.workbench.selected]
	source := emit_item(draft)
	if draft.appended {
		return fmt.tprintf("// append to ship_item_roster, and bump the count:\n%s\n\n%s", source, emit_roster_size(f.content.item_count))
	}
	if item_moves_a_seed(f.content, f.workbench.selected) {
		return fmt.tprintf(ITEM_SEED_WARNING, f.workbench.selected, source)
	}
	return fmt.tprintf("// replaces roster row %d in place\n%s", f.workbench.selected, source)
}

// ITEM_SEED_WARNING is what an edit to an **existing** row costs. The edit moves no index
// — the Forge only ever appends — but a shop's shelf and an Offer's options are drawn by
// indexing this table, so every seed that already dealt this row now deals something else.
ITEM_SEED_WARNING :: "// WARNING: this replaces roster row %d, so every seed that draws it now deals a different item\n%s"

// item_moves_a_seed reports whether the draft has been edited away from the roster row it
// was loaded from.
item_moves_a_seed :: proc(c: Content, index: int) -> bool {
	if index >= ship.ITEM_ROSTER_SIZE || c.items[index].appended {
		return false
	}
	return c.items[index].item != ship.ship_item_roster()[index]
}

// workbench_item is the row under edit. Every field control writes straight through this
// pointer, which is what makes the budget panel beside it recompute on the same frame, and
// every pane on this surface asks for it here rather than re-deriving the clamp.
workbench_item :: proc(f: ^Forge) -> ^Item_Draft {
	f.workbench.selected = clamp(f.workbench.selected, 0, max(f.content.item_count - 1, 0))
	return &f.content.items[f.workbench.selected]
}

// roster_pane is the whole roster in roster order — the order an Offer and a shop index
// it — filtered, and summarised by grant cell underneath.
@(private = "file")
roster_pane :: proc(f: ^Forge, bounds: rl.Rectangle) {
	inner := panel(bounds, fmt.tprintf("Roster  (%d items)", f.content.item_count))
	form := form_begin(inner)

	filter_row := form_row(&form)
	draw_text("filter", filter_row.x, filter_row.y + 5, color_of(FORGE_TEXT_DIM))
	ui_name(
		&f.ui,
		{filter_row.x + 40, filter_row.y, filter_row.width - 40, filter_row.height},
		&f.workbench.filter,
		"type to filter the roster by name",
	)

	facets := form_row(&form)
	width := (facets.width - 3 * FORGE_GAP) / 4
	tier_options, tier_count := filter_options(ship.Tier)
	size_options, size_count := filter_options(ship.Slot_Size)
	tag_options, tag_count := filter_options(ship.Tag)
	verb_options, verb_count := filter_options(ship.Verb)
	ui_enum(&f.ui, {facets.x, facets.y, width, facets.height}, tier_options, &f.workbench.tier, tier_count, "filter by tier")
	ui_enum(&f.ui, {facets.x + width + FORGE_GAP, facets.y, width, facets.height}, size_options, &f.workbench.size, size_count, "filter by slot size")
	ui_enum(&f.ui, {facets.x + 2 * (width + FORGE_GAP), facets.y, width, facets.height}, tag_options, &f.workbench.tag, tag_count, "filter by tag")
	ui_enum(&f.ui, {facets.x + 3 * (width + FORGE_GAP), facets.y, width, facets.height}, verb_options, &f.workbench.verb, verb_count, "filter by verb")

	fault_row := form_row(&form)
	ui_check(&f.ui, {fault_row.x, fault_row.y, 14, 14}, "faults only", &f.workbench.faults_only, "show only items roster_check reports a fault for")
	ui_enum(
		&f.ui,
		{fault_row.x + 96, fault_row.y, 132, fault_row.height},
		"sort: roster;sort: name;sort: tier;sort: size;sort: weight;sort: cost;sort: fault",
		&f.workbench.sort,
		len(Roster_Sort),
		"sorts the view only; the # column stays the roster index, which is what a seed draws by",
	)
	if ui_button(&f.ui, {fault_row.x + fault_row.width - 96, fault_row.y, 96, fault_row.height}, "+ append item", "append a new item at the end of the roster") {
		if index, ok := content_append_item(&f.content); ok {
			f.workbench.selected = index
		}
	}

	summary_height := f32(5 * FORGE_ROW)
	table := form_remaining(&form)
	table.height -= summary_height
	roster_table(f, table)
	roster_summary(f, {table.x, table.y + table.height, table.width, summary_height})
}

// Filtered is the roster reduced to the rows the facets admit, ordered by the sort key. A
// fixed array rather than a dynamic one: the roster's bound is the tool's bound.
Filtered :: struct {
	index: [FORGE_MAX_ITEMS]int,
	count: int,
}

// roster_filter is the view the table draws: the rows the facets admit, in the sort key's
// order. Rebuilt every frame, so a filter is applied the moment it is typed.
roster_filter :: proc(f: ^Forge) -> (out: Filtered) {
	w := f.workbench
	for i in 0 ..< f.content.item_count {
		draft := f.content.items[i]
		if !text_contains_fold(name_text(draft.name), name_text(w.filter)) {
			continue
		}
		if w.tier > 0 && int(draft.item.tier) != w.tier - 1 {
			continue
		}
		if w.size > 0 && int(draft.item.fitting.size) != w.size - 1 {
			continue
		}
		if w.tag > 0 && ship.Tag(w.tag - 1) not_in draft.item.fitting.tags {
			continue
		}
		if w.verb > 0 && !item_has_verb(draft.item.fitting, ship.Verb(w.verb - 1)) {
			continue
		}
		if w.faults_only && ship.roster_check(draft.item).fault == .None {
			continue
		}
		out.index[out.count] = i
		out.count += 1
	}
	roster_sort(f, &out)
	return
}

// Roster_Sort is the key the roster view is ordered by. **Roster order is the default and
// is not a preference**: it is the order an Offer and a shop index the table by, so it is
// the order an author reasons about seeds in. Every other key reorders the view alone —
// the index column keeps showing the roster index.
Roster_Sort :: enum {
	Roster,
	Name,
	Tier,
	Size,
	Weight,
	Cost,
	Fault,
}

@(private = "file")
roster_sort :: proc(f: ^Forge, filtered: ^Filtered) {
	sort := Roster_Sort(clamp(f.workbench.sort, 0, len(Roster_Sort) - 1))
	if sort == .Roster {
		return
	}
	// Insertion sort: the roster is fifty-odd rows, it is re-sorted once a frame, and
	// insertion is stable — so rows that tie on the key stay in roster order behind it.
	for i in 1 ..< filtered.count {
		index := filtered.index[i]
		k := i
		for k > 0 && roster_sorts_before(f, index, filtered.index[k - 1], sort) {
			filtered.index[k] = filtered.index[k - 1]
			k -= 1
		}
		filtered.index[k] = index
	}
}

@(private = "file")
roster_sorts_before :: proc(f: ^Forge, a: int, b: int, sort: Roster_Sort) -> bool {
	left, right := f.content.items[a], f.content.items[b]
	switch sort {
	case .Roster:
		return false
	case .Name:
		return name_text(left.name) < name_text(right.name)
	case .Tier:
		return left.item.tier < right.item.tier
	case .Size:
		return left.item.fitting.size < right.item.fitting.size
	case .Weight:
		return left.item.fitting.weight < right.item.fitting.weight
	case .Cost:
		return ship.roster_check(left.item).cost > ship.roster_check(right.item).cost
	case .Fault:
		return ship.roster_check(left.item).fault != .None && ship.roster_check(right.item).fault == .None
	}
	unreachable()
}

@(private = "file")
item_has_verb :: proc(fitting: ship.Fitting, verb: ship.Verb) -> bool {
	for i in 0 ..< fitting.effect_count {
		if fitting.effects[i].verb == verb {
			return true
		}
	}
	return false
}

// roster_table draws one row per admitted item: its index, name, cell, weight, tags,
// effect count and its budget verdict as a colour. The columns are drawn on the mono step
// so the numeric ones stack.
@(private = "file")
roster_table :: proc(f: ^Forge, bounds: rl.Rectangle) {
	filtered := roster_filter(f)
	visible := int(bounds.height / FORGE_ROW) - 1
	focused := ui_focus_region(&f.ui, bounds, "up/down selects, home/end jumps; the colour is roster_check's verdict")

	walked := false
	if focused {
		row := roster_row_of(filtered, f.workbench.selected)
		before := row
		if key_pressed(.DOWN) {
			row += 1
		}
		if key_pressed(.UP) {
			row -= 1
		}
		if key_pressed(.PAGE_DOWN) {
			row += visible
		}
		if key_pressed(.PAGE_UP) {
			row -= visible
		}
		if rl.IsKeyPressed(.HOME) {
			row = 0
		}
		if rl.IsKeyPressed(.END) {
			row = filtered.count - 1
		}
		walked = row != before
		if filtered.count > 0 {
			f.workbench.selected = filtered.index[clamp(row, 0, filtered.count - 1)]
		}
	}

	if rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds) {
		f.workbench.scroll -= int(rl.GetMouseWheelMove()) * 3
	}

	// The window follows the cursor only when the cursor moved: the wheel is free to look
	// somewhere else in the roster without dragging the selection along behind it.
	if walked {
		selected_row := roster_row_of(filtered, f.workbench.selected)
		f.workbench.scroll = clamp(f.workbench.scroll, max(selected_row - visible + 1, 0), max(selected_row, 0))
	}
	f.workbench.scroll = clamp(f.workbench.scroll, 0, max(filtered.count - visible, 0))

	right := bounds.x + bounds.width
	header := bounds.y
	draw_text("#", bounds.x + 2, header, color_of(FORGE_TEXT_DIM))
	draw_text("item", bounds.x + 26, header, color_of(FORGE_TEXT_DIM))
	draw_mono_right("wt", right - 96, header, color_of(FORGE_TEXT_DIM))
	draw_mono_right("fx", right - 66, header, color_of(FORGE_TEXT_DIM))
	draw_mono_right("cost", right - 8, header, color_of(FORGE_TEXT_DIM))
	rl.DrawLineV({bounds.x, header + FORGE_ROW - 4}, {right, header + FORGE_ROW - 4}, color_of(FORGE_LINE))

	for row in f.workbench.scroll ..< min(f.workbench.scroll + visible, filtered.count) {
		index := filtered.index[row]
		draft := f.content.items[index]
		verdict := ship.roster_check(draft.item)
		y := bounds.y + f32(row - f.workbench.scroll + 1) * FORGE_ROW

		if index == f.workbench.selected {
			rl.DrawRectangleRec({bounds.x, y - 2, bounds.width, FORGE_ROW}, color_of(FORGE_PANEL_ALT))
		}
		if rl.IsMouseButtonPressed(.LEFT) &&
		   rl.CheckCollisionPointRec(rl.GetMousePosition(), {bounds.x, y - 2, bounds.width, FORGE_ROW}) {
			f.workbench.selected = index
		}

		rl.DrawRectangleRec({bounds.x, y, 3, FORGE_ROW - 6}, color_of(verdict_color(verdict)))
		draw_mono(fmt.tprintf("%2d", index), bounds.x + 6, y, color_of(FORGE_TEXT_DIM))
		draw_text(
			fmt.tprintf("%s  %v/%v  %s", name_text(draft.name), draft.item.tier, draft.item.fitting.size, tags_text(draft.item.fitting.tags)),
			bounds.x + 26,
			y,
			color_of(index == f.workbench.selected ? FORGE_TEXT : FORGE_TEXT_DIM),
		)
		draw_mono_right(fmt.tprintf("%d", draft.item.fitting.weight), right - 96, y, color_of(FORGE_TEXT_DIM))
		draw_mono_right(fmt.tprintf("%d", draft.item.fitting.effect_count), right - 66, y, color_of(FORGE_TEXT_DIM))
		draw_mono_right(points_text(verdict.cost), right - 8, y, color_of(verdict_color(verdict)))
	}
}

@(private = "file")
roster_row_of :: proc(filtered: Filtered, item: int) -> int {
	for row in 0 ..< filtered.count {
		if filtered.index[row] == item {
			return row
		}
	}
	return 0
}

// roster_summary counts the roster into the grant cells the budget licenses it by, and
// calls out the thin ones — a cell with almost nothing in it is a shelf an Offer or a shop
// can barely deal from.
@(private = "file")
roster_summary :: proc(f: ^Forge, bounds: rl.Rectangle) {
	cells: [ship.Slot_Size][ship.Tier]int
	for i in 0 ..< f.content.item_count {
		item := f.content.items[i].item
		cells[item.fitting.size][item.tier] += 1
	}

	rl.DrawLineV({bounds.x, bounds.y}, {bounds.x + bounds.width, bounds.y}, color_of(FORGE_LINE))
	draw_text("items per grant cell", bounds.x, bounds.y + 4, color_of(FORGE_TEXT_DIM))
	column := bounds.x + 90
	for tier in ship.Tier {
		draw_mono_right(fmt.tprintf("%v", tier), column + 56, bounds.y + 4, color_of(FORGE_TEXT_DIM))
		column += 62
	}
	for size, row in ship.Slot_Size {
		y := bounds.y + f32(row + 1) * FORGE_ROW - 2
		draw_text(fmt.tprintf("%v", size), bounds.x, y, color_of(FORGE_TEXT_DIM))
		column = bounds.x + 90
		for tier in ship.Tier {
			count := cells[size][tier]
			// A cell with fewer than three entries cannot vary what it deals; that is a
			// thin shelf, not a fault, so it warns rather than faults.
			color := count < 3 ? FORGE_WARN : FORGE_TEXT
			draw_mono_right(fmt.tprintf("%d", count), column + 56, y, color_of(color))
			column += 62
		}
	}
}

// item_pane is the closed field set: exactly what a Fitting authors, and its derived
// read-outs beside it.
@(private = "file")
item_pane :: proc(f: ^Forge, bounds: rl.Rectangle) {
	draft := workbench_item(f)
	fitting := &draft.item.fitting
	inner := panel(bounds, "Item")
	form := form_begin(inner)

	name_field := form_field(&form, "name")
	ui_name(&f.ui, name_field, &draft.name, "the authored name; it must not collide with an item or a Trade axis")
	if draft.name.len == 0 {
		form_note(&form, "unnamed: roster_check stops at Roster_Fault.Unnamed", FORGE_FAULT)
	} else if content_name_collides(f.content, name_text(draft.name), f.workbench.selected) {
		form_note(&form, "that name is already taken by another item or a Trade axis", FORGE_FAULT)
	}
	if item_moves_a_seed(f.content, f.workbench.selected) {
		form_note(&form, fmt.tprintf("edited: every seed that draws roster index %d now deals a different item", f.workbench.selected), FORGE_WARN)
	}

	tier_options, tier_count := enum_options(ship.Tier)
	tier := int(draft.item.tier)
	if ui_enum(&f.ui, form_field(&form, "tier"), tier_options, &tier, tier_count, "weakest to strongest; also the shop price ladder") {
		draft.item.tier = ship.Tier(tier)
	}
	size_options, size_count := enum_options(ship.Slot_Size)
	size := int(fitting.size)
	if ui_enum(&f.ui, form_field(&form, "size"), size_options, &size, size_count, "the slot size this item fits, exactly") {
		fitting.size = ship.Slot_Size(size)
		// Bulk is a volume inside a slot, so a size change re-bounds it rather than
		// leaving a value the new slot cannot hold.
		fitting.bulk = clamp(fitting.bulk, 0, ship.ship_cargo_slot_contribution(fitting.size))
	}

	weight_low, weight_high := ship.budget_weight_band(fitting.size)
	weight_field := form_field(&form, "weight", 72)
	ui_value(&f.ui, weight_field, &fitting.weight, weight_low, weight_high, "weight earns allowance above the size default and spends it below")
	draw_text(
		fmt.tprintf("band %d to %d, default %d", weight_low, weight_high, ship.WEIGHT_DEFAULT[fitting.size]),
		weight_field.x + weight_field.width + FORGE_GAP,
		weight_field.y + 5,
		color_of(FORGE_TEXT_DIM),
	)

	ui_tag_set(&f.ui, form_field(&form, "tags"), &fitting.tags, "a fitting's family membership; multi-tag is allowed")

	contribution := ship.ship_cargo_slot_contribution(fitting.size)
	bulk_field := form_field(&form, "bulk", 72)
	ui_value(&f.ui, bulk_field, &fitting.bulk, 0, contribution, "the volume the item's own machinery takes; capacity is the leftover")
	draw_text(
		fmt.tprintf("0 to %d - %d carries nothing", contribution, contribution),
		bulk_field.x + bulk_field.width + FORGE_GAP,
		bulk_field.y + 5,
		color_of(FORGE_TEXT_DIM),
	)

	exposed_row := form_field(&form, "requires exposed")
	ui_check(&f.ui, {exposed_row.x, exposed_row.y + 2, 12, 12}, "may only install in an exposed slot", &fitting.requires_exposed, "an item that must be seen to work refuses a concealed slot")

	form_line(&form, "derived")
	capacity := ship.ship_fitting_capacity(fitting^)
	ui_derived(form_field(&form, "capacity", 72), fmt.tprintf("%d", capacity), "contribution - bulk")
	ui_derived(form_field(&form, "speed cost", 72), fmt.tprintf("%d", -(fitting.weight / 10)), "weight/10, subtracted from effective Speed")
	ui_derived(form_field(&form, "shop cost", 72), fmt.tprintf("%d", ship.ship_item_cost(draft.item.tier)), "ITEM_COST by tier, in cargo")
	ui_derived(form_field(&form, "fitting weight", 72), fmt.tprintf("%d", ship.ship_fitting_weight(fitting^)), "authored mass plus cargo stowed; cargo_held is not authored")
}

// emit_pane renders the source the surface would copy. Showing it rather than only
// copying it is what makes an emit inspectable — an author reads the line before pasting.
emit_pane :: proc(f: ^Forge, bounds: rl.Rectangle, source: string) {
	inner := panel(bounds, "Copy as Odin  (Ctrl+C)")
	y := inner.y
	line_start := 0
	for i in 0 ..= len(source) {
		if i < len(source) && source[i] != '\n' {
			continue
		}
		wrap_text(source[line_start:i], inner.x, &y, inner.width, inner.y + inner.height)
		line_start = i + 1
	}
}

// wrap_text lays one emitted line out across the pane, breaking on width. Emitted source
// is long and the pane is narrow, and a line that ran off the edge would hide the part an
// author most wants to check.
@(private = "file")
wrap_text :: proc(text: string, x: f32, y: ^f32, width: f32, bottom: f32) {
	per_line := max(int(width / mono_advance), 8)
	for start := 0; start < max(len(text), 1); start += per_line {
		if y^ > bottom - FORGE_TEXT_SIZE {
			return
		}
		draw_mono(text[start:min(start + per_line, len(text))], x, y^, color_of(FORGE_TEXT))
		y^ += FORGE_TEXT_SIZE + 2
	}
}

// filter_options prefixes an enum's members with "any", which is the facet's zero value —
// a filter that admits everything is the state the list starts in.
@(private = "file")
filter_options :: proc(T: typeid) -> (options: string, count: int) {
	members, member_count := enum_options(T)
	return fmt.tprintf("any;%s", members), member_count + 1
}

// tags_text writes a tag set the way the table reads it: initials, in Tag order.
tags_text :: proc(tags: bit_set[ship.Tag]) -> string {
	text := ""
	for tag in ship.Tag {
		if tag in tags {
			text = fmt.tprintf("%s%c", text, fmt.tprintf("%v", tag)[0])
		}
	}
	return text
}

// text_contains_fold is the type-to-filter match: an ASCII case-insensitive substring
// test, so an author types "gun" and finds "Naval Gun Crew".
text_contains_fold :: proc(haystack: string, needle: string) -> bool {
	if len(needle) == 0 {
		return true
	}
	if len(needle) > len(haystack) {
		return false
	}
	for start in 0 ..= len(haystack) - len(needle) {
		matched := true
		for i in 0 ..< len(needle) {
			if fold(haystack[start + i]) != fold(needle[i]) {
				matched = false
				break
			}
		}
		if matched {
			return true
		}
	}
	return false
}

@(private = "file")
fold :: proc(b: u8) -> u8 {
	return b >= 'A' && b <= 'Z' ? b + 32 : b
}
