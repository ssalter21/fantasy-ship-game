package run

import "../ship"

// PVE_OPPONENT_OFFENSE_BONUS_PER_TIER scales a PvE opponent's Gun Deck
// output by zone and port_closeness (issue #23), reusing the same zone_tier
// ladder as every other zone-scaled placeholder in run.odin — so a deeper,
// more-contested Ship Battle point hits harder, not just soaks more HP and
// Durability (already covered by run_ship_battle_difficulty and
// run_ship_battle_opponent_durability).
PVE_OPPONENT_OFFENSE_BONUS_PER_TIER :: 2

run_pve_opponent_offense_bonus :: proc(zone: Zone, port_closeness: int) -> int {
	return run_zone_scaled(zone, PVE_OPPONENT_OFFENSE_BONUS_PER_TIER) + port_closeness
}

// run_pve_opponent builds a full Ship Battle opponent (issue #23): the one
// ship template (ADR-0004), filled with the same starting-fitting roster
// used everywhere else in this slice — base Captain's Quarters and Top
// Crew, and an Upgraded Gun Deck scaled by this point's zone/port-closeness.
// hp and durability reuse run_make_opponent_ship's existing zone-scaled
// formulas rather than duplicating them. Carries no captain — a captain is a
// player-side, run-start choice (CONTEXT.md), not opponent content. Caller
// owns the returned Ship's layout slice.
run_pve_opponent :: proc(zone: Zone, port_closeness: int) -> ship.Ship {
	s := run_make_opponent_ship(zone, port_closeness)

	layout := ship.ship_template_layout()
	bonus := run_pve_opponent_offense_bonus(zone, port_closeness)

	ok: bool
	ok = ship.ship_fit(&layout[0], ship.ship_fitting_captains_quarters())
	assert(ok)
	ok = ship.ship_fit(&layout[1], ship.ship_fitting_top_crew())
	assert(ok)
	ok = ship.ship_fit(&layout[2], ship.ship_fitting_upgraded_gun_deck(bonus))
	assert(ok)
	ok = ship.ship_fit(&layout[3], ship.ship_fitting_cargo("Spoils"))
	assert(ok)
	ok = ship.ship_fit(&layout[4], ship.ship_fitting_cargo("Spoils"))
	assert(ok)
	ok = ship.ship_fit(&layout[5], ship.ship_fitting_cargo("Spoils"))
	assert(ok)

	s.layout = layout
	return s
}

// Ship_Battle_Point identifies one of the map's 4 actual Ship Battle points
// by the same (zone, port_closeness) key run_map_create already derives per
// point.
Ship_Battle_Point :: struct {
	zone:           Zone,
	port_closeness: int,
}

// ship_battle_points hand-lists the map's 4 actual Ship Battle points in map
// order (issue #23 — of the map's 12 total encounter points, 4 are Ship
// Battles), mirroring zone_encounter_kinds' placement: Coastal has two
// (nearer-port first), Open_Sea and Deep have one each.
ship_battle_points := [4]Ship_Battle_Point{
	{zone = .Coastal, port_closeness = 3},
	{zone = .Coastal, port_closeness = 2},
	{zone = .Open_Sea, port_closeness = 3},
	{zone = .Deep, port_closeness = 3},
}

// run_pve_opponents builds the map's 4 hand-authored Ship Battle PvE
// opponents as Ghost_Snapshots (issue #23; ADR-0008: hand-authored PvE
// opponents are themselves Ghost_Snapshot values, hp set explicitly as a
// difficulty knob rather than reset-from-capture). steps = 0: these are
// authored directly, never captured from a live run. Caller owns each
// returned snapshot's ship.layout slice.
run_pve_opponents :: proc() -> [4]Ghost_Snapshot {
	snaps: [4]Ghost_Snapshot
	for point, i in ship_battle_points {
		snaps[i] = Ghost_Snapshot{
			ship = run_pve_opponent(point.zone, point.port_closeness),
			progress = Ghost_Progress{
				steps             = 0,
				zone              = point.zone,
				difficulty_rating = run_ship_battle_difficulty(point.zone, point.port_closeness),
			},
		}
	}
	return snaps
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

// Encounter_Marker is presentation-facing metadata distinguishing an
// Encounter_Kind visually on the map (issue #23: Ship Battle points must
// read as visually distinct from Upgrade Offer/Stat Trade points).
// core/run has no rendering system of its own (ADR-0003's headless/UI
// split) — these are plain identifiers a future UI package (issue #24) maps
// to real assets, not asset references themselves.
Encounter_Marker :: struct {
	icon:  string,
	color: string,
}

encounter_kind_marker := [Encounter_Kind]Encounter_Marker{
	.Ship_Battle   = {icon = "crossed-swords", color = "crimson"},
	.Upgrade_Offer = {icon = "chevron-up", color = "gold"},
	.Stat_Trade    = {icon = "scales", color = "azure"},
}

// run_encounter_marker looks up e's visual marker by its kind.
run_encounter_marker :: proc(e: Encounter) -> Encounter_Marker {
	switch _ in e {
	case Encounter_Ship_Battle:
		return encounter_kind_marker[.Ship_Battle]
	case Encounter_Upgrade_Offer:
		return encounter_kind_marker[.Upgrade_Offer]
	case Encounter_Stat_Trade:
		return encounter_kind_marker[.Stat_Trade]
	}
	unreachable()
}
