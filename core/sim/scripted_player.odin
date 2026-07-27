package sim

import "../combat"
import "../ship"
import "../voyage"

// The scripted player is the no-player captain shared by the headless runner and the
// capture harness: both wrap it in their Input_Source and hand it the voyage state their
// Event_Sink tracked. It is a **reference player, not an AI** — every decision it makes is
// a stated rule, written down beside the code that applies it, and the rules are the
// content: what a sweep driven by this measures is a voyage played to them.
//
// It is deterministic and reads nothing but the Scripted_View it is given, so it adds no
// randomness of its own to the Sim's seeded RNG (ADR-0001) and a seed reproduces a voyage
// exactly. Node kinds stay hidden: the travel plan depends only on the graph shape, never
// on what an unvisited node holds.

// SCRIPTED_CARGO_RESERVE is the hold the reference player keeps back rather than spending
// in a shop: a card that would take it below this is not bought, however affordable. It is
// what makes the player *leave* a shop it could still dig deeper into, and what leaves it
// something to spend at the next shelf and to pay a Trade's cargo cost with.
SCRIPTED_CARGO_RESERVE :: 20

// SCRIPTED_TRADE_HULL_PERCENT is the share of Max Hull a Trade's cost may not take the ship
// below. voyage_trade_can_accept floors Hull at 1, which is payable and unsurvivable; this
// is the reference player's own, higher floor.
SCRIPTED_TRADE_HULL_PERCENT :: 50

// SCRIPTED_COMMIT_HULL_PERCENT is the share of Max Hull below which the reference player
// stops firing and Commits (ADR-0028).
SCRIPTED_COMMIT_HULL_PERCENT :: 30

// Scripted_View is everything scripted_player_command reads, and the whole of the seam
// between it and its driver. Every field is a fact the Sim broadcast on an Event, so a
// driver fills this from the stream its sink already tracks rather than reaching into the
// Sim (ADR-0001).
Scripted_View :: struct {
	// The travel plan's inputs: the masked map from Event_Voyage_Started, the node from the
	// latest Event_Arrived_At_Node, and the legal destinations from Event_Travel_Options.
	voyage_map:       voyage.Map,
	current:          Node_ID,
	travel_options:   []Node_ID,
	// player is the ship as of the latest Event_Ship_Updated: its hold pays for an option,
	// its layout berths one, and its Hull answers the battle rules.
	player:           ship.Ship,
	// stage_options is the list the option-list stage on screen is presenting
	// (Event_Options_Presented), indexed by the Option_Index a Command_Choose_Option names.
	stage_options:    [STAGE_OPTION_MAX]Maybe(Stage_Option),
	// The Trade stage's bargain and the Sim's own affordability answer
	// (Event_Trade_Presented). can_accept is the Sim's to give — a cargo cost is measured
	// against the holds rather than a field (ADR-0020) — so it is read off the event rather
	// than re-derived here.
	trade:            voyage.Stage_Trade,
	trade_can_accept: bool,
	// may_press is whether this battle's one Press is still in hand (Event_Battle_Menu) —
	// the Battle's own ration, which is what keeps the Press rule inside it.
	may_press:        bool,
	// refit_incoming is the fitting the open Refit was opened to place
	// (Event_Refit_Started), cleared on Event_Fitting_Installed and Event_Refit_Finished.
	// nil means there is nothing left to place.
	refit_incoming:   Maybe(ship.Fitting),
}

// scripted_player_command answers whichever decision the Sim is awaiting, by the rule the
// proc it delegates to states. The switch is exhaustive, so a new Phase is a compile error
// here rather than a decision the reference player silently declines.
scripted_player_command :: proc(view: Scripted_View, awaiting: Phase) -> Command {
	switch awaiting {
	case .Awaiting_Battle_Command:
		return Command(Command_Battle_Choice{combat_command = scripted_battle_order(view)})
	case .Awaiting_Option_Choice:
		return Command(Command_Choose_Option{selection = scripted_option_pick(view)})
	case .Awaiting_Trade_Choice:
		return Command(Command_Trade_Choice{accept = scripted_accepts_trade(view)})
	case .Awaiting_Travel_Choice:
		next := voyage.voyage_forward_option(view.voyage_map, view.current, view.travel_options)
		return Command(Command_Travel_To{node_id = next})
	case .Awaiting_Refit:
		return Command(Command_Refit{command = scripted_refit_command(view)})
	case .Ended:
		panic("scripted_player_command called while the sim isn't awaiting a decision")
	}
	panic("unreachable")
}

