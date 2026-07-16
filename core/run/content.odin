package run

import "../ship"
import "core:math/rand"

// Hostile_Archetype is one authored entry in the Fight primitive's content roster
// (issue #135, ADR-0014's "Fight gains a hostile roster"): a named hostile build,
// the items it carries, and how fast it sails. It carries no HP, no Durability and
// no magnitudes — those are the node's stakes — so an archetype is authored purely
// as *what kind of ship this is*, and the site decides how much of it there is.
//
// This is the type that retires the one-opponent template. Every battle in the
// game used to be the same ship — Captain's Quarters, Top Crew, an Upgraded Gun
// Deck, Spoils in the rest — with bigger numbers the deeper you went. There was no
// hostile roster, there was a hostile *template*. An archetype is now a roster row,
// and the hostiles in the game are that table.
//
// `items` names roster items by their authored name (ship_item_by_name) rather
// than restating their magnitudes: a hostile is built out of the *same* ~50 items
// the player can be offered (ADR-0012), so the two halves of the game cannot drift
// apart, and an item's tags/synergies/conditions work aboard a hostile exactly as
// they do aboard the player. Names are checked by test, not by the compiler — see
// every_hostile_archetype_is_built_from_real_roster_items.
//
// **Order is authoring.** Items are placed first-empty-fit (ship_fit_first_empty_slot)
// and the template lists its slots exposed-first within each size, so an item's
// position in this list decides whether it ends up on deck or in the hold — which
// in turn decides whether a Condition_Self_Visibility or Selector(Visibility.Concealed)
// effect fires. Smuggler's Run authors two throwaway Mediums ahead of its Wraith
// Cannon for exactly this reason.
Hostile_Archetype :: struct {
	name: string,
	// speed is the archetype's base Speed — the one Fight stat the stakes group
	// explicitly disowns ("Speed is not a stakes reading", run.odin), and so the
	// one it is free to claim. It replaces the flat FIGHT_OPPONENT_SPEED, which
	// pinned every hostile in the game at 5 against a starting player's 4.
	//
	// That flat 5 was quietly load-bearing, and wrong in both directions: it meant
	// *every* hostile was escape-eligible at BASELINE_ROUND_COUNT and so bolted
	// (combat_scripted_command), while the player — slower than everything — could
	// never take Leave Combat at all, and the roster's Condition_Opponent_Slower
	// items (Storm Sails) could never fire. Spreading speed across the roster is
	// what makes all three live: a Hulk at 2 is a hostile you may walk away from, a
	// Reef Skimmer at 6 is one that will leave *you*.
	speed: int,
	items: []string,
}

// The backing arrays for each archetype's item list. Package-level for the same
// reason catalog.odin's stage arrays are: an archetype is static authored data
// reused by every node that draws it, so its item list must not be per-node
// memory. @(rodata) — unlike recipe_catalog these are constant initializers.
@(rodata)
COASTAL_PRIVATEER_ITEMS := [?]string{"Long Nines", "Carronade", "Swivel Guns", "Boarding Nets"}

// Three guns as of #151 — the build the name always promised. Swivel Guns is the
// third; see the entry's own note for why the roster's smallest gun is the one that
// fits.
@(rodata)
BROADSIDE_COMPANY_ITEMS := [?]string{"Naval Gun Crew", "Swivel Guns", "Powder Monkeys", "Boarding Pikes"}

@(rodata)
DEEPWATER_MENAGERIE_ITEMS := [?]string{"Hunter's Pack", "Snapping Eels", "War Hound"}

@(rodata)
SMUGGLERS_RUN_ITEMS := [?]string{"Copper Sheathing", "Iron Plating", "Wraith Cannon", "Spare Rigging", "Ghost Lantern"}

@(rodata)
IRONCLAD_HULK_ITEMS := [?]string{"Long Nines", "Ramming Prow", "Reinforced Hull", "Ballast Stones"}

@(rodata)
BOARDING_PARTY_ITEMS := [?]string{"Naval Gun Crew", "Admiral's Guard", "Boarding Pikes"}

@(rodata)
DEATH_THROES_ITEMS := [?]string{"Deck Cannon", "Kraken Spawn", "War Hound"}

@(rodata)
REEF_SKIMMER_ITEMS := [?]string{"Deck Cannon", "Carronade", "Copper Sheathing", "Swivel Guns", "Spare Rigging"}

