package voyage

import "../ship"
import "core:math/rand"

// Hostile_Archetype is one authored entry in the Fight roster (ADR-0014): a named
// hostile build — just the items it carries. No Hull, Durability, or Speed: the node's
// stakes supply hull and durability, and Speed derives from what the build weighs
// (ADR-0020). An archetype says *what kind of ship this is*; the site decides how much.
//
// `items` names roster items by their authored name (ship_item_by_name), so a hostile is
// built from the same items the player can be offered (ADR-0012) — tags, synergies, and
// conditions work aboard a hostile exactly as aboard the player. Names are checked by
// every_hostile_archetype_is_built_from_real_roster_items, not the compiler.
//
// Order is authoring: items are placed first-empty-fit (ship_fit_first_empty_slot) into a
// template whose slots are exposed-first within each size, so an item's position decides
// whether it lands on deck or in the concealed hold — which decides whether a
// Condition_Self_Visibility or Selector(Visibility.Concealed) effect fires. Smuggler's Run
// lists two throwaway Mediums ahead of its Wraith Cannon for exactly this reason.
Hostile_Archetype :: struct {
	name:  string,
	items: []string,
}

// Backing arrays for each archetype's item list — static authored data reused by every
// node that draws it, so it must not be per-node memory. @(rodata): these are constant
// initializers (unlike hostile_roster below, which slices them).
@(rodata)
COASTAL_PRIVATEER_ITEMS := [?]string{"Long Nines", "Carronade", "Swivel Guns", "Boarding Nets"}

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

