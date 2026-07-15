package run

import "../combat"
import "../ship"

// Stage resolution + ghost emission: what happens when a stage the ship arrived
// at is applied. Each primitive that changes run state resolves here and returns
// a Ghost_Snapshot (ADR-0008) of the player-side ship at that point, stamped
// with the node's stakes (its Scaling_Site). The stage's tuned magnitudes were
// already baked into its content at generation time (content.odin); this is only
// the arrival-time application and snapshot.
// run_start_battle/run_finish_ship_battle bracket a Fight around core/combat,
// which owns the actual round resolution.
//
// These are the per-primitive *applications*; which stage is applied next, and
// whether the walk continues past it, is the encounter's own cursor
// (run_encounter_resolve_stage in stage.odin), driven by the Sim (issue #131).

// run_start_battle triggers a Fight stage: hands off to core/combat's existing
// Battle type rather than reimplementing combat. Caller drives the returned
// Battle to completion via combat.combat_resolve_round as normal.
run_start_battle :: proc(s: ^ship.Ship, fight: ^Stage_Fight) -> combat.Battle {
	return combat.combat_battle_create(s, &fight.opponent)
}

// run_finish_ship_battle resolves a Fight once its Battle has ended and returns a
// Ghost_Snapshot (ADR-0008) of s, the player-side ship handed to run_start_battle,
// not the opponent — a stage is "resolved" from the player's own run-progress
// perspective. The snapshot's stakes are rebuilt from the node's own zone/depth
// rather than read off the opponent's (now battle-worn) hp, which would reflect
// remaining HP, not what the node staked: that rationale is why Stage_Fight
// retains depth at all. The returned snapshot's layout aliases s (see
// run_ghost_snapshot_of): the Sim owns the single arena-backed capture
// (issue #82).
run_finish_ship_battle :: proc(battle: ^combat.Battle, s: ^ship.Ship, fight: ^Stage_Fight, zone: Zone, steps: int) -> Ghost_Snapshot {
	assert(battle.ended, "run_finish_ship_battle called before the battle ended")

	return run_ghost_snapshot_of(s, steps, Scaling_Site{zone = zone, depth = fight.depth})
}

// An Offer stage has no run-side apply proc (issue #96): unlike a Trade it
// changes no ship stat on arrival, and unlike the retired Upgrade Offer it
// grants nothing at resolve time — picking an item opens a Refit (core/sim's
// sim_open_refit) that places it through the manual-loadout commands, and the
// old run_apply_upgrade_offer / its resolve-time Ghost_Snapshot are retired with
// the auto-replace path. The Sim marks the node resolved when the choice is made.

// run_apply_stat_trade resolves a Trade stage: unlike an Offer, a Trade is a
// single fixed trade-off rather than a choice among options, so it applies
// immediately and permanently on arrival, matching "no decline". Returns a
// post-trade Ghost_Snapshot (ADR-0008) carrying the node's own stakes — a Trade
// reads the site as swing size, and the snapshot records the site itself, so it
// no longer has to pass off gain_durability as a difficulty a Trade never had
// (ADR-0014).
run_apply_stat_trade :: proc(s: ^ship.Ship, trade: Stage_Trade, site: Scaling_Site, steps: int) -> Ghost_Snapshot {
	s.durability += trade.gain_durability
	s.speed -= trade.cost_speed

	return run_ghost_snapshot_of(s, steps, site)
}
