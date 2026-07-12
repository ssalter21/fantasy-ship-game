package run

import "../combat"
import "../ship"
import "core:math"
import "core:math/rand"

// Zone is one of the three fixed difficulty bands a Point belongs to, in a
// fixed linear order (CONTEXT.md): Coastal (nearest Start) -> Open_Sea ->
// Deep (nearest Goal). Both encounter difficulty and reward quality scale
// with zone. The zones survive the node-graph redesign (ADR-0009, which
// supersedes ADR-0007's topology/fog) — only the map's shape and the
// within-zone gradient axis changed.
Zone :: enum {
	Coastal,
	Open_Sea,
	Deep,
}

// zone_tier is the single shared per-zone difficulty/reward ladder
// (placeholder values expected to move during playtesting) — Coastal <
// Open_Sea < Deep. Ship Battle, Upgrade Offer, and Stat Trade each scale off
// this one table via their own PER_TIER constant below, so the three kinds
// land on distinguishable magnitudes instead of duplicating the same literal
// table.
zone_tier := [Zone]int{.Coastal = 1, .Open_Sea = 2, .Deep = 3}

// The difficulty/reward gradient now stacks two axes: the per-zone tier
// ladder above, and depth-within-zone — how deep into a zone's phase a node
// sits, normalized to a fixed range (DEPTH_STEPS) so the spread is consistent
// regardless of how many layers a seed happened to roll. Both feed every
// zone-scaled formula below via run_zone_depth_scaled. Depth replaces the retired
// Ship-Battle-only "port proximity / contested waters" input, and now applies
// to all three encounter kinds.
DEPTH_STEPS :: 3

SHIP_BATTLE_HP_PER_TIER :: 10
SHIP_BATTLE_HP_PER_DEPTH :: 3
SHIP_BATTLE_DURABILITY_PER_TIER :: 1
SHIP_BATTLE_DURABILITY_PER_DEPTH :: 1
SHIP_BATTLE_OPPONENT_SPEED :: 5
UPGRADE_OFFER_QUALITY_PER_TIER :: 15
UPGRADE_OFFER_QUALITY_PER_DEPTH :: 5
STAT_TRADE_DURABILITY_PER_TIER :: 8
STAT_TRADE_DURABILITY_PER_DEPTH :: 2
STAT_TRADE_SPEED_COST_PER_TIER :: 1
STAT_TRADE_SPEED_COST_PER_DEPTH :: 1

// run_zone_depth_scaled is the shared accessor behind every zone-and-depth-scaled
// placeholder below: a kind's per_tier constant times the zone's position on
// zone_tier, plus its per_depth constant times the node's normalized
// depth-within-zone. The two axes stack, so a deep node in a zone outscales a
// shallow one, and a Deep-zone node still outscales a Coastal one.
run_zone_depth_scaled :: proc(zone: Zone, depth: int, per_tier: int, per_depth: int) -> int {
	return zone_tier[zone] * per_tier + depth * per_depth
}

// run_normalize_depth maps a node's raw depth (its 0-based layer index within
// its zone's phase) onto the fixed 0..DEPTH_STEPS range, so the difficulty
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

// run_ship_battle_difficulty is the game-configured opponent's HP baseline
// for a Ship Battle point: rises by zone tier and by depth-within-zone.
run_ship_battle_difficulty :: proc(zone: Zone, depth: int) -> int {
	return run_zone_depth_scaled(zone, depth, SHIP_BATTLE_HP_PER_TIER, SHIP_BATTLE_HP_PER_DEPTH)
}

// run_ship_battle_opponent_durability is the opponent's flat incoming-damage
// reduction (core/combat's durability stat) for a Ship Battle point: like
// run_ship_battle_difficulty, rises by zone tier and by depth, so a deeper
// battle isn't HP-pool-only.
run_ship_battle_opponent_durability :: proc(zone: Zone, depth: int) -> int {
	return run_zone_depth_scaled(zone, depth, SHIP_BATTLE_DURABILITY_PER_TIER, SHIP_BATTLE_DURABILITY_PER_DEPTH)
}

