package main

import "core:testing"
import sim "../../core/sim"

// These cover the scripted half of capture — the half that has no window in it.
// The drawing half can't be tested here for the same reason the menu loops can't:
// rl.IsWindowReady() is false under `odin test`, and capture_shot guards on it.

@(test)
capture_scripted_command_answers_every_non_travel_phase :: proc(t: ^testing.T) {
	state := Capture_State{}

	battle := capture_scripted_command(&state, .Awaiting_Battle_Command)
	_, is_battle := battle.(sim.Command_Battle_Choice)
	testing.expect(t, is_battle)

	options := capture_scripted_command(&state, .Awaiting_Option_Choice)
	choose, is_choose := options.(sim.Command_Choose_Option)
	testing.expect(t, is_choose)
	_, took_one := choose.selection.?
	testing.expect(t, !took_one, "the scripted route declines every option list")

	trade := capture_scripted_command(&state, .Awaiting_Trade_Choice)
	bargain, is_trade := trade.(sim.Command_Trade_Choice)
	testing.expect(t, is_trade)
	testing.expect(t, !bargain.accept, "the scripted route rejects every trade")

	refit := capture_scripted_command(&state, .Awaiting_Refit)
	_, is_refit := refit.(sim.Command_Refit)
	testing.expect(t, is_refit)
}

@(test)
capture_phase_slug_names_every_phase_distinctly :: proc(t: ^testing.T) {
	seen: map[string]bool
	defer delete(seen)

	for phase in sim.Phase {
		slug := capture_phase_slug(phase)
		testing.expect(t, slug != "unknown", "every phase should name its own screen")
		testing.expect(t, !seen[slug], "two phases should not share a filename")
		seen[slug] = true
	}
}
