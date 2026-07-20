package combat

import "../ship"
import "../testutil"
import "core:testing"

@(test)
round_with_no_fittings_and_no_commands_deals_no_damage :: proc(t: ^testing.T) {
	a := ship.Ship{hull = 20, speed = 5}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, battle.round, 1)
	testing.expect_value(t, a.hull, 20)
	testing.expect_value(t, b.hull, 20)
	testing.expect_value(t, len(events), 0)
	testing.expect(t, !battle.ended)
}

// A hit lands at its full weight (ADR-0026): nothing stands between a side's Fire total
// and the target's hull, so raw and final are the same number in every event.
@(test)
fire_fitting_deals_its_full_magnitude_to_the_target :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(10))}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, b.hull, 20 - 10)
	testing.expect_value(t, a.hull, 20)
	testing.expect_value(t, len(events), 1)
	dealt, ok := events[0].(Event_Damage_Dealt)
	testing.expect(t, ok)
	testing.expect_value(t, dealt.target, Side.B)
	testing.expect_value(t, dealt.damage, 10)
}

// A Brace fitting adds to its own hull rather than subtracting from the hit (ADR-0027):
// the damage still lands whole, and the repair that met it is a separate, earlier fact.
@(test)
a_brace_fitting_repairs_instead_of_reducing_the_incoming_damage :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(10))}
	surgeon := ship.Fitting{name = "Ship's Surgeon", category = .Brace, active = ship.effect_repair(ship.expr_const(4))}
	a := ship.Ship{
		hull = 20, max_hull = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{
		hull = 20, max_hull = 30, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = surgeon}},
	}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	// Repaired to 24, then struck for the whole 10.
	testing.expect_value(t, b.hull, 14)
	repaired, ok := events[0].(Event_Hull_Repaired)
	testing.expect(t, ok) // and said first, ahead of the hit
	testing.expect_value(t, repaired.side, Side.B)
	testing.expect_value(t, repaired.amount, 4)
	dealt, dealt_ok := events[1].(Event_Damage_Dealt)
	testing.expect(t, dealt_ok)
	testing.expect_value(t, dealt.damage, 10) // nothing was subtracted from the hit
}

// A Crew-tagged Fire fitting and a gun of equal magnitude contribute to raw
// *identically*: swapping which one carries which magnitude leaves the damage unchanged.
// The two are one interchangeable pile — the property Muster's removal into Fire rests on
// (ADR-0025), and the one the category's presence would have broken.
@(test)
a_former_crew_fitting_and_a_gun_of_equal_magnitude_contribute_to_raw_identically :: proc(t: ^testing.T) {
	// Same two magnitudes, swapped between the Crew fitting and the gun. Both are `.Fire`.
	fire_both :: proc(crew_mag, gun_mag: ship.Magnitude) -> int {
		crew := ship.Fitting{name = "Top Crew", category = .Fire, tags = {.Crew}, active = ship.effect_phase_contribution(ship.expr_const(int(crew_mag)))}
		gun := ship.Fitting{name = "Cannon", category = .Fire, tags = {.Weapon}, active = ship.effect_phase_contribution(ship.expr_const(int(gun_mag)))}
		a := ship.Ship{
			hull = 40, speed = 5,
			layout = []ship.Layout_Slot{
				{slot = ship.Slot{size = .Small}, fitting = crew},
				{slot = ship.Slot{size = .Large}, fitting = gun},
			},
		}
		b := ship.Ship{hull = 40, speed = 5}
		battle := combat_battle_create(&a, &b)
		events: [dynamic]Event
		defer delete(events)
		cmds: [Side]Maybe(Command)
		combat_resolve_round(&battle, cmds, &events)
		return b.hull
	}

	// crew(3) + gun(10) and crew(10) + gun(3) both deal 13: the two channels are one.
	testing.expect_value(t, fire_both(3, 10), 40-13)
	testing.expect_value(t, fire_both(10, 3), 40-13)
}

// A Fire fitting never reduces incoming damage — trivially true since ADR-0026 deleted
// the subtracted side of the exchange, but kept as the standing guard that a Crew-tagged
// Fire fitting adds to what its ship *deals* and nothing else.
@(test)
a_fire_fitting_does_not_reduce_incoming_damage :: proc(t: ^testing.T) {
	crew := ship.Fitting{name = "Top Crew", category = .Fire, tags = {.Crew}, active = ship.effect_phase_contribution(ship.expr_const(3))}
	shield := ship.Fitting{name = "Shield Charm", category = .Brace, active = ship.effect_phase_contribution(ship.expr_const(4))}
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(20))}
	a := ship.Ship{
		hull = 40, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = crew},
			{slot = ship.Slot{size = .Small}, fitting = shield},
		},
	}
	b := ship.Ship{
		hull = 40, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	// Neither the Top Crew's 3 nor the Shield Charm's 4 stands in the way: B's raw
	// damage is 20, and 20 lands.
	testing.expect_value(t, a.hull, 40-20)
}

@(test)
press_fire_multiplies_only_the_submitters_fire_output :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(10))}
	// Hulls deep enough to outlast a pressed broadside, so the round reads as a
	// comparison of the two sides' output rather than as a sinking.
	a := ship.Ship{
		hull = 100, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{
		hull = 100, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Press{phase = .Fire})
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, b.hull, 100-10*PRESS_MULTIPLIER)
	testing.expect_value(t, a.hull, 100-10)
}

