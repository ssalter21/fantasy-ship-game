package voyage

import "../combat"
import "../ship"

// Stage resolution: the arrival-time application of each primitive that changes run
// state, mutating the player-side ship and nothing else. Magnitudes were baked into
// the stage's content at generation time (content.odin); this only applies them.
// voyage_start_battle/voyage_finish_ship_battle bracket a Fight around core/combat,
// which owns round resolution.
//
// No proc here returns a Ghost_Snapshot (ADR-0008): a ghost is captured once per
// encounter, at the end of the node's walk (sim_walk_encounter), not per stage.
//
// Which stage applies next, and whether the walk continues past it, is the
// encounter's own cursor (voyage_encounter_resolve_stage in stage.odin).

// voyage_start_battle triggers a Fight stage: hands off to core/combat's Battle.
// Caller drives the returned Battle to completion via combat.combat_resolve_round.
voyage_start_battle :: proc(s: ^ship.Ship, fight: ^Stage_Fight) -> combat.Battle {
	return combat.combat_battle_create(s, &fight.opponent)
}

// voyage_finish_ship_battle reads an ended Battle as a Fight's Stage_Outcome
// (ADR-0014) — what the battle's ending means to the encounter.
//
// Break Off halts: the captain took the Speed-gated escape (ADR-0006), so the
// encounter ends and nothing downstream of the Fight is reached — flee a
// [Fight, Reward] and the loot stage never fires. Every other ending completes it,
// including a round-cap stalemate and the opponent's *own* escape (Side.B fleeing is
// the fight being over, not the captain declining it).
//
// The captain's own sinking is neither, and is not asked of this proc: permadeath
// stops the walk dead (ADR-0006), so the caller checks voyage_can_travel before
// consulting the outcome. That gate is what lets the payout below assume a Destroyed
// ending reaching here is the player's kill.
//
// Only a wreck pays (#159): a sunk opponent's still-stowed cargo (ship_cargo) is
// stowed into the player's hold exactly like a Reward. A fled opponent and a stalemate
// pay nothing — so the outcome reads off the Battle's reason/winner, not `escaped`
// alone, which cannot tell a clean kill from a draw. `payout` is the gross hold looted;
// the player may keep less, and `spilled` is that difference — the part of the payout
// above remaining cargo capacity that was lost (#157), straight from the stow rather
// than a caller's before/after subtraction. Both are 0 for a payout-less ending.
voyage_finish_ship_battle :: proc(battle: ^combat.Battle) -> (outcome: Stage_Outcome, payout: int, spilled: int) {
	assert(battle.ended, "voyage_finish_ship_battle called before the battle ended")

	if battle.reason == .Destroyed {
		winner, has_winner := battle.winner.?
		assert(has_winner && winner == .A, "a Destroyed battle paying out must have the player (.A) as the winner")
		// The wreck is the loser (.B). This *reads* its hold and never mutates it: the
		// Fight's opponent layout aliases the map node's backing array (sim_enter_stage
		// shallow-copies Stage_Fight), so emptying it here would corrupt the stored node.
		// A sinking pays only what is still aboard — heaved cargo is already gone (#159).
		wreck := battle.ships[.B]
		payout = ship.ship_cargo(wreck^)
		player := battle.ships[.A]
		spilled = ship.ship_stow_cargo(player.layout, ship.ship_cargo(player^) + payout)
	}

	outcome = .Halted if .A in battle.escaped else .Completed
	return
}

// An Offer stage has no run-side apply proc (issue #96): it changes no ship stat when
// it resolves. Picking an item opens a Refit (core/sim's sim_open_refit) that places it
// through the manual-loadout commands; the Sim marks the node resolved on the choice.

// voyage_trade_stat_floor is the lowest a stat may be left by paying a trade's cost
// (issue #136). Durability and Cargo floor at 0 — a ship with none of them is still a
// valid ship. Hull and Max Hull floor at 1: sinking the ship on a menu would hand
// permadeath to a choice stage, duplicating Fight's outcome while dodging its agency.
voyage_trade_stat_floor :: proc(stat: Trade_Stat) -> int {
	switch stat {
	case .Hull, .Max_Hull:
		return 1
	case .Durability, .Cargo:
		return 0
	}
	unreachable()
}

// voyage_trade_stat_reading is how much of `stat` the ship currently has, for measuring
// a trade's cost against.
//
// It reads the effective stat, never the raw base field (ADR-0012): effective is the
// number combat and escape resolve against, so it is what the ship truly "has" — a
// +Durability fitting genuinely makes a Durability cost affordable. Hull reads its base
// directly because Ship.hull has no modifier path — fittings move the ceiling
// (Modify_Max_Hull), not the current value.
voyage_trade_stat_reading :: proc(s: ^ship.Ship, stat: Trade_Stat) -> int {
	switch stat {
	case .Hull:
		return s.hull
	case .Max_Hull:
		return ship.ship_effective_max_hull(s)
	case .Durability:
		return ship.ship_effective_durability(s)
	case .Cargo:
		return ship.ship_cargo(s^)
	}
	unreachable()
}

