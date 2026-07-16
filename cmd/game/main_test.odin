package main

import "core:testing"
import combat "../../core/combat"
import run "../../core/run"
import ship "../../core/ship"
import sim "../../core/sim"

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
	voyage_map := run.voyage_map_create(0)
	defer run.voyage_map_destroy(&voyage_map)

	state := Game_State{}
	defer delete(state.visited)
	defer delete(state.positions)
	defer delete(state.voyage_map.nodes) // dispatch clones the map's nodes into UI-owned storage

	dispatch(&state, sim.Event(sim.Event_Voyage_Started{voyage_map = voyage_map, ship = state.player}))
	dispatch(&state, sim.Event(sim.Event_Travel_Options{options = []sim.Node_ID{1, 2}}))
	dispatch(&state, sim.Event(sim.Event_Arrived_At_Node{node = voyage_map.nodes[0]}))
	dispatch(&state, sim.Event(sim.Event_Ship_Battle_Sighted{opponent = state.player}))
	dispatch(&state, sim.Event(sim.Event_Battle_Menu{may_leave = true}))
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
	dispatch(&state, sim.Event(sim.Event_Encounter_Resolved{snapshot = run.Ghost_Snapshot{}}))
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
option_menu_loop_falls_back_to_declining_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}

	cmd := option_menu_loop(&state)

	choice, ok := cmd.(sim.Command_Choose_Option)
	testing.expect(t, ok)
	_, has_selection := choice.selection.?
	testing.expect(t, !has_selection) // nil selection == decline: skip an Offer, leave a Shop
}

@(test)
refit_menu_loop_falls_back_to_finish_without_a_live_window :: proc(t: ^testing.T) {
	state := Game_State{}

	cmd := refit_menu_loop(&state)

	refit, ok := cmd.(sim.Command_Refit)
	testing.expect(t, ok)
	_, is_finish := refit.command.(sim.Refit_Finish)
	testing.expect(t, is_finish)
}

@(test)
refit_click_maps_clicks_to_loadout_operations :: proc(t: ^testing.T) {
	// The place/swap/move/finish interaction is pure state logic, testable
	// without a live window (issue #96).
	s := ship.ship_starting_ship()
	defer delete(s.layout)
	state := Game_State{player = s}
	finish := len(s.layout)
	// Starting slots: 0 top deck (M) Captain's Quarters, 2 gun deck (L) Gun Deck,
	// 4 hold 1 (M) Cargo. Place a Medium item so the swap/move slots line up.

	// Finish box commits a Refit_Finish.
	cmd, ready := refit_click(&state, finish, finish)
	testing.expect(t, ready)
	refit, _ := cmd.(sim.Command_Refit)
	_, is_finish := refit.command.(sim.Refit_Finish)
	testing.expect(t, is_finish)

	// Placing a Medium item: clicking any filled slot emits Refit_Replace and lets
	// the Sim decide the fit — the menu no longer predicts the size match (issue
	// #111). Slot 0 holds Captain's Quarters (Medium).
	state.refit_incoming = ship.ship_fitting_top_crew() // Medium
	cmd, ready = refit_click(&state, 0, finish)
	testing.expect(t, ready)
	refit, _ = cmd.(sim.Command_Refit)
	replace, is_replace := refit.command.(sim.Refit_Replace)
	testing.expect(t, is_replace)
	testing.expect_value(t, replace.slot, ship.Slot_Index(0))

	// A filled slot of a different size (2 is a Large Gun Deck) is no longer
	// ignored: the menu emits the same Refit_Replace and the Sim rejects the size
	// mismatch (Event_Refit_Rejected), rather than the menu re-checking the rule.
	cmd, ready = refit_click(&state, 2, finish)
	testing.expect(t, ready)
	refit, _ = cmd.(sim.Command_Refit)
	replace, is_replace = refit.command.(sim.Refit_Replace)
	testing.expect(t, is_replace)
	testing.expect_value(t, replace.slot, ship.Slot_Index(2))

	// An empty same-size slot installs the pending item.
	state.player.layout[4].fitting = nil // hold 1, Medium
	cmd, ready = refit_click(&state, 4, finish)
	testing.expect(t, ready)
	refit, _ = cmd.(sim.Command_Refit)
	install, is_install := refit.command.(sim.Refit_Install)
	testing.expect(t, is_install)
	testing.expect_value(t, install.slot, ship.Slot_Index(4))

	// Rearranging (no pending item): select a filled source, then move it to the
	// empty slot 4.
	state.refit_incoming = nil
	state.refit_move_from = nil
	_, ready = refit_click(&state, 0, finish)
	testing.expect(t, !ready) // selecting, not committing
	from, selecting := state.refit_move_from.?
	testing.expect(t, selecting)
	testing.expect_value(t, from, ship.Slot_Index(0))
	cmd, ready = refit_click(&state, 4, finish)
	testing.expect(t, ready)
	refit, _ = cmd.(sim.Command_Refit)
	move, is_move := refit.command.(sim.Refit_Move)
	testing.expect(t, is_move)
	testing.expect_value(t, move.from, ship.Slot_Index(0))
	testing.expect_value(t, move.to, ship.Slot_Index(4))
	_, still_selecting := state.refit_move_from.?
	testing.expect(t, !still_selecting) // move committed, selection cleared

	// Clicking the selected source again cancels the move.
	_, _ = refit_click(&state, 0, finish)
	_, ready = refit_click(&state, 0, finish)
	testing.expect(t, !ready)
	_, still_selecting = state.refit_move_from.?
	testing.expect(t, !still_selecting)
}

