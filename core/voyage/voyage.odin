package voyage

import "../ship"
import "core:math"

// This file holds the voyage's shared domain data model (Zone, Node, Map) and the
// stakes scaling group — the one cohesive family of zone-and-depth-scaled formulas
// behind a shared accessor. Sibling files hold the rest: the encounter stage model
// (stage.odin), procedural map generation (generation.odin), travel legality
// (navigation.odin), encounter resolution + ghost emission (encounter.odin), and the
// per-stage content itself (content.odin).

// Zone is one of the three fixed stakes bands a Node belongs to, in fixed linear
// order (CONTEXT.md): Coastal (nearest Start) -> Open_Sea -> Deep (nearest Haven).
// How much is on the line at a node scales with zone.
Zone :: enum {
	Coastal,
	Open_Sea,
	Deep,
}

// zone_tier is the single shared per-zone stakes ladder (placeholder values) —
// Coastal < Open_Sea < Deep. Every stage primitive scales off this one table via its
// own PER_TIER constant below, so the primitives land on distinguishable magnitudes
// instead of duplicating the same literal table.
zone_tier := [Zone]int{.Coastal = 1, .Open_Sea = 2, .Deep = 3}

// The stakes gradient stacks two axes: the per-zone tier ladder above, and
// depth-within-zone — how deep into a zone's phase a node sits, normalized to a fixed
// range (DEPTH_STEPS) so the spread is consistent regardless of how many layers a seed
// rolled. Both feed every zone-scaled formula below via voyage_zone_depth_scaled.
DEPTH_STEPS :: 3

// The stakes constants below belong to **stage primitives**, not encounter kinds
// (ADR-0014): one gradient, read differently by each primitive — Fight as opponent
// power, Offer as item quality, Trade as swing size, Reward as cargo. Grouping them by
// primitive is what lets a recipe compose stages without asking which kind of encounter
// it is. Shop has no per-tier/per-depth constants: it prices by item tier
// (ship_item_cost), and lands here if that stops being enough.

// Fight's opponent-Hull and durability baselines, scaled by tier and depth via
// voyage_fight_opponent_hull/_durability below. Hull is denominated against
// ship.STARTING_HULL (ADR-0017): sized so a hostile's pool lasts past the escape gate at
// BASELINE_ROUND_COUNT rather than dropping before Break Off can be reached.
FIGHT_OPPONENT_HULL_PER_TIER :: 40
FIGHT_OPPONENT_HULL_PER_DEPTH :: 12
FIGHT_OPPONENT_DURABILITY_PER_TIER :: 1
FIGHT_OPPONENT_DURABILITY_PER_DEPTH :: 1

// The power reading is a **percent**, not a bonus — the one reading in this group that
// multiplies rather than adds (ADR-0019). Every other primitive's reading is a quantity
// the site *grants* (cargo, item quality, a swing), so zero is a coherent floor and
// adding is the whole of it. A hostile is not granted: it arrives already authored, and
// the site decides **how much of it lands here** — which only a multiplier can express,
// an additive bonus cannot say "less than what was authored".
//
// A multiplier is proportional to tier, so PER_TIER *is* the Coastal factor and Open Sea
// lands on twice it: 50 means the roster is authored at **Open Sea weight** — met as its
// entry describes it in the middle zone, at half that in the Coastal shallows, and half
// again on top in The Deep. That is a claim the roster can be read against
// (hostile_roster's band note).
FIGHT_OPPONENT_POWER_PERCENT_PER_TIER :: 50
FIGHT_OPPONENT_POWER_PERCENT_PER_DEPTH :: 5

OFFER_ITEM_QUALITY_PER_TIER :: 15
OFFER_ITEM_QUALITY_PER_DEPTH :: 5

// The Trade primitive's stakes constants are **per tradeable stat** (Trade_Stat), not
// per trade: a Trade is a roster entry naming two stats (content.odin's Trade_Axis) and
// each side's magnitude is that stat's swing at this site. Indexed by what is traded,
// the table is the trade **exchange rate** that keeps every roster entry consistently
// priced from one place — authoring a new axis is naming two stats, not inventing two
// more constants.
//
// The rows are **ratios, not independent knobs**: unlike every other primitive's
// reading, a row is only meaningful against the others. They are anchored to the item
// roster (ADR-0012 prices each stat in cargo by tier), so zone_tier's 1/2/3 is that
// ladder read off — one swing at zone tier N is one tier-N stat fitting. Hull has no
// anchor, because nothing in the game heals and so nothing prices a repair: it keeps
// twice Max Hull's relationship, since a permanent ceiling outweighs one-off repair.
// Cargo is anchored the other way, to Reward's payout (#133), and quotes a known
// residual against the rest (#124's business, not this table's).
//
// **No PER_DEPTH row, and adding one would break the rate.** A swing must be payable out
// of the stat, and Durability is costed against a starting Durability of 2 — its Coastal
// swing can be at most 2, but depth spans DEPTH_STEPS, so any per-depth constant adds 3
// across a zone, wider than the stat itself. One frozen row freezes the table: a rate is
// only a rate if every row scales together. Trade keeps its gradient in the tier ladder's
// 3x spread; voyage_trade_swing takes a Zone, not a Scaling_Site, for the same reason.
TRADE_SWING_HULL_PER_TIER :: 16
TRADE_SWING_MAX_HULL_PER_TIER :: 8
TRADE_SWING_DURABILITY_PER_TIER :: 1
TRADE_SWING_CARGO_PER_TIER :: 15