// run_upgrade_offer_quality is a zone-and-depth-scaled reward-quality
// placeholder — a deeper Upgrade Offer grants a bigger boost than a shallow
// one in the same zone. Concrete meaning (what an Upgrade Offer actually
// grants) is issue #23's content.
run_upgrade_offer_quality :: proc(zone: Zone, depth: int) -> int {
	return run_zone_depth_scaled(zone, depth, UPGRADE_OFFER_QUALITY_PER_TIER, UPGRADE_OFFER_QUALITY_PER_DEPTH)
}

// run_stat_trade_gain_durability and run_stat_trade_cost_speed are the
// zone-and-depth-scaled magnitudes of a Stat Trade's two sides: a deeper
// trade is a bigger swing (more Durability gained, more Speed spent) than a
// shallow one in the same zone.
run_stat_trade_gain_durability :: proc(zone: Zone, depth: int) -> int {
	return run_zone_depth_scaled(zone, depth, STAT_TRADE_DURABILITY_PER_TIER, STAT_TRADE_DURABILITY_PER_DEPTH)
}

run_stat_trade_cost_speed :: proc(zone: Zone, depth: int) -> int {
	return run_zone_depth_scaled(zone, depth, STAT_TRADE_SPEED_COST_PER_TIER, STAT_TRADE_SPEED_COST_PER_DEPTH)
}

// Point_Kind is what a Point is: the Start/home port, a per-zone Port, an
// Encounter, or the Goal. Points are now graph nodes with edges/adjacency
// (ADR-0009), but the kind vocabulary is
// unchanged.
Point_Kind :: enum {
	Start,
	Port,
	Encounter,
	Goal,
}

// run_point_is_port reports whether p functions as a port — true for both
// .Start (the home port) and .Port (each zone's ports), so a caller doesn't
// need to special-case .Start itself just to ask "is this point a port".
run_point_is_port :: proc(p: Point) -> bool {
	return p.kind == .Start || p.kind == .Port
}

// Encounter_Kind is the type of interaction an Encounter point presents.
Encounter_Kind :: enum {
	Ship_Battle,
	Upgrade_Offer,
	Stat_Trade,
}

// Encounter is what happens automatically on the first arrival at an
// Encounter point (no decline once arrived). Shaped as an open union,
// mirroring core/combat's Command/Event pattern, so a future kind can be
// added without restructuring callers.
Encounter :: union {
	Encounter_Ship_Battle,
	Encounter_Upgrade_Offer,
	Encounter_Stat_Trade,
}

// Encounter_Ship_Battle is a full battle against a game-configured opponent,
// resolved via core/combat's existing phased-round Battle — this package
// hands off to combat.combat_battle_create rather than reimplementing combat.
// opponent's stats are a difficulty placeholder (run_make_opponent_ship);
// real PvE opponent content is issue #23.
Encounter_Ship_Battle :: struct {
	// depth is this node's normalized depth-within-zone (0..DEPTH_STEPS),
	// retained so run_finish_ship_battle can recompute the point's original
	// tuned difficulty rating without reading it off the battle-worn opponent.
	depth:    int,
	opponent: ship.Ship,
}

// Encounter_Upgrade_Offer is a choice among upgrade options; picking one is a
// separate captain decision left to implementation — this package only
// carries the offer's zone-and-depth-scaled quality placeholder. Real upgrade
// content is issue #23.
Encounter_Upgrade_Offer :: struct {
	quality: int,
}

// Encounter_Stat_Trade is a permanent stat-for-stat/cargo trade-off (example:
// +Durability for -Speed) — that concrete shape is modeled directly rather
// than as a generic stat-enum system, matching this slice's single
// hand-authored trade axis. Both magnitudes are zone-and-depth-scaled.
Encounter_Stat_Trade :: struct {
	gain_durability: int,
	cost_speed:      int,
}