// hostile_roster is every hostile in the game, authored in the same table shape as
// trade_roster and catalog.odin's recipe_catalog. Not @(rodata): slicing the backing
// arrays above is not a constant initializer, so the entries fill at program init.
//
// Eight entries, one behind each of the roster's effect themes: flat guns (Coastal
// Privateer), Tag synergy (Broadside Company, Deepwater Menagerie), concealment (Smuggler's
// Run), stat-modifier armour (Ironclad Hulk), Crew (Boarding Party), Hull-threshold
// conditionals (Death Throes), speed modifiers (Reef Skimmer). Larger than trade_roster
// (six) because Fight appears in the most recipes — a voyage meets more Fights than Trades —
// and a hostile is the most looked-at content in the game.
//
// An archetype is character, stakes is power. Entries are authored at Open Sea weight
// (ADR-0019): voyage_fight_opponent_power reads 100% in the middle zone, half in the Coastal
// shallows, half-again on top in The Deep. Because an archetype is drawn with no regard to
// zone, all entries stay in a comparable band — otherwise the draw would swamp the depth
// gradient. No entry is the "Deep" one; depth is the site's job.
//
// The band has two walls, both enforced by test rather than by eye. Ceiling: damage is
// `raw - (effective_durability + defense_bonus)`, so an overshooting hostile sinks a starting
// player before the escape gate (a_starting_player_can_fight_every_archetype_at_coastal).
// Floor: `max(0, …)` means an entry that deals too little arrives at Coastal, keeps half,
// and cannot scratch a starting ship's bulwark of 4 — a fight with no risk
// (a_starting_player_takes_real_damage_from_every_archetype_at_coastal).
//
// Magnitudes ride on the items, so the numbers here are ADR-0012's placeholders.
hostile_roster := [?]Hostile_Archetype {
	// The plain baseline: guns, no tricks, no synergy — the other seven are variations
	// from it, so it goes first. Its guns plus a half-full hold weigh enough to derive to
	// Speed 4 (ship_effective_speed), tying the player, so neither side can break off and
	// this fight has to be fought out.
	{name = "Coastal Privateer", items = COASTAL_PRIVATEER_ITEMS[:]},
	// Every gun aboard makes the crew's guns hit harder: Powder Monkeys muster per Weapon,
	// and every other item is a Weapon (Boarding Pikes and Naval Gun Crew are Crew+Weapon,
	// so they pay in while reading as boarders). Swivel Guns is the roster's smallest gun —
	// the third weapon the band holds with margin while still paying the synergy.
	{name = "Broadside Company", items = BROADSIDE_COMPANY_ITEMS[:]},
	// Beasts, with Hunter's Pack paying per Beast aboard — a synergy quadratic in its own
	// family. War Hound's own gun is gated below half Hull, so the Pack's count rises up
	// front and the Hound only fires once the Menagerie is dying. Three light beasts over
	// an 8-slot hull leave it half-full and nearly weightless, so it derives to Speed 7 —
	// the fastest ship in the game, an accepted cost of the flat-50%-hold placeholder
	// (issue #176). The "one a starting player can outrun" role is carried by the Ironclad
	// Hulk instead.
	{name = "Deepwater Menagerie", items = DEEPWATER_MENAGERIE_ITEMS[:]},
	// Runs dark and fast. Placement is the trick: two throwaway Mediums push the Wraith
	// Cannon and Ghost Lantern into the concealed hold, where their Condition_Self_Visibility
	// fires — the build that only works because of item order. Copper Sheathing and Spare
	// Rigging leave it deriving to Speed 8, so it bolts the round BASELINE_ROUND_COUNT
	// unlocks: kill it fast or it is gone.
	{name = "Smuggler's Run", items = SMUGGLERS_RUN_ITEMS[:]},
	// Armour: spends its budget on Modify_Durability, a wall you chip rather than burst
	// (held to +3 total — see the floor wall above). Two Larges of iron make it the
	// heaviest hull in the roster, so it derives to Speed 2 — the only hostile slower than
	// the player, the one a starting captain can walk away from. Ramming Prow gives the
	// wall a way to hit back, so an all-defence build still clears the damage floor.
	{name = "Ironclad Hulk", items = IRONCLAD_HULK_ITEMS[:]},
	// Crew, carrying Admiral's Guard (+3 per Crew aboard, three Crew here, so +9). A
	// Selector muster: it feeds Fire only (ADR-0017), so it is a hard hitter, not an
	// invulnerable one, and the site's way down makes it +4 at Coastal and +15 in The Deep.
	{name = "Boarding Party", items = BOARDING_PARTY_ITEMS[:]},
	// Wakes up dying: two of its three guns are gated on its own Hull below half, so it
	// opens with a single Deck Cannon and turns savage when the player thinks it is won. A
	// conditional as a shape, not a discount.
	{name = "Death Throes", items = DEATH_THROES_ITEMS[:]},
	// Two Modify_Speed items over a light, half-full hull derive to Speed 8, so it bolts
	// the round it becomes eligible — the counterpart to the Hulk, breaking off from you.
	// The Carronade makes breaking off cost the player something. Its Modify_Speed items
	// sit under Category .Muster, which the site scales, so this is the build that would
	// break loudest if ship_fitting_output_scaled ever touched passives
	// (the_site_never_moves_a_hostiles_speed).
	{name = "Reef Skimmer", items = REEF_SKIMMER_ITEMS[:]},
}

// voyage_hostile_roster returns every authored hostile archetype; voyage_pve_opponent
// deals from it, so the hostiles in the game are this table and nothing else.
voyage_hostile_roster :: proc() -> []Hostile_Archetype {
	return hostile_roster[:]
}

// voyage_make_opponent_ship computes a PvE opponent's stakes-scaled stats — hull and
// durability — from the node's Scaling_Site (issue #23). It sets the uniform BASE_SPEED
// base (ADR-0020); a hostile's actual Speed derives from what it carries
// (ship_effective_speed), so there is nothing site-specific to set here.
// voyage_pve_opponent layers the archetype's loadout on top; this ship has no layout or
// captain of its own and is not a complete opponent.
voyage_make_opponent_ship :: proc(site: Scaling_Site) -> ship.Ship {
	hull := voyage_fight_opponent_hull(site)
	return ship.Ship{
		hull         = hull,
		max_hull     = hull,
		durability = voyage_fight_opponent_durability(site),
		speed      = ship.BASE_SPEED,
	}
}

