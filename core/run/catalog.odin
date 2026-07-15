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
// #138, and the per-zone bucket draw that would place them is #134.

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
