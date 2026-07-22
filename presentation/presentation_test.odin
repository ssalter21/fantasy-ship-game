package presentation

import "core:testing"
import combat "../core/combat"
import voyage "../core/voyage"
import ship "../core/ship"
import sim "../core/sim"

// These smoke tests call the Input_Source/Event_Sink procs directly rather
// than through a live window: rl.IsWindowReady() is false under `odin
// test`, so every blocking menu_loop/play_beat call returns its harmless
// default immediately instead of entering a render loop (see
// get_captain_choice's and play_beat's IsWindowReady guards).

@(test)
get_captain_choice_returns_a_default_travel_choice_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}
	cmd := get_captain_choice(&state, .Awaiting_Travel_Choice)

	_, ok := cmd.(sim.Command_Travel_To)
	testing.expect(t, ok)
}

@(test)
dispatch_does_not_crash_on_any_event_variant_without_a_live_window :: proc(t: ^testing.T) {
	voyage_map := voyage.voyage_map_create(0)
	defer voyage.voyage_map_destroy(&voyage_map)

	state := Game_State{}
	defer delete(state.visited)
	defer delete(state.positions)
	defer delete(state.voyage_map.nodes) // dispatch clones the map's nodes into UI-owned storage

	dispatch(&state, sim.Event(sim.Event_Voyage_Started{voyage_map = voyage_map, ship = state.player}))
	dispatch(&state, sim.Event(sim.Event_Travel_Options{options = []sim.Node_ID{1, 2}}))
	dispatch(&state, sim.Event(sim.Event_Arrived_At_Node{node = voyage_map.nodes[0]}))
	dispatch(&state, sim.Event(sim.Event_Ship_Battle_Sighted{opponent = state.player}))
	dispatch(&state, sim.Event(sim.Event_Battle_Menu{may_break_off = true}))
	dispatch(&state, sim.Event(sim.Event_Battle_Event{inner = combat.Event(combat.Event_Battle_Ended{reason = .Destroyed})}))
	dispatch(&state, sim.Event(sim.Event_Ship_Updated{ship = state.player}))
	dispatch(&state, sim.Event(sim.Event_Stage_Entered{kind = .Fight, index = 0, count = 1}))
	dispatch(&state, sim.Event(sim.Event_Encounter_Halted{at = .Fight, index = 0, count = 1}))
	dispatch(&state, sim.Event(sim.Event_Options_Presented{}))
	dispatch(&state, sim.Event(sim.Event_Refit_Started{incoming = ship.ship_fitting_gun_deck()}))
	dispatch(&state, sim.Event(sim.Event_Fitting_Installed{slot = 0, fitting = ship.ship_fitting_gun_deck()}))
	dispatch(&state, sim.Event(sim.Event_Refit_Finished{}))
	dispatch(&state, sim.Event(sim.Event_Voyage_Ended{status = .Won}))
}

@(test)
dispatch_does_not_crash_on_an_encounter_resolved_event_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}
	defer delete(state.visited)
	defer delete(state.positions)

	// The snapshot's layout is arena-owned by the Sim (issue #52) — dispatch
	// takes no ownership of it, so this just confirms handling the variant
	// doesn't crash.
	dispatch(&state, sim.Event(sim.Event_Encounter_Resolved{snapshot = voyage.Ghost_Snapshot{}}))
}

@(test)
battle_menu_loop_falls_back_to_hold_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}

	cmd := battle_menu_loop(&state)

	choice, ok := cmd.(sim.Command_Battle_Choice)
	testing.expect(t, ok)
	_, is_hold := choice.combat_command.(combat.Command_Hold)
	testing.expect(t, is_hold)
}

@(test)
offer_shop_loop_falls_back_to_declining_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}

	cmd := offer_shop_loop(&state)

	choice, ok := cmd.(sim.Command_Choose_Option)
	testing.expect(t, ok)
	_, has_selection := choice.selection.?
	testing.expect(t, !has_selection) // nil selection == decline: skip an Offer, leave a Shop
}