// voyage_stakes_scales_category reports whether the site's power reading scales a fitting
// of this Category. The rule: stakes scales what a hostile deals, never its bulwark.
// raw_damage = Fire + Muster (ADR-0017), so scaling those makes a deep hostile hit
// harder; Brace is excluded because bulwark is subtracted from raw — a site that scaled it
// would eventually make a hostile impossible to hurt at any magnitude.
//
// This is the *category* half of the rule. Category is a combat phase, and .Muster also
// holds every Modify_Speed item; ship_fitting_output_scaled is what declines to touch
// those, for the reason on that proc.
voyage_stakes_scales_category :: proc(category: ship.Category) -> bool {
	switch category {
	case .Fire, .Muster:
		return true // raw_damage = Fire + Muster (ADR-0017)
	case .Brace:
		return false // bulwark: subtracted from raw, never scaled
	}
	return false
}

// voyage_fit_hostile_loadout fits an archetype's items into the one ship template
// (ADR-0004), each scaled to the site's power reading, and fills the leftover slots with
// Spoils (issue #91, the opponent's analogue of the player's Cargo). The or_return chain
// mirrors ship_fit_starting_loadout: a false return means the archetype asks for more slots
// of a size than the template has — a content bug this package's tests catch, not a runtime
// condition.
//
// power_percent is a factor applied per fitting, so it is scale-invariant: three guns at
// 50% is the same proportion as one gun at 50%, and gun count cannot swamp the site's
// reading. A Selector scales with its match count, upstream of effect_magnitude's synergy
// seam — the multiplier holds through that for the same reason.
voyage_fit_hostile_loadout :: proc(layout: []ship.Layout_Slot, archetype: Hostile_Archetype, power_percent: int) -> bool {
	for name in archetype.items {
		item, found := ship.ship_item_by_name(name)
		assert(found, "hostile archetype names an item that is not in the roster")

		fitting := item.fitting
		if voyage_stakes_scales_category(fitting.category) {
			fitting = ship.ship_fitting_output_scaled(fitting, power_percent)
		}
		ship.ship_fit_first_empty_slot(layout, fitting) or_return
	}
	return ship.ship_fill_empty_slots_with_cargo(layout, "Spoils")
}

// voyage_pve_opponent builds a full Ship Battle opponent: it draws one archetype from the
// hostile roster (#135) and bakes it at the node's stakes — the archetype supplies the
// loadout (and, through its weight, its Speed), the site supplies hull, durability, and the
// fire bonus. Draws off the map generator's RNG, so which hostile a node holds is
// reproducible per seed yet varies node to node; called from voyage_bake_stage at
// generation time (ADR-0013: nothing rolls on arrival).
//
// The draw reads no zone — archetype and stakes are independent axes, so a Deep node gets a
// tougher hostile, not a different pool. Carries no captain (a captain is a player-side,
// run-start choice — CONTEXT.md). Caller owns the returned Ship's layout slice;
// voyage_map_destroy frees it per Fight stage.
voyage_pve_opponent :: proc(site: Scaling_Site, gen: rand.Generator) -> ship.Ship {
	roster := voyage_hostile_roster()
	archetype := roster[rand.int_max(len(roster), gen)]

	// BASE_SPEED base only; a hostile's actual Speed falls out of its weight like every
	// other ship's (ship_effective_speed).
	s := voyage_make_opponent_ship(site)

	layout := ship.ship_template_layout()
	assert(
		voyage_fit_hostile_loadout(layout, archetype, voyage_fight_opponent_power(site)),
		"hostile archetype loadout: a fitting failed to fit the ship template",
	)

	s.layout = layout
	return s
}

// OFFER_ITEM_QUALITY_DIVISOR converts a node's Offer quality reading
// (voyage_offer_item_quality) into a flat magnitude bonus added to each offered item (issue
// #96) — a smaller, more legible number than raw quality. Not a stakes constant (it converts
// a reading rather than scaling by tier/depth), so it stays with its consumer rather than
// joining the scaling group.
OFFER_ITEM_QUALITY_DIVISOR :: 5

