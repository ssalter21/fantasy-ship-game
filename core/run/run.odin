package run

import "../ship"
import "core:math"

// This file holds the run's shared domain data model (Zone, Node, Map, the
// Encounter variants) and the stakes scaling group — the one cohesive family
// of zone-and-depth-scaled formulas behind a shared accessor.
// The other concerns carved out of the original single module live in sibling
// files: procedural map generation (generation.odin), travel legality
// (navigation.odin), encounter resolution + ghost emission (encounter.odin),
// and the per-encounter content itself (content.odin).

// Zone is one of the three fixed stakes bands a Node belongs to, in a fixed
// linear order (CONTEXT.md): Coastal (nearest Start) -> Open_Sea -> Deep
// (nearest Goal). How much is on the line at a node scales with zone. The
// zones survive the node-graph redesign (ADR-0009, which supersedes ADR-0007's
// topology/fog) — only the map's shape and the within-zone gradient axis
// changed.
Zone :: enum {
	Coastal,
	Open_Sea,
	Deep,
}

// zone_tier is the single shared per-zone stakes ladder (placeholder values
// expected to move during playtesting) — Coastal < Open_Sea < Deep. Every
// stage primitive scales off this one table via its own PER_TIER constant
// below, so the primitives land on distinguishable magnitudes instead of
// duplicating the same literal table.
zone_tier := [Zone]int{.Coastal = 1, .Open_Sea = 2, .Deep = 3}

// The stakes gradient stacks two axes: the per-zone tier ladder above, and
// depth-within-zone — how deep into a zone's phase a node sits, normalized to a
// fixed range (DEPTH_STEPS) so the spread is consistent regardless of how many
// layers a seed happened to roll. Both feed every zone-scaled formula below via
// run_zone_depth_scaled. Depth replaces the retired Fight-only "port proximity /
// contested waters" input, and applies to every primitive.
DEPTH_STEPS :: 3

// The stakes constants below belong to **stage primitives**, not to encounter
// kinds (ADR-0014): one gradient, read differently by each primitive — Fight as
// opponent power, Offer as item quality, Trade as swing size. Grouping them by
// primitive is what lets a recipe compose stages without asking which kind of
// encounter it is. Shop and Reward have no per-tier/per-depth constants yet: a
// Shop prices by item tier (ship_item_cost), and Reward has no implementation to
// tune — both land here when they gain one.

FIGHT_OPPONENT_HP_PER_TIER :: 10
FIGHT_OPPONENT_HP_PER_DEPTH :: 3
FIGHT_OPPONENT_DURABILITY_PER_TIER :: 1
FIGHT_OPPONENT_DURABILITY_PER_DEPTH :: 1
FIGHT_OPPONENT_OFFENSE_PER_TIER :: 2
FIGHT_OPPONENT_OFFENSE_PER_DEPTH :: 1
FIGHT_OPPONENT_SPEED :: 5

OFFER_ITEM_QUALITY_PER_TIER :: 15
OFFER_ITEM_QUALITY_PER_DEPTH :: 5

TRADE_GAIN_DURABILITY_PER_TIER :: 8
TRADE_GAIN_DURABILITY_PER_DEPTH :: 2
TRADE_COST_SPEED_PER_TIER :: 1
TRADE_COST_SPEED_PER_DEPTH :: 1

// Scaling_Site is a node's position on the stakes gradient: the (zone, depth)
// pair every zone-and-depth-scaled formula below reads. It says *how much is on
// the line here* — the primitive reading it decides what that means. The two
// axes are a cohesive scaling group, so they travel as one named struct (issue
// #113) rather than as a positional int/enum pair that call sites could silently
// swap — the whole-struct idiom the Odin standards prescribe. Assembled from a
// node's zone and normalized depth: at generation time to scale its content, and
// again at battle-finish (run_finish_ship_battle) to record its stakes.
Scaling_Site :: struct {
	zone:  Zone,
	depth: int,
}