// Press Fire doubles the *whole* Fire pile — the guns and the crew-tagged fittings
// alike — since they share the one Fire phase (ADR-0025). No seam splits the pile.
@(test)
press_fire_multiplies_the_whole_fire_pile_including_former_crew :: proc(t: ^testing.T) {
	crew := ship.Fitting{name = "Top Crew", category = .Fire, tags = {.Crew}, active = ship.effect_phase_contribution(ship.expr_const(2))}
	cannon := ship.Fitting{name = "Cannon", category = .Fire, tags = {.Weapon}, active = ship.effect_phase_contribution(ship.expr_const(5))}
	a := ship.Ship{
		hull = 40, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = crew},
			{slot = ship.Slot{size = .Large}, fitting = cannon},
		},
	}
	b := ship.Ship{hull = 40, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Press{phase = .Fire})
	combat_resolve_round(&battle, cmds, &events)

	// (crew(2) + cannon(5)) * PRESS_MULTIPLIER — both piles multiplied, no seam.
	testing.expect_value(t, b.hull, 40-(2+5)*PRESS_MULTIPLIER)
}

// Press Brace multiplies its own phase's fittings like any Press (ADR-0006), and since that
// phase repairs, the order buys Hull: the pressing ship ends the round PRESS_MULTIPLIER
// repairs better off than the one that held.
@(test)
press_brace_multiplies_the_repair_the_round_restores :: proc(t: ^testing.T) {
	surgeon := ship.Fitting{name = "Ship's Surgeon", category = .Brace, active = ship.effect_repair(ship.expr_const(4))}
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(20))}

	// Damaged, with headroom for both runs' repair: a full hull would cap them equal and
	// the comparison would prove nothing.
	defender := ship.Ship {
		hull = 50,
		max_hull = 100,
		speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = surgeon}},
	}
	attacker := ship.Ship {
		hull = 50,
		max_hull = 100,
		speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}

	// Two runs off identical ships, differing only in A's order. The layouts are
	// read-only here, so the copies can share one backing array.
	pressed_defender, pressed_attacker := defender, attacker
	held_defender, held_attacker := defender, attacker

	events: [dynamic]Event
	defer delete(events)

	pressed_battle := combat_battle_create(&pressed_defender, &pressed_attacker)
	press: [Side]Maybe(Command)
	press[.A] = Command(Command_Press{phase = .Brace})
	combat_resolve_round(&pressed_battle, press, &events)

	held_battle := combat_battle_create(&held_defender, &held_attacker)
	hold: [Side]Maybe(Command)
	hold[.A] = Command(Command_Hold{})
	combat_resolve_round(&held_battle, hold, &events)

	// Both take B's Fire output whole — a Press never touches the incoming hit — but the
	// pressed run mended twice as much before it landed.
	testing.expect_value(t, held_defender.hull, 50 + 4 - 20)
	testing.expect_value(t, pressed_defender.hull, 50 + 4 * PRESS_MULTIPLIER - 20)
}

@(test)
a_speed_stat_modifier_fitting_raises_effective_speed_for_escape_eligibility :: proc(t: ^testing.T) {
	fast_sails := ship.Fitting{
		name = "Fast Sails", size = .Small,
		passive = ship.effect_modify_speed(ship.expr_const(3)),
	}
	// Equal base Speed (5), but A carries a +3 Speed fitting: past the baseline
	// round count only the strictly-faster side may break off, so A is eligible.
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = fast_sails}},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT

	testing.expect_value(t, combat_effective_speed(&battle, .A), 5 + 3)
	testing.expect(t, combat_may_break_off(&battle, .A))
	testing.expect(t, !combat_may_break_off(&battle, .B))
}

@(test)
the_three_starting_fittings_phase_output_matches_their_magnitude_constants :: proc(t: ^testing.T) {
	// Regression anchor for the Effect port (issue #92): the ported flat/constant
	// starting fittings must produce phase output equal to their magnitude constants.
	// Top Crew and Gun Deck share the Fire phase (ADR-0025), so Fire output is the *sum*
	// of their two constants; Captain's Quarters is the lone Brace fitting.
	s := ship.ship_starting_ship()
	defer delete(s.layout)
	opponent := ship.Ship{}
	battle := combat_battle_create(&s, &opponent)

	testing.expect_value(t, combat_phase_output_this_round(&battle, .A, .Brace), ship.CAPTAINS_QUARTERS_REPAIR_MAGNITUDE)
	testing.expect_value(t, combat_phase_output_this_round(&battle, .A, .Fire), ship.TOP_CREW_OFFENSE_MAGNITUDE + ship.GUN_DECK_OFFENSE_MAGNITUDE)
}

@(test)
hold_is_a_no_op_identical_to_submitting_no_command :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(10))}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Hold{})
	combat_resolve_round(&battle, cmds, &events)

	// Same outcome as the no-command baseline round: Hold is a stance, and it resolves
	// nothing — no scaling, no jettison, no ending.
	testing.expect_value(t, b.hull, 20-10)
	testing.expect_value(t, a.hull, 20)
	testing.expect_value(t, combat_effective_speed(&battle, .A), 5)
	testing.expect(t, !battle.ended)

	// Nor does holding spend the battle's one Press.
	testing.expect(t, combat_may_press(&battle, .A))
}

