package voyage

// The recipe catalog: every encounter in the game, hand-authored (ADR-0014).
//
// Adding an encounter means adding one entry below — no enum, no union arm, no Sim
// phase, no new file — because the stage primitives (stage.odin) are the alphabet
// and a Recipe is a name plus an order over Stage_Specs (a Shop stage carries which
// hold it sells from). Which bucket an entry lands in is derived from its stage
// count, never authored here.
//
// Two pools live here, and the split *is* the bucket model: recipe_catalog is what
// the zones deal from, filtered by stage count into buckets; port_bucket is
// bespoke-placed and exempt from that rule (ADR-0014). Authoring a recipe in
// port_bucket is the one place bucket membership is authored rather than derived.
//
// # The authoring conventions
//
// **Costs precede boons** — a convention the type system does not enforce. A halt
// is an *exit*: any stage the captain can decline is a free escape from everything
// downstream, so the two declinable *costs* — Fight (Break Off halts) and Trade
// (reject halts) — are authored ahead of the boons they pay for. `[Fight, Reward]`
// is the shape: fleeing forfeits the loot. `[Offer, Fight]` is the anti-shape: skip
// an item you never had and the fight is dodged for nothing.
// costs_precede_boons_in_every_authored_recipe checks the table against exactly
// that partition.
//
// **A name is not decoration.** All variance below the stage list comes from each
// primitive's own content roster, so two recipes with the same stage list would be
// the same encounter twice: a bucket holds one recipe per *shape*. The only reason
// two Shop recipes can share a shape is that they name different holds.
//
// **Only the Port bucket opens on a Shop.** Shop is the revealing primitive, and
// the map labels a revealed encounter by its **first stage** (view.odin's
// node_appearance) — so a `[Shop]` merchant vessel and a `[Shop]` Port would read
// as the same "Shop" marker, with no way to tell a narrow specialist hold from the
// Chandlery until the voyage gets there. The Port bucket's guaranteed placement is
// a promise that a Shop marker is a general market; a counterfeit Port breaks it. A
// merchant earns its Shop by putting a stage in front of it — a Port is
// *guaranteed* and therefore general, a merchant a *windfall* and therefore narrow.
// only_the_port_bucket_opens_on_a_shop pins it.
//
// This rule is load-bearing because an encounter reveals iff its first stage
// reveals (ADR-0016): "opens on a Shop" ≡ "reveals" ≡ "is a Port". The same
// convention that keeps a counterfeit Port off the map is what makes every merchant
// below **hidden**, and it cannot be traded for a better merchant marker — a
// revealing `[Shop]` merchant would be something a captain could *route* to, and a
// merchant is a windfall, not a destination.
//
// # Sizing
//
// ~5-6 per stage-count bucket: a run draws only ~3-4 encounters from a zone's ~15
// nodes, so this size lets a zone rarely repeat itself while staying hand-tunable.
//
// **The 1-stage bucket is capped at four, permanently.** With one stage there is
// exactly one shape per primitive, so the bucket tops out at five by the alphabet —
// and the fifth, `[Shop]`, is the Port's by the rule above. A further entry could
// only duplicate a shape, i.e. one encounter twice
// (see every_bucket_authors_one_recipe_per_shape). This is a cap, not a shortfall:
// a `[Shop]` merchant would reveal itself, so it is forbidden regardless of marker
// (ADR-0016).

// --- The 1-stage bucket: Coastal.
//
// One recipe per primitive, less the Shop the Port bucket reserves. Coastal has no
// shops but its two Ports: every merchant vessel is two or three stages, so none is
// dealt here — a consequence of the two rules above, not authored.
//
// Each recipe's stages are package-level so a Recipe's `stages` slice points at
// static data — a recipe is authored once and reused by every node that draws it,
// so it owns no per-node memory.

@(rodata)
SKIRMISH_STAGES := [?]Stage_Spec{{kind = .Fight}}

@(rodata)
FLOTSAM_STAGES := [?]Stage_Spec{{kind = .Offer}}

@(rodata)
BARGAIN_STAGES := [?]Stage_Spec{{kind = .Trade}}

// Reward has nothing to decline, so this recipe stops for no decision at all
// (stage.odin).
@(rodata)
DRIFTING_SALVAGE_STAGES := [?]Stage_Spec{{kind = .Reward}}

// --- The 2-stage bucket: Open Sea. Where composition starts.

@(rodata)
SEA_BATTLE_STAGES := [?]Stage_Spec{{kind = .Fight}, {kind = .Reward}}

@(rodata)
DERELICT_STAGES := [?]Stage_Spec{{kind = .Offer}, {kind = .Reward}}

@(rodata)
BOARDING_ACTION_STAGES := [?]Stage_Spec{{kind = .Fight}, {kind = .Offer}}

@(rodata)
PRESS_GANG_STAGES := [?]Stage_Spec{{kind = .Fight}, {kind = .Shop, stock = .Press_Gang}}

@(rodata)
SMUGGLERS_COVE_STAGES := [?]Stage_Spec{{kind = .Trade}, {kind = .Shop, stock = .Curiosity_Dealer}}

@(rodata)
PRIVATEERS_TOLL_STAGES := [?]Stage_Spec{{kind = .Trade}, {kind = .Reward}}