// Point is a single node on the run's procedurally-generated map (ADR-0009).
// zone is nil for Start and Goal, which sit
// outside the three difficulty bands. encounter is set only when
// kind == .Encounter. layer/lane are the node's position in the layered
// forward graph — layer is its column (Start = 0, rising toward Goal), lane
// its row within that column; presentation derives screen coordinates from
// them, so Points still carry no screen coordinates of their own. depth is
// the node's normalized depth-within-zone (0 for Start/Goal). Adjacency lives
// on Map.edges, not on the Point.
Point :: struct {
	id:        int,
	zone:      Maybe(Zone),
	kind:      Point_Kind,
	encounter: Maybe(Encounter),
	layer:     int,
	lane:      int,
	depth:     int,
}

// Map is the run's procedurally-generated node graph: the Points plus the
// symmetric adjacency in edges (edges[i] lists the ids of every node sharing
// an edge with point i). Travel legality is not "go anywhere" any more — it
// is derived from this adjacency plus the visited set by run_travel_options.
Map :: struct {
	points: []Point,
	edges:  [][]int,
}

// --- Generation constants (all tuning knobs live here, near the generator;
// no config file, no settings UI) -------------------------------------------

// nodes_per_zone is each zone's total *point* budget (50 total across the
// three zones, plus Start and Goal). A port consumes a slot rather than
// adding on top, so real encounter counts are these minus PORTS_PER_ZONE
// (15 / 15 / 14 = 44 encounters).
nodes_per_zone := [Zone]int{.Coastal = 17, .Open_Sea = 17, .Deep = 16}

// PORTS_PER_ZONE scattered ports per zone (6 total, plus the Start home
// port), each placed in a uniformly random layer within its zone's phase.
PORTS_PER_ZONE :: 2

// LAYER_WIDTH_MIN/MAX bound how many nodes sit in one layer of the forward
// graph (locked by #60 as the tunable starting point).
LAYER_WIDTH_MIN :: 4
LAYER_WIDTH_MAX :: 6

// OUT_DEGREE_MAX bounds a regular node's forward out-edges (#60 locked 1..4);
// every non-Goal node gets at least one forward edge by construction, so the
// effective range is 1..OUT_DEGREE_MAX. The Start node is exempt: it is the
// sole source for the whole first layer, so it fans out to all of it.
OUT_DEGREE_MAX :: 4

// LATERAL_EDGE_CHANCE is the per-pair probability of a same-layer (lateral)
// edge — a bonus route legal to traverse either direction, never load-bearing
// for reachability.
LATERAL_EDGE_CHANCE :: 0.15

