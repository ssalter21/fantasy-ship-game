package run

import "../ship"
import "core:math"

// This file holds the run's shared domain data model (Zone, Node, Map) and the
// stakes scaling group — the one cohesive family of zone-and-depth-scaled
// formulas behind a shared accessor. The other concerns carved out of the
// original single module live in sibling files: the encounter stage model an
// Encounter node holds (stage.odin), procedural map generation
// (generation.odin), travel legality (navigation.odin), encounter resolution +
// ghost emission (encounter.odin), and the per-stage content itself
// (content.odin).

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
// contested waters" input, and applies to every stage primitive.
DEPTH_STEPS :: 3

// The stakes constants below belong to **stage primitives**, not to encounter
// kinds (ADR-0014): one gradient, read differently by each primitive — Fight as
// opponent power, Offer as item quality, Trade as swing size, Reward as treasure.
// Grouping them by primitive is what lets a recipe compose stages without asking
// which kind of encounter it is. Shop still has no per-tier/per-depth constants:
// it prices by item tier (ship_item_cost), and lands here if that stops being
// enough.

// Scaled x4 with ship.STARTING_HP by #151 (ADR-0017), keeping the same shape. A
// Coastal hostile used to hold 10 HP against the player's 20 — *half* — so it died
// in 2-3 rounds, which is how every fight in the game managed to end before the
// escape gate at BASELINE_ROUND_COUNT and leave Leave Combat unreachable. See
// STARTING_HP for why the pool had to grow rather than the damage shrink.
FIGHT_OPPONENT_HP_PER_TIER :: 40
FIGHT_OPPONENT_HP_PER_DEPTH :: 12
FIGHT_OPPONENT_DURABILITY_PER_TIER :: 1
FIGHT_OPPONENT_DURABILITY_PER_DEPTH :: 1

// The offense reading kept its pre-roster values (#135), and that is a property
// rather than an accident: it is a hostile's **total** offensive uplift, shared out
// across whatever Offensive fittings its archetype carries (run_fit_hostile_loadout),
// so it means the same thing it did when the one opponent template had exactly one
// Upgraded Gun Deck to spend it on. An archetype with a single gun reproduces the
// retired template's numbers exactly. Had the bonus gone per-fitting instead, these
// two constants would have had to be retuned against the *average gun count* of the
// roster — i.e. re-tuned again every time an entry was authored.
FIGHT_OPPONENT_OFFENSE_PER_TIER :: 2
FIGHT_OPPONENT_OFFENSE_PER_DEPTH :: 1

// FIGHT_OPPONENT_SPEED is **gone** (#135) — a hostile's Speed is its archetype's
// (content.odin's Hostile_Archetype.speed), not the site's. It was never a stakes
// reading; the comment below said so while the constant sat in this group anyway.
// Pinned flat at 5 against a starting player's 4, it also meant every hostile in the
// game was escape-eligible at the baseline round and none could ever be escaped
// from.

OFFER_ITEM_QUALITY_PER_TIER :: 15
OFFER_ITEM_QUALITY_PER_DEPTH :: 5

