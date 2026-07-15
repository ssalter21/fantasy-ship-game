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
// changes no ship stat when it resolves, and unlike the retired Upgrade Offer it
// grants nothing at resolve time — picking an item opens a Refit (core/sim's
// sim_open_refit) that places it through the manual-loadout commands, and the
// old run_apply_upgrade_offer / its resolve-time Ghost_Snapshot are retired with
// the auto-replace path. The Sim marks the node resolved when the choice is made.

// run_trade_stat_floor is the lowest a stat may be left by paying a trade's cost
// (issue #136). Durability, Speed and Treasure floor at 0 — a ship with none of
// them is a valid, badly-off ship. HP and Max HP floor at **1**: a trade is a
// bargain struck on a menu, and sinking the ship there would hand permadeath to
// a stage whose whole job is a choice, duplicating Fight's outcome while dodging
// its agency.
run_trade_stat_floor :: proc(stat: Trade_Stat) -> int {
	switch stat {
	case .HP, .Max_HP:
		return 1
	case .Durability, .Speed, .Treasure:
		return 0
	}
	unreachable()
}

// run_trade_stat_reading is how much of `stat` the ship currently has, for
// deciding what a trade's cost can be measured against.
//
// It reads the **effective** stat, never the raw base field (ADR-0012, issue
// #92): a fitting that grants +Durability genuinely makes a Durability cost
// affordable, because effective is the number combat and escape actually resolve
// against, so it is the number the ship truly "has". HP is its own reading rather
// than an effective one because Ship.hp has no modifier path — fittings move the
// *ceiling* (Modify_Max_HP), not the current value.
run_trade_stat_reading :: proc(s: ^ship.Ship, stat: Trade_Stat) -> int {
	switch stat {
	case .HP:
		return s.hp
	case .Max_HP:
		return ship.ship_effective_max_hp(s)
	case .Durability:
		return ship.ship_effective_durability(s)
	case .Speed:
		return ship.ship_effective_speed(s)
	case .Treasure:
		return s.starting_treasure
	}
	unreachable()
}

// run_trade_can_accept reports whether the ship can pay this trade's cost in full
// (issue #136) — the question the Trade stage's accept option is gated on.
//
// A trade is **all or nothing**: a cost the ship cannot cover is not clamped down
// to what it can afford, because a clamped cost is a free lunch at the floor (dump
// Speed to 0 once, then take every +Durability-for-Speed bargain for nothing), and
// it is not allowed to run the stat negative either, which is what the welded axis
// silently did — a Deep Bargain costs 6 Speed against a starting 4. Instead the
// trade simply cannot be accepted, and rejecting halts the stage (ADR-0014), which
// is a path the player already has.
//
// That an unaffordable trade is a dead node is a **tuning** signal, not a model
// gap: it means that stat's swing has outgrown the ship at that site. It is now
// visible instead of silently corrupting the stat, which is what the map's
// stakes-tuning fog wants to see.
run_trade_can_accept :: proc(s: ^ship.Ship, trade: Stage_Trade) -> bool {
	return run_trade_stat_reading(s, trade.cost.stat) - trade.cost.amount >= run_trade_stat_floor(trade.cost.stat)
}

// run_trade_pay deducts a trade's cost. The amount is measured against the
// effective stat (run_trade_can_accept) but *paid out of the base field*, which
// is the only field a run owns — so a heavily-fitted ship can pay a cost its base
// alone couldn't cover, and the base may land negative. That is fine and
// deliberate: nothing reads the base directly, so what the ship has is still
// effective >= the floor.
//
// Spending Max HP pulls the ceiling down under current HP, so hp re-clamps to the
// new effective ceiling — the ship cannot be left holding more HP than it can now
// hold.
run_trade_pay :: proc(s: ^ship.Ship, cost: Trade_Term) {
	switch cost.stat {
	case .HP:
		s.hp -= cost.amount
	case .Max_HP:
		s.max_hp -= cost.amount
		s.hp = min(s.hp, ship.ship_effective_max_hp(s))
	case .Durability:
		s.durability -= cost.amount
	case .Speed:
		s.speed -= cost.amount
	case .Treasure:
		s.starting_treasure -= cost.amount
	}
}

// run_trade_grant applies a trade's gain. Gaining HP is a repair and so caps at
// the ship's effective max (issue #92: effective, so a +Max_HP fitting's headroom
// counts) — there is no overheal. Gaining Max HP raises the ceiling without
// filling it: it is headroom, not a repair, and the two stats stay distinct
// precisely so a roster entry can trade one for the other.
run_trade_grant :: proc(s: ^ship.Ship, gain: Trade_Term) {
	switch gain.stat {
	case .HP:
		s.hp = min(s.hp + gain.amount, ship.ship_effective_max_hp(s))
	case .Max_HP:
		s.max_hp += gain.amount
	case .Durability:
		s.durability += gain.amount
	case .Speed:
		s.speed += gain.amount
	case .Treasure:
		s.starting_treasure += gain.amount
	}
}

// run_apply_trade resolves an **accepted** Trade stage (issue #136), permanently
// swapping the trade's cost for its gain and returning a post-trade
// Ghost_Snapshot (ADR-0008) carrying the node's own stakes.
//
// Only accepting reaches here. The old run_apply_stat_trade applied on arrival —
// a Trade was "a single fixed trade-off rather than a choice", so it matched
// "no decline" and had no reject at all. Under ADR-0014 a Trade is a stage like
// any other: accept completes it, reject halts the encounter, and the Sim asks
// before anything is applied.
//
// **Cost is paid before the gain is granted**, which is load-bearing for
// Cannibalized Timbers (+HP for -Max HP): lowering the ceiling first means the repair
// caps against the ceiling the player just sold, not the one they had. Any trade
// whose two stats don't interact is unaffected by the order.
//
// Affordability is the caller's gate, not a rejection: the Sim only offers accept
// when run_trade_can_accept, so arriving here unable to pay is a driver bug.
run_apply_trade :: proc(s: ^ship.Ship, trade: Stage_Trade, site: Scaling_Site, steps: int) -> Ghost_Snapshot {
	assert(run_trade_can_accept(s, trade), "run_apply_trade on a trade the ship cannot pay for")

	run_trade_pay(s, trade.cost)
	run_trade_grant(s, trade.gain)

	return run_ghost_snapshot_of(s, steps, site)
}
