package run

// The recipe catalog: every encounter in the game, hand-authored (ADR-0014).
//
// This file is the point of the whole effort. Adding an encounter means adding
// one entry below — no enum, no union arm, no Sim phase, no new file — because
// the stage primitives (stage.odin) are the alphabet and a Recipe is just a name
// plus an order over them. Which bucket an entry lands in is derived from its
// stage count, never authored here.
//
// The catalog is deliberately thin right now: it holds the three one-stage ports
// of the encounter kinds ADR-0014 retired, which is exactly what keeps today's
// generated maps identical while the model underneath them changes. Authoring the
// real catalog — ~5-6 recipes per stage-count bucket, including the multi-stage
// ones the primitives exist for ([Fight, Reward], [Offer, Reward]) — is issue
// #138. Because every entry here is one stage long, the 2- and 3-stage buckets
// the zone draw (generation.odin) asks for are still empty; run_zone_recipe_pool
// documents what that means until #138 fills them.
//
// Two pools live here, and the split *is* the bucket model: recipe_catalog is
// what the zones deal from, filtered by stage count into buckets; port_bucket is
// bespoke-placed and exempt from that rule (ADR-0014). A recipe is in the Port
// bucket by being authored there — that is the one place membership is authored
// rather than derived, which is exactly what "bespoke placement" means.

// SEA_BATTLE / DERELICT / BARGAIN are the three retired encounter kinds as
// one-stage recipes (ADR-0014: Ship Battle -> [Fight], Item Offer -> [Offer],
// Stat Trade -> [Trade]). Their stage backing is package-level so a Recipe's
// `stages` slice points at static data — a recipe is authored once and reused by
// every node that draws it, so it owns no per-node memory.
@(rodata)
SEA_BATTLE_STAGES := [?]Stage_Kind{.Fight}

@(rodata)
DERELICT_STAGES := [?]Stage_Kind{.Offer}

@(rodata)
BARGAIN_STAGES := [?]Stage_Kind{.Trade}

// recipe_catalog is every encounter in the game — the authored table
// run_recipe_catalog hands out, in the same package-level-table shape as
// generation.odin's zone_tier/nodes_per_zone tuning knobs. Not @(rodata) despite
// never being written: taking a slice of the backing arrays above is not a
// constant initializer, so the entries are filled at program init instead.
recipe_catalog := [?]Recipe {
	{name = "Sea Battle", stages = SEA_BATTLE_STAGES[:]},
	{name = "Derelict", stages = DERELICT_STAGES[:]},
	{name = "Bargain", stages = BARGAIN_STAGES[:]},
}

// run_recipe_catalog returns every authored recipe. Generation deals from this
// (via run_make_recipe_bag) rather than switching over a kind enum, so the set of
// encounters in the game is this list and nothing else.
run_recipe_catalog :: proc() -> []Recipe {
	return recipe_catalog[:]
}

// PORT_STAGES backs the Port recipe. A Port is not a kind of place any more — it
// is `[Shop]`, an encounter like any other, visible on the map only because Shop
// is the revealing primitive (run_stage_kind_reveals). What still makes it a Port
// is *where* it is put: two per zone, off the entrance layer (generation.odin's
// step 3). Placement is the whole of its bespokeness.
@(rodata)
PORT_STAGES := [?]Stage_Kind{.Shop}

// port_bucket is the Port bucket's pool: the recipes eligible for the two
// bespoke port placements in each zone. A bucket is a pool plus a placement rule
// (ADR-0014), and this is the one bucket whose pool is authored rather than
// derived from stage count — Ports are exempt from the zone mapping, so a Port is
// one stage even in The Deep.
//
// One recipe today, dealt through the same run_make_recipe_bag the zones use
// rather than assigned directly, so widening it (a free port, a naval yard) is a
// catalog entry here and nothing else. A Shop-bearing recipe authored into
// recipe_catalog above instead would be a *hidden* merchant vessel at sea, drawn
// by whichever zone its stage count files it under — same primitive, different
// bucket, which is the point.
port_bucket := [?]Recipe {
	{name = "Port", stages = PORT_STAGES[:]},
}

// run_port_bucket returns the Port bucket's pool. Split from run_recipe_catalog
// so a Port can never fall into a zone's stage-count draw: the zones deal from
// the catalog, the port placement deals from this.
run_port_bucket :: proc() -> []Recipe {
	return port_bucket[:]
}