// --- The 3-stage bucket: The Deep.
//
// Five distinct *shapes*, not five variations on `[Fight, X, Reward]`.

@(rodata)
CONTESTED_ANCHORAGE_STAGES := [?]Stage_Spec {
	{kind = .Fight},
	{kind = .Shop, stock = .Ordnance_Hoy},
	{kind = .Reward},
}

@(rodata)
SUNKEN_RELIQUARY_STAGES := [?]Stage_Spec {
	{kind = .Offer},
	{kind = .Shop, stock = .Menagerie},
	{kind = .Reward},
}

// Order here is an economy, not just cost-before-boon: the Reward funds the Shop,
// so swapping the two boons would be a different encounter.
@(rodata)
PRIZE_CONVOY_STAGES := [?]Stage_Spec {
	{kind = .Fight},
	{kind = .Reward},
	{kind = .Shop, stock = .Press_Gang},
}

@(rodata)
SMUGGLERS_RUN_STAGES := [?]Stage_Spec {
	{kind = .Trade},
	{kind = .Shop, stock = .Curiosity_Dealer},
	{kind = .Offer},
}

@(rodata)
KRAKENS_WAKE_STAGES := [?]Stage_Spec{{kind = .Fight}, {kind = .Trade}, {kind = .Reward}}

// recipe_catalog is every encounter in the game — the authored table
// voyage_recipe_catalog hands out. Not @(rodata) despite never being written:
// slicing the backing arrays above is not a constant initializer, so the entries
// fill at program init.
//
// Grouped by stage count for reading only. Nothing derives a bucket from the order
// here — voyage_recipe_bucket reads len(r.stages) and nothing else, so moving a line
// changes which recipe the bag's remainder favours and nothing more.
recipe_catalog := [?]Recipe {
	// 1 stage — Coastal.
	{name = "Skirmish", stages = SKIRMISH_STAGES[:]},
	{name = "Flotsam", stages = FLOTSAM_STAGES[:]},
	{name = "Bargain", stages = BARGAIN_STAGES[:]},
	{name = "Drifting Salvage", stages = DRIFTING_SALVAGE_STAGES[:]},
	// 2 stages — Open Sea.
	{name = "Sea Battle", stages = SEA_BATTLE_STAGES[:]},
	{name = "Derelict", stages = DERELICT_STAGES[:]},
	{name = "Boarding Action", stages = BOARDING_ACTION_STAGES[:]},
	{name = "Press Gang", stages = PRESS_GANG_STAGES[:]},
	{name = "Smuggler's Cove", stages = SMUGGLERS_COVE_STAGES[:]},
	{name = "Privateer's Toll", stages = PRIVATEERS_TOLL_STAGES[:]},
	// 3 stages — The Deep.
	{name = "Contested Anchorage", stages = CONTESTED_ANCHORAGE_STAGES[:]},
	{name = "Sunken Reliquary", stages = SUNKEN_RELIQUARY_STAGES[:]},
	{name = "Prize Convoy", stages = PRIZE_CONVOY_STAGES[:]},
	{name = "Smuggler's Run", stages = SMUGGLERS_RUN_STAGES[:]},
	{name = "Kraken's Wake", stages = KRAKENS_WAKE_STAGES[:]},
}

// voyage_recipe_catalog returns every authored recipe. Generation deals from this
// (via voyage_make_recipe_bag) rather than switching over a kind enum, so the set of
// encounters in the game is this list and nothing else.
voyage_recipe_catalog :: proc() -> []Recipe {
	return recipe_catalog[:]
}

// PORT_STAGES backs the Port recipe. A Port is `[Shop]`, an encounter like any
// other, visible on the map only because Shop is the revealing primitive
// (voyage_stage_kind_reveals). What makes it a Port is *where* it is placed — two
// per zone, off the entrance layer (generation.odin's step 3) — and *what* it
// sells: the Chandlery, the one pool with no family filter. The recipe names the
// pool rather than drawing it because a guaranteed placement is only worth
// promising if what you find there is a general market. See Stock_Pool.
@(rodata)
PORT_STAGES := [?]Stage_Spec{{kind = .Shop, stock = .Chandlery}}

// port_bucket is the Port bucket's pool: the recipes eligible for the two bespoke
// port placements in each zone. A bucket is a pool plus a placement rule (ADR-0014),
// and this is the one bucket whose pool is authored rather than derived from stage
// count — Ports are exempt from the zone mapping, so a Port is one stage even in The
// Deep.
//
// Dealt through the same voyage_make_recipe_bag the zones use rather than assigned
// directly, so widening it (a free port, a naval yard) is a catalog entry here and
// nothing else. The Shop-bearing recipes in recipe_catalog above are the other side
// of that line: authored there, they are *merchant vessels* — filed into a zone's
// stage-count bucket by length, narrow-holded, and never guaranteed. Same primitive,
// different bucket.
port_bucket := [?]Recipe {
	{name = "Port", stages = PORT_STAGES[:]},
}

// voyage_port_bucket returns the Port bucket's pool. Split from voyage_recipe_catalog
// so a Port can never fall into a zone's stage-count draw: the zones deal from
// the catalog, the port placement deals from this.
voyage_port_bucket :: proc() -> []Recipe {
	return port_bucket[:]
}