// The Trade primitive's stakes constants are **per tradeable stat**, not per
// trade (issue #136). A Trade is no longer one welded +Durability/-Speed axis
// with a constant for each of its two sides; it is a roster entry naming two
// stats (content.odin's Trade_Axis), and each side's magnitude is that stat's
// swing at this site. So the table below is indexed by what is being traded
// rather than by which side of which trade it sits on: one swing of Durability
// costs one swing of Speed because a swing is the unit both are quoted in.
//
// That makes this table the trade **exchange rate**, and it is what keeps N
// stats' worth of roster entries consistently priced against each other from one
// place — authoring a new axis is naming two stats, never inventing two more
// constants. It also means every axis is one swing for one swing: there is
// deliberately no per-entry multiplier to author a deliberately-greedy or
// generous trade. Nothing has asked for one yet, and a weight field can be added
// to Trade_Axis later without restructuring a single caller.
//
// # A swing is one of the zone's stat fittings (issue #146)
//
// These are the one group in this file whose constants are **not independent**.
// Every other primitive's reading answers only to itself — if a hostile's HP is
// too low, raise it. A rate table is a set of *ratios*, so a row can only be read
// against the other rows, and the anchor they are all read against is the item
// roster: ADR-0012 already prices each stat in treasure, by tier, and a Shop is
// where a captain actually converts one into the other. That price list says a
// point of Durability and a point of Speed cost exactly the same (Iron Plating
// +1 Durability and Spare Rigging +1 Speed are both Splash, both 10; Reinforced
// Hull +2 and Copper Sheathing +2 are both Shallow, both 25; Dragon Turtle +3 and
// Enchanted Keel +3 are both Deep, both 45), and that a point of Max HP is worth
// about half of either (Salt Provisions +2 Max HP for the same 10).
//
// zone_tier's 1/2/3 is that same ladder, so the table below is the ladder read
// off: **one swing at zone tier N is one tier-N stat fitting.** Coastal trades in
// Iron Plating and Spare Rigging (1) and Salt Provisions (2); The Deep trades in
// Dragon Turtle and Enchanted Keel (3) and Treasure Vault (6). That is what makes
// a bargain legible as well as fair — a Deep trade moves a Deep item's worth of
// stat — and it hands a Trade its reason to exist next to a Shop, since it quotes
// the shop's price and **costs no slot**.
//
// Durability's 8 was the one row that lied, and its provenance is the whole
// explanation: it was the *gain* side of the welded axis, where being generous was
// the point, while Speed's 1 was the *cost* side, where being honest was. A welded
// axis only ever has to work in one direction, so exactly one of its two rows had
// to be wrong the moment #136 let a roster entry run it backwards. Eight points of
// Durability is not a fitting, it is an armoured fleet — 96 treasure of armour on a
// starting purse of 50 — so Stripped Spars and Scrapped Armour could never be paid.
//
// # Why no PER_DEPTH row (issue #146)
//
// There isn't one, and this is arithmetic rather than taste. A swing has to be
// payable out of the stat, and the roster costs Durability (Stripped Spars,
// Scrapped Armour) against a **starting Durability of 2**. So Durability's Coastal
// swing can be at most 2 — and since depth spans DEPTH_STEPS, any per-depth
// constant at all adds 3 across a zone, more than the entire stat. **The depth axis
// is wider than the stat it would scale.** Durability's row is therefore pinned to
// tier alone; the two rows must then match (see below), which pins Speed; and a
// rate is only a rate if every row scales together, which pins the rest. One
// frozen row freezes the table.
//
// Dropping it is a repair, not a loss. With per-tier and per-depth as independent
// knobs the table quoted a *different rate at every depth*: Lightened Hold swapped
// 1 Speed for 2 Max HP at the top of Coastal (fair) and 4 Speed for 5 Max HP at
// the bottom of it (a 1.75x gift), for the same named bargain, invisibly. Now every
// row is `tier x rate`, so the ratios between stats are the same at all twelve
// sites by construction — one rate, not twelve, which is the only thing an exchange
// rate can mean. Trade keeps a real gradient in the tier ladder's 3x spread; what
// it loses is the half of the gradient it had no room for.
//
// **Durability and Speed must be equal, not merely close.** The roster authors
// Braced Bulkheads (+Durability for -Speed) and Stripped Spars (its exact inverse)
// on purpose — "the entry that proves the axis is a space and not a point". An
// inverse pair makes any inequality between two rows a permanent verdict: quote
// Speed above Durability and Spars is free value while Bulkheads is a trap that
// exists to be rejected, at every site, forever. The shop's price list happens to
// say the same thing, so this is a discovered equality rather than a chosen one.
//
// The residue: a Deep Durability swing is 3 against a bare hull's 2, so the two
// Durability-costing entries need a single Iron Plating (10 treasure, the cheapest
// item in the game) before The Deep will take them. That is content, not a dead
// node — you cannot strip armour you never bought — and it is the last of the
// starting-Durability-of-2 problem, which is combat's band to widen (#151) and not
// this table's. If Durability ever gets a range, this table gets a resolution finer
// than a zone, and the depth axis becomes expressible again.
//
// HP is the one row with no anchor, because nothing else in the game heals and so
// nothing prices a repair. It keeps #136's authored relationship instead — twice
// Max HP's, since a point of permanent ceiling is worth more than a point of
// one-off repair — which Cannibalized Timbers spends as a flat 2 HP per Max HP at
// every zone. Treasure keeps its 15: it is anchored the other way, to Reward's
// payout (#133's `a_reward_outpays_selling_a_stat_at_the_same_site`), and the
// item ladder's own non-linearity (10/25/45 against zone_tier's 1/2/3) is economy
// tuning this map rules out of scope. That leaves Treasure quoting ~1.36x the
// other rows at Coastal and meeting them exactly at The Deep — the known residual,
// and #124's business rather than this table's.
//
// # The two HP rows moved x4 with the HP scale (issue #151)
//
// **Derived by the rule above, not retuned.** ADR-0017 raised ship.STARTING_HP 20 ->
// 100, and everything denominated in HP followed — including the roster's four
// Modify_Max_HP items (Salt Provisions 2->8, Ship's Surgeon 4->16, Treasure Vault
// 6->24, Titan's Heart 8->32). A swing at zone tier N is one tier-N stat fitting, so
// Max HP's row is still read straight off that price list: 8/16/24 against Salt
// Provisions, Ship's Surgeon and Treasure Vault, exactly as 2/4/6 was before. HP's
// row keeps its "twice Max HP's" relationship for the same reason it always had it.
// The other three rows are untouched — Durability and Speed are denominated in raw
// damage, Treasure in treasure, and neither scale moved.
//
// **#151 did not reopen the depth axis**, contrary to what the note above hoped:
// the band widened through the buff fold and the HP scale rather than through
// Durability, whose base is still 2. So there is still nothing finer than a zone to
// express a depth step in, and the axis stays deleted.
TRADE_SWING_HP_PER_TIER :: 16
TRADE_SWING_MAX_HP_PER_TIER :: 8
TRADE_SWING_DURABILITY_PER_TIER :: 1
TRADE_SWING_SPEED_PER_TIER :: 1
TRADE_SWING_TREASURE_PER_TIER :: 15