// hostile_roster is every hostile in the game, in the same authored-table shape as
// trade_roster above and catalog.odin's recipe_catalog. Not @(rodata) despite never
// being written: taking a slice of the backing arrays above is not a constant
// initializer, so the entries fill at program init (the same reason recipe_catalog
// isn't).
//
// **Size — eight.** A run traverses only ~3-4 nodes per zone (~11-14 of 50), so
// this is sized like trade_roster (six) but deliberately larger, for two reasons.
// Fight is the primitive that appears in the *most* recipes — it is [Fight] today
// and the spine of [Fight, Reward], this effort's headline recipe (#138) — so a run
// meets more Fights than Trades, and six would repeat inside a single zone. And a
// hostile is the most-*looked-at* content in the game: you stare at its layout for a
// whole battle, where a Trade is one line you read and answer. The bar for "I have
// seen this before" is far lower, so the roster has to be wider to clear it. Eight
// is also the smallest size that puts one build behind each of the roster's effect
// themes below; fewer would leave whole item families with no hostile that uses them.
//
// **Coverage.** One build per idea, spanning what ADR-0012's items can actually do:
// plain flat guns (Coastal Privateer), a Tag synergy (Broadside Company on Weapon,
// Deepwater Menagerie on Beast), concealment — both the condition and the placement
// trick (Smuggler's Run), stat-modifier armour (Ironclad Hulk), a Crew build
// (Boarding Party), HP-threshold conditionals (Death Throes), and speed
// stat-modifiers (Reef Skimmer).
//
// **The authoring rule: an archetype is character, stakes is power** — and as of
// #165 (ADR-0019) the table has a **weight**: an entry is authored at **Open Sea**,
// the zone where run_fight_opponent_power reads 100%. A captain meets an entry as it
// is written here in the middle zone, at half of it in the Coastal shallows, and at
// half again on top in The Deep. Entries stay authored to a *comparable* band — the
// Fight analogue of trade_roster's "every axis is one swing for one swing" — because
// an archetype is drawn with no regard to zone, so any build can turn up anywhere and
// a build three times another would let the draw swamp the gradient. No entry is the
// "Deep" one: depth is the site's job.
//
// **The band has two walls and the *floor* is the new one** (#165). Damage is
// `raw - (effective_durability + defense_bonus)`, so the old wall still stands —
// stacked +Durability makes a hostile hard to dent, and overshooting sinks a starting
// player before the escape gate. But `max(0, ...)` has a floor as well as a ceiling,
// and a factor that scales *down* is what walks the roster into it: a starting ship
// soaks **4**, so an entry authored to deal less than ~10 arrives at Coastal, keeps
// half of it, and **cannot scratch the player at all** — a fight with no risk in it,
// which is the same dead node #151 found at the other wall. Both are enforced by
// test, not by eye: a_starting_player_can_fight_every_archetype_at_coastal bounds the
// ceiling, and a_starting_player_takes_real_damage_from_every_archetype_at_coastal
// bounds the floor.
//
// **That floor is why the whole table was re-authored up** with #165, and it is the
// change's honest cost as well as its point. Every entry here was originally written
// to be survivable by a *starting ship at Coastal* — that was the only test — so the
// table was authored at **Coastal weight** while the model now reads it as Open Sea
// weight, and halving an already-Coastal entry put six of the eight under the soak
// floor. Re-authoring is not decoration: a multiplier needs headroom above soak
// before it has anywhere to scale down *to*.
//
// **The payoff is that the ceiling moved, so builds that were too heavy now fit.**
// #135 could not author a `Selector` buff onto a hostile at all (Admiral's Guard read
// +12 *defence* and made the fight arithmetically unwinnable); #151 fixed the
// category — buff feeds Offensive only, so a Selector is a hard hitter rather than an
// invulnerable one — but left the magnitude too heavy for a Coastal starting ship,
// which is why Boarding Party was still carrying flat War Drums. With a way down,
// +9 of Guard is +4 at Coastal and +15 in The Deep. **Boarding Party finally carries
// the item two tickets have documented it wanting**, and the constraint that barred
// it has gone from a category (#135) to a magnitude (#151) to a zone (#165).
//
// Magnitudes ride on the items, so the numbers here are ADR-0012's placeholders and
// move with them; the map's "stakes constant tuning per primitive" fog owns the rest.
hostile_roster := [?]Hostile_Archetype {
	// The retired template's honest successor: guns, no tricks, no synergy to read.
	// First so the roster opens on something recognisable, and so there is a
	// baseline the other seven are variations *from*. Speed 4 ties the player's, so
	// neither side can leave — this is the one that has to be fought out.
	//
	// Long Nines joins with #165, into the Large slot the entry had been leaving to
	// Spoils. There is no cleverness to report: this is the plainest demonstration of
	// what the way down bought, since "a privateer carries a big gun" needed no
	// argument and was simply unaffordable while an entry had to survive contact with
	// a starting ship undiminished.
	{name = "Coastal Privateer", speed = 4, items = COASTAL_PRIVATEER_ITEMS[:]},
	// Every gun aboard makes the crew's guns hit harder: Powder Monkeys buff per
	// Weapon, and every other item is a Weapon (Boarding Pikes and Naval Gun Crew are
	// multi-tag Crew+Weapon, so they pay into it while reading as boarders).
	//
	// **Three guns as of #151, and it is this entry that measures the widened band.**
	// The third gun was unauthorable before: it took the build to a two-round kill,
	// so the roster's headline weapon-synergy archetype carried two guns and could not
	// state its own concept. It fits now because the fold left `defense_bonus` — a
	// starting ship's soak stopped being ~90% of its raw — and because a Coastal
	// hostile's HP is no longer half the player's, so the fight lasts long enough to
	// be one. Swivel Guns rather than a Carronade: the roster's *smallest* gun is
	// what the band holds with margin (a starting player wins at 28 of 100 HP against
	// this, against 10 of 100 with a Carronade), and the synergy is what makes it
	// worth carrying — a third Weapon is worth its own 3 *plus* a point on every
	// Powder Monkeys reading, which is the entry's whole argument.
	{name = "Broadside Company", speed = 4, items = BROADSIDE_COMPANY_ITEMS[:]},
	// Beasts, and Hunter's Pack paying per Beast aboard. **Three of them as of #165**,
	// which is the third Beast the entry's own note had been asking for: the synergy is
	// quadratic in its own family, so War Hound is +3 to the Pack *and* a whole extra
	// gun — the reason it was unaffordable before, and the reason it is worth having
	// now. It is also the entry that most needed the multiplier rather than a bigger
	// bonus: a Selector build is exactly what an additive share mis-scaled (see
	// run_fit_hostile_loadout). War Hound's own magnitude is gated below half HP, so
	// the Pack's count rises immediately and the Hound's gun only joins once the
	// Menagerie is dying. Slow and laden: at 3 it is the archetype a starting player
	// can outrun, which is what makes Leave Combat a real option rather than a menu
	// item nothing satisfies.
	{name = "Deepwater Menagerie", speed = 3, items = DEEPWATER_MENAGERIE_ITEMS[:]},
	// Runs dark and runs fast. The trick is placement: two throwaway Mediums push the
	// Wraith Cannon into the concealed hold, where its Condition_Self_Visibility fires
	// — the archetype whose build only works because of the *order* of its item list.
	// Spare Rigging keeps it at an effective 8, so it bolts the round
	// BASELINE_ROUND_COUNT unlocks, which is the archetype's whole character (kill it
	// quickly or it is gone) and is what #151's widened band made observable: before,
	// the fight ended at round 2 and nothing ever reached the gate to bolt at.
	//
	// **It takes its Ghost Lantern with #165**, which the entry has been asking for
	// across two tickets: #135 could not have it because buff was soak and the Lantern
	// would have made the hostile undentable; #151 killed that reason and said so here
	// ("the entry is worth revisiting"), but a +4 buff on top of a Wraith Cannon was
	// still too much ship to meet at Coastal undiminished. Every Small slot on the
	// template is concealed, so the Lantern's Condition_Self_Visibility fires for the
	// same reason the Cannon's does — the entry now states its theme twice with one
	// mechanism, which is what it was for.
	{name = "Smuggler's Run", speed = 5, items = SMUGGLERS_RUN_ITEMS[:]},
	// Armour: the build that spends on Modify_Durability, so it is a wall you chip
	// rather than one you burst. Held to +3 total — see the both-walls note above.
	// At 2 it is the slowest thing afloat and the easiest to walk away from.
	//
	// **It is a ram as of #165, and that is the floor wall in one entry.** Armour was
	// its whole budget, which left it dealing 8 — and half of 8 is a starting ship's
	// soak exactly, so a Coastal Hulk was a ten-round grind that could not land a
	// single point of damage. An archetype whose character is *not hitting you* is the
	// one a scale-down walks into the floor first. Ramming Prow answers it in
	// character rather than by bolting a gun on: a ram is what an ironclad is *for*,
	// it takes the Large slot the entry was leaving to Spoils, and it leaves the
	// armour untouched — so the wall now hits back instead of being scenery.
	{name = "Ironclad Hulk", speed = 2, items = IRONCLAD_HULK_ITEMS[:]},
	// Crew — **and the entry that finally carries Admiral's Guard** (+3 per Crew
	// aboard, three Crew here, so +9). It is the roster's longest-running argument,
	// settled: #135 authored flat War Drums instead because buff folded into defence
	// and +9 of Guard was an unwinnable fight rather than a hard one; #151 removed
	// that fold and made the bar a *magnitude* rather than a category, but a starting
	// ship still met the full +9 at Coastal; #165's way down makes it +4 there and +15
	// in The Deep. Three tickets, and each one moved the obstacle down a level —
	// category, then magnitude, then zone. This is the archetype the whole
	// Selector half of ADR-0012's roster was waiting on.
	{name = "Boarding Party", speed = 4, items = BOARDING_PARTY_ITEMS[:]},
	// Wakes up when it is dying: two of its three guns are gated on its own HP below
	// half, so it opens with a single Deck Cannon and turns savage exactly when the
	// player thinks it is won. The roster's argument that a conditional is a *shape*,
	// not a discount.
	{name = "Death Throes", speed = 3, items = DEATH_THROES_ITEMS[:]},
	// Two Modify_Speed items on top of a base 6 — an effective 9, so it is gone the
	// round it becomes eligible. The counterpart to the Hulk: the archetype that
	// leaves *you*, and the second one #165 found sitting on the floor, for the mirror
	// reason — its budget went into speed rather than armour, but it was equally not
	// spent on hitting you, so half of its 7 could not clear a starting ship's soak
	// either. It is a nuisance by design, and a nuisance that deals nothing at all for
	// the five rounds before it bolts is not a nuisance, it is a cutscene. The
	// Carronade is what makes leaving cost the player something.
	//
	// The two Modify_Speed items are also this entry's second job: they are why
	// the_site_never_moves_a_hostiles_speed exists. Both are filed under Category
	// `.Buff` — a category the site now scales — so this is the build that would break
	// loudest if ship_fitting_output_scaled ever started touching passives.
	{name = "Reef Skimmer", speed = 6, items = REEF_SKIMMER_ITEMS[:]},
}

