package presentation

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import cutaway "./cutaway"
import ship "../core/ship"
import sim "../core/sim"
import rl "vendor:raylib"

// Capture mode is the third Input_Source/Event_Sink pair (ADR-0002), beside the
// game's blocking menus and headless's instant scripts: it renders a real frame,
// screenshots it, and returns a *scripted* command so the session walks itself.
// That is the whole idea — no player, but a real window and the real render code.
//
// It lives beside the render code it photographs — draw_scene, Game_State and
// dispatch are package-private, so capture sees exactly the screens the game
// draws. Capture renders, so ADR-0003's reason for splitting headless out (never
// link the renderer) does not argue for a capture executable of its own.

// The instant every shot's chart is frozen at (juice_clock_pin). Chosen off zero, where the
// moored ship's bob sits at a zero crossing and its heel at a peak: a shot should catch the hull
// mid-rock, the way a player sees it, rather than at the one instant of the cycle that flatters
// it into stillness.
@(private)
CAPTURE_CLOCK :: 0.3

// Capture_State drives the scripted walk and numbers the shots it takes. The Game_State
// it wraps is handed to the *real* dispatch untouched, so capture sees exactly the screens
// the game draws rather than a second, drifting copy: the two halves take separate
// rawptrs, so capture's Input_Source and the game's Event_Sink can read different structs
// without either knowing about the other.
//
// The registry's shots are numbered by their place in it, so the running count here belongs
// to the voyage half alone: it counts decision screens passed, which capture_voyage_number
// turns into the number a file carries.
@(private)
Capture_State :: struct {
	game:    Game_State,
	shots:   int, // decision screens the walk has passed, shot or skipped
	written: int, // shots that reached the capture directory, not shots attempted
	// target is the one voyage screen a targeted walk came for, "" for the full gallery.
	// The walk numbers every screen it passes either way and shoots only this one, so a
	// targeted shot lands on the file the gallery would have given it.
	target:  string,
	// taken is set once the target has been shot at, whether or not the file landed. It is
	// what stops the walk, and it stops it on the *first* screen carrying the name — a
	// phase recurs (there are many travel screens) and the first is the one the number
	// belongs to.
	taken:   bool,
}

// Capture_Scene is the world one shot draws from, staged fresh for that shot and torn
// down after it. Every screen capture shoots standalone reads some part of it: a ship, a
// voyage map, an opponent. Each shot gets its own, so no shot inherits the state another
// left behind and every entry stands alone.
@(private)
Capture_Scene :: struct {
	game:     Game_State,
	// player and opponent are the ships this scene built for itself, if it built any.
	// game.player is not necessarily one of them: staging from a Sim leaves it pointing at
	// arena-backed storage the Sim owns, since dispatch assigns Event_Voyage_Started's ship
	// straight through. So the scene frees the ships it made, never the one game happens to
	// point at.
	player:   ship.Ship,
	opponent: ship.Ship,
	// voyage is the Sim a staged screen was populated from, and the scene keeps it alive
	// for exactly as long as it keeps the Game_State: dispatch leaves arena-backed slices
	// borrowed from the Sim in there (travel_options), so a Sim destroyed at the end of
	// staging leaves the frame drawing freed memory. nil when the shot staged no voyage.
	voyage:   ^sim.Sim,
}

// A Capture_Shot is one named state of one screen — the resting screen, but equally the
// hovered berth, the drag in flight and the animation caught mid-raise. Capture has no
// mouse and so cannot discover those, but it can be told where the cursor is: a state
// belongs here as its own entry, never hard-coded into another shot's frame for one run
// and reverted after. The name is what --shot asks for and what an unknown name is
// reported against, and the entry's place in the table is the number its file carries —
// so a shot taken on its own lands on the same file the full walk gives it.
//
// The work splits in two because the frame is drawn twice (capture_write says why):
//
//   - `stage` builds the state the shot draws from, and runs *once*. It is where the
//     allocation goes — a ship, a ticked Sim — and it is nil for a screen that draws from
//     nothing at all.
//   - `frame` composes one frame, and runs *twice*. It may arrange the scene it was given
//     (a drag, a cursor, a raise) but must not allocate, since it does that twice too. It
//     returns false when the state it names cannot be arranged — a missing roster item, a
//     berth with nowhere to put a hover — and then nothing is shot.
@(private)
Capture_Shot :: struct {
	name:  string,
	stage: proc(scene: ^Capture_Scene),
	frame: proc(scene: ^Capture_Scene) -> bool,
}