@(test)
build_surface_loop_falls_back_to_finish_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}

	cmd := build_surface_loop(&state)

	refit, ok := cmd.(sim.Command_Refit)
	testing.expect(t, ok)
	_, is_finish := refit.command.(sim.Refit_Finish)
	testing.expect(t, is_finish)
}

@(test)
build_drop_command_maps_drags_to_loadout_operations :: proc(t: ^testing.T) {
	// The drag-first install/swap/move/discard mapping is pure state logic, testable
	// without a live window (#302 — the drag-first successor to refit_click's test). The
	// exact-size fit rule is the Sim's, so this only asserts which command a landed drag
	// emits, never whether the Sim will accept it.
	s := ship.ship_starting_ship()
	defer delete(s.layout)
	state := Game_State{player = s}
	// Starting slots: 0 top deck (M) Captain's Quarters, 2 gun deck (L) Gun Deck,
	// 3 forecastle (L) a bare hold, 4 hold 1 (M) a bare hold.

	// Every berth is occupied now — a free one carries a hold rather than nothing — so
	// a shelf drop always swaps in (Replace, discarding the occupant). The Install leg of
	// the mapping survives for a genuinely empty slot, which is unreachable in play.
	shelf := Build_Drag{active = true, from_slot = nil, fitting = ship.ship_fitting_top_crew()}
	cmd, ready, wants := build_drop_command(&state, shelf, ship.Slot_Index(3), false, false)
	testing.expect(t, ready)
	_, no_discard := wants.?
	testing.expect(t, !no_discard)
	refit, _ := cmd.(sim.Command_Refit)
	replace, is_replace := refit.command.(sim.Refit_Replace)
	testing.expect(t, is_replace)
	testing.expect_value(t, replace.slot, ship.Slot_Index(3))

	// The same on a berth holding a real fitting: the occupant is discarded.
	cmd, ready, _ = build_drop_command(&state, shelf, ship.Slot_Index(0), false, false)
	testing.expect(t, ready)
	refit, _ = cmd.(sim.Command_Refit)
	replace, is_replace = refit.command.(sim.Refit_Replace)
	testing.expect(t, is_replace)
	testing.expect_value(t, replace.slot, ship.Slot_Index(0))

	// Dropped in open water (no target) it returns to the shelf — no command.
	_, ready, _ = build_drop_command(&state, shelf, nil, false, false)
	testing.expect(t, !ready)

	// An installed fitting dragged onto another slot moves it there.
	slot_drag := Build_Drag{active = true, from_slot = ship.Slot_Index(0), fitting = ship.ship_fitting_captains_quarters()}
	cmd, ready, _ = build_drop_command(&state, slot_drag, ship.Slot_Index(4), false, false)
	testing.expect(t, ready)
	refit, _ = cmd.(sim.Command_Refit)
	move, is_move := refit.command.(sim.Refit_Move)
	testing.expect(t, is_move)
	testing.expect_value(t, move.from, ship.Slot_Index(0))
	testing.expect_value(t, move.to, ship.Slot_Index(4))

	// Dropped back on its own slot it cancels — no move.
	_, ready, _ = build_drop_command(&state, slot_drag, ship.Slot_Index(0), false, false)
	testing.expect(t, !ready)

	// Dragged onto the discard zone it asks for a confirm rather than committing.
	_, ready, wants = build_drop_command(&state, slot_drag, nil, true, false)
	testing.expect(t, !ready)
	discard, wants_discard := wants.?
	testing.expect(t, wants_discard)
	testing.expect_value(t, discard.slot, ship.Slot_Index(0))
	testing.expect(t, !discard.burn) // the bin takes the whole fitting off the ship
}

