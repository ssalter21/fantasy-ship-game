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
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.Effect{magnitude = 10}}
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
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.Effect{magnitude = 10}}
	surgeon := ship.Fitting{name = "Ship's Surgeon", category = .Brace, active = ship.Effect{kind = .Repair, magnitude = 4}}
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
		crew := ship.Fitting{name = "Top Crew", category = .Fire, tags = {.Crew}, active = ship.Effect{magnitude = crew_mag}}
		gun := ship.Fitting{name = "Cannon", category = .Fire, tags = {.Weapon}, active = ship.Effect{magnitude = gun_mag}}
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
	crew := ship.Fitting{name = "Top Crew", category = .Fire, tags = {.Crew}, active = ship.Effect{magnitude = 3}}
	shield := ship.Fitting{name = "Shield Charm", category = .Brace, active = ship.Effect{magnitude = 4}}
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.Effect{magnitude = 20}}
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
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.Effect{magnitude = 10}}
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
	cmds[.A] = Command(Command_Press{phase = .Fire})
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, b.hull, 20-10*PRESS_MULTIPLIER)
	testing.expect_value(t, a.hull, 20-10)
}

// Press Fire doubles the *whole* Fire pile — the guns and the crew-tagged fittings
// alike — since they share the one Fire phase (ADR-0025). No seam splits the pile.
@(test)
press_fire_multiplies_the_whole_fire_pile_including_former_crew :: proc(t: ^testing.T) {
	crew := ship.Fitting{name = "Top Crew", category = .Fire, tags = {.Crew}, active = ship.Effect{magnitude = 2}}
	cannon := ship.Fitting{name = "Cannon", category = .Fire, tags = {.Weapon}, active = ship.Effect{magnitude = 5}}
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

	// (crew(2) + cannon(5)) * PRESS_MULTIPLIER = 14 — both piles doubled, no seam.
	testing.expect_value(t, b.hull, 40-(2+5)*PRESS_MULTIPLIER)
}

// Press Brace doubles its own phase's fittings like any Press (ADR-0006), and since that
// phase repairs, the order buys Hull: the pressing ship ends the round PRESS_MULTIPLIER
// repairs better off than the one that held.
@(test)
press_brace_doubles_the_repair_the_round_restores :: proc(t: ^testing.T) {
	surgeon := ship.Fitting{name = "Ship's Surgeon", category = .Brace, active = ship.Effect{kind = .Repair, magnitude = 4}}
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.Effect{magnitude = 20}}

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
		passive = ship.Effect{kind = .Modify_Speed, magnitude = 3},
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

	testing.expect_value(t, combat_phase_output(&battle, .A, .Brace), ship.CAPTAINS_QUARTERS_REPAIR_MAGNITUDE)
	testing.expect_value(t, combat_phase_output(&battle, .A, .Fire), ship.TOP_CREW_OFFENSE_MAGNITUDE + ship.GUN_DECK_OFFENSE_MAGNITUDE)
}

@(test)
hold_is_a_no_op_identical_to_submitting_no_command :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.Effect{magnitude = 10}}
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

	// Same outcome as the no-command baseline round (cannon(10) not pressed,
	// no Man the Sails/Jettison/Break Off side effects): Hold contributes nothing.
	testing.expect_value(t, b.hull, 20-10)
	testing.expect_value(t, a.hull, 20)
	testing.expect_value(t, combat_effective_speed(&battle, .A), 5)
	testing.expect(t, !battle.ended)
}

