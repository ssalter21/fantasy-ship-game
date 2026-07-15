package run

// The recipe catalog: every encounter in the game, hand-authored (ADR-0014).
//
// This file is the point of the whole effort. Adding an encounter means adding
// one entry below — no enum, no union arm, no Sim phase, no new file — because
// the stage primitives (stage.odin) are the alphabet and a Recipe is just a name
// plus an order over them (widened to a Stage_Spec by ADR-0015, so a Shop can be
// told which hold it sells from). Which bucket an entry lands in is derived from
// its stage count, never authored here.
//
// Two pools live here, and the split *is* the bucket model: recipe_catalog is
// what the zones deal from, filtered by stage count into buckets; port_bucket is
// bespoke-placed and exempt from that rule (ADR-0014). A recipe is in the Port
// bucket by being authored there — that is the one place membership is authored
// rather than derived, which is exactly what "bespoke placement" means.
//
// # The authoring conventions
//
// **Costs precede boons**, and this is a convention the type system deliberately
// does not enforce (#127). The reason it matters is that a halt is an *exit*: any
// stage the captain can decline is a free escape from everything downstream. So
// the two declinable *costs* — Fight (Leave Combat halts) and Trade (reject halts)
// — are authored ahead of the boons they pay for, never behind them. `[Fight,
// Reward]` is the shape: fleeing forfeits the loot, so leaving has a price.
// `[Offer, Fight]` is the anti-shape: skip an item you never had and the fight is
// dodged for nothing. costs_precede_boons_in_every_authored_recipe checks the
// table below against exactly that partition.
//
// **A name is not decoration.** Each recipe reads as a thing — a Derelict, a Press
// Gang — because that is the vocabulary the team says aloud and the noun a stage
// tuple cannot be. Two recipes with the same stage list and different names would
// be the same encounter twice, since all variance below the stage list comes from
// each primitive's own content roster; so a bucket holds one recipe per *shape*,
// and the only reason two Shop recipes can share a shape is that they name
// different holds.
//
// **Only the Port bucket opens on a Shop**, and this one is authoring's discovery
// rather than an inherited rule (#138). Shop is the revealing primitive, and the
// map labels a revealed encounter by its **first stage** (view.odin's
// node_appearance) — so a `[Shop]` merchant vessel and a `[Shop]` Port are the same
// marker, reading "Shop", with no way to tell a six-card specialist hold from the
// Chandlery until you have spent the voyage getting there. That is precisely the
// gamble #137 made a recipe *name* its pool to prevent: the Port bucket's
// guaranteed placement is a promise that a Shop marker is a general market, and a
// counterfeit Port breaks the promise no matter how good the Port itself is.
//
// So a merchant vessel earns its Shop by putting a stage in front of it — which is
// its bucket restated: a Port is *guaranteed* and therefore general, a merchant is
// a *windfall* and therefore narrow. only_the_port_bucket_opens_on_a_shop pins it.
//
// **This does not make merchants hidden, and ADR-0014 is contradictory about
// whether they should be** — a contradiction nothing could observe until there was
// a merchant to look at (#138). run_encounter_reveals asks whether an encounter
// holds a revealing stage *anywhere*, so every recipe below carrying a Shop is
// visible before arrival; it is merely labelled by its first stage, so a Press Gang
// draws a "Battle" marker and a Smuggler's Cove a "Trade" one. Since a plain Sea
// Battle is hidden, a *visible* Battle marker is an unintended tell that a market
// waits behind the fight. The ADR says both "visible iff it contains a revealing
// stage" (which is the code) and "a merchant vessel at sea is a **hidden**
// encounter that happens to carry a Shop stage" (which is the intent, and which
// Stock_Pool's narrow-holds argument leans on: nothing is planned around a
// windfall). Authoring cannot settle that — it is a change to the Sim's hiding
// contract either way — so it is graduated to its own ticket, not decided here.
//
// # Sizing
//
// ~5-6 per stage-count bucket (#138). A run draws only ~3-4 encounters from a
// zone's ~15 nodes, so 5-6 means a zone rarely repeats itself while staying small
// enough to hand-tune.
//
// **The 1-stage bucket lands at four, and cannot hold more.** With one stage there
// is exactly one shape per primitive, so the bucket is capped at five by the
// alphabet — and the fifth, `[Shop]`, is the Port's, by the rule above. Four is
// therefore the whole of the 1-stage bucket, not a shortfall against the ~5-6
// target: a fifth entry could only be a duplicate shape, which is one encounter
// twice (see every_bucket_authors_one_recipe_per_shape). The 2- and 3-stage
// buckets, where the shape space opens up, carry six and five.

