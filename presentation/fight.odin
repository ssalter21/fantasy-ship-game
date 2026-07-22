#+private
package presentation

import "core:fmt"
import combat "../core/combat"
import cutaway "./cutaway"
import ship "../core/ship"
import sim "../core/sim"
import rl "vendor:raylib"

// The Fight stage (#315, #305, ADR-0024): the most complex of the five stages, drawn as
// two facing Cutaways broadside-to-broadside — you on the left, the opponent on the right —
// inside the shared encounter frame. It is the design #305 settled:
//
//   - Facing cutaways. Each ship is the same Cutaway as the Build surface (#308) — the
//     deck's exposed stations above a drawn waterline, the belly's holds below — laid out by
//     the cutaway module (fight_ship_region, #426) at a reduced scale so the two ships share
//     the width, the hull painted by draw_build_hull.
//   - Per-slot concealment (ADR-0030). Each slot carries its own seen / concealed badge from
//     its base visibility, decoupled from the waterline (a layout may put a concealed station
//     above the line or an exposed hold below it, and the screen renders exactly that). A
//     scouted opponent's concealed slots read "???" and its hold / weight stay hidden, the same gate
//     draw_ship_panel used; you see your own ship whole.
//   - The captain action-row, no amber. The one-decision-per-round menu is a bottom row of
//     steel controls (a Press per phase while the battle's one Press is unspent, Commit,
//     Jettison, Hold, and Break Off once escape-eligible). Jettison is one order that picks
//     its target in a **second step** — the row is replaced by the laden fittings, and
//     clicking one heaves it — so the order set stays at ADR-0028's five however many holds
//     the ship has. A Fight has no single default move — choosing *is* the game — so none of
//     them takes the reserved amber; hover is carried by the caret + scrim lift, exactly as
//     the Build surface (amber is assigned, not tracked).
//   - Per-round-exchange playback. A round's simultaneous exchange lands as one beat through
//     the shared playback layer (#311): both damage numbers float over their hulls in the
//     Fight hue and both hulls drain together, one click to the next round (ADR-0006). The
//     dispatch-side batching that gathers a round into one beat lives in main.odin's
//     dispatch; the rendering is here.
//
// Split composition (draw_fight_scene) from polling (battle_menu_loop) like the other stages,
// so the beat overlay and --capture both draw the scene without a poll loop (#277).

FIGHT_SHIP_SCALE :: 0.5 // two four-slot decks side by side fit the window only shrunk this far
FIGHT_MARGIN :: 10
FIGHT_CENTER_GAP :: 16
FIGHT_REGION_W :: (WINDOW_WIDTH - 2 * FIGHT_MARGIN - FIGHT_CENTER_GAP) / 2
FIGHT_PLAYER_X :: FIGHT_MARGIN
FIGHT_OPP_X :: FIGHT_MARGIN + FIGHT_REGION_W + FIGHT_CENTER_GAP
FIGHT_STATBLOCK_Y :: 64
FIGHT_DECK_Y :: 150
FIGHT_WATERLINE_Y :: 268
FIGHT_HOLD_Y :: 286
FIGHT_KEEL_Y :: 430
FIGHT_ACTION_TOP :: 470
FIGHT_ACTION_H :: 34
FIGHT_ACTION_MAX :: 16

// Fight_Action_Kind is what clicking a button does. Two of the three submit nothing: the
// Fight asks for its one order across two steps, and moving between them is a click that the
// Sim never hears about.
Fight_Action_Kind :: enum {
	Submit, // send the carried Command as this round's order
	Open_Targets, // Jettison: show the laden fittings, which is where it gets its slot index
	Belay, // leave the target step without heaving anything
}

// Fight_Action is one button of the captain action-row: where it sits, what it reads, what
// clicking it does, and whether it is takeable this round (Break Off is not until
// escape-eligible, and a Press is not once the battle's one Press is spent). `command` is the
// order a .Submit button sends, and is nil on the other two kinds. No amber flag — nothing on
// the Fight is the default, so the row is drawn uniformly steel and only hover lifts a scrim.
Fight_Action :: struct {
	rect:    rl.Rectangle,
	label:   string,
	kind:    Fight_Action_Kind,
	command: combat.Command,
	enabled: bool,
}