// The ration is per *fight*: a Press spent in one round is gone for the rest of the
// battle, and the flag the Fight menu reads says so from the round after it lands.
@(test)
press_is_available_once_per_battle :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(5))}
	a := ship.Ship{
		hull = 200, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hull = 200, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)

	testing.expect(t, combat_may_press(&battle, .A))
	testing.expect(t, combat_may_press(&battle, .B))

	press: [Side]Maybe(Command)
	press[.A] = Command(Command_Press{phase = .Fire})
	combat_resolve_round(&battle, press, &events)

	testing.expect(t, !combat_may_press(&battle, .A))
	testing.expect(t, combat_may_press(&battle, .B)) // rationed per side, not per battle

	// A later round with no Press does not hand it back.
	held: [Side]Maybe(Command)
	held[.A] = Command(Command_Hold{})
	combat_resolve_round(&battle, held, &events)
	testing.expect(t, !combat_may_press(&battle, .A))
}

@(test)
a_second_press_in_the_same_battle_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	a := ship.Ship{hull = 200, speed = 5}
	b := ship.Ship{hull = 200, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	press: [Side]Maybe(Command)
	press[.A] = Command(Command_Press{phase = .Fire})
	combat_resolve_round(&battle, press, &events)

	// The menu never offers a spent Press (Event_Battle_Menu.may_press), so reaching
	// here is a driver bug rather than a legitimate rejection.
	testing.expect_assert(t, "Command_Press submitted after this battle's Press was spent")
	combat_resolve_round(&battle, press, &events)
}

// Commit is one-directional: the round's repair is multiplied and the round's damage is
// nothing, so a committing captain can survive a round but never win on it.
@(test)
commit_multiplies_the_brace_total_and_zeroes_the_fire_total :: proc(t: ^testing.T) {
	surgeon := ship.Fitting{name = "Ship's Surgeon", category = .Brace, active = ship.effect_repair(ship.expr_const(4))}
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(10))}
	a := ship.Ship{
		hull = 50, max_hull = 100, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = surgeon},
			{slot = ship.Slot{size = .Large}, fitting = cannon},
		},
	}
	b := ship.Ship{hull = 50, max_hull = 100, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Commit{})
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, a.hull, 50 + 4 * COMMIT_MULTIPLIER)
	testing.expect_value(t, b.hull, 50) // the guns were the price
}

// Unlike Press, Commit is unrationed: it can be taken every round of a battle.
@(test)
commit_is_available_every_round :: proc(t: ^testing.T) {
	surgeon := ship.Fitting{name = "Ship's Surgeon", category = .Brace, active = ship.effect_repair(ship.expr_const(4))}
	a := ship.Ship{
		hull = 50, max_hull = 100, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = surgeon}},
	}
	b := ship.Ship{hull = 50, max_hull = 100, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Commit{})
	for _ in 0 ..< 3 {
		combat_resolve_round(&battle, cmds, &events)
	}

	testing.expect_value(t, a.hull, 50 + 3 * 4 * COMMIT_MULTIPLIER)
}

@(test)
jettison_cargo_empties_the_fitting_and_speeds_the_ship_up_by_shedding_weight :: proc(t: ^testing.T) {
	// A full Small hold weighs 10 (ADR-0020), so it costs its ship 1 Speed
	// (weight/10). Heaving it makes the ship read 1 faster — emergent from the
	// lighter hull, not a granted bonus (JETTISON_SPEED_BONUS is retired, #158).
	cargo := ship.Fitting{name = "Rations", size = .Small, cargo_held = 10}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = cargo}},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	testing.expect_value(t, combat_effective_speed(&battle, .A), 4) // laden: 5 − 10/10

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 0})
	combat_resolve_round(&battle, cmds, &events)

	// The fitting stays put; what went over the side is its cargo. Under the old model
	// a cargo fitting *was* its cargo, so heaving it nulled the slot — now a laden gun
	// must survive having its load heaved, and an emptied hold is still capacity.
	emptied, still_occupied := a.layout[0].fitting.?
	testing.expect(t, still_occupied)
	testing.expect_value(t, emptied.cargo_held, 0)
	testing.expect_value(t, combat_effective_speed(&battle, .A), 5) // lighter by the cargo

	jettison_event_found := false
	for event in events {
		if dropped, ok := event.(Event_Cargo_Jettisoned); ok {
			jettison_event_found = true
			testing.expect_value(t, dropped.side, Side.A)
			testing.expect_value(t, dropped.fitting.name, "Rations")
			testing.expect_value(t, dropped.fitting.cargo_held, 10) // the event reports what went over
		}
	}
	testing.expect(t, jettison_event_found)

	// The gain persists — the cargo is gone for good, so the next round still reads
	// the lighter ship (nothing settles or restores the heaved cargo).
	next_cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, next_cmds, &events)
	testing.expect_value(t, combat_effective_speed(&battle, .A), 5)
}

