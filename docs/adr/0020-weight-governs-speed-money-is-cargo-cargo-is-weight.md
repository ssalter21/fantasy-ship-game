# ADR-0020: Weight governs Speed — money is cargo, and cargo is weight

## Status

Accepted. **Amends ADR-0006** (Speed becomes a derived stat, `JETTISON_SPEED_BONUS` retires, and the "claimed by the opponent as spoils" settlement is demoted to flavour and deleted), **ADR-0004** (cargo stops being effect-less — it *is* the money, and its weight is its contents rather than its size), **ADR-0012** (`Modify_Speed` items modify a term in a derived stat, and the Shop's spend no longer reads a `starting_treasure` field), and **ADR-0011** (records the deliberate decision *not* to give weight and treasure `distinct` types, and why). Builds on **ADR-0008** (a `Ghost_Snapshot` is a wholesale copy of a ship's fittings, so weight and purse ride along with them for free) and **ADR-0010 / issue #52** (the run-scoped arena block that outlived a tick to settle jettison is deleted here). Recorded before the code changes, exactly as ADR-0014 (#128) was for the encounter model.

## Context

Two number systems in the game were **denominated incompatibly, and nothing caught it**. Item costs are Splash 10 / Shallow 25 / Deep 45 against `STARTING_TREASURE :: 50`; ship capacity was denominated in *slots* — Small 1 / Medium 2 / Large 3, plus a base and a captain bonus. The starting purse was ~5× what the hull could physically carry, and a single Deep item cost 4× the hull's entire slot capacity. `ship_cargo_capacity` computed a number **no non-test caller read**; `Fitting.stack_count` was pinned at `CARGO_STACK_COUNT :: 1` and documented as counting stacked cargo units nothing counted; `combat_settle_jettisoned_cargo` returned a `[]ship.Fitting` **nothing received**. Three inert pieces, a 5× denomination gap, and a `starting_treasure` field that floated free of everything physical about the ship.

