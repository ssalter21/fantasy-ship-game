package run

import "../combat"
import "../ship"

// Zone is one of the three fixed difficulty bands a Point belongs to, in a
// fixed linear order (ADR-0007, CONTEXT.md): Coastal (nearest Start) ->
// Open_Sea -> Deep (nearest Goal). Both encounter difficulty and reward
// quality scale with zone.
Zone :: enum {
	Coastal,
	Open_Sea,
	Deep,
}

// zone_tier is the single shared per-zone difficulty/reward ladder (ADR-0007
// "Consequences": placeholder values expected to move during playtesting,
// matching ADR-0006's own placeholder constants) — Coastal < Open_Sea < Deep.
// Ship Battle, Upgrade Offer, and Stat Trade each scale off this one table
// via their own PER_TIER constant below, so the three kinds land on
// distinguishable magnitudes instead of duplicating the same literal table.
zone_tier := [Zone]int{.Coastal = 1, .Open_Sea = 2, .Deep = 3}

CONTESTED_BONUS_PER_STEP :: 2
SHIP_BATTLE_HP_PER_TIER :: 10
SHIP_BATTLE_DURABILITY_PER_TIER :: 1
SHIP_BATTLE_OPPONENT_SPEED :: 5
UPGRADE_OFFER_QUALITY_PER_TIER :: 15
STAT_TRADE_DURABILITY_PER_TIER :: 8
STAT_TRADE_SPEED_COST_PER_TIER :: 1

// run_zone_scaled is the shared accessor behind every zone-scaled placeholder
// below: a kind's per_tier constant times zone's position on zone_tier.
run_zone_scaled :: proc(zone: Zone, per_tier: int) -> int {
	return zone_tier[zone] * per_tier
}

// run_ship_battle_difficulty is the game-configured opponent's HP baseline
// for a Ship Battle point (ADR-0007): rises by zone, and within a zone rises
// with port_closeness — a hand-placed "how near this zone's port" ranking
// (higher = nearer = more contested), not a computed geometric distance.
run_ship_battle_difficulty :: proc(zone: Zone, port_closeness: int) -> int {
	return run_zone_scaled(zone, SHIP_BATTLE_HP_PER_TIER) + port_closeness * CONTESTED_BONUS_PER_STEP
}

// run_ship_battle_opponent_durability is the opponent's flat incoming-damage
// reduction (core/combat's durability stat) for a Ship Battle point: like
// run_ship_battle_difficulty, rises by zone and by port_closeness, so
// "contested waters" difficulty isn't HP-pool-only (ADR-0007).
run_ship_battle_opponent_durability :: proc(zone: Zone, port_closeness: int) -> int {
	return run_zone_scaled(zone, SHIP_BATTLE_DURABILITY_PER_TIER) + port_closeness
}

// run_upgrade_offer_quality is a zone-scaled reward-quality placeholder
// (ADR-0007). Concrete meaning (what an Upgrade Offer actually grants) is
// issue #23's content, not this ticket's.
run_upgrade_offer_quality :: proc(zone: Zone) -> int {
	return run_zone_scaled(zone, UPGRADE_OFFER_QUALITY_PER_TIER)
}

// run_stat_trade_gain_durability and run_stat_trade_cost_speed are the
// zone-scaled magnitudes of a Stat Trade's two sides (ADR-0007: "bigger stat
// trades ... the deeper the zone" applies to the trade-off as a whole, not
// only the reward half — so cost_speed scales by zone too, not just
// gain_durability).
run_stat_trade_gain_durability :: proc(zone: Zone) -> int {
	return run_zone_scaled(zone, STAT_TRADE_DURABILITY_PER_TIER)
}

run_stat_trade_cost_speed :: proc(zone: Zone) -> int {
	return run_zone_scaled(zone, STAT_TRADE_SPEED_COST_PER_TIER)
}

// Point_Kind is what a Point is: the Start/home port, a per-zone Port, an
// Encounter, or the Goal. CONTEXT.md deliberately avoids "node"/"tile" here
// since Points carry no edges/adjacency (ADR-0007's open, non-node-graph
// topology).
Point_Kind :: enum {
	Start,
	Port,
	Encounter,
	Goal,
}