// run_hostile_roster returns every authored hostile archetype. run_pve_opponent
// deals from this rather than building one hardcoded loadout, so the set of
// hostiles in the game is this table and nothing else — the Fight half of the same
// authored-content rule catalog.odin states for recipes and trade_roster for trades.
run_hostile_roster :: proc() -> []Hostile_Archetype {
	return hostile_roster[:]
}

// run_make_opponent_ship computes a Ship Battle opponent's stakes-scaled stats (hp,
// durability) from the node's Scaling_Site — the numeric half of a PvE opponent
// (issue #23). run_pve_opponent layers an archetype's loadout and speed on top of
// these; this proc has no layout/captain/speed of its own and is not itself a
// complete opponent.
//
// Speed left this proc with issue #135: hp and durability are the site's readings,
// but speed is the archetype's (see Hostile_Archetype.speed), so a stats-from-site
// helper has nothing to say about it.
run_make_opponent_ship :: proc(site: Scaling_Site) -> ship.Ship {
	hp := run_fight_opponent_hp(site)
	return ship.Ship{
		hp         = hp,
		max_hp     = hp,
		durability = run_fight_opponent_durability(site),
	}
}

// run_stakes_scales_category reports whether the site's power reading scales a
// fitting of this Category — the whole of the rule, which is: **stakes scales what a
// hostile deals, never what it soaks.**
//
// #135 wrote that rule as "only Offensive fittings take it", and its stated reason
// was that a bonus on Buff or Defensive would inflate `defense_bonus` and make a
// deep hostile harder to *hurt* rather than harder to fight. **Half of that reason
// died with #151** (ADR-0017) and the rule outlived it: Buff no longer feeds
// `defense_bonus` at all — `raw_damage = boosted(Offensive) + boosted(Buff)` — so a
// scaled Buff fitting now makes a hostile hit harder, which is exactly what stakes
// is for. Only the Defensive half of the reason survives, and it survives intact:
// soak is subtracted from raw, so a site that scaled it would eventually make a
// hostile impossible to hurt at any magnitude.
//
// Under the old additive bonus this was a rounding error — a flat +2..+9 that Buff
// happened not to collect. Under a multiplier it is the defect itself: a hostile's
// unscaled Buff would be a **floor the site cannot lower**, so Boarding Party's War
// Drums (3) and Broadside Company's Powder Monkeys would stand at full strength in
// the Coastal shallows while the guns beside them halved — the same "the floor is
// whatever was authored" complaint this ticket exists to answer, just smaller.
//
// Note this is the *category* half of the rule only. Category is a combat phase, and
// `.Buff` also holds every Modify_Speed item in the roster; it is
// ship_fitting_output_scaled that declines to touch those, and the reason it must is
// on that proc.
run_stakes_scales_category :: proc(category: ship.Category) -> bool {
	switch category {
	case .Offensive, .Buff:
		return true // raw_damage = Offensive + Buff (core/combat, ADR-0017)
	case .Defensive:
		return false // soak, and soak's vocabulary has to stay small
	}
	return false
}