// fight_action_commands builds the current step's button list — labels, commands, and which
// are takeable — without laying it out, so what is offered is a pure function of the ship and
// the menu flags, unit-tested without a window (fight_action_layout adds the rects). The Fight
// asks for one order in two steps, and this is the one place that decides which step is
// showing, so the loop and the draw can't disagree about what the row means.
fight_action_commands :: proc(state: ^Game_State) -> (actions: [FIGHT_ACTION_MAX]Fight_Action, n: int) {
	if state.jettison_targeting {
		return fight_target_commands(state)
	}
	return fight_order_commands(state)
}

// fight_order_commands is the captain's order row: ADR-0028's five and nothing else. The
// Presses come from the Phase enum so a new phase would appear automatically, each
// disabled once the battle's one Press is spent; then Commit, Jettison, Hold, and Break Off
// last, disabled until may_break_off. An untakeable order is offered-but-disabled rather than
// dropped: the order set is fixed, so the row is the same length every round however laden the
// ship is. Jettison opens a step rather than submitting, which is what keeps a ship's holds
// from each adding a button here.
fight_order_commands :: proc(state: ^Game_State) -> (actions: [FIGHT_ACTION_MAX]Fight_Action, n: int) {
	for category in ship.Phase {
		fight_add_action(&actions, &n, fmt.tprintf("Press %v", category), .Submit, combat.Command(combat.Command_Press{phase = category}), state.may_press)
	}
	fight_add_action(&actions, &n, "Commit", .Submit, combat.Command(combat.Command_Commit{}), true)
	// Nothing aboard to throw over the side means no heave to take, so the order dims rather
	// than opening a step with no targets in it.
	fight_add_action(&actions, &n, "Jettison", .Open_Targets, nil, ship.ship_cargo(state.player) > 0)
	fight_add_action(&actions, &n, "Hold", .Submit, combat.Command(combat.Command_Hold{}), true)
	fight_add_action(&actions, &n, "Break Off", .Submit, combat.Command(combat.Command_Break_Off{}), state.may_break_off)
	return actions, n
}

// fight_target_commands is Jettison's second step: one button per laden fitting, plus a Belay
// to back out. Picking a target *is* the confirmation, so a heave is never confirmed again.
fight_target_commands :: proc(state: ^Game_State) -> (actions: [FIGHT_ACTION_MAX]Fight_Action, n: int) {
	for layout_slot, i in state.player.layout {
		fitting, has_fitting := layout_slot.fitting.?
		// Only a fitting that is actually carrying is a target: an empty one weighs nothing
		// extra, so heaving it would be free Speed (combat_apply_jettison asserts the same).
		if !has_fitting || fitting.cargo_held <= 0 {
			continue
		}
		// Named by the **slot**, not the fitting: every bare hold is called "Cargo", so a row
		// labelled by fitting reads as five identical buttons, while the slot names ("hold 2",
		// "forecastle") are the words the cutaway above is labelled with. A slot too plain to
		// have a name falls back to what fills it.
		berth := layout_slot.slot.name if layout_slot.slot.name != "" else fitting.name
		label := fmt.tprintf("%s (%d)", berth, fitting.cargo_held)
		fight_add_action(&actions, &n, label, .Submit, combat.Command(combat.Command_Jettison_Cargo{slot_index = ship.Slot_Index(i)}), true)
	}
	fight_add_action(&actions, &n, "Belay that", .Belay, nil, true)
	return actions, n
}

fight_add_action :: proc(
	actions: ^[FIGHT_ACTION_MAX]Fight_Action,
	n: ^int,
	label: string,
	kind: Fight_Action_Kind,
	command: combat.Command,
	enabled: bool,
) {
	if n^ >= FIGHT_ACTION_MAX {
		return
	}
	actions[n^] = Fight_Action{label = label, kind = kind, command = command, enabled = enabled}
	n^ += 1
}