// The Reward primitive's stakes constants are its treasure payout (issue #132) —
// the whole of what a Reward is tuned by, since treasure is the whole of what it
// grants. #130 recorded that "Reward has nothing to tune" and left it out of this
// group; that held only while the primitive was an empty arm, and #132 superseded
// it by giving Reward something to grant.
//
// Anchored against the Treasure *swing* above, and deliberately a little above it:
// the swing is the price a stat fetches when sold (run_trade_swing is the exchange
// rate between stats), so quoting the payout against it is what makes "is looting
// worth it" a question with an answer. It pays **more** than selling a stat because
// a Reward is usually earned by whatever stage precedes it — a Fight risks the run,
// a Trade only costs a stat — and a payout that undercut the safest way to raise
// money would make [Fight, Reward] a worse Bargain. Kept as its own constants rather
// than derived from the swing, because a primitive owns its stakes constants
// (ADR-0014) and tuning one must not silently move the other.
//
// Placeholders on the same footing as every constant in this group. For scale: at
// the starting purse of 50 against item costs of 10/25/45, a Coastal reward is a
// Small item and a Deep one is a Large item with change — which is the point of
// #132's answer, since a Shop stage the player cannot afford to meet is a worse
// Offer.
REWARD_TREASURE_PER_TIER :: 20
REWARD_TREASURE_PER_DEPTH :: 5

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
// run_fight_opponent_offense the bonus added to each of its Offensive fittings
// (issue #23; #135 made it per-fitting when the one Gun Deck became a roster
// loadout). All three rise by zone tier and by depth-within-zone.
//
// These three are the whole of what stakes says about a hostile. Its Speed and its
// loadout are its **archetype's** (content.odin's Hostile_Archetype) — the two axes
// are independent, so the site decides how much hostile there is and the roster
// decides which one it is.
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

