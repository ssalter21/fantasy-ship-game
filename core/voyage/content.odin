package voyage

import "../ship"
import "core:math/rand"

// Hostile_Archetype is one authored entry in the Fight roster (ADR-0014): a named hostile
// build — just the items it carries. No Hull or Speed: the node's stakes supply hull, and
// Speed derives from what the build weighs (ADR-0020). An archetype
// says *what kind of ship this is*; the site decides how much.
//
// `items` names roster items by their authored name (ship_item_by_name), so a hostile is
// built from the same items the player can be offered (ADR-0012) — tags, synergies, and
// conditions work aboard a hostile exactly as aboard the player. Names are checked by test,
// not the compiler.
//
// Order is authoring: items are placed first-empty-fit (ship_fit_first_empty_slot) into a
// template whose slots are exposed-first within each size, so an item's position decides
// whether it lands on deck or in the concealed hold — which decides whether a
// Own_Visibility-reading or Selector(Visibility.Concealed) effect fires.
Hostile_Archetype :: struct {
	name:  string,
	items: []string,
}

// Backing arrays for each archetype's item list — static authored data reused by every node
// that draws it, so it must not be per-node memory. @(rodata): these are constant
// initializers (unlike hostile_roster below, which slices them).
@(rodata)
COASTAL_PRIVATEER_ITEMS := [?]string{"Long Nines", "Carronade", "Swivel Guns", "Carpenter's Mate"}

@(rodata)
BROADSIDE_COMPANY_ITEMS := [?]string{"Naval Gun Crew", "Swivel Guns", "Powder Monkeys", "Boarding Pikes"}

@(rodata)
DEEPWATER_MENAGERIE_ITEMS := [?]string{"Hunter's Pack", "Snapping Eels", "War Hound"}

@(rodata)
SMUGGLERS_RUN_ITEMS := [?]string{"Copper Sheathing", "Oakum & Pitch", "Wraith Cannon", "Spare Rigging", "Ghost Lantern"}

@(rodata)
IRONCLAD_HULK_ITEMS := [?]string{"Long Nines", "Ramming Prow", "Shipwright's Kit", "Spare Timbers"}

@(rodata)
BOARDING_PARTY_ITEMS := [?]string{"Naval Gun Crew", "Admiral's Guard", "Boarding Pikes"}

@(rodata)
DEATH_THROES_ITEMS := [?]string{"Deck Cannon", "Kraken Spawn", "War Hound"}

@(rodata)
REEF_SKIMMER_ITEMS := [?]string{"Deck Cannon", "Carronade", "Copper Sheathing", "Swivel Guns", "Spare Rigging"}

// hostile_roster is every hostile in the game, authored in the same table shape as
// trade_roster and catalog.odin's recipe_catalog; voyage_pve_opponent deals from it. Not
// @(rodata): slicing the backing arrays above is not a constant initializer, so the entries
// fill at program init.
//
// The authoring contract every entry must satisfy: an archetype is character, stakes is
// power. Entries are authored at Open Sea weight (ADR-0019) — voyage_fight_opponent_power
// reads 100% in the middle zone, half at Coastal, half-again on top in The Deep — and stay
// within a comparable band, because an archetype is drawn with no regard to zone and a wide
// spread would let the draw swamp the depth gradient. The band has two test-enforced walls: a
// ceiling (an overshooting hostile sinks a starting player before the escape gate) and a
// floor (`max(0, …)` means one dealing too little cannot scratch a starting ship at Coastal —
// a fight with no risk). Magnitudes ride on the items (ADR-0012 placeholders).
hostile_roster := [?]Hostile_Archetype {
	{name = "Coastal Privateer", items = COASTAL_PRIVATEER_ITEMS[:]},
	{name = "Broadside Company", items = BROADSIDE_COMPANY_ITEMS[:]},
	{name = "Deepwater Menagerie", items = DEEPWATER_MENAGERIE_ITEMS[:]},
	{name = "Smuggler's Run", items = SMUGGLERS_RUN_ITEMS[:]},
	{name = "Ironclad Hulk", items = IRONCLAD_HULK_ITEMS[:]},
	{name = "Boarding Party", items = BOARDING_PARTY_ITEMS[:]},
	{name = "Death Throes", items = DEATH_THROES_ITEMS[:]},
	{name = "Reef Skimmer", items = REEF_SKIMMER_ITEMS[:]},
}