// The standalone shots, in walk order — the one source of truth for what capture can
// photograph without a voyage. `--shot <name>` takes one of these and needs no Sim at all;
// `--capture` takes all of them and then walks. Everything past them is a decision screen
// the scripted voyage reaches by sailing to it (capture_phase_slug names those), and
// `--shot` gets there by walking (capture_walk).
@(private)
capture_shots := [?]Capture_Shot {
	{name = "chart-table", frame = capture_frame_chart_table},
	{name = "chart-table-hover", frame = capture_frame_chart_table_hover},
	{name = "home", stage = capture_stage_home, frame = capture_frame_home},
	{name = "home-chart-rising", stage = capture_stage_home, frame = capture_frame_home_chart_rising},
	{name = "home-chart", stage = capture_stage_home, frame = capture_frame_home_chart},
	{name = "build", stage = capture_stage_refit, frame = capture_frame_build},
	{name = "build-hover", stage = capture_stage_refit, frame = capture_frame_build_hover},
	{name = "build-shelf", stage = capture_stage_refit, frame = capture_frame_build_shelf},
	{name = "build-placing", stage = capture_stage_refit, frame = capture_frame_build_placing},
	{name = "build-burning", stage = capture_stage_refit, frame = capture_frame_build_burning},
	{name = "build-burn-confirm", stage = capture_stage_refit, frame = capture_frame_build_burn_confirm},
	{name = "encounter-frame", stage = capture_stage_refit, frame = capture_frame_encounter_frame},
	{name = "encounter-playback", stage = capture_stage_refit, frame = capture_frame_encounter_playback},
	{name = "shop", stage = capture_stage_shop, frame = capture_frame_shop},
	{name = "shop-travelling", stage = capture_stage_shop, frame = capture_frame_shop_travelling},
	{name = "shop-buying", stage = capture_stage_shop, frame = capture_frame_shop_buying},
	{name = "offer", stage = capture_stage_offer, frame = capture_frame_offer},
	{name = "fight", stage = capture_stage_fight, frame = capture_frame_fight},
	{name = "fight-exchange", stage = capture_stage_fight, frame = capture_frame_fight_exchange},
	{name = "fight-jettison", stage = capture_stage_fight, frame = capture_frame_fight_jettison},
}

// capture_shot_for finds a standalone shot by name, with the number its file carries.
@(private)
capture_shot_for :: proc(name: string) -> (shot: Capture_Shot, number: int, ok: bool) {
	for candidate, i in capture_shots {
		if candidate.name == name {
			return candidate, i, true
		}
	}
	return {}, 0, false
}

// capture_voyage_names is what the walk's own screens can be asked for by. They have no
// registry of their own: a decision screen is named for its Phase, so the Phases are the
// list and capture_phase_slug is the naming.
@(private)
capture_voyage_names :: proc() -> (names: [len(sim.Phase)]string) {
	for phase, i in sim.Phase {
		names[i] = capture_phase_slug(phase)
	}
	return
}

// capture_voyage_named reports whether a name is one of the walk's own screens. Unlike a
// standalone shot, the number is not knowable here: it falls out of where the screen sits
// in the walk, which is what walking is for.
@(private)
capture_voyage_named :: proc(name: string) -> bool {
	names := capture_voyage_names()
	return slice.contains(names[:], name)
}

// capture_voyage_number is the number the file of the walk's `passed`th decision screen
// carries. The voyage numbers on from the registry, so the two halves of the gallery share
// one run of numbers and a walked shot lands past every standalone one — which is what lets
// a targeted walk write the gallery's own filename without having shot the registry first.
@(private)
capture_voyage_number :: proc(passed: int) -> int {
	return len(capture_shots) + passed
}

// capture_open builds the window every capture entry shoots in. Paired with
// capture_close, which the caller defers — Odin scopes a defer to its own proc.
@(private)
capture_open :: proc(title: cstring) {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, title)
	rl.SetTargetFPS(60)
	ui_fonts_load()
	art_load()

	// Every capture mode wants a repeatable frame, and only capture does: a session left on the
	// live clock is what the idle motion exists for.
	juice_clock_pin(CAPTURE_CLOCK)

	// Not fatal: raylib reports its own failure per shot, and a capture run that writes
	// nothing is still worth watching walk the route.
	capture_dir_prepare()
}

@(private)
capture_close :: proc() {
	art_unload()
	ui_fonts_unload()
	rl.CloseWindow()
	capture_dir_release()
}

// capture_take shoots one registry entry: stages the scene, composes the frame twice and
// writes the PNG. Reports whether the shot reached the capture directory.
@(private)
capture_take :: proc(state: ^Capture_State, shot: Capture_Shot, number: int) -> bool {
	if !rl.IsWindowReady() {
		return false
	}

	scene := Capture_Scene{}
	defer capture_scene_destroy(&scene)
	if shot.stage != nil {
		shot.stage(&scene)
	}

	if !shot.frame(&scene) {
		fmt.eprintfln("capture: %s could not be arranged", shot.name)
		return false
	}
	shot.frame(&scene) // the second of the two draws capture_write needs
	return capture_write(state, number, shot.name)
}