// run_fit_hostile_loadout fits an archetype's authored items into the one ship
// template (ADR-0004), each scaled to this site's power reading, and hands the
// leftovers to ship_fill_empty_slots_with_cargo (issue #91: the opponent's spare
// slots fill with "Spoils" the way the player's fill with "Cargo"). An or_return
// chain like core/ship's ship_fit_starting_loadout — a false return means the
// archetype and the template have drifted out of sync (it asks for more Larges than
// the template has), a content bug this package's own tests catch, not a runtime
// condition.
//
// **`power_percent` is a factor applied per fitting, and the per-fitting part is
// free** — which is the whole of what #165 bought. #135 could not apply its bonus
// per fitting, because an *additive* bonus lets gun count multiply the site's
// reading: a three-gun build would collect three times a one-gun build's uplift, so
// which archetype you drew would move a hostile's power more than how deep you were
// — the gradient swamped by the draw. It therefore shared **one total** across the
// guns (run_offense_share, now deleted), and paid for that with the machinery.
//
// A multiplier is **scale-invariant**, so the dilemma dissolves rather than moving:
// three guns at 50% is the same proportion as one gun at 50%, and the count cannot
// swamp anything it no longer touches.
//
// **And the shared total did not achieve its own goal anyway** — #165 measured it.
// A share lands on an *authored magnitude*, upstream of effect_magnitude's synergy
// seam, so a Selector multiplies the share by its match count: Deepwater Menagerie's
// Hunter's Pack (+3 per Beast, two Beasts aboard) turned the site's Deep reading of
// 9 into **14 points of output** where every flat build got 9, and Death Throes —
// whose guns are gated on its own HP — banked 3 of it until it was dying. The site's
// reading was worth 56% more to a synergy build than to a flat one, and #135's
// `the_stakes_uplift_is_the_same_total_for_every_archetype` could not see it because
// it sums authored magnitudes rather than resolving output. So the independence
// property this machinery existed to protect was **already broken by exactly the
// mechanism it was protecting against**, one level down: not count-of-guns, but
// count-of-Beasts. The multiplier is the first shape that actually holds it, and
// holds it through a selector for the same structural reason.
run_fit_hostile_loadout :: proc(layout: []ship.Layout_Slot, archetype: Hostile_Archetype, power_percent: int) -> bool {
	for name in archetype.items {
		item, found := ship.ship_item_by_name(name)
		assert(found, "hostile archetype names an item that is not in the roster")

		fitting := item.fitting
		if run_stakes_scales_category(fitting.category) {
			fitting = ship.ship_fitting_output_scaled(fitting, power_percent)
		}
		ship.ship_fit_first_empty_slot(layout, fitting) or_return
	}
	return ship.ship_fill_empty_slots_with_cargo(layout, "Spoils")
}

