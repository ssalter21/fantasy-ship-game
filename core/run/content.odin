package run

import "../ship"
import "core:math/rand"

// run_make_opponent_ship computes a Ship Battle opponent's baseline stats
// (hp, durability, speed) from the node's Scaling_Site — the numeric half of a
// hand-authored PvE opponent (issue #23). run_pve_opponent layers a
// hand-authored layout on top of these same stats; this proc has no
// layout/captain of its own and is not itself a complete opponent.
run_make_opponent_ship :: proc(site: Scaling_Site) -> ship.Ship {
	hp := run_fight_opponent_hp(site)
	return ship.Ship{
		hp         = hp,
		max_hp     = hp,
		durability = run_fight_opponent_durability(site),
		speed      = FIGHT_OPPONENT_SPEED,
	}
}

// run_pve_opponent builds a full Ship Battle opponent (issue #23): the one
// ship template (ADR-0004), filled with the same starting-fitting roster
// used everywhere else in this slice — base Captain's Quarters and Top
// Crew, and an Upgraded Gun Deck scaled by this node's zone/depth. hp and
// durability reuse run_make_opponent_ship's existing zone-and-depth-scaled
// formulas rather than duplicating them. Carries no captain — a captain is a
// player-side, run-start choice (CONTEXT.md), not opponent content. Caller
// owns the returned Ship's layout slice.
// run_fit_pve_opponent_loadout fits the opponent's fixed combat loadout into
// the template's exposed slots and hands the rest to
// ship_fill_empty_slots_with_cargo (issue #54: an or_return chain replacing
// hand-threaded ok/assert pairs, mirroring core/ship's
// ship_fit_starting_loadout — a false return means the template and this
// roster have drifted out of sync). Issue #91: the opponent's spare slots fill
// with "Spoils" cargo the same way the player's fill with "Cargo".
run_fit_pve_opponent_loadout :: proc(layout: []ship.Layout_Slot, bonus: int) -> bool {
	ship.ship_fit(&layout[0], ship.ship_fitting_captains_quarters()) or_return
	ship.ship_fit(&layout[1], ship.ship_fitting_top_crew()) or_return
	ship.ship_fit(&layout[2], ship.ship_fitting_upgraded_gun_deck(bonus)) or_return
	return ship.ship_fill_empty_slots_with_cargo(layout, "Spoils")
}

run_pve_opponent :: proc(site: Scaling_Site) -> ship.Ship {
	s := run_make_opponent_ship(site)

	layout := ship.ship_template_layout()
	bonus := run_fight_opponent_offense(site)
	assert(run_fit_pve_opponent_loadout(layout, bonus), "PvE opponent loadout: a fitting failed to fit its template slot")

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
// shared front half of sampling N distinct roster items, used by both the Offer
// stage (run_item_offer_options) and the Shop stage (run_port_shop). Each takes
// the first N and maps them its own way: an offer scales the fitting by node
// stakes, a shop prices it by tier. Consolidating the shuffle here keeps the two
// samplers from drifting (issue #98).
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
// **Size — six.** A run traverses only ~3-4 nodes per zone (~11-14 of 50), and a
// Trade is one recipe among the catalog's three, so a single run meets a handful
// of trades at most. Six is the smallest size that still makes a *run* mostly
// non-repeating while making consecutive runs visibly different — the roster's
// actual job. Going wider buys variance the player never lives long enough to
// see; going narrower (four, say) and a single run would routinely draw the same
// bargain twice, which is exactly the sameness this ticket exists to kill.
//
// **Coverage.** Every stat is gained by some entry and — except HP — spent by
// some entry. HP is deliberately gain-only: nothing else in the game heals
// (combat is the only writer of Ship.hp, and it only ever subtracts), which makes
// repair the scarcest thing a trade can offer. Costing HP is available in the
// model (run_trade_pay handles it, floored) but unauthored: a trade that damages
// you is a Fight without the fight, and it is the one cost that could end a run
// on a menu.
// Names are checked against core/ship's fitting roster and deliberately don't
// collide with it: a Trade is not a thing you install, and "Reinforced Hull"
// already names a Medium Defensive fitting the player can be holding while a
// trade is on screen.
@(rodata)
trade_roster := [?]Trade_Axis {
	// The welded axis, now merely the first row. Durability and Speed kept their
	// old constants, so this entry reproduces the pre-#136 Bargain exactly.
	{name = "Braced Bulkheads", gain = .Durability, cost = .Speed},
	// The inverse — the entry that proves the axis is a space and not a point.
	{name = "Stripped Spars", gain = .Speed, cost = .Durability},
	// Patch the damage you have by permanently lowering the ceiling. The one
	// entry that trades HP against Max HP, which is why both are distinct stats.
	{name = "Cannibalized Timbers", gain = .HP, cost = .Max_HP},
	{name = "Lightened Hold", gain = .Speed, cost = .Max_HP},
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
// Shop's deck — and reads each side's magnitude as that stat's swing at this
// node's site. Called from run_bake_stage at generation time; nothing rolls on
// arrival.
//
// Both terms read the *same* site, so stakes move the whole trade together: a
// Deep Braced Bulkheads gains more Durability and costs more Speed than a Coastal
// one, rather than scaling only the half that used to have a constant.
run_make_trade :: proc(site: Scaling_Site, gen: rand.Generator) -> Stage_Trade {
	roster := run_trade_roster()
	axis := roster[rand.int_max(len(roster), gen)]

	return Stage_Trade{
		name = axis.name,
		gain = Trade_Term{stat = axis.gain, amount = run_trade_swing(site, axis.gain)},
		cost = Trade_Term{stat = axis.cost, amount = run_trade_swing(site, axis.cost)},
	}
}

// run_port_shop bakes a Shop stage's deck (#123, ADR-0013): the *full* roster
// shuffled into a per-seed-reproducible order (run_shuffled_roster_indices, off
// the map generator's RNG so decks vary node to node yet reproduce per seed),
// each card priced by its Tier (ship.ship_item_cost). Unlike an Offer the fitting
// is stocked as-authored, not stakes-scaled: a shop's variance is which items and
// what they cost, and cost already rises with tier, so layering a quality bonus
// on top would double-count the tier. Baked at generation time so a Shop carries
// its whole deck as content, like an Offer carries its options; the shelf window
// and draw-down are runtime concerns the Sim owns. Every card is distinct — the
// deck is a permutation of the roster — so a shelf drawn off it never repeats an
// item within one stage.
//
// Still named for the Port because a Port is the only thing that carries a shop
// today; once Ports are the [Shop] recipe (#134/#137) the stage's stock pool is
// what varies, which is #137's half.
run_port_shop :: proc(gen: rand.Generator) -> Stage_Shop {
	roster := ship.ship_item_roster()
	order := run_shuffled_roster_indices(gen)

	shop: Stage_Shop
	for roster_index, deck_pos in order {
		item := roster[roster_index]
		shop.deck[deck_pos] = Shop_Item{fitting = item.fitting, cost = ship.ship_item_cost(item.tier)}
	}
	return shop
}