// run_zone_depth_scaled is the shared accessor behind every zone-and-depth-scaled
// placeholder below: a primitive's per_tier constant times the zone's position on
// zone_tier, plus its per_depth constant times the site's normalized
// depth-within-zone. The two axes stack, so a deep node in a zone outscales a
// shallow one, and a Deep-zone node still outscales a Coastal one.
run_zone_depth_scaled :: proc(site: Scaling_Site, per_tier: int, per_depth: int) -> int {
	return zone_tier[site.zone] * per_tier + site.depth * per_depth
}

// run_normalize_depth maps a node's raw depth (its 0-based layer index within
// its zone's phase) onto the fixed 0..DEPTH_STEPS range, so the stakes
// spread is stable no matter how many layers a particular seed rolled for
// that zone: the shallowest layer always normalizes to 0 and the deepest
// always to DEPTH_STEPS. A single-layer zone (never happens at the real node
// budget, but guarded) collapses to 0.
run_normalize_depth :: proc(raw_depth: int, zone_layer_count: int) -> int {
	if zone_layer_count <= 1 {
		return 0
	}
	fraction := f64(raw_depth) / f64(zone_layer_count - 1)
	return int(math.round(fraction * f64(DEPTH_STEPS)))
}

// The Fight primitive reads the site's stakes as opponent power, across three
// stats so a deeper fight isn't HP-pool-only: run_fight_opponent_hp is the
// opponent's HP baseline, run_fight_opponent_durability its flat
// incoming-damage reduction (core/combat's durability stat), and
// run_fight_opponent_offense its Gun Deck output bonus (issue #23). All three
// rise by zone tier and by depth-within-zone. Speed is not a stakes reading —
// FIGHT_OPPONENT_SPEED is flat.
run_fight_opponent_hp :: proc(site: Scaling_Site) -> int {
	return run_zone_depth_scaled(site, FIGHT_OPPONENT_HP_PER_TIER, FIGHT_OPPONENT_HP_PER_DEPTH)
}

run_fight_opponent_durability :: proc(site: Scaling_Site) -> int {
	return run_zone_depth_scaled(site, FIGHT_OPPONENT_DURABILITY_PER_TIER, FIGHT_OPPONENT_DURABILITY_PER_DEPTH)
}

run_fight_opponent_offense :: proc(site: Scaling_Site) -> int {
	return run_zone_depth_scaled(site, FIGHT_OPPONENT_OFFENSE_PER_TIER, FIGHT_OPPONENT_OFFENSE_PER_DEPTH)
}

// run_offer_item_quality is the Offer primitive's stakes reading: a deeper
// Offer presents stronger items than a shallow one in the same zone. It feeds
// run_item_offer_options' per-item scaling bonus (issue #96, ADR-0012).
run_offer_item_quality :: proc(site: Scaling_Site) -> int {
	return run_zone_depth_scaled(site, OFFER_ITEM_QUALITY_PER_TIER, OFFER_ITEM_QUALITY_PER_DEPTH)
}

// run_trade_gain_durability and run_trade_cost_speed are the Trade primitive's
// stakes reading — swing size, across the trade's two sides: a deeper trade is a
// bigger swing (more Durability gained, more Speed spent) than a shallow one in
// the same zone.
run_trade_gain_durability :: proc(site: Scaling_Site) -> int {
	return run_zone_depth_scaled(site, TRADE_GAIN_DURABILITY_PER_TIER, TRADE_GAIN_DURABILITY_PER_DEPTH)
}

run_trade_cost_speed :: proc(site: Scaling_Site) -> int {
	return run_zone_depth_scaled(site, TRADE_COST_SPEED_PER_TIER, TRADE_COST_SPEED_PER_DEPTH)
}

// Node_Kind is what a Node is: the Start/home port, a per-zone Port, an
// Encounter, or the Goal. Nodes are now graph nodes with edges/adjacency
// (ADR-0009), but the kind vocabulary is
// unchanged.
Node_Kind :: enum {
	Start,
	Port,
	Encounter,
	Goal,
}

