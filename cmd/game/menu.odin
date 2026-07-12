package main

import "core:fmt"
import "core:strings"
import combat "../../core/combat"
import run "../../core/run"
import ship "../../core/ship"
import sim "../../core/sim"
import rl "vendor:raylib"

BEAT_MAX_SECONDS :: 1.2

// play_beat runs a short blocking render loop showing overlay until the
// player clicks/presses a key or a short timer elapses (ADR-0002's "UI
// plays this back with animation" — the minimal version: a readable pause
// rather than a frame-by-frame animation). Clones overlay into a
// persistent-allocator copy up front: callers commonly pass a
// fmt.tprintf/battle_event_text result (temp-allocator memory), and this
// loop's own draw_scene call frees the temp allocator every frame, which
// would otherwise corrupt overlay after the first frame.
play_beat :: proc(state: ^Game_State, overlay: string) {
	if !rl.IsWindowReady() {
		return
	}
	stable_overlay := strings.clone(overlay)
	defer delete(stable_overlay)

	elapsed: f32
	for !rl.WindowShouldClose() {
		elapsed += rl.GetFrameTime()
		draw_scene(state, stable_overlay)
		if elapsed > BEAT_MAX_SECONDS || rl.IsKeyPressed(.SPACE) || rl.IsMouseButtonPressed(.LEFT) {
			return
		}
	}
}

// battle_event_text renders one core/combat Event as a human-readable beat.
battle_event_text :: proc(event: combat.Event) -> string {
	switch e in event {
	case combat.Event_Damage_Dealt:
		return fmt.tprintf("%v takes %d damage!", e.target, e.final_damage)
	case combat.Event_Ship_Sunk:
		return fmt.tprintf("%v's ship is sunk!", e.side)
	case combat.Event_Cargo_Jettisoned:
		return fmt.tprintf("%v jettisons %s!", e.side, e.fitting.name)
	case combat.Event_Battle_Ended:
		switch e.reason {
		case .Destroyed:
			return "The battle ends in destruction."
		case .Left_Combat:
			return "A ship flees the battle."
		case .Round_Cap:
			return "The battle ends in a stalemate."
		}
	}
	return ""
}

// play_battle_event_beat plays one combat round event's beat and, once the
// battle has ended, clears the in-battle UI state.
play_battle_event_beat :: proc(state: ^Game_State, event: combat.Event) {
	if !rl.IsWindowReady() {
		return
	}
	play_beat(state, battle_event_text(event))
	if _, ended := event.(combat.Event_Battle_Ended); ended {
		state.in_battle = false
		state.sighted_opponent = nil
	}
}

Button :: struct {
	rect:    rl.Rectangle,
	label:   string,
}

// clicked_button returns the index of the first button the mouse clicked
// this frame, or -1.
clicked_button :: proc(buttons: []Button) -> int {
	if !rl.IsMouseButtonPressed(.LEFT) {
		return -1
	}
	mouse := rl.GetMousePosition()
	for b, i in buttons {
		if rl.CheckCollisionPointRec(mouse, b.rect) {
			return i
		}
	}
	return -1
}

draw_buttons :: proc(buttons: []Button) {
	for b in buttons {
		rl.DrawRectangleRec(b.rect, rl.LIGHTGRAY)
		rl.DrawRectangleLinesEx(b.rect, 1, rl.DARKGRAY)
		rl.DrawText(fmt.ctprintf("%s", b.label), i32(b.rect.x + 8), i32(b.rect.y + 8), 14, rl.BLACK)
	}
}

// button_menu_loop blocks, drawing prompt and buttons each frame, until the
// player clicks one of buttons or the window closes. Returns the picked
// index, or -1 if the window closed without a pick. Shared by
// battle_menu_loop and upgrade_menu_loop, which differ only in how they map
// the picked index to a sim.Command.
button_menu_loop :: proc(state: ^Game_State, prompt: string, buttons: []Button) -> int {
	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		draw_scene_contents(state, prompt)
		draw_buttons(buttons)
		rl.EndDrawing()
		free_all(context.temp_allocator)

		picked := clicked_button(buttons)
		if picked >= 0 {
			return picked
		}
	}
	return -1
}