// capture_scene_destroy frees everything staging a scene allocated. Odin's delete is
// happy with the zero value, so this covers a scene whose stage set only some of it —
// and a shot that staged nothing at all.
@(private)
capture_scene_destroy :: proc(scene: ^Capture_Scene) {
	// dispatch clones the nodes into UI-owned storage and makes the two parallel arrays;
	// travel_options stays borrowed from the Sim, so it is not freed here.
	delete(scene.game.visited)
	delete(scene.game.positions)
	delete(scene.game.voyage_map.nodes)
	// game.player and game.sighted_opponent are copies of these two and share their
	// layouts, so the deletes here free both sides.
	delete(scene.player.layout)
	delete(scene.opponent.layout)

	// Last: the Game_State above borrows from this arena.
	if scene.voyage != nil {
		sim.sim_destroy(scene.voyage)
		free(scene.voyage)
	}
}

// capture_take_all shoots every registry entry, each numbered by its place in the table.
// Both the whole-set entry and the scripted walk render their standalone shots through here.
@(private)
capture_take_all :: proc(state: ^Capture_State) {
	for shot, number in capture_shots {
		capture_take(state, shot, number)
	}
}

// capture_shots_main renders the whole standalone set in one window and returns, without the
// voyage walk --capture follows it with. Reports whether every entry landed: a partial set is a
// failure, since a caller comparing the shots against a manifest would read the stale PNG left
// in place of a missing one as an unchanged screen.
capture_shots_main :: proc() -> bool {
	capture_open("Fantasy Ship Game (shots)")
	defer capture_close()

	state := Capture_State{}
	capture_take_all(&state)

	if state.written != len(capture_shots) {
		fmt.eprintfln(
			"capture: %d of %d shot(s) landed in %s",
			state.written,
			len(capture_shots),
			capture_dir(),
		)
		return false
	}
	return true
}

// capture_shot_main renders one named screen, writes its PNG and returns — the targeted
// counterpart to capture_main's whole gallery, entered from main when --shot is passed.
// Reports whether the shot reached the capture directory.
//
// The name decides how much has to run: a standalone screen stages itself, so the cost is
// the window and one frame; one of the walk's own screens has to be sailed to, so the
// voyage runs — but only as far as that screen. Resolving the name comes first, so a name
// that is neither is answered without opening a window at all.
capture_shot_main :: proc(name: string) -> bool {
	if shot, number, standalone := capture_shot_for(name); standalone {
		return capture_shot_by_staging(shot, number)
	}
	if capture_voyage_named(name) {
		return capture_shot_by_sailing(name)
	}

	// Both lists are fixed-width — one entry per registry row, one per Phase — so the
	// report that closes the process allocates nothing but the two joined strings.
	shot_names: [len(capture_shots)]string
	for candidate, i in capture_shots {
		shot_names[i] = candidate.name
	}
	voyage_names := capture_voyage_names()
	fmt.eprintfln(
		"capture: no shot named %q.\n  screens: %s\n  voyage screens: %s\n" +
		"  A voyage screen is reached by sailing to it, so the walk need not pass every one.",
		name,
		strings.join(shot_names[:], ", ", context.temp_allocator),
		strings.join(voyage_names[:], ", ", context.temp_allocator),
	)
	return false
}

// capture_shot_by_staging shoots one registry entry in a window of its own. No Sim, no
// voyage: only the asked-for entry's stage and frame run.
@(private)
capture_shot_by_staging :: proc(shot: Capture_Shot, number: int) -> bool {
	capture_open("Fantasy Ship Game (shot)")
	defer capture_close()

	state := Capture_State{}
	if !capture_take(&state, shot, number) {
		// Either the frame reported it could not be arranged, or the shot was composed and
		// could not be moved out of the working directory. capture_take has already said
		// which. Both are failures: nothing is in the capture directory to look at.
		fmt.eprintfln("capture: %s did not land in %s", shot.name, capture_dir())
		return false
	}
	return true
}

// capture_shot_by_sailing sails the scripted voyage for one of its own screens and stops
// the moment that shot lands — the counterpart for a screen no staging can reach, only
// playing to it. The registry is skipped entirely, so a targeted run costs the sailing up
// to that screen and no more.
@(private)
capture_shot_by_sailing :: proc(name: string) -> bool {
	capture_open("Fantasy Ship Game (shot)")
	defer capture_close()

	state := Capture_State{target = name}
	capture_walk(&state)

	if !state.taken {
		// The walk sailed to the end without ever reaching this screen: its route met no
		// stage that presents one.
		fmt.eprintfln("capture: the scripted voyage never reached %s, so nothing was shot", name)
		return false
	}
	if state.written == 0 {
		// Reached and composed, but the file could not be moved into the capture
		// directory — capture_write has already said why.
		fmt.eprintfln("capture: %s did not land in %s", name, capture_dir())
		return false
	}
	return true
}

// capture_main is the scripted session, entered from main when --capture is passed.
// It builds the same window and Sim the real game does; only the Input_Source
// differs. The standalone shots come from the same registry --shot reads, so there is
// no second list of them to drift.
capture_main :: proc() {
	capture_open("Fantasy Ship Game (capture)")
	defer capture_close()

	state := Capture_State{}
	capture_take_all(&state)
	capture_walk(&state)

	fmt.printfln("capture: wrote %d shot(s) to %s", state.written, capture_dir())
}