// run_node_is_port reports whether p functions as a port — true for both
// .Start (the home port) and .Port (each zone's ports), so a caller doesn't
// need to special-case .Start itself just to ask "is this node a port".
run_node_is_port :: proc(p: Node) -> bool {
	return p.kind == .Start || p.kind == .Port
}

// Encounter_Kind is the type of interaction an Encounter node presents. The
// old Upgrade_Offer is repurposed as the Item_Offer (ADR-0012, issue #96): the
// encounter-kind slot in the map model is unchanged — the map still deals three
// kinds per zone — only this kind's content and behavior changed.
Encounter_Kind :: enum {
	Ship_Battle,
	Item_Offer,
	Stat_Trade,
}

// Encounter is what happens automatically on the first arrival at an
// Encounter node (no decline once arrived). Shaped as an open union,
// mirroring core/combat's Command/Event pattern, so a future kind can be
// added without restructuring callers.
Encounter :: union {
	Encounter_Ship_Battle,
	Encounter_Item_Offer,
	Encounter_Stat_Trade,
}

// ITEM_OFFER_OPTION_COUNT is how many distinct roster items an Item Offer
// presents (issue #96, ADR-0012's "presents a few distinct roster items"). The
// player picks one to place — or skips — so this is the "N" in the acceptance
// criteria. Fixed here (a small fixed array on the encounter, no allocation)
// rather than varying per node; must be <= ship.ITEM_ROSTER_SIZE so the pool can
// supply that many distinct items.
ITEM_OFFER_OPTION_COUNT :: 3

// Encounter_Ship_Battle is a full battle against a game-configured opponent,
// resolved via core/combat's existing phased-round Battle — this package
// hands off to combat.combat_battle_create rather than reimplementing combat.
// opponent's stats are a stakes placeholder (run_make_opponent_ship);
// real PvE opponent content is issue #23.
Encounter_Ship_Battle :: struct {
	// depth is this node's normalized depth-within-zone (0..DEPTH_STEPS),
	// retained so run_finish_ship_battle can rebuild the node's Scaling_Site —
	// its original stakes — without reading it off the battle-worn opponent.
	depth:    int,
	opponent: ship.Ship,
}

// Encounter_Item_Offer presents a few distinct roster items to place by hand
// (ADR-0012, issue #96) — the repurposed Upgrade Offer. `options` are the
// concrete items on offer, drawn from the roster pool and zone-and-depth-scaled
// at generation time (run_item_offer_options), so an Item Offer carries its
// items as baked content the way a Ship Battle carries its opponent, rather than
// a bare quality number resolved later. Picking one opens a Refit to place or
// swap it; the player may also skip. A fixed-size array — no owned heap, so
// run_map_destroy needs no per-offer cleanup.
Encounter_Item_Offer :: struct {
	options: [ITEM_OFFER_OPTION_COUNT]ship.Fitting,
}

// SHOP_SHELF_SIZE is how many deck cards a Port shop shows at once — the shelf
// window onto the top of the deck (#123, ADR-0013's "a shelf of the top 5").
// The deck itself is the full roster (Shop.deck); this is only how much of it is
// visible/buyable at any moment. Must stay <= ship.ITEM_ROSTER_SIZE so a full
// shelf can be drawn.
SHOP_SHELF_SIZE :: 5

// Shop_Item is one purchasable card in a Port shop (#98): the roster `fitting`
// on offer and its `cost` in treasure. Cost is stored as a plain int, priced
// once at generation from the item's Tier (ship.ship_item_cost) — tier itself
// doesn't ride along because nothing past pricing reads it, and a bare Fitting is
// what the Refit ultimately places. Buying deducts cost from the ship's
// starting_treasure and opens a Refit to place the fitting.
Shop_Item :: struct {
	fitting: ship.Fitting,
	cost:    int,
}

