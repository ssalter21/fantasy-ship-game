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
- **HP** — the ship's health, persisting across an entire run rather than resetting per encounter. Reaching 0 sinks the ship and ends the run. See ADR-0006.
- **Durability** — a damage-reduction/resistance stat applied to all incoming damage instances, as a flat per-hit reduction (`final_damage = max(0, raw_damage − Durability)`). Not a separate decaying resource — it modifies HP loss, it isn't a second health pool. See ADR-0006.
- **Speed** — the ship's stat governing when it may disengage from combat: once a battle passes its baseline round count, the higher-Speed ship may leave. Also breaks ties in a same-round mutual kill and in round-cap stalemate resolution. See ADR-0006.
_Avoid_: Initiative, turn order — combat resolves simultaneously by fixed phase, not by Speed-based turn order.
- **Starting treasure** — a one-time amount of starting capital the ship begins a run with. Not a capacity.
- **Layout** — the fixed set of **slots** a ship template defines. No grid/coordinates and no shape packing — slots are discrete, sized, named containers.
- **Slot** — a single unit of ship layout. Has a **size** (small / medium / large) and a **base visibility** (exposed / concealed). Slot names (e.g. "gun deck") are flavor only and impose no restriction on what can fill them.
- **Fitting** — the single, unified concept for anything that occupies a slot: crew members, weapons, cargo/quarters, or other fantasy entities (creatures, magical objects). Deliberately not split into parallel type systems. A fitting has a size, an effective visibility, a name, a **category** (Buff / Defensive / Offensive — see ADR-0006), and a passive and/or active (auto-triggering) effect.
- **Cargo** — the one special-cased fitting: stackable, generic, effect-less filler that consumes capacity but contributes no combat effect.
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

## Vertical-slice scope (see GitHub issue #4)

- One fixed ship template: 6 slots — 2 medium exposed ("top deck", "top crew"), 1 large exposed ("gun deck"), 3 small concealed.
- Fixed starting loadout: "Top Crew", "Captain's Quarters", "Gun Deck" fill the exposed slots; cargo fills the 3 concealed slots by default.
- Findable content is limited to upgraded variants of those same three fittings (e.g. "Upgraded Gun Deck") — no separate fitting roster.
- Exactly one captain.
