package run

import "../combat"
import "../ship"

// Encounter resolution + ghost emission: what happens on first arrival at an
// Encounter node. Each of the three kinds resolves here and returns a
// Ghost_Snapshot (ADR-0008) of the player-side ship at that point. The
// encounter's tuned magnitudes were already baked into its content at
// generation time (content.odin); this is only the arrival-time application
// and snapshot. run_start_battle/run_finish_ship_battle bracket a Ship Battle
// around core/combat, which owns the actual round resolution.

// run_start_battle triggers a Ship Battle encounter: hands off to core/combat's
// existing Battle type rather than reimplementing combat. Caller drives the
// returned Battle to completion via combat.combat_resolve_round as normal.
run_start_battle :: proc(s: ^ship.Ship, encounter: ^Encounter_Ship_Battle) -> combat.Battle {
	return combat.combat_battle_create(s, &encounter.opponent)
}

// run_finish_ship_battle resolves a Ship Battle once its Battle has ended and
// returns a Ghost_Snapshot (ADR-0008) of s, the player-side ship handed to
// run_start_battle, not the opponent — an encounter is "resolved" from the
// player's own run-progress perspective. difficulty_rating is recomputed from
// zone/depth rather than read off the opponent's (now battle-worn) hp, since
// that would reflect remaining HP, not the node's original tuned difficulty.
// The returned snapshot's layout aliases s (see run_ghost_snapshot_of): the
// Sim owns the single arena-backed capture (issue #82).
run_finish_ship_battle :: proc(battle: ^combat.Battle, s: ^ship.Ship, encounter: ^Encounter_Ship_Battle, zone: Zone, steps: int) -> Ghost_Snapshot {
	assert(battle.ended, "run_finish_ship_battle called before the battle ended")

	return run_ghost_snapshot_of(s, steps, zone, run_ship_battle_difficulty(zone, encounter.depth))
}

// run_apply_upgrade_offer resolves an Upgrade Offer encounter (ADR-0008):
// grants nothing concrete yet since which upgrade the captain picks among
// offer's options is real content for issue #23 — this proc only returns the
// resolved Ghost_Snapshot, using offer's zone-and-depth-scaled quality
// placeholder as the snapshot's difficulty_rating.
run_apply_upgrade_offer :: proc(s: ^ship.Ship, offer: Encounter_Upgrade_Offer, zone: Zone, steps: int) -> Ghost_Snapshot {
	return run_ghost_snapshot_of(s, steps, zone, offer.quality)
}

// run_apply_stat_trade resolves a Stat Trade encounter: unlike Upgrade Offer,
// a Stat Trade is a single fixed trade-off rather than a choice among
// options, so it applies immediately and permanently on arrival, matching "no
// decline". Returns a post-trade Ghost_Snapshot (ADR-0008); the trade's own
// gain_durability is already this node's zone-and-depth-scaled tuned
// magnitude, so it doubles as the snapshot's difficulty_rating.
run_apply_stat_trade :: proc(s: ^ship.Ship, trade: Encounter_Stat_Trade, zone: Zone, steps: int) -> Ghost_Snapshot {
	s.durability += trade.gain_durability
	s.speed -= trade.cost_speed

	return run_ghost_snapshot_of(s, steps, zone, trade.gain_durability)
}
