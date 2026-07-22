package sim

import "core:testing"
import "../combat"
import "../voyage"

@(test)
scripted_command_travels_to_a_legal_forward_neighbor_of_the_current_node :: proc(t: ^testing.T) {
	m := voyage.voyage_map_create(0)
	defer voyage.voyage_map_destroy(&m)

	// Stand in for the Sim's Event_Travel_Options broadcast: the legal moves
	// from Start (issue #83). scripted_command plans from these, not from a
	// shadow visited set of its own.
	visited := make([]bool, len(m.nodes))
	defer delete(visited)
	visited[0] = true
	options := voyage.voyage_travel_options(m, 0, visited)

	cmd := scripted_command(m, 0, options, .Awaiting_Travel_Choice)

	travel, ok := cmd.(Command_Travel_To)
	testing.expect(t, ok)
	// The chosen destination must be one of the emitted options and a forward
	// step (a deeper layer) — progress toward Haven, never an illegal jump.
	testing.expect(t, voyage.voyage_can_travel_to(m, 0, visited, travel.node_id))
	testing.expect(t, m.nodes[travel.node_id].layer > m.nodes[0].layer)
}

@(test)
scripted_command_answers_every_non_travel_phase :: proc(t: ^testing.T) {
	// The non-travel branches read none of the travel inputs, so zero values do.
	battle := scripted_command(voyage.Map{}, 0, nil, .Awaiting_Battle_Command)
	choice, is_battle := battle.(Command_Battle_Choice)
	testing.expect(t, is_battle)
	_, is_hold := choice.combat_command.(combat.Command_Hold)
	testing.expect(t, is_hold, "the scripted route holds every battle round")

	options := scripted_command(voyage.Map{}, 0, nil, .Awaiting_Option_Choice)
	choose, is_choose := options.(Command_Choose_Option)
	testing.expect(t, is_choose)
	_, took_one := choose.selection.?
	testing.expect(t, !took_one, "the scripted route declines every option list")

	trade := scripted_command(voyage.Map{}, 0, nil, .Awaiting_Trade_Choice)
	bargain, is_trade := trade.(Command_Trade_Choice)
	testing.expect(t, is_trade)
	testing.expect(t, !bargain.accept, "the scripted route rejects every trade")

	refit := scripted_command(voyage.Map{}, 0, nil, .Awaiting_Refit)
	finish, is_refit := refit.(Command_Refit)
	testing.expect(t, is_refit)
	_, is_finish := finish.command.(Refit_Finish)
	testing.expect(t, is_finish, "the scripted route finishes any refit untouched")
}
