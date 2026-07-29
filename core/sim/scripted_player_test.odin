package sim

import "core:testing"
import "../combat"
import "../ship"
import "../voyage"

// scripted_ship is a starting ship for a rule to be read against, plus the cargo the rule
// under test wants in its hold. The caller owns the layout.
scripted_ship :: proc(cargo: int) -> ship.Ship {
	s := ship.ship_starting_ship()
	ship.ship_stow_cargo(s.layout, cargo)
	return s
}

// scripted_option_view stages an option list against a ship carrying `cargo` — the shape
// both the Offer (free options) and Shop (priced ones) rules are read in.
scripted_option_view :: proc(player: ship.Ship, options: ..Stage_Option) -> Scripted_View {
	view := Scripted_View{player = player}
	for option, i in options {
		view.stage_options[i] = option
	}
	return view
}

@(test)
scripted_player_command_travels_to_a_legal_forward_neighbor_of_the_current_node :: proc(t: ^testing.T) {
	m := voyage.voyage_map_create(0)
	defer voyage.voyage_map_destroy(&m)

	// Stand in for the Sim's Event_Travel_Options broadcast: the legal moves
	// from Start. scripted_player_command plans from these, not from a
	// shadow visited set of its own.
	visited := make([]bool, len(m.nodes))
	defer delete(visited)
	visited[0] = true
	options := voyage.voyage_travel_options(m, 0, visited)

	cmd := scripted_player_command(
		Scripted_View{voyage_map = m, current = 0, travel_options = options},
		.Awaiting_Travel_Choice,
	)

	travel, ok := cmd.(Command_Travel_To)
	testing.expect(t, ok)
	// The chosen destination must be one of the emitted options and a forward
	// step (a deeper layer) — progress toward Haven, never an illegal jump.
	testing.expect(t, voyage.voyage_can_travel_to(m, 0, visited, travel.node_id))
	testing.expect(t, m.nodes[travel.node_id].layer > m.nodes[0].layer)
}

// Rule 2 of the battle order: the battle's one Press goes on Fire the first round it can,
// and never again once the ration is spent.
@(test)
scripted_player_command_spends_the_battle_s_one_press_on_fire :: proc(t: ^testing.T) {
	player := scripted_ship(ship.STARTING_CARGO)
	defer delete(player.layout)

	first := scripted_player_command(Scripted_View{player = player, may_press = true}, .Awaiting_Battle_Command)
	choice, is_battle := first.(Command_Battle_Choice)
	testing.expect(t, is_battle)
	press, is_press := choice.combat_command.(combat.Command_Press)
	testing.expect(t, is_press, "the reference player spends its Press while it has one")
	testing.expect_value(t, press.phase, ship.Phase.Fire)

	// may_press is the Battle's own ration (Event_Battle_Menu), so a spent Press is simply
	// never submitted again — combat asserts on a second one.
	spent := scripted_player_command(Scripted_View{player = player, may_press = false}, .Awaiting_Battle_Command)
	after, _ := spent.(Command_Battle_Choice)
	_, is_hold := after.combat_command.(combat.Command_Hold)
	testing.expect(t, is_hold, "a battle whose Press is spent holds")
}

// Rule 1: a hull under the commit share stops firing, but only while something aboard
// repairs — Commit doubling a Brace of nothing would just switch the guns off.
@(test)
scripted_player_command_commits_on_a_low_hull_that_can_still_repair :: proc(t: ^testing.T) {
	hurt := scripted_ship(ship.STARTING_CARGO)
	defer delete(hurt.layout)
	hurt.hull = hurt.max_hull * SCRIPTED_COMMIT_HULL_PERCENT / 100 - 1

	cmd := scripted_player_command(Scripted_View{player = hurt, may_press = true}, .Awaiting_Battle_Command)
	choice, _ := cmd.(Command_Battle_Choice)
	_, is_commit := choice.combat_command.(combat.Command_Commit)
	testing.expect(t, is_commit, "a hull under the commit share commits before it presses")

	// The same hull with the repair torn out: Commit has nothing to double, so the rule
	// falls through to the Press.
	for &layout_slot in hurt.layout {
		if fitting, filled := layout_slot.fitting.?; filled && .Brace in ship.ship_fitting_phases(fitting) {
			layout_slot.fitting = ship.ship_fitting_hold(layout_slot.slot.size)
		}
	}
	dry := scripted_player_command(Scripted_View{player = hurt, may_press = true}, .Awaiting_Battle_Command)
	dry_choice, _ := dry.(Command_Battle_Choice)
	_, presses := dry_choice.combat_command.(combat.Command_Press)
	testing.expect(t, presses, "a ship that cannot repair has nothing to commit with")
}

