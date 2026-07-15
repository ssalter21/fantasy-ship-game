package run

import "../testutil"
import "core:math/rand"
import "core:testing"

// --- The stage walk: complete-or-halt (ADR-0014) ----------------------------

// walk_fixture is a hand-built three-stage encounter, independent of the
// generator and of what any catalog recipe happens to author: the walk's
// semantics are what these assert, not the content.
walk_fixture :: proc() -> Encounter {
	return Encounter{stages = {Stage_Trade{}, Stage_Offer{}, Stage_Reward{}}, count = 3}
}

@(test)
a_completed_stage_advances_the_cursor_to_the_next_stage :: proc(t: ^testing.T) {
	e := walk_fixture()

	stage, ok := run_encounter_current(e)
	testing.expect(t, ok)
	testing.expect_value(t, run_stage_kind(stage), Stage_Kind.Trade)

	more := run_encounter_resolve_stage(&e, .Completed)

	testing.expect(t, more)
	stage, ok = run_encounter_current(e)
	testing.expect(t, ok)
	testing.expect_value(t, run_stage_kind(stage), Stage_Kind.Offer)
}

@(test)
completing_the_last_stage_finishes_the_walk :: proc(t: ^testing.T) {
	e := walk_fixture()

	testing.expect(t, run_encounter_resolve_stage(&e, .Completed))
	testing.expect(t, run_encounter_resolve_stage(&e, .Completed))
	// The third and last stage: completing it leaves nothing pending.
	testing.expect(t, !run_encounter_resolve_stage(&e, .Completed))

	testing.expect(t, run_encounter_is_finished(e))
	_, ok := run_encounter_current(e)
	testing.expect(t, !ok)
}

@(test)
a_halted_stage_ends_the_encounter_and_skips_every_later_stage :: proc(t: ^testing.T) {
	e := walk_fixture()

	// Halt on the very first stage: the Offer and Reward behind it never resolve.
	// This is what makes [Fight, Reward] mean "flee the blockade, forfeit the
	// loot" with no authored gate.
	more := run_encounter_resolve_stage(&e, .Halted)

	testing.expect(t, !more)
	testing.expect(t, run_encounter_is_finished(e))
	_, ok := run_encounter_current(e)
	testing.expect(t, !ok)
}

@(test)
a_halt_partway_through_keeps_the_stages_already_walked :: proc(t: ^testing.T) {
	e := walk_fixture()

	testing.expect(t, run_encounter_resolve_stage(&e, .Completed)) // Trade granted
	testing.expect(t, !run_encounter_resolve_stage(&e, .Halted)) // skipped the Offer

	// The cursor records that the walk got past the first stage before ending —
	// "keeping what earlier stages already granted" is the run state those stages
	// already mutated, and the walk never rewinds it.
	testing.expect(t, run_encounter_is_finished(e))
	testing.expect(t, e.cursor >= 1)
}

@(test)
resolving_a_stage_on_a_finished_encounter_asserts :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	e := Encounter{stages = {0 = Stage_Reward{}}, count = 1}
	run_encounter_resolve_stage(&e, .Completed)

	testing.expect_assert(t, "resolved a stage on an encounter whose walk already finished")
	run_encounter_resolve_stage(&e, .Completed)
}

// --- Stage-derived visibility ----------------------------------------------

@(test)
only_a_shop_stage_reveals_its_encounter :: proc(t: ^testing.T) {
	for kind in Stage_Kind {
		testing.expectf(
			t,
			run_stage_kind_reveals(kind) == (kind == .Shop),
			"%v: Shop is the only revealing primitive today",
			kind,
		)
	}
}

