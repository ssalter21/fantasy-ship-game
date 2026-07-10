package sim

import "core:math/rand"

Sim :: struct {
	rng:               rand.Default_Random_State,
	round:             int,
	round_cap:         int,
	awaiting_decision: bool,
}

// Command is the only way presentation may mutate the Sim (see ADR-0001).
Command :: union {
	Command_Submit_Captain_Choice,
}

Command_Submit_Captain_Choice :: struct {
	choice: int, // stub: the real captain-decision vocabulary is a future ticket.
}

// Event is the only way presentation learns what happened inside the Sim (see ADR-0001).
Event :: union {
	Event_Round_Resolved,
	Event_Awaiting_Captain_Decision,
	Event_Run_Ended,
}

Event_Round_Resolved :: struct {
	round: int,
}

Event_Awaiting_Captain_Decision :: struct {
	round: int,
}

Event_Run_Ended :: struct {
	rounds: int,
}

sim_create :: proc(seed: u64) -> Sim {
	s: Sim
	s.rng = rand.create_u64(seed)
	gen := rand.default_random_generator(&s.rng)
	// Stub round resolution: this run lasts 1 or 2 rounds, deterministic per seed.
	// Real round/phase resolution (ADR-0006) replaces this in a later ticket.
	s.round_cap = 1 + rand.int_max(2, gen)
	return s
}

// sim_tick resolves one round and batch-emits that round's events into `events`.
// It either returns having resolved the run to completion (Event_Run_Ended), or
// returns with the Sim awaiting a captain decision (Event_Awaiting_Captain_Decision).
// Calling sim_tick again while still awaiting a decision is a driver bug (ADR-0001).
sim_tick :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	assert(!sim.awaiting_decision, "sim_tick called while a captain decision is still outstanding")

	sim.round += 1
	append(events, Event_Round_Resolved{round = sim.round})

	if sim.round >= sim.round_cap {
		append(events, Event_Run_Ended{rounds = sim.round})
		return
	}

	sim.awaiting_decision = true
	append(events, Event_Awaiting_Captain_Decision{round = sim.round})
}

sim_submit_captain_choice :: proc(sim: ^Sim, cmd: Command) {
	assert(sim.awaiting_decision, "submitted a captain choice while the sim wasn't awaiting one")
	_, ok := cmd.(Command_Submit_Captain_Choice)
	assert(ok, "sim_submit_captain_choice received a Command that wasn't Command_Submit_Captain_Choice")
	sim.awaiting_decision = false
}