// Shop is a Port's persistent purchasable deck (#123, ADR-0013, amending #98):
// its own seed-baked shuffled deck of the *full* roster, each card priced by
// tier, drawn from the roster pool at generation time (run_port_shop) and carried
// as baked content the way an Item Offer carries its options. The deck is a pure
// function of the run seed (no runtime RNG), so a seed's Ports are fully
// determined before play, and each Port owns a distinct deck.
//
// A Port never "resolves" — it is a revisitable landmark whose deck is drawn down
// over the run: the shop presents a SHOP_SHELF_SIZE window off the top, buying a
// shelf card refills that slot from the next deck card, and the draw progress
// persists across visits. That draw-down state (which cards have been bought) is
// per-Port *runtime* state the Sim keeps keyed by Node — the deck itself is
// immutable baked content. A fixed-size array: no owned heap, so run_map_destroy
// needs no per-shop cleanup.
Shop :: struct {
	deck: [ship.ITEM_ROSTER_SIZE]Shop_Item,
}

// Encounter_Stat_Trade is a permanent stat-for-stat/cargo trade-off (example:
// +Durability for -Speed) — that concrete shape is modeled directly rather
// than as a generic stat-enum system, matching this slice's single
// hand-authored trade axis. Both magnitudes are zone-and-depth-scaled.
Encounter_Stat_Trade :: struct {
	gain_durability: int,
	cost_speed:      int,
}

// Node_ID identifies a node in a Map's nodes slice by position (ADR-0011:
// distinct from a plain int so a node id can't be silently swapped with a
// slot index, an option index, or a raw layer/lane offset — a mixed-up id
// becomes a compile error, not a value that plausibly indexes the wrong node).
// The run package owns this type because it owns the Map; sim aliases it
// (sim.Node_ID) so a single distinct type crosses the run/sim boundary with no
// conversion. The generator computes ids as plain int layer/lane arithmetic
// internally and converts to Node_ID only where an id is stored (Node.id,
// Map.edges) — see generation.odin.
Node_ID :: distinct int

// Node is a single node on the run's procedurally-generated map (ADR-0009).
// zone is nil for Start and Goal, which sit
// outside the three stakes bands. encounter is set only when
// kind == .Encounter; shop is set only on a .Port node (#98). layer/lane are the
// node's position in the layered forward graph — layer is its column (Start = 0,
// rising toward Goal), lane its row within that column; presentation derives
// screen coordinates from them, so Nodes still carry no screen coordinates of
// their own. depth is the node's normalized depth-within-zone (0 for
// Start/Goal). Adjacency lives on Map.edges, not on the Node.
Node :: struct {
	id:        Node_ID,
	zone:      Maybe(Zone),
	kind:      Node_Kind,
	encounter: Maybe(Encounter),
	shop:      Maybe(Shop),
	layer:     int,
	lane:      int,
	depth:     int,
}

// Map is the run's procedurally-generated node graph: the Nodes plus the
// symmetric adjacency in edges (edges[i] lists the ids of every node sharing
// an edge with node i). Travel legality is not "go anywhere" any more — it
// is derived from this adjacency plus the visited set by run_travel_options.
Map :: struct {
	nodes: []Node,
	edges: [][]Node_ID,
}

// Run_Status is the run's overall outcome so far (Win/loss conditions
// unchanged by the node-graph redesign).
Run_Status :: enum {
	In_Progress,
	Won,
	Lost,
}

// run_status reports the run's outcome: lost at 0 HP (permadeath) regardless
// of position, won by being at Goal with HP > 0, otherwise still in progress.
// HP loss itself happens in core/combat/core/ship; this is just the run-level
// read of that state.
run_status :: proc(s: ^ship.Ship, current: Node) -> Run_Status {
	if s.hp <= 0 {
		return .Lost
	}
	if current.kind == .Goal {
		return .Won
	}
	return .In_Progress
}

// run_can_travel reports whether the ship may still travel to another node:
// false once HP has reached 0 — a sunk ship has already lost and makes no
// further routing choice.
run_can_travel :: proc(s: ^ship.Ship) -> bool {
	return s.hp > 0
}