// voyage_hostile_roster returns every authored hostile archetype; voyage_pve_opponent deals
// from it.
voyage_hostile_roster :: proc() -> []Hostile_Archetype {
	return hostile_roster[:]
}

// voyage_make_opponent_ship computes a PvE opponent's stakes-scaled hull from the node's
// Scaling_Site (issue #23), and sets the uniform BASE_SPEED base (ADR-0020); a
// hostile's actual Speed derives from what it carries (ship_effective_speed).
// voyage_pve_opponent layers the archetype's loadout on top — this ship has no layout or
// captain of its own and is not a complete opponent.
voyage_make_opponent_ship :: proc(site: Scaling_Site) -> ship.Ship {
	hull := voyage_fight_opponent_hull(site)
	return ship.Ship{
		hull     = hull,
		max_hull = hull,
		speed    = ship.BASE_SPEED,
	}
}

// voyage_fit_hostile_loadout fits an archetype's items into the one ship template (ADR-0004),
// each scaled to the site's power reading, and fills the leftover slots with Spoils (issue
// #91, the opponent's analogue of the player's Cargo). The or_return chain mirrors
// ship_fit_starting_loadout: a false return means the archetype asks for more slots of a size
// than the template has — a content bug this package's tests catch, not a runtime condition.
//
// power_percent is a factor applied per fitting, so it is scale-invariant: three guns at 50%
// is the same proportion as one gun at 50%, and gun count cannot swamp the site's reading. A
// Selector scales with its match count, upstream of effect_magnitude's synergy seam — the
// multiplier holds through that for the same reason.
//
// **Stakes scales what a hostile deals, and Fire damage is the only thing it deals**, which
// is a guard on the verb rather than on the loadout: ship_fitting_output_scaled moves
// Phase_Contribution effects and leaves Repair and Modify_Speed where they were, so every
// fitting can be handed to it. Repair is exempt because a hostile repair that reached the
// player's per-round Fire output would be an unkillable hostile (ADR-0027); a deep hostile's
// staying power grows through its Hull pool instead, which has no such ceiling.
voyage_fit_hostile_loadout :: proc(layout: []ship.Layout_Slot, archetype: Hostile_Archetype, power_percent: int) -> bool {
	for name in archetype.items {
		item, found := ship.ship_item_by_name(name)
		assert(found, "hostile archetype names an item that is not in the roster")

		ship.ship_fit_first_empty_slot(layout, ship.ship_fitting_output_scaled(item.fitting, power_percent)) or_return
	}
	ship.ship_fill_empty_slots_with_holds(layout, "Spoils") or_return
	ship.ship_fill_holds_to_percent(layout, ship.HOSTILE_FILL_PERCENT)
	return true
}

// voyage_pve_opponent builds a full Ship Battle opponent: it draws one archetype from the
// hostile roster and bakes it at the node's stakes — the archetype supplies the loadout (and,
// through its weight, its Speed), the site supplies hull and the fire bonus.
// Draws off the map generator's RNG, so which hostile a node holds is reproducible per seed
// yet varies node to node; called from voyage_bake_stage at generation time (ADR-0013:
// nothing rolls on arrival).
//
// The draw reads no zone — archetype and stakes are independent axes, so a Deep node gets a
// tougher hostile, not a different pool. Carries no captain (a captain is a player-side,
// run-start choice — CONTEXT.md). Caller owns the returned Ship's layout slice;
// voyage_map_destroy frees it per Fight stage.
voyage_pve_opponent :: proc(site: Scaling_Site, gen: rand.Generator) -> ship.Ship {
	roster := voyage_hostile_roster()
	archetype := roster[rand.int_max(len(roster), gen)]

	// BASE_SPEED base only; a hostile's actual Speed falls out of its weight
	// (ship_effective_speed).
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
		// tier's power is already baked into the item's magnitudes, so the offer reads only
		// the fitting and scales it by this node's quality (a shop reads the tier for cost).
		options[i] = ship.ship_fitting_scaled(roster[indices[i]].fitting, bonus)
	}
	return options
}