// The Reward primitive's stakes constant is its cargo payout (issue #132) — the whole of
// what a Reward grants. Anchored against the Cargo swing above and deliberately a little
// higher: the swing is the price a stat fetches when sold, so quoting the payout against
// it makes "is looting worth it" a question with an answer. It pays **more** than selling
// a stat because a Reward is usually earned by a risking stage (a Fight risks the voyage),
// and a payout that undercut the safest way to raise money would make [Fight, Reward] a
// worse bargain. Kept as its own constants rather than derived from the swing, because a
// primitive owns its stakes constants (ADR-0014) and tuning one must not move the other.
REWARD_CARGO_PER_TIER :: 20
REWARD_CARGO_PER_DEPTH :: 5

// Scaling_Site is a node's position on the stakes gradient: the (zone, depth) pair every
// zone-and-depth-scaled formula below reads. It says *how much is on the line here* — the
// primitive reading it decides what that means. The two axes travel as one named struct
// (issue #113) rather than a positional int/enum pair that call sites could silently swap
// — the whole-struct idiom the Odin standards prescribe. Assembled at generation time to
// scale a node's content, and again as the node's walk finishes (sim_current_site) to
// record its stakes on the encounter's Ghost_Snapshot.
Scaling_Site :: struct {
	zone:  Zone,
	depth: int,
}

// voyage_zone_depth_scaled is the shared accessor behind every zone-and-depth-scaled
// placeholder below: a primitive's per_tier constant times the zone's position on
// zone_tier, plus its per_depth constant times the site's normalized
// depth-within-zone. The two axes stack, so a deep node in a zone outscales a
// shallow one, and a Deep-zone node still outscales a Coastal one.
voyage_zone_depth_scaled :: proc(site: Scaling_Site, per_tier: int, per_depth: int) -> int {
	return zone_tier[site.zone] * per_tier + site.depth * per_depth
}

// voyage_normalize_depth maps a node's raw depth (its 0-based layer index within its
// zone's phase) onto the fixed 0..DEPTH_STEPS range, so the stakes spread is stable no
// matter how many layers a particular seed rolled: the shallowest layer normalizes to 0
// and the deepest to DEPTH_STEPS. A single-layer zone (guarded, never happens at the real
// node budget) collapses to 0.
voyage_normalize_depth :: proc(raw_depth: int, zone_layer_count: int) -> int {
	if zone_layer_count <= 1 {
		return 0
	}
	fraction := f64(raw_depth) / f64(zone_layer_count - 1)
	return int(math.round(fraction * f64(DEPTH_STEPS)))
}

// The Fight primitive reads the site's stakes as opponent power across three stats, so a
// deeper fight isn't Hull-pool-only: voyage_fight_opponent_hull is the opponent's Hull
// baseline, voyage_fight_opponent_durability its flat incoming-damage reduction
// (core/combat's durability stat), and voyage_fight_opponent_power the percent its
// archetype's output is scaled to (issue #23). All three rise by zone tier and by
// depth-within-zone.
//
// These three are the whole of what stakes says about a hostile. Its loadout is its
// **archetype's** (content.odin's Hostile_Archetype) and its Speed derives from that
// loadout's weight (ADR-0020) — neither is a site reading, so the site decides how much
// hostile there is and the roster decides which one it is.
voyage_fight_opponent_hull :: proc(site: Scaling_Site) -> int {
	return voyage_zone_depth_scaled(site, FIGHT_OPPONENT_HULL_PER_TIER, FIGHT_OPPONENT_HULL_PER_DEPTH)
}

voyage_fight_opponent_durability :: proc(site: Scaling_Site) -> int {
	return voyage_zone_depth_scaled(site, FIGHT_OPPONENT_DURABILITY_PER_TIER, FIGHT_OPPONENT_DURABILITY_PER_DEPTH)
}

// voyage_fight_opponent_power is a **percent** — 100 means "the archetype exactly as
// authored" — where the other two readings are quantities (see the constant above).
voyage_fight_opponent_power :: proc(site: Scaling_Site) -> int {
	return voyage_zone_depth_scaled(site, FIGHT_OPPONENT_POWER_PERCENT_PER_TIER, FIGHT_OPPONENT_POWER_PERCENT_PER_DEPTH)
}

// voyage_offer_item_quality is the Offer primitive's stakes reading: a deeper Offer
// presents stronger items than a shallow one in the same zone. It feeds
// voyage_item_offer_options' per-item scaling bonus (issue #96, ADR-0012).
voyage_offer_item_quality :: proc(site: Scaling_Site) -> int {
	return voyage_zone_depth_scaled(site, OFFER_ITEM_QUALITY_PER_TIER, OFFER_ITEM_QUALITY_PER_DEPTH)
}

