# ADR-0004: Unified "fitting" concept in a sized, non-spatial ship layout

## Status

Accepted, partially amended by ADR-0012 (build variance). The "Deferred/out of scope" note below — no fitting roster beyond the three starting fittings plus their upgraded variants — is retired there. The slot / unified-fitting / exact-size-fit-rule model carries forward unchanged; ADR-0012 extends the fitting with tags, data-driven context-sensitive effects, and stat-modifiers on top of it. **Further amended by ADR-0020** (the weight economy): **cargo stops being effect-less.** This ADR calls cargo "the one special case: stackable and effect-less" — under ADR-0020 a cargo fitting **is the ship's money**, so it has an effect (it is the treasure), and it is the one fitting whose **weight is its contents rather than its size** (an empty hold weighs nothing). Cargo still contributes nothing to a combat *phase*, but it is no longer inert. **Further amended by ADR-0030** (#407): a fitting no longer has "an effective visibility" of its own — visibility is the slot's alone — and the passive/active effect pair described below is long gone (an effect names its own verb and phase, ADR-0029). The exact-size fit rule stands, now with a second, independent gate beside it: a fitting may require an exposed slot. The slot/fit-rule model is otherwise untouched. See ADR-0020 and ADR-0030.

## Context

Issue #4 asked for the minimal ship & crew model for the vertical slice: what a ship consists of, what a crew member consists of, and how many of each are needed.

Two shapes were considered for the ship's build space:

- A true spatial grid (or polyomino packing, Backpack Battles–style), giving geometric placement and an information-hiding angle (hide valuable cargo in an unusual spot).
- An abstract slot budget with no geometry at all.

A geometric/spatial angle was wanted (it supports a "hide your cargo" mechanic relevant to the ghost-based async PvP model), but full 2D packing was judged too much engine/UI complexity for a slice whose stated goal is a minimal, headless-testable crew/ship model.

Separately, crew members, weapons, cargo, and quarters were initially treated as distinct types competing for the same slots, which would mean maintaining several parallel type systems all needing size/visibility/attachment logic.

## Decision

- A ship's layout is a **fixed list of slots**, each with a **size** (small / medium / large) and a **base visibility** (exposed / concealed). No coordinates, no shapes, no rotation/packing.
- Anything that occupies a slot — crew member, weapon, cargo, quarters, or any other fantasy entity — is a single unified **fitting** concept, not separate types. A fitting has a size, an effective visibility, a name, and a passive and/or active (auto-triggering) effect. Cargo is the one special case: stackable and effect-less.
- The **fit rule is exact size match** — a fitting can only occupy a slot of its own size. Downsizing (small fitting in a large slot) is not allowed.
- Slot names (e.g. "gun deck") are flavor labels only; they impose no type restriction on what can fill them.

## Consequences

- The layout system is arithmetic-simple and headless-testable — no packing/collision algorithm to write or debug, consistent with the project's headless/UI-split architecture goal (issue #3).
- Because the fit rule is exact-match, large slots are not strictly dominant over small ones — committing to a slot mix at ship-design time is a real tradeoff, not a formality. This is intentionally easy to loosen later (e.g. large slots becoming more broadly capable at some cost) without restructuring the model.
- Unifying crew/weapons/cargo/quarters under one "fitting" concept means new fantasy content (a bound elemental, a cursed figurehead) needs no special-casing to be a slot occupant — it just needs a size and an effect profile.
- Deferred/out of scope for this slice: ship layout variety (only one ship template), and a fitting roster beyond the 3 starting fittings plus their upgraded variants.
