package run

import "../combat"
import "../ship"
import "core:math/rand"
import "core:strings"
import "core:testing"

// test_opponent builds an opponent the way run_bake_stage does, off a fresh
// generator for `seed`, so a test can talk about "the hostile seed 3 deals" without
// standing up a whole map.
test_opponent :: proc(site: Scaling_Site, seed: u64) -> ship.Ship {
	state := rand.create(seed)
	return run_pve_opponent(site, rand.default_random_generator(&state))
}

// test_hostile builds one *named* archetype at a site, bypassing the draw — the
// per-archetype tests need to say which build they mean rather than fish for it
// across seeds.
test_hostile :: proc(archetype: Hostile_Archetype, site: Scaling_Site) -> ship.Ship {
	s := run_make_opponent_ship(site) // sets the uniform BASE_SPEED base
	layout := ship.ship_template_layout()
	assert(run_fit_hostile_loadout(layout, archetype, run_fight_opponent_power(site)))
	s.layout = layout
	return s
}

// hostile_output is what an archetype actually *deals* in a round —
// `raw_damage = Offensive + Buff` (core/combat, ADR-0017) — resolved through a real
// Battle rather than read off the authored magnitudes.
//
// The distinction is the whole reason this helper exists (#165). phase_magnitude
// below sums `active.magnitude` directly, which is blind to both seams that stand
// between a magnitude and a damage number: a **synergy** multiplies it by its match
// count, and a **conditional** gates it on live battle state. #135's independence
// test measured magnitudes and so reported a property that resolved output did not
// have — Deepwater Menagerie collected 14 points of a site reading worth 9, because
// Hunter's Pack's share was multiplied by the Beasts aboard. A property about what a
// hostile hits for has to be measured where it is hit.
//
// `round` picks which round's state the conditionals resolve against; Death Throes
// is a different ship above and below half Hull.
hostile_output :: proc(hostile: ^ship.Ship, round: int = 1) -> int {
	player := ship.ship_starting_ship()
	defer delete(player.layout)

	battle := combat.combat_battle_create(&player, hostile)
	battle.round = round
	return combat.combat_phase_output(&battle, .B, .Offensive) + combat.combat_phase_output(&battle, .B, .Buff)
}

// hostile_at_power builds an archetype at an explicit power percent, off a site that
// contributes nothing of its own — the only way to ask what an entry was *authored*
// as (100%) independently of where it was met.
hostile_at_power :: proc(archetype: Hostile_Archetype, percent: int) -> ship.Ship {
	s := ship.Ship{}
	s.speed = ship.BASE_SPEED
	layout := ship.ship_template_layout()
	assert(run_fit_hostile_loadout(layout, archetype, percent))
	s.layout = layout
	return s
}

@(test)
run_pve_opponent_fills_every_slot_of_the_one_ship_template :: proc(t: ^testing.T) {
	opponent := test_opponent(Scaling_Site{zone = .Coastal, depth = 3}, 0)
	defer delete(opponent.layout)

	testing.expect_value(t, len(opponent.layout), 8)
	for layout_slot in opponent.layout {
		_, has_fitting := layout_slot.fitting.?
		testing.expect(t, has_fitting)
	}
}

@(test)
run_pve_opponent_stats_reuse_the_existing_zone_and_depth_scaled_fight_formulas :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Deep, depth = 2}
	opponent := test_opponent(site, 0)
	defer delete(opponent.layout)

	testing.expect_value(t, opponent.hull, run_fight_opponent_hull(site))
	testing.expect_value(t, opponent.durability, run_fight_opponent_durability(site))
}

@(test)
run_pve_opponent_carries_no_captain :: proc(t: ^testing.T) {
	opponent := test_opponent(Scaling_Site{zone = .Coastal, depth = 3}, 0)
	defer delete(opponent.layout)

	_, has_captain := opponent.captain.?
	testing.expect(t, !has_captain)
}

// --- Hostile roster (issue #135) --------------------------------------------

// The point of the ticket. Every battle in the game used to be the same ship with
// bigger numbers — a hostile *template*, not a roster. If the draw only ever yields
// one build, nothing was retired.
@(test)
run_pve_opponent_draws_more_than_one_distinct_archetype_across_seeds :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Open_Sea, depth = 1}
	seen: map[string]bool
	defer delete(seen)

	for seed in u64(0) ..< 50 {
		opponent := test_opponent(site, seed)
		defer delete(opponent.layout)
		// An archetype has no name on the built Ship, so identify the build by the
		// loadout it produced — which is the thing the player actually meets.
		seen[loadout_signature(opponent)] = true
	}

	testing.expect(t, len(seen) > 1)
}