// --- The 1-stage bucket: Coastal.
//
// One recipe per primitive, less the Shop the Port bucket reserves. The first three
// are the encounter kinds ADR-0014 retired, carried over unchanged in shape:
// Ship Battle -> [Fight], Item Offer -> [Offer], Stat Trade -> [Trade]. Their
// *names* moved, though: the glossary gives "Sea Battle" and "Derelict" to the
// two-stage recipes below, which is what those words have meant since ADR-0014
// was written. The one-stage ports held them as placeholders while the two-stage
// bucket was empty, and hand them back here.
//
// Coastal therefore has **no shops but its two Ports** — every merchant vessel is
// two stages or three, so none can be dealt here. That falls out of the two rules
// above rather than being authored, and it is the shallows reading correctly: the
// starting zone is where the map's promises are kept, and the strange narrow holds
// are further out.
//
// Each recipe's stages are package-level so a Recipe's `stages` slice points at
// static data — a recipe is authored once and reused by every node that draws it,
// so it owns no per-node memory.

// A lone hostile with nothing aboard worth taking. What Sea Battle is without the
// prize — and the reason the two are different encounters rather than one: with no
// Reward downstream, Leave Combat costs nothing, so this is the fight you are free
// to walk away from.
@(rodata)
SKIRMISH_STAGES := [?]Stage_Spec{{kind = .Fight}}

// Wreckage on the swell: one fitting's worth, take it or leave it.
@(rodata)
FLOTSAM_STAGES := [?]Stage_Spec{{kind = .Offer}}

// A permanent swap, one stat for another, drawn from the trade roster (#136).
@(rodata)
BARGAIN_STAGES := [?]Stage_Spec{{kind = .Trade}}

// Free treasure, and the one encounter whose interaction is *arriving*: Reward has
// nothing to decline, so this recipe stops for no decision at all (stage.odin).
@(rodata)
DRIFTING_SALVAGE_STAGES := [?]Stage_Spec{{kind = .Reward}}

// --- The 2-stage bucket: Open Sea.
//
// Where composition starts. Every entry is a cost paid before a boon, or a boon
// whose forfeit is the price of skipping the one before it.

// The headline recipe, and the glossary's definition of the term: win the battle,
// take the prize. Complete-or-halt does all the work — flee and the loot stage is
// simply never reached, with no authored gate (ADR-0014).
@(rodata)
SEA_BATTLE_STAGES := [?]Stage_Spec{{kind = .Fight}, {kind = .Reward}}

// The glossary's other named recipe: an abandoned hulk holding both a fitting and
// a purse. No fight — the only encounter where the *Offer* is the gate, since
// skipping it halts and forfeits the treasure behind it. That is also why Reward
// reads its own node and never a neighbouring stage (#132): there is no opponent
// here to loot.
@(rodata)
DERELICT_STAGES := [?]Stage_Spec{{kind = .Offer}, {kind = .Reward}}

// Beat them, then strip the hulk. Sea Battle's sibling, paying in a fitting rather
// than coin — the pair is exactly ADR-0014's point that `[Fight, Offer]` and
// `[Fight, Reward]` differ in whether the captain gets to choose.
@(rodata)
BOARDING_ACTION_STAGES := [?]Stage_Spec{{kind = .Fight}, {kind = .Offer}}

// Beat the crew, then take your pick of the survivors. The Shop *is* the payoff
// for the fight, which is what makes this composition and not a Fight with a
// garnish — and it means a hold of nothing but Crew is reachable on purpose, which
// is the one way to build the roster's biggest synergy trap deliberately
// (Stock_Pool's .Press_Gang note).
@(rodata)
PRESS_GANG_STAGES := [?]Stage_Spec{{kind = .Fight}, {kind = .Shop, stock = .Press_Gang}}

// Pay the toll to be let alongside, then buy what the hold is hiding. The Trade is
// a genuine cost — reject it and the market behind it is never opened.
@(rodata)
SMUGGLERS_COVE_STAGES := [?]Stage_Spec{{kind = .Trade}, {kind = .Shop, stock = .Curiosity_Dealer}}

// Pay the privateer and take a cut of a prize someone else fought for. Refuse and
// the coin goes with them.
@(rodata)
PRIVATEERS_TOLL_STAGES := [?]Stage_Spec{{kind = .Trade}, {kind = .Reward}}

