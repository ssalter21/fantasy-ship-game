package run

import "../combat"
import "../ship"

// Stage resolution: what happens when a stage the ship arrived at is applied.
// Each primitive that changes run state resolves here, mutating the player-side
// ship and nothing else. The stage's tuned magnitudes were already baked into its
// content at generation time (content.odin); this is only the arrival-time
// application. run_start_battle/run_finish_ship_battle bracket a Fight around
// core/combat, which owns the actual round resolution.
//
// **No proc here returns a Ghost_Snapshot** (issue #162, ADR-0008 as amended). It
// used to look like each one should: a stage that changes the ship is exactly the
// thing a ghost records. But a ghost is captured once per *encounter*, at the end
// of the node's walk — so an emit hanging off an apply proc is a stage-level
// cadence nobody chose, and the proc set that happened to return one (Fight,
// Trade, Reward) silently left Offer and Shop — the two stages that change the
// *build* — recording nothing at all. The Sim captures it at the one site that
// knows the walk is over (sim_walk_encounter).
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

// run_finish_ship_battle reads an ended Battle as a Fight's Stage_Outcome
// (ADR-0014) — what this battle's ending means to the encounter, which is the one
// thing a Fight has to say for itself once combat has stopped.
//
// **Leave Combat halts**: the captain took ADR-0006's Speed-gated escape, so the
// encounter ends here and nothing downstream of the Fight is reached — flee a
// [Fight, Reward] and the loot stage never fires, with no authored gate saying so.
// Every other ending completes it: victory obviously, but also a round-cap
// stalemate, and the opponent's *own* escape — Side.B fleeing is not the captain
// declining the fight, so it reads as the fight being over rather than as a halt.
//
// **The captain's own sinking is neither**, and is not asked of this proc: the
// run is over by permadeath (ADR-0006) and the walk stops dead rather than
// resolving the stage at all, so the caller checks run_can_travel before it
// consults the outcome. That gate is also what lets the payout below assume a
// Destroyed ending reaching here is the *player's* kill.
//
// **Only a wreck pays** (#159): a sunk opponent hands over its hold as it stands —
// the real cargo still stowed in its cargo slots (ship_cargo), stowed into
// the player's hold exactly like a Reward (run_apply_reward). A fled opponent and
// a round-cap stalemate pay nothing, which is why the outcome had to become
// readable off the Battle (combat's reason/winner) rather than off `escaped` alone:
// `escaped` cannot tell a clean kill from a twenty-round draw, and both complete.
// The `payout` return is the gross hold looted (0 when nothing was); the player may
// keep less, because a payout above the ship's remaining cargo capacity is lost
// (#157) — the mainline case here, since #176's flat 50% hostile fill pays 30–65
// against ~40 of headroom, so winning a Fight routinely spills cargo overboard.
//
// It used to return a Ghost_Snapshot instead, which is why it took the player's
// ship, the node's zone, and the step count it no longer needs — see the file
// header (issue #162).
run_finish_ship_battle :: proc(battle: ^combat.Battle) -> (outcome: Stage_Outcome, payout: int) {
	assert(battle.ended, "run_finish_ship_battle called before the battle ended")

	if battle.reason == .Destroyed {
		winner, has_winner := battle.winner.?
		assert(has_winner && winner == .A, "a Destroyed battle paying out must have the player (.A) as the winner")
		// The wreck is the loser (.B). This *reads* its hold and never mutates it: the
		// Fight's opponent layout aliases the map node's backing array (sim_enter_stage
		// shallow-copies Stage_Fight), so emptying it here would corrupt the stored node.
		// Heaved cargo is already gone (jettison destroys it, #159); a sinking pays only
		// what is still aboard.
		wreck := battle.ships[.B]
		payout = ship.ship_cargo(wreck^)
		player := battle.ships[.A]
		ship.ship_stow_cargo(player.layout, ship.ship_cargo(player^) + payout)
	}

	outcome = .Halted if .A in battle.escaped else .Completed
	return
}

// An Offer stage has no run-side apply proc (issue #96): unlike a Trade it
// changes no ship stat when it resolves, and unlike the retired Upgrade Offer it
// grants nothing at resolve time — picking an item opens a Refit (core/sim's
// sim_open_refit) that places it through the manual-loadout commands, and the
// old run_apply_upgrade_offer / its resolve-time Ghost_Snapshot are retired with
// the auto-replace path. The Sim marks the node resolved when the choice is made.