@(test)
dragging_a_laden_fitting_onto_the_ledger_asks_to_burn_its_cargo :: proc(t: ^testing.T) {
	// The out-of-combat burn (#401): a drag onto the hold ledger asks to burn one berth's
	// cargo, the fitting staying put. It is a *different* target from the discard bin, whose
	// meaning stays "this thing leaves the ship" — so a laden gun is never unremovable.
	s := ship.ship_starting_ship()
	defer delete(s.layout)
	state := Game_State{player = s}

	// Slot 5 (hold 2, Small) carries cargo out of the starting stow; slot 2 (the Gun Deck)
	// is all bulk and carries nothing.
	laden, _ := state.player.layout[5].fitting.?
	drag := Build_Drag{active = true, from_slot = ship.Slot_Index(5), fitting = laden}

	_, ready, wants := build_drop_command(&state, drag, nil, false, true)
	testing.expect(t, !ready) // a burn is confirmed first, never committed by the drop
	burn, wants_burn := wants.?
	testing.expect(t, wants_burn)
	testing.expect_value(t, burn.slot, ship.Slot_Index(5))
	testing.expect(t, burn.burn)

	// The bin's meaning is untouched by the load: a *laden* fitting dropped there still
	// leaves the ship whole, cargo and all. This is what keeps a laden gun removable — if
	// carrying something rerouted the bin to a burn, a gun with cargo in it could never be
	// taken off the ship at all.
	_, ready, wants = build_drop_command(&state, drag, nil, true, false)
	testing.expect(t, !ready)
	binned, wants_bin := wants.?
	testing.expect(t, wants_bin)
	testing.expect_value(t, binned.slot, ship.Slot_Index(5))
	testing.expect(t, !binned.burn)
	testing.expect_value(t, build_confirm_command(binned), sim.Command(sim.Command_Refit{command = sim.Refit_Remove{slot = 5}}))

	// A fitting carrying nothing has nothing to burn, so the ledger is inert under it.
	bare, _ := state.player.layout[2].fitting.?
	empty_drag := Build_Drag{active = true, from_slot = ship.Slot_Index(2), fitting = bare}
	_, ready, wants = build_drop_command(&state, empty_drag, nil, false, true)
	testing.expect(t, !ready)
	_, asks := wants.?
	testing.expect(t, !asks)

	// The shelf item is not cargo of the ship's, so dropping it on the ledger just returns
	// it to the shelf.
	shelf := Build_Drag{active = true, from_slot = nil, fitting = ship.ship_fitting_top_crew()}
	_, ready, wants = build_drop_command(&state, shelf, nil, false, true)
	testing.expect(t, !ready)
	_, shelf_asks := wants.?
	testing.expect(t, !shelf_asks)
}

@(test)
the_confirm_gate_commits_a_burn_and_a_discard_to_different_commands :: proc(t: ^testing.T) {
	// One confirm gate serves both destructive gestures, and which command it commits is
	// carried by the pending confirm — a burn empties the berth, a discard removes it.
	burn := build_confirm_command(Build_Confirm{slot = ship.Slot_Index(5), burn = true})
	refit, _ := burn.(sim.Command_Refit)
	jettison, is_jettison := refit.command.(sim.Refit_Jettison_Cargo)
	testing.expect(t, is_jettison)
	testing.expect_value(t, jettison.slot, ship.Slot_Index(5))

	discard := build_confirm_command(Build_Confirm{slot = ship.Slot_Index(5), burn = false})
	refit, _ = discard.(sim.Command_Refit)
	remove, is_remove := refit.command.(sim.Refit_Remove)
	testing.expect(t, is_remove)
	testing.expect_value(t, remove.slot, ship.Slot_Index(5))
}

// encounter_of bakes a stage list into an Encounter, as generation would from a recipe
// — the shorthand the #139 view tests are written in.
encounter_of :: proc(stages: ..voyage.Stage) -> voyage.Encounter {
	e := voyage.Encounter{count = len(stages)}
	for stage, i in stages {
		e.stages[i] = stage
	}
	return e
}

// node_of is an Encounter node holding that stage list, as presentation is handed one on
// Event_Arrived_At_Node (or, for a revealing encounter, at voyage start).
node_of :: proc(stages: ..voyage.Stage) -> voyage.Node {
	return voyage.Node{kind = .Encounter, zone = voyage.Zone.Coastal, encounter = encounter_of(..stages)}
}

