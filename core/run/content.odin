package run

import "../ship"

// PVE_OPPONENT_OFFENSE_BONUS_PER_TIER/PER_DEPTH scale a PvE opponent's Gun
// Deck output by zone tier and depth-within-zone (issue #23), reusing the
// same run_scaled shape as every other zone-and-depth-scaled placeholder in
// run.odin — so a deeper Ship Battle point hits harder, not just soaks more
// HP and Durability (already covered by run_ship_battle_difficulty and
// run_ship_battle_opponent_durability).
PVE_OPPONENT_OFFENSE_BONUS_PER_TIER :: 2
PVE_OPPONENT_OFFENSE_BONUS_PER_DEPTH :: 1

run_pve_opponent_offense_bonus :: proc(zone: Zone, depth: int) -> int {
	return run_scaled(zone, depth, PVE_OPPONENT_OFFENSE_BONUS_PER_TIER, PVE_OPPONENT_OFFENSE_BONUS_PER_DEPTH)
}

// run_pve_opponent builds a full Ship Battle opponent (issue #23): the one
// ship template (ADR-0004), filled with the same starting-fitting roster
// used everywhere else in this slice — base Captain's Quarters and Top
// Crew, and an Upgraded Gun Deck scaled by this point's zone/depth. hp and
// durability reuse run_make_opponent_ship's existing zone-and-depth-scaled
// formulas rather than duplicating them. Carries no captain — a captain is a
// player-side, run-start choice (CONTEXT.md), not opponent content. Caller
// owns the returned Ship's layout slice.
// run_fit_pve_opponent_loadout fits every slot of run_pve_opponent's fixed
// loadout (issue #54: an or_return chain replacing 6 hand-threaded
// ok/assert pairs, mirroring core/ship's ship_fit_starting_loadout — a false
// return means the template and this roster have drifted out of sync).
run_fit_pve_opponent_loadout :: proc(layout: []ship.Layout_Slot, bonus: int) -> bool {
	ship.ship_fit(&layout[0], ship.ship_fitting_captains_quarters()) or_return
	ship.ship_fit(&layout[1], ship.ship_fitting_top_crew()) or_return
	ship.ship_fit(&layout[2], ship.ship_fitting_upgraded_gun_deck(bonus)) or_return
	ship.ship_fit(&layout[3], ship.ship_fitting_cargo("Spoils")) or_return
	ship.ship_fit(&layout[4], ship.ship_fitting_cargo("Spoils")) or_return
	return ship.ship_fit(&layout[5], ship.ship_fitting_cargo("Spoils"))
}

run_pve_opponent :: proc(zone: Zone, depth: int) -> ship.Ship {
	s := run_make_opponent_ship(zone, depth)

	layout := ship.ship_template_layout()
	bonus := run_pve_opponent_offense_bonus(zone, depth)
	assert(run_fit_pve_opponent_loadout(layout, bonus), "PvE opponent loadout: a fitting failed to fit its template slot")

	s.layout = layout
	return s
}

// UPGRADE_OFFER_QUALITY_DIVISOR converts a point's zone-scaled quality
// placeholder (run_upgrade_offer_quality) into a flat magnitude bonus for
// whichever of the three starting fittings the captain picks (issue #23): a
// smaller, more legible number than raw quality while still scaling with it.
UPGRADE_OFFER_QUALITY_DIVISOR :: 5

// run_upgrade_offer_options is the fixed menu presented at every Upgrade
// Offer point (issue #23; ADR-0004: findable content is limited to upgraded
// variants of the three starting fittings — no separate fitting roster, so
// the menu itself never varies). Only the magnitude scales per point, driven
// by that point's own zone-scaled quality.
run_upgrade_offer_options :: proc(offer: Encounter_Upgrade_Offer) -> [3]ship.Fitting {
	bonus := offer.quality / UPGRADE_OFFER_QUALITY_DIVISOR
	return [3]ship.Fitting{
		ship.ship_fitting_upgraded_top_crew(bonus),
		ship.ship_fitting_upgraded_captains_quarters(bonus),
		ship.ship_fitting_upgraded_gun_deck(bonus),
	}
}