// voyage_trade_swing is the Trade primitive's stakes reading: how much of `stat` one
// swing is worth in this zone. A Deep trade is a bigger swing than a Coastal one, on
// *both* sides, since a trade's gain and cost are each a swing of their own stat read off
// the same zone. Keyed by stat rather than by side, one proc answers for every roster
// entry — gain and cost are the same question asked twice.
//
// It takes a Zone rather than a Scaling_Site because Trade reads half the gradient: the
// swing table is an exchange rate with no room for a depth axis (see TRADE_SWING_* above,
// where the depth axis would span more than a starting ship's entire Durability), so a
// `site` here would be a parameter the proc had to ignore.
voyage_trade_swing :: proc(zone: Zone, stat: Trade_Stat) -> int {
	switch stat {
	case .Hull:
		return zone_tier[zone] * TRADE_SWING_HULL_PER_TIER
	case .Max_Hull:
		return zone_tier[zone] * TRADE_SWING_MAX_HULL_PER_TIER
	case .Durability:
		return zone_tier[zone] * TRADE_SWING_DURABILITY_PER_TIER
	case .Cargo:
		return zone_tier[zone] * TRADE_SWING_CARGO_PER_TIER
	}
	unreachable()
}

// voyage_reward_cargo is the Reward primitive's stakes reading: the cargo a Reward at
// this site pays out (issue #132). A Deep reward outweighs a Coastal one, and a deeper
// node in a zone outpays a shallower one.
//
// It reads **this node's own site and nothing else** — in particular not the opponent a
// preceding Fight staged. Reading the neighbour would couple Reward to Fight and leave
// [Offer, Reward] undefined, since there is no opponent there to count; a primitive that
// reads the stage before it stops working the moment it is composed differently, which is
// the whole thing composable stages exist to avoid.
voyage_reward_cargo :: proc(site: Scaling_Site) -> int {
	return voyage_zone_depth_scaled(site, REWARD_CARGO_PER_TIER, REWARD_CARGO_PER_DEPTH)
}

// Node_Kind is what a Node is: the Start, an Encounter, or the Haven (ADR-0014). Start
// and Haven are genuine landmarks — fixed, terminal, carrying no encounter — a fact about
// a node's place in the graph that nothing in a stage list can express, and the reason
// the kind survives at all. It carries no content of any kind; there is no Port kind (a
// port is a node dealt the [Shop] recipe like any other).
Node_Kind :: enum {
	Start,
	Encounter,
	Haven,
}

// Node_ID identifies a node in a Map's nodes slice by position (ADR-0011): distinct from
// a plain int so a node id can't be silently swapped with a slot index, an option index,
// or a raw layer/lane offset — a mixed-up id becomes a compile error, not a value that
// plausibly indexes the wrong node. The voyage package owns this type because it owns the
// Map; sim aliases it (sim.Node_ID) so a single distinct type crosses the boundary with
// no conversion. The generator computes ids as plain int layer/lane arithmetic internally
// and converts to Node_ID only where an id is stored (Node.id, Map.edges) — see
// generation.odin.
Node_ID :: distinct int

// Node is a single node on the voyage's procedurally-generated map (ADR-0009). zone is
// nil for Start and Haven, which sit outside the three stakes bands. encounter is set on
// every node that holds content and nil on the Start/Haven landmarks, which hold none.
// layer/lane are the node's position in the layered forward graph — layer is its column
// (Start = 0, rising toward Haven), lane its row within that column; presentation derives
// screen coordinates from them, so Nodes carry none of their own. depth is the node's
// normalized depth-within-zone (0 for Start/Haven). Adjacency lives on Map.edges, not on
// the Node.
Node :: struct {
	id:        Node_ID,
	zone:      Maybe(Zone),
	kind:      Node_Kind,
	encounter: Maybe(Encounter),
	layer:     int,
	lane:      int,
	depth:     int,
}

// Map is the voyage's procedurally-generated node graph: the Nodes plus the symmetric
// adjacency in edges (edges[i] lists the ids of every node sharing an edge with node i).
// Travel legality derives from this adjacency plus the visited set, via
// voyage_travel_options.
Map :: struct {
	nodes: []Node,
	edges: [][]Node_ID,
}

// Voyage_Status is the voyage's overall outcome so far.
Voyage_Status :: enum {
	In_Progress,
	Won,
	Lost,
}

// voyage_status reports the voyage's outcome: lost at 0 Hull (permadeath) regardless of
// position, won by being at Haven with Hull > 0, otherwise still in progress. Hull loss
// itself happens in core/combat and core/ship; this is just the voyage-level read of that
// state.
voyage_status :: proc(s: ^ship.Ship, current: Node) -> Voyage_Status {
	if s.hull <= 0 {
		return .Lost
	}
	if current.kind == .Haven {
		return .Won
	}
	return .In_Progress
}

// voyage_can_travel reports whether the ship may still travel to another node: false once
// Hull has reached 0 — a sunk ship has already lost and makes no further routing choice.
voyage_can_travel :: proc(s: ^ship.Ship) -> bool {
	return s.hull > 0
}