// run_map_create builds the run's procedurally-generated node graph from
// seed: a layered forward graph grown zone-by-zone (Coastal -> Open_Sea ->
// Deep, into Goal), with reachability and zero dead ends guaranteed by
// construction and extra edges for real branching. Same seed => identical
// map. Caller owns the returned Map and must free it with run_map_destroy.
run_map_create :: proc(seed: u64) -> Map {
	state := rand.create_u64(seed)
	gen := rand.default_random_generator(&state)

	// --- 1. Lay out the layers: Start (1) -> each zone's layers -> Goal (1).
	layer_zone: [dynamic]Maybe(Zone)
	layer_width: [dynamic]int
	defer delete(layer_zone)
	defer delete(layer_width)

	append(&layer_zone, nil)
	append(&layer_width, 1)

	zone_first_layer: [Zone]int
	zone_layer_count: [Zone]int
	for zone in Zone {
		zone_first_layer[zone] = len(layer_width)
		widths := run_partition_layers(nodes_per_zone[zone], gen)
		zone_layer_count[zone] = len(widths)
		for w in widths {
			append(&layer_zone, Maybe(Zone)(zone))
			append(&layer_width, w)
		}
		delete(widths)
	}

	append(&layer_zone, nil)
	append(&layer_width, 1)

	n_layers := len(layer_width)

	// --- 2. Materialize the nodes layer by layer (ids run in layer order).
	points: [dynamic]Point
	layer_start_id := make([]int, n_layers)
	defer delete(layer_start_id)

	for l in 0 ..< n_layers {
		layer_start_id[l] = len(points)
		zone_m := layer_zone[l]
		for lane in 0 ..< layer_width[l] {
			kind := Point_Kind.Encounter
			if l == 0 {
				kind = .Start
			} else if l == n_layers - 1 {
				kind = .Goal
			}

			depth := 0
			if zone, ok := zone_m.?; ok {
				raw_depth := l - zone_first_layer[zone]
				depth = run_normalize_depth(raw_depth, zone_layer_count[zone])
			}

			append(&points, Point{id = len(points), zone = zone_m, kind = kind, layer = l, lane = lane, depth = depth})
		}
	}
	n := len(points)

	// --- 3. Place ports: PORTS_PER_ZONE per zone, each in a uniformly random
	// layer within that zone's phase (two ports may share a layer). A port
	// consumes an Encounter slot rather than adding a node.
	for zone in Zone {
		zl0 := zone_first_layer[zone]
		zl1 := zl0 + zone_layer_count[zone]
		placed: [PORTS_PER_ZONE]int
		count := 0
		for count < PORTS_PER_ZONE {
			l := zl0 if zl1 - zl0 <= 1 else rand.int_range(zl0, zl1, gen)
			lane := rand.int_max(layer_width[l], gen)
			id := layer_start_id[l] + lane

			taken := false
			for k in 0 ..< count {
				if placed[k] == id {
					taken = true
					break
				}
			}
			if taken {
				continue
			}
			placed[count] = id
			count += 1
			points[id].kind = .Port
		}
	}

	// --- 4. Assign encounter kinds from a per-zone shuffled bag, split as
	// evenly across the three kinds as a three-way division allows, then build
	// each encounter's zone-and-depth-scaled content.
	for zone in Zone {
		enc_ids: [dynamic]int
		for p in points {
			pz, in_zone := p.zone.?
			if in_zone && pz == zone && p.kind == .Encounter {
				append(&enc_ids, p.id)
			}
		}
		bag := run_make_kind_bag(len(enc_ids), gen)
		for id, i in enc_ids {
			points[id].encounter = run_make_encounter(bag[i], zone, points[id].depth)
		}
		delete(bag)
		delete(enc_ids)
	}

	// --- 5. Wire edges. Symmetric adjacency; forward edges connect
	// consecutive layers, laterals connect same-layer nodes.
	adj := make([][dynamic]int, n)
	forward_out := make([]int, n)
	defer delete(forward_out)

	for l in 0 ..< n_layers - 1 {
		a0 := layer_start_id[l]
		a1 := a0 + layer_width[l]
		b0 := layer_start_id[l + 1]
		b1 := b0 + layer_width[l + 1]

		// Out guarantee: every node in layer l gets at least one forward edge
		// into layer l+1 — no dead ends, and every non-Goal node can always
		// step forward toward Goal.
		for u in a0 ..< a1 {
			v := b0 + rand.int_max(b1 - b0, gen)
			run_add_edge(adj, u, v)
			forward_out[u] += 1
		}

		// In guarantee: every node in layer l+1 that still has no incoming
		// edge gets one from a layer-l source with spare out-degree — so no
		// node is unreachable from Start.
		for v in b0 ..< b1 {
			if run_has_incoming(adj[:], v, a0, a1) {
				continue
			}
			u := run_pick_source_with_capacity(a0, a1, forward_out, gen)
			run_add_edge(adj, u, v)
			forward_out[u] += 1
		}

		// Extra edges: real branching, capped at OUT_DEGREE_MAX forward edges
		// per node (Start exempt — it must fan out to the whole first layer).
		for u in a0 ..< a1 {
			extra := rand.int_max(OUT_DEGREE_MAX, gen)
			for _ in 0 ..< extra {
				if l != 0 && forward_out[u] >= OUT_DEGREE_MAX {
					break
				}
				v := b0 + rand.int_max(b1 - b0, gen)
				if !run_contains(adj[u][:], v) {
					run_add_edge(adj, u, v)
					forward_out[u] += 1
				}
			}
		}
	}

	// Lateral edges within a layer (skip the single-node Start/Goal layers).
	for l in 1 ..< n_layers - 1 {
		a0 := layer_start_id[l]
		w := layer_width[l]
		for i in 0 ..< w {
			for j in i + 1 ..< w {
				if rand.float64(gen) < LATERAL_EDGE_CHANCE {
					run_add_edge(adj, a0 + i, a0 + j)
				}
			}
		}
	}

	edges := make([][]int, n)
	for i in 0 ..< n {
		edges[i] = adj[i][:]
	}
	delete(adj)

	return Map{points = points[:], edges = edges}
}

