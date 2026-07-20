# ADR-0030: Visibility is the slot's, and an item may require exposure

## Status

Accepted — **supersedes ADR-0005** in full. The three-layer precedence chain (slot base visibility → fitting-level override → ship/captain-level forced override) is retired: layer 2 is deleted along with the `Fitting.visibility_override` field that implemented it, and layer 3 — never implemented — is withdrawn as an anticipated extension point rather than left standing. A fitting's visibility is the visibility of the slot it sits in, and nothing else.

In its place, a fitting may state a **requirement**: `Fitting.requires_exposed`, checked at fit-legality time beside ADR-0004's size gate.

## Context

Issue [#407](https://github.com/ssalter21/fantasy-ship-game/issues/407), under the item-authoring effort ([#363](https://github.com/ssalter21/fantasy-ship-game/issues/363)), closes the Fitting's field set. The visibility override was one of the fields it had to answer for.

ADR-0005 wrote the override as a symmetric per-item escape hatch: an unmissable artifact forces itself exposed, a hidden assassin forces itself concealed. Two things have happened since.

**Concealment became a real resource.** Visibility is a countable Selector axis, a readable quantity (`Own_Visibility`), and the filter a scouting report applies (`ship_scouting_report` shows only exposed fittings). Items are authored against all three — *Ghost Lantern* and *Wraith Cannon* pay out while concealed, *Smuggler's Crates* and *Storm Caller* count concealed fittings. The ship template has four exposed slots and four concealed ones, and a captain who wants a concealed build is choosing which four items go below.

**An override makes that resource free.** An item that declares its own concealment carries its slot's scarcity in its pocket: it takes a concealed reading out of an exposed slot without giving anything up, so the four-and-four split stops binding for exactly the items that care about it most. Nothing was priced for that, and the power budget ([#408](https://github.com/ssalter21/fantasy-ship-game/issues/408)) has no term for it — an override is capacity the budget cannot see.

The mirror image is the interesting one. A *requirement* spends the same scarcity in the opposite direction: an item that must be flown where it can be seen costs its captain one of four exposed slots, and competes there against the guns. That is a real trade, made out of the layout the ship already has, with no new state anywhere.

## Decision

**Effective visibility collapses to the slot's base visibility.** `ship_effective_visibility` is deleted rather than reduced to a pass-through — with nothing to resolve, a resolver is a lie about the model. Its four callers (the Selector match, the census, the expression context's `Own_Visibility`, and two UI readers) read `layout_slot.slot.base_visibility` directly.

**`Fitting.requires_exposed: bool` replaces `visibility_override`**, checked in `ship_fitting_fits` alongside the size match — so install, replace and move are all held to it by construction, at the one seam all three already share.

**A `bool`, not a `Maybe(Visibility)`.** Widening a requirement later is free and narrowing one is not: `requires_exposed` can grow into a `requires: Maybe(Visibility)` the day an item needs to demand concealment, while a symmetric field authored today would be an override in a second costume — a "requires concealed" item, in a layout where concealment is the cheaper half, asks for nothing. The zero value is also the honest default: an item with nothing to say about visibility fits anywhere its size allows.

**The zero value that lied dies by construction.** The deleted `Fitting.category` defaulted to Brace, so a hold or an effect-less fitting silently counted as a Brace item. `requires_exposed`'s zero value costs nobody anything, which is why it needs no authoring-helper guard of the kind `bulk` needs (`roster_item` names it as a defaulted parameter, and that is the whole of its authoring surface).

**A Fitting is POD with exactly one mutable instance field, `cargo_held`.** The stronger "immutable POD" claim is precisely false and nothing may be built on it. What the weaker claim buys is what matters: a Fitting stays plain data, so a Ghost_Snapshot's one-level copy of the slot slice remains sound (ADR-0008).

**No roster item requires exposure yet.** The field is authorable through `roster_item` and unused by the fifty; an item that wants it is content work, priced by #408.

## Consequences

- **The Fitting's field set closes** at `name, size, weight, bulk, cargo_held, tags, requires_exposed, effects, effect_count`. `category`, `visibility_override`, `passive`, `active`, the `Condition` union and its five variants, and `Selector`'s `Category` axis are all gone.
- **Concealment is contested rather than declared.** Every item that reads concealment must be *put* below deck, spending one of four concealed slots to do it — which is the property the concealed-synergy items were authored against and never actually had.
- **A future ship/captain forced-visibility capability is unanticipated, by choice.** ADR-0005 reserved layer 3 for it. Nothing has asked for it in the years since, and reserving a precedence position for a capability nobody has designed is what turned a one-line read into a three-layer chain in the first place. If one arrives, it will be designed then, against the code that exists then.
- **The move gate tightened.** `ship_move` used to compare sizes itself; it now goes through `ship_fitting_fits` like the other two, so an exposure-requiring fitting cannot be installed legally and then smuggled below.
- **The UI's two drop-affordance predicates ask the rule instead of restating it.** `build_is_legal_berth` and `offer_shop_legal_berth` compared sizes themselves; both now call `ship_fitting_fits`. The offer shelf's drop is *gated* on its predicate — which is what lets the bridge auto-finish — so a second copy of the rule there would have shown an exposure-requiring item a legal berth and then bounced it off the Sim.
- **ADR-0004 is untouched.** The exact-size fit rule stands; this adds a second, independent gate beside it rather than amending the first.
- **The retired vocabulary is recorded, never un-said.** ADR-0005 keeps its text and takes a Status back-pointer here (the precedent ADR-0004 set for ADR-0012 and ADR-0020); CONTEXT.md's *Effective visibility* entry is replaced and the three-layer chain filed under the `_Avoid_` convention (ADR-0021).

See GitHub issue [#407](https://github.com/ssalter21/fantasy-ship-game/issues/407) for the ticket, and ADR-0005 for the chain this retires.