// run_point_is_port reports whether p functions as a port (ADR-0007: "4
// ports total: the Start/home port, plus one per zone") — true for both
// .Start (the home port) and .Port (each zone's port), so a caller doesn't
// need to special-case .Start itself just to ask "is this point a port".
run_point_is_port :: proc(p: Point) -> bool {
	return p.kind == .Start || p.kind == .Port
}

// Encounter_Kind is the type of interaction an Encounter point presents
// (ADR-0007).
Encounter_Kind :: enum {
	Ship_Battle,
	Upgrade_Offer,
	Stat_Trade,
}

// Encounter is what happens automatically on arrival at an Encounter point
// (ADR-0007: "Triggering" — no decline once arrived). Shaped as an open
// union, mirroring core/combat's Command/Event pattern, so a future kind can
// be added without restructuring callers.
Encounter :: union {
	Encounter_Ship_Battle,
	Encounter_Upgrade_Offer,
	Encounter_Stat_Trade,
}

// Encounter_Ship_Battle is a full battle against a game-configured opponent,
// resolved via core/combat's existing phased-round Battle (ADR-0006,
// ADR-0007) — this package hands off to combat.combat_battle_create rather
// than reimplementing combat. opponent's stats are a difficulty placeholder
// (run_make_opponent_ship); real PvE opponent content is issue #23.
Encounter_Ship_Battle :: struct {
	// port_closeness is a hand-placed "how near this zone's port" ranking
	// (ADR-0007's "contested waters"): higher = nearer = harder. Not a
	// computed geometric distance — Points carry no coordinates.
	port_closeness: int,
	opponent:       ship.Ship,
}

// Encounter_Upgrade_Offer is a choice among upgrade options (ADR-0007);
// picking one is a separate captain decision left to implementation
// (ADR-0007's Consequences) — this package only carries the offer's
// zone-scaled quality placeholder. Real upgrade content is issue #23.
Encounter_Upgrade_Offer :: struct {
	quality: int,
}

// Encounter_Stat_Trade is a permanent stat-for-stat/cargo trade-off
// (ADR-0007's example: +Durability for -Speed) — that concrete shape is
// modeled directly rather than as a generic stat-enum system, matching this
// slice's single hand-authored trade axis. gain_durability is the
// zone-scaled placeholder magnitude; cost_speed is a fixed placeholder.
Encounter_Stat_Trade :: struct {
	gain_durability: int,
	cost_speed:      int,
}

// Point is a single hand-placed location on the run's map (ADR-0007,
// CONTEXT.md). zone is nil for Start and Goal, which sit outside the three
// difficulty bands. encounter is set only when kind == .Encounter.
Point :: struct {
	id:        int,
	zone:      Maybe(Zone),
	kind:      Point_Kind,
	encounter: Maybe(Encounter),
}

// Map is the run's full set of hand-placed Points (ADR-0007). Points carry
// no edges/adjacency to each other: from any visited point the player may
// travel to any other point (no reachability gating beyond run_can_travel).
Map :: struct {
	points: []Point,
}

// run_make_opponent_ship turns a Ship Battle point's zone/port_closeness into
// a concrete opponent ship.Ship (placeholder mapping — real PvE opponent
// content is issue #23). hp and durability both scale by zone and
// port_closeness, so difficulty isn't HP-pool-only.
run_make_opponent_ship :: proc(zone: Zone, port_closeness: int) -> ship.Ship {
	return ship.Ship{
		hp         = run_ship_battle_difficulty(zone, port_closeness),
		durability = run_ship_battle_opponent_durability(zone, port_closeness),
		speed      = SHIP_BATTLE_OPPONENT_SPEED,
	}
}