// scripted_battle_order is the round's order, by three rules read in order:
//
//  1. **Commit** while Hull has fallen below SCRIPTED_COMMIT_HULL_PERCENT of Max Hull and
//     something aboard repairs. Doubled Brace and no guns beats a round of fire when the
//     next exchange would sink the ship, and doubling a Brace of nothing is worth nothing
//     (ADR-0028).
//  2. **Press** the Fire phase while this battle's one Press is still in hand. The ration
//     is per battle and dies with it, so an unspent Press is worth nothing, and the
//     earliest round it can be spent is the one where ending the fight sooner saves the
//     most Hull.
//  3. **Hold** otherwise.
//
// Press lands at most once per battle because rule 2 reads may_press — the Battle's own
// ration (combat_may_press), broadcast each round on Event_Battle_Menu — rather than a
// count kept here. Reading Commit first means a battle fought from a hull that never rises
// back over the share spends no Press at all: survival outranks the ration, and a Commit
// that repairs the ship over the share hands the Press back to rule 2.
//
// Break Off is never taken: the reference player fights its battles out, so a sweep
// measures a fight rather than an escape.
scripted_battle_order :: proc(view: Scripted_View) -> combat.Command {
	commit_share := scripted_hull_at_least(view.player.hull, view.player.max_hull, SCRIPTED_COMMIT_HULL_PERCENT)
	if !commit_share && scripted_can_repair(view.player) {
		return combat.Command_Commit{}
	}
	if view.may_press {
		return combat.Command_Press{phase = .Fire}
	}
	return combat.Command_Hold{}
}

// scripted_hull_at_least reports whether `hull` is `percent` of `max_hull` or more, in
// integers so the reading is exact at every hull. The one share the rules are read in.
scripted_hull_at_least :: proc(hull: int, max_hull: int, percent: int) -> bool {
	return hull * 100 >= max_hull * percent
}

// scripted_can_repair reports whether anything installed feeds the Brace phase — the
// condition on Commit's ×2 having something to multiply.
scripted_can_repair :: proc(player: ship.Ship) -> bool {
	for layout_slot in player.layout {
		if fitting, filled := layout_slot.fitting.?; filled && .Brace in ship.ship_fitting_phases(fitting) {
			return true
		}
	}
	return false
}

// scripted_option_pick answers an option list — an Offer's items or a Shop's shelf, the one
// decision the two share — with the first option that passes every rule below, or nil to
// decline (skip the Offer, leave the Shop).
//
//   - **A berth first.** An option with nowhere to go (scripted_berth) is passed over:
//     taking it spends the pick — and a shop's cargo — on a fitting the Refit then drops.
//   - **A free option is taken.** Skipping an Offer halts the encounter (ADR-0014) and
//     forfeits every stage behind it, so an item that can be placed always is.
//   - **A priced one is bought while the hold stays at SCRIPTED_CARGO_RESERVE or above.**
//     The quoted price already carries this visit's escalation (voyage_shop_price), so
//     digging deeper into one shop prices itself out; the reserve is what makes the player
//     leave a shelf it could still buy from rather than buy it out.
//   - **First, not best.** The presented order is the rule — ranking items is an AI's job.
//
// The affordability rule is stricter than the Sim's own (voyage_option_can_afford), so a
// pick is never refused as unaffordable and re-offered.
scripted_option_pick :: proc(view: Scripted_View) -> Maybe(Option_Index) {
	for presented, i in view.stage_options {
		option, on_offer := presented.?
		if !on_offer {
			continue
		}
		if _, berthed := scripted_berth(view.player.layout, option.fitting).?; !berthed {
			continue
		}
		if cost, priced := option.cost.?; priced && ship.ship_cargo(view.player) - cost < SCRIPTED_CARGO_RESERVE {
			continue
		}
		return Option_Index(i)
	}
	return nil
}