// capture_walk sails the scripted voyage, photographing the decision screens it passes:
// every one of them for the gallery, or just the one a targeted run named. Both entries
// walk the same seed through the same driver, which is what makes the two land on the same
// file.
//
// It owns the storage the walk's dispatch clones into and frees it on the way out, so
// state.game is not readable once this returns.
@(private)
capture_walk :: proc(state: ^Capture_State) {
	// The walk's dispatch clones the voyage map into UI-owned storage; a standalone shot's
	// scene owns its own copies and frees them in capture_scene_destroy.
	defer delete(state.game.visited)
	defer delete(state.game.positions)
	defer delete(state.game.voyage_map.nodes)

	s := sim.sim_create(VOYAGE_SEED)
	defer sim.sim_destroy(&s)

	// The two halves take separate rawptrs: the sink gets the plain Game_State the
	// real dispatch expects, the input gets the Capture_State that also holds the
	// shot counter. The stop hook is passed either way and simply never fires for the
	// gallery, which has no target to have reached.
	input := sim.Input_Source {
		data               = state,
		get_captain_choice = capture_get_captain_choice,
		should_stop        = capture_shot_taken,
	}
	sink := sim.Event_Sink{data = &state.game, dispatch = dispatch}

	sim.run_session(&s, input, sink)

	// The voyage's end is a screen but never a decision: run_session returns on
	// Event_Voyage_Ended, so nothing asks the input for a command in the Ended phase. The
	// walk shoots it here instead, numbered and filed like every other screen it passed —
	// but only when the voyage actually ended, since a targeted walk returns as soon as its
	// own shot has landed.
	if state.game.status != .In_Progress {
		capture_voyage_shot(state, .Ended, capture_phase_slug(.Ended))
	}
}

// capture_shot_taken is the walk's way out: a targeted run has what it came for once its
// screen has been shot at. The gallery never sets this, so it sails to the voyage's end.
@(private)
capture_shot_taken :: proc(data: rawptr) -> bool {
	return (cast(^Capture_State)data).taken
}

// capture_get_captain_choice is the capture Input_Source: draw the decision screen
// the player would have been shown, screenshot it, then answer the decision from
// the shared scripted player (sim.scripted_player_command) instead of from a click —
// fed the voyage state the real dispatch tracked into Game_State. Unlike the
// game's menu loops it blocks on nothing, and unlike headless's it draws — which
// is the whole point of the third Input_Source.
@(private)
capture_get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Capture_State)data

	capture_voyage_shot(state, awaiting, capture_phase_slug(awaiting))
	return sim.scripted_player_command(capture_scripted_view(&state.game), awaiting)
}

// capture_scripted_view is the scripted player's input, read off the Game_State the real
// dispatch fills. Every field it wants is already tracked there for the screen that renders
// it, so the walk needs no second copy of the event stream — it hands over the same facts
// the player would have been looking at.
@(private)
capture_scripted_view :: proc(game: ^Game_State) -> sim.Scripted_View {
	return sim.Scripted_View {
		voyage_map       = game.voyage_map,
		current          = game.current_node_id,
		travel_options   = game.travel_options,
		player           = game.player,
		stage_options    = game.stage_options,
		trade            = game.active_trade,
		trade_can_accept = game.trade_can_accept,
		may_press        = game.may_press,
		refit_incoming   = game.refit_incoming,
	}
}

// capture_voyage_shot renders one frame of the current decision screen and writes it out.
// This is the voyage half, which reaches its screens by walking rather than by name, so it
// numbers its own shots as it goes rather than reading a number off the registry.
//
// A targeted walk passes the same screens in the same order and takes the number with it,
// shooting only the one it named: skipping a screen still spends its number, or a shot
// taken this way would land on a different file than the gallery gives it. A phase recurs
// along the route, so the first screen carrying the name is the one that is shot — and the
// one that ends the walk.
@(private)
capture_voyage_shot :: proc(state: ^Capture_State, awaiting: sim.Phase, label: string) {
	if !rl.IsWindowReady() {
		return
	}

	number := capture_voyage_number(state.shots)
	state.shots += 1

	if state.target != "" {
		if state.taken || label != state.target {
			return
		}
		state.taken = true
	}

	capture_draw_screen(state, awaiting, label)
	capture_draw_screen(state, awaiting, label)
	capture_write(state, number, label)
}

// The Chart Table (#278) is stateless and precedes any voyage, so it is the one screen
// capture can shoot without staging anything at all.

// -1: no button is hovered. The screen photographs in its resting state rather than in
// whatever state a pointer happens to leave it.
@(private)
capture_frame_chart_table :: proc(scene: ^Capture_Scene) -> bool {
	draw_chart_table(-1)
	return true
}