@(test)
man_the_sails_grants_a_speed_increase_for_this_round_only :: proc(t: ^testing.T) {
	a := ship.Ship{hull = 20, speed = 5}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Man_The_Sails{})
	combat_resolve_round(&battle, cmds, &events)

	testing.expect_value(t, combat_effective_speed(&battle, .A), 5+MAN_THE_SAILS_SPEED_BONUS)

	next_cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, next_cmds, &events)

	testing.expect_value(t, combat_effective_speed(&battle, .A), 5)
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
reallocate_moves_cargo_between_holds_without_changing_weight_or_speed :: proc(t: ^testing.T) {
	// Reallocation pours cargo from one hold into another, conserving the total
	// aboard (ADR-0020, #157): weight is unchanged, so Speed does not move the round it
	// is issued — what it buys is jettison granularity, not Speed. A full Large (40)
	// pours into an empty Small, capped at the Small's 10 capacity (the destination
	// slot's size is the denomination, #156).
	large_cargo := ship.Fitting{name = "Cargo", size = .Large, cargo_held = 40}
	a := ship.Ship{
		hull = 20, speed = 10,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Large}, fitting = large_cargo},
			{slot = ship.Slot{size = .Small}, fitting = ship.ship_fitting_hold(.Small)},
		},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	before := combat_effective_speed(&battle, .A) // 10 − 40/10 = 6
	testing.expect_value(t, before, 6)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	combat_resolve_round(&battle, cmds, &events)

	src, ok0 := a.layout[0].fitting.?
	testing.expect(t, ok0)
	testing.expect_value(t, src.cargo_held, 30) // gave up the Small's 10
	dst, ok1 := a.layout[1].fitting.?
	testing.expect(t, ok1)
	testing.expect_value(t, dst.cargo_held, 10) // a new Small hold, full
	testing.expect_value(t, ship.ship_cargo(a), 40) // conserved
	testing.expect_value(t, combat_effective_speed(&battle, .A), before) // no weight shifted

	found := false
	for event in events {
		if moved, ok := event.(Event_Cargo_Reallocated); ok {
			found = true
			testing.expect_value(t, moved.side, Side.A)
			testing.expect_value(t, moved.from, ship.Slot_Index(0))
			testing.expect_value(t, moved.to, ship.Slot_Index(1))
			testing.expect_value(t, moved.amount, 10)
		}
	}
	testing.expect(t, found)
}

@(test)
reallocate_buys_a_finer_jettison_than_the_hold_allowed :: proc(t: ^testing.T) {
	// The precision reallocation buys (#157): with a single full Large as its only
	// cargo, the cheapest heave is the whole 40 (4 Speed). Splitting 10 into an empty
	// Small first lets the next Jettison shed exactly 10 (1 Speed) — a finer amount
	// than was reachable before the reallocation, paid for with the round it cost.
	large_cargo := ship.Fitting{name = "Cargo", size = .Large, cargo_held = 40}
	a := ship.Ship{
		hull = 20, speed = 10,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Large}, fitting = large_cargo},
			{slot = ship.Slot{size = .Small}, fitting = ship.ship_fitting_hold(.Small)},
		},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	laden := combat_effective_speed(&battle, .A) // 10 − 40/10 = 6

	events: [dynamic]Event
	defer delete(events)

	// Round 1: reallocate 10 into the Small. Weight unchanged, so Speed unchanged.
	realloc_cmds: [Side]Maybe(Command)
	realloc_cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	combat_resolve_round(&battle, realloc_cmds, &events)
	testing.expect_value(t, combat_effective_speed(&battle, .A), laden)

	// Round 2: jettison the freshly-split Small — sheds exactly 10, one Speed, a finer
	// heave than the 40 the hold allowed before.
	jettison_cmds: [Side]Maybe(Command)
	jettison_cmds[.A] = Command(Command_Jettison_Cargo{slot_index = 1})
	combat_resolve_round(&battle, jettison_cmds, &events)
	testing.expect_value(t, combat_effective_speed(&battle, .A), laden + 1)
}

@(test)
reallocate_into_a_partial_hold_grows_it_up_to_capacity :: proc(t: ^testing.T) {
	// Pouring into a partly-full cargo fitting grows it, capped at min(source, room)
	// (#156): a Medium holding 5 has room for 15 more, so a Large of 40 gives up
	// exactly 15 and keeps 25 — nothing overflows or is lost.
	large_cargo := ship.Fitting{name = "Cargo", size = .Large, cargo_held = 40}
	medium_cargo := ship.Fitting{name = "Cargo", size = .Medium, cargo_held = 5}
	a := ship.Ship{
		hull = 20, speed = 10,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Large}, fitting = large_cargo},
			{slot = ship.Slot{size = .Medium}, fitting = medium_cargo},
		},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	combat_resolve_round(&battle, cmds, &events)

	src, ok0 := a.layout[0].fitting.?
	testing.expect(t, ok0)
	testing.expect_value(t, src.cargo_held, 25)
	dst, ok1 := a.layout[1].fitting.?
	testing.expect(t, ok1)
	testing.expect_value(t, dst.cargo_held, 20) // 5 + 15, a full Medium
	testing.expect_value(t, ship.ship_cargo(a), 45)
}

