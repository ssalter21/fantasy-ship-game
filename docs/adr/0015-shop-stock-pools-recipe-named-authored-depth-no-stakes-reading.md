# ADR-0015: Shop stock pools — recipe-named, authored depth, no stakes reading

## Status

Accepted. **Completes the supersession of ADR-0013** that ADR-0014 announced: ADR-0013's cross-visit persistence is gone (retired in #131) and its whole-roster deck is gone (retired here), leaving only its multi-buy-per-visit loop and its shelf window standing — both re-justified below on new grounds, because ADR-0013's own reasons for them are dead.

**Amends ADR-0014's "a recipe is a name plus an order over primitives"**: a recipe authors a stage *spec*, which is a primitive plus what that primitive cannot draw for itself. Today that is one field on one primitive (a Shop's stock pool). Everything else in ADR-0014 — the closed primitive set, complete-or-halt, recipes-picked-not-composed, stage-count buckets, stage-derived visibility, stakes-not-difficulty — carries forward unchanged, as do ADR-0012's roster/tags/tiers/Refit decisions.

**Retires `Node_Kind.Port`**, reaching the `Start | Encounter | Goal` end state ADR-0014 named.

## Context

ADR-0014 made `Shop` a stage primitive rather than a property of a Port, so a merchant vessel at sea can carry one. That left three questions it deliberately did not answer, and #131 left a fourth as doc debt.

