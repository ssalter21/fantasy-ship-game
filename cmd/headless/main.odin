package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import ship "../../core/ship"
import voyage "../../core/voyage"
import sim "../../core/sim"

main :: proc() {
	req, ok := headless_request(os.args[1:])
	if !ok {
		fmt.eprintln(
			"headless: usage: headless [--seed <n>] [--runs <n>] [--out <path>] [--fights <path>]",
		)
		os.exit(1)
	}

	destination := req.out.? or_else "stdout"
	out, opened := headless_open_destination(req.out)
	if !opened {
		fmt.eprintfln("headless: cannot open %s for writing", destination)
		os.exit(1)
	}

	// The Fight rows go to their own file or nowhere: two CSVs of different shapes cannot
	// share one destination, so there is no stdout fallback for this one.
	fights: Maybe(^os.File)
	if path, named := req.fights.?; named {
		file, fights_opened := headless_open_destination(path)
		if !fights_opened {
			fmt.eprintfln("headless: cannot open %s for writing", path)
			os.exit(1)
		}
		fights = file
	}

	// stdout is not this run's to close, and a file's close is a write's last chance to fail,
	// so it counts toward whether the sweep landed.
	wrote := headless_sweep(req, out, fights)
	closed := out == os.stdout || os.close(out) == nil
	if file, writing_fights := fights.?; writing_fights {
		closed = os.close(file) == nil && closed
	}
	if !wrote || !closed {
		// Both destinations are named, because either one's write is what the sweep failed on.
		failed := destination
		if path, named := req.fights.?; named {
			failed = fmt.tprintf("%s and %s", destination, path)
		}
		fmt.eprintfln("headless: could not write the sweep to %s", failed)
		os.exit(1)
	}
}

// Run_Request is the run a command line asked for: `runs` voyages from consecutive seeds
// starting at `seed`, so repeating the pair repeats the whole sweep, with the rows written to
// `out` — a path, or nil for stdout — and the per-Fight rows to `fights`, a path or nil for
// none at all. Its zero value is a run of no voyages, which is nothing —
// headless_request starts from the one-voyage default instead (a deliberate break with the
// zero-value-is-meaningful rule).
Run_Request :: struct {
	seed:   u64,
	runs:   int,
	out:    Maybe(string),
	fights: Maybe(string),
}

// headless_request reads the run out of a command line, in either `--flag <value>` or
// `--flag=<value>` spelling. Absent flags give one voyage from seed 0, written to stdout.
//
// Anything it cannot read as a runnable request is rejected: an unknown flag, a bare word,
// a non-number, a run of none, an empty path, a flag whose value is the next flag, or the two
// paths naming one file. A sweep script that misspells `--seed` gets an error rather than a
// thousand voyages from the wrong seed. A spaced value that itself begins `--` is refused
// before any flag's own reading of it, which is the only guard a path can have — it is
// otherwise any string at all.
headless_request :: proc(args: []string) -> (req: Run_Request, ok: bool) {
	req = Run_Request{seed = 0, runs = 1, out = nil, fights = nil}

	for i := 0; i < len(args); {
		flag, value := args[i], ""
		if eq := strings.index_byte(flag, '='); eq >= 0 {
			flag, value = flag[:eq], flag[eq + 1:]
			i += 1
		} else if i + 1 < len(args) && !strings.has_prefix(args[i + 1], "--") {
			value = args[i + 1]
			i += 2
		} else {
			return req, false // a flag at the tail, or one naming the next flag as its value
		}

		switch flag {
		case "--seed":
			req.seed = strconv.parse_u64(value) or_return
		case "--runs":
			req.runs = strconv.parse_int(value) or_return
			if req.runs < 1 {
				return req, false
			}
		case "--out":
			if value == "" {
				return req, false
			}
			req.out = value
		case "--fights":
			if value == "" {
				return req, false
			}
			req.fights = value
		case:
			return req, false
		}
	}
	// An unnamed `--out` reads as "", which no accepted `--fights` path can be, so stdout
	// never collides with a file here.
	fights_path, writing_fights := req.fights.?
	out_path := req.out.? or_else ""
	if writing_fights && fights_path == out_path {
		return req, false
	}
	return req, true
}

// headless_voyage runs one scripted voyage from a seed and reports how it ended, as the row
// a sweep writes for it, together with a row per battle fought along the way.
//
// The Sim is built and destroyed here, so a sweep holds one voyage's run-scoped arena at a
// time (ADR-0010) rather than a thousand. Only values cross back out: everything the sink
// tracked by reference — the Event it last saw, the Map, the travel options — borrows from
// that arena and is gone by the time this returns. That is why the row is assembled here,
// while the Sim still stands: the ship's cargo is summed across its layout (ship_cargo), and
// that layout is arena-borrowed like the rest. The Fight rows are plain values and static
// archetype names, so they cross out safely; the array carrying them is the caller's to
// delete.
headless_voyage :: proc(seed: u64, quiet: bool) -> (Voyage_Row, [dynamic]Fight_Row) {
	s := sim.sim_create(seed)
	defer sim.sim_destroy(&s)

	state := Headless_State{fights = {seed = seed}}
	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}
	sink := sim.Event_Sink{data = &state, dispatch = quiet ? headless_track : headless_print}

	sim.run_session(&s, input, sink)

	// The last battle of a voyage has no next sighting to close it.
	fight_log_close(&state.fights)

	row := Voyage_Row {
		seed       = seed,
		status     = state.status,
		zone       = state.deepest_zone,
		nodes      = state.nodes,
		hull       = state.view.player.hull,
		cargo      = ship.ship_cargo(state.view.player),
		encounters = state.encounters,
		events     = state.event_count,
	}
	return row, state.fights.rows
}