@(test)
reallocate_that_empties_the_source_leaves_the_fitting_in_place :: proc(t: ^testing.T) {
	// A source drained to nothing keeps its fitting — an emptied hold is an ordinary
	// installed fitting, and the ship's capacity, not an empty slot. A Small of 10
	// poured into an empty Medium moves all 10 and leaves the Small carrying nothing.
	small_cargo := ship.Fitting{name = "Cargo", size = .Small, cargo_held = 10}
	a := ship.Ship{
		hull = 20, speed = 10,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = small_cargo},
			{slot = ship.Slot{size = .Medium}, fitting = ship.ship_fitting_hold(.Medium)},
		},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)

	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	combat_resolve_round(&battle, cmds, &events)

	src, still_occupied := a.layout[0].fitting.?
	testing.expect(t, still_occupied)
	testing.expect_value(t, src.cargo_held, 0)
	testing.expect_value(t, ship.ship_fitting_capacity(src), 10) // still capacity, just empty
	dst, ok1 := a.layout[1].fitting.?
	testing.expect(t, ok1)
	testing.expect_value(t, dst.cargo_held, 10)
}

@(test)
reallocate_from_a_slot_to_itself_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}
	cargo := ship.Fitting{name = "Cargo", size = .Small, cargo_held = 10}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{{slot = ship.Slot{size = .Small}, fitting = cargo}},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 0})
	testing.expect_assert(t, "Command_Reallocate from and to are the same slot")
	combat_resolve_round(&battle, cmds, &events)
}

@(test)
reallocate_from_a_fitting_carrying_nothing_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}
	cannon := ship.Fitting{name = "Cannon", category = .Fire}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Large}, fitting = cannon},
			{slot = ship.Slot{size = .Small}},
		},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	testing.expect_assert(t, "Command_Reallocate from holds no cargo")
	combat_resolve_round(&battle, cmds, &events)
}

@(test)
reallocate_into_an_empty_slot_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}
	// "Into a non-cargo fitting" has no referent left — every fitting sits on the cargo
	// axis, so a gun with bulk to spare is a legal destination. What is illegal is an
	// *empty* slot: it holds nothing to pour into and carries no capacity of its own.
	cargo := ship.Fitting{name = "Cargo", size = .Small, cargo_held = 10}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = cargo},
			{slot = ship.Slot{size = .Large}},
		},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	testing.expect_assert(t, "Command_Reallocate to is an empty slot")
	combat_resolve_round(&battle, cmds, &events)
}

@(test)
reallocate_may_pour_into_a_fitting_that_is_not_a_hold :: proc(t: ^testing.T) {
	// The axis made this legal: a gun that authors less than its full slot carries the
	// remainder, so it is a destination like any other.
	cargo := ship.Fitting{name = "Cargo", size = .Small, cargo_held = 10}
	armed_trader := ship.Fitting{name = "Armed Trader", size = .Large, bulk = 30, category = .Fire}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = cargo},
			{slot = ship.Slot{size = .Large}, fitting = armed_trader},
		},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	combat_resolve_round(&battle, cmds, &events)

	dst, _ := a.layout[1].fitting.?
	testing.expect_value(t, dst.cargo_held, 10) // into the gun's spare 10
	testing.expect_value(t, ship.ship_cargo(a), 10) // conserved
}