// A heave empties one fitting and **re-stows what is left across the whole ship**
// (#400): the hold the captain picked is not a container that stays empty, it is
// where this heave was taken from. The ship keeps carrying everything it did not
// throw away, spread by the same water-fill every out-of-battle cargo change uses.
@(test)
jettison_re_stows_the_remaining_cargo_across_the_ship :: proc(t: ^testing.T) {
	hold :: proc(name: string, cargo: int) -> ship.Fitting {
		return ship.Fitting{name = name, size = .Small, cargo_held = cargo}
	}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = hold("Fore hold", 10)},
			{slot = ship.Slot{size = .Small}, fitting = hold("Aft hold", 10)},
		},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	testing.expect_value(t, combat_effective_speed(&battle, .A), 3) // laden: 5 − 20/10

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 0})
	combat_resolve_round(&battle, cmds, &events)

	// 10 went over the side; the other 10 is now split evenly rather than left
	// sitting in the untouched hold.
	fore, _ := a.layout[0].fitting.?
	aft, _ := a.layout[1].fitting.?
	testing.expect_value(t, fore.cargo_held, 5)
	testing.expect_value(t, aft.cargo_held, 5)
	testing.expect_value(t, ship.ship_cargo(a), 10)
	testing.expect_value(t, combat_effective_speed(&battle, .A), 4) // lighter by the heave alone
}

// Re-stowing is what makes jettison **self-flattening**: because the remainder is
// spread back over every hold, the fitting the captain heaves next holds a smaller
// share than it did last round. Every heave sheds no more than the one before it, so
// the escape window closes as it is used and a captain cannot dump their whole hold
// at a fixed price per round.
@(test)
successive_jettisons_shed_monotonically_less :: proc(t: ^testing.T) {
	hold :: proc(cargo: int) -> ship.Fitting {
		return ship.Fitting{name = "Hold", size = .Small, cargo_held = cargo}
	}
	a := ship.Ship{
		hull = 20, speed = 20,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = hold(10)},
			{slot = ship.Slot{size = .Small}, fitting = hold(10)},
			{slot = ship.Slot{size = .Small}, fitting = hold(10)},
		},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 0})

	previous := max(int)
	for _ in 0 ..< 3 {
		before := ship.ship_cargo(a)
		combat_resolve_round(&battle, cmds, &events)
		shed := before - ship.ship_cargo(a)
		testing.expect(t, shed > 0) // a heave always costs the ship something
		testing.expect(t, shed <= previous)
		previous = shed
	}
	testing.expect(t, previous < 10) // the last heave shed less than the first
}

@(test)
jettison_cargo_on_a_fitting_carrying_nothing_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	cannon := ship.Fitting{name = "Cannon", category = .Fire}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 0})

	// Carrying nothing means weighing nothing extra, so heaving it would be free Speed.
	testing.expect_assert(t, "Command_Jettison_Cargo slot_index holds no cargo")
	combat_resolve_round(&battle, cmds, &events)
}

@(test)
may_break_off_is_false_before_the_baseline_round_count_even_if_faster :: proc(t: ^testing.T) {
	a := ship.Ship{hull = 20, speed = 10}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT - 1

	testing.expect(t, !combat_may_break_off(&battle, .A))
}

@(test)
may_break_off_is_false_after_baseline_when_not_the_faster_side :: proc(t: ^testing.T) {
	a := ship.Ship{hull = 20, speed = 5}
	b := ship.Ship{hull = 20, speed = 10}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT

	testing.expect(t, !combat_may_break_off(&battle, .A))
}

@(test)
may_break_off_is_true_after_baseline_for_the_strictly_faster_side :: proc(t: ^testing.T) {
	a := ship.Ship{hull = 20, speed = 10}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT

	testing.expect(t, combat_may_break_off(&battle, .A))
}

@(test)
scripted_command_holds_when_not_escape_eligible :: proc(t: ^testing.T) {
	a := ship.Ship{hull = 20, speed = 10}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT - 1

	testing.expect_value(t, combat_scripted_command(&battle, .A), Command(Command_Hold{}))
}

@(test)
scripted_command_breaks_off_once_escape_eligible :: proc(t: ^testing.T) {
	a := ship.Ship{hull = 20, speed = 10}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT

	testing.expect_value(t, combat_scripted_command(&battle, .A), Command(Command_Break_Off{}))
}

@(test)
break_off_ends_the_battle_immediately_with_no_phase_resolution :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(10))}
	a := ship.Ship{
		hull = 20, speed = 10,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Break_Off{})
	combat_resolve_round(&battle, cmds, &events)

	testing.expect(t, battle.ended)
	testing.expect_value(t, b.hull, 20) // no fire phase resolved this round
	testing.expect_value(t, len(events), 1)
	ended, ok := events[0].(Event_Battle_Ended)
	testing.expect(t, ok)
	testing.expect_value(t, ended.reason, End_Reason.Broke_Off)
	_, has_winner := ended.winner.?
	testing.expect(t, !has_winner)

	// The Battle mirrors the ending it emitted, so a caller holding only the Battle —
	// voyage_finish_ship_battle, deciding the wreck payout (#159) — reads it without the
	// event stream.
	testing.expect_value(t, battle.reason, End_Reason.Broke_Off)
	_, battle_has_winner := battle.winner.?
	testing.expect(t, !battle_has_winner)
}