@(test)
scripted_player_command_holds_a_healthy_round_with_no_press_left :: proc(t: ^testing.T) {
	player := scripted_ship(ship.STARTING_CARGO)
	defer delete(player.layout)

	cmd := scripted_player_command(Scripted_View{player = player, may_press = false}, .Awaiting_Battle_Command)
	choice, _ := cmd.(Command_Battle_Choice)
	_, is_hold := choice.combat_command.(combat.Command_Hold)
	testing.expect(t, is_hold, "a full hull with no Press left holds")
}

// An Offer's items are free, so the rule takes the first one with a berth rather than
// halting the encounter by skipping.
@(test)
scripted_player_command_takes_the_first_free_option_it_can_berth :: proc(t: ^testing.T) {
	player := scripted_ship(ship.STARTING_CARGO)
	defer delete(player.layout)

	// The starting layout's Large berths carry holds, so a Large item is placeable and the
	// first one presented is the pick.
	large := ship.Fitting{name = "Long Nines", size = .Large, bulk = 40, weight = 30}
	view := scripted_option_view(player, Stage_Option{fitting = large}, Stage_Option{fitting = large})

	cmd := scripted_player_command(view, .Awaiting_Option_Choice)
	choose, is_choose := cmd.(Command_Choose_Option)
	testing.expect(t, is_choose)
	selection, took := choose.selection.?
	testing.expect(t, took, "a free option with a berth is taken")
	testing.expect_value(t, selection, Option_Index(0))
}

// An option with nowhere to go is passed over: the pick — and a shop's cargo — would buy a
// fitting the Refit then has to drop.
@(test)
scripted_player_command_passes_over_an_option_with_no_berth :: proc(t: ^testing.T) {
	player := scripted_ship(ship.STARTING_CARGO)
	defer delete(player.layout)
	// Every Large berth taken by a real fitting, so a Large item has nowhere a hold can be
	// displaced for it.
	gun := ship.ship_fitting_gun_deck()
	for &layout_slot in player.layout {
		if layout_slot.slot.size == .Large {
			layout_slot.fitting = gun
		}
	}

	large := ship.Fitting{name = "Long Nines", size = .Large, bulk = 40, weight = 30}
	view := scripted_option_view(player, Stage_Option{fitting = large})

	cmd := scripted_player_command(view, .Awaiting_Option_Choice)
	choose, _ := cmd.(Command_Choose_Option)
	_, took := choose.selection.?
	testing.expect(t, !took, "an option with no berth is declined rather than taken and dropped")
}

// A priced card is bought only while the hold stays at the reserve or above, which is what
// makes the player leave a shop rather than buy it out.
@(test)
scripted_player_command_buys_down_to_the_cargo_reserve_and_no_further :: proc(t: ^testing.T) {
	player := scripted_ship(SCRIPTED_CARGO_RESERVE + 30)
	defer delete(player.layout)

	large := ship.Fitting{name = "Long Nines", size = .Large, bulk = 40, weight = 30}
	affordable := scripted_option_view(player, Stage_Option{fitting = large, cost = 30})
	bought := scripted_player_command(affordable, .Awaiting_Option_Choice)
	choose, _ := bought.(Command_Choose_Option)
	selection, took := choose.selection.?
	testing.expect(t, took, "a card the hold can pay for without breaking the reserve is bought")
	testing.expect_value(t, selection, Option_Index(0))

	// One more cargo on the price — the escalation a second buy at this shop adds — and the
	// same card is left on the shelf.
	dear := scripted_option_view(player, Stage_Option{fitting = large, cost = 31})
	left := scripted_player_command(dear, .Awaiting_Option_Choice)
	leaving, _ := left.(Command_Choose_Option)
	_, still_took := leaving.selection.?
	testing.expect(t, !still_took, "a card that would break the reserve is left and the shop is left with it")
}

// The trade rule's two clauses: the Sim's affordability gate, then the reference player's
// own hull floor.
@(test)
scripted_player_command_accepts_a_payable_trade_and_rejects_an_unpayable_one :: proc(t: ^testing.T) {
	player := scripted_ship(ship.STARTING_CARGO)
	defer delete(player.layout)

	cheap := Scripted_View {
		player           = player,
		trade_can_accept = true,
		trade            = voyage.Stage_Trade {
			gain = voyage.Trade_Term{stat = .Max_Hull, amount = 10},
			cost = voyage.Trade_Term{stat = .Cargo, amount = 10},
		},
	}
	accepted := scripted_player_command(cheap, .Awaiting_Trade_Choice)
	bargain, is_trade := accepted.(Command_Trade_Choice)
	testing.expect(t, is_trade)
	testing.expect(t, bargain.accept, "a payable bargain is taken rather than halting the encounter")

	unaffordable := cheap
	unaffordable.trade_can_accept = false
	refused := scripted_player_command(unaffordable, .Awaiting_Trade_Choice)
	refusal, _ := refused.(Command_Trade_Choice)
	testing.expect(t, !refusal.accept, "a cost the ship cannot pay in full is never accepted")
}

