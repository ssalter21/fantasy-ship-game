package sim

import "core:math/rand"
import "core:testing"

@(test)
same_seed_produces_identical_rng_draws :: proc(t: ^testing.T) {
	a := sim_create(42)
	b := sim_create(42)

	gen_a := rand.default_random_generator(&a.rng)
	gen_b := rand.default_random_generator(&b.rng)

	draw_a := rand.uint64(gen_a)
	draw_b := rand.uint64(gen_b)

	testing.expect_value(t, draw_a, draw_b)
}

@(test)
tick_again_while_awaiting_decision_asserts :: proc(t: ^testing.T) {
	// seed 0 gives this stub run a round cap of 2, so round 1 awaits a decision.
	sim := sim_create(0)
	events: [dynamic]Event
	defer delete(events)
	sim_tick(&sim, &events)

	testing.expect_assert(t, "sim_tick called while a captain decision is still outstanding")
	sim_tick(&sim, &events)
}

@(test)
submit_captain_choice_asserts_when_command_is_not_the_captain_choice_variant :: proc(t: ^testing.T) {
	// seed 0 gives this stub run a round cap of 2, so round 1 awaits a decision.
	sim := sim_create(0)
	events: [dynamic]Event
	defer delete(events)
	sim_tick(&sim, &events)

	testing.expect_assert(t, "sim_submit_captain_choice received a Command that wasn't Command_Submit_Captain_Choice")
	sim_submit_captain_choice(&sim, Command{})
}

@(test)
run_session_ends_without_a_decision_when_the_run_needs_none :: proc(t: ^testing.T) {
	// seed 1 gives this stub run a round cap of 1: it ends on the first round.
	sim := sim_create(1)

	sink_state := Recording_Sink_State{}
	defer delete(sink_state.events)
	sink := Event_Sink{data = &sink_state, dispatch = recording_sink_dispatch}

	input := Input_Source{data = nil, get_captain_choice = unreachable_get_captain_choice}

	run_session(&sim, input, sink)

	testing.expect_value(t, len(sink_state.events), 2)
	testing.expect_value(t, sink_state.events[0], Event(Event_Round_Resolved{round = 1}))
	testing.expect_value(t, sink_state.events[1], Event(Event_Run_Ended{rounds = 1}))
}

@(test)
run_session_asks_for_and_submits_a_decision_before_the_run_ends :: proc(t: ^testing.T) {
	// seed 0 gives this stub run a round cap of 2: round 1 awaits a decision,
	// round 2 ends the run.
	sim := sim_create(0)

	sink_state := Recording_Sink_State{}
	defer delete(sink_state.events)
	sink := Event_Sink{data = &sink_state, dispatch = recording_sink_dispatch}

	input_state := Scripted_Input_State{choice = Command(Command_Submit_Captain_Choice{choice = 7})}
	input := Input_Source{data = &input_state, get_captain_choice = scripted_input_get_captain_choice}

	run_session(&sim, input, sink)

	testing.expect_value(t, input_state.calls, 1)
	testing.expect_value(t, len(sink_state.events), 4)
	testing.expect_value(t, sink_state.events[0], Event(Event_Round_Resolved{round = 1}))
	testing.expect_value(t, sink_state.events[1], Event(Event_Awaiting_Captain_Decision{round = 1}))
	testing.expect_value(t, sink_state.events[2], Event(Event_Round_Resolved{round = 2}))
	testing.expect_value(t, sink_state.events[3], Event(Event_Run_Ended{rounds = 2}))
}

Recording_Sink_State :: struct {
	events: [dynamic]Event,
}

recording_sink_dispatch :: proc(data: rawptr, event: Event) {
	state := cast(^Recording_Sink_State)data
	append(&state.events, event)
}

unreachable_get_captain_choice :: proc(data: rawptr) -> Command {
	panic("input source should not be asked for a decision when the run ends without needing one")
}

Scripted_Input_State :: struct {
	choice: Command,
	calls:  int,
}

scripted_input_get_captain_choice :: proc(data: rawptr) -> Command {
	state := cast(^Scripted_Input_State)data
	state.calls += 1
	return state.choice
}