// encounter_of bakes a stage list into an Encounter, as generation would from a recipe
// — the shorthand the #139 view tests are written in.
encounter_of :: proc(stages: ..run.Stage) -> run.Encounter {
	e := run.Encounter{count = len(stages)}
	for stage, i in stages {
		e.stages[i] = stage
	}
	return e
}

// node_of is an Encounter node holding that stage list, as presentation is handed one on
// Event_Arrived_At_Node (or, for a revealing encounter, at voyage start).
node_of :: proc(stages: ..run.Stage) -> run.Node {
	return run.Node{kind = .Encounter, zone = run.Zone.Coastal, encounter = encounter_of(..stages)}
}

@(test)
a_revealed_encounter_is_labelled_a_port_not_its_primitive :: proc(t: ^testing.T) {
	// Issue #139's smallest AC, and the last of the map's per-kind vocabulary: a `[Shop]`
	// used to read "Shop" because the label came straight off the stage. A node that
	// *opens* on a Shop is a Port — ADR-0016's "opens on a Shop" ≡ "reveals" ≡ "is a
	// Port" — so the map says what the captain is looking at rather than which primitive
	// generation baked.
	_, label := node_appearance(node_of(run.Stage_Shop{}), false)
	testing.expect_value(t, label, "Port")
}

@(test)
node_appearance_renders_the_mask_it_was_given_and_never_re_derives_it :: proc(t: ^testing.T) {
	// ADR-0009's hiding contract is the Sim's to keep: a hidden encounter's stages are
	// simply absent from the payload (sim_mask_encounters), so there is nothing here to
	// leak and nothing to decide.
	masked := run.Node{kind = .Encounter, zone = run.Zone.Coastal}
	_, label := node_appearance(masked, false)
	testing.expect_value(t, label, "")

	// A merchant carries a Shop but does not *open* on one, so it is a windfall met at
	// sea, not a market to route to (ADR-0016). The Sim masks it, so this node shape
	// should never reach the view unvisited — but the view asks voyage_encounter_reveals,
	// the same predicate the mask does, so handed the stages anyway it agrees rather than
	// inventing a second rule that could drift.
	_, label = node_appearance(node_of(run.Stage_Fight{}, run.Stage_Shop{}), false)
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
	walked := encounter_of(run.Stage_Fight{}, run.Stage_Reward{})
	walked.cursor = walked.count
	node := run.Node{kind = .Encounter, zone = run.Zone.Coastal, encounter = walked}

	_, label := node_appearance(node, true)
	testing.expect_value(t, label, "Battle")
}