// run_pve_opponent builds a full Ship Battle opponent by drawing one archetype from
// the hostile roster (#135) and baking it at this node's stakes: the archetype
// supplies the loadout and speed, the site supplies hp, durability, and the
// offensive bonus. Draws off the map generator's RNG (`gen`) — so *which* hostile a
// node holds is reproducible per seed yet varies node to node, exactly like an
// Offer's items, a Shop's deck and a Trade's axis — and is called from
// run_bake_stage at generation time. Nothing rolls on arrival (ADR-0013).
//
// The draw reads no zone: archetype and stakes are independent axes, so a Deep node
// gets a *tougher* hostile, not a different pool of them. Whether some archetypes
// should be zone-gated after all is the catalog's own eligibility question (the
// map's "per-zone eligibility beyond stage count" fog), not this draw's.
//
// Carries no captain — a captain is a player-side, run-start choice (CONTEXT.md),
// not opponent content. Caller owns the returned Ship's layout slice; run_map_destroy
// frees it per Fight stage.
run_pve_opponent :: proc(site: Scaling_Site, gen: rand.Generator) -> ship.Ship {
	roster := run_hostile_roster()
	archetype := roster[rand.int_max(len(roster), gen)]

	s := run_make_opponent_ship(site)
	// A hostile's Speed falls out of its weight like every other ship's now
	// (ADR-0020, #176/#180): its base is the uniform BASE_SPEED, and its loadout
	// plus its cargo fill decide what it actually reads (ship_effective_speed).
	// archetype.speed is vestigial pending the item-weight authoring pass (#143
	// fog), which re-derives the roster's Speed spread from authored weights and a
	// flat-50% hold and forward-ports #135's straddle test — it is no longer read.
	s.speed = ship.BASE_SPEED

	layout := ship.ship_template_layout()
	assert(
		run_fit_hostile_loadout(layout, archetype, run_fight_opponent_power(site)),
		"hostile archetype loadout: a fitting failed to fit the ship template",
	)

	s.layout = layout
	return s
}

// OFFER_ITEM_QUALITY_DIVISOR converts a node's Offer quality reading
// (run_offer_item_quality) into a flat magnitude bonus added to each offered
// item (issue #96): a smaller, more legible number than raw quality while still
// scaling with it — the same knob the old Upgrade Offer applied to its three
// fixed variants, now spread across the roster items on offer. Not a stakes
// constant — it converts a reading rather than scaling by tier/depth — so it
// stays here with its consumer rather than joining the scaling group.
OFFER_ITEM_QUALITY_DIVISOR :: 5

// run_item_offer_options picks the distinct roster items an Offer stage presents
// (issue #96, ADR-0012): it samples ITEM_OFFER_OPTION_COUNT distinct items from
// ship_item_roster — shuffling the pool's indices with the map generator's RNG
// (`gen`) so an offer's items are reproducible per seed yet vary node to node —
// and scales each by this node's stakes. Baked at generation time
// (run_bake_stage), so the offer carries its items as content, like a Fight
// carries its opponent. Retires run_upgrade_offer_options' fixed three-upgrade
// menu.
run_item_offer_options :: proc(site: Scaling_Site, gen: rand.Generator) -> [ITEM_OFFER_OPTION_COUNT]ship.Fitting {
	bonus := run_offer_item_quality(site) / OFFER_ITEM_QUALITY_DIVISOR
	roster := ship.ship_item_roster()
	indices := run_shuffled_roster_indices(gen)

	options: [ITEM_OFFER_OPTION_COUNT]ship.Fitting
	for i in 0 ..< ITEM_OFFER_OPTION_COUNT {
		// The offer places the item; tier's power is already baked into the
		// item's magnitudes, so it reads only the fitting (a shop, #98, reads the
		// tier for cost). The item is scaled by this node's zone/depth quality.
		options[i] = ship.ship_fitting_scaled(roster[indices[i]].fitting, bonus)
	}
	return options
}

