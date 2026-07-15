package run

import "../ship"
import "core:math/rand"

// run_make_opponent_ship computes a Ship Battle opponent's baseline stats
// (hp, durability, speed) from the node's Scaling_Site — the numeric half of a
// hand-authored PvE opponent (issue #23). run_pve_opponent layers a
// hand-authored layout on top of these same stats; this proc has no
// layout/captain of its own and is not itself a complete opponent.
run_make_opponent_ship :: proc(site: Scaling_Site) -> ship.Ship {
	hp := run_ship_battle_difficulty(site)
	return ship.Ship{
		hp         = hp,
		max_hp     = hp,
		durability = run_ship_battle_opponent_durability(site),
		speed      = SHIP_BATTLE_OPPONENT_SPEED,
	}
}

// PVE_OPPONENT_OFFENSE_BONUS_PER_TIER/PER_DEPTH scale a PvE opponent's Gun
// Deck output by zone tier and depth-within-zone (issue #23), reusing the
// same run_zone_depth_scaled shape as every other zone-and-depth-scaled placeholder in
// run.odin — so a deeper Ship Battle node hits harder, not just soaks more
// HP and Durability (already covered by run_ship_battle_difficulty and
// run_ship_battle_opponent_durability).
PVE_OPPONENT_OFFENSE_BONUS_PER_TIER :: 2
PVE_OPPONENT_OFFENSE_BONUS_PER_DEPTH :: 1

run_pve_opponent_offense_bonus :: proc(site: Scaling_Site) -> int {
	return run_zone_depth_scaled(site, PVE_OPPONENT_OFFENSE_BONUS_PER_TIER, PVE_OPPONENT_OFFENSE_BONUS_PER_DEPTH)
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
	bonus := run_pve_opponent_offense_bonus(site)
	assert(run_fit_pve_opponent_loadout(layout, bonus), "PvE opponent loadout: a fitting failed to fit its template slot")

	s.layout = layout
	return s
}

// ITEM_OFFER_QUALITY_DIVISOR converts a node's zone-scaled quality placeholder
// (run_item_offer_quality) into a flat magnitude bonus added to each offered
// item (issue #96): a smaller, more legible number than raw quality while still
// scaling with it — the same knob the old Upgrade Offer applied to its three
// fixed variants, now spread across the roster items on offer.
ITEM_OFFER_QUALITY_DIVISOR :: 5

// run_item_offer_options picks the distinct roster items an Offer stage presents
// (issue #96, ADR-0012): it samples ITEM_OFFER_OPTION_COUNT distinct items from
// ship_item_roster — shuffling the pool's indices with the map generator's RNG
// (`gen`) so an offer's items are reproducible per seed yet vary node to node —
// and scales each by this node's stakes. Baked at generation time
// (run_bake_stage), so the offer carries its items as content, like a Fight
// carries its opponent. Retires run_upgrade_offer_options' fixed three-upgrade
// menu.
run_item_offer_options :: proc(site: Scaling_Site, gen: rand.Generator) -> [ITEM_OFFER_OPTION_COUNT]ship.Fitting {
	bonus := run_item_offer_quality(site) / ITEM_OFFER_QUALITY_DIVISOR
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