// Begin under the cursor. Every row is drawn identically, so this shot's whole difference from
// the resting one is what hover draws: the caret in the label's margin, and the scrim's lift.
@(private)
capture_frame_chart_table_hover :: proc(scene: ^Capture_Scene) -> bool {
	draw_chart_table(0)
	return true
}

// capture_stage_home stages Home (#317) — the persistent between-encounters Build surface
// and the chart raised over it. Home reads the same map, positions and travel options a
// real voyage's first tick emits, so a throwaway Sim ticked once and dispatched into a
// fresh Game_State populates it without a scripted walk — which has no mouse to raise the
// tab. The first tick emits only Event_Voyage_Started and Event_Travel_Options, neither of
// which plays a beat, so dispatching them here is safe.
@(private)
capture_stage_home :: proc(scene: ^Capture_Scene) {
	scene.voyage = new_clone(sim.sim_create(VOYAGE_SEED))

	events: [dynamic]sim.Event
	defer delete(events)
	sim.sim_tick(scene.voyage, &events)
	for e in events {
		dispatch(&scene.game, e)
	}

	// home_loop asserts the full-width chart page every frame; capture bypasses the loop,
	// so assert it here or the raised chart shoots at the voyage width the live game
	// never shows on this screen.
	map_width_set(&scene.game, MAP_HOME_W)
}

// At anchor: the ship in refit as the resting home, no granted item and so no shelf.
@(private)
capture_frame_home :: proc(scene: ^Capture_Scene) -> bool {
	draw_home(&scene.game, ship_framing_moored(), Build_Drag{}, nil, NO_MOUSE, 0)
	return true
}

// Mid-flip: the chart half-raised, sliding up over a partly-dimmed surface. draw_home
// composes any elevation, so the click flip (#329) is photographable at a fixed point of
// its animation rather than by racing it — the split #277 asks for.
@(private)
capture_frame_home_chart_rising :: proc(scene: ^Capture_Scene) -> bool {
	draw_home(&scene.game, ship_framing_moored(), Build_Drag{}, nil, NO_MOUSE, 0.5)
	return true
}

// The chart raised over the surface: the sailable overlay, the between-encounters travel view.
@(private)
capture_frame_home_chart :: proc(scene: ^Capture_Scene) -> bool {
	draw_home(&scene.game, ship_framing_moored(), Build_Drag{}, nil, NO_MOUSE, 1)
	return true
}

// capture_stage_refit stages the real starting ship (#302) and nothing else. The Build
// surface, the encounter frame and the shots below them read only the ship, so they need
// no Sim — which is why they are shot standalone here rather than from the scripted walk,
// whose own ship is whatever the route has made of it by the time it refits.
@(private)
capture_stage_refit :: proc(scene: ^Capture_Scene) {
	scene.player = ship.ship_starting_ship()
	scene.game.player = scene.player
}

// At rest: the ship in refit, no granted item and so no shelf.
@(private)
capture_frame_build :: proc(scene: ^Capture_Scene) -> bool {
	draw_build_surface(&scene.game, ship_framing_moored(), Build_Drag{}, nil, NO_MOUSE)
	return true
}

// Hovering a berth: its opening lit, and its description card thrown clear of the hull on
// a leader line. Capture has no mouse, so the cursor is placed on the sterncastle's
// opening — the same point a real hover lands on.
@(private)
capture_frame_build_hover :: proc(scene: ^Capture_Scene) -> bool {
	rooms, n := cutaway.galleon_rooms(scene.game.player.layout)
	over, aimed := capture_room_centre(rooms, n, 0)
	if !aimed {
		return false
	}
	draw_build_surface(&scene.game, ship_framing_moored(), Build_Drag{}, nil, over)
	return true
}

// capture_shelf_granted puts a granted Large item on the shelf and hands it back — the
// arrangement the shelf shot and the drag lifting off it both start from. Large, so the
// empty forecastle is a legal berth for it.
@(private)
capture_shelf_granted :: proc(scene: ^Capture_Scene) -> (ship.Fitting, bool) {
	granted, ok := ship.ship_item_by_name("Long Nines")
	if !ok {
		return {}, false
	}
	scene.game.refit_incoming = granted.fitting
	return granted.fitting, true
}

// A granted Large item waiting on the shelf — a parchment card centred under the ship.
@(private)
capture_frame_build_shelf :: proc(scene: ^Capture_Scene) -> bool {
	if _, ok := capture_shelf_granted(scene); !ok {
		return false
	}
	draw_build_surface(&scene.game, ship_framing_moored(), Build_Drag{}, nil, NO_MOUSE)
	return true
}

// Mid-drag: the granted item lifted off the shelf, its ghost over the empty Large
// forecastle, legal berths lit and the rest dimmed. The forecastle is the fourth deck slot.
@(private)
capture_frame_build_placing :: proc(scene: ^Capture_Scene) -> bool {
	granted, ok := capture_shelf_granted(scene)
	if !ok {
		return false
	}

	rooms, n := cutaway.galleon_rooms(scene.game.player.layout)
	over, aimed := capture_room_centre(rooms, n, 3)
	if !aimed {
		return false
	}
	draw_build_surface(&scene.game, ship_framing_moored(), Build_Drag{active = true, from_slot = nil, fitting = granted}, nil, over)
	return true
}

