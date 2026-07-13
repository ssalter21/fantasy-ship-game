# ADR-0012: Build variance — a real fitting roster, context-sensitive data-driven effects, stat-modifying fittings, manual loadout, and item acquisition

## Status

Accepted. Amends ADR-0004. ADR-0004's core model — a fixed list of sized/visibility-tagged slots, a single unified **fitting** concept, and the exact-size fit rule — carries forward unchanged. This ADR retires ADR-0004's explicit deferral of "a fitting roster beyond the 3 starting fittings plus their upgraded variants" and extends the fitting model along the axes that let a run's ship diverge from every other run's. It also builds on ADR-0006 (fitting categories / phased combat) and ADR-0008 (the Ghost_Snapshot must be able to carry a fitting's effect as data).

## Context

The vertical slice (issue #4, ADR-0004) deliberately shipped no build variance: one ship template, three starting fittings, and — as findable content — only *upgraded variants of those same three*. Every run's ship therefore converged on the same handful of shapes. ADR-0004 called this out explicitly as out of scope, flagged for a later effort.

The build-variance effort (issue #88, from a grilling session; child tickets #89–#98) is that effort. Its destination: testers can build meaningfully different ships within a run by acquiring and installing distinct items that carry tag synergies and conditional effects. Reaching it needs several decisions that ADR-0004 left open, and that the rest of the effort's tickets all lean on. This ADR records them so the shared vocabulary exists before the code does; it is the first child ticket (#89) and changes no code.

Two constraints shaped the decisions:

- **Ghosts carry effects (ADR-0008).** A `Ghost_Snapshot` is a wholesale copy of a ship's state used as an opponent. Whatever an effect *is*, it must survive being copied into a snapshot and resolved by an opponent's engine — so an effect cannot be a code pointer or a closure. It has to be **plain data**.
- **Fittings had no reach outside their phase (ADR-0006).** An ADR-0004/0006 fitting only contributes output to its one combat phase. Real build variance wants fittings that change the ship itself (a sturdier hull, a faster one) and fittings whose worth depends on the rest of the build — neither of which the flat-constant effect model could express.

## Decision

### A real fitting roster (was: three fittings plus upgraded variants; #97)

A run now draws from a **roster of distinct items** — target **~50** — rather than the three starting fittings and their upgrades. The roster spans the five tag families (below) and the full effect vocabulary (below), authored as **data**, and feeds the acquisition channels (below). The upgraded-variant model is retired as the source of findable content; the three starting fittings remain as the fixed opening loadout.

### Tags — five families, independent of phase (#90)

Every fitting carries one or more **tags**, drawn from five **families**: **Crew, Weapon, Beast, Artifact, Cargo**. A tag is **independent of a fitting's combat phase** (ADR-0006's Buff / Defensive / Offensive) and of its slot size/visibility — it is a separate classifying axis, not a re-labeling of phase or category. A fitting **may hold more than one tag**; multi-tag is allowed but used sparingly. Tags exist to be *counted*: they are the axis synergy effects (below) select over. Tagging alone changes no behavior.

### Effects are data-driven and context-sensitive (was: bare per-phase constant; #92, #93, #94)

An ADR-0004 effect was effectively a bare constant contributed to one phase. It is generalized to a **data-driven effect resolvable against a context** — the effect's magnitude is *computed at resolve time* from the context it sees, rather than stored as a fixed number. The context is the owning ship (its current layout and effective stats) and, for combat, the live battle/opponent state. Effects remain **plain data — no function pointers, no closures** — so a `Ghost_Snapshot` can carry a fitting's effect and an opponent's engine can resolve it (ADR-0008). The parameterized effect kinds form a **closed set**, not open-coded behavior.

The effect vocabulary:

- **Flat effect** — a constant magnitude that ignores context. **Most items stay flat.** The three starting fittings port to this form with byte-identical combat output.
- **Stat-modifier effect** — see below.
- **Synergy effect** (#93) — magnitude scales with the **count of installed fittings matching a selector**, where the selector ranges over **tag / size / visibility / category**. Resolved against the owning ship's current layout at resolve time (so it rises as matching fittings are added and falls as they are removed). A multi-tag fitting counts once for *each* of its tags. Example: "for each Weapon aboard, +Offense."
- **Conditional effect** (#94) — magnitude is **gated by a battle- or ship-state trigger**, evaluated per round against live state. Triggers cover at least: HP threshold, round number, own concealment, and opponent faster/slower. Example: "below half HP, +Offense" contributes nothing above the threshold.

**Synergy** and **conditional** are the two effects whose magnitude genuinely depends on context; together they are what "context-sensitive" names. Flat and stat-modifier resolve against context too (the model is uniform) but a flat effect ignores it and a stat-modifier reads only the owning ship.

### Fittings may modify ship stats (was: fittings only feed a combat phase; #92)

A fitting can carry a **stat-modifier effect** that adjusts the ship's **effective Durability / Speed / Max HP**, not just contribute to a combat phase. Combat and escape logic read a ship's **effective stats** (base fields plus installed modifiers), never the raw base fields. This gives fittings reach over the ship itself — a hull that trades a slot for durability, a rig that trades one for speed — which the phase-only model of ADR-0004/0006 could not express.

### Manual loadout, no inventory (was: auto-replace on pickup; #95)

The player arranges the ship's fittings **manually**, through Sim commands to **install / move / remove** a fitting across slots, with full placement agency. ADR-0004's exact-size fit rule is enforced on every placement; an illegal placement is rejected without disturbing the layout. There is **no inventory**: a fitting pulled fully off the ship is **discarded** — nothing holds an un-installed fitting. Each loadout change emits an Event. Rearranging the loadout this way is a **Refit**.

### Acquisition — Item Offer and Port shop (was: Upgrade Offer auto-replace; #96, #98)

Two channels put roster items on a ship, both feeding the same Refit flow:

- **Item Offer** — the ADR-0007/0009 **Upgrade Offer** encounter kind is **repurposed** into an Item Offer: it presents a few *distinct roster items* (or a skip), and picking one opens the loadout to place or swap it via the manual-loadout commands. The old same-category auto-replace path is retired. Item Offers are **free**.
- **Port shop** — a **Port** (ADR-0009) becomes a shop presenting a stock of purchasable items; buying **deducts from the ship's `starting_treasure`** and an unaffordable item cannot be bought. Purchases are placed through the same Refit flow.

The economy is deliberately **minimal**: a fixed starting budget (`starting_treasure`), Item Offers free, shop purchases paid. No broader currency, no sell-back.

### Item tiers — Splash / Shallow / Deep (#97)

Roster items are graded across three **tiers** — **Splash** (lightest / cheapest / weakest), **Shallow** (mid), **Deep** (strongest) — echoing the run's Coastal → Open Sea → The Deep progression. Tier scales an item's power and its shop cost; it is a catalog-authoring axis, not a new runtime system. The redlined catalog (the "Ship's Manifest" artifact) fixes each item's tier before the roster is authored as data (#97).

## Consequences

- ADR-0004's "no fitting roster beyond the three starting fittings" deferral is closed. ADR-0004's slot/fitting/fit-rule model is otherwise untouched and should be read alongside this ADR (as it already is alongside ADR-0006).
- The `Fitting` type gains a tag set and a data-driven effect (a closed set of flat / stat-modifier / synergy / conditional kinds) in place of a bare per-phase constant. The effect stays plain data so it round-trips through a `Ghost_Snapshot` (ADR-0008).
- Combat and escape read **effective** ship stats. Any code path today reading raw Durability / Speed / Max HP during a battle must route through the effective-stat resolution once stat-modifier fittings exist (#92).
- The hull grows to accommodate real variety (8 slots — Large x2 / Medium x3 / Small x3, 4 exposed / 4 concealed) — recorded as its own ticket (#91), consistent with ADR-0004's note that the slot mix is a real design tradeoff and easy to widen.
- The Upgrade Offer encounter kind's *name and behavior* change (Item Offer), but the encounter-kind slot in ADR-0007/0009's map model is unchanged — the map still deals three kinds per zone.
- Ports gain a shop interaction and a minimal spend economy on `starting_treasure`; the broader run economy ADR-0006 left open stays open (this is the minimum needed to make acquisition a choice).
- Effect magnitudes, the ~50 roster size, per-tier power/cost, and the fixed budget are **placeholder tuning**, expected to move in playtest without reopening this ADR — matching the ADR-0006/0009 placeholder-constant convention.

See GitHub issue #88 for the effort and its grilling notes, #89 for this recording ticket, and #90–#98 for the child tickets that implement each decision above.