// voyage_item_offer_options picks the distinct roster items an Offer stage presents (issue
// #96, ADR-0012): it samples ITEM_OFFER_OPTION_COUNT distinct items from ship_item_roster,
// shuffling the pool's indices with the map generator's RNG so an offer is reproducible per
// seed yet varies node to node, and scales each by this node's stakes. Baked at generation
// time (voyage_bake_stage), so the offer carries its items as content.
voyage_item_offer_options :: proc(site: Scaling_Site, gen: rand.Generator) -> [ITEM_OFFER_OPTION_COUNT]ship.Fitting {
	bonus := voyage_offer_item_quality(site) / OFFER_ITEM_QUALITY_DIVISOR
	roster := ship.ship_item_roster()
	indices := voyage_shuffled_roster_indices(gen)

	options: [ITEM_OFFER_OPTION_COUNT]ship.Fitting
	for i in 0 ..< ITEM_OFFER_OPTION_COUNT {
		// tier's power is already baked into the item's magnitudes, so the offer reads
		// only the fitting and scales it by this node's quality (a shop, #98, reads the
		// tier for cost instead).
		options[i] = ship.ship_fitting_scaled(roster[indices[i]].fitting, bonus)
	}
	return options
}

// voyage_shuffled_roster_indices returns the roster's indices (0..<ship.ITEM_ROSTER_SIZE)
// in a per-seed-reproducible shuffled order — the front half of sampling N distinct roster
// items for the Offer stage (voyage_item_offer_options takes the first
// ITEM_OFFER_OPTION_COUNT). Offer-only: a Shop draws from its own stock pool
// (voyage_bake_shop), not the whole roster — an Offer's pool is what the sea washes up,
// while a shop is a business that chose what to carry.
voyage_shuffled_roster_indices :: proc(gen: rand.Generator) -> [ship.ITEM_ROSTER_SIZE]int {
	indices: [ship.ITEM_ROSTER_SIZE]int
	for i in 0 ..< ship.ITEM_ROSTER_SIZE {
		indices[i] = i
	}
	rand.shuffle(indices[:], gen)
	return indices
}

// Trade_Axis is one authored entry in the Trade roster (issue #136): a named bargain and
// the two stats it swaps. It carries no magnitudes — those are each stat's swing at the
// node's site (voyage_trade_swing) — so an axis is authored purely as "what for what" and
// the site decides how big.
Trade_Axis :: struct {
	name: string,
	gain: Trade_Stat,
	cost: Trade_Stat,
}

// trade_roster is every trade in the game, authored in the same table shape as
// catalog.odin's recipe_catalog. @(rodata): unlike hostile_roster these are constant
// initializers (no slices of other arrays), so the table lives in read-only memory.
//
// A deliberately thin roster of three (ADR-0020): Speed is a derived read-out of weight,
// not a stored stat a Trade can pay out of, so the Speed-touching rows are gone until Speed
// returns as tradeable fittings. Hull is gain-only (Cannibalized Timbers), Max Hull and
// Cargo sit on both sides, Durability is cost-only (Scrapped Armour). Hull stays gain-only
// on purpose: nothing else in the game heals (combat is the only writer of Ship.hull, and
// it only ever subtracts), so repair is the scarcest thing a trade can offer, and a trade
// that damages you is a Fight without the fight. Names are checked against core/ship's
// roster and deliberately don't collide with it — a Trade is not a thing you install.
@(rodata)
trade_roster := [?]Trade_Axis {
	// Patch the damage you have by permanently lowering the ceiling — the one entry that
	// trades Hull against Max Hull, which is why they are distinct stats.
	{name = "Cannibalized Timbers", gain = .Hull, cost = .Max_Hull},
	{name = "Scrapped Armour", gain = .Cargo, cost = .Durability},
	{name = "Shipwright's Bargain", gain = .Max_Hull, cost = .Cargo},
}