// The out-of-combat burn (#401), mid-drag: a laden berth dragged onto the hold ledger,
// which arms as the burn target.
@(private)
capture_frame_build_burning :: proc(scene: ^Capture_Scene) -> bool {
	slot, any_laden := capture_laden_slot(scene.game.player.layout).?
	if !any_laden {
		return false
	}
	laden, _ := scene.game.player.layout[slot].fitting.?

	ledger := build_ledger_rect()
	on_ledger := rl.Vector2{ledger.x + ledger.width / 2, ledger.y + ledger.height / 2}
	draw_build_surface(
		&scene.game,
		ship_framing_moored(),
		Build_Drag{active = true, from_slot = slot, fitting = laden},
		nil,
		on_ledger,
	)
	return true
}

// The confirm that drop opens.
@(private)
capture_frame_build_burn_confirm :: proc(scene: ^Capture_Scene) -> bool {
	slot, any_laden := capture_laden_slot(scene.game.player.layout).?
	if !any_laden {
		return false
	}
	draw_build_surface(&scene.game, ship_framing_moored(), Build_Drag{}, Build_Confirm{slot = slot, burn = true}, NO_MOUSE)
	return true
}

// capture_laden_slot is the first berth carrying cargo — what the burn shots drag and
// then confirm.
@(private)
capture_laden_slot :: proc(layout: []ship.Layout_Slot) -> Maybe(ship.Slot_Index) {
	for layout_slot, i in layout {
		if fitting, filled := layout_slot.fitting.?; filled && fitting.cargo_held > 0 {
			return ship.Slot_Index(i)
		}
	}
	return nil
}

// capture_room_centre is where a cursor has to be to point into a berth on the moored ship
// screen: the middle of that slot's projected opening. NO_MOUSE (over nothing) when the slot
// placed no room.
@(private)
capture_room_centre :: proc(
	rooms: [cutaway.MAX_SLOTS]cutaway.Room,
	n: int,
	slot: ship.Slot_Index,
) -> (
	rl.Vector2,
	bool,
) {
	return capture_room_centre_in(rooms, n, slot, cutaway.galleon_view(WINDOW_WIDTH, WINDOW_HEIGHT))
}

// capture_room_centre_in is the same aim through a named framing — the seam a stage that
// presents her under a different camera needs, since the opening it has to point at is not
// where the moored view puts it (#476).
@(private)
capture_room_centre_in :: proc(
	rooms: [cutaway.MAX_SLOTS]cutaway.Room,
	n: int,
	slot: ship.Slot_Index,
	view: cutaway.View,
) -> (
	rl.Vector2,
	bool,
) {
	room, placed := cutaway.galleon_room_for_slot(rooms, n, slot)
	if !placed {
		return NO_MOUSE, false
	}
	return cutaway.galleon_face_centre(cutaway.galleon_room_face(room, view)), true
}

// The shared encounter frame (#304) — the constant furniture the per-stage builds fill in:
// the bare frame on a representative stage, header naming it in its category colour, the
// top-right stat line, the view-only chart tab, the vignette.
@(private)
capture_frame_encounter_frame :: proc(scene: ^Capture_Scene) -> bool {
	draw_encounter_frame(&scene.game, .Shop, "")
	return true
}

// The playback layer over that frame — the Reward beat, which is only this overlay.
@(private)
capture_frame_encounter_playback :: proc(scene: ^Capture_Scene) -> bool {
	draw_encounter_frame(&scene.game, .Reward, "Salvage! You haul aboard 4 cargo.")
	return true
}

// capture_stage_shop stages the Shop stage (#312): the starting ship plus a synthesized
// priced shelf. The scripted walk only ever meets free Offers — a Shop lives at a Port —
// so this stop is built here instead.
@(private)
capture_stage_shop :: proc(scene: ^Capture_Scene) {
	capture_stage_refit(scene)
	// The screen reads its kind off the stage-entered Event (#430), so the synthesized
	// stop announces itself a Shop the way a real walk would.
	scene.game.stage_progress = sim.Event_Stage_Entered{kind = .Shop, index = 0, count = 1}
	names := [?]string{"Long Nines", "Chain & Bar Shot", "Titan's Heart", "Outriggers"}
	costs := [?]int{18, 34, 120, 26} // the 120 sits above the starting hold, so it dims
	for name, i in names {
		if item, ok := ship.ship_item_by_name(name); ok {
			scene.game.stage_options[i] = sim.Stage_Option{fitting = item.fitting, cost = costs[i]}
		}
	}
}

// The shelf at rest: priced cards, one dearer than the hold can pay so its dimmed,
// undraggable read shows.
@(private)
capture_frame_shop :: proc(scene: ^Capture_Scene) -> bool {
	draw_offer_shop(&scene.game, offer_shop_alongside(), Shelf_Drag{}, NO_MOUSE)
	return true
}