// travel_menu_loop blocks until the player clicks one of the currently-legal
// destination nodes (the ones draw_map rings and numbers), then returns a
// Command_Travel_To (ADR-0002). Clicks on non-reachable nodes are ignored, so
// the graph's connectivity is the actual constraint on movement — the UI
// offers exactly the moves run_travel_options allows, the same rule the Sim
// gates travel on (issue #71).
travel_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		return sim.Command(sim.Command_Travel_To{point_id = sim.Point_ID(state.current_point_id)})
	}
	for !rl.WindowShouldClose() {
		draw_scene(state, "Click a highlighted node to travel there.")

		if rl.IsMouseButtonPressed(.LEFT) {
			mouse := rl.GetMousePosition()
			options := run.run_travel_options(state.run_map, state.current_point_id, state.visited)
			defer delete(options)
			for dest in options {
				if rl.CheckCollisionPointCircle(mouse, state.positions[dest], POINT_RADIUS) {
					return sim.Command(sim.Command_Travel_To{point_id = sim.Point_ID(dest)})
				}
			}
		}
	}
	// The window is closing without a pick. Travel is now gated, so the old
	// "stay put" fallback (travel to the current node) is an illegal self-move
	// the Sim would assert on — return a legal forward option instead so the
	// run winds down cleanly rather than panicking on quit.
	closing := run.run_travel_options(state.run_map, state.current_point_id, state.visited)
	defer delete(closing)
	if len(closing) > 0 {
		return sim.Command(sim.Command_Travel_To{point_id = sim.Point_ID(closing[0])})
	}
	return sim.Command(sim.Command_Travel_To{point_id = sim.Point_ID(state.current_point_id)})
}

// battle_menu_loop blocks until the player picks a battle action (Boost one
// of the three phases, Man the Sails, Jettison a cargo slot, or Leave
// Combat if may_leave — ADR-0006's one-decision-per-round menu), then
// returns a Command_Battle_Choice.
battle_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		return sim.Command(sim.Command_Battle_Choice{combat_command = combat.Command(combat.Command_Hold{})})
	}
	// Button labels are heap-allocated (fmt.aprintf, context.allocator) and
	// explicitly freed below, not built with fmt.tprintf: this loop calls
	// free_all(context.temp_allocator) once per frame (draw_ship_panel's own
	// per-frame labels rely on that), which would otherwise silently
	// corrupt these buttons' labels after the first frame, since they're
	// built once before the loop starts but read on every frame after.
	buttons := make([dynamic]Button)
	defer {
		for b in buttons {
			delete(b.label)
		}
		delete(buttons)
	}
	combat_commands := make([dynamic]combat.Command)
	defer delete(combat_commands)

	y : f32 = 440
	for category in ship.Category {
		append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = fmt.aprintf("Boost %v", category)})
		append(&combat_commands, combat.Command(combat.Command_Boost{phase = category}))
		y += 34
	}

	append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = fmt.aprintf("Man the Sails")})
	append(&combat_commands, combat.Command(combat.Command_Man_The_Sails{}))
	y += 34

	for layout_slot, i in state.player.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting || !fitting.is_cargo {
			continue
		}
		append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = fmt.aprintf("Jettison %s", fitting.name)})
		append(&combat_commands, combat.Command(combat.Command_Jettison_Cargo{slot_index = ship.Slot_Index(i)}))
		y += 34
	}

	if state.may_leave {
		append(&buttons, Button{rect = rl.Rectangle{x = SHIP_PANEL_X, y = y, width = 220, height = 30}, label = fmt.aprintf("Leave Combat")})
		append(&combat_commands, combat.Command(combat.Command_Leave_Combat{}))
		y += 34
	}

	picked := button_menu_loop(state, "Choose your captain's command.", buttons[:])
	if picked >= 0 {
		return sim.Command(sim.Command_Battle_Choice{combat_command = combat_commands[picked]})
	}
	return sim.Command(sim.Command_Battle_Choice{combat_command = combat.Command(combat.Command_Hold{})})
}

// upgrade_menu_loop blocks until the player picks one of the 3 fixed
// Upgrade Offer options, then returns a Command_Pick_Upgrade.
upgrade_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		return sim.Command(sim.Command_Pick_Upgrade{option_index = 0})
	}
	options := state.upgrade_options

	// See battle_menu_loop's comment: labels must survive across this
	// loop's per-frame free_all(context.temp_allocator), so they're
	// heap-allocated (fmt.aprintf) and freed explicitly below.
	buttons: [3]Button
	defer for b in buttons {
		delete(b.label)
	}
	for option, i in options {
		magnitude := 0
		if active, has_active := option.active.?; has_active {
			magnitude = int(active.magnitude)
		}
		buttons[i] = Button{
			rect  = rl.Rectangle{x = SHIP_PANEL_X, y = f32(460 + i * 60), width = 260, height = 48},
			label = fmt.aprintf("%s (%d)", option.name, magnitude),
		}
	}

	picked := button_menu_loop(state, "Choose an upgrade.", buttons[:])
	if picked >= 0 {
		return sim.Command(sim.Command_Pick_Upgrade{option_index = sim.Option_Index(picked)})
	}
	return sim.Command(sim.Command_Pick_Upgrade{option_index = 0})
}