// run_partition_layers splits a zone's node budget into a list of layer widths,
// each within [LAYER_WIDTH_MIN, LAYER_WIDTH_MAX], summing exactly to total.
// The layer count is chosen randomly among those that admit a valid split,
// then the surplus over the minimum is scattered across layers. Caller owns
// the returned slice.
run_partition_layers :: proc(total: int, gen: rand.Generator) -> []int {
	min_layers := (total + LAYER_WIDTH_MAX - 1) / LAYER_WIDTH_MAX
	max_layers := total / LAYER_WIDTH_MIN
	k := min_layers if max_layers <= min_layers else rand.int_range(min_layers, max_layers + 1, gen)

	widths := make([]int, k)
	for i in 0 ..< k {
		widths[i] = LAYER_WIDTH_MIN
	}
	surplus := total - k * LAYER_WIDTH_MIN
	for surplus > 0 {
		i := rand.int_max(k, gen)
		if widths[i] < LAYER_WIDTH_MAX {
			widths[i] += 1
			surplus -= 1
		}
	}
	return widths
}

// run_make_kind_bag builds count encounter kinds split as evenly across the three
// kinds as a three-way division allows (e.g. 15 -> 5/5/5, 14 -> 5/5/4), then
// shuffles them. Guarantees the zone-wide pool is even; makes no attempt to
// balance kinds along any individual route. Caller owns the returned slice.
run_make_kind_bag :: proc(count: int, gen: rand.Generator) -> []Encounter_Kind {
	bag := make([]Encounter_Kind, count)
	base := count / 3
	rem := count % 3

	i := 0
	for kind, k in ([3]Encounter_Kind{.Ship_Battle, .Upgrade_Offer, .Stat_Trade}) {
		c := base + (1 if k < rem else 0)
		for _ in 0 ..< c {
			bag[i] = kind
			i += 1
		}
	}
	rand.shuffle(bag, gen)
	return bag
}

// run_make_encounter builds one Encounter's zone-and-depth-scaled content for
// the given kind. Split out so the generator's kind-assignment loop reads as
// data, not a switch.
run_make_encounter :: proc(kind: Encounter_Kind, zone: Zone, depth: int) -> Encounter {
	switch kind {
	case .Ship_Battle:
		return Encounter_Ship_Battle{depth = depth, opponent = run_pve_opponent(zone, depth)}
	case .Upgrade_Offer:
		return Encounter_Upgrade_Offer{quality = run_upgrade_offer_quality(zone, depth)}
	case .Stat_Trade:
		return Encounter_Stat_Trade{
			gain_durability = run_stat_trade_gain_durability(zone, depth),
			cost_speed      = run_stat_trade_cost_speed(zone, depth),
		}
	}
	unreachable()
}

// run_add_edge records a symmetric edge between u and v (each appears in the
// other's adjacency), skipping duplicates.
run_add_edge :: proc(adj: [][dynamic]int, u, v: int) {
	if run_contains(adj[u][:], v) {
		return
	}
	append(&adj[u], v)
	append(&adj[v], u)
}