FIGHT_ACTION_PAD :: 16
FIGHT_ACTION_GAP :: 10

// fight_action_layout lays the action list into a centred flow of buttons at the bottom of the
// screen, wrapping to a fresh centred row when the next button would overrun the window (the
// starting ship's four laden holds make a nine-button round too wide for one row). Each button
// is sized to its label, so the row reads as an action bar rather than a fixed grid. Measuring
// needs the baked font, so this is the window-side half of fight_action_commands; the loop and
// the draw both call it and get identical rects, the same split offer_shop_shelf_rects uses.
fight_action_layout :: proc(state: ^Game_State) -> (actions: [FIGHT_ACTION_MAX]Fight_Action, n: int) {
	actions, n = fight_action_commands(state)

	widths: [FIGHT_ACTION_MAX]f32
	for i in 0 ..< n {
		widths[i] = rl.MeasureTextEx(ui_font_body, fmt.ctprintf("%s", actions[i].label), UI_BODY_SIZE, 1).x + 2 * FIGHT_ACTION_PAD
	}

	row_max := f32(WINDOW_WIDTH - 2 * FIGHT_MARGIN)

	// place_row centres one run of buttons [from, to) on its own row and assigns their rects.
	place_row :: proc(actions: ^[FIGHT_ACTION_MAX]Fight_Action, widths: [FIGHT_ACTION_MAX]f32, from, to, row: int) {
		total: f32 = 0
		for i in from ..< to {
			total += widths[i]
		}
		if to - from > 1 {
			total += f32(to - from - 1) * FIGHT_ACTION_GAP
		}
		x := (f32(WINDOW_WIDTH) - total) / 2
		y := f32(FIGHT_ACTION_TOP + row * (FIGHT_ACTION_H + FIGHT_ACTION_GAP))
		for i in from ..< to {
			actions[i].rect = rl.Rectangle{x = x, y = y, width = widths[i], height = FIGHT_ACTION_H}
			x += widths[i] + FIGHT_ACTION_GAP
		}
	}

	row := 0
	row_start := 0
	row_w: f32 = 0
	for i in 0 ..< n {
		add_w := widths[i]
		if i > row_start {
			add_w += FIGHT_ACTION_GAP
		}
		if i > row_start && row_w + add_w > row_max {
			place_row(&actions, widths, row_start, i, row)
			row += 1
			row_start = i
			row_w = widths[i]
		} else {
			row_w += add_w
		}
	}
	place_row(&actions, widths, row_start, n, row)
	return actions, n
}

// battle_menu_loop is the Fight's blocking decision loop (ADR-0006's one-decision-per-round
// menu), the drag-free successor to the old modal button list. It renders the facing cutaways
// and the action row, and returns a Command_Battle_Choice when a takeable button is clicked.
// The picked command is a value (its Jettison slot index and all) so it survives the per-frame
// free_all the action labels are torn down by.
//
// A button carrying no command changes step rather than ending the round (Jettison opens its
// targets, Belay closes them), so the loop keeps polling and the row it draws next frame is
// the other one. Each round opens on the order row, whatever the last one ended on.
battle_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		// The Hold is built through a local rather than inlined into the literal:
		// dev-2026-06 folds a fully-constant *nested* union literal to a nil inner tag, so
		// the inlined form returns a Command_Battle_Choice whose combat_command is nil. A
		// local makes the value non-constant and the tag survives. Inline it once the ci.yml
		// pin moves to a nightly that folds this correctly.
		hold := combat.Command(combat.Command_Hold{})
		return sim.Command(sim.Command_Battle_Choice{combat_command = hold})
	}

	state.jettison_targeting = false

	for {
		window_quit_if_closed()
		mouse := rl.GetMousePosition()

		rl.BeginDrawing()
		draw_fight_scene(state, mouse)
		rl.EndDrawing()

		actions, n := fight_action_layout(state)
		// Only the picked action's `kind` and `command` are read below, both values that
		// survive the per-frame free_all — its label does not, having been formatted into
		// the temp allocator this frame.
		picked: Maybe(Fight_Action)
		if rl.IsMouseButtonPressed(.LEFT) {
			for a in actions[:n] {
				if a.enabled && rl.CheckCollisionPointRec(mouse, a.rect) {
					picked = a
					break
				}
			}
		}
		free_all(context.temp_allocator)

		action, clicked := picked.?
		if !clicked {
			continue
		}
		switch action.kind {
		case .Open_Targets:
			state.jettison_targeting = true
		case .Belay:
			state.jettison_targeting = false
		case .Submit:
			state.jettison_targeting = false
			return sim.Command(sim.Command_Battle_Choice{combat_command = action.command})
		}
	}
}

