# ADR-0013: Port shop — persistent per-port deck, refill-on-buy, deferred cost escalation

## Status

Accepted. Amends ADR-0012's "Acquisition — Item Offer and Port shop" decision. Everything else in ADR-0012 (the roster, tags, effects, manual loadout, tiers) carries forward unchanged, as does the fixed-purse economy. This ADR only revises *how a Port shop presents and dispenses its stock* — the shape of the interaction, not the roster it draws from.

## Context

ADR-0012 committed to a Port shop as "a stock of purchasable items; buying deducts from `starting_treasure`," under a deliberately minimal economy. Issue #98 (PR #121) implemented that literally: each Port baked a flat stock of 4 tier-priced roster items, buying one opened a Refit to place it, and the Sim then returned to a travel choice. Two properties fell out of that minimal reading that, on review, undersell the mechanic:

- **One purchase per visit.** A buy's Refit finished back at `Awaiting_Travel_Choice`, so a player who wanted a second item had to leave the Port and walk back. A "shop" that ejects you after one purchase.
- **A static, shallow shelf.** Four fixed items per Port, never refilling, gave a shop no depth: once you had seen its four, there was nothing more to find there ever.

The question this ADR settles is what a Port shop should feel like across a whole run, given the economy stays a **fixed one-time purse** (treasure is spent, never earned — ADR-0012). The options considered:

- **Reshuffle each visit** — a fresh random shelf every arrival. Rejected: with a fixed purse there is nothing to "come back for," and it turns pacing back and forth into a reroll button. It also defeats the plan a player most wants to make — "I saw an item I want; I'll return for it" — because the item is gone on return.
- **Persistent per-port deck** — each Port owns a stable, seed-baked shuffled deck of the roster; the shelf is a window onto the top of the deck; buying draws the deck forward; the cursor and purchases persist across visits. Chosen.

## Decision

### A Port shop is a persistent per-port deck, drawn down over the run

Each of the map's Ports bakes, at generation time, its **own shuffled deck of the full item roster** — deterministic from the run seed, like every other generated feature. The shop presents a **shelf of the top 5** cards. This replaces #98's flat 4-item stock.

### Buying refills the shelf from the deck; you may buy until you leave

Buying an affordable shelf item deducts its tier price, opens the Refit to place it (unchanged from ADR-0012), and on the Refit's finish **returns to the shop** rather than to a travel choice. The bought slot **refills by drawing the next card off the deck**. A player may therefore keep buying within a single visit — digging as deep into that Port's deck as the purse allows — and only an explicit **Leave** returns to travel. An unaffordable buy is still refused and the shop stays open (ADR-0012's "an unaffordable item cannot be bought").

### The deck and purchases persist across visits

A Port is a revisitable landmark (ADR-0009). Its draw cursor and the items already bought from it **persist for the rest of the run**: revisiting shows the same shelf minus what you took, so an item seen earlier is still there to come back for, and a Port already dug deep does not reset. Because each Port owns a distinct deck, **run variety comes from checking Port against Port**, not from rerolling one. This persistent per-Port state is new: #98 kept none, treating the shop as stateless baked content.

### Cost escalation with depth is designed but deferred

The intended pressure that makes port-hopping the main play — **each successive purchase at a given Port costing more**, so draining one shop deep is expensive — is deliberately **not built in this slice**. It is a genuinely new economic curve that wants playtest tuning, and it is cleanly separable from the deck/refill mechanic above. It is recorded here and ticketed as the next step. The leading shape is an **additive per-Port surcharge**: `price = tier_base + step × (items already bought at this Port)`, with `step` a single placeholder constant — but the shape is not committed, and no numbers are fixed until playtest, matching ADR-0012's placeholder-economy convention.

## Consequences

- ADR-0012's Port-shop decision is amended: a shop is a persistent per-Port deck with a 5-item shelf and refill-on-buy, not a flat static stock, and multi-buy per visit replaces one-buy-then-eject. The fixed-purse economy, tier pricing, free Item Offers, no sell-back, and the shared Refit placement flow are all unchanged.
- The Sim gains **persistent per-Port runtime state** (a draw cursor and purchase record keyed by Node) — the first per-node mutable run state the shop has needed. A revisited Port must resume its cursor, not re-present a fresh shelf.
- The shop's post-buy phase transition changes from `Awaiting_Travel_Choice` to re-entering the shop; only Leave exits to travel.
- Reachable deck exhaustion is not a practical concern: a fixed purse buys a handful of items against a full-roster deck, so a shelf can always be filled in practice; the implementation still handles a short tail gracefully.
- Cost escalation is left open as a follow-up ticket under the build-variance effort (#88); this ADR is the record of *why* it is separate and what its intended shape is, so deferring it does not lose the design.
- Reproducibility is preserved: the deck is a pure function of the run seed (no runtime RNG draw), so a seed's Ports remain fully determined before play — the same property #98 and the rest of the map generation hold.

See GitHub issue #88 for the build-variance effort, #98 / PR #121 for the minimal implementation this revises, and the two follow-up tickets (persistent-deck implementation, and deferred cost escalation).