// run_contains reports whether xs holds x — a linear scan, fine for the tiny
// per-node adjacency lists.
run_contains :: proc(xs: []int, x: int) -> bool {
	for e in xs {
		if e == x {
			return true
		}
	}
	return false
}

// run_has_incoming reports whether v already has an edge from any node in the
// layer spanning [a0, a1).
run_has_incoming :: proc(adj: [][dynamic]int, v, a0, a1: int) -> bool {
	for u in adj[v] {
		if u >= a0 && u < a1 {
			return true
		}
	}
	return false
}

// run_pick_source_with_capacity chooses a node in [a0, a1) whose forward
// out-degree is still below OUT_DEGREE_MAX; falls back to any node in range if
// somehow all are saturated (layer widths make that unreachable in practice).
run_pick_source_with_capacity :: proc(a0, a1: int, forward_out: []int, gen: rand.Generator) -> int {
	candidates: [dynamic]int
	defer delete(candidates)
	for u in a0 ..< a1 {
		if forward_out[u] < OUT_DEGREE_MAX {
			append(&candidates, u)
		}
	}
	if len(candidates) == 0 {
		return a0 + rand.int_max(a1 - a0, gen)
	}
	return candidates[rand.int_max(len(candidates), gen)]
}

// run_neighbor_is_legal reports whether travel from current to neighbor is
// allowed (assuming they share an edge): a forward or lateral neighbor (same
// or higher layer) is always legal; a backward neighbor (lower layer) is
// legal only by retrace to an already-visited node.
run_neighbor_is_legal :: proc(m: Map, current, neighbor: int, visited: []bool) -> bool {
	if m.points[neighbor].layer >= m.points[current].layer {
		return true
	}
	return visited[neighbor]
}

// run_travel_options is the single seam every legal-move consumer shares (the
// Sim's travel gate, the UI's reachable-next affordance, and tests): the ids
// legally reachable from current given visited — forward and lateral
// neighbors always, backward neighbors only if already visited. Caller owns
// the returned slice.
run_travel_options :: proc(m: Map, current: int, visited: []bool) -> []int {
	options: [dynamic]int
	for neighbor in m.edges[current] {
		if run_neighbor_is_legal(m, current, neighbor, visited) {
			append(&options, neighbor)
		}
	}
	return options[:]
}

// run_can_travel_to is the allocation-free predicate form of
// run_travel_options for a single destination — dest must both share an edge
// with current and satisfy the legality rule. The Sim's travel gate uses this
// to assert against illegal (non-neighbor or backward-unvisited) destinations.
run_can_travel_to :: proc(m: Map, current: int, visited: []bool, dest: int) -> bool {
	for neighbor in m.edges[current] {
		if neighbor == dest {
			return run_neighbor_is_legal(m, current, dest, visited)
		}
	}
	return false
}

// run_map_destroy frees a Map's owned memory: each node's adjacency slice and
// the edges array, m.points itself, plus each Ship Battle encounter's
// opponent.layout slice (issue #23; run_pve_opponent allocates a fresh layout
// per point). Callers of run_map_create must use this instead of a bare
// delete(m.points).
run_map_destroy :: proc(m: ^Map) {
	for point in m.points {
		encounter, has_encounter := point.encounter.?
		if !has_encounter {
			continue
		}
		if battle, is_battle := encounter.(Encounter_Ship_Battle); is_battle {
			delete(battle.opponent.layout)
		}
	}
	for adj in m.edges {
		delete(adj)
	}
	delete(m.edges)
	delete(m.points)
}

// run_make_opponent_ship computes a Ship Battle opponent's baseline stats
// (hp, durability, speed) from zone/depth — the numeric half of a
// hand-authored PvE opponent (issue #23). run_pve_opponent (content.odin)
// layers a hand-authored layout on top of these same stats; this proc has
// no layout/captain of its own and is not itself a complete opponent.
run_make_opponent_ship :: proc(zone: Zone, depth: int) -> ship.Ship {
	hp := run_ship_battle_difficulty(zone, depth)
	return ship.Ship{
		hp         = hp,
		max_hp     = hp,
		durability = run_ship_battle_opponent_durability(zone, depth),
		speed      = SHIP_BATTLE_OPPONENT_SPEED,
	}
}