// draw_fight is draw_fight_scene wrapped in its own Begin/EndDrawing pair, for the callers with
// nothing further to draw on top: --capture's fight shot. The loop and the beat overlay share
// their own pair around draw_fight_scene instead.
draw_fight :: proc(state: ^Game_State, mouse: rl.Vector2) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	draw_fight_scene(state, mouse)
}

// draw_fight_scene composes the whole Fight without a drawing pair of its own, so draw_beat can
// lay the playback overlay over it in the same frame (the shared layer, #311). The two ship
// bodies draw under the vignette; the chrome — stat blocks, header, the round / stage readouts,
// the action row, the view-only chart tab, the stamp — draws over it, so the top-corner type
// isn't sunk into the darkened frame (the same rule draw_encounter_chrome follows). The Fight
// opts out of the shared top-right Hull·SPD·Cargo line: it would float your stats over the
// opponent, and each ship already carries its own stat block (#305).
draw_fight_scene :: proc(state: ^Game_State, mouse: rl.Vector2) {
	rl.ClearBackground(COLOUR_DEEP)

	draw_fight_ship_body(&state.player, FIGHT_PLAYER_X, false)
	if opponent, ok := state.sighted_opponent.?; ok {
		draw_fight_ship_body(&opponent, FIGHT_OPP_X, true)
	}

	draw_vignette()

	draw_fight_statblock(&state.player, FIGHT_PLAYER_X, "Your Ship", false)
	if opponent, ok := state.sighted_opponent.?; ok {
		draw_fight_statblock(&opponent, FIGHT_OPP_X, "Opponent", true)
	}

	draw_encounter_header(.Fight)
	draw_fight_readouts(state)
	draw_fight_action_row(state, mouse)
	draw_encounter_chart_tab()
	draw_chart_table_version_stamp()
}

// fight_ship_region is one ship's half-width cutaway region — the player's or the
// opponent's, told apart only by `area_x`. Spelled once so hull, cards and any hit-test
// read the same cross-section (#426).
fight_ship_region :: proc(area_x: f32) -> cutaway.Region {
	return cutaway.Region {
		x           = area_x,
		w           = FIGHT_REGION_W,
		deck_y      = FIGHT_DECK_Y,
		waterline_y = FIGHT_WATERLINE_Y,
		hold_y      = FIGHT_HOLD_Y,
		keel_y      = FIGHT_KEEL_Y,
		scale       = FIGHT_SHIP_SCALE,
	}
}

// draw_fight_ship_body draws one ship's cutaway — the faint hull, then each slot's card — in
// its region. `gate` is the ADR-0030 concealment gate: true for a scouted opponent, whose
// concealed fittings read "???"; false for your own ship, seen whole.
draw_fight_ship_body :: proc(s: ^ship.Ship, area_x: f32, gate: bool) {
	region := fight_ship_region(area_x)
	draw_build_hull(region)
	rects, n := cutaway.cutaway_slot_rects(s.layout, region)
	for i in 0 ..< n {
		draw_fight_card(rects[i], s.layout[i], gate)
	}
}