// voyage_shuffled_roster_indices returns the roster's indices (0..<ship.ITEM_ROSTER_SIZE) in
// a per-seed-reproducible shuffled order — the front half of sampling N distinct roster items
// for the Offer stage (voyage_item_offer_options takes the first ITEM_OFFER_OPTION_COUNT).
// Offer-only: a Shop draws from its own stock pool (voyage_bake_shop), not the whole roster.
voyage_shuffled_roster_indices :: proc(gen: rand.Generator) -> [ship.ITEM_ROSTER_SIZE]int {
	indices: [ship.ITEM_ROSTER_SIZE]int
	for i in 0 ..< ship.ITEM_ROSTER_SIZE {
		indices[i] = i
	}
	rand.shuffle(indices[:], gen)
	return indices
}

// Trade_Axis is one authored entry in the Trade roster (issue #136): a named bargain and the
// two stats it swaps. It carries no magnitudes — those are each stat's swing at the node's
// site (voyage_trade_swing) — so an axis is authored purely as "what for what" and the site
// decides how big.
Trade_Axis :: struct {
	name: string,
	gain: Trade_Stat,
	cost: Trade_Stat,
}

// trade_roster is every trade in the game, authored in the same table shape as
// recipe_catalog; voyage_make_trade deals from it. @(rodata): unlike hostile_roster these are
// constant initializers, so the table lives in read-only memory.
//
// Authoring guardrails: Hull is gain-only and stays that way — nothing else in the game heals
// (combat is the only writer of Ship.hull and only ever subtracts), so repair is the scarcest
// thing a trade can offer, and a trade that damages you is a Fight without the fight. Names
// are checked against core/ship's roster and must not collide with it — a Trade is not a
// thing you install. Speed is not tradeable here: it is a derived read-out of weight
// (ADR-0020), not a stat a Trade can pay out of.
@(rodata)
trade_roster := [?]Trade_Axis {
	{name = "Cannibalized Timbers", gain = .Hull, cost = .Max_Hull},
	{name = "Shipwright's Bargain", gain = .Max_Hull, cost = .Cargo},
}

// voyage_trade_roster returns every authored trade axis; voyage_make_trade deals from it.
voyage_trade_roster :: proc() -> []Trade_Axis {
	return trade_roster[:]
}

// voyage_make_trade bakes a Trade stage (issue #136): it draws one axis off the map
// generator's RNG — reproducible per seed, varying node to node — and reads each side's
// magnitude as that stat's swing in this node's zone. Called from voyage_bake_stage at
// generation time. Both terms read the same zone, so stakes move the whole trade together.
//
// It takes a Zone rather than the node's full Scaling_Site because a swing is zone-scaled and
// nothing else (#146: see TRADE_SWING_* in voyage.odin) — so Trade is the one primitive that
// reads *part* of its node's stakes, where the Shop beside it in voyage_bake_stage reads none.
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
// difference in how it reaches a node: an archetype and an axis are *drawn*, a stock pool is
// *named by the recipe* (Stage_Spec.stock). A Fight can draw with no regard to zone because
// archetype and stakes are independent; a Shop cannot, because the two carriers of Shop stages
// are not interchangeable — a Port is guaranteed (PORTS_PER_ZONE per zone), so it must be a
// dependable general market, while a merchant vessel is a windfall that can afford to be
// narrow. Naming the pool on the recipe is what lets those two mean different holds.
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
// `families` is the subset: the Tag families the shop stocks. Filtered on Tag (ADR-0012's
// family axis), not Phase, because Phase is a combat phase — filtering on it would sort
// wares by when they fire, not what they are. A Maybe: nil means *no filter*, not *every
// family*, so an unfiltered shop keeps stocking a sixth Tag the day one is authored without
// this table being edited.
//
// `depth` is the size: how many cards deep the hold is. With the shelf window at
// SHOP_SHELF_SIZE, a visit reaches `depth` cards at most, so depth is what decides whether a
// shop can be emptied. Stock varies by nothing else: not tier weighting (Shop reads no stakes
// — see voyage.odin) and not price (economy tuning, out of scope).
Stock :: struct {
	name:     string,
	families: Maybe(bit_set[ship.Tag]),
	depth:    int,
}

