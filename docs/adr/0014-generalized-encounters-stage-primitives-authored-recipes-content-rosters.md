# ADR-0014: Generalized encounters — stage primitives, authored recipes, content rosters

## Status

Accepted. **Supersedes ADR-0013** (a Port shop's cross-visit persistence drops; the multi-buy-until-you-leave loop within one visit survives). **Amends ADR-0009's wording**: its difficulty gradient is renamed **stakes**, and its per-zone encounter-kind bag becomes a **recipe bag**. ADR-0009's topology, movement, port placement, encounter-fires-once, and presentation decisions carry forward unchanged, as do ADR-0012's roster/tags/effects/Refit decisions and ADR-0006's combat resolution.

## Context

Since ADR-0007 an encounter has been **one hidden kind out of three** — Ship Battle, Item Offer, Stat Trade — and the codebase mirrors that enum end to end: an `Encounter_Kind` enum, a per-kind Encounter union variant, per-kind Sim phases, per-kind Commands and Events, and a `sim_*.odin` file per kind. Adding a fourth kind means touching every one of those. The shape has held so far because three kinds is small, but it makes the cheapest content in the game — "what happens when you arrive somewhere" — the most expensive thing to add.

Two independent pressures forced the question:

- **Composite encounters have nowhere to live.** "Fight a blockade, then loot it" is a Ship Battle *and* a reward. Under one-kind-per-node it can only be a fourth kind that hard-codes the pair, and "fight then get an item" a fifth. Every combination is a new enum value and a new file.
- **Ports are a special case that shouldn't be.** A Port is a landmark that isn't an encounter, holding a shop no encounter can hold. A merchant vessel met at sea — a shop you *didn't* see coming — is unrepresentable, purely because shop-ness is welded to landmark-ness.

Meanwhile Item Offer has a content roster (ADR-0012's ~50 items) while Ship Battle has one opponent template and Stat Trade has one hard-coded axis (+Durability / −Speed). Two of the three kinds have no variance at all, which reads as a missing *trait* layer only until you notice the kinds themselves are the trait.

The options considered:

- **Keep `Encounter_Kind`, add kinds as needed.** Rejected: it is exactly the cost the effort exists to remove, and combinations multiply the enum.
- **Kinds plus an orthogonal trait-modifier layer** — a Ship Battle with a "rewarding" trait, an Offer with a "risky" trait. Rejected: it needs a trait/kind compatibility matrix, and every trait that changes what *happens* (rather than what a number is) is a stage in disguise. A stage primitive **is** the trait.
- **Encounter as an ordered list of stage primitives**, assembled into hand-authored recipes. Chosen.

## Decision

### An Encounter is an ordered list of stages

An **Encounter** is an ordered list of **stages** and a cursor. Today's three kinds become one-stage recipes; nothing about a node changes except what it holds. A run's map holds exactly one Encounter type — `Encounter_Kind`, the per-kind union variants, the per-kind Phases/Commands/Events, and the per-kind `sim_*.odin` files are all removed.

### The stage primitive set is closed: `Fight | Offer | Trade | Shop | Reward`

Five primitives, deliberately closed. `Fight` (a battle per ADR-0006), `Offer` (pick one item of a few, or skip — ADR-0012's Item Offer), `Trade` (a permanent stat-for-stat swap), `Shop` (buy from stock against starting treasure), `Reward` (a grant). `Shop` exists as its own primitive rather than as Offer-with-a-price precisely so Offer can be redesigned later without dragging Shop along.

Adding a new *encounter* must not require adding a primitive: the set is the alphabet, and content lives in the catalog. A sixth primitive is a real ADR-sized decision, not a content change.

### Complete-or-halt, with the primitive defining completion

A stage resolves to exactly one of two outcomes: **completed** (advance the cursor to the next stage) or **halted** (the encounter ends here, keeping everything earlier stages already granted). There are **no authored gates** — a recipe does not say "advance only if the player won"; the primitive itself defines what completing means:

- **Fight** — victory completes; **Leave Combat halts**; sinking ends the run (permadeath, ADR-0006).
- **Offer** — picking completes; skipping halts.
- **Trade** — accepting completes; rejecting halts.
- **Shop** — leaving completes (a shop cannot be failed).
- **Reward** — always completes.

This is what makes `[Fight, Reward]` mean the obvious thing with no authoring: flee the blockade and you don't get the loot, because a halt stops the walk. It also gives the Sim **one** generic path — walk the stages, stop on halt, stop at the end — instead of a phase graph per kind.

### A Recipe is a named, authored stage set

A **Recipe** is the authored unit of content: a name plus its ordered stages plus the per-stage content each draws from. `Sea Battle = [Fight, Reward]`. `Derelict = [Offer, Reward]`. Recipes are hand-authored catalog entries — the whole point of the effort is that a developer adds an encounter by adding one, touching no enum, no union, no Sim phase, and no new file.

### Generation picks recipes; it does not compose stages

Generation **never assembles a stage list**. It picks a whole authored recipe from a bucket, and each of that recipe's stages rolls its content from its own roster. Mix-and-match is a **developer authoring tool, not a runtime generative system**.

This is the load-bearing constraint. A generator that composed stages freely would emit encounters no human ever read — `[Trade, Trade, Trade]`, `[Shop, Fight]` where the fight punishes you for shopping — and no amount of legality rules recovers taste; you would be debugging a grammar instead of writing content. Authored recipes keep every encounter in the game something a person decided was good, while the primitives keep the cost of *deciding* it near zero. The combinatorial space is a palette for the author, not a search space for the generator.

### A Bucket is a pool of recipes plus a placement rule; membership is derived

A **Bucket** is a pool of recipes with a rule for where its picks go. The 1-, 2-, and 3-stage buckets are drawn per zone; **membership is derived from `len(recipe.stages)`, never authored** — a recipe cannot be filed in the wrong bucket, because it isn't filed at all. The **Port bucket** (`[Shop]`, visible) keeps ADR-0009's two-per-zone placement, and Start and Goal stay fixed and terminal.

ADR-0009's per-zone shuffled encounter-**kind** bag becomes a per-zone shuffled **recipe** bag; the deal-evenly-across-the-zone's-nodes property is unchanged.

### Zone hard-maps to stage count: Coastal 1, Open Sea 2, Deep 3

A zone draws from exactly one stage-count bucket: **Coastal 1 → Open Sea 2 → The Deep 3**. Not a weighted mix — a hard mapping, so the zone ladder is legible as "encounters get longer" on top of ADR-0009's per-zone stakes ladder.

Pacing survives it because ADR-0009's layers are 4–6 wide: a run traverses only ~3–4 nodes per zone (~11–14 of the ~50 points), so a Deep zone is a handful of 3-stage encounters, not sixteen. A player who wants a shorter run can route shallow deliberately.

### Visibility is stage-derived, not a node fact

An encounter is **visible on the map iff it contains a revealing stage** — today only `Shop`. Visibility stops being a `Node_Kind` property and becomes a question asked of the stage list. ADR-0009's Variant A presentation is unchanged in every other respect: the graph is always drawn; a non-revealing encounter's content stays hidden until arrival.

The consequence is the one that motivated it: **shops are no longer Port-exclusive**. A Port is `[Shop]` placed by the Port bucket, and a merchant vessel at sea is a hidden encounter that happens to carry a Shop stage — the same primitive, placed differently.

### Stakes, not difficulty

`Scaling_Site` (zone tier + depth) is a **stakes** gradient, not a difficulty one: it says *how much is on the line here*, and each primitive reads it through its own per-tier/per-depth constants — Fight as opponent power, Reward as treasure, Offer as item quality, Trade as swing size, Shop as stock quality. ADR-0009's "difficulty and reward rise with zone and depth" is one axis named twice; stakes is the name that covers both, and the only one that means anything for a Trade or an Offer.

Accordingly **`Ghost_Snapshot.difficulty_rating` is retired as a misnomer**. `run_apply_stat_trade` already shoves `gain_durability` into it — a Stat Trade has no difficulty, only stakes — so the field is already lying in the code that fills it. All scaling constants stay code-level named constants (ADR-0006/0007/0009's convention).

### Variance is per-stage content rosters, not a trait layer

There is **no orthogonal trait-modifier layer** — no trait bag, no trait/stage compatibility matrix, no runtime trait rolling. A stage primitive *is* the trait, and variance comes from each stage rolling content from **its own roster**: Fight gains a hostile roster (retiring the one-opponent template), Trade gains a roster of stat axes (unwelding +Durability/−Speed), and Offer keeps ADR-0012's item roster.

Two standing constraints from ADR-0012 and ADR-0013 bind all of this:

- **No runtime RNG.** An encounter's recipe *and* every stage's content are baked at map generation, a pure function of the run seed. Nothing rolls on arrival — the property ADR-0013 already holds for Port decks now covers every stage.
- **Content is plain data — no function pointers** — a closed parameterized set, so a `Ghost_Snapshot` can carry it (ADR-0008, ADR-0012).

### Port cross-visit persistence drops (superseding ADR-0013)

A Port is now an ordinary encounter that happens to be `[Shop]` and visible, so ADR-0009's encounter-fires-once rule applies to it: **a Port resolves once**, its `port_shelves` persistent per-node state collapses, and the draw cursor and purchase record no longer survive a visit.

ADR-0013 chose persistence so that "I saw an item I want; I'll return for it" would hold. That plan was **already near-moot in practice**: with a fixed starting purse and no way to earn treasure, walking back to a Port you had already shopped could not pay off — you would arrive with less money than when you left, at the shelf you already declined. The persistence machinery served a case that barely arose, and it bought that case with the only per-node mutable run state in the Sim.

The `Reward` stage does change the premise — treasure can now be earned, so a return trip *could* pay off — but repeatability stays dropped for now: it is a pacing question worth answering with a played build rather than a preserved mechanism. ADR-0013's **multi-buy loop within a single visit survives** unchanged (buy → Refit → back to the shop → only Leave exits); it is only the *cross-visit* half that goes.

## Consequences

- `core/run` gains a stage/recipe data model and a recipe catalog; `Encounter_Kind`, the per-kind Encounter variants, and the per-kind `sim_*.odin` files are deleted. The Sim gains **one** generic stage-walking path with complete-or-halt semantics, replacing per-kind phases, Commands, and Events.
- Adding an encounter becomes a catalog edit — the acceptance test for this effort is that a new encounter touches no enum, no union, no Sim phase, and no new file.
- `Ghost_Snapshot.difficulty_rating` is retired; ADR-0008's Progress definition (which names it, and cites ADR-0007's since-retired port-proximity nuance as its reason to exist) loses that field. What a `Ghost_Snapshot` carries in its place rides on the stakes work.
- The Sim loses its only per-node mutable run state (`port_shelves`, ADR-0013). Port shops become baked, once-resolved content like every other encounter.
- Fight and Trade gain content rosters, so the "two of three kinds have no variance" gap closes without a trait layer. Trade's welded +Durability/−Speed axis becomes one roster entry among several.
- The UI must render an arbitrary stage sequence rather than three known screens, including communicating a **halt** as a consequence (you fled, so you don't get the loot) rather than as a bug. How it paces multi-stage transitions is left to the build — it needs something watchable to judge.
- ADR-0009's presentation gains one wrinkle: visibility is now asked of an encounter's stages, so a visible non-Port node (a merchant vessel) is possible and the renderer can no longer key off landmark-ness.
- Deliberately left open: per-zone recipe eligibility beyond stage count (hard mapping means stage count is the only filter today), the stakes constants per primitive, and what a second `Fight` in one recipe (`[Fight, Fight, Reward]`, legal under the 3-stage bucket) plays like with HP carrying between them. All three want a played build.
- Out of scope for this effort and unchanged by it: the Item Offer redesign, economy tuning (including ADR-0013's deferred cost escalation, closed as deferred in #124), branch graphs (stages advance by cursor; no per-outcome successor tables — the gate field can widen later without restructuring callers), and runtime trait rolling.

See GitHub issue #127 for the encounter-model effort and its design tickets, #88 for the build-variance effort this follows, and ADR-0012 / ADR-0013 for the roster and shop decisions it builds on.