// run_shuffled_roster_indices returns the roster's indices
// (0..<ship.ITEM_ROSTER_SIZE) in a per-seed-reproducible shuffled order — the
// front half of sampling N distinct roster items for the Offer stage
// (run_item_offer_options), which takes the first ITEM_OFFER_OPTION_COUNT.
//
// The Shop stage used to share this (issue #98, when both sampled the whole
// roster) and no longer does: a shop draws from its **stock pool**, not the
// roster (issue #137), so it shuffles that pool's candidate subset instead
// (run_bake_shop). The two samplers have deliberately diverged — an Offer's pool
// *is* the roster because an offer is what the sea happens to wash up, while a
// shop is a business that chose what to carry.
run_shuffled_roster_indices :: proc(gen: rand.Generator) -> [ship.ITEM_ROSTER_SIZE]int {
	indices: [ship.ITEM_ROSTER_SIZE]int
	for i in 0 ..< ship.ITEM_ROSTER_SIZE {
		indices[i] = i
	}
	rand.shuffle(indices[:], gen)
	return indices
}

// Trade_Axis is one authored entry in the Trade primitive's content roster
// (issue #136): a named bargain, and the two stats it swaps. It carries no
// magnitudes — those are each stat's swing at the node's site (run_trade_swing),
// so an axis is authored purely as "what for what" and the site decides how big.
//
// This is the type that unwelds Stage_Trade's +Durability/-Speed: the axis used
// to *be* the struct's two field names, so every trade in the game was one point
// in the space CONTEXT.md described. An axis is now a roster row, and the space
// is the roster.
Trade_Axis :: struct {
	name: string,
	gain: Trade_Stat,
	cost: Trade_Stat,
}

// trade_roster is every trade in the game, in the same authored-table shape as
// catalog.odin's recipe_catalog and generation.odin's tuning knobs. @(rodata):
// unlike recipe_catalog these entries are constant initializers (no slices of
// other arrays), so the table can live in read-only memory.
//
// **Size — three, for now (ADR-0020, #180).** The roster was six until Speed left
// the Trade vocabulary: Speed is a derived read-out of weight now, not a stored
// stat a Trade can pay out of or bank into, so the three Speed-touching rows
// (Braced Bulkheads, Stripped Spars, Lightened Hold) are removed. Speed returns
// later as *fittings* that modify it, traded as fittings. The remaining three are
// accepted as a deliberately thin roster in the meantime — a run meets only a
// handful of trades, so a run is still mostly non-repeating.
//
// **Coverage — thinner now, and consciously so.** HP is gain-only (Cannibalized
// Timbers), Max HP and Treasure sit on both sides, and **Durability is cost-only**
// (Scrapped Armour) — it lost its one gainer when Braced Bulkheads left with Speed.
// HP stays gain-only on purpose: nothing else in the game heals (combat is the only
// writer of Ship.hp, and it only ever subtracts), so repair is the scarcest thing a
// trade can offer, and a trade that damages you is a Fight without the fight. That
// Durability is no longer gainable is the accepted cost of the #180 cut; a
// Durability-gaining row returns whenever the roster is re-widened.
// Names are checked against core/ship's fitting roster and deliberately don't
// collide with it: a Trade is not a thing you install, and "Reinforced Hull"
// already names a Medium Defensive fitting the player can be holding while a
// trade is on screen.
@(rodata)
trade_roster := [?]Trade_Axis {
	// Patch the damage you have by permanently lowering the ceiling. The one
	// entry that trades HP against Max HP, which is why both are distinct stats.
	{name = "Cannibalized Timbers", gain = .HP, cost = .Max_HP},
	{name = "Scrapped Armour", gain = .Treasure, cost = .Durability},
	{name = "Shipwright's Bargain", gain = .Max_HP, cost = .Treasure},
}

// run_trade_roster returns every authored trade axis. run_make_trade deals from
// this rather than reading a hardcoded pair off Stage_Trade's fields, so the set
// of trades in the game is this table and nothing else — the Trade half of the
// same authored-content rule catalog.odin states for recipes.
run_trade_roster :: proc() -> []Trade_Axis {
	return trade_roster[:]
}

// run_make_trade bakes a Trade stage (issue #136): it draws one axis from the
// roster off the map generator's RNG — so which bargain a node offers is
// reproducible per seed yet varies node to node, like an Offer's items and a
// Shop's deck — and reads each side's magnitude as that stat's swing in this
// node's zone. Called from run_bake_stage at generation time; nothing rolls on
// arrival.
//
// Both terms read the *same* zone, so stakes move the whole trade together: a
// Deep Braced Bulkheads gains more Durability and costs more Speed than a Coastal
// one, rather than scaling only the half that used to have a constant.
//
// It takes a Zone rather than the node's full Scaling_Site because a swing is
// zone-scaled and nothing else (#146: an exchange rate has no room for a second
// axis — see TRADE_SWING_* in run.odin). So a Trade is the one primitive that
// reads *part* of its node's stakes; the Shop arm beside it in run_bake_stage
// reads none.
run_make_trade :: proc(zone: Zone, gen: rand.Generator) -> Stage_Trade {
	roster := run_trade_roster()
	axis := roster[rand.int_max(len(roster), gen)]

	return Stage_Trade{
		name = axis.name,
		gain = Trade_Term{stat = axis.gain, amount = run_trade_swing(zone, axis.gain)},
		cost = Trade_Term{stat = axis.cost, amount = run_trade_swing(zone, axis.cost)},
	}
}