// run_start_battle triggers a Ship Battle encounter: hands off to core/combat's
// existing Battle type rather than reimplementing combat. Caller drives the
// returned Battle to completion via combat.combat_resolve_round as normal.
run_start_battle :: proc(s: ^ship.Ship, encounter: ^Encounter_Ship_Battle) -> combat.Battle {
	return combat.combat_battle_create(s, &encounter.opponent)
}

// run_finish_ship_battle emits Event_Encounter_Resolved (ADR-0008) once a
// Ship Battle's Battle has ended: the snapshot is of s, the player-side ship
// handed to run_start_battle, not the opponent — an encounter is "resolved"
// from the player's own run-progress perspective. difficulty_rating is
// recomputed from zone/depth rather than read off the opponent's (now
// battle-worn) hp, since that would reflect remaining HP, not the point's
// original tuned difficulty.
run_finish_ship_battle :: proc(battle: ^combat.Battle, s: ^ship.Ship, encounter: ^Encounter_Ship_Battle, zone: Zone, steps: int, events: ^[dynamic]Event) {
	assert(battle.ended, "run_finish_ship_battle called before the battle ended")

	run_emit_encounter_resolved(s, steps, zone, run_ship_battle_difficulty(zone, encounter.depth), events)
}

// run_apply_upgrade_offer triggers an Upgrade Offer encounter's resolution
// (ADR-0008): grants nothing concrete yet since which upgrade the captain
// picks among offer's options is real content for issue #23 — this proc only
// captures the emission half of the pattern, using offer's zone-and-depth-
// scaled quality placeholder as the snapshot's difficulty_rating.
run_apply_upgrade_offer :: proc(s: ^ship.Ship, offer: Encounter_Upgrade_Offer, zone: Zone, steps: int, events: ^[dynamic]Event) {
	run_emit_encounter_resolved(s, steps, zone, offer.quality, events)
}

// run_apply_stat_trade triggers a Stat Trade encounter: unlike Upgrade Offer,
// a Stat Trade is a single fixed trade-off rather than a choice among
// options, so it applies immediately and permanently on arrival, matching "no
// decline". Emits Event_Encounter_Resolved (ADR-0008) with a post-trade
// snapshot; the trade's own gain_durability is already this point's
// zone-and-depth-scaled tuned magnitude, so it doubles as the snapshot's
// difficulty_rating.
run_apply_stat_trade :: proc(s: ^ship.Ship, trade: Encounter_Stat_Trade, zone: Zone, steps: int, events: ^[dynamic]Event) {
	s.durability += trade.gain_durability
	s.speed -= trade.cost_speed

	run_emit_encounter_resolved(s, steps, zone, trade.gain_durability, events)
}

// run_emit_encounter_resolved captures a Ghost_Snapshot and appends its
// Event_Encounter_Resolved (ADR-0008) — the shared tail of every
// encounter-resolution proc above, which otherwise differ only in how they
// arrive at difficulty_rating.
run_emit_encounter_resolved :: proc(s: ^ship.Ship, steps: int, zone: Zone, difficulty_rating: int, events: ^[dynamic]Event) {
	snap := run_ghost_snapshot_capture(s, steps, zone, difficulty_rating)
	append(events, Event(Event_Encounter_Resolved{snapshot = snap}))
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
run_status :: proc(s: ^ship.Ship, current: Point) -> Run_Status {
	if s.hp <= 0 {
		return .Lost
	}
	if current.kind == .Goal {
		return .Won
	}
	return .In_Progress
}

// run_can_travel reports whether the ship may still travel to another point:
// false once HP has reached 0 — a sunk ship has already lost and makes no
// further routing choice.
run_can_travel :: proc(s: ^ship.Ship) -> bool {
	return s.hp > 0
}