// --- The 3-stage bucket: The Deep.
//
// Five *shapes*, not five variations on `[Fight, X, Reward]` (#138): one fights in
// to a market, one never fights at all, one lets the loot pay for the shop, one
// ends on a trader's parting gift, and one buys its way past a picket.

// Fight your way into the trading post, then loot what the fight left — the
// canonical three-stage composition (#138). Reveals itself on the map, because it
// holds a Shop; see the note on run_encounter_reveals in view.odin about what that
// currently *shows*.
@(rodata)
CONTESTED_ANCHORAGE_STAGES := [?]Stage_Spec {
	{kind = .Fight},
	{kind = .Shop, stock = .Ordnance_Hoy},
	{kind = .Reward},
}

// Ruins with a beast-dealer moored in them. The one deep recipe with no Fight and
// no Trade — three boons, where the only cost is that skipping the salvage halts
// the walk and forfeits both the market and the treasure behind it.
@(rodata)
SUNKEN_RELIQUARY_STAGES := [?]Stage_Spec {
	{kind = .Offer},
	{kind = .Shop, stock = .Menagerie},
	{kind = .Reward},
}

// Win, take the coin, and hire from the survivors *with it*. The one recipe where
// stage order is an economy rather than a sequence: the Reward funds the Shop, so
// putting them the other way round would be a different encounter.
@(rodata)
PRIZE_CONVOY_STAGES := [?]Stage_Spec {
	{kind = .Fight},
	{kind = .Reward},
	{kind = .Shop, stock = .Press_Gang},
}

// Pay to be let in, buy what the oddities dealer has, and take a parting pick.
// Ends on the Offer, so the last stage's skip forfeits nothing — the one place a
// declinable boon sits last and is a gift rather than a gate.
@(rodata)
SMUGGLERS_RUN_STAGES := [?]Stage_Spec {
	{kind = .Trade},
	{kind = .Shop, stock = .Curiosity_Dealer},
	{kind = .Offer},
}

// Beat the picket, buy passage with a stat, then loot the wreck it was guarding.
// Two costs stacked before one boon — the deepest the convention allows, and the
// only recipe that asks the captain to pay twice before anything is granted.
@(rodata)
KRAKENS_WAKE_STAGES := [?]Stage_Spec{{kind = .Fight}, {kind = .Trade}, {kind = .Reward}}

// recipe_catalog is every encounter in the game — the authored table
// run_recipe_catalog hands out, in the same package-level-table shape as
// generation.odin's zone_tier/nodes_per_zone tuning knobs. Not @(rodata) despite
// never being written: taking a slice of the backing arrays above is not a
// constant initializer, so the entries are filled at program init instead.
//
// Grouped by stage count for reading only. Nothing derives a bucket from the order
// here — run_recipe_bucket reads len(r.stages) and nothing else, so moving a line
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

// run_recipe_catalog returns every authored recipe. Generation deals from this
// (via run_make_recipe_bag) rather than switching over a kind enum, so the set of
// encounters in the game is this list and nothing else.
run_recipe_catalog :: proc() -> []Recipe {
	return recipe_catalog[:]
}

// PORT_STAGES backs the Port recipe. A Port is not a kind of place any more — it
// is `[Shop]`, an encounter like any other, visible on the map only because Shop
// is the revealing primitive (run_stage_kind_reveals). What still makes it a Port
// is *where* it is put — two per zone, off the entrance layer (generation.odin's
// step 3) — and, since issue #137, *what it sells*: the Chandlery pool, the one
// pool with no family filter at all.
//
// Those two are the same fact stated twice, which is why the recipe names the pool
// rather than drawing it. Bespoke placement guarantees six Ports per run, so routing
// to one is a plan the map always honours; that promise is only worth making if what
// you find there is a general market. See Stock_Pool.
@(rodata)
PORT_STAGES := [?]Stage_Spec{{kind = .Shop, stock = .Chandlery}}

// port_bucket is the Port bucket's pool: the recipes eligible for the two
// bespoke port placements in each zone. A bucket is a pool plus a placement rule
// (ADR-0014), and this is the one bucket whose pool is authored rather than
// derived from stage count — Ports are exempt from the zone mapping, so a Port is
// one stage even in The Deep.
//
// One recipe today, dealt through the same run_make_recipe_bag the zones use
// rather than assigned directly, so widening it (a free port, a naval yard) is a
// catalog entry here and nothing else. The Shop-bearing recipes in recipe_catalog
// above are the other side of that line: authored there, they are *merchant
// vessels* — dealt into whichever zone's stage-count bucket their length files
// them under, narrow-holded, and never guaranteed. Same primitive, different
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
