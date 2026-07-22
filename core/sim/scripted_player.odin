package sim

import "../combat"
import "../voyage"

// scripted_command is the no-player captain shared by the headless runner and the
// capture harness: both wrap it in their Input_Source, feeding it the voyage state
// their Event_Sink tracked (the map from Event_Voyage_Started, the current node,
// the latest Event_Travel_Options). It resolves every decision deterministically —
// sail forward, Hold every battle round, decline everything else — and node kinds
// are hidden, so the plan depends only on the graph shape, never on what an
// unvisited node holds.
scripted_command :: proc(
	voyage_map: voyage.Map,
	current: Node_ID,
	travel_options: []Node_ID,
	awaiting: Phase,
) -> Command {
	switch awaiting {
	case .Awaiting_Battle_Command:
		return Command(Command_Battle_Choice{combat_command = combat.Command_Hold{}})
	case .Awaiting_Option_Choice:
		// Decline every option list: a nil selection takes nothing and opens no refit,
		// so the scripted player never spends cargo or edits a loadout — it just walks
		// through.
		return Command(Command_Choose_Option{selection = nil})
	case .Awaiting_Trade_Choice:
		// Reject every Trade: accepting would swap a stat on the route's bargains, so
		// rejecting keeps the voyage a pure function of the graph.
		return Command(Command_Trade_Choice{accept = false})
	case .Awaiting_Travel_Choice:
		next := voyage.voyage_forward_option(voyage_map, current, travel_options)
		return Command(Command_Travel_To{node_id = next})
	case .Awaiting_Refit:
		// Declining every option list means a refit never opens; if one did, this just
		// finishes it rather than editing the loadout.
		return Command(Command_Refit{command = Refit_Finish{}})
	case .Ended:
		panic("scripted_command called while the sim isn't awaiting a decision")
	}
	panic("unreachable")
}
