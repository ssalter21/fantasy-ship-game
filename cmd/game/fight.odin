package main

import "core:fmt"
import combat "../../core/combat"
import ship "../../core/ship"
import sim "../../core/sim"
import rl "vendor:raylib"

// The Fight stage (#315, #305, ADR-0024): the most complex of the five stages, drawn as
// two facing Cutaways broadside-to-broadside — you on the left, the opponent on the right —
// inside the shared encounter frame. It is the design #305 settled:
//
//   - Facing cutaways. Each ship is the same Cutaway as the Build surface (#308) — the
//     deck's exposed stations above a drawn waterline, the belly's holds below — reusing
//     build_slot_rects / draw_build_hull at a reduced scale so the two ships share the width.
//   - Per-slot concealment (ADR-0005). Each slot carries its own seen / concealed badge from
//     ship_effective_visibility, decoupled from the waterline (a ship can carry a concealed
//     deck station or a forced-visible hold, and the screen renders exactly that). A scouted
//     opponent's concealed slots read "???" and its hold / weight stay hidden, the same gate
//     draw_ship_panel used; you see your own ship whole.
//   - The captain action-row, no amber. The one-decision-per-round menu is a bottom row of
//     steel controls (Press Muster / Brace / Fire, Man the Sails, a Jettison per laden hold,
//     Break Off once escape-eligible). A Fight has no single default move — choosing *is* the
//     game — so none of them takes the reserved amber; hover is carried by the caret + scrim
//     lift, exactly as the Build surface (amber is assigned, not tracked).
//   - Per-round-exchange playback. A round's simultaneous exchange lands as one beat through
//     the shared playback layer (#311): both damage numbers float over their hulls in the
//     Fight hue and both hulls drain together, one click to the next round (ADR-0006). The
//     dispatch-side batching that gathers a round into one beat lives in main.odin's
//     dispatch; the rendering is here.
//
// In-battle Reallocate retired with the old modal battle_menu_loop (#305): refit is locked in
// a Fight (ADR-0024), and pouring cargo between holds shifts no weight and so no Speed — it
// had no tactical payload. Jettison stays, a real captain move (drop weight, gain Speed to run).
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
FIGHT_HULL_TOP_Y :: FIGHT_DECK_Y - 22
FIGHT_WATERLINE_Y :: 268
FIGHT_HOLD_Y :: 286
FIGHT_KEEL_Y :: 430
FIGHT_ACTION_TOP :: 470
FIGHT_ACTION_H :: 34
FIGHT_ACTION_MAX :: 16

// Fight_Action is one button of the captain action-row: where it sits, what it reads, the
// combat.Command it submits, and whether it is takeable this round (Break Off is not, until
// escape-eligible). No amber flag — nothing on the Fight is the default, so the row is drawn
// uniformly steel and only hover lifts a scrim.
Fight_Action :: struct {
	rect:    rl.Rectangle,
	label:   string,
	command: combat.Command,
	enabled: bool,
}