// Part-way through the travel (#476): the camera swinging to her beam, her hull straightening
// as the projection blends out of perspective, her canvas being handed, and the column still
// off to the right. A move is the one thing a still cannot judge — but stills along it are what
// say whether the blend is monotone and whether anything tears half-way.
@(private)
capture_frame_shop_travelling :: proc(scene: ^Capture_Scene) -> bool {
	draw_offer_shop(&scene.game, offer_shop_travel(0.5), Shelf_Drag{}, NO_MOUSE)
	return true
}

// A buy in flight: the card in hand over the empty Large forecastle, with the stat line
// ghosting the post-buy cargo (`Cargo 80/90 → 62/90`).
@(private)
capture_frame_shop_buying :: proc(scene: ^Capture_Scene) -> bool {
	item, ok := ship.ship_item_by_name("Long Nines") // Large, so the empty Large forecastle lights
	if !ok {
		return false
	}

	stage := offer_shop_alongside()
	rooms, n := cutaway.galleon_rooms(scene.game.player.layout)
	over, aimed := capture_room_centre_in(rooms, n, 3, stage.framing.view)
	if !aimed {
		return false
	}

	drag := Shelf_Drag{active = true, option_index = sim.Option_Index(0), fitting = item.fitting, cost = 18}
	draw_offer_shop(&scene.game, stage, drag, over)
	return true
}

// capture_stage_offer stages the Offer stage (#312): the same screen with the one thing that
// differs between the two — its stock is free, so no card carries a price and the control reads
// Skip rather than Leave. The scripted walk's first option screen is a Shop, so without this
// entry the unpriced column goes unphotographed.
@(private)
capture_stage_offer :: proc(scene: ^Capture_Scene) {
	capture_stage_refit(scene)
	scene.game.stage_progress = sim.Event_Stage_Entered{kind = .Offer, index = 0, count = 1}
	names := [?]string{"Deck Pumps", "Bilge Rats", "Carpenter's Mate"}
	for name, i in names {
		if item, ok := ship.ship_item_by_name(name); ok {
			scene.game.stage_options[i] = sim.Stage_Option{fitting = item.fitting}
		}
	}
}

@(private)
capture_frame_offer :: proc(scene: ^Capture_Scene) -> bool {
	draw_offer_shop(&scene.game, offer_shop_alongside(), Shelf_Drag{}, NO_MOUSE)
	return true
}

// capture_stage_fight stages the Fight stage (#315) — the facing cutaways the scripted
// walk can't linger on (it Holds every round and the battle blurs past in beats). It reads
// only two ships: the starting ship as the player, a second one as a mid-fight opponent
// (Hull dropped, so a scouted, damaged foe reads) whose concealed holds render "???".
@(private)
capture_stage_fight :: proc(scene: ^Capture_Scene) {
	capture_stage_refit(scene)
	scene.opponent = ship.ship_starting_ship()
	scene.opponent.hull = 58 // a foe already worn down, so the opponent stat block reads a real fight

	scene.game.sighted_opponent = scene.opponent
	scene.game.in_battle = true
	scene.game.battle_round = 3 // "Round 4", escape still a couple of rounds off
	scene.game.may_press = true // the fight's one Press still in hand, so the row shows it takeable
	scene.game.stage_progress = sim.Event_Stage_Entered{kind = .Fight, index = 0, count = 2}
}

// The fight at rest: both cutaways, the per-slot visibility badges, the round / stage
// readouts, the uniform action row.
@(private)
capture_frame_fight :: proc(scene: ^Capture_Scene) -> bool {
	draw_fight(&scene.game, NO_MOUSE)
	return true
}

// The round-exchange beat: both damage numbers floating over their hulls under the shared scrim.
@(private)
capture_frame_fight_exchange :: proc(scene: ^Capture_Scene) -> bool {
	draw_fight_exchange(&scene.game, 9, 14)
	return true
}

// Jettison's target step: the same row, showing what the ship is carrying rather than the
// captain's orders. A player reaches it with a click, so without this entry the second
// step goes unphotographed.
@(private)
capture_frame_fight_jettison :: proc(scene: ^Capture_Scene) -> bool {
	scene.game.jettison_targeting = true
	draw_fight(&scene.game, NO_MOUSE)
	return true
}