// zone_encounter_kinds hand-places each zone's 4 Encounter points' kinds
// (ADR-0007: split 4/4/4 across the 12 total, mixed per zone rather than
// concentrated in one kind). Position within a zone (index into this array)
// also drives Ship Battle port_closeness below: index 0 sits nearest that
// zone's port.
zone_encounter_kinds := [Zone][4]Encounter_Kind{
	.Coastal  = {.Ship_Battle, .Ship_Battle, .Upgrade_Offer, .Stat_Trade},
	.Open_Sea = {.Ship_Battle, .Upgrade_Offer, .Upgrade_Offer, .Stat_Trade},
	.Deep     = {.Ship_Battle, .Upgrade_Offer, .Stat_Trade, .Stat_Trade},
}

// run_map_create builds the run's fixed hand-placed map (ADR-0007): Start
// (home port) -> Coastal -> Open_Sea -> Deep (each 1 Port + 4 Encounter
// points) -> Goal. Caller owns the returned Map.points slice.
run_map_create :: proc() -> Map {
	// id is always len(points) at the point of each append below (points are
	// appended strictly in order, one id each), so it needs no separate
	// counter — just read the slice's own length.
	points := make([dynamic]Point)

	append(&points, Point{id = len(points), kind = .Start})

	for zone in Zone {
		append(&points, Point{id = len(points), zone = zone, kind = .Port})

		for kind, position in zone_encounter_kinds[zone] {
			// index 0 is nearest the port just placed above; closeness
			// counts down from there (ADR-0007's "contested waters").
			closeness := len(zone_encounter_kinds[zone]) - 1 - position

			encounter: Encounter
			switch kind {
			case .Ship_Battle:
				encounter = Encounter_Ship_Battle{
					port_closeness = closeness,
					opponent       = run_make_opponent_ship(zone, closeness),
				}
			case .Upgrade_Offer:
				encounter = Encounter_Upgrade_Offer{quality = run_upgrade_offer_quality(zone)}
			case .Stat_Trade:
				encounter = Encounter_Stat_Trade{
					gain_durability = run_stat_trade_gain_durability(zone),
					cost_speed      = run_stat_trade_cost_speed(zone),
				}
			}

			append(&points, Point{id = len(points), zone = zone, kind = .Encounter, encounter = encounter})
		}
	}

	append(&points, Point{id = len(points), kind = .Goal})

	return Map{points = points[:]}
}

// run_start_battle triggers a Ship Battle encounter (ADR-0007): hands off to
// core/combat's existing Battle type rather than reimplementing combat.
// Caller drives the returned Battle to completion via
// combat.combat_resolve_round as normal.
run_start_battle :: proc(s: ^ship.Ship, encounter: ^Encounter_Ship_Battle) -> combat.Battle {
	return combat.combat_battle_create(s, &encounter.opponent)
}

// run_apply_stat_trade triggers a Stat Trade encounter (ADR-0007): unlike
// Upgrade Offer, a Stat Trade is a single fixed trade-off rather than a
// choice among options, so it applies immediately and permanently on
// arrival, matching "no decline" (ADR-0007's Triggering).
run_apply_stat_trade :: proc(s: ^ship.Ship, trade: Encounter_Stat_Trade) {
	s.durability += trade.gain_durability
	s.speed -= trade.cost_speed
}

// Run_Status is the run's overall outcome so far (ADR-0007's Win/loss
// conditions).
Run_Status :: enum {
	In_Progress,
	Won,
	Lost,
}

// run_status reports the run's outcome (ADR-0007): lost at 0 HP
// (permadeath) regardless of position, won by being at Goal with HP > 0,
// otherwise still in progress. HP loss itself happens in core/combat/
// core/ship; this is just the run-level read of that state.
run_status :: proc(s: ^ship.Ship, current: Point) -> Run_Status {
	if s.hp <= 0 {
		return .Lost
	}
	if current.kind == .Goal {
		return .Won
	}
	return .In_Progress
}

// run_can_travel reports whether the ship may still travel to another point
// (ADR-0007): false once HP has reached 0 — a sunk ship has already lost and
// makes no further routing choice.
run_can_travel :: proc(s: ^ship.Ship) -> bool {
	return s.hp > 0
}