// run_trade_stat_floor is the lowest a stat may be left by paying a trade's cost
// (issue #136). Durability and Cargo floor at 0 — a ship with none of them is a
// valid, badly-off ship. Hull and Max Hull floor at **1**: a trade is a bargain struck
// on a menu, and sinking the ship there would hand permadeath to a stage whose
// whole job is a choice, duplicating Fight's outcome while dodging its agency.
run_trade_stat_floor :: proc(stat: Trade_Stat) -> int {
	switch stat {
	case .Hull, .Max_Hull:
		return 1
	case .Durability, .Cargo:
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
// against, so it is the number the ship truly "has". Hull is its own reading rather
// than an effective one because Ship.hull has no modifier path — fittings move the
// *ceiling* (Modify_Max_Hull), not the current value.
run_trade_stat_reading :: proc(s: ^ship.Ship, stat: Trade_Stat) -> int {
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

// run_trade_pay deducts a trade's cost. For the base-field stats the amount is
// measured against the effective stat (run_trade_can_accept) but *paid out of the
// base field*, which is the only field a run owns — so a heavily-fitted ship can
// pay a cost its base alone couldn't cover, and the base may land negative. That
// is fine and deliberate: nothing reads the base directly, so what the ship has
// is still effective >= the floor.
//
// Cargo has no base field (ADR-0020): it is the holds, so paying re-stows the
// cargo at its reduced total (ship_stow_cargo), the affordability gate having
// already guaranteed cargo >= amount.
//
// Spending Max Hull pulls the ceiling down under current Hull, so hull re-clamps to the
// new effective ceiling — the ship cannot be left holding more Hull than it can now
// hold.
run_trade_pay :: proc(s: ^ship.Ship, cost: Trade_Term) {
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

// run_trade_grant applies a trade's gain. Gaining Hull is a repair and so caps at
// the ship's effective max (issue #92: effective, so a +Max_Hull fitting's headroom
// counts) — there is no overheal. Gaining Max Hull raises the ceiling without
// filling it: it is headroom, not a repair, and the two stats stay distinct
// precisely so a roster entry can trade one for the other.
run_trade_grant :: proc(s: ^ship.Ship, gain: Trade_Term) {
	switch gain.stat {
	case .Hull:
		s.hull = min(s.hull + gain.amount, ship.ship_effective_max_hull(s))
	case .Max_Hull:
		s.max_hull += gain.amount
	case .Durability:
		s.durability += gain.amount
	case .Cargo:
		// Cargo is the holds now (ADR-0020): re-stow the raised total, so a gain
		// above capacity is lost (#157) rather than banked in a scalar field. That
		// the one Cargo-gaining axis (Scrapped Armour) can thus burn its own
		// payout — and, since cargo *is* weight, slow the ship as it pays out —
		// is the accepted, un-guarded cost of the axis, not a special case to clamp
		// (#199): the gain side stays as open as the model, the cost side alone gated.
		ship.ship_stow_cargo(s.layout, ship.ship_cargo(s^) + gain.amount)
	}
}

// run_apply_trade resolves an **accepted** Trade stage (issue #136), permanently
// swapping the trade's cost for its gain.
//
// Only accepting reaches here. The old run_apply_stat_trade applied on arrival —
// a Trade was "a single fixed trade-off rather than a choice", so it matched
// "no decline" and had no reject at all. Under ADR-0014 a Trade is a stage like
// any other: accept completes it, reject halts the encounter, and the Sim asks
// before anything is applied.
//
// **Cost is paid before the gain is granted**, which is load-bearing for
// Cannibalized Timbers (+Hull for -Max Hull): lowering the ceiling first means the repair
// caps against the ceiling the player just sold, not the one they had. Any trade
// whose two stats don't interact is unaffected by the order.
//
// Affordability is the caller's gate, not a rejection: the Sim only offers accept
// when run_trade_can_accept, so arriving here unable to pay is a driver bug.
run_apply_trade :: proc(s: ^ship.Ship, trade: Stage_Trade) {
	assert(run_trade_can_accept(s, trade), "run_apply_trade on a trade the ship cannot pay for")

	run_trade_pay(s, trade.cost)
	run_trade_grant(s, trade.gain)
}

// run_apply_reward pays a Reward stage's cargo into the ship's hold (issues
// #132, #133).
//
// The amount is not computed here — it was baked into the stage at generation
// (run_bake_stage), so this is only the application, like every other proc in this
// file.
//
// Unconditional, and that is the primitive: a Reward is a boon with nothing to
// decline, so unlike run_apply_trade there is no affordability gate to assert and
// no caller-side choice to have been made first. It always completes
// (Stage_Outcome.Completed), which is what makes [Fight, Reward] read as "win, then
// loot" with no authored gate — the halt on fleeing is Fight's, not Reward's.
run_apply_reward :: proc(s: ^ship.Ship, reward: Stage_Reward) {
	// The reward stows into the holds (ADR-0020): a payout above the ship's
	// remaining cargo capacity is lost (#157), which is the mainline case once a
	// rich ship's slots are full.
	ship.ship_stow_cargo(s.layout, ship.ship_cargo(s^) + reward.cargo)
}