// draw_fight_card draws one slot at fight scale: an empty berth as a dashed outline, a masked
// opponent slot as "???", an own or exposed fitting as its name and category chip. Every slot,
// filled or not, carries its per-slot visibility badge (the slot's base visibility), so a
// concealed deck station and an exposed hold each read for what they are, decoupled from
// which row they sit in. The name is clipped to the card (a small card can
// hold "Gun Deck" but not "Captain's Quarters"), keeping text from bleeding into its neighbour.
draw_fight_card :: proc(rect: rl.Rectangle, layout_slot: ship.Layout_Slot, gate: bool) {
	visibility := layout_slot.slot.base_visibility
	fitting, has_fitting := layout_slot.fitting.?

	if !has_fitting {
		draw_build_dashed_rect(rect, COLOUR_STEEL)
		draw_fight_visibility_badge(rect, visibility)
		return
	}

	masked := gate && visibility == .Concealed
	is_hold := ship.ship_fitting_is_hold(fitting)
	rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, 0.55))
	rl.DrawRectangleLinesEx(rect, 2, is_hold && !masked ? COLOUR_BLUE_RECESSIVE : COLOUR_STEEL)

	if masked {
		// A scouted opponent's concealed fitting: its presence shows, its identity does not
		// (the same "???" draw_ship_panel's gate renders). Its hold count / weight stay hidden.
		q := fmt.ctprint("???")
		size := rl.MeasureTextEx(ui_font_body, q, UI_BODY_SIZE, 1)
		rl.DrawTextEx(ui_font_body, q, rl.Vector2{rect.x + (rect.width - size.x) / 2, rect.y + (rect.height - size.y) / 2}, UI_BODY_SIZE, 1, rl.Fade(COLOUR_CREAM, 0.8))
		draw_fight_visibility_badge(rect, visibility)
		return
	}

	rl.BeginScissorMode(i32(rect.x), i32(rect.y), i32(rect.width), i32(rect.height))
	name_tone := is_hold ? rl.Fade(COLOUR_CREAM, 0.75) : COLOUR_CREAM
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", fitting.name), rl.Vector2{rect.x + 8, rect.y + 6}, UI_BODY_SIZE, 1, name_tone)
	if is_hold {
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("holds %d", fitting.cargo_held), rl.Vector2{rect.x + 8, rect.y + rect.height - 26}, UI_BODY_SIZE, 1, COLOUR_STEEL)
	} else {
		draw_build_phase_chip(rl.Vector2{rect.x + 8, rect.y + rect.height - 26}, fitting_phase_label(fitting))
	}
	rl.EndScissorMode()

	draw_fight_visibility_badge(rect, visibility)
}

// draw_fight_visibility_badge marks a slot's visibility with a small eye (seen) or
// struck-through eye (concealed) — a shape, not a font glyph (the guide: glyphs are shapes),
// the same eye idiom draw_build_zone_label uses for the whole zone, here narrowed to the one
// slot because a Fight reads visibility per slot (#305). It sits bottom-right, clear of the
// name (top-left) and the chip / holds line (bottom-left), so a long clipped name never runs
// under it.
draw_fight_visibility_badge :: proc(rect: rl.Rectangle, visibility: ship.Visibility) {
	c := rl.Vector2{rect.x + rect.width - 13, rect.y + rect.height - 13}
	tint := rl.Fade(COLOUR_STEEL, 0.85)
	rl.DrawEllipseLines(i32(c.x), i32(c.y), 7, 4, tint)
	rl.DrawCircleV(c, 1.6, tint)
	if visibility == .Concealed {
		rl.DrawLineEx(rl.Vector2{c.x - 7, c.y + 4}, rl.Vector2{c.x + 7, c.y - 4}, 2, tint)
	}
}