@(test)
an_escape_eligible_side_declining_to_break_off_lets_combat_continue_normally :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(10))}
	a := ship.Ship{
		hull = 20, speed = 10,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT

	events: [dynamic]Event
	defer delete(events)

	testing.expect(t, combat_may_break_off(&battle, .A))

	// A is escape-eligible this round but submits no command (declines the
	// offer): the round resolves as normal instead of ending combat.
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect(t, !battle.ended)
	testing.expect_value(t, b.hull, 20-10)
}

@(test)
a_ship_reduced_to_zero_hull_is_sunk_and_the_opponent_wins :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(25))}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, b.hull, 0)
	testing.expect(t, battle.ended)

	// The Battle mirrors the emitted ending (#159): a kill is queryable off it.
	testing.expect_value(t, battle.reason, End_Reason.Destroyed)
	battle_winner, battle_has_winner := battle.winner.?
	testing.expect(t, battle_has_winner)
	testing.expect_value(t, battle_winner, Side.A)

	sunk_found, ended_found := false, false
	for event in events {
		if sunk, ok := event.(Event_Ship_Sunk); ok {
			sunk_found = true
			testing.expect_value(t, sunk.side, Side.B)
		}
		if ended, ok := event.(Event_Battle_Ended); ok {
			ended_found = true
			testing.expect_value(t, ended.reason, End_Reason.Destroyed)
			winner, has_winner := ended.winner.?
			testing.expect(t, has_winner)
			testing.expect_value(t, winner, Side.A)
		}
	}
	testing.expect(t, sunk_found)
	testing.expect(t, ended_found)
}

@(test)
a_mutual_kill_in_the_same_round_is_won_by_the_higher_speed_side :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(25))}
	a := ship.Ship{
		hull = 20, speed = 10,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, a.hull, 0)
	testing.expect_value(t, b.hull, 0)

	for event in events {
		if ended, ok := event.(Event_Battle_Ended); ok {
			winner, has_winner := ended.winner.?
			testing.expect(t, has_winner)
			testing.expect_value(t, winner, Side.A)
		}
	}
}

@(test)
a_mutual_kill_with_equal_speed_has_no_winner :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(25))}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	b := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
	}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	for event in events {
		if ended, ok := event.(Event_Battle_Ended); ok {
			_, has_winner := ended.winner.?
			testing.expect(t, !has_winner)
		}
	}
}

@(test)
hard_round_cap_forces_resolution_by_higher_hull :: proc(t: ^testing.T) {
	a := ship.Ship{hull = 15, speed = 5}
	b := ship.Ship{hull = 10, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	for i in 0 ..< HARD_ROUND_CAP - 1 {
		clear(&events)
		combat_resolve_round(&battle, cmds, &events)
		testing.expect(t, !battle.ended)
	}

	clear(&events)
	combat_resolve_round(&battle, cmds, &events)

	testing.expect(t, battle.ended)
	testing.expect_value(t, battle.round, HARD_ROUND_CAP)
	ended, ok := find_battle_ended(events[:])
	testing.expect(t, ok)
	testing.expect_value(t, ended.reason, End_Reason.Round_Cap)
	winner, has_winner := ended.winner.?
	testing.expect(t, has_winner)
	testing.expect_value(t, winner, Side.A)

	// The Battle mirrors the emitted ending (#159): a stalemate is Round_Cap on it,
	// which is how voyage_finish_ship_battle tells a draw (pays nothing) from a kill.
	testing.expect_value(t, battle.reason, End_Reason.Round_Cap)
	battle_winner, battle_has_winner := battle.winner.?
	testing.expect(t, battle_has_winner)
	testing.expect_value(t, battle_winner, Side.A)
}

@(test)
hard_round_cap_tie_break_falls_back_to_speed_when_hull_is_tied :: proc(t: ^testing.T) {
	a := ship.Ship{hull = 10, speed = 8}
	b := ship.Ship{hull = 10, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = HARD_ROUND_CAP - 1

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	ended, ok := find_battle_ended(events[:])
	testing.expect(t, ok)
	winner, has_winner := ended.winner.?
	testing.expect(t, has_winner)
	testing.expect_value(t, winner, Side.A)
}

@(test)
hard_round_cap_tie_break_has_no_winner_when_hull_and_speed_are_both_tied :: proc(t: ^testing.T) {
	a := ship.Ship{hull = 10, speed = 5}
	b := ship.Ship{hull = 10, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = HARD_ROUND_CAP - 1

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events)

	ended, ok := find_battle_ended(events[:])
	testing.expect(t, ok)
	_, has_winner := ended.winner.?
	testing.expect(t, !has_winner)
}

find_battle_ended :: proc(events: []Event) -> (Event_Battle_Ended, bool) {
	for event in events {
		if ended, ok := event.(Event_Battle_Ended); ok {
			return ended, true
		}
	}
	return {}, false
}

// Heaved cargo is destroyed, never settled (ADR-0020, #159): there is no
// post-battle settlement to hand it back, so the ship's cargo just falls by the
// hold and stays fallen — win or lose. The literal "claimed by the opponent"
// reading was retired because it would make jettison free whenever you win.
@(test)
jettisoned_cargo_is_destroyed_with_nothing_to_settle :: proc(t: ^testing.T) {
	cargo := ship.Fitting{name = "Rations", size = .Small, cargo_held = 10}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = cargo}},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	testing.expect_value(t, ship.ship_cargo(a), 10)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 0})
	combat_resolve_round(&battle, cmds, &events)

	// The cargo is lighter, and there is no settlement path to give it back.
	testing.expect_value(t, ship.ship_cargo(a), 0)
}