// Baked at generation off the map generator's RNG, so the same seed must yield the
// same hostile — the no-runtime-RNG property (ADR-0013) covers which opponent a
// node holds, like every other stage's content.
@(test)
run_pve_opponent_is_reproducible_per_seed :: proc(t: ^testing.T) {
	site := Scaling_Site{zone = .Deep, depth = 2}
	a := test_opponent(site, 11)
	defer delete(a.layout)
	b := test_opponent(site, 11)
	defer delete(b.layout)

	testing.expect_value(t, loadout_signature(a), loadout_signature(b))
	// Speed is derived from the loadout now (ADR-0020), so a reproducible draw reads a
	// reproducible Speed — the raw base field is the uniform BASE_SPEED on both.
	testing.expect_value(t, ship.ship_effective_speed(&a), ship.ship_effective_speed(&b))
}

// An archetype names its items instead of restating their magnitudes, so a typo is
// caught here rather than by an assert at map generation. Also the template-drift
// check: an entry asking for more Larges than the template has cannot fit.
@(test)
every_hostile_archetype_is_built_from_real_roster_items :: proc(t: ^testing.T) {
	for archetype in run_hostile_roster() {
		testing.expect(t, len(archetype.name) > 0)
		testing.expectf(t, len(archetype.items) > 0, "%v carries no items", archetype.name)

		for name in archetype.items {
			_, found := ship.ship_item_by_name(name)
			testing.expectf(t, found, "%v names %q, which is not a roster item", archetype.name, name)
		}

		layout := ship.ship_template_layout()
		defer delete(layout)
		testing.expectf(
			t,
			run_fit_hostile_loadout(layout, archetype, 0),
			"%v's items do not fit the one ship template",
			archetype.name,
		)
	}
}

// Stakes is the power axis: a deeper node's hostile hits harder, whichever build it
// happens to be. Drawing both from the same seed makes them the same archetype, so
// the only difference is the site.
@(test)
a_deeper_node_gives_the_opponent_harder_hitting_offensive_fittings :: proc(t: ^testing.T) {
	coastal := test_opponent(Scaling_Site{zone = .Coastal, depth = 0}, 4)
	defer delete(coastal.layout)
	deep := test_opponent(Scaling_Site{zone = .Deep, depth = 3}, 4)
	defer delete(deep.layout)

	testing.expect_value(t, loadout_signature(coastal), loadout_signature(deep)) // same build
	testing.expect(t, phase_magnitude(deep, .Offensive) > phase_magnitude(coastal, .Offensive))
	testing.expect(t, deep.hull > coastal.hull)
	testing.expect(t, deep.durability > coastal.durability)
}

// **Stakes scales what a hostile deals, never what it soaks** — the surviving half
// of #135's rule (run_stakes_scales_category), and the half whose reason is still
// alive: soak is subtracted from raw damage, so a site that scaled it would make a
// deep hostile impossible to *hurt* rather than harder to fight.
//
// The other half of #135's rule — "Buff is not scaled either" — is deliberately
// **gone** (#165), because #151 took Buff out of `defense_bonus`, so a scaled Buff
// fitting now hits harder rather than soaking harder. That the two halves had one
// stated reason and only one of them still holds is why this test names the
// property rather than the category list.
//
// Both of a Defensive fitting's routes into soak are checked, since the roster uses
// both: `Barricades` is an active that feeds the Defensive phase, and `Reinforced
// Hull` is a passive Modify_Durability that never enters a phase at all. The site's
// own durability reading is subtracted off so this asks about the *archetype's*
// contribution rather than run_make_opponent_ship's baseline, which is a stakes
// reading and is meant to move.
@(test)
the_site_scales_what_a_hostile_deals_and_never_what_it_soaks :: proc(t: ^testing.T) {
	shallow_site := Scaling_Site{zone = .Coastal, depth = 0}
	deep_site := Scaling_Site{zone = .Deep, depth = DEPTH_STEPS}

	for archetype in run_hostile_roster() {
		shallow := test_hostile(archetype, shallow_site)
		defer delete(shallow.layout)
		deep := test_hostile(archetype, deep_site)
		defer delete(deep.layout)

		testing.expectf(
			t,
			phase_magnitude(deep, .Defensive) == phase_magnitude(shallow, .Defensive),
			"%v's defensive output moved with the site — soak is subtracted from raw, so scaling it walls the player",
			archetype.name,
		)
		testing.expectf(
			t,
			ship.ship_effective_durability(&deep) - run_fight_opponent_durability(deep_site) ==
			ship.ship_effective_durability(&shallow) - run_fight_opponent_durability(shallow_site),
			"%v's fittings contributed more Durability in The Deep — the site scaled a Modify_Durability passive",
			archetype.name,
		)
	}
}