// voyage_trade_roster returns every authored trade axis; voyage_make_trade deals from it,
// so the trades in the game are this table and nothing else.
voyage_trade_roster :: proc() -> []Trade_Axis {
	return trade_roster[:]
}

// voyage_make_trade bakes a Trade stage (issue #136): it draws one axis off the map
// generator's RNG — reproducible per seed, varying node to node — and reads each side's
// magnitude as that stat's swing in this node's zone. Called from voyage_bake_stage at
// generation time. Both terms read the same zone, so stakes move the whole trade together.
//
// It takes a Zone rather than the node's full Scaling_Site because a swing is zone-scaled
// and nothing else (#146: an exchange rate has no room for a second axis — see TRADE_SWING_*
// in voyage.odin). So Trade is the one primitive that reads *part* of its node's stakes,
// where the Shop beside it in voyage_bake_stage reads none.
voyage_make_trade :: proc(zone: Zone, gen: rand.Generator) -> Stage_Trade {
	roster := voyage_trade_roster()
	axis := roster[rand.int_max(len(roster), gen)]

	return Stage_Trade{
		name = axis.name,
		gain = Trade_Term{stat = axis.gain, amount = voyage_trade_swing(zone, axis.gain)},
		cost = Trade_Term{stat = axis.cost, amount = voyage_trade_swing(zone, axis.cost)},
	}
}

// Stock_Pool is one authored entry in the Shop roster (issue #137): what kind of business
// this shop is. The Shop analogue of Hostile_Archetype and Trade_Axis, with one decisive
// difference: an archetype and an axis are *drawn*, a stock pool is *named by the recipe*
// (Stage_Spec.stock).
//
// A Fight draws its archetype with no regard to zone because archetype and stakes are
// independent axes (#135). A Shop cannot, because the two things carrying Shop stages are
// not interchangeable: a Port is *guaranteed* (the Port bucket places PORTS_PER_ZONE per
// zone), so it must be a dependable general market; a merchant vessel is a *windfall* that
// competes for a stage-count slot, so it can afford to be narrow and strange. Naming the
// pool on the recipe is what lets "Port" mean the general store and a merchant mean a hold
// full of one thing.
Stock_Pool :: enum {
	Chandlery,
	Ordnance_Hoy,
	Press_Gang,
	Menagerie,
	Curiosity_Dealer,
}

// Stock is what one Stock_Pool is made of — the two things a shop's stock varies by (issue
// #137): subset and size.
//
// Subset, via `families`: the Tag families the shop stocks — its character (a hold of
// Weapons is an ordnance hoy, a hold of Beasts a menagerie). Filtered on Tag (ADR-0012's
// family axis), not Category, because Category is a combat phase — a "Brace shop" would
// describe when its wares fire, not what they are. `families` is a Maybe; nil means *no
// filter*, not *every family*, so a chandlery keeps stocking a sixth Tag the day one is
// authored without this table being edited.
//
// Size, via `depth`: how many cards deep the hold is, and the only reason a shop can be
// exhausted — with the shelf window at SHOP_SHELF_SIZE, a visit reaches `depth` cards at
// most. Not tier weighting (Shop reads no stakes — see voyage.odin) and not price (economy
// tuning, out of scope).
Stock :: struct {
	name:     string,
	families: Maybe(bit_set[ship.Tag]),
	depth:    int,
}