// scripted_accepts_trade answers a Trade: accept a bargain the ship can pay for in full and
// that leaves it able to fight, reject anything else.
//
// "Able to fight" is the cost side measured against the Max Hull the ship has **now**:
// what the bargain takes out of the ship it is, so the gain side cannot buy its way past the
// floor by raising the ceiling the share is read against.
//
// can_accept is the Sim's own gate (voyage_trade_can_accept), so a cost the ship cannot
// cover is never submitted. The hull clause is the whole of the rest: rejecting **halts**
// the encounter (ADR-0014) and forfeits every stage behind the Trade, so the rule leans
// toward accepting, and the clause is only there to stop the player selling itself down to
// the 1 Hull the affordability floor would still allow.
scripted_accepts_trade :: proc(view: Scripted_View) -> bool {
	if !view.trade_can_accept {
		return false
	}
	remaining := scripted_hull_after_cost(view.player, view.trade.cost)
	return scripted_hull_at_least(remaining, view.player.max_hull, SCRIPTED_TRADE_HULL_PERCENT)
}

// scripted_hull_after_cost is the Hull a trade's cost would leave, projected by the same
// rule that applies it (voyage_trade_pay): a Hull cost comes off the hull, a Max Hull cost
// pulls the ceiling down and the hull clamps to it, and a Cargo cost moves neither. The
// switch is exhaustive, so a fourth Trade_Stat is a compile error here rather than a cost
// this silently reads as free.
scripted_hull_after_cost :: proc(player: ship.Ship, cost: voyage.Trade_Term) -> int {
	switch cost.stat {
	case .Hull:
		return player.hull - cost.amount
	case .Max_Hull:
		return min(player.hull, player.max_hull - cost.amount)
	case .Cargo:
		return player.hull
	}
	unreachable()
}

// scripted_refit_command places the fitting the Refit was opened for, then closes it: swap
// the incoming into the berth scripted_berth picked, or finish outright when there is
// nothing left to place or nowhere to put it (an unplaced incoming is discarded — there is
// no inventory, ADR-0012).
//
// The placement is a **Replace** rather than an Install because a berth always holds
// something: the starting layout fills every slot and a vacated one backfills a hold, so
// place-or-swap is the one operation the rule needs. The Sim clears the incoming as it
// lands, so the call after a placement finishes the refit.
scripted_refit_command :: proc(view: Scripted_View) -> Refit_Command {
	incoming, placing := view.refit_incoming.?
	if !placing {
		return Refit_Finish{}
	}
	berth, berthed := scripted_berth(view.player.layout, incoming).?
	if !berthed {
		return Refit_Finish{}
	}
	return Refit_Replace{slot = berth}
}

// scripted_berth is where the reference player stows an incoming fitting: the first berth
// it fits (ADR-0004's exact size, plus any exposure it demands) that carries a bare hold,
// preferring one carrying nothing.
//
// **Only a hold is ever displaced.** A hold is free and unowned, so swapping one out costs
// its captain nothing but the capacity it was; a real fitting is never given up, which is
// what keeps the rule from trading a gun for an item and calling it a gain. An unladen hold
// first, because a laden one's cargo is re-stowed into whatever capacity is left and the
// overflow goes over the side (ADR-0020).
scripted_berth :: proc(layout: []ship.Layout_Slot, fitting: ship.Fitting) -> Maybe(ship.Slot_Index) {
	laden: Maybe(ship.Slot_Index)
	for layout_slot, i in layout {
		if !ship.ship_fitting_fits(layout_slot.slot, fitting) {
			continue
		}
		installed, filled := layout_slot.fitting.?
		if filled && !ship.ship_fitting_is_hold(installed) {
			continue
		}
		if !filled || installed.cargo_held == 0 {
			return ship.Slot_Index(i)
		}
		if _, already := laden.?; !already {
			laden = ship.Slot_Index(i)
		}
	}
	return laden
}