@(test)
an_encounter_reveals_iff_it_contains_a_shop_stage :: proc(t: ^testing.T) {
	hidden := Encounter{stages = {0 = Stage_Fight{}, 1 = Stage_Reward{}}, count = 2}
	testing.expect(t, !run_encounter_reveals(hidden))

	// A Port: the one-stage [Shop] recipe.
	port := Encounter{stages = {0 = Stage_Shop{}}, count = 1}
	testing.expect(t, run_encounter_reveals(port))

	// A merchant vessel: a Shop that isn't first, and isn't a Port. Visibility is
	// asked of the whole stage list, so this reveals too.
	merchant := Encounter{stages = {0 = Stage_Fight{}, 1 = Stage_Shop{}}, count = 2}
	testing.expect(t, run_encounter_reveals(merchant))
}

@(test)
a_stage_past_the_count_never_counts_toward_visibility :: proc(t: ^testing.T) {
	// count is the authored length; a Shop sitting in an unused slot is not part
	// of the encounter and must not reveal it.
	e := Encounter{stages = {0 = Stage_Fight{}, 1 = Stage_Shop{}}, count = 1}
	testing.expect(t, !run_encounter_reveals(e))
}

// --- Recipes and the catalog ------------------------------------------------

@(test)
every_catalog_recipe_fits_an_encounter_and_names_itself :: proc(t: ^testing.T) {
	catalog := run_recipe_catalog()
	testing.expect(t, len(catalog) > 0)

	for r in catalog {
		testing.expectf(t, len(r.name) > 0, "a catalog recipe is unnamed")
		testing.expectf(t, len(r.stages) > 0, "%s: a recipe must author at least one stage", r.name)
		testing.expectf(
			t,
			len(r.stages) <= ENCOUNTER_MAX_STAGES,
			"%s: %d stages exceeds the %d-stage cap an Encounter can hold",
			r.name,
			len(r.stages),
			ENCOUNTER_MAX_STAGES,
		)
	}
}

@(test)
a_recipes_bucket_is_derived_from_its_stage_count_not_authored :: proc(t: ^testing.T) {
	// The property under test is structural: a Recipe has no bucket field to
	// disagree with its stage list, so a recipe cannot be filed in the wrong
	// bucket. All that's left to assert is that the derivation is the stage count
	// itself — the key the per-zone bucket draw (#134) will group on.
	one := Recipe{name = "One", stages = SEA_BATTLE_STAGES[:]}
	testing.expect_value(t, len(one.stages), 1)

	two := Recipe{name = "Two", stages = []Stage_Kind{.Fight, .Reward}}
	testing.expect_value(t, len(two.stages), 2)
}

@(test)
run_encounter_from_recipe_bakes_every_authored_stage_in_order :: proc(t: ^testing.T) {
	state := rand.create(0)
	gen := rand.default_random_generator(&state)

	r := Recipe{name = "Blockade", stages = []Stage_Kind{.Fight, .Offer, .Reward}}
	e := run_encounter_from_recipe(r, Scaling_Site{zone = .Deep, depth = 1}, gen)
	defer for i in 0 ..< e.count {
		if fight, is_fight := e.stages[i].(Stage_Fight); is_fight {
			delete(fight.opponent.layout)
		}
	}

	testing.expect_value(t, e.count, 3)
	testing.expect_value(t, e.cursor, 0) // a fresh encounter starts on its first stage
	for kind, i in r.stages {
		testing.expectf(t, run_stage_kind(e.stages[i]) == kind, "stage %d: baked out of authored order", i)
	}

	// Baked content, not a bare number resolved later: the Fight carries a real
	// opponent and the Offer real items.
	fight, is_fight := e.stages[0].(Stage_Fight)
	testing.expect(t, is_fight)
	testing.expect(t, fight.opponent.hp > 0)
}