// fight_action_commands builds the round's action list — labels, commands, and which are
// takeable — without laying it out, so the set of moves offered is a pure function of the
// ship and the escape flag, unit-tested without a window (fight_action_layout adds the rects).
// The three Presses come from the Category enum so a new phase would appear automatically;
// one Jettison per laden hold; Break Off last, disabled until may_break_off. Reallocate is
// gone (#305).
fight_action_commands :: proc(state: ^Game_State) -> (actions: [FIGHT_ACTION_MAX]Fight_Action, n: int) {
	add :: proc(actions: ^[FIGHT_ACTION_MAX]Fight_Action, n: ^int, label: string, command: combat.Command, enabled: bool) {
		if n^ >= FIGHT_ACTION_MAX {
			return
		}
		actions[n^] = Fight_Action{label = label, command = command, enabled = enabled}
		n^ += 1
	}

	for category in ship.Category {
		add(&actions, &n, fmt.tprintf("Press %v", category), combat.Command(combat.Command_Press{phase = category}), true)
	}
	add(&actions, &n, "Man the Sails", combat.Command(combat.Command_Man_The_Sails{}), true)

	for layout_slot, i in state.player.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting || !fitting.is_cargo {
			continue
		}
		add(&actions, &n, fmt.tprintf("Jettison %s", fitting.name), combat.Command(combat.Command_Jettison_Cargo{slot_index = ship.Slot_Index(i)}), true)
	}

	add(&actions, &n, "Break Off", combat.Command(combat.Command_Break_Off{}), state.may_break_off)
	return actions, n
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

	for {
		window_quit_if_closed()
		mouse := rl.GetMousePosition()

		rl.BeginDrawing()
		draw_fight_scene(state, mouse)
		rl.EndDrawing()

		actions, n := fight_action_layout(state)
		picked: Maybe(combat.Command)
		if rl.IsMouseButtonPressed(.LEFT) {
			for a in actions[:n] {
				if a.enabled && rl.CheckCollisionPointRec(mouse, a.rect) {
					picked = a.command
					break
				}
			}
		}
		free_all(context.temp_allocator)

		if cmd, ok := picked.?; ok {
			return sim.Command(sim.Command_Battle_Choice{combat_command = cmd})
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

// draw_fight_ship_body draws one ship's cutaway — the faint hull, then each slot's card — in
// its region. `gate` is the ADR-0005 concealment gate: true for a scouted opponent, whose
// concealed fittings read "???"; false for your own ship, seen whole.
draw_fight_ship_body :: proc(s: ^ship.Ship, area_x: f32, gate: bool) {
	draw_build_hull(area_x, FIGHT_REGION_W, FIGHT_HULL_TOP_Y, FIGHT_WATERLINE_Y, FIGHT_KEEL_Y)
	rects, n := build_slot_rects(s.layout, area_x, FIGHT_REGION_W, FIGHT_DECK_Y, FIGHT_HOLD_Y, FIGHT_SHIP_SCALE)
	for i in 0 ..< n {
		draw_fight_card(rects[i], s.layout[i], gate)
	}
}

// draw_fight_card draws one slot at fight scale: an empty berth as a dashed outline, a masked
// opponent slot as "???", an own or exposed fitting as its name and category chip. Every slot,
// filled or not, carries its per-slot visibility badge (ship_effective_visibility) — the #305
// refinement that a concealed deck station and a forced-visible hold each read for what they
// are, decoupled from which row they sit in. The name is clipped to the card (a small card can
// hold "Gun Deck" but not "Captain's Quarters"), keeping text from bleeding into its neighbour.
draw_fight_card :: proc(rect: rl.Rectangle, layout_slot: ship.Layout_Slot, gate: bool) {
	visibility := ship.ship_effective_visibility(layout_slot)
	fitting, has_fitting := layout_slot.fitting.?

	if !has_fitting {
		draw_build_dashed_rect(rect, COLOUR_STEEL)
		draw_fight_visibility_badge(rect, visibility)
		return
	}

	masked := gate && visibility == .Concealed
	is_cargo := fitting.is_cargo
	rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, 0.55))
	rl.DrawRectangleLinesEx(rect, 2, is_cargo && !masked ? COLOUR_BLUE_RECESSIVE : COLOUR_STEEL)

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
	name_tone := is_cargo ? rl.Fade(COLOUR_CREAM, 0.75) : COLOUR_CREAM
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", fitting.name), rl.Vector2{rect.x + 8, rect.y + 6}, UI_BODY_SIZE, 1, name_tone)
	if is_cargo {
		rl.DrawTextEx(ui_font_body, fmt.ctprintf("holds %d", fitting.stack_count), rl.Vector2{rect.x + 8, rect.y + rect.height - 26}, UI_BODY_SIZE, 1, COLOUR_STEEL)
	} else {
		draw_build_category_chip(rl.Vector2{rect.x + 8, rect.y + rect.height - 26}, fitting.category)
	}
	rl.EndScissorMode()

	draw_fight_visibility_badge(rect, visibility)
}