// capture_write writes the presented frame to the capture directory under `number`, so the
// shots carry the walk order a session reading them back follows. Reports whether the file
// landed there, and names it on stdout — one `capture: wrote <path>` line per shot, which is
// how a caller learns the set a run produced.
//
// The shot already at that name is moved aside rather than overwritten (capture_keep_previous),
// so the frame this one is about to be compared against survives being replaced.
//
// Callers draw their frame twice before calling: rl.TakeScreenshot reads back the
// framebuffer that EndDrawing just presented, so a single draw would screenshot
// whatever was on screen *before* this one. Drawing the same scene into both buffers
// makes the read-back land on this frame regardless of which buffer is read.
@(private)
capture_write :: proc(state: ^Capture_State, number: int, label: string) -> bool {
	// rl.TakeScreenshot runs the filename through GetFileName() and writes into the
	// process's working directory, so a path prefix here is silently dropped — the shot
	// always lands beside the exe's cwd. Each one is moved into the capture directory
	// immediately rather than left to litter the repo root; capture does not get to choose
	// where raylib writes, only where the file ends up.
	name := fmt.tprintf("%02d-%s.png", number, label)
	rl.TakeScreenshot(strings.clone_to_cstring(name, context.temp_allocator))

	dest := fmt.tprintf("%s/%s", capture_dir(), name)
	capture_keep_previous(dest)

	// A shot that cannot be moved is removed rather than left behind: the repo root is not
	// a capture directory, `*.png` there is not gitignored, and a stranded shot is one
	// `git add .` away from being committed. It is reported unwritten either way, so a
	// targeted run fails rather than reporting a file that is not there.
	if err := os.rename(name, dest); err != nil {
		fmt.eprintfln("capture: could not move %s into %s (%v)", name, capture_dir(), err)
		if err := os.remove(name); err != nil {
			fmt.eprintfln("capture: %s is stranded in the working directory (%v)", name, err)
		}
		return false
	}
	state.written += 1
	fmt.printfln("capture: wrote %s", dest)
	return true
}

// capture_draw_screen draws the frame a player would be looking at for this decision. The
// travel screen (Home, #317), the option screen (Offer/Shop, #312), the Trade stage (#318) and
// the Fight (#315) are all fully drawable surfaces split from their loops, so the scripted walk
// photographs each as the player would see it — at rest, with no drag. Refit still falls back to
// draw_scene, which renders the scene *without* that screen's chrome — its controls are still
// welded inside its blocking menu loop. The remaining gap is the finding, not an oversight: see
// issue #277.
@(private)
capture_draw_screen :: proc(state: ^Capture_State, awaiting: sim.Phase, label: string) {
	#partial switch awaiting {
	case .Awaiting_Travel_Choice:
		// home_loop asserts the full-width chart page every frame; capture bypasses the
		// loop, so assert it here to shoot what the player would see.
		map_width_set(&state.game, MAP_HOME_W)
		draw_home(&state.game, ship_framing_moored(), Build_Drag{}, nil, NO_MOUSE, 0)
	case .Awaiting_Option_Choice:
		draw_offer_shop(&state.game, offer_shop_alongside(), Shelf_Drag{}, NO_MOUSE)
	case .Awaiting_Trade_Choice:
		draw_trade(&state.game, NO_MOUSE)
	case .Awaiting_Battle_Command:
		draw_fight(&state.game, NO_MOUSE)
	case .Ended:
		// The end-of-voyage beat, which is the whole of that screen: the same headline over
		// the same scene the dispatch plays it over.
		draw_beat(&state.game, voyage_end_headline(state.game.status))
	case:
		draw_scene(&state.game, fmt.tprintf("[capture] %s", label), NO_MOUSE)
	}
}

// capture_phase_slug names a decision screen for its filename. The Phase is the only
// thing distinguishing one screen from another here, which is itself a limit worth
// naming: capture can ask for "the trade screen", not for "the trade screen at the
// third Deep node".
@(private)
capture_phase_slug :: proc(awaiting: sim.Phase) -> string {
	switch awaiting {
	case .Awaiting_Travel_Choice:
		return "travel"
	case .Awaiting_Battle_Command:
		return "battle"
	case .Awaiting_Option_Choice:
		return "options"
	case .Awaiting_Trade_Choice:
		return "trade"
	case .Awaiting_Refit:
		return "refit"
	case .Ended:
		return "ended"
	}
	return "unknown"
}

// capture_requested reports whether the process was started as a capture run.
capture_requested :: proc() -> bool {
	return slice.contains(os.args[1:], "--capture")
}

// capture_shot_requested reports the single screen the process was started to shoot.
capture_shot_requested :: proc() -> (name: string, requested: bool) {
	return capture_shot_arg(os.args[1:])
}

// capture_shots_requested reports whether the process was started to render the whole
// standalone set.
capture_shots_requested :: proc() -> bool {
	return capture_shots_arg(os.args[1:])
}

// capture_shots_arg reads `--shots` out of a command line. It takes no name, so it is a
// whole-word match: `--shot build` is one screen and must not read as the set.
@(private)
capture_shots_arg :: proc(args: []string) -> bool {
	return slice.contains(args, "--shots")
}

// capture_shot_arg reads `--shot <name>` (or `--shot=<name>`) out of a command line. A
// bare --shot is a request naming nothing, which falls into the unknown-name report
// listing what can be asked for.
@(private)
capture_shot_arg :: proc(args: []string) -> (name: string, requested: bool) {
	return arg_value(args, "--shot")
}