// Stock_Pool names one authored entry in the Shop primitive's content roster
// (issue #137): what kind of business this shop is. It is the Shop analogue of
// Hostile_Archetype and Trade_Axis — the content that stops every shop in the game
// from being the same shop — with one decisive difference: **an archetype and an
// axis are drawn, a stock pool is named by the recipe** (Stage_Spec.stock).
//
// That difference is the whole of what makes a Port and a merchant vessel stock
// differently, and it is deliberate. A Fight draws its archetype with no regard to
// where it is because archetype and stakes are independent axes (#135) — any build
// may turn up anywhere. A Shop cannot work that way, because the two things
// carrying Shop stages are not interchangeable:
//
//   - A **Port** is *guaranteed*: the Port bucket places exactly PORTS_PER_ZONE of
//     them in every zone (generation.odin), so every run has six, and routing to one
//     is a plan the map always honours. That promise is only worth making if a Port
//     is a dependable general market — a Port that could roll a six-card specialist
//     hold would make "go and restock" a gamble, which is the one thing the bespoke
//     placement exists to prevent.
//   - A **merchant vessel** is a *windfall*: it competes for slots in its zone's
//     stage-count bucket, so it may not appear at all. A windfall can afford to be
//     narrow and strange, because nothing is planned around it.
//
// Drawing the pool freely would make which-shop-is-this a per-node accident and
// leave that asymmetry inexpressible. Naming it on the recipe is what lets "Port"
// mean *the general store* and a merchant vessel mean *a hold full of one thing*.
Stock_Pool :: enum {
	Chandlery,
	Ordnance_Hoy,
	Press_Gang,
	Menagerie,
	Curiosity_Dealer,
}

// Stock is what one Stock_Pool is made of: the two things a shop's stock varies by
// (issue #137 asked which of pool subset / size / tier weighting / price "stocking
// differently" means, and this type is the answer — **subset and size**).
//
// **Subset, via `families`** — the shop's character. The Tag families are the
// roster's own authored family axis (ADR-0012), and they are what reads as a kind
// of business: a hold of Weapons is an ordnance hoy, a hold of Beasts is a
// menagerie. Filtering on Tag rather than Category (Buff/Defensive/Offensive) is
// deliberate: Category is a *combat phase*, so a "Defensive shop" describes when its
// wares fire, not what they are, and no chandler ever sorted a warehouse that way.
//
// **Size, via `depth`** — how many cards deep the hold is, and the only reason a
// shop can be exhausted. With the shelf window at SHOP_SHELF_SIZE, a visit reaches
// `depth` cards at most, so this is what separates a Port you cannot empty from a
// merchant you can (see the table below).
//
// **Not tier weighting, and not price.** Tier weighting is the stakes question, and
// Shop deliberately reads no stakes at all (run.odin's scaling group says why: the
// gradient a shop faces is the purse the captain brings). Price is economy tuning,
// which this map rules out of scope — and a per-pool discount would collide with
// #124's depth surcharge, the one price knob that already exists.
//
// `families` is a **Maybe**, and nil means *no filter* rather than *every family*.
// A chandlery is defined by not being choosy, so it must keep stocking a sixth Tag
// the day one is authored, without this table being edited to remember it. It also
// keeps the whole-roster case from quietly depending on every roster item carrying
// a tag (they all do today — see every_roster_item_carries_a_tag_family — but that
// is the Offer's business, not a fact a chandlery should rest on).
Stock :: struct {
	name:     string,
	families: Maybe(bit_set[ship.Tag]),
	depth:    int,
}