@(test)
a_revealed_encounter_is_labelled_a_port_not_its_primitive :: proc(t: ^testing.T) {
	// Issue #139's smallest AC, and the last of the map's per-kind vocabulary: a `[Shop]`
	// used to read "Shop" because the label came straight off the stage. A node that
	// *opens* on a Shop is a Port — ADR-0016's "opens on a Shop" ≡ "reveals" ≡ "is a
	// Port" — so the map says what the captain is looking at rather than which primitive
	// generation baked.
	_, label := node_appearance(node_of(voyage.Stage_Shop{}), false)
	testing.expect_value(t, label, "Port")
}

@(test)
node_appearance_renders_the_mask_it_was_given_and_never_re_derives_it :: proc(t: ^testing.T) {
	// ADR-0009's hiding contract is the Sim's to keep: a hidden encounter's stages are
	// simply absent from the payload (sim_mask_encounters), so there is nothing here to
	// leak and nothing to decide.
	masked := voyage.Node{kind = .Encounter, zone = voyage.Zone.Coastal}
	_, label := node_appearance(masked, false)
	testing.expect_value(t, label, "")

	// A merchant carries a Shop but does not *open* on one, so it is a windfall met at
	// sea, not a market to route to (ADR-0016). The Sim masks it, so this node shape
	// should never reach the view unvisited — but the view asks voyage_encounter_reveals,
	// the same predicate the mask does, so handed the stages anyway it agrees rather than
	// inventing a second rule that could drift.
	_, label = node_appearance(node_of(voyage.Stage_Fight{}, voyage.Stage_Shop{}), false)
	testing.expect_value(t, label, "")
}

@(test)
a_node_is_labelled_by_the_stage_it_opens_with_not_by_its_cursor :: proc(t: ^testing.T) {
	// The contingency #161 left commented at both ends: reveal is defined on stage 0
	// while the label used to come from voyage_encounter_current, i.e. the **cursor**.
	//
	// #161 read that as latent-but-harmless because a walked-out node's cursor sits past
	// the end and would fall through to a blank marker. It never did — presentation's copy
	// of a node is taken at arrival, before the walk, and the walk advances the *Sim's*
	// private map, so this cursor is frozen at 0 for the rest of the voyage and the two rules
	// could not drift because one was reading a constant. This pins the rule that was
	// always meant, against a cursor deliberately walked off the end: a fought-out
	// [Fight, Reward] is a Battle on the map, not a blank, and not "Loot".
	walked := encounter_of(voyage.Stage_Fight{}, voyage.Stage_Reward{})
	walked.cursor = walked.count
	node := voyage.Node{kind = .Encounter, zone = voyage.Zone.Coastal, encounter = walked}

	_, label := node_appearance(node, true)
	testing.expect_value(t, label, "Battle")
}

@(test)
each_revealed_stage_kind_inks_a_distinct_doodle :: proc(t: ^testing.T) {
	// Build step 3 (#348) split the blue chart's single "diamond + hue" into one
	// cartographer's-hand doodle per revealed opening, so a captain reads what a known stop
	// holds from its shape alone, without a legend (spec §3). A Shop opening is the Port's
	// anchor; the four others each take their own mark. Visited so a non-revealing kind still
	// shows its identity (only a Shop opening reveals unvisited, ADR-0016).
	testing.expect_value(t, node_mark(node_of(voyage.Stage_Shop{}), true), Node_Mark.Anchor)
	testing.expect_value(t, node_mark(node_of(voyage.Stage_Fight{}), true), Node_Mark.Cutlasses)
	testing.expect_value(t, node_mark(node_of(voyage.Stage_Offer{}), true), Node_Mark.Scroll)
	testing.expect_value(t, node_mark(node_of(voyage.Stage_Trade{}), true), Node_Mark.Scales)
	testing.expect_value(t, node_mark(node_of(voyage.Stage_Reward{}), true), Node_Mark.Chest)
}