// **Speed is the archetype's axis, and the site must not touch it** (#165, and the
// reason FIGHT_OPPONENT_SPEED was retired onto Hostile_Archetype by #135).
//
// This is a new tripwire, and it is live rather than theoretical: the roster's four
// Modify_Speed items are filed under Category `.Buff` (Spare Rigging, Copper
// Sheathing, Outriggers, Enchanted Keel), and `.Buff` is a category the site now
// scales. Only ship_fitting_output_scaled's refusal to touch anything but an active
// Phase_Contribution keeps a Deep node from handing Reef Skimmer more Speed than a
// Coastal one — which would quietly decide who is allowed to leave the fight, since
// escape eligibility is *strictly faster* (combat_may_leave).
//
// Two archetypes have real stakes in this: Smuggler's Run's Spare Rigging is what
// takes it to an effective 8 so it bolts the round the gate opens, and Reef Skimmer
// is two Modify_Speed items stacked.
@(test)
the_site_never_moves_a_hostiles_speed :: proc(t: ^testing.T) {
	for archetype in run_hostile_roster() {
		shallow := test_hostile(archetype, Scaling_Site{zone = .Coastal, depth = 0})
		defer delete(shallow.layout)
		deep := test_hostile(archetype, Scaling_Site{zone = .Deep, depth = DEPTH_STEPS})
		defer delete(deep.layout)

		testing.expectf(
			t,
			ship.ship_effective_speed(&deep) == ship.ship_effective_speed(&shallow),
			"%v sails at %d in The Deep and %d at Coastal — the site is scaling a Modify_Speed fitting, and Speed is the archetype's axis",
			archetype.name,
			ship.ship_effective_speed(&deep),
			ship.ship_effective_speed(&shallow),
		)
	}
}

// **The independence property, measured where the damage lands** (#165).
//
// #135 wanted the site's reading to be worth the same to every archetype, so that
// which hostile you drew could not matter more than how deep you were. Its shared
// total (run_offense_share) could not deliver that, and its test could not see the
// failure: measuring *authored magnitudes*, it reported an equal uplift while
// resolved output diverged by 56% — Deepwater Menagerie's Hunter's Pack multiplied
// its share by the Beasts aboard, and Death Throes banked most of its share behind
// an Hull conditional.
//
// A multiplier states the property in the only form that can hold through a synergy:
// **the same proportion, not the same amount.** `(m x pct) x count` is
// `pct x (m x count)` for any count, so this passes for a flat build, a Selector
// build and a conditional build alike — which is the structural claim, and it is
// what the additive share could never make.
//
// Resolved at round 1 and again at a round where Death Throes' Hull conditionals are
// live would need two ships; round 1 is enough, because the property is about the
// *shape* of the scaling and a conditional that is unmet contributes 0 at every
// power, which scales correctly and trivially.
//
// The tolerance is rounding, and it is bounded rather than fudged:
// ship_fitting_output_scaled rounds each fitting half-up, so a fitting is off by at
// most half a point before its synergy count multiplies it — a couple of points
// across a whole build. It is deliberately far tighter than the 5-point divergence
// the old model had at Coastal and the 5-point one it had in The Deep.
@(test)
the_site_scales_every_archetype_by_the_same_proportion :: proc(t: ^testing.T) {
	// Half a point per scaled fitting, times the largest synergy count in the roster.
	TOLERANCE :: 2

	for archetype in run_hostile_roster() {
		as_authored := hostile_at_power(archetype, 100)
		defer delete(as_authored.layout)
		base := hostile_output(&as_authored)

		for zone in Zone {
			for depth in 0 ..= DEPTH_STEPS {
				site := Scaling_Site{zone = zone, depth = depth}
				percent := run_fight_opponent_power(site)

				hostile := test_hostile(archetype, site)
				defer delete(hostile.layout)

				expected := (base * percent) / 100
				actual := hostile_output(&hostile)
				testing.expectf(
					t,
					abs(actual - expected) <= TOLERANCE,
					"%v deals %d at %v depth %d (%d%% of an authored %d); every archetype must land within %d of %d — the site's reading is worth more to this build than to a flat one",
					archetype.name,
					actual,
					zone,
					depth,
					percent,
					base,
					TOLERANCE,
					expected,
				)
			}
		}
	}
}

