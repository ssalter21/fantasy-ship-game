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

// SHOP_DEPTH_SURCHARGE_STEP is the per-purchase shop price surcharge (issue #124): each
// successive buy within one visit costs this much more than the last, so digging one shop
// deep is expensive and the player is pushed to compare shop against shop. A placeholder
// magnitude, not committed (ADR-0012).
SHOP_DEPTH_SURCHARGE_STEP :: 5

// voyage_shop_price is the cargo a shelf card costs, whole: its tier's base price plus the
// depth surcharge for the buys already made at this shop, `base + step × purchases`.
//
// The **entire** price rule, in one expression — a card is never quoted at a part of its
// price. `purchases` is the Sim's per-visit count (core/sim's Shop_Visit): the visit is
// state the Sim tracks, the price it implies is decided here, next to the other "can you
// afford this?" rule (voyage_trade_can_accept).
voyage_shop_price :: proc(item: ship.Roster_Item, purchases: int) -> int {
	return ship.ship_item_cost(item.tier) + SHOP_DEPTH_SURCHARGE_STEP * purchases
}

// voyage_shop_option prices one stock card into the option a shop presents — the only way
// a priced Stage_Option is made, so the shelf's shown price and the buy's charge read one
// number.
voyage_shop_option :: proc(item: ship.Roster_Item, purchases: int) -> Stage_Option {
	return Stage_Option{fitting = item.fitting, cost = voyage_shop_price(item, purchases)}
}

// voyage_offer_option wraps one of an Offer's baked items as a **free** option: an Offer's
// cost is the halt it takes to refuse, not cargo (ADR-0012).
voyage_offer_option :: proc(fitting: ship.Fitting) -> Stage_Option {
	return Stage_Option{fitting = fitting}
}

// voyage_option_can_afford reports whether the ship can pay for a presented option — the
// Shop counterpart of voyage_trade_can_accept, and the gate on taking one.
//
// A free option is affordable outright: nil cost means there is no price to check, not a
// price of 0. A priced one is measured against the hold (ADR-0020 — money *is* the cargo),
// and an unaffordable card cannot be bought at all (ADR-0012): the price is never clamped
// to what the ship happens to be carrying.
voyage_option_can_afford :: proc(s: ^ship.Ship, option: Stage_Option) -> bool {
	cost, priced := option.cost.?
	if !priced {
		return true
	}
	return ship.ship_cargo(s^) >= cost
}

// voyage_option_charge deducts a taken option's price from the hold, reporting whether
// anything was spent — false for a free option, which has nothing to pay.
//
// Cargo has no base field (ADR-0020): it is the holds, so paying re-stows the cargo at its
// reduced total, the affordability gate having guaranteed cargo >= cost. Like
// voyage_apply_trade, affordability is the caller's gate and not a rejection here: arriving
// unable to pay is a driver bug.
voyage_option_charge :: proc(s: ^ship.Ship, option: Stage_Option) -> (spent: bool) {
	cost, priced := option.cost.?
	if !priced {
		return false
	}
	assert(voyage_option_can_afford(s, option), "voyage_option_charge on an option the ship cannot afford")

	ship.ship_stow_cargo(s.layout, ship.ship_cargo(s^) - cost)
	return true
}

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

// Trade_Reading is one card's stat before the swap and after it (#310/#318): the pair the
// Trade view renders as `before → after`. Computed Sim-side, where reading effective stats is
// free, so the view draws the projection straight from Event_Trade_Presented rather than
// recomputing the ship. `after` is the truthful post-swap figure: a Cargo gain clamps at
// capacity so #157 overflow shows as an after that can't reach before+amount, a Hull repair
// caps against the ceiling a Max-Hull cost just lowered, and an unaffordable cost's after sits
// below its floor (voyage_trade_stat_floor) — exactly the below-floor read the give card wants.
Trade_Reading :: struct {
	before: int,
	after:  int,
}

// voyage_trade_project computes both cards' before→after readings for the Trade view. It does
// not mutate the ship and does not run voyage_apply_trade — Ship.layout is a shared slice, so a
// value-copy would still stow into the real holds, and apply asserts on an unaffordable trade
// this must still project. Each side is figured from the effective readings and the swap's own
// rules: the cost (give) side simply loses its amount and is allowed below the floor (so an
// unaffordable trade shows the give card dipping under it); the gain (get) side adds its amount
// and then clamps the way voyage_trade_grant would — a Hull repair against the ceiling the
// Max-Hull cost lowers, a Cargo gain against capacity (surfacing #157).
voyage_trade_project :: proc(s: ^ship.Ship, trade: Stage_Trade) -> (cost, gain: Trade_Reading) {
	cost.before = voyage_trade_stat_reading(s, trade.cost.stat)
	cost.after = cost.before - trade.cost.amount

	gain.before = voyage_trade_stat_reading(s, trade.gain.stat)
	switch trade.gain.stat {
	case .Hull:
		// A repair caps against the ceiling — lowered first if the cost is paid in Max Hull,
		// mirroring voyage_apply_trade's pay-before-grant order.
		ceiling := ship.ship_effective_max_hull(s)
		if trade.cost.stat == .Max_Hull {
			ceiling -= trade.cost.amount
		}
		gain.after = min(gain.before + trade.gain.amount, ceiling)
	case .Cargo:
		// A gain above the holds' capacity is lost (#157), so the after stalls at capacity.
		gain.after = min(gain.before + trade.gain.amount, ship.ship_cargo_capacity(s^))
	case .Max_Hull, .Durability:
		gain.after = gain.before + trade.gain.amount
	}
	return
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