// voyage_trade_can_accept reports whether the ship can pay this trade's cost in full
// (issue #136) — the gate on the Trade stage's accept option.
//
// A trade is all or nothing: a cost the ship cannot cover is neither clamped to what it
// can afford (a clamped cost is a free lunch at the floor) nor allowed to run the stat
// negative. The trade simply cannot be accepted, and rejecting halts the stage (ADR-0014).
//
// An unaffordable trade being a dead node is a deliberate tuning signal, not a model gap:
// it means that stat's swing has outgrown the ship at that site.
voyage_trade_can_accept :: proc(s: ^ship.Ship, trade: Stage_Trade) -> bool {
	return voyage_trade_stat_reading(s, trade.cost.stat) - trade.cost.amount >= voyage_trade_stat_floor(trade.cost.stat)
}

// voyage_trade_pay deducts a trade's cost. The cost is measured against the effective
// stat (voyage_trade_can_accept) but paid out of the base field, the only field a voyage
// owns — so a heavily-fitted ship can pay a cost its base alone couldn't cover, and the
// base may land negative. That is fine: nothing reads the base directly, so effective is
// still >= the floor.
//
// Cargo has no base field (ADR-0020): it is the holds, so paying re-stows the cargo at
// its reduced total (ship_stow_cargo), the affordability gate having guaranteed cargo >=
// amount.
//
// Spending Max Hull pulls the ceiling down under current Hull, so hull re-clamps to the
// new effective ceiling — the ship cannot hold more Hull than it can now hold.
voyage_trade_pay :: proc(s: ^ship.Ship, cost: Trade_Term) {
	switch cost.stat {
	case .Hull:
		s.hull -= cost.amount
	case .Max_Hull:
		s.max_hull -= cost.amount
		s.hull = min(s.hull, ship.ship_effective_max_hull(s))
	case .Durability:
		s.durability -= cost.amount
	case .Cargo:
		ship.ship_stow_cargo(s.layout, ship.ship_cargo(s^) - cost.amount)
	}
}

// voyage_trade_grant applies a trade's gain. Gaining Hull is a repair and caps at the
// ship's effective max (a +Max_Hull fitting's headroom counts) — there is no overheal.
// Gaining Max Hull raises the ceiling without filling it: headroom, not a repair. The
// two stats stay distinct precisely so a trade can swap one for the other.
voyage_trade_grant :: proc(s: ^ship.Ship, gain: Trade_Term) {
	switch gain.stat {
	case .Hull:
		s.hull = min(s.hull + gain.amount, ship.ship_effective_max_hull(s))
	case .Max_Hull:
		s.max_hull += gain.amount
	case .Durability:
		s.durability += gain.amount
	case .Cargo:
		// Cargo is the holds (ADR-0020): re-stow the raised total, so a gain above
		// capacity is lost (#157) rather than banked. A Cargo gain can thus burn its own
		// payout — and, since cargo *is* weight, slow the ship as it pays — which is the
		// accepted, un-guarded cost: the gain side stays as open as the model, only the
		// cost side gated (#199).
		ship.ship_stow_cargo(s.layout, ship.ship_cargo(s^) + gain.amount)
	}
}

// voyage_apply_trade resolves an accepted Trade stage (issue #136), permanently swapping
// the trade's cost for its gain. Only accepting reaches here; reject halts the encounter
// (ADR-0014), and the Sim asks before anything is applied.
//
// Cost is paid before the gain is granted: for a trade whose gain caps against a ceiling
// the cost lowers (a Hull repair paid in Max Hull), lowering the ceiling first means the
// repair caps against the ceiling the player just sold, not the one they had. A trade
// whose two stats don't interact is unaffected by the order.
//
// Affordability is the caller's gate, not a rejection: the Sim only offers accept when
// voyage_trade_can_accept, so arriving here unable to pay is a driver bug.
voyage_apply_trade :: proc(s: ^ship.Ship, trade: Stage_Trade) {
	assert(voyage_trade_can_accept(s, trade), "voyage_apply_trade on a trade the ship cannot pay for")

	voyage_trade_pay(s, trade.cost)
	voyage_trade_grant(s, trade.gain)
}

// voyage_apply_reward pays a Reward stage's cargo into the ship's hold (issues #132,
// #133). The amount was baked into the stage at generation (voyage_bake_stage).
//
// Unconditional, and that is the primitive: a Reward is a boon with nothing to decline,
// so unlike voyage_apply_trade there is no affordability gate and no caller-side choice.
// It always completes, which is what makes [Fight, Reward] read as "win, then loot" — the
// halt on fleeing is Fight's, not Reward's.
voyage_apply_reward :: proc(s: ^ship.Ship, reward: Stage_Reward) {
	// The reward stows into the holds (ADR-0020): a payout above remaining cargo
	// capacity is lost (#157), the mainline case once a rich ship's slots are full.
	ship.ship_stow_cargo(s.layout, ship.ship_cargo(s^) + reward.cargo)
}