// **100% means the archetype exactly as authored** — the property that lets the
// roster's entries be read as written (hostile_roster's band note) and that makes
// Open Sea the zone the table is authored at (zone_tier's 1/2/3 against
// FIGHT_OPPONENT_POWER_PERCENT_PER_TIER's 50). If a scaling at 100 moved a single
// magnitude, the entries would mean something other than what they say.
@(test)
a_hundred_percent_power_leaves_an_archetype_exactly_as_authored :: proc(t: ^testing.T) {
	for archetype in run_hostile_roster() {
		scaled := hostile_at_power(archetype, 100)
		defer delete(scaled.layout)

		layout := ship.ship_template_layout()
		defer delete(layout)
		for name in archetype.items {
			item, _ := ship.ship_item_by_name(name)
			testing.expect(t, ship.ship_fit_first_empty_slot(layout, item.fitting))
		}
		testing.expect(t, ship.ship_fill_empty_slots_with_cargo(layout, "Spoils"))

		unscaled := ship.Ship{layout = layout, speed = ship.BASE_SPEED}
		testing.expectf(
			t,
			loadout_signature(scaled) == loadout_signature(unscaled),
			"%v is not itself at 100%% power",
			archetype.name,
		)
		testing.expectf(
			t,
			hostile_output(&scaled) == hostile_output(&unscaled),
			"%v deals %d at 100%% power but was authored to deal %d",
			archetype.name,
			hostile_output(&scaled),
			hostile_output(&unscaled),
		)
	}
}

// **The forward-ported #135 straddle** (ADR-0020, #176/#177): with Speed derived
// from weight, the roster must still **straddle the player** — at least one hostile
// slower (so Leave Combat is a real option) and at least one faster (so a hostile can
// flee first). #135 asserted this against the old flat FIGHT_OPPONENT_SPEED; it is
// re-derived here now that a hostile's Speed falls out of its loadout plus its
// flat-50% hold (#194).
//
// **The player's purse is pinned explicitly** at STARTING_CARGO + CAPTAIN_STARTING_CARGO
// (#176's hard requirement): the comparison reads the player's *derived* Speed at the
// starting purse — never inferring 4 from STARTING_SPEED — because after the model
// lands the player's Speed is whatever their purse says (9 broke … 0 full), so
// "straddle" is a joint property of (roster, purse) and only a pinned purse makes it
// well-formed. ship_starting_ship stows exactly that sum, so it *is* the pin.
//
// It is a **point, not a window** (#177): leaving the window as you get rich is the
// feature, so this asserts one side each and no more. Placement (centre the starting
// purse, room to grow) is a playtest aim, not an asserted bound. At the starting purse
// the straddle rests on the **Ironclad Hulk alone** (1 slower / 6 faster) — the heavy
// entry most sensitive to the authored item weights (content.odin's band).
@(test)
the_hostile_roster_straddles_the_player_at_the_starting_purse :: proc(t: ^testing.T) {
	// Pin the player's purse explicitly: ship_starting_ship stows STARTING_CARGO +
	// the captain's CAPTAIN_STARTING_CARGO, so this reads the derived Speed at exactly
	// the pinned purse rather than the STARTING_SPEED constant.
	player := ship.ship_starting_ship()
	defer delete(player.layout)
	player_speed := ship.ship_effective_speed(&player)

	slower, faster := 0, 0
	distinct_speeds: map[int]bool
	defer delete(distinct_speeds)
	for archetype in run_hostile_roster() {
		hostile := test_hostile(archetype, Scaling_Site{zone = .Coastal, depth = 0})
		defer delete(hostile.layout)
		hostile_speed := ship.ship_effective_speed(&hostile)
		distinct_speeds[hostile_speed] = true
		switch {
		case hostile_speed < player_speed:
			slower += 1
		case hostile_speed > player_speed:
			faster += 1
		}
	}

	// The straddle: a hostile a starting player can outrun, and one that outruns them.
	testing.expectf(t, slower >= 1, "no hostile is slower than the player's %d — Leave Combat is a dead option", player_speed)
	testing.expectf(t, faster >= 1, "no hostile is faster than the player's %d — nothing can flee first", player_speed)
	// And a genuine spread, not one flat number: what a hostile carries moves its Speed.
	testing.expect(t, len(distinct_speeds) > 1)
}

// **The weight-floor invariant on the hostile side** (ADR-0020, #175): `base −
// weight/10 >= 0` for every hostile at its maximum reachable fill. A hostile's
// reachable fill is the flat 50% every spare slot is stowed to (HOSTILE_FILL_PERCENT,
// #176) — its actual in-game state — so this builds each archetype the way
// run_pve_opponent does and asserts its derived Speed never reads below 0. The
// invariant is a **test, never a live clamp** (#175): the model is authored so
// nothing reads below 0 rather than max(0, …) hiding a negative.
//
// **This is the tripwire for the out-of-scope hostile-template work** (#176). At the
// current flat-50% fill the heaviest hull (Ironclad Hulk, ~149) reads 2, well clear
// of 0. But #158's *fully-laden* fittings+capacity band is 159–179, which sits astride
// the 160 weight budget (BASE_SPEED 16 × the /10 divisor) — so any future template
// that pushes a hostile's fill toward 100% drives the heavy entries negative, and this
// assert is what catches it. Fully-laden is not reachable today; it is the boundary the
// template work must respect.
@(test)
every_hostile_reads_a_nonnegative_speed_at_its_reachable_fill :: proc(t: ^testing.T) {
	for archetype in run_hostile_roster() {
		hostile := test_hostile(archetype, Scaling_Site{zone = .Coastal, depth = 0})
		defer delete(hostile.layout)
		speed := ship.ship_effective_speed(&hostile)
		testing.expectf(t, speed >= 0, "%v derives a negative Speed (%d) at its 50%% fill — the weight floor is breached", archetype.name, speed)
	}
}