@(test)
a_bare_reward_recipe_bakes_its_payout_from_the_site :: proc(t: ^testing.T) {
	// Drifting salvage — free treasure — is a legal recipe, and that is a feature
	// (#133): a Reward has nothing to decline, so an encounter that is only a Reward is
	// coherent rather than an encounter with no interaction. Nothing authors it in the
	// catalog yet (#138 owns that, and adding an entry would reshape every seed's map),
	// so this pins that the model already builds and bakes one.
	state := rand.create(0)
	gen := rand.default_random_generator(&state)

	site := Scaling_Site{zone = .Open_Sea, depth = 2}
	r := Recipe{name = "Drifting Salvage", stages = []Stage_Kind{.Reward}}
	e := run_encounter_from_recipe(r, site, gen)

	testing.expect_value(t, e.count, 1)
	reward, is_reward := e.stages[0].(Stage_Reward)
	testing.expect(t, is_reward)

	// The payout is content baked at generation, and it is this node's own reading of
	// the gradient — no runtime roll decides it on arrival.
	testing.expect_value(t, reward.treasure, run_reward_treasure(site))
	testing.expect(t, reward.treasure > 0)
}

@(test)
run_encounter_from_recipe_bakes_stakes_scaled_content :: proc(t: ^testing.T) {
	// Each bake gets its own generator off the same seed, so both draw the same
	// axis from the trade roster (#136) and the site is the only difference
	// between them. Sharing one generator would advance it between the two calls
	// and compare two *different* bargains, whose magnitudes are quoted in
	// different stats and needn't be ordered at all.
	shallow_state := rand.create(0)
	deep_state := rand.create(0)

	r := Recipe{name = "Bargain", stages = BARGAIN_STAGES[:]}
	shallow := run_encounter_from_recipe(r, Scaling_Site{zone = .Coastal, depth = 0}, rand.default_random_generator(&shallow_state))
	deep := run_encounter_from_recipe(r, Scaling_Site{zone = .Deep, depth = DEPTH_STEPS}, rand.default_random_generator(&deep_state))

	// The same recipe at a higher-stakes site bakes a bigger swing — the recipe
	// authors the shape, the Scaling_Site the magnitude.
	st, _ := shallow.stages[0].(Stage_Trade)
	dt, _ := deep.stages[0].(Stage_Trade)
	testing.expect_value(t, dt.gain.stat, st.gain.stat)
	testing.expect(t, dt.gain.amount > st.gain.amount)
	testing.expect(t, dt.cost.amount > st.cost.amount)
}

@(test)
run_encounter_from_recipe_rejects_a_recipe_past_the_stage_cap :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	state := rand.create(0)
	gen := rand.default_random_generator(&state)
	r := Recipe{name = "Too Long", stages = []Stage_Kind{.Trade, .Trade, .Trade, .Trade}}

	testing.expect_assert(t, "a recipe authored more stages than an Encounter can hold")
	run_encounter_from_recipe(r, Scaling_Site{zone = .Coastal, depth = 0}, gen)
}

// --- The recipe bag ---------------------------------------------------------

@(test)
run_make_recipe_bag_deals_evenly_across_whatever_pool_it_is_given :: proc(t: ^testing.T) {
	state := rand.create(7)
	gen := rand.default_random_generator(&state)

	// Two pool sizes, to pin that the even split is over the pool rather than the
	// three-way division run_make_kind_bag hard-coded.
	pool2 := []Recipe{{name = "A", stages = SEA_BATTLE_STAGES[:]}, {name = "B", stages = BARGAIN_STAGES[:]}}
	for count in ([]int{0, 1, 2, 7, 15}) {
		bag := run_make_recipe_bag(count, pool2, gen)
		defer delete(bag)
		testing.expect_value(t, len(bag), count)

		counts: map[string]int
		defer delete(counts)
		for r in bag {
			counts[r.name] += 1
		}
		lo := min(counts["A"], counts["B"])
		hi := max(counts["A"], counts["B"])
		testing.expectf(t, hi - lo <= 1, "count %d: spread %d..%d not even over a 2-recipe pool", count, lo, hi)
	}
}

@(test)
run_make_recipe_bag_rejects_an_empty_pool :: proc(t: ^testing.T) {
	when testutil.SKIP_WINDOWS_ASSERT_BUG {
		return
	}

	state := rand.create(0)
	gen := rand.default_random_generator(&state)

	testing.expect_assert(t, "cannot deal a recipe bag from an empty pool")
	bag := run_make_recipe_bag(3, nil, gen)
	delete(bag)
}