@(test)
identical_ships_and_commands_produce_identical_results_every_time :: proc(t: ^testing.T) {
	make_ships :: proc() -> (ship.Ship, ship.Ship) {
		cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.effect_phase_contribution(ship.expr_const(7))}
		a := ship.Ship{
			hull = 30, speed = 5,
			layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
		}
		b := ship.Ship{
			hull = 30, speed = 6,
			layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = cannon}},
		}
		return a, b
	}

	run_five_rounds :: proc() -> (int, int) {
		a, b := make_ships()
		battle := combat_battle_create(&a, &b)
		events: [dynamic]Event
		defer delete(events)
		cmds: [Side]Maybe(Command)
		for i in 0 ..< 5 {
			clear(&events)
			combat_resolve_round(&battle, cmds, &events)
		}
		return a.hull, b.hull
	}

	a_hull_1, b_hull_1 := run_five_rounds()
	a_hull_2, b_hull_2 := run_five_rounds()

	testing.expect_value(t, a_hull_1, a_hull_2)
	testing.expect_value(t, b_hull_1, b_hull_2)
}

// Demo (issue #93): a synergy fitting's combat output scales with the count of
// installed fittings matching its selector, resolved against the owning ship's
// current layout at combat-resolve time (combat_phase_output routes magnitude
// through ship.effect_magnitude). Here an Fire "for each Weapon, +Offense"
// fitting's phase output rises as Weapon fittings are added and falls as they
// are removed. The synergy fitting is itself an Artifact, so it never counts
// toward its own selector — the output tracks the other Weapons only.
@(test)
synergy_offense_rises_and_falls_with_the_weapon_count_aboard :: proc(t: ^testing.T) {
	OFFENSE_PER_WEAPON :: 3
	synergy_gun := ship.Fitting{
		name     = "Runic Battery",
		size     = .Large,
		category = .Fire,
		tags     = {.Artifact},
		active   = ship.effect_phase_contribution(ship.expr_const(OFFENSE_PER_WEAPON), ship.Selector(ship.Tag.Weapon)),
	}
	cannon := ship.Fitting{name = "Cannon", size = .Large, tags = {.Weapon}}
	ballista := ship.Fitting{name = "Ballista", size = .Small, tags = {.Weapon}}

	s := ship.Ship{
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Large, base_visibility = .Exposed}, fitting = synergy_gun},
			{slot = ship.Slot{size = .Large, base_visibility = .Exposed}},
			{slot = ship.Slot{size = .Small, base_visibility = .Concealed}},
		},
	}
	// combat_phase_output resolves against a battle (issue #94); the synergy
	// count only depends on s's own layout, so the opponent is a bare ship.
	opponent := ship.Ship{}
	battle := combat_battle_create(&s, &opponent)

	// No Weapons aboard yet: for-each-Weapon output is zero.
	testing.expect_value(t, combat_phase_output_this_round(&battle, .A, .Fire), 0)

	// Add one Weapon: output rises to one Weapon's worth.
	s.layout[1].fitting = cannon
	testing.expect_value(t, combat_phase_output_this_round(&battle, .A, .Fire), OFFENSE_PER_WEAPON)

	// Add a second Weapon: output rises again.
	s.layout[2].fitting = ballista
	testing.expect_value(t, combat_phase_output_this_round(&battle, .A, .Fire), 2 * OFFENSE_PER_WEAPON)

	// Remove a Weapon: output falls back.
	s.layout[1].fitting = nil
	testing.expect_value(t, combat_phase_output_this_round(&battle, .A, .Fire), OFFENSE_PER_WEAPON)
}

@(test)
a_below_half_hull_conditional_offense_fitting_contributes_only_below_the_threshold :: proc(t: ^testing.T) {
	// Demo for issue #94: a "below half Hull, +Offense" fitting resolves its
	// Fire phase output through the conditional seam, so it adds nothing
	// while the ship is above half Hull and its full magnitude once below.
	desperado := ship.Fitting{
		name = "Desperado Cannon", size = .Large, category = .Fire,
		active = ship.effect_phase_contribution(ship.expr_below_hull_percent(50, 10)),
	}

	// Same fitting fired against the same bare target, differing only in the
	// attacker's current Hull relative to its half-Hull threshold.
	damage_dealt_at_hull :: proc(attacker: ship.Fitting, attacker_hull: int) -> int {
		a := ship.Ship{
			hull = attacker_hull, max_hull = 20, speed = 5,
			layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = attacker}},
		}
		b := ship.Ship{hull = 20, max_hull = 20, speed = 5}
		battle := combat_battle_create(&a, &b)
		events: [dynamic]Event
		defer delete(events)
		cmds: [Side]Maybe(Command)
		combat_resolve_round(&battle, cmds, &events)
		return 20 - b.hull
	}

	above := damage_dealt_at_hull(desperado, 20) // full Hull: above the threshold
	below := damage_dealt_at_hull(desperado, 9) // below half of 20

	testing.expect_value(t, above, 0) // contributes nothing above the threshold
	testing.expect_value(t, below, 10) // its full bonus below it
	testing.expect(t, below > above)
}