@(test)
a_visited_node_keeps_its_marker_faded :: proc(t: ^testing.T) {
	fought := node_of(run.Stage_Fight{})

	color, label := node_appearance(fought, true)
	testing.expect_value(t, label, "Battle") // where you have been, and what it was

	full, _ := node_marker(.Fight)
	testing.expect(t, color.a < full.a) // ...but faded: the walk is over, ADR-0014 resolves once
}

@(test)
a_halt_beat_names_the_stages_it_forfeits :: proc(t: ^testing.T) {
	// Issue #139's central AC: fleeing a [Fight, Reward] must *visibly* cost the reward.
	// The model says so by never reaching the stage, which is silent; this is the line
	// that makes the silence legible.
	nodes := [1]run.Node{node_of(run.Stage_Fight{}, run.Stage_Reward{})}
	state := Game_State{voyage_map = run.Map{nodes = nodes[:]}}

	text := halt_beat_text(&state, sim.Event_Encounter_Halted{at = .Fight, index = 0, count = 2})
	testing.expect_value(t, text, "You break off and slip away. You leave behind: Loot.")

	// A halt on the *last* stage forfeits nothing downstream, so it says so instead of
	// naming an empty list — skipping a one-stage Offer must not read as a loss.
	skipped := [1]run.Node{node_of(run.Stage_Offer{})}
	state = Game_State{voyage_map = run.Map{nodes = skipped[:]}}
	text = halt_beat_text(&state, sim.Event_Encounter_Halted{at = .Offer, index = 0, count = 1})
	testing.expect_value(t, text, "You take nothing. The encounter ends here.")

	// Everything behind the cursor is named, not just the next one.
	deep := [1]run.Node{node_of(run.Stage_Trade{}, run.Stage_Shop{}, run.Stage_Reward{})}
	state = Game_State{voyage_map = run.Map{nodes = deep[:]}}
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
only_a_stage_with_no_screen_of_its_own_gets_an_entry_beat :: proc(t: ^testing.T) {
	// The pacing rule #139 settled: a stage that parks for a decision is seen as its own
	// screen, so the strip is all it needs. Reward parks nowhere (#133) — it pays out and
	// the walk carries straight on — so without a beat a [Fight, Reward]'s whole loot is a
	// cargo that silently grew. Under `odin test` play_beat is a no-op, so this pins the
	// selection rule rather than the render: every kind is handled, and only Reward looks
	// its content up.
	nodes := [1]run.Node{node_of(run.Stage_Reward{cargo = 30})}
	state := Game_State{voyage_map = run.Map{nodes = nodes[:]}}

	for kind in run.Stage_Kind {
		play_stage_entry_beat(&state, sim.Event_Stage_Entered{kind = kind, index = 0, count = 1})
	}

	// A Reward beat reads its amount off the arrival copy, so an index past the encounter
	// (which the Sim cannot emit) must decline rather than index out of bounds.
	play_stage_entry_beat(&state, sim.Event_Stage_Entered{kind = .Reward, index = 2, count = 3})
}

@(test)
fitting_effect_intent_describes_each_effect_kind :: proc(t: ^testing.T) {
	flat := ship.Fitting{category = .Fire, active = ship.Effect{magnitude = 5}}
	testing.expect_value(t, fitting_effect_intent(flat), "+5 Offense")

	dur := ship.Fitting{category = .Brace, passive = ship.Effect{kind = .Modify_Durability, magnitude = 2}}
	testing.expect_value(t, fitting_effect_intent(dur), "+2 Durability")

	synergy := ship.Fitting{category = .Muster, active = ship.Effect{magnitude = 2, synergy = ship.Selector(ship.Tag.Weapon)}}
	testing.expect_value(t, fitting_effect_intent(synergy), "+2 Muster per Weapon")

	conditional := ship.Fitting{category = .Fire, active = ship.Effect{magnitude = 8, conditional = ship.Condition_Hull_Below{percent = 50}}}
	testing.expect_value(t, fitting_effect_intent(conditional), "+8 Offense below 50% Hull")

	cargo := ship.ship_fitting_cargo("Cargo", .Small, 10)
	testing.expect_value(t, fitting_effect_intent(cargo), "no effect")
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