// draw_fight_statblock names a ship and prints its own stats over its cutaway — the source the
// Fight uses instead of the shared frame's one stat line (#305). Your ship shows its cargo; a
// scouted opponent's cargo / weight stay behind the concealment gate (ADR-0030), so its block
// stops at Hull · SPD. Centred over the ship's region, title cream, stats steel.
draw_fight_statblock :: proc(s: ^ship.Ship, area_x: f32, title: string, gate: bool) {
	region := fight_ship_region(area_x)
	centre_x := region.x + region.w / 2

	tctext := fmt.ctprintf("%s", title)
	tsize := rl.MeasureTextEx(ui_font_body, tctext, UI_BODY_SIZE, 1)
	rl.DrawTextEx(ui_font_body, tctext, rl.Vector2{centre_x - tsize.x / 2, FIGHT_STATBLOCK_Y}, UI_BODY_SIZE, 1, COLOUR_CREAM)

	sctext := fmt.ctprintf("%s", ship_stat_line(s, gate))
	ssize := rl.MeasureTextEx(ui_font_body, sctext, UI_BODY_SIZE, 1)
	rl.DrawTextEx(ui_font_body, sctext, rl.Vector2{centre_x - ssize.x / 2, FIGHT_STATBLOCK_Y + 24}, UI_BODY_SIZE, 1, COLOUR_STEEL)
}

// draw_fight_readouts draws the two readouts the Fight adds to the frame (#305): the stage
// position top-right (a position within the encounter, not a preview of upcoming kinds, so it
// keeps #304's no-preview rule) and, top-centre, the round about to be fought with the escape
// window leading and the hard cap (ADR-0006) as a quiet ceiling — because a fight rarely
// reaches it and "/20" alone would misread as a fixed length. Readouts, never amber.
draw_fight_readouts :: proc(state: ^Game_State) {
	if progress, ok := state.stage_progress.?; ok {
		txt := fmt.ctprintf("Stage %d / %d", progress.index + 1, progress.count)
		size := rl.MeasureTextEx(ui_font_body, txt, UI_BODY_SIZE, 1)
		rl.DrawTextEx(ui_font_body, txt, rl.Vector2{WINDOW_WIDTH - size.x - ENCOUNTER_STAT_MARGIN, ENCOUNTER_HEADING.y}, UI_BODY_SIZE, 1, COLOUR_STEEL)
	}

	round_txt := fmt.ctprintf("Round %d", state.battle_round + 1)
	cap_txt := fmt.ctprintf(" / %d", combat.HARD_ROUND_CAP)
	rsize := rl.MeasureTextEx(ui_font_body, round_txt, UI_BODY_SIZE, 1)
	csize := rl.MeasureTextEx(ui_font_body, cap_txt, UI_BODY_SIZE, 1)
	gx := (WINDOW_WIDTH - (rsize.x + csize.x)) / 2
	rl.DrawTextEx(ui_font_body, round_txt, rl.Vector2{gx, ENCOUNTER_HEADING.y}, UI_BODY_SIZE, 1, COLOUR_CREAM)
	rl.DrawTextEx(ui_font_body, cap_txt, rl.Vector2{gx + rsize.x, ENCOUNTER_HEADING.y}, UI_BODY_SIZE, 1, rl.Fade(COLOUR_STEEL, 0.6))

	esc := fmt.ctprintf("%s", fight_escape_text(state))
	esize := rl.MeasureTextEx(ui_font_body, esc, UI_BODY_SIZE, 1)
	rl.DrawTextEx(ui_font_body, esc, rl.Vector2{(WINDOW_WIDTH - esize.x) / 2, ENCOUNTER_HEADING.y + 24}, UI_BODY_SIZE, 1, COLOUR_CYAN_DIM)
}

// fight_escape_text reads the escape window off the round counter and the escape flag: ready
// once may_break_off (ADR-0006's "faster, past the baseline round"), a countdown to the
// baseline until then, and a nudge to outpace the foe once the baseline has passed but the
// speed edge hasn't been won. A string (not a draw) so it is unit-tested without a window.
fight_escape_text :: proc(state: ^Game_State) -> string {
	if state.may_break_off {
		return "Break off ready"
	}
	remaining := combat.BASELINE_ROUND_COUNT - state.battle_round
	if remaining > 0 {
		return fmt.tprintf("escape opens in %d", remaining)
	}
	return "outpace them to break off"
}