// run_trade_swing is the Trade primitive's stakes reading: how much of `stat` one
// swing is worth in this zone. A Deep trade is a bigger swing (more Durability
// gained, more Speed spent) than a Coastal one — on *both* sides, since a trade's
// gain and cost are each a swing of their own stat read off the same zone.
//
// This is the whole of the Trade primitive's stakes reading: it replaces
// run_trade_gain_durability / run_trade_cost_speed, which existed only because
// the axis was welded into Stage_Trade and each side therefore had exactly one
// stat it could ever be. Keyed by stat rather than by side, one proc answers for
// every roster entry, and gain and cost are the same question asked twice.
//
// **It takes a Zone rather than a Scaling_Site, and that is the point** — Trade
// reads half the gradient, so it is handed half. The swing table is an exchange
// rate and a rate has no room for a second axis (see TRADE_SWING_* above: the
// depth axis spans more than a starting ship's entire Durability), so a `site`
// here would be a parameter this proc had to ignore. run_bake_shop set the
// precedent in #137 by taking no site at all; this is the same argument one notch
// weaker. It is also what makes the decision unbreakable rather than a row of
// zeroes someone could refill: there is no depth to read.
run_trade_swing :: proc(zone: Zone, stat: Trade_Stat) -> int {
	switch stat {
	case .HP:
		return zone_tier[zone] * TRADE_SWING_HP_PER_TIER
	case .Max_HP:
		return zone_tier[zone] * TRADE_SWING_MAX_HP_PER_TIER
	case .Durability:
		return zone_tier[zone] * TRADE_SWING_DURABILITY_PER_TIER
	case .Speed:
		return zone_tier[zone] * TRADE_SWING_SPEED_PER_TIER
	case .Treasure:
		return zone_tier[zone] * TRADE_SWING_TREASURE_PER_TIER
	}
	unreachable()
}

// run_reward_treasure is the Reward primitive's stakes reading: the treasure a
// Reward at this site pays out (issue #132). A Deep reward outweighs a Coastal
// one, and a deeper node in a zone outpays a shallower one.
//
// It reads **this node's own site and nothing else** — in particular not the
// opponent a preceding Fight staged. Reading the neighbour would couple Reward to
// Fight and leave `[Offer, Reward]` undefined, since there is no opponent there to
// count; a primitive that reads the stage before it stops working the moment it is
// composed differently, which is the whole thing composable stages exist to avoid.
// The opponent's "Spoils" cargo (run_fit_pve_opponent_loadout) stays flavour until
// #143 makes treasure literally cargo.
run_reward_treasure :: proc(site: Scaling_Site) -> int {
	return run_zone_depth_scaled(site, REWARD_TREASURE_PER_TIER, REWARD_TREASURE_PER_DEPTH)
}

// Node_Kind is what a Node is: the Start, an Encounter, or the Goal — ADR-0014's
// end state, reached in issue #137.
//
// It **survives** because Start and Goal are genuine landmarks: fixed, terminal,
// carrying no encounter. That is a fact about a node's place in the graph rather
// than about its content, so nothing in a stage list can express it. What it no
// longer carries is content of any kind.
//
// `.Port` is **gone**, and its removal is the last weld between a Shop and a node
// kind. It shrank in three steps: ADR-0014 took its visibility (an encounter is
// visible because it opens with a revealing stage — run_encounter_reveals — not
// because its kind is exempt), #134 took its content (a Port is a node dealt the [Shop]
// recipe, stocked by the same path as every other node), and #131 took the last
// thing that read it (the Sim's per-Port shelf state, which had keyed arrival off
// the kind). That left a value marking only *how a node was placed*, which nothing
// asked and which quietly implied a Port was a different sort of place than the
// merchant vessel carrying the same primitive. Generation still places Ports
// bespokely (generation.odin's step 3) — it just tracks them in the local `placed`
// list for as long as that matters, which is until their recipes are dealt, rather
// than staining the node with it for the rest of the run.
Node_Kind :: enum {
	Start,
	Encounter,
	Goal,
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
// zone is nil for Start and Goal, which sit outside the three stakes bands.
// encounter is set on every node that holds content — .Encounter nodes and the
// bespoke-placed .Port ones alike (#134) — and nil on the Start/Goal landmarks,
// which hold none. The separate `shop: Maybe(Stage_Shop)` a Port used to carry
// (#98) is gone with the Port bucket: a port's stock is its [Shop] stage, so
// there is one field content arrives in rather than a general one plus a
// port-shaped exception. layer/lane are the node's position in the layered
// forward graph — layer is its column (Start = 0, rising toward Goal), lane its
// row within that column; presentation derives screen coordinates from them, so
// Nodes still carry no screen coordinates of their own. depth is the node's
// normalized depth-within-zone (0 for Start/Goal). Adjacency lives on Map.edges,
// not on the Node.
Node :: struct {
	id:        Node_ID,
	zone:      Maybe(Zone),
	kind:      Node_Kind,
	encounter: Maybe(Encounter),
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