@(test)
reallocate_into_a_full_hold_moves_nothing_and_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}
	// A full destination has no room, so the move would shift 0 cargo — the menu
	// never offers it (battle_reallocate_can_receive), and the combat layer asserts,
	// exactly like jettisoning an empty slot buys nothing.
	from_cargo := ship.Fitting{name = "Cargo", size = .Small, cargo_held = 10}
	full_small := ship.Fitting{name = "Cargo", size = .Small, cargo_held = 10}
	a := ship.Ship{
		hull = 20, speed = 5,
		layout = []ship.Layout_Slot{
			{slot = ship.Slot{size = .Small}, fitting = from_cargo},
			{slot = ship.Slot{size = .Small}, fitting = full_small},
		},
	}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	events: [dynamic]Event
	defer delete(events)
	cmds: [Side]Maybe(Command)
	cmds[.A] = Command(Command_Reallocate{from = 0, to = 1})
	testing.expect_assert(t, "Command_Reallocate moves no cargo (source empty or destination full)")
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
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.Effect{magnitude = 10}}
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
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.Effect{magnitude = 10}}
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
man_the_sails_speed_increase_can_swing_escape_eligibility_for_the_round_it_was_used :: proc(t: ^testing.T) {
	a := ship.Ship{hull = 20, speed = 5}
	b := ship.Ship{hull = 20, speed = 5}
	battle := combat_battle_create(&a, &b)
	battle.round = BASELINE_ROUND_COUNT - 1

	events: [dynamic]Event
	defer delete(events)

	// Tied base Speed: not escape-eligible on its own once baseline is reached.
	cmds: [Side]Maybe(Command)
	combat_resolve_round(&battle, cmds, &events) // battle.round == BASELINE_ROUND_COUNT
	testing.expect(t, !combat_may_break_off(&battle, .A))

	// A plays Man the Sails this round, tipping it strictly faster. The
	// temp_speed bonus isn't reset until the *next* combat_resolve_round
	// call, so it's still in effect for the escape-eligibility check made
	// right after this round resolves (i.e. before next round's command).
	clear(&events)
	sails_cmds: [Side]Maybe(Command)
	sails_cmds[.A] = Command(Command_Man_The_Sails{})
	combat_resolve_round(&battle, sails_cmds, &events)

	testing.expect(t, combat_may_break_off(&battle, .A))
}

@(test)
a_ship_reduced_to_zero_hull_is_sunk_and_the_opponent_wins :: proc(t: ^testing.T) {
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.Effect{magnitude = 25}}
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
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.Effect{magnitude = 25}}
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
	cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.Effect{magnitude = 25}}
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
		cannon := ship.Fitting{name = "Cannon", category = .Fire, active = ship.Effect{magnitude = 7}}
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
		active   = ship.Effect{magnitude = OFFENSE_PER_WEAPON, synergy = ship.Selector(ship.Tag.Weapon)},
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
	testing.expect_value(t, combat_phase_output(&battle, .A, .Fire), 0)

	// Add one Weapon: output rises to one Weapon's worth.
	s.layout[1].fitting = cannon
	testing.expect_value(t, combat_phase_output(&battle, .A, .Fire), OFFENSE_PER_WEAPON)

	// Add a second Weapon: output rises again.
	s.layout[2].fitting = ballista
	testing.expect_value(t, combat_phase_output(&battle, .A, .Fire), 2 * OFFENSE_PER_WEAPON)

	// Remove a Weapon: output falls back.
	s.layout[1].fitting = nil
	testing.expect_value(t, combat_phase_output(&battle, .A, .Fire), OFFENSE_PER_WEAPON)
}

@(test)
a_below_half_hull_conditional_offense_fitting_contributes_only_below_the_threshold :: proc(t: ^testing.T) {
	// Demo for issue #94: a "below half Hull, +Offense" fitting resolves its
	// Fire phase output through the conditional seam, so it adds nothing
	// while the ship is above half Hull and its full magnitude once below.
	desperado := ship.Fitting{
		name = "Desperado Cannon", size = .Large, category = .Fire,
		active = ship.Effect{magnitude = 10, conditional = ship.Condition_Hull_Below{percent = 50}},
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
		active = ship.Effect{magnitude = 8, conditional = ship.Condition_Self_Visibility{visibility = .Concealed}},
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