**Shops had no content roster.** Every other primitive now has one — Fight draws a hostile archetype (#135), Trade draws an axis (#136), Offer samples the item roster — but every shop in the game was the same shop: the full item roster, shuffled. Once Shop stopped being Port-exclusive that became untenable, because the two things carrying Shop stages are not alike. A **Port** is guaranteed — the Port bucket places two in every zone — so routing to one is a plan the map always honours. A **merchant vessel** competes for a slot in its zone's stage-count bucket and may not appear at all. If both drew the same stock, "merchant vessel" would be nothing but "a Port somewhere else".

**The whole-roster deck had outlived its reason.** ADR-0013 gave each Port a shuffled deck of all ~50 roster items because its draw-down *persisted across every visit in the run*, so a deck had a whole run to be chewed through. #131 retired that persistence — an encounter is walked once, so there is no second visit to persist into — which left a 50-card deck that a single visit can reach about 13 cards into. Roughly 37 cards were baked into every shop on every map and could never be looked at.

**Whether a shop reads its node's stakes was explicitly reopened.** ADR-0013 stocked as-authored, reasoning that cost already rises with tier so a quality bonus would double-count it. Every other primitive reads `Scaling_Site`, which makes Shop the odd one out and worth re-asking.

**#131 changed ADR-0013's behaviour but wrote no ADR.** This is the record.

The options considered for the stock pool:

- **Draw the pool freely from a roster**, the way a Fight draws its archetype. Rejected: it makes which-shop-is-this a per-node accident, so a Port could roll a six-card specialist hold and the routing promise the bespoke placement exists to make would become a gamble. #135's reason for drawing freely does not transfer — it is about *power* (an archetype three times another would swamp the stakes gradient), and a narrow pool is not weaker, only narrower.
- **Derive the pool from the bucket** — Port bucket gets the broad pool. Rejected: that is a content exception for a bucket, which is exactly what #134 deleted when it made a Port draw its `[Shop]` recipe like any other node.
- **Name the pool on the recipe.** Chosen.

## Decision

### A Shop's stock pool is authored content, named by the recipe

A **stock pool** is a named row in the Shop primitive's content roster — the analogue of a hostile archetype or a trade axis — and a recipe carrying a Shop **names which pool it sells from**. This is the one content roster that is chosen rather than sampled, and that is the whole point: it is what lets "Port" mean *the general store* and a merchant vessel mean *a hold full of one thing*.

A recipe therefore authors a **stage spec** — a primitive plus what that primitive cannot draw for itself — rather than a bare primitive. The pool is carried as an optional field, set on a Shop spec and absent on every other, so a pool is explicitly absent rather than accidentally the zero pool. The widening stays deliberately narrow: a field earns a place here only when a primitive genuinely cannot draw the thing itself, and this is not a re-entry point for the orthogonal trait layer ADR-0014 rejected.

### Stocking "differently" means subset and size — not tier weighting, not price

A pool authors two things:

- **Subset** — the Tag families it stocks, the roster's own authored family axis (ADR-0012). A hold of Weapons is an ordnance hoy; a hold of Beasts is a menagerie. Filtering on Tag rather than round Category is deliberate: a Category is a combat *phase*, so a "Defensive shop" says when its wares fire, not what they are.
- **Size** — how deep the hold is, and so the **reserve** behind the shelf, which is what a purchase draws on.

The Port's pool is the **Chandlery**: no family filter at all, and deep enough that the shelf is still full when the starting purse runs out. Specialist pools are one family and shallow enough that the second purchase of a visit already bares a slot. That difference lands inside the two or three buys a real visit makes, rather than at some theoretical exhaustion.

A chandlery's "no filter" is the *absence* of a predicate rather than a list of every family, so it keeps stocking a sixth Tag the day one is authored without the table being edited to remember it.

**Tier weighting is rejected** because it is the stakes question below. **Price is rejected** as economy tuning, which this effort rules out of scope, and because a per-pool discount would collide with #124's depth surcharge — the one price knob that already exists.

### A Shop reads no stakes at all — the gradient is the purse, not the shelf

Shop is the **one primitive that ignores its own node's `Scaling_Site`**, and it keeps no per-tier/per-depth constants.

ADR-0013's reason survives — cost already rises with tier, so scaling an item's magnitudes on top would charge once and pay twice — but it is no longer the main one. The stronger reason arrived with #133: **a Reward's payout is site-scaled** (20/tier + 5/depth), so depth already means *more treasure*. A shop that also improved with depth would compound the same progression from both ends: richer captain **and** better shelf. So the market is a fixed market, and what changes as a run goes deeper is the purse a captain brings to it.

This makes Shop's exception legible rather than anomalous. Every other primitive scales what it *presents*; a shop is the one whose gradient sits on the player's side of the table.

### The shelf window and refill-on-buy survive — on #124's reason, not ADR-0013's

A shop still shows a five-card **shelf** onto its stock, and buying still refills the bought slot from the stock behind it. ADR-0013's reason for the window was cross-visit draw-down, which is dead.

It earns its place on a different reason now: **#124's depth surcharge**, which charges more for each successive buy at one shop, only means anything if buying reveals something new. Show the whole stock at once and the surcharge degenerates into a flat "buying more costs more" tax on a menu the captain has already read. Behind a window it is the price of *digging* — spend a little to see what else is in the hold — which is the decision a shop exists to pose.

What the window no longer hides is a whole roster. A shop's stock is now what a shop actually has.

**Running a shop dry is content, not a defensive branch.** ADR-0013 called exhaustion "not a practical concern" and handled a short tail only "gracefully". A narrow hold is now meant to be emptied.

### `Node_Kind.Port` is retired

`Node_Kind` reaches ADR-0014's end state: `Start | Encounter | Goal`. Start and Goal are landmarks by graph *position*, which no stage list can express; everything else is an Encounter and what it holds is asked of its stages.

`.Port` shrank in three steps — ADR-0014 took its visibility, #134 took its content, #131 took the last thing that read it — leaving a value that marked only *how a node was placed*, which nothing asked and which quietly implied a Port was a different sort of place than a merchant vessel carrying the same primitive. Generation still places Ports bespokely; it just tracks them locally for as long as that matters (until their recipes are dealt) instead of staining the node for the rest of the run.

## Consequences

- ADR-0013 is now fully superseded. Of its four decisions, cross-visit persistence (#131) and the whole-roster deck (here) are gone; multi-buy-per-visit and the shelf window survive on new reasons; its deferred cost escalation shipped as #124 and is now what justifies the window.
- A shop's stock shrinks from the whole item roster to its pool's authored depth. **Generated maps do not move**: the Chandlery applies no filter, so its shuffle is identical to the old whole-roster deck's and a Port's stock is an exact prefix of the deck it used to bake. Only the unreachable tail is gone.
- The Sim's shop state indexes a stock position rather than a deck position, and a shelf slot with nothing behind it is now reachable in normal play.
- Four specialist pools are authored but unreachable until #138 writes the recipes that name them — the same split #135 made when it authored eight hostile archetypes against a catalog holding a single `[Fight]`. Authoring a merchant-vessel recipe here would deal it into a zone's stage-count bucket and reshape every seed's map, which is #138's call.
- The map view labels a revealing encounter **"Shop"** rather than "Port": the label comes from the stage, and a baked Encounter does not carry its recipe's name. Naming a revealed encounter properly is #139's, along with rendering an arbitrary stage sequence.
- A Chandlery is not infinite: buying all twelve cards out at the cheapest tier costs 450 against a starting purse of 50. The claim the depth supports is the reachable one — the purse gives out first.

See GitHub issue #137 for this decision, #127 for the encounter-model effort, ADR-0013 for the Port shop this supersedes, ADR-0014 for the stage model it extends, and #138 for the catalog that will name the specialist pools.
