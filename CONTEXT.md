# Context: Fantasy Ship Game

Single-context repo. See `docs/adr/` for the decisions behind these terms.

## Glossary

### Engine core (headless/UI boundary)

**Sim**:
The single mutable core simulation state for a run — ships, crew, combat, RNG. Has no dependency on rendering or input devices; the same `Sim` runs identically headless or under a UI.
_Avoid_: Game state, world

**Command**:
An operation submitted to the Sim that mutates its state (e.g. submitting a captain's decision). The only way presentation is allowed to affect the Sim.
_Avoid_: Action, input

**Event**:
A fact emitted by the Sim describing something that happened (e.g. `DamageDealt`, `AwaitingCaptainDecision`). The only way presentation learns what happened inside the Sim.
_Avoid_: Message, notification

**Tick**:
One call to the Sim's step procedure. Resolves an entire round of auto-battler logic instantly and batch-emits that round's Events. Not tied to real/wall-clock time — a Tick is a logical sim step, not a rendered frame.
_Avoid_: Frame, step (when referring to rendering)

**run_session**:
The single driver loop, shared by headless and UI, that calls Tick, dispatches Events to an Event_Sink, and asks an Input_Source for a captain's decision whenever the Sim is awaiting one.

**Input_Source**:
The pluggable source `run_session` asks for a captain's decision. Headless mode supplies a scripted or seeded-random one; UI mode supplies one that renders a decision menu and blocks until the player picks.

**Event_Sink**:
The pluggable destination `run_session` dispatches a Tick's Events to. Headless mode logs or records them; UI mode plays them back with animation, blocking until playback finishes.

**Headless mode**:
Running a session with no rendering — used for tests, simulation, and ghost-battle resolution. Compile-time incapable of importing the rendering library (a separate executable, not a runtime flag).
_Avoid_: Simulation mode, test mode

**UI mode**:
Running a session with a human player and real-time rendering.
_Avoid_: Game mode, client mode

### Ship & crew model

- **Ship** — a run's vessel. Owns a small set of top-level stats (HP, Durability, Speed, starting treasure) and a fixed **layout**. Combat power itself comes from what's installed in the layout, not from the ship directly.
- **HP** — the ship's health, persisting across an entire run rather than resetting per encounter. Reaching 0 sinks the ship and ends the run (permadeath). See ADR-0006.
- **Durability** — a damage-reduction/resistance stat applied to all incoming damage instances, as a flat per-hit reduction (`final_damage = max(0, raw_damage − Durability)`). Not a separate decaying resource — it modifies HP loss, it isn't a second health pool. See ADR-0006.
- **Speed** — the ship's stat governing when it may disengage from combat: once a battle passes its baseline round count, the higher-Speed ship may leave. Also breaks ties in a same-round mutual kill and in round-cap stalemate resolution. See ADR-0006.
  _Avoid_: Initiative, turn order — combat resolves simultaneously by fixed phase, not by Speed-based turn order.
- **Starting treasure** — a one-time amount of starting capital the ship begins a run with. Not a capacity.
- **Layout** — the fixed set of **slots** a ship template defines. No grid/coordinates and no shape packing — slots are discrete, sized, named containers.
- **Slot** — a single unit of ship layout. Has a **size** (small / medium / large) and a **base visibility** (exposed / concealed). Slot names (e.g. "gun deck") are flavor only and impose no restriction on what can fill them.
- **Fitting** — the single, unified concept for anything that occupies a slot: crew members, weapons, cargo/quarters, or other fantasy entities (creatures, magical objects). Deliberately not split into parallel type systems. A fitting has a size, an effective visibility, a name, a **category** (Buff / Defensive / Offensive — see ADR-0006), a set of **tag families**, and a passive and/or active (auto-triggering) effect.
- **Tag family** — one of five families (Crew, Weapon, Beast, Artifact, Cargo) a fitting belongs to, independent of its combat phase/category. A fitting carries a *set* of them: usually one, occasionally more (multi-tag is allowed but used sparingly). This is the axis the build-variance effort's synergy effects count fittings along; on its own it drives no behavior.
- **Cargo** — the one special-cased fitting: stackable, generic, effect-less filler that consumes capacity but contributes no combat effect. (Carries the Cargo tag family.)
- **Cargo capacity** — a baseline ship stat, adjusted up or down by which slots get allocated to cargo vs. other fittings.
- **Fit rule** — a fitting may only occupy a slot of the exact matching size (see ADR-0004 for why, and for the flagged extension point).
- **Effective visibility** — a fitting's visibility as actually observed by an opponent (e.g. when scouting a ghost snapshot), resolved through a three-layer precedence: slot base visibility → fitting-level override → ship/captain-level forced override. See ADR-0005.
- **Captain** — a run-start choice, structurally separate from the slot system (not a fitting, consumes no slot). Can influence a ship's slot limits/structure and grants additional manual per-round captain actions.

### Combat resolution (see ADR-0006)

- **Round** — one unit of battle resolution: the captain's decision is applied, then fitting effects resolve through the Buff → Defensive → Offensive phases. Corresponds to one Tick.
- **Phase** — one of the three fixed stages (Buff, Defensive, Offensive) a round resolves through, in that order. Both ships resolve a phase together (simultaneous, not sequential-by-Speed); a ship's own fittings within a phase trigger in fixed slot order. Every fitting belongs to exactly one phase.
- **Leave Combat** — a captain decision, available once a ship's Speed exceeds its opponent's after the battle's baseline round count, that ends the battle immediately for both ships without destruction.
- **Jettison Cargo** — a captain decision that empties a cargo-filled slot for a permanent Speed increase for the rest of the battle. Settled at battle end: lost if the jettisoning ship escapes, claimed by the opponent as spoils otherwise.
- **Man the Sails** — a captain decision granting a temporary Speed increase, lasting that round only.

### Map & run structure (see ADR-0009, superseding ADR-0007's topology/ports/gradient; encounter terms amended by ADR-0014)

- **Run** — one playable attempt from Start to Goal (or to permadeath). Not resumable/saved — save/resume and meta-progression between runs are not yet specified.
- **Node** — a single location in the run's map. The map is a procedurally-generated connected graph, regenerated fresh each run (seeded, reproducible); a node carries **edges** to other nodes and, if it's an encounter, a stage list whose content is hidden until arrival unless it contains a revealing stage.
  _Avoid_: point, tile.
- **Edge** — a directed connection between two nodes. Edges are only ever generated forward (layer *i* → *i+1*), but at runtime are walkable both ways: forward into new territory, or backward to an already-visited node.
- **Layer** — nodes are generated in ordered layers (a few wide); edges connect adjacent layers. A node's position across layers within its zone is its **depth**.
- **Zone** — one of three fixed **stakes** bands, generated as three sequential phases in a fixed order: Coastal (nearest Start, lowest stakes) → Open Sea (mid) → The Deep (nearest Goal, highest). Stakes rise with zone. A zone also **hard-maps to an encounter's stage count** — Coastal 1, Open Sea 2, The Deep 3 — so encounters get longer as well as steeper (ADR-0014).
- **Depth** — a node's layer index within its zone's phase, normalized to a fixed range. Stakes rise with depth, stacking on top of the per-zone gradient, and every stage primitive reads the gradient through its own constants. Replaces ADR-0007's retired port-proximity ("contested waters") effect.
- **Stakes** — how much is on the line at a node: the single gradient `Scaling_Site` (zone tier + depth) expresses, which each stage primitive reads through its own per-tier/per-depth constants — Fight as opponent power, Reward as treasure, Offer as item quality, Trade as swing size, Shop as stock quality. Renames ADR-0009's "difficulty" gradient, which was one axis named twice and meant nothing for a Trade or an Offer.
  _Avoid_: difficulty — it only ever described the Fight reading.
- **Start** — the run's origin node; also the home port. A landmark.
- **Goal** — the run's destination node. Reaching it with HP > 0 wins the run. Carries no port and no encounter. A landmark.
- **Landmark** — Start or Goal: a node carrying no encounter (never triggers one) and always fully visible on the map. Port left this category in ADR-0014 — it is an encounter (`[Shop]`) that is visible because Shop reveals, not because it is exempt.
- **Port** — an encounter node holding the one-stage `[Shop]` recipe, placed by the Port bucket — two per zone (six) plus Start — each **consuming** one of its zone's node slots rather than being added on top. Visible on the map because Shop is a revealing stage, not because it is a landmark: a Port is an ordinary encounter and, since ADR-0014, resolves once like any other.
- **Encounter** — a non-landmark node's content: an ordered list of **stages** plus a cursor, walked once on **first** arrival (no decline option); revisiting a node never re-triggers it. The only way to avoid an encounter is to route around its node. There is exactly one Encounter type — the interaction it presents is its stage list, not a kind tag (ADR-0014).
- **Stage** — one step of an encounter: a **stage primitive** plus the content it was baked with. An encounter walks its stages in order, and each resolves to **completed** or **halted**.
- **Stage primitive** — one of five values a stage is drawn from: **Fight, Offer, Trade, Shop, Reward**. A closed set — adding an encounter must never require adding a primitive. A primitive *is* the trait: there is no orthogonal trait layer, and variance comes from each stage's own content roster.
  _Avoid_: encounter kind, trait.
- **Complete / Halt** — the two outcomes of a stage, and the whole of an encounter's control flow. **Completed** advances the cursor to the next stage; **halted** ends the encounter there, keeping whatever earlier stages already granted. The primitive defines which is which — Fight: victory completes, Leave Combat halts, sinking ends the run; Offer: pick completes, skip halts; Trade: accept completes, reject halts; Shop: leaving completes; Reward: always completes. Recipes author **no** gates.
- **Recipe** — a named, authored stage set: the unit of encounter content. `Sea Battle = [Fight, Reward]`; `Derelict = [Offer, Reward]`. Generation **picks a whole recipe** and each of its stages rolls content from its own roster — generation never composes a stage list. Mix-and-match is a developer authoring tool, not a runtime generative system.
- **Bucket** — a pool of recipes plus a placement rule. The 1-/2-/3-stage buckets are dealt per zone via a shuffled **recipe bag** (ADR-0009's kind bag, renamed), and membership is **derived** from `len(recipe.stages)`, never authored. The Port bucket (`[Shop]`) is placed two per zone; Start and Goal are fixed and terminal.
- **Encounter kind** — **retired** (ADR-0014). Was: the one type of interaction a node presented (Ship Battle / Upgrade Offer / Stat Trade), as an enum mirrored by a union variant, Sim phases, Commands, Events, and a `sim_*.odin` file per kind. The three kinds are now one-stage recipes: Ship Battle → `[Fight]`, Item Offer → `[Offer]`, Stat Trade → `[Trade]`.
- **Fight** — the stage primitive for a full battle against an opponent ship, resolved via the phased-round combat system (ADR-0006). Mechanically identical to a future ghost-PvP battle; this slice's opponents are not real players' stored snapshots. Draws its opponent from a **hostile roster**, retiring the single hand-tuned opponent template.
- **Offer** — the stage primitive presenting a few *distinct roster items* (or a skip) and opening a Refit to place or swap the pick. Free. Formerly the **Upgrade Offer** encounter kind (same-category auto-replace of a starting fitting), repurposed as the **Item Offer** by the build-variance effort (ADR-0012, #96) and now a primitive in its own right.
- **Trade** — the stage primitive for a permanent stat-for-stat or stat-for-cargo trade-off. Draws its axis from a roster; the +Durability / −Speed swap that was the whole of the old Stat Trade kind is now one entry among several.
- **Reward** — the stage primitive that grants something outright and always completes. What it grants is not yet settled.

### Ghost snapshots and async PvP (see ADR-0008)

- **Ghost_Snapshot** — a captured copy of a ship's current state (stats, layout/fittings, captain) plus its run progress (steps taken, zone), used as the opponent-ship representation for a Fight stage. The same struct serves both this slice's hand-authored PvE opponents and, eventually, real players' captured state — there is no separate opponent-config type.
- **`Ghost_Snapshot.difficulty_rating`** — **retired as a misnomer** (ADR-0014). It was meant to carry a node's tuned difficulty number, but a Stat Trade has no difficulty — only **stakes** — so `run_apply_stat_trade` already passes `gain_durability` into the field, and the code that fills it is already lying about what it means. Stakes (`Scaling_Site`: zone tier + depth) is the concept that survives.
- **EncounterResolved** — the Event the Sim emits after an encounter resolves, carrying a fresh `Ghost_Snapshot` of the ship's state at that point.
- **Hold** — a `Command` variant that is a formal no-op: a scripted (non-player-controlled) ship submits it every round except when automatically taking Leave Combat once escape-eligible. Scripted opponents never choose Boost/Man the Sails/Jettison Cargo in this slice.
  _Avoid_: assuming a scripted opponent's Input_Source needs randomness — it doesn't; see ADR-0008.

A `Ghost_Snapshot`'s HP always resets to the ship's max/base HP at capture time, regardless of the real ship's current run-persistent HP — a ghost is a decoupled copy that may be fought independently by multiple opponents, while the real player's own HP keeps degrading normally on their own run. Hand-authored PvE opponents may still set HP to any explicit value as a difficulty knob.

### Build variance: tags, effects, and acquisition (see ADR-0012, amending ADR-0004)

- **Tag** — a classifying label a Fitting carries, independent of its combat phase (ADR-0006) and of its slot size/visibility. Exists to be *counted* by synergy effects, not to restrict placement. A fitting may hold more than one; multi-tag is allowed but used sparingly.
  _Avoid_: type, class — a tag imposes no fit restriction, unlike slot size.
- **Tag family** — one of the five values a Tag is drawn from: **Crew, Weapon, Beast, Artifact, Cargo**. A closed set.
- **Context-sensitive effect** — a fitting effect whose magnitude is *computed at resolve time* from the context it sees (the owning ship, and for combat the live battle/opponent state) rather than stored as a fixed number. A **closed parameterized set** of plain data — no function pointers — so a Ghost_Snapshot can carry it (ADR-0008). Synergy and conditional are its two genuinely context-dependent kinds; flat and stat-modifier resolve against the same context but a flat effect ignores it and a stat-modifier reads only the owning ship.
  _Avoid_: scripted effect, effect callback — effects are data, not code.
- **Flat effect** — an effect with a constant magnitude that ignores context. The common case: most roster items are flat, and the three starting fittings port to this form (see ADR-0012).
- **Synergy effect** — an effect whose magnitude scales with the **count of installed fittings matching a selector** (over tag / size / visibility / category), resolved against the owning ship's current layout. Rises as matching fittings are added and falls as they are removed; a multi-tag fitting counts once per tag.
- **Conditional effect** — an effect whose magnitude is **gated by a battle- or ship-state trigger** (at least: HP threshold, round number, own concealment, opponent faster/slower), evaluated per round against live state.
- **Stat-modifier effect** — an effect that adjusts the owning ship's **effective Durability / Speed / Max HP** rather than feeding a combat phase. Combat and escape read *effective* stats (base fields plus installed modifiers), never the raw base fields.
- **Splash / Shallow / Deep tier** — the three power/cost grades a roster item is authored at — Splash (lightest / cheapest) → Shallow (mid) → Deep (strongest) — echoing the Coastal → Open Sea → The Deep run progression. A catalog-authoring axis, not a runtime system.
- **Refit** — rearranging a ship's fittings by hand through Sim install / move / remove commands, enforcing ADR-0004's exact-size fit rule. There is **no inventory**: a fitting pulled fully off the ship is discarded, and every loadout change emits an Event.
  _Avoid_: inventory management — nothing holds an un-installed fitting.
- **Item Offer** — the Upgrade Offer encounter kind repurposed: presents a few *distinct roster items* (or a skip) and opens a Refit to place or swap the pick, retiring the old same-category auto-replace. Free. Now the **Offer** stage primitive (ADR-0014).
- **Shop** — the stage primitive presenting purchasable roster items; buying deducts from the ship's **starting treasure** and places the item through a Refit. Stock is seed-baked; buying refills the shelf and returns to the shop, so a visit can buy repeatedly until you **leave** (which completes the stage). Minimal economy: fixed starting budget, Offers free, shop purchases paid, no sell-back. See ADR-0013 (revising ADR-0012) for the multi-buy loop, which survives; cost escalation with purchase depth is designed but deferred (#124, closed as deferred).
  Shop is **not Port-exclusive** — it is a **revealing** stage (an encounter containing one is visible on the map), so a Port is just the `[Shop]` recipe, while a merchant vessel at sea is a hidden encounter carrying a Shop stage. Its **cross-visit persistence is dropped** (ADR-0014 superseding ADR-0013): a Port resolves once like every other encounter, and `port_shelves` — the Sim's only per-node mutable run state — collapses. ADR-0013's persistent per-Port deck existed so a player could return for an item seen earlier, but with a fixed purse and no way to earn treasure, a return trip could never pay off.

## Vertical-slice scope (see GitHub issue #4)

- One fixed ship template: 8 slots (issue #91, ADR-0012) — Large x2, Medium x3, Small x3, split 4 exposed ("top deck", "top crew", "gun deck", "forecastle") / 4 concealed (one medium plus three small holds).
- Fixed starting loadout: "Top Crew", "Captain's Quarters", "Gun Deck" fill three exposed slots; cargo fills every remaining slot by default, each cargo filler sized to its slot (issue #91).
- Findable content is limited to upgraded variants of those same three fittings (e.g. "Upgraded Gun Deck") — no separate fitting roster. _(Superseded by the build-variance effort's ~50-item roster — ADR-0012, #97.)_
- Exactly one captain.
- Map: a procedurally-generated connected node graph, Start/home port → Coastal → Open Sea → The Deep → Goal, ~50 points (17/17/16 per zone) of which 44 are encounters (15/15/14) and 6 are ports (2 per zone). Encounters are dealt via a per-zone shuffled **recipe** bag, drawn from the zone's stage-count bucket (Coastal 1 / Open Sea 2 / Deep 3). Supersedes the original 12-point open map. See ADR-0009 and ADR-0014.