@(test)
a_while_concealed_conditional_offense_fitting_reads_its_own_slot_visibility :: proc(t: ^testing.T) {
	// The own-concealment trigger resolves against the slot the fitting sits in
	// (combat_phase_output fills self_slot per fitting): the same fitting in a
	// concealed slot contributes, in an exposed slot does not.
	ambush := ship.Fitting{
		name = "Ambush Cannon", size = .Large, category = .Fire,
		active = ship.effect_phase_contribution(ship.expr_while_concealed(8)),
	}

	damage_from_slot :: proc(attacker: ship.Fitting, base_visibility: ship.Visibility) -> int {
		a := ship.Ship{
			hull = 20, max_hull = 20, speed = 5,
			layout = []ship.Layout_Slot{
				{slot = ship.Slot{size = .Large, base_visibility = base_visibility}, fitting = attacker},
			},
		}
		b := ship.Ship{hull = 20, max_hull = 20, speed = 5}
		battle := combat_battle_create(&a, &b)
		events: [dynamic]Event
		defer delete(events)
		cmds: [Side]Maybe(Command)
		combat_resolve_round(&battle, cmds, &events)
		return 20 - b.hull
	}

	testing.expect_value(t, damage_from_slot(ambush, .Exposed), 0)
	testing.expect_value(t, damage_from_slot(ambush, .Concealed), 8)
}

// --- The round's two-pass context (#404) -------------------------------------
//
// The move this ticket exists for: an item authored to fire on a round number, on the
// opponent's speed, or on the captain's own order used to be resolved with no battle
// context at all, so it was *always unmet* — mid-battle included. These pin each of those
// readings through a real resolved round.

// fire_only builds a one-slot ship whose single Fire fitting carries `magnitude` as an
// authored tree, ready to be fought as side A. The caller owns the slot it lives in, so
// the layout outlives the call.
fire_only :: proc(layout: []ship.Layout_Slot, magnitude: ship.Expr) -> ship.Ship {
	gun := ship.Fitting {
		name     = "Authored Gun",
		size     = .Large,
		category = .Fire,
		active   = ship.effect_phase_contribution(magnitude),
	}
	layout[0] = ship.Layout_Slot{slot = ship.Slot{size = .Large}, fitting = gun}
	return ship.Ship{hull = 200, max_hull = 200, speed = 5, layout = layout}
}

// damage_this_round resolves one round with the given orders and reports what side B lost.
damage_this_round :: proc(battle: ^Battle, cmds: [Side]Maybe(Command)) -> int {
	events: [dynamic]Event
	defer delete(events)
	before := battle.ships[.B].hull
	combat_resolve_round(battle, cmds, &events)
	return before - battle.ships[.B].hull
}

@(test)
a_round_gated_item_fires_the_round_it_names_and_not_before :: proc(t: ^testing.T) {
	a_layout: [1]ship.Layout_Slot
	a := fire_only(a_layout[:], ship.expr_from_round(3, 7))
	b := ship.Ship{hull = 200, max_hull = 200, speed = 5}
	battle := combat_battle_create(&a, &b)
	none: [Side]Maybe(Command)

	testing.expect_value(t, damage_this_round(&battle, none), 0) // round 1
	testing.expect_value(t, damage_this_round(&battle, none), 0) // round 2
	testing.expect_value(t, damage_this_round(&battle, none), 7) // round 3: it wakes up
	testing.expect_value(t, damage_this_round(&battle, none), 7) // and stays awake
}

@(test)
an_opponent_speed_gated_item_reads_the_speeds_pass_one_computed :: proc(t: ^testing.T) {
	// Side B is the heavier ship, so A is the faster one and a "vs a faster foe" item
	// stays quiet; loading A down flips which side is faster and wakes it.
	a_layout: [1]ship.Layout_Slot
	a := fire_only(a_layout[:], ship.expr_while_opponent_faster(5))
	b := ship.Ship{hull = 200, max_hull = 200, speed = 20}
	battle := combat_battle_create(&a, &b)
	none: [Side]Maybe(Command)

	testing.expect(t, combat_effective_speed(&battle, .B) > combat_effective_speed(&battle, .A))
	testing.expect_value(t, damage_this_round(&battle, none), 5)

	b.speed = 1 // now the slower side
	testing.expect_value(t, damage_this_round(&battle, none), 0)
}

@(test)
an_order_reading_item_pays_on_the_round_its_order_is_given :: proc(t: ^testing.T) {
	// "Pays off the round the captain presses Fire" — a reading of the captain's own
	// order, which no context carried before this. Press multiplies its own phase, so the
	// item's 4 lands as 12 on the round it fires.
	on_press_fire := ship.expr_gate(
		.Eq,
		ship.expr_quantity(.Captains_Order),
		ship.expr_const(int(ship.Captains_Order.Press_Fire)),
		ship.expr_const(4),
		ship.expr_const(0),
	)
	a_layout: [1]ship.Layout_Slot
	a := fire_only(a_layout[:], on_press_fire)
	b := ship.Ship{hull = 200, max_hull = 200, speed = 5}
	battle := combat_battle_create(&a, &b)

	quiet: [Side]Maybe(Command)
	testing.expect_value(t, damage_this_round(&battle, quiet), 0)

	pressing: [Side]Maybe(Command)
	pressing[.A] = Command_Press{phase = .Fire}
	testing.expect_value(t, damage_this_round(&battle, pressing), 4 * PRESS_MULTIPLIER)

	// The order is this round's, not a flag that stays set.
	testing.expect_value(t, damage_this_round(&battle, quiet), 0)
}