// draw_fight_action_row draws the captain action-row from the laid-out list: each takeable
// button a steel-bordered translucent control whose scrim lifts and whose caret appears on
// hover (hover carried by the scrim + caret, not by amber — the amber rule); an untakeable
// order — Break Off before the escape window, a Press after the battle's one is spent, a
// Jettison with nothing aboard to heave — dimmed to recessive blue and un-hoverable. No amber
// anywhere, because a Fight has no default move.
//
// Jettison's target step carries a caption, because the row's meaning changes under it: the
// same buttons now name what goes over the side, and clicking one does it. It is the only
// prompt the heave gets — picking the target is the confirmation.
draw_fight_action_row :: proc(state: ^Game_State, mouse: rl.Vector2) {
	if state.jettison_targeting {
		caption: cstring = "Heave what? There is no getting it back."
		size := rl.MeasureTextEx(ui_font_body, caption, UI_BODY_SIZE, 1)
		rl.DrawTextEx(ui_font_body, caption, rl.Vector2{(WINDOW_WIDTH - size.x) / 2, FIGHT_ACTION_TOP - UI_BODY_SIZE - 8}, UI_BODY_SIZE, 1, COLOUR_STEEL)
	}

	actions, n := fight_action_layout(state)
	for a in actions[:n] {
		hovered := a.enabled && rl.CheckCollisionPointRec(mouse, a.rect)
		if a.enabled {
			rl.DrawRectangleRec(a.rect, rl.Fade(COLOUR_GROUND, hovered ? 0.8 : 0.55))
			rl.DrawRectangleLinesEx(a.rect, 2, COLOUR_STEEL)
		} else {
			rl.DrawRectangleRec(a.rect, rl.Fade(COLOUR_GROUND, 0.4))
			rl.DrawRectangleLinesEx(a.rect, 2, rl.Fade(COLOUR_BLUE_RECESSIVE, 0.7))
		}

		label_tone := a.enabled ? COLOUR_STEEL : rl.Fade(COLOUR_STEEL, 0.4)
		ctext := fmt.ctprintf("%s", a.label)
		size := rl.MeasureTextEx(ui_font_body, ctext, UI_BODY_SIZE, 1)
		rl.DrawTextEx(ui_font_body, ctext, rl.Vector2{a.rect.x + (a.rect.width - size.x) / 2, a.rect.y + (FIGHT_ACTION_H - UI_BODY_SIZE) / 2}, UI_BODY_SIZE, 1, label_tone)

		if hovered {
			draw_caret(rl.Vector2{a.rect.x + 9, a.rect.y + a.rect.height / 2}, COLOUR_STEEL)
		}
	}
}

// dispatch_battle_event routes one combat round event (#315): a damage hit is accumulated into
// the round's exchange so the whole round lands as one beat (fight_flush_exchange), the round's
// closing Round_Resolved lands both hulls as the Event states them (#429); a Ship_Sunk or
// Battle_Ended flushes that pending exchange first and then plays as its own beat; a jettison
// or a repair, which land at round start before any damage, play immediately. Battle_Ended is
// where the in-battle UI state is torn down. Called from dispatch, so it runs on the same
// rawptr-shared Game_State the render loop reads.
dispatch_battle_event :: proc(state: ^Game_State, event: combat.Event) {
	switch e in event {
	case combat.Event_Hull_Repaired:
		// Repair lands ahead of the round's guns (ADR-0027), so it plays as its own beat
		// rather than joining the exchange — showing the hull its event states.
		fight_set_hull(state, e.side, e.hull)
		play_beat(state, battle_event_text(event))
	case combat.Event_Damage_Dealt:
		// The hit is a playback number only: the hulls land from Event_Round_Resolved,
		// so presentation never re-derives a hull from a delta.
		state.pending_exchange[e.target] += e.damage
		state.exchange_active = true
	case combat.Event_Round_Resolved:
		for side in combat.Side {
			fight_set_hull(state, side, e.hull[side])
		}
	case combat.Event_Ship_Sunk:
		fight_flush_exchange(state)
		play_beat(state, battle_event_text(event))
	case combat.Event_Battle_Ended:
		fight_flush_exchange(state)
		play_beat(state, battle_event_text(event))
		state.in_battle = false
		state.sighted_opponent = nil
	case combat.Event_Cargo_Jettisoned:
		play_beat(state, battle_event_text(event))
	}
}