// **The roster's authoring rule, made checkable**: an archetype is character, stakes
// is power, so every build must be a real fight for a *starting* ship at Coastal —
// the state the player is actually in when they meet their first hostile, and (since
// the draw reads no zone) any archetype can be that first hostile.
//
// Both failure directions are one-line mistakes in the table: damage is
// `raw - (effective_durability + defense_bonus)`, so a few points of stacked
// +Durability makes a hostile undentable, and overshooting the other way one-shots
// the player. This test is what keeps the eight entries inside the band.
//
// **The floor is BASELINE_ROUND_COUNT, and #151 made that a real number rather than
// a hopeful one.** It used to be 4 — *below* the escape gate — and it was never
// reached anyway: every archetype died in 2-3 rounds, so `combat_may_leave` never
// returned true and Leave Combat, which ADR-0006 calls "the primary tool for
// avoiding a run-ending mistake", was unreachable in every Coastal fight in the
// game. A fight that ends before the gate is not a fight the captain gets to play;
// it is a coin flip that resolves itself. So the bound is the gate itself, by
// reference and not by literal: both ships must still be afloat when escape unlocks.
@(test)
a_starting_player_can_fight_every_archetype_at_coastal :: proc(t: ^testing.T) {
	// A fight that runs this long has stopped being one.
	ROUND_CAP :: 30
	// The intended fight length: long enough that Leave Combat comes off the bench.
	MIN_PLAYER_ROUNDS :: combat.BASELINE_ROUND_COUNT

	for archetype in run_hostile_roster() {
		player := ship.ship_starting_ship()
		defer delete(player.layout)
		hostile := test_hostile(archetype, Scaling_Site{zone = .Coastal, depth = 0})
		defer delete(hostile.layout)

		battle := combat.combat_battle_create(&player, &hostile)
		events: [dynamic]combat.Event
		defer delete(events)

		// Both sides Hold: this is about the damage band the loadouts produce, not
		// about escape, so the fight is fought out rather than scripted.
		hold := [combat.Side]Maybe(combat.Command) {
			.A = combat.Command(combat.Command_Hold{}),
			.B = combat.Command(combat.Command_Hold{}),
		}
		for !battle.ended && battle.round < ROUND_CAP {
			combat.combat_resolve_round(&battle, hold, &events)
			if player.hull <= 0 {
				testing.expectf(
					t,
					battle.round >= MIN_PLAYER_ROUNDS,
					"%v sinks a starting ship in %d round(s) at Coastal — the archetype is carrying stakes' job",
					archetype.name,
					battle.round,
				)
			}
		}

		// Not a wall: the player's damage got through at all.
		testing.expectf(
			t,
			hostile.hull < hostile.max_hull,
			"a starting player cannot scratch %v at Coastal (durability %d) — see the both-walls note on hostile_roster",
			archetype.name,
			ship.ship_effective_durability(&hostile),
		)
		// And the fight actually ends, rather than grinding on the damage floor.
		testing.expectf(t, battle.ended, "%v and a starting player cannot finish a fight at Coastal", archetype.name)
		// The other wall, and the one #151 added: a fight must last long enough for
		// the captain to have played it. Ending before the escape gate means Leave
		// Combat was never on the menu, so the hostile resolved itself.
		testing.expectf(
			t,
			battle.round >= MIN_PLAYER_ROUNDS,
			"%v and a starting player finish at Coastal in %d round(s), before the escape gate at %d — Leave Combat never comes off the bench",
			archetype.name,
			battle.round,
			MIN_PLAYER_ROUNDS,
		)
	}
}

