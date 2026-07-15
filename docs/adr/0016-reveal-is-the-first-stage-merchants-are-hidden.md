# ADR-0016: Reveal is the first stage — merchants are hidden

## Status

Accepted. **Amends ADR-0014's "visibility is stage-derived"**: an encounter is visible on the map iff its **first** stage reveals, not iff it contains a revealing stage anywhere. Everything else in ADR-0014 carries forward unchanged — the closed primitive set, complete-or-halt, recipes-picked-not-composed, stage-count buckets, stakes-not-difficulty — as does ADR-0015's stock-pool model, whose narrow-holds argument this vindicates rather than disturbs.

A new ADR rather than errata on ADR-0014: ADR-0014 never said "first stage" in either of the two places it discussed visibility, so the reconciling mechanism is genuinely new, and it changes the Sim's hiding contract.

## Context

ADR-0014 says two things about a merchant vessel, and they disagree:

- §Visibility: an encounter is "**visible on the map iff it contains a revealing stage**" — which is what the code did.
- §Visibility's motivating consequence: "a merchant vessel at sea is a **hidden** encounter that happens to carry a Shop stage."

Nothing could observe the contradiction until there was a merchant to look at. Issue #138 authored one, and the any-stage scan resolved it in favour of the first line: every recipe carrying a Shop anywhere revealed itself before arrival. That produced a tell nobody designed. A revealed encounter is labelled by its first stage, so Press Gang `[Fight, Shop]` drew a **"Battle"** marker while a plain Sea Battle `[Fight, Reward]` stayed hidden — meaning a *visible* Battle marker told the captain a market waited behind that fight. Two encounters that should be indistinguishable before arrival were not.

The crux turned out not to be about visibility at all. It is: **is a merchant vessel something the captain can plan a route to?**

- If **yes**, revealing it is right, and ADR-0015's stock-pool reasoning needs re-justifying — it made a merchant's hold narrow and strange precisely because "nothing is planned around a windfall".
- If **no**, it must be hidden, and the §Visibility line is the wrong one.

The answer is **no**. A merchant is a *windfall*: you meet one, you don't route to one. This gives a clean two-tier design — **plan for Ports, stumble into markets** — and it means ADR-0015 is sound exactly as written, not in need of repair.

The options considered:

- **Reveal iff any stage reveals** (the status quo). Rejected: it makes merchants plannable, contradicts ADR-0014's own stated intent, and leaks the tell above.
- **Reveal iff any stage reveals, but name the marker honestly** so a `[Fight, Shop]` reads as such. Rejected: it fixes the tell by *confirming* the plan, which is the thing being ruled out. Naming cannot help, because the objection is not about the marker.
- **Reveal iff the first stage reveals.** Chosen.

## Decision

### An encounter reveals iff its first stage reveals

`run_encounter_reveals` asks stage 0 instead of scanning. `run_stage_kind_reveals` stays as the per-primitive predicate — "Shop is the revealing primitive" is still the right factoring, and it leaves room for a second revealing primitive without re-opening this.

ADR-0014's §Visibility rule is corrected accordingly. Its consequence line — "a merchant vessel at sea is a hidden encounter that happens to carry a Shop stage" — **stands verbatim**; it was the intent all along.

### The honest cost: the predicate now derives a constant

Weighed and accepted. `catalog.odin`'s `only_the_port_bucket_opens_on_a_shop` convention means the Port recipe is the only thing in the game whose first stage is a Shop. So the predicate returns true for the Port bucket and false for everything else — which is `Node_Kind.Port`, the weld ADR-0015 spent a PR deleting, computed rather than stored. ADR-0014's "visibility is stage-derived, not a node fact" stays true in *form* while deriving a constant.

Not decisive, because the derivation is contingent on an **authoring convention, not a type-level fact**: author one `[Shop, Fight]` and it stops being constant, whereas `Node_Kind.Port` was a fact no recipe could dislodge. That is a real difference in kind — but it is thinner than the claim reads, and it is recorded here rather than left for a future reader to discover.

### The map goes uniformly dark, and that is the intent

Counted against today's catalog, this is bigger than a merchant-hiding tweak. **The Deep carries a Shop in 4 of its 5 recipes** (only Kraken's Wake doesn't), so ~12 of its ~15 nodes reveal themselves today and **afterwards 2 do** — its Ports. Open Sea drops from ~4 visible to 2. Coastal is unchanged, already 2.

So the change **inverts the zone gradient**: The Deep is currently the game's *most* legible zone, and afterwards all three are identically dark — two Ports each, everything else a surprise. Depth stops meaning anything for what the captain can *see*.

Bought deliberately, on ADR-0015's own argument: **information is not a gradient here, stakes are** (site-scaled treasure, opponent power). A second gradient on visibility would compound the same progression from both ends — the exact reason ADR-0015 kept Shop from reading stakes. The Deep reading as unknown is also thematically right.

## Consequences

- The unintended tell dies completely: a visible Battle marker no longer means a market waits behind the fight, because there is no visible Battle marker. What replaces it is sharper and has no exceptions — **Shop marker ⟺ Port ⟺ the Chandlery's general market**, one learnable rule.
- **`only_the_port_bucket_opens_on_a_shop` gains a second justification** and needs no new reasoning. Its original one is untouched (a Shop-opening merchant draws a Port's marker and is a counterfeit Port). It now *also* implies merchant hiddenness, because "opens on a Shop" ≡ "reveals" ≡ "is a Port". A Port's three facts — visible, guaranteed, general-stocked — collapse to one cause.
- **The 1-stage bucket is four permanently.** #138 reserved the fifth shape (`[Shop]`) rather than closing it, on the theory that the blocker was an ambiguous marker — a UI accident a naming pass could fix. It cannot: a `[Shop]` merchant opens on a Shop, so it reveals, so it is plannable, so it is forbidden regardless of naming. The reason upgrades from a UI accident to a model fact.
- **ADR-0015 is undisturbed.** Its narrow-holds argument assumed a merchant is a windfall; this makes that true rather than asserted.
- Every seed's **map is unchanged** — nothing about baking or the RNG stream moves, only what the mask withholds. The change is observable in `sim_mask_encounters` and the renderer's `node_appearance`, not in generation.
- The renderer's scope shrinks: there is exactly **one** kind of revealed encounter to name (the Port), plus visited nodes. Note that reveal is defined on stage 0 while the label reads the **cursor**; they coincide for an unvisited node, and must not be allowed to drift apart silently.

See GitHub issues #154 (the decision) and #161 (this record), ADR-0014 for the encounter-stage model this amends, and ADR-0015 for the stock pools whose windfall premise it settles.