@(test)
a_masked_stop_is_a_buoy_and_landmarks_keep_their_marks :: proc(t: ^testing.T) {
	// The Sim hides encounter identity by dropping the encounter (encounter = nil); that
	// masked stop is the dotted "?" buoy — the whole of the fog (spec §7). Start and Haven are
	// landmarks, not stages, so they keep their own marks regardless of visited state.
	masked := voyage.Node{kind = .Encounter, zone = voyage.Zone.Coastal}
	testing.expect_value(t, node_mark(masked, false), Node_Mark.Buoy)
	testing.expect_value(t, node_mark(voyage.Node{kind = .Start}, false), Node_Mark.Home)
	testing.expect_value(t, node_mark(voyage.Node{kind = .Haven}, false), Node_Mark.Island)
}

@(test)
node_identity_ink_never_spends_coral :: proc(t: ^testing.T) {
	// Coral (#E1552B) is the parchment's one warm accent, reserved for the Haven X and the
	// danger tick (spec §3/§8) — the destination and the risks, nothing else. Node *identity*
	// inks strong sepia or recedes to faded-ink, so the eye is only ever pulled to those two
	// things. This pins that contract across every kind and both visited states; the coral X
	// is drawn inside draw_haven_island, not returned as a node's identity ink.
	nodes := []voyage.Node {
		{kind = .Start},
		{kind = .Haven},
		node_of(voyage.Stage_Shop{}),
		node_of(voyage.Stage_Fight{}),
		node_of(voyage.Stage_Offer{}),
		node_of(voyage.Stage_Trade{}),
		node_of(voyage.Stage_Reward{}),
		{kind = .Encounter, zone = voyage.Zone.Coastal}, // masked buoy
	}
	for n in nodes {
		for visited in ([]bool{false, true}) {
			color, _ := node_appearance(n, visited)
			is_coral := color.r == INK_CORAL.r && color.g == INK_CORAL.g && color.b == INK_CORAL.b
			testing.expect(t, !is_coral)
		}
	}
}

@(test)
a_visited_node_keeps_its_marker_faded :: proc(t: ^testing.T) {
	fought := node_of(voyage.Stage_Fight{})

	color, label := node_appearance(fought, true)
	testing.expect_value(t, label, "Battle") // where you have been, and what it was

	full := stage_tint(.Fight)
	testing.expect(t, color.a < full.a) // ...but faded: the walk is over, ADR-0014 resolves once
}

@(test)
a_halt_beat_names_the_stages_it_forfeits :: proc(t: ^testing.T) {
	// Issue #139's central AC: fleeing a [Fight, Reward] must *visibly* cost the reward.
	// The model says so by never reaching the stage, which is silent; this is the line
	// that makes the silence legible.
	nodes := [1]voyage.Node{node_of(voyage.Stage_Fight{}, voyage.Stage_Reward{})}
	state := Game_State{voyage_map = voyage.Map{nodes = nodes[:]}}

	text := halt_beat_text(&state, sim.Event_Encounter_Halted{at = .Fight, index = 0, count = 2})
	testing.expect_value(t, text, "You break off and slip away. You leave behind: Loot.")

	// A halt on the *last* stage forfeits nothing downstream, so it says so instead of
	// naming an empty list — skipping a one-stage Offer must not read as a loss.
	skipped := [1]voyage.Node{node_of(voyage.Stage_Offer{})}
	state = Game_State{voyage_map = voyage.Map{nodes = skipped[:]}}
	text = halt_beat_text(&state, sim.Event_Encounter_Halted{at = .Offer, index = 0, count = 1})
	testing.expect_value(t, text, "You take nothing. The encounter ends here.")

	// Everything behind the cursor is named, not just the next one.
	deep := [1]voyage.Node{node_of(voyage.Stage_Trade{}, voyage.Stage_Shop{}, voyage.Stage_Reward{})}
	state = Game_State{voyage_map = voyage.Map{nodes = deep[:]}}
	text = halt_beat_text(&state, sim.Event_Encounter_Halted{at = .Trade, index = 0, count = 3})
	testing.expect_value(t, text, "You turn the bargain down. You leave behind: Market, Loot.")
}