// **The band's floor** (#165) — the wall a way *down* creates, and the one the test
// above cannot see.
//
// a_starting_player_can_fight_every_archetype_at_coastal bounds the ceiling: it
// checks the player can scratch the hostile, and that the fight lasts past the escape
// gate. Nothing checked the converse, because until #165 nothing could fail it —
// every archetype out-damaged a starting ship at Coastal, which was the complaint.
// A multiplicative site factor makes the opposite failure reachable for the first
// time: damage is `max(0, raw - soak)`, a starting ship soaks 4, and an entry
// authored to deal 8 keeps 4 of it at Coastal — so the fight is a ten-round grind in
// which the hostile lands *nothing*. That is the same dead node #151 found at the
// ceiling, arrived at from underneath.
//
// This is what forced the roster's re-authoring rather than a taste call: six of the
// eight entries failed it on the day the factor landed (see hostile_roster's note).
// The bar is deliberately "the player is hurt at all" — not a margin — because the
// margin is a tuning question and this is a structural one. The failure it names is
// **zero**, and zero is not a number the playtest should have to discover.
@(test)
a_starting_player_takes_real_damage_from_every_archetype_at_coastal :: proc(t: ^testing.T) {
	ROUND_CAP :: 30

	for archetype in run_hostile_roster() {
		player := ship.ship_starting_ship()
		defer delete(player.layout)
		hostile := test_hostile(archetype, Scaling_Site{zone = .Coastal, depth = 0})
		defer delete(hostile.layout)

		battle := combat.combat_battle_create(&player, &hostile)
		events: [dynamic]combat.Event
		defer delete(events)
		hold := [combat.Side]Maybe(combat.Command) {
			.A = combat.Command(combat.Command_Hold{}),
			.B = combat.Command(combat.Command_Hold{}),
		}
		for !battle.ended && battle.round < ROUND_CAP {
			combat.combat_resolve_round(&battle, hold, &events)
		}

		testing.expectf(
			t,
			player.hull < player.max_hull,
			"%v cannot scratch a starting player at Coastal — half of its authored output is under a starting ship's soak, so the fight has no risk in it",
			archetype.name,
		)
	}
}

// **The Selector question, answered as a test** (#151). Admiral's Guard is +3 per
// Crew aboard, so on a four-Crew build it reads +12 — and the pre-#151 fold put all
// twelve into the build's own `defense_bonus`, against a starting player's raw of 8.
// That is not a hard fight, it is arithmetic: the player's damage is `max(0, ...)`,
// so it was exactly zero, for every round, forever. A whole family of ADR-0012's
// roster — every `Selector`-based item, which is most of what the roster is *for* —
// could not sit on a hostile at any magnitude.
//
// It can now, and the reason is structural rather than tuned: a Selector buff is
// output, and output is the side of the ledger that can absorb a 12. The build is a
// hard hitter instead of an invincible one, which is a *magnitude* problem (tunable
// by the entry, the site, or the item) rather than a *category* one. So this test
// asserts the property that changed — the player's damage gets through a stacked
// Selector buff — and not a number.
@(test)
a_selector_buff_can_sit_on_a_hostile_without_walling_the_player :: proc(t: ^testing.T) {
	// Four Crew aboard: Admiral's Guard itself, Naval Gun Crew, Boarding Pikes and
	// Deckhands are all Crew-tagged, so the Guard reads its own maximum.
	guard := [?]string{"Naval Gun Crew", "Admiral's Guard", "Boarding Pikes", "Deckhands"}

	player := ship.ship_starting_ship()
	defer delete(player.layout)
	hostile := test_hostile({name = "Admiral's Guard build", items = guard[:]}, Scaling_Site{zone = .Coastal, depth = 0})
	defer delete(hostile.layout)

	battle := combat.combat_battle_create(&player, &hostile)
	events: [dynamic]combat.Event
	defer delete(events)
	hold := [combat.Side]Maybe(combat.Command) {
		.A = combat.Command(combat.Command_Hold{}),
		.B = combat.Command(combat.Command_Hold{}),
	}
	combat.combat_resolve_round(&battle, hold, &events)

	testing.expectf(
		t,
		hostile.hull < hostile.max_hull,
		"a starting player cannot scratch a four-Crew Admiral's Guard build — the buff is soaking again, and every Selector item is barred from half the game",
	)
}

// loadout_signature names the build a Ship is carrying, in slot order — enough to
// tell two archetypes apart (and to tell the same one drawn twice is the same one)
// without an archetype name riding along on the built Ship.
loadout_signature :: proc(s: ship.Ship) -> string {
	signature: strings.Builder
	strings.builder_init(&signature, context.temp_allocator)
	for layout_slot in s.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting {
			continue
		}
		strings.write_string(&signature, fitting.name)
		strings.write_byte(&signature, '|')
	}
	return strings.to_string(signature)
}

// phase_magnitude totals the authored magnitudes of a ship's fittings in one combat
// phase. Read off the fittings rather than through combat_phase_output so it needs
// no Battle — a synergy resolves against the ship alone here, which is all these
// tests compare.
phase_magnitude :: proc(s: ship.Ship, phase: ship.Category) -> int {
	total := 0
	for layout_slot in s.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting || fitting.category != phase {
			continue
		}
		if active, ok := fitting.active.?; ok {
			total += int(active.magnitude)
		}
	}
	return total
}