The effort (issue #143) was charted as *"money takes space"* — treasure relocated into slots. A grilling session redrew it. Money merely *taking space* costs you slots you'd rather give to guns: real, but indirect, and treasure stays fundamentally an `int` living somewhere else. **Weight is what makes taking space cost something.** Laden is slow; slow cannot escape; so getting rich is what makes you catchable, and Jettison Cargo becomes "how much money will I pay for how much Speed, right now, with someone shooting at me." Speed that is **emergent, not granted**.

The model was **not** fully grilled during charting, so eight decisions were resolved as their own tickets before this recording (the tracking issue is the index): the unit system (#156), the ceiling and overflow (#157), the weight→Speed curve (#158), sinking and spoils (#159), the starting stow (#172), the hostile fill (#176), the Speed floor (#175), and the straddle test (#177). This ADR records them as one canon. A prototype (PR #173) validated the curve against #135's hostile roster.

## Decision

### The destination

**Weight governs Speed, and money is weight.** Every fitting weighs what its size weighs; a cargo fitting **is** the treasure, and weighs it. `Ship.starting_treasure` is gone — a ship's purse *is* the treasure in its hold. A ship's Speed reads its weight, so getting rich is what makes you catchable. Sinking a ship pays you the hold that was slowing it; what you heave overboard is gone for good.

Reaching the end means, as a test a reader can apply: **there is no number on a ship representing money, and no ship's Speed can be read without asking what it is carrying.**

### The unit system: one unit is one treasure (#156)

Weight, capacity, and money are **the same scale** — the fix for the denomination gap is to make the two number systems commensurable, not to reconcile two rates. One unit of capacity holds one unit of treasure and weighs one unit of weight. Capacity grows to *meet* money rather than money re-pointing to meet capacity: a **Small** hold holds 10, a **Medium** 20, a **Large** 40 (×10 and *doubling*, so a Large hold is worth four Smalls). The 8-slot hull therefore holds **90** against a **50** purse — headroom by construction, so **no money constant re-points**.

- **Cargo weighs its contents, 1:1.** An empty hold weighs nothing; a full Small weighs 10. Cargo is the one fitting whose weight is *not* its size.
- **Non-cargo weight is authored per item**, in the same band as a full hold of its size (Large ~30–45, Medium ~15–25, Small ~5–12) — a *balance* choice per item, the knob that makes a strong item pay for its strength, not a mechanical derivation from slot size.
- Consequence, for free: **guns are permanently heavy, cargo only while full**, so **emptiness — not loadout — is what varies**, and the "a bruiser is slow" property survives.

### The curve: `speed = base + modifiers − weight/10` (#158)

Speed is **derived, not authored**, and stays an `int` (the standing constraint: "more variable, not a threshold" means derived, *not* float — every escape gate, tie-break, and `Condition_Opponent_Faster/_Slower` depends on integer comparison). Weight enters as a **subtrahend, not a replacement**: ADR-0012's `Modify_Speed` items and #136's Speed-granting Trade axes still have `modifiers` to land in.

- **The divisor is the exchange rate, and 10 is forced.** #156's ×10-and-doubling capacity table then *is* the Speed table ÷10 (Small hold = 1 Speed, Medium 2, Large 4). Any coarser divisor makes jettisoning a Small hold buy **0 Speed** — a no-op jettison, worse than the `JETTISON_SPEED_BONUS :: 1` it retires.
- **`base` is one constant, not per-hull, and a *calibration*** — whatever makes the starting ship read `STARTING_SPEED`. So `STARTING_SPEED :: 4` stops being the Speed a ship *has* and becomes the Speed it *reads*, and **`Ship.speed` stops varying between ships**. The prototype's placeholder `base` of 16 falls out of placeholder weights and re-points when the real ones land.

### The ceiling is structural; overflow is lost; free reallocation makes it fair (#157)

Treasure lives only in cargo fittings, which live only in finite slots — so weight punishes hoarding but **stores nothing above capacity**. There is no soft cap: overflow above capacity is **lost**.

- **`ship_cargo_capacity` survives, redefined** — the size contribution of every slot *not* carrying a non-cargo fitting (empty slots included). A broke ship reads 90, not the old base-plus-bonus 3. **A slot spent on a gun is money you cannot carry** — the refit tension, exactly.
- **`STARTING_BASE_CARGO_CAPACITY`, `CAPTAIN_CARGO_CAPACITY_BONUS`, `Ship.base_cargo_capacity`, and `Captain.cargo_capacity_bonus` are deleted** — unfillable (room no slot provides), not merely homeless.
- **Reallocation is free outside battle; a captain's order costs the round inside it.** Reallocating shifts no weight, only *jettison granularity*, so the in-combat order buys **precision** (shed exactly 10, gain exactly 1 Speed): tempo paid for treasure saved.
- Falls out: **the richer you are, the coarser your jettisons must be.** Fine granularity lives in the three Smalls (30 total); at ~90 the Large *must* be full and the cheapest thing you can heave is a 40. Getting rich takes away your ability to buy Speed *cheaply* — a second mechanism for free.
- **"Hold" is retained as the collective term for all of a ship's cargo fittings** (so "your hold is full" means treasure has met capacity). The per-slot "a hold" — an installable container distinct from both the slot and the treasure — does **not** exist; the domain has slots and the cargo fittings in them, nothing between.

### Sinking pays the wreck's hold; jettisoned cargo is destroyed (#159)

- **Sinking a ship pays you its hold as it stands** — the real cargo slots, not a baked amount. A deep hostile is slow *because* it is rich and worth catching *for the same reason*, from one number.
- **Only a wreck pays** ("you loot a wreck, not a winner"): `run_finish_ship_battle`, which today reads only `escaped`, must learn `End_Reason.Destroyed` (winner `.A`) from `.Round_Cap`. A round-cap stalemate pays nothing.
- **Jettisoned cargo is destroyed, never claimed.** ADR-0006's "claimed by the opponent as spoils" was never observable (the opponent is discarded when the encounter ends) and, read literally, would make jettison *free* whenever you win — dump your purse for Speed, collect it off the wreck. It is **retired as flavour**. Jettison collapses to **null the slot, emit the event**; `combat_settle_jettisoned_cargo`, `battle.jettisoned`, and the run-scoped arena block in `sim_process_battle_round` (issue #52's machinery) are **deleted, not wired**.
- Does **not** reopen #132/#133: a Fight paying out of its own opponent reads no neighbour, so `[Offer, Reward]` (the Derelict) is untouched.

### `JETTISON_SPEED_BONUS` dies rather than scales

If Speed reads weight, dropping a hold makes you faster *because the ship is lighter* — proportional, for free. `JETTISON_SPEED_BONUS :: 1` and `battle.perm_speed` both retire, and no "scale the bonus by weight dropped" mechanic is ever written. The jettison assert (`combat_apply_jettison` requires `has_fitting && fitting.is_cargo`) already does the work that keeps an empty hold from being heaved for free Speed — an empty hold weighs nothing, so there is no Speed in it to buy. **No new rule.**

### The starting 50: stowed by a rule, and the captain names part of it (#172)

- The amount gets an owner: **`STARTING_CARGO :: 40`** (ship configuration, beside `STARTING_HP`) **+ `CAPTAIN_STARTING_CARGO :: 10`** (Odessa) = **50**. `Ship.starting_treasure` the *field* still dies — no purse number rides on a ship at runtime; "a full purse" becomes **derived** from the sum.
- **Placement is a rule, not authored numbers**: `ship_stow_treasure(layout, amount)` fills **smallest slots first**. The starting stow is three Smalls at 10 + the Medium at 20 = **50 exactly**, with the Large (forecastle) **empty** as visible headroom — the player starts at the *fine* end of #157's granularity property, and the empty Large teaches the ceiling before a Reward costs a payout.
- **This reverses #157's vestigial `Captain`.** `Captain.cargo_capacity_bonus` stays deleted (unfillable); `Captain.starting_cargo_bonus` is added and **fillable** — it adds treasure into the 40 of headroom #157 established. The 40/10 split makes the captain lever *live* rather than ornamental, exercised by the only captain in the game.
- Scoped to the player's bootstrap only: **`ship_fill_empty_slots_with_cargo` survives for the hostile**, whose fill #176 sets at a flat 50%. The two rules are deliberately different — the hostile's is a placeholder for templates, the player's a designed default.

### A hostile's cargo is a flat 50% full (#176)

Neither the archetype (#158's authored purse) nor the site (#159's depth gradient) owns a hostile's richness: both are **deferred**, and a hostile's cargo is **a flat 50% of capacity**, provisionally, until hostile ship *templates* exist to derive richness from. So **`Hostile_Archetype.speed: int` is replaced by no claimant** — a hostile's Speed falls out of its weight like every other ship's. Fill being a constant means depth moves no hostile's Speed, so "the site never moves a hostile's Speed" (#135's disowned Fight stat) is **re-derived, not overturned**. The flat fill *sets* a Fight's payout at **30–65** (half of capacity) against a Reward's 20–45 — so #157's overflow becomes the **mainline** result of winning a Fight.

### The Speed floor is 0, and it never fires (#175)

Speed floors at 0 as an **authoring invariant, asserted** (`assert(base − weight/10 >= 0)`) — **never** a live `max(0, …)` clamp. Negative is out on fiction (a ship is not blown backwards; at 0 you have *brought the sails in*), and that reframing dissolves every objection to a floor, because each objection is an objection to a *clamp that fires* — collapsing distinct weights onto one reading. Author so nothing reads below 0 and the clamp is never written: **jettison at 0 always buys Speed** (0 is the genuine bottom, not a clamp hiding a −1), and the forced divisor survives.

- **`base` is not a free parameter** (it is the calibration above), so the budget is the *spread*: **`STARTING_SPEED × divisor = 40`** is the entire weight headroom above the starting ship. It is satisfied today with **zero slack at exactly one point** — the player's full hold lands on 0 *precisely*, because capacity − starting purse = 90 − 50 = 40 = the budget.
- No tie-break at 0, and it was never undefined: `combat_speed_tiebreak`'s `winner` is written and never read by non-test code, strict `>` already deadlocks at *every* equal value (three of #135's archetypes tie the player's 4 today, shipped), a mutual kill ends the run by permadeath, and a round cap does not pay.
- This binds the hostile-template work #176 defers to: #158's 159–179 fittings-plus-capacity band *is* the fully-laden band, so any template pushing fill toward 100% breaches the invariant, and the assert is the tripwire.
- **Scoped to the weight term because it cannot be total** — a Speed *modifier* (Braced Bulkheads, `cost = .Speed`) spends the same 40 at runtime and cumulatively across a run, so no authored weight can bound it. What a modifier may do on top of this invariant is **#180**, still open (see Consequences).

### The straddle test comes forward, pinned to the player's purse (#177)

Under this model the player's Speed *is not `STARTING_SPEED`* — it is whatever their purse says (9…0 across purse 0–90). So "does the roster straddle 4?" is not well-formed: straddle is a joint property of (roster, player purse). #135's straddle test is forward-ported with its shape **unchanged** (≥1 hostile slower, ≥1 faster) and changed **only** to pin the player's purse **explicitly** at `STARTING_CARGO + CAPTAIN_STARTING_CARGO` — it may **not** read `STARTING_SPEED` and infer 4. It asserts a **point** at the starting purse, **not** a window-with-bounds: leaving the window as the player gets rich is the *feature* (the win → too-laden-to-catch → spend-or-jettison → hunt-again loop), and a rigid `±D` assertion would fight the per-hostile Speed/weight tuning that is playtest data, never locked in code. The model re-creates #135's flat-`FIGHT_OPPONENT_SPEED` failure at *both* ends (0 slower / 8 faster at low hostile ladenness; 8/0 at a broke player), so this test is the only thing standing between the model and the failure it can re-create.

### Weight and treasure do **not** earn `distinct` types (amending ADR-0011's application)

ADR-0011 asks any effort touching confusable domain quantities to decide whether they earn `distinct` types. The finding: **they do not**, and the reason *is* the model.

- #156 collapsed treasure, capacity, and weight onto **one scale** — a treasure weighs exactly 1, non-cargo weight is authored in the same units. "Money is weight" is therefore *literally true at the value level*: a cargo fitting's treasure count and its weight contribution are the same integer. A `Treasure` / `Weight` split would force a conversion at the exact seam the model exists to make seamless.
- The hazard ADR-0011 guards against here was a **denomination** bug (slots vs treasure, ~5×), and the fix was to make the two systems **commensurable**, not incomparable. Distinct types make incompatible things *not compile*; these things were made *compatible*.
- The one genuine scale change — weight to Speed — is the `/10` divisor, and it lives in exactly one place (`ship_effective_speed` / `combat_effective_speed`). Speed stays `int` per ADR-0011's own carve-out (a stat, not a confusable identifier), as do HP, Durability, and the treasure/weight counts.

## Consequences

- **This ADR is canon only — no code changes** (as ADR-0014/#128 was). It gates the migration, Speed-reads-weight, jettison, spoils, Shop, and Trade execution tickets, whose shape it fixes.
- **The migration** retires `Ship.starting_treasure` and every reader of it (`run_trade_pay`, the Reward payout, the Shop spend at `sim_encounter.odin`) moves to ask the layout instead of a field. `content_test.odin:240`/`:243`'s `deep <= STARTING_TREASURE` must compare against the **sum** `STARTING_CARGO + CAPTAIN_STARTING_CARGO` (`45 <= 40` fails otherwise, silently inverting "a full purse buys one Deep item").
- **Speed-reads-weight** gives `ship_effective_speed` / `combat_effective_speed` a weight term and retires `JETTISON_SPEED_BONUS` and `battle.perm_speed`. Because `Ship.speed` stops varying between ships, whether the field *survives or collapses into a constant* is **coupled to #180**: if it collapses, `run_trade_pay`'s `s.speed -= cost.amount` has no home. That decision is deferred to #180, not taken here.
- **#180 is the one open corner of this model.** `base + modifiers − weight` records that a Speed modifier still lands, but *what a Speed-cost or Speed-granting Trade axis does under weight* — subtract a modifier or add ballast, and what bounds a cumulative Trade cost once the hold fills — is unresolved. #175's invariant is deliberately scoped to the weight term for exactly this reason. The model is complete for everything except the modifier term's semantics.
- **The authoring pass** (the ~50 item weights + re-derived hostile Speeds, one ticket because `base` calibrates against the weights and every purse sits on them) spends a 40-point budget with **zero slack** at the starting purse; `assert(base − weight/10 >= 0)` at every ship's maximum reachable fill is a hard acceptance criterion, and #135's straddle test (pinned purse, ≥1 each side) comes forward unchanged.
- **ADR-0008 is unamended but load-bearing**: a `Ghost_Snapshot` already carries fittings as plain data, so weight and purse ride along with a captured ship and an opponent's engine reads its Speed off its hold with no new field. `sim_encounter.odin:213` shallow-copies `Stage_Fight`, so `opponent.layout` aliases the map node's backing array — latent today, but the spoils payout will *read that layout*, which the migration must handle.
- **Out of scope, recorded so it is not mistaken for a bug:** hostile ship *templates* (#176) — the flat 50% fill is the placeholder standing where template work will land; six of eight archetypes outrun a starting player and the Deepwater Menagerie inverts worst (authored slow at 3, reads 7) because it flies the player's 8-slot hull with 130 of capacity it never uses. No fill percentage fixes that; only a hull sized for the build does. Also out of scope: general economy retuning (item costs, #124's surcharge, `REWARD_TREASURE_PER_*`, the Trade swing table — #127's tuning fog owns these); the captain's *other* mechanical levers beyond `starting_cargo_bonus`.
- **UI** (fog): showing weight, and a purse that is the hold rather than a number; reading the ceiling *before* a Reward, now that overflow is mainline. **Mast configuration** is the cosmetic read-out of Speed — never an input — and **0 renders as "sails in"** rather than a number that looks broken; both are new vocabulary this ADR seeds into the glossary.

See GitHub issue #143 for the effort and its map, #160 for this recording ticket, and #156 / #157 / #158 / #159 / #172 / #175 / #176 / #177 for the decisions recorded above. Amends ADR-0004, ADR-0006, ADR-0011, ADR-0012; builds on ADR-0008 and ADR-0010.