// stock_pools is every shop in the game, authored in the same table shape as hostile_roster
// and trade_roster. @(rodata): like trade_roster, constant initializers.
//
// Only Chandlery is wired today — the Port recipe names it and no other recipe carries a
// Shop, so the specialist holds are authored content waiting on the recipes that will name
// them (issue #138).
//
// `depth` sets the reserve behind the shelf (depth - SHOP_SHELF_SIZE): a visit sees
// SHOP_SHELF_SIZE cards and refills each bought slot from the reserve, so the reserve is the
// only thing standing between a shop and exhaustion — once it is spent, buying leaves bare
// slots and the shop visibly shrinks. A full-shelf Chandlery and an emptiable specialist are
// both pinned by test.
@(rodata)
stock_pools := [Stock_Pool]Stock {
	.Chandlery = {name = "Chandlery", families = nil, depth = 12},
	.Ordnance_Hoy = {name = "Ordnance Hoy", families = bit_set[ship.Tag]{.Weapon}, depth = 6},
	.Press_Gang = {name = "Press Gang", families = bit_set[ship.Tag]{.Crew}, depth = 6},
	.Menagerie = {name = "Menagerie", families = bit_set[ship.Tag]{.Beast}, depth = 6},
	.Curiosity_Dealer = {name = "Curiosity Dealer", families = bit_set[ship.Tag]{.Artifact}, depth = 6},
}

// voyage_stock_pool returns one pool's authored stock.
voyage_stock_pool :: proc(pool: Stock_Pool) -> Stock {
	return stock_pools[pool]
}

// voyage_stock_candidates returns the roster indices a pool may stock, in roster order, and
// how many — the filter half of voyage_bake_shop, split out so the pool table can be checked
// against the roster by test without baking a shop.
//
// An unfiltered pool (families = nil) yields the whole roster in order, untouched — which also
// keeps an unfiltered shuffle identical to the whole-roster deck, so seed-pinned Port maps do
// not move. A filtered pool keeps an item carrying *any* of the pool's families, so a
// multi-tag item (Naval Gun Crew is Crew+Weapon) is stocked under each of its tags.
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

// voyage_bake_shop bakes a Shop stage's stock from its authored pool (issue #137): the pool's
// candidates shuffled per-seed off the map generator's RNG, cut off at the pool's authored
// depth. Every card is distinct, being a sample of a permutation, so a shelf never repeats an
// item within one visit.
//
// A card is stocked as the roster item it is, tier and all, and priced only when the shelf
// presents it (voyage_shop_price) — its price turns on the visit's purchase depth, which no
// amount of generation-time work can know.
//
// It takes no Scaling_Site — Shop is the one primitive that ignores its node's stakes. Cost
// already rises with tier (ADR-0013), and Reward's payout is site-scaled (issue #133), so a
// shop that also improved with depth would compound the same progression from both ends. The
// market is fixed; the gradient a shop faces is the cargo the captain brings.
voyage_bake_shop :: proc(pool: Stock_Pool, gen: rand.Generator) -> Stage_Shop {
	stock := voyage_stock_pool(pool)
	roster := ship.ship_item_roster()

	candidates, n := voyage_stock_candidates(stock)
	rand.shuffle(candidates[:n], gen)

	shop := Stage_Shop{count = min(stock.depth, n)}
	for i in 0 ..< shop.count {
		shop.stock[i] = roster[candidates[i]]
	}
	return shop
}