@(test)
the_opponents_order_is_not_a_thing_a_tree_can_read :: proc(t: ^testing.T) {
	// There is one order quantity and it is the reader's own, so B pressing changes
	// nothing about what A's order-reading item pays. A scripted ship's order is a
	// constant, so reading it would carry no information anyway.
	on_press_fire := ship.expr_gate(
		.Eq,
		ship.expr_quantity(.Captains_Order),
		ship.expr_const(int(ship.Captains_Order.Press_Fire)),
		ship.expr_const(4),
		ship.expr_const(0),
	)
	a_layout: [1]ship.Layout_Slot
	a := fire_only(a_layout[:], on_press_fire)
	b := ship.Ship{hull = 200, max_hull = 200, speed = 5}
	battle := combat_battle_create(&a, &b)

	opponent_presses: [Side]Maybe(Command)
	opponent_presses[.B] = Command_Press{phase = .Fire}
	testing.expect_value(t, damage_this_round(&battle, opponent_presses), 0)
}

@(test)
damage_taken_last_round_is_what_the_hull_lost_and_starts_a_battle_at_zero :: proc(t: ^testing.T) {
	// A "hit me and I hit back harder" item reads the previous round's loss, so it deals
	// nothing in round one and mirrors the incoming damage from round two on.
	a_layout: [1]ship.Layout_Slot
	a := fire_only(a_layout[:], ship.expr_quantity(.Damage_Taken_Last_Round))
	hitter := ship.Fitting {
		name     = "Cannon",
		size     = .Large,
		category = .Fire,
		active   = ship.effect_phase_contribution(ship.expr_const(6)),
	}
	b := ship.Ship {
		hull = 200,
		max_hull = 200,
		speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Large}, fitting = hitter}},
	}
	battle := combat_battle_create(&a, &b)
	none: [Side]Maybe(Command)

	// Round one: nothing has happened yet, so the counter is the zero Battle's zero.
	testing.expect_value(t, battle.damage_taken_last_round[.A], 0)
	testing.expect_value(t, damage_this_round(&battle, none), 0)
	testing.expect_value(t, battle.damage_taken_last_round[.A], 6)

	// Round two: it fires back exactly what it took.
	testing.expect_value(t, damage_this_round(&battle, none), 6)
}

@(test)
a_round_gated_speed_modifier_moves_escape_eligibility_mid_battle :: proc(t: ^testing.T) {
	// The two-pass build in one player-visible consequence: a speed modifier that wakes on
	// round three lifts the ship's Speed *inside* the battle, so the side that could not
	// break off becomes the strictly-faster one and can. Resolved with no round at all —
	// which is what happened before #404 — it would never fire and the escape would never
	// open.
	sails := ship.Fitting {
		name    = "Storm Canvas",
		size    = .Small,
		passive = ship.effect_modify_speed(ship.expr_from_round(3, 6)),
	}
	a := ship.Ship {
		hull = 200,
		max_hull = 200,
		speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = sails}},
	}
	b := ship.Ship{hull = 200, max_hull = 200, speed = 5}
	battle := combat_battle_create(&a, &b)

	battle.round = 2
	testing.expect_value(t, combat_effective_speed(&battle, .A), 5)

	battle.round = 3
	testing.expect_value(t, combat_effective_speed(&battle, .A), 5 + 6)

	battle.round = BASELINE_ROUND_COUNT
	testing.expect(t, combat_may_break_off(&battle, .A))
	testing.expect(t, !combat_may_break_off(&battle, .B))
}

@(test)
an_item_reading_the_opponent_counts_only_what_is_exposed :: proc(t: ^testing.T) {
	// The opponent reaches a tree as a scouting report and nothing else, so a "+2 per gun
	// they are showing" item pays for the guns on deck and nothing for the ones below it.
	per_enemy_gun := ship.expr_mul(ship.expr_const(2), ship.expr_count_opponent(ship.Selector(ship.Tag.Weapon)))
	a_layout: [1]ship.Layout_Slot
	a := fire_only(a_layout[:], per_enemy_gun)
	gun :: proc() -> ship.Fitting {
		return ship.Fitting{name = "Long Nines", size = .Large, tags = {.Weapon}}
	}
	b := ship.Ship {
		hull = 200,
		max_hull = 200,
		speed = 5,
		layout = []ship.Layout_Slot {
			{slot = ship.Slot{size = .Large, base_visibility = .Exposed}, fitting = gun()},
			{slot = ship.Slot{size = .Large, base_visibility = .Concealed}, fitting = gun()},
		},
	}
	battle := combat_battle_create(&a, &b)
	none: [Side]Maybe(Command)

	// Two guns aboard, one of them out of sight: only the exposed one is counted.
	testing.expect_value(t, damage_this_round(&battle, none), 2)
}