// Headless_State is the shared context the Input_Source and Event_Sink halves of
// the auto-player cooperate through — each callback receives only its own rawptr,
// so shared state has nowhere else to live.
//
// It counts events rather than keeping them: an Event borrows from the Sim's run arena,
// so a kept copy is only valid as long as the Sim is. status, the counts and the zone are
// what both sinks leave behind for a caller that outlives the Sim — plain values, and the
// whole of what a Voyage_Row is assembled from. `view` is the scripted player's own input,
// filled by the sink from the same stream: the map, ship and stage state it decides from all
// borrow from the Sim's arena too, and are read only while it lives.
//
// `fights` is the other thing that leaves: the Fight rows of this voyage, filled from the same
// stream and from the orders get_captain_choice submits. `site` is the one thing a Fight row
// needs that no battle Event carries — the stakes of the node the walk is standing on.
Headless_State :: struct {
	event_count:  int,
	last_event:   sim.Event, // borrowed from the Sim's run arena; valid only while it lives
	status:       voyage.Voyage_Status,
	nodes:        int,
	encounters:   int,
	deepest_zone: Maybe(voyage.Zone),
	site:         voyage.Scaling_Site,
	view:         sim.Scripted_View,
	fights:       Fight_Log,
}

// get_captain_choice is the headless Input_Source: it hands the shared scripted
// player (sim.scripted_player_command) the voyage state the sink tracked.
//
// A battle order is recorded on its way out, because it is the one half of a Fight row the
// Event stream cannot supply: the Sim broadcasts what a round *did*, never which order was
// given for it.
get_captain_choice :: proc(data: rawptr, awaiting: sim.Phase) -> sim.Command {
	state := cast(^Headless_State)data
	cmd := sim.scripted_player_command(state.view, awaiting)
	if battle, is_battle := cmd.(sim.Command_Battle_Choice); is_battle {
		fight_log_order(&state.fights, battle.combat_command)
	}
	return cmd
}

// headless_print is the printing sink: format the event, then track it like the quiet one
// does. The line is the whole difference between the two.
//
// It prints to stderr because stdout is where the rows go when no path was named, and a
// voyage's events are commentary on a run rather than its output — so watching a single run
// go by and piping its row are the same command.
headless_print :: proc(data: rawptr, event: sim.Event) {
	fmt.eprintfln("%v", event)
	headless_track(data, event)
}

// headless_track is the quiet sink: count every event, keep the voyage's outcome, and
// keep the scripted player's view of the voyage current — all of it without formatting a
// thing. The view's fields are the facts the player decides from, each taken from the one
// Event that carries it (sim.Scripted_View).
// Event_Encounter_Resolved.snapshot needs no cleanup here — it lives in the Sim's
// run-scoped arena and is freed wholesale by sim_destroy, not owned per-recipient.
headless_track :: proc(data: rawptr, event: sim.Event) {
	state := cast(^Headless_State)data
	state.event_count += 1
	state.last_event = event

	switch e in event {
	case sim.Event_Voyage_Started:
		state.view.voyage_map = e.voyage_map
		state.view.player = e.ship
	case sim.Event_Travel_Options:
		state.view.travel_options = e.options
	case sim.Event_Arrived_At_Node:
		state.view.current = e.node.id
		state.nodes += 1
		// The deepest zone, not the latest: travel back to an already-visited node is legal
		// (voyage_neighbor_is_legal), and how far the voyage got is the fact a row carries.
		// Zone is declared in stakes order, so the deeper zone is the greater one.
		if zone, zoned := e.node.zone.?; zoned {
			if deepest, reached := state.deepest_zone.?; !reached || zone > deepest {
				state.deepest_zone = zone
			}
			// The stakes a battle at this node is fought at, kept as the latest rather than
			// the deepest — it is where the walk *is*, not how far it got.
			state.site = voyage.Scaling_Site{zone = zone, depth = e.node.depth}
		}
	case sim.Event_Voyage_Ended:
		state.status = e.status
	case sim.Event_Battle_Menu:
		state.view.may_press = e.may_press
	case sim.Event_Ship_Updated:
		state.view.player = e.ship
	case sim.Event_Options_Presented:
		state.view.stage_options = e.options
	case sim.Event_Trade_Presented:
		state.view.trade = e.trade
		state.view.trade_can_accept = e.can_accept
	case sim.Event_Refit_Started:
		state.view.refit_incoming = e.incoming
	case sim.Event_Fitting_Installed:
		// The incoming item has landed, so the refit has nothing left to place.
		state.view.refit_incoming = nil
	case sim.Event_Refit_Finished:
		state.view.refit_incoming = nil
	case sim.Event_Encounter_Resolved:
		// One per node walked to its end, whatever its stage list held — so this counts the
		// encounters the voyage got through, and the node it sank at is not one of them.
		state.encounters += 1
	case sim.Event_Ship_Battle_Sighted:
		// The player's Hull as it stands going in, off the latest Event_Ship_Updated the view
		// already tracks, and the opponent's as sighted — the two pools the swings come out of.
		fight_log_sighted(&state.fights, state.site, e.archetype, state.view.player.hull, e.opponent.hull)
	case sim.Event_Battle_Event:
		fight_log_battle_event(&state.fights, e.inner)
	case sim.Event_Wreck_Looted:
		fight_log_payout(&state.fights, e.gross)
	case sim.Event_Reward_Paid:
	case sim.Event_Stage_Entered:
	case sim.Event_Encounter_Halted:
	case sim.Event_Purchase_Rejected:
	case sim.Event_Fitting_Moved:
	case sim.Event_Fitting_Removed:
	case sim.Event_Cargo_Jettisoned:
	case sim.Event_Refit_Rejected:
	}
}