// stock_pools is every shop in the game, authored in the same table shape as hostile_roster,
// trade_roster, and catalog.odin's recipe_catalog. @(rodata): like trade_roster, constant
// initializers.
//
// Only Chandlery is reachable today — the Port recipe names it (catalog.odin) and no other
// recipe carries a Shop, so the four specialist holds below are authored content waiting on
// the recipes that will name them (issue #138).
//
// Depth is authored per pool, and the feel is in the reserve it leaves behind the shelf
// (depth - SHOP_SHELF_SIZE) — what a purchase draws on before buying starts leaving bare
// slots. Chandlery's 12 leaves a reserve of 7, so the shelf is still full when a starting
// cargo of 50 runs out (emptying a Port takes a fortune spent on trinkets). A specialist's
// 6 leaves a reserve of 1, so the second purchase of a visit already bares a slot — a
// single ship's hold next to a town's warehouse. Both are pinned by test
// (a_chandlerys_reserve_outlasts_the_cargo_a_captain_brings,
// a_narrow_hold_shrinks_as_it_is_bought_and_can_be_emptied).
@(rodata)
stock_pools := [Stock_Pool]Stock {
	// The Port's pool and the only one a recipe names today. No filter: the general store
	// the Port bucket's guaranteed placement promises.
	.Chandlery = {name = "Chandlery", families = nil, depth = 12},
	// Guns — the largest specialist pool (15 Weapon items), a powder hoy running ordnance
	// between ports.
	.Ordnance_Hoy = {name = "Ordnance Hoy", families = bit_set[ship.Tag]{.Weapon}, depth = 6},
	// Hands — Crew, the family Admiral's Guard's per-Crew synergy sits in (see
	// hostile_roster), so this is the shop that can build that trap on purpose.
	.Press_Gang = {name = "Press Gang", families = bit_set[ship.Tag]{.Crew}, depth = 6},
	// Beasts — the smallest candidate family (10), so a 6-deep hold is over half of it and
	// two menageries in a run would visibly repeat.
	.Menagerie = {name = "Menagerie", families = bit_set[ship.Tag]{.Beast}, depth = 6},
	// Oddities — Artifact has no unifying mechanic (the roster's "everything else"), so its
	// stock is unpredictable in kind rather than uniform.
	.Curiosity_Dealer = {name = "Curiosity Dealer", families = bit_set[ship.Tag]{.Artifact}, depth = 6},
}

// voyage_stock_pool returns one pool's authored stock — the shops in the game are this
// table and nothing else.
voyage_stock_pool :: proc(pool: Stock_Pool) -> Stock {
	return stock_pools[pool]
}

// voyage_stock_candidates returns the roster indices a pool may stock, in roster order, and
// how many — the filter half of voyage_bake_shop, split out so the pool table can be checked
// against the roster by test without baking a shop.
//
// An unfiltered pool (families = nil) yields the whole roster in order, untouched — which is
// also what keeps a Chandlery's shuffle identical to the whole-roster deck, so seed-pinned
// Port maps do not move. A filtered pool keeps an item carrying *any* of the pool's families,
// so a multi-tag item (Naval Gun Crew is Crew+Weapon) is stocked by both an Ordnance Hoy and
// a Press Gang, the way selector_matches counts it under each of its tags.
voyage_stock_candidates :: proc(stock: Stock) -> (indices: [ship.ITEM_ROSTER_SIZE]int, count: int) {
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

// voyage_bake_shop bakes a Shop stage's stock from its authored pool (issue #137): the
// pool's candidates shuffled per-seed off the map generator's RNG, cut off at the pool's
// authored depth, each card priced by its Tier (ship.ship_item_cost). Every card is
// distinct, being a sample of a permutation, so a shelf never repeats an item within one
// visit.
//
// It takes no Scaling_Site — Shop is the one primitive that ignores its node's stakes. An
// Offer scales its items by the site; a shop stocks them as authored. Cost already rises
// with tier (ADR-0013), and Reward's payout is site-scaled (issue #133: 20/tier + 5/depth),
// so a shop that also improved with depth would compound the same progression from both
// ends. The market is fixed; the gradient a shop faces is the cargo the captain brings.
voyage_bake_shop :: proc(pool: Stock_Pool, gen: rand.Generator) -> Stage_Shop {
	stock := voyage_stock_pool(pool)
	roster := ship.ship_item_roster()

	candidates, n := voyage_stock_candidates(stock)
	rand.shuffle(candidates[:n], gen)

	shop := Stage_Shop{count = min(stock.depth, n)}
	for i in 0 ..< shop.count {
		item := roster[candidates[i]]
		shop.stock[i] = Shop_Item{fitting = item.fitting, cost = ship.ship_item_cost(item.tier)}
	}
	return shop
}