@(test)
scripted_player_command_rejects_a_trade_that_would_sell_the_hull_down :: proc(t: ^testing.T) {
	player := scripted_ship(ship.STARTING_CARGO)
	defer delete(player.layout)

	// A Hull cost the affordability gate allows (it floors at 1) but that leaves the ship
	// under the reference player's own share of Max Hull.
	view := Scripted_View {
		player           = player,
		trade_can_accept = true,
		trade            = voyage.Stage_Trade {
			gain = voyage.Trade_Term{stat = .Cargo, amount = 20},
			cost = voyage.Trade_Term {
				stat   = .Hull,
				amount = player.max_hull * SCRIPTED_TRADE_HULL_PERCENT / 100 + 1,
			},
		},
	}

	cmd := scripted_player_command(view, .Awaiting_Trade_Choice)
	bargain, _ := cmd.(Command_Trade_Choice)
	testing.expect(t, !bargain.accept, "a bargain that leaves the ship unable to fight is rejected")

	// The share is read against the Max Hull the ship has now, so raising the ceiling on the
	// gain side buys the same cost no way past the floor.
	inflated := view
	inflated.trade.gain = voyage.Trade_Term{stat = .Max_Hull, amount = player.max_hull}
	still := scripted_player_command(inflated, .Awaiting_Trade_Choice)
	stubborn, _ := still.(Command_Trade_Choice)
	testing.expect(t, !stubborn.accept, "a raised ceiling does not pay for the hull the cost takes")

	// A Max Hull cost pulls the ceiling down onto the hull, which the projection has to
	// follow: the hull it leaves is what the rule measures, not the untouched field.
	sold_ceiling := view
	sold_ceiling.trade.cost = voyage.Trade_Term{stat = .Max_Hull, amount = player.max_hull - 1}
	ceiling := scripted_player_command(sold_ceiling, .Awaiting_Trade_Choice)
	sold, _ := ceiling.(Command_Trade_Choice)
	testing.expect(t, !sold.accept, "a ceiling sold out from under the hull takes the hull with it")
}

// A Refit places what it was opened for, in the berth the placement rule picked, and then
// closes on the call after — the Sim clears the incoming as it lands.
@(test)
scripted_player_command_swaps_the_incoming_fitting_into_a_hold_and_then_finishes :: proc(t: ^testing.T) {
	player := scripted_ship(ship.STARTING_CARGO)
	defer delete(player.layout)

	large := ship.Fitting{name = "Long Nines", size = .Large, bulk = 40, weight = 30}
	placing := scripted_player_command(Scripted_View{player = player, refit_incoming = large}, .Awaiting_Refit)
	refit, is_refit := placing.(Command_Refit)
	testing.expect(t, is_refit)
	replace, is_replace := refit.command.(Refit_Replace)
	testing.expect(t, is_replace, "an incoming fitting is swapped into a berth carrying a hold")

	berth := player.layout[replace.slot]
	testing.expect(t, ship.ship_fitting_fits(berth.slot, large), "the chosen berth admits the fitting")
	displaced, filled := berth.fitting.?
	testing.expect(t, filled && ship.ship_fitting_is_hold(displaced), "only a hold is ever displaced")

	done := scripted_player_command(Scripted_View{player = player}, .Awaiting_Refit)
	finish, _ := done.(Command_Refit)
	_, is_finish := finish.command.(Refit_Finish)
	testing.expect(t, is_finish, "a refit with nothing left to place finishes")
}

// An unladen hold goes first, so taking an item aboard doesn't put cargo over the side that
// an empty berth of the same size would have spared.
@(test)
scripted_berth_prefers_a_hold_carrying_nothing :: proc(t: ^testing.T) {
	player := scripted_ship(0)
	defer delete(player.layout)

	small := ship.Fitting{name = "Bilge Rats", size = .Small, bulk = 10, weight = 4}
	first_small := -1
	for layout_slot, i in player.layout {
		if layout_slot.slot.size == .Small {
			if first_small < 0 {
				first_small = i
			}
		}
	}
	testing.expect(t, first_small >= 0, "the template carries a Small berth to test against")

	// Load the first Small hold only: the rule should walk past it to the next unladen one.
	laden, _ := player.layout[first_small].fitting.?
	laden.cargo_held = ship.ship_fitting_capacity(laden)
	player.layout[first_small].fitting = laden

	berth, berthed := scripted_berth(player.layout, small).?
	testing.expect(t, berthed)
	testing.expect(t, int(berth) != first_small, "a laden hold is only displaced when nothing emptier fits")

	// With every Small hold laden there is nothing emptier, so the first one is taken after all.
	for &layout_slot in player.layout {
		if fitting, filled := layout_slot.fitting.?; filled && layout_slot.slot.size == .Small {
			fitting.cargo_held = ship.ship_fitting_capacity(fitting)
			layout_slot.fitting = fitting
		}
	}
	fallback, has_fallback := scripted_berth(player.layout, small).?
	testing.expect(t, has_fallback)
	testing.expect_value(t, int(fallback), first_small)
}