// draw_fight_visibility_badge marks a slot's effective visibility with a small eye (seen) or
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
// Fight uses instead of the shared frame's one stat line (#305). Your ship shows its hold; a
// scouted opponent's hold / weight stay behind the concealment gate (ADR-0005), so its block
// stops at Hull · DUR · SPD. Centred over the ship's region, title cream, stats steel.
draw_fight_statblock :: proc(s: ^ship.Ship, area_x: f32, title: string, gate: bool) {
	centre_x := area_x + FIGHT_REGION_W / 2

	tctext := fmt.ctprintf("%s", title)
	tsize := rl.MeasureTextEx(ui_font_body, tctext, UI_BODY_SIZE, 1)
	rl.DrawTextEx(ui_font_body, tctext, rl.Vector2{centre_x - tsize.x / 2, FIGHT_STATBLOCK_Y}, UI_BODY_SIZE, 1, COLOUR_CREAM)

	stats: string
	if gate {
		stats = fmt.tprintf("Hull %d/%d · DUR %d · SPD %d", s.hull, s.max_hull, ship.ship_effective_durability(s), ship.ship_effective_speed(s))
	} else {
		stats = fmt.tprintf(
			"Hull %d/%d · DUR %d · SPD %d · Hold %d/%d",
			s.hull,
			s.max_hull,
			ship.ship_effective_durability(s),
			ship.ship_effective_speed(s),
			ship.ship_cargo(s^),
			ship.ship_cargo_capacity(s^),
		)
	}
	sctext := fmt.ctprintf("%s", stats)
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
// hover (hover carried by the scrim + caret, not by amber — the amber rule); a disabled Break
// Off dimmed to recessive blue and un-hoverable. No amber anywhere, because a Fight has no
// default move.
draw_fight_action_row :: proc(state: ^Game_State, mouse: rl.Vector2) {
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
// the round's exchange and drained from the struck hull rather than played on its own, so the
// whole round lands as one beat (fight_flush_exchange); a Ship_Sunk or Battle_Ended flushes
// that pending exchange first and then plays as its own beat; a jettison, which lands at round
// start before any damage, plays immediately. Battle_Ended is where the in-battle UI state is
// torn down, the job the old play_battle_event_beat did. Called from dispatch, so it runs on
// the same rawptr-shared Game_State the render loop reads.
dispatch_battle_event :: proc(state: ^Game_State, event: combat.Event) {
	switch e in event {
	case combat.Event_Damage_Dealt:
		state.pending_exchange[e.target] += e.final_damage
		state.exchange_active = true
		// Drain the struck hull now so both stat blocks read current when the beat renders.
		// The opponent's hull has no Event_Ship_Updated to carry it, and the player's is kept
		// in step with the Sim's authoritative copy that Event_Ship_Updated re-lands after.
		if e.target == .A {
			state.player.hull = max(0, state.player.hull - e.final_damage)
		} else if opponent, ok := state.sighted_opponent.?; ok {
			opponent.hull = max(0, opponent.hull - e.final_damage)
			state.sighted_opponent = opponent
		}
	case combat.Event_Ship_Sunk:
		fight_flush_exchange(state)
		play_beat(state, battle_event_text(event))
	case combat.Event_Battle_Ended:
		fight_flush_exchange(state)
		play_beat(state, battle_event_text(event))
		state.in_battle = false
		state.sighted_opponent = nil
	case combat.Event_Cargo_Jettisoned, combat.Event_Cargo_Reallocated:
		play_beat(state, battle_event_text(event))
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

	draw_fight_scene(state, rl.Vector2{-1, -1})
	draw_playback_overlay("")
	draw_fight_damage_number(FIGHT_PLAYER_X, dmg_a)
	if _, ok := state.sighted_opponent.?; ok {
		draw_fight_damage_number(FIGHT_OPP_X, dmg_b)
	}
}

// draw_fight_damage_number floats a round's damage over a ship's deck in the Fight hue
// (#A6485A, stage_tint's one warm), at title size for impact — never amber (damage is the
// world talking, not a control to act on). Nothing drawn when the side took no damage.
draw_fight_damage_number :: proc(area_x: f32, damage: int) {
	if damage <= 0 {
		return
	}
	text := fmt.ctprintf("-%d", damage)
	size := rl.MeasureTextEx(ui_font_title, text, UI_TITLE_SIZE, 1)
	centre_x := area_x + FIGHT_REGION_W / 2
	rl.DrawTextEx(ui_font_title, text, rl.Vector2{centre_x - size.x / 2, FIGHT_DECK_Y + 20}, UI_TITLE_SIZE, 1, stage_tint(.Fight))
}