@(test)
run_map_create_wires_the_hand_authored_pve_opponent_content_into_fight_stages :: proc(t: ^testing.T) {
	m := run_map_create(0)
	defer run_map_destroy(&m)

	found_a_fight := false
	for node in m.nodes {
		encounter, has_encounter := node.encounter.?
		if !has_encounter {
			continue
		}
		fight, is_fight := only_stage(encounter, Stage_Fight)
		if !is_fight {
			continue
		}
		found_a_fight = true
		testing.expect_value(t, len(fight.opponent.layout), 8)
	}
	testing.expect(t, found_a_fight)
}

@(test)
run_item_offer_options_presents_distinct_roster_items :: proc(t: ^testing.T) {
	state := rand.create(0)
	gen := rand.default_random_generator(&state)
	options := run_item_offer_options(Scaling_Site{zone = .Coastal, depth = 0}, gen)

	// Every offered option is a distinct roster item (no repeats), and each is a
	// real fitting the player could place — not a cargo filler.
	testing.expect_value(t, len(options), ITEM_OFFER_OPTION_COUNT)
	for a, i in options {
		testing.expect(t, !a.is_cargo)
		testing.expect(t, len(a.name) > 0)
		for b, j in options {
			if i != j {
				testing.expect(t, a.name != b.name)
			}
		}
	}
}

@(test)
run_item_offer_options_scale_up_with_a_deeper_node :: proc(t: ^testing.T) {
	// A deeper node's quality bonus lifts the offered items' magnitudes. Drawing
	// both offers from the same seed makes them sample the same items in the same
	// order, so the only difference is the zone/depth scaling.
	low_state := rand.create(7)
	high_state := rand.create(7)
	low := run_item_offer_options(Scaling_Site{zone = .Coastal, depth = 0}, rand.default_random_generator(&low_state))
	high := run_item_offer_options(Scaling_Site{zone = .Deep, depth = 3}, rand.default_random_generator(&high_state))

	found_scaled := false
	for i in 0 ..< ITEM_OFFER_OPTION_COUNT {
		testing.expect_value(t, low[i].name, high[i].name) // same items, same order
		if effect_strength(high[i]) > effect_strength(low[i]) {
			found_scaled = true
		}
	}
	testing.expect(t, found_scaled)
}

// --- Trade roster (issue #136) ----------------------------------------------

// The point of the ticket: the trade axis is no longer one welded point. If the
// roster only ever yields one distinct bargain, nothing was unwelded.
@(test)
run_make_trade_draws_more_than_one_distinct_axis_across_seeds :: proc(t: ^testing.T) {
	seen: map[string]bool
	defer delete(seen)

	for seed in u64(0) ..< 50 {
		state := rand.create(seed)
		trade := run_make_trade(.Open_Sea, rand.default_random_generator(&state))
		seen[trade.name] = true
	}

	testing.expect(t, len(seen) > 1)
}

// Baked at generation off the map generator's RNG, so the same seed must yield
// the same bargain — the no-runtime-RNG property (ADR-0013) applies to a Trade's
// content like every other stage's.
@(test)
run_make_trade_is_reproducible_per_seed :: proc(t: ^testing.T) {
	a_state := rand.create(11)
	b_state := rand.create(11)
	a := run_make_trade(.Deep, rand.default_random_generator(&a_state))
	b := run_make_trade(.Deep, rand.default_random_generator(&b_state))

	testing.expect_value(t, a, b)
}

// Both sides read the same zone, so stakes move the whole trade — not just the
// half that used to own a constant.
@(test)
run_make_trade_scales_both_sides_with_the_zone :: proc(t: ^testing.T) {
	shallow_state := rand.create(3)
	deep_state := rand.create(3)
	shallow := run_make_trade(.Coastal, rand.default_random_generator(&shallow_state))
	deep := run_make_trade(.Deep, rand.default_random_generator(&deep_state))

	testing.expect_value(t, shallow.name, deep.name) // same seed, same axis drawn
	testing.expect(t, deep.gain.amount > shallow.gain.amount)
	testing.expect(t, deep.cost.amount > shallow.cost.amount)
}

// A baked trade's magnitudes are exactly its two stats' swings in that zone —
// the roster entry contributes the stats, the zone contributes the numbers.
@(test)
run_make_trade_reads_each_side_as_that_stats_swing :: proc(t: ^testing.T) {
	state := rand.create(5)
	trade := run_make_trade(.Open_Sea, rand.default_random_generator(&state))

	testing.expect_value(t, trade.gain.amount, run_trade_swing(.Open_Sea, trade.gain.stat))
	testing.expect_value(t, trade.cost.amount, run_trade_swing(.Open_Sea, trade.cost.stat))
}

// Every entry is a real swap: a trade that gains and costs the same stat is a
// no-op dressed as a decision.
@(test)
every_trade_roster_entry_swaps_two_different_stats_and_is_named :: proc(t: ^testing.T) {
	for axis in run_trade_roster() {
		testing.expect(t, len(axis.name) > 0)
		testing.expectf(t, axis.gain != axis.cost, "%v gains and costs the same stat", axis.name)
	}
}