@(test)
the_encounter_strip_tracks_the_walk_and_clears_when_it_is_over :: proc(t: ^testing.T) {
	// The strip is presentation's only view of the cursor (issue #139), so it lives and
	// dies by these two events.
	state := Game_State{}

	dispatch(&state, sim.Event(sim.Event_Stage_Entered{kind = .Trade, index = 1, count = 3}))
	progress, walking := state.stage_progress.?
	testing.expect(t, walking)
	testing.expect_value(t, progress.index, 1)
	testing.expect_value(t, progress.count, 3)

	// Being asked where to sail *is* the end of the walk — the Sim emits travel options
	// only from Awaiting_Travel_Choice — so no end-of-encounter event is needed to clear
	// the strip off the map.
	dispatch(&state, sim.Event(sim.Event_Travel_Options{options = []sim.Node_ID{1}}))
	_, still_walking := state.stage_progress.?
	testing.expect(t, !still_walking)
}

@(test)
the_reward_beat_reports_the_haul_and_names_any_spill :: proc(t: ^testing.T) {
	// The beat renders Event_Reward_Paid's outcome as-is (#431) — no capacity math of
	// its own — so what it says and what the Sim did are one fact. The spill clause
	// appears only when something actually went overboard.
	testing.expect_value(t, reward_beat_text(30, 0), "Salvage! You haul aboard 30 cargo.")
	testing.expect_value(
		t,
		reward_beat_text(30, 12),
		"Salvage! You haul aboard 30 cargo. 12 spills overboard — your hold is full.",
	)
}

@(test)
fitting_effect_intent_describes_each_effect_kind :: proc(t: ^testing.T) {
	flat := ship.ship_fitting_with_effects(ship.Fitting{}, ship.effect_phase_contribution(ship.expr_const(5)))
	testing.expect_value(t, fitting_effect_intent(flat), "+5 Offense")

	repair := ship.ship_fitting_with_effects(ship.Fitting{}, ship.effect_repair(ship.expr_const(2)))
	testing.expect_value(t, fitting_effect_intent(repair), "+2 Repair")

	synergy := ship.ship_fitting_with_effects(ship.Fitting{}, ship.effect_phase_contribution(ship.expr_const(2), ship.Selector(ship.Tag.Weapon)))
	testing.expect_value(t, fitting_effect_intent(synergy), "+2 Offense per Weapon")

	conditional := ship.ship_fitting_with_effects(ship.Fitting{}, ship.effect_phase_contribution(ship.expr_below_hull_percent(50, 8)))
	testing.expect_value(t, fitting_effect_intent(conditional), "+8 Offense when its condition holds")

	hold := ship.ship_fitting_hold(.Small)
	testing.expect_value(t, fitting_effect_intent(hold), "no effect")
}

@(test)
fitting_tags_label_lists_every_family :: proc(t: ^testing.T) {
	multi := ship.Fitting{tags = {.Crew, .Weapon}}
	testing.expect_value(t, fitting_tags_label(multi.tags), "Crew, Weapon")

	none := ship.Fitting{}
	testing.expect_value(t, fitting_tags_label(none.tags), "none")
}

@(test)
version_defaults_to_dev_without_the_git_sha_define :: proc(t: ^testing.T) {
	// Built under `odin test` (no -define:GIT_SHA), the compile-time stamp
	// falls back to its #config default. A build passing -define:GIT_SHA=...
	// overrides this; issue #44.
	testing.expect_value(t, VERSION, "dev")
}

@(test)
draw_version_stamp_does_not_crash_without_a_live_window :: proc(t: ^testing.T) {
	// Respects the same IsWindowReady() guard as the rest of the render
	// layer (ADR-0003): a no-op under `odin test` rather than a raylib call
	// with no live window.
	draw_version_stamp()
}