// fight_set_hull lands a side's hull as the Event stated it (#429). Presentation still keeps
// its own copy of both ships as render state — the opponent's has no Event_Ship_Updated to
// carry it, and the player's is kept in step until the authoritative copy re-lands — but every
// value written here comes off the stream, never re-derived or re-clamped (ADR-0001).
fight_set_hull :: proc(state: ^Game_State, side: combat.Side, hull: int) {
	if side == .A {
		state.player.hull = hull
	} else if opponent, ok := state.sighted_opponent.?; ok {
		opponent.hull = hull
		state.sighted_opponent = opponent
	}
}

// fight_flush_exchange plays the one beat a round's exchange earned, if any damage landed:
// both hulls have already drained, so the beat shows them at rest with the round's damage
// numbers floating over each, one click to move on (ADR-0006's simultaneous resolution). A
// no-op when nothing was pending, so a round that lands no damage passes with no beat.
fight_flush_exchange :: proc(state: ^Game_State) {
	if !state.exchange_active {
		return
	}
	dmg_a := state.pending_exchange[.A]
	dmg_b := state.pending_exchange[.B]
	state.pending_exchange[.A] = 0
	state.pending_exchange[.B] = 0
	state.exchange_active = false
	play_round_exchange_beat(state, dmg_a, dmg_b)
}

// play_round_exchange_beat blocks in a short render loop (like play_beat) rendering the fight
// scene under the shared scrim with each side's damage floating over its hull, until the player
// clicks / presses or BEAT_MAX_SECONDS elapses (ADR-0002 / ADR-0022).
play_round_exchange_beat :: proc(state: ^Game_State, dmg_a: int, dmg_b: int) {
	if !rl.IsWindowReady() {
		return
	}
	elapsed: f32
	for {
		window_quit_if_closed()
		elapsed += rl.GetFrameTime()
		draw_fight_exchange(state, dmg_a, dmg_b)
		if elapsed > BEAT_MAX_SECONDS || rl.IsKeyPressed(.SPACE) || rl.IsMouseButtonPressed(.LEFT) {
			return
		}
	}
}

// draw_fight_exchange draws one frame of the round-exchange beat: the fight scene, the shared
// playback scrim over it, then each side's damage number over its hull in the Fight hue —
// drawn over the scrim so it stays bright while the ships dim beneath it. Its own drawing pair,
// like draw_beat; reused by --capture to shoot the beat.
draw_fight_exchange :: proc(state: ^Game_State, dmg_a: int, dmg_b: int) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	draw_fight_scene(state, NO_MOUSE)
	draw_playback_overlay("")
	draw_fight_damage_number(FIGHT_PLAYER_X, dmg_a)
	if _, ok := state.sighted_opponent.?; ok {
		draw_fight_damage_number(FIGHT_OPP_X, dmg_b)
	}
}

// draw_fight_damage_number floats a round's damage over a ship's deck in the Fight hue
// (#A6485A, stage_tint's one warm), at title size for impact — never amber (damage is the
// world talking, not a control to act on). Nothing drawn when the side took no damage. The
// deck line comes off the same region the ship drew in, so the number can't drift from the
// cutaway it floats over.
draw_fight_damage_number :: proc(area_x: f32, damage: int) {
	if damage <= 0 {
		return
	}
	region := fight_ship_region(area_x)
	text := fmt.ctprintf("-%d", damage)
	size := rl.MeasureTextEx(ui_font_title, text, UI_TITLE_SIZE, 1)
	centre_x := region.x + region.w / 2
	rl.DrawTextEx(ui_font_title, text, rl.Vector2{centre_x - size.x / 2, region.deck_y + 20}, UI_TITLE_SIZE, 1, stage_tint(.Fight))
}