// The roster's coverage after the #180 cut (content.odin): Speed left the Trade
// vocabulary, dropping the roster to three rows, so coverage is deliberately
// partial. Hull is gain-only (nothing else heals), Durability is now cost-only (it
// lost its gainer when Braced Bulkheads left), and Max Hull / Treasure sit on both
// sides. This pins that exact shape so a re-widening of the roster is a conscious
// edit here rather than a silent drift.
@(test)
the_trade_roster_covers_the_stats_the_surviving_three_rows_can :: proc(t: ^testing.T) {
	gained: bit_set[Trade_Stat]
	cost: bit_set[Trade_Stat]
	for axis in run_trade_roster() {
		gained += {axis.gain}
		cost += {axis.cost}
	}

	testing.expect_value(t, gained, bit_set[Trade_Stat]{.Hull, .Max_Hull, .Treasure})
	testing.expect_value(t, cost, bit_set[Trade_Stat]{.Max_Hull, .Durability, .Treasure})
}

// baked_trade is a roster axis priced at a zone — exactly what run_make_trade
// builds once the draw has picked the axis, without the draw. It lets the
// takeability tests below ask about a *named* entry rather than whichever one a
// seed happened to deal.
baked_trade :: proc(axis: Trade_Axis, zone: Zone) -> Stage_Trade {
	return trade_of(axis.gain, run_trade_swing(zone, axis.gain), axis.cost, run_trade_swing(zone, axis.cost))
}

// #146's headline: **an entry no ship can pay for is authored content the player
// cannot reach.** Two of the six were exactly that before the retune — Stripped
// Spars and Scrapped Armour cost 8 Durability at Coastal against a hull that has
// 2, so a Bargain node's only answer was reject, in a run that traverses ~3-4
// nodes per zone.
//
// Asserted against a **bare starting ship**, which is the strongest form of the
// claim and the honest one for these two zones: a Bargain is a 1-stage recipe, so
// Coastal deals it to a captain who has bought nothing yet. If this is too strict
// it is the swing table that is wrong, not the test.
@(test)
every_trade_roster_entry_is_takeable_by_a_starting_ship_outside_the_deep :: proc(t: ^testing.T) {
	for axis in run_trade_roster() {
		for zone in ([]Zone{.Coastal, .Open_Sea}) {
			s := ship.ship_starting_ship()
			defer delete(s.layout)

			testing.expectf(
				t,
				run_trade_can_accept(&s, baked_trade(axis, zone)),
				"%v is a dead node in %v: a starting ship cannot pay %v of %v",
				axis.name,
				zone,
				run_trade_swing(zone, axis.cost),
				axis.cost,
			)
		}
	}
}

// The residue of the retune, pinned rather than papered over (#146). A Deep
// Durability swing is 3 against a bare hull's 2, so the two Durability-costing
// entries ask for one bought point of armour before The Deep will take them — one
// Iron Plating, 10 treasure, the cheapest item in the game, against four
// guaranteed Ports and a zone of Rewards behind you.
//
// That is content rather than a dead node: you cannot strip armour you never
// bought, and Scrapped Armour's whole proposition is selling the armour you have.
// It is also the last of the starting-Durability-of-2 problem — the stat's range
// is set by combat's single-digit band (#135), which is #151's to widen, not this
// table's. **If #151 raises the base, this test should fail**, and the right
// response is to delete it: it exists to say that the gap is one plating wide and
// known, not that it should stay.
@(test)
the_deep_asks_one_point_of_armour_before_it_will_buy_a_ships_armour :: proc(t: ^testing.T) {
	for axis in run_trade_roster() {
		if axis.cost != .Durability {
			continue
		}

		bare := ship.ship_starting_ship()
		defer delete(bare.layout)
		testing.expectf(
			t,
			!run_trade_can_accept(&bare, baked_trade(axis, .Deep)),
			"%v is takeable in The Deep by a bare hull — the residue this test documents is gone, so delete it",
			axis.name,
		)

		plated := ship.ship_starting_ship()
		defer delete(plated.layout)
		plated.durability += 1 // what one Iron Plating buys

		testing.expectf(
			t,
			run_trade_can_accept(&plated, baked_trade(axis, .Deep)),
			"%v needs more than a single plating in The Deep",
			axis.name,
		)
	}
}

// effect_strength reads the magnitude of whichever effect a roster item carries,
// so a test can assert the quality scaling lifted it without caring which slot
// (passive/active) the item's one effect sits in.
effect_strength :: proc(f: ship.Fitting) -> int {
	if active, ok := f.active.?; ok {
		return int(active.magnitude)
	}
	if passive, ok := f.passive.?; ok {
		return int(passive.magnitude)
	}
	return 0
}