// stock_pools is every shop in the game, in the same authored-table shape as
// hostile_roster, trade_roster, and catalog.odin's recipe_catalog. @(rodata): like
// trade_roster these entries are constant initializers, so the table can live in
// read-only memory.
//
// **Only Chandlery is reachable today.** The Port recipe names it (catalog.odin) and
// no other recipe carries a Shop, so the four specialist holds below are authored
// content waiting on the recipes that will name them — issue #138, which owns the
// catalog. This is the same split #135 made: it authored eight hostile archetypes
// while the catalog still held a single [Fight]. Authoring a merchant-vessel recipe
// here instead would deal it into a zone's stage-count bucket and reshape every
// seed's map, which is #138's call to make and not this ticket's.
//
// **Depth is authored per pool, and it is the whole difference in feel.** What matters
// is not the number itself but the **reserve** it leaves behind the shelf — depth minus
// SHOP_SHELF_SIZE — because that is what a purchase draws on. A visit sees the shelf
// and refills a bought slot from the reserve; when the reserve is gone, buying starts
// leaving bare slots and the shop visibly shrinks.
//
//   - Chandlery's 12 leaves a reserve of **7**. The starting purse of 50 buys about
//     three cards even at the cheapest tier (10, then #124's surcharge makes it 15, 20),
//     so the shelf is still full when the money runs out — the captain gives up before
//     the shop does. It is not infinite: buying all 12 out at the cheapest tier costs
//     10+15+…+65 = 450, nine times what a run starts with, so emptying a Port means
//     arriving with a fortune and spending the lot on trinkets.
//   - A specialist's 6 leaves a reserve of **1**. The *second* purchase of a visit
//     already bares a slot. That is the difference, and it lands within the two or
//     three buys a real visit makes rather than at some theoretical exhaustion — which
//     is exactly what a single ship's hold should feel like next to a town's warehouse.
//
// Both are pinned by test (a_chandlerys_reserve_outlasts_the_purse_a_captain_brings,
// a_narrow_hold_shrinks_as_it_is_bought_and_can_be_emptied), because the interesting
// quantity is a difference of two constants against a third and no one will notice by
// eye when the surcharge moves.
@(rodata)
stock_pools := [Stock_Pool]Stock {
	// The Port's pool, and the only one a recipe names today. No filter at all: a
	// chandlery is the general store, which is the promise the Port bucket's
	// guaranteed placement is making.
	.Chandlery = {name = "Chandlery", families = nil, depth = 12},
	// Guns. The largest specialist pool (15 Weapon items) and the most obvious
	// merchant: a powder hoy running ordnance between ports.
	.Ordnance_Hoy = {name = "Ordnance Hoy", families = bit_set[ship.Tag]{.Weapon}, depth = 6},
	// Hands. Crew is the family the roster's biggest synergy trap sits in
	// (Admiral's Guard, +3 per Crew aboard — see hostile_roster), so a hold that
	// sells nothing but Crew is the one shop that can build that trap on purpose.
	.Press_Gang = {name = "Press Gang", families = bit_set[ship.Tag]{.Crew}, depth = 6},
	// Beasts. The smallest candidate family (10), so its 6 is over half the pool —
	// two menageries in one run would visibly repeat, which is the honest cost of a
	// narrow family and a reason #138 may want it rare.
	.Menagerie = {name = "Menagerie", families = bit_set[ship.Tag]{.Beast}, depth = 6},
	// Oddities. Artifact is the family with no unifying mechanic — it is the
	// roster's "everything else" — so this is the specialist whose stock is
	// unpredictable in kind rather than uniform.
	.Curiosity_Dealer = {name = "Curiosity Dealer", families = bit_set[ship.Tag]{.Artifact}, depth = 6},
}

// run_stock_pool returns one pool's authored stock. The Shop half of the same
// authored-content rule catalog.odin states for recipes and trade_roster for trades:
// the shops in the game are this table and nothing else.
run_stock_pool :: proc(pool: Stock_Pool) -> Stock {
	return stock_pools[pool]
}

// run_stock_candidates returns the roster indices a pool is allowed to stock, in
// roster order, and how many there are — the filter half of run_bake_shop, split out
// so the pool table can be checked against the roster by test without baking a shop.
//
// An unfiltered pool (families = nil) yields the whole roster in order, untouched.
// That is not just a convenience: it is what keeps a Chandlery's shuffle identical to
// the pre-#137 whole-roster deck's, so Ports generate exactly the stock they always
// did and the seed-pinned maps do not move.
//
// A filtered pool keeps an item if it carries **any** of the pool's families — a
// multi-tag item (Naval Gun Crew is Crew+Weapon) is stocked by both an Ordnance Hoy
// and a Press Gang, the same way selector_matches counts it under each of its tags
// (ADR-0012).
run_stock_candidates :: proc(stock: Stock) -> (indices: [ship.ITEM_ROSTER_SIZE]int, count: int) {
	roster := ship.ship_item_roster()
	families, filtered := stock.families.?
	for item, i in roster {
		if filtered && item.fitting.tags & families == {} {
			continue
		}
		indices[count] = i
		count += 1
	}
	return
}

// run_bake_shop bakes a Shop stage's stock from its authored pool (issue #137,
// superseding ADR-0013's whole-roster deck): the pool's candidates shuffled into a
// per-seed-reproducible order off the map generator's RNG — so stock varies node to
// node yet reproduces per seed, like an Offer's items and a Fight's archetype — cut
// off at the pool's authored depth, each card priced by its Tier
// (ship.ship_item_cost). Every card is distinct, being a sample of a permutation, so
// a shelf drawn off it never repeats an item within one visit.
//
// **It takes no Scaling_Site, and that is the point** — Shop is the one primitive
// that ignores its own node's stakes. An Offer scales its items' magnitudes by the
// site; a shop stocks them exactly as authored. ADR-0013 justified that by
// double-counting *tier* (cost already rises with tier, so a quality bonus on top
// would charge once and pay twice), and that still holds, but the stronger reason
// arrived with #133: **Reward's payout is site-scaled** (20/tier + 5/depth), so depth
// already means "more treasure". A shop that also improved with depth would compound
// the same progression from both ends — richer captain *and* better shelf. So the
// market is a fixed market, and the gradient a shop faces is the purse the captain
// brings to it. That is why this proc has no `site` parameter to ignore.
run_bake_shop :: proc(pool: Stock_Pool, gen: rand.Generator) -> Stage_Shop {
	stock := run_stock_pool(pool)
	roster := ship.ship_item_roster()

	candidates, n := run_stock_candidates(stock)
	rand.shuffle(candidates[:n], gen)

	shop := Stage_Shop{count = min(stock.depth, n)}
	for i in 0 ..< shop.count {
		item := roster[candidates[i]]
		shop.stock[i] = Shop_Item{fitting = item.fitting, cost = ship.ship_item_cost(item.tier)}
	}
	return shop
}
