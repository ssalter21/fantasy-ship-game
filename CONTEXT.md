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
- **HP** — the ship's health, persisting across an entire run (not reset between encounters). Reaching 0 sinks the ship and ends the run (permadeath). See ADR-0006.
- **Durability** — a damage-reduction/resistance stat applied to all incoming damage instances. Not a separate decaying resource — it modifies HP loss, it isn't a second health pool.
- **Speed** — the ship's initiative/turn-order stat in the auto-battler.
- **Starting treasure** — a one-time amount of starting capital the ship begins a run with. Not a capacity.
- **Layout** — the fixed set of **slots** a ship template defines. No grid/coordinates and no shape packing — slots are discrete, sized, named containers.
- **Slot** — a single unit of ship layout. Has a **size** (small / medium / large) and a **base visibility** (exposed / concealed). Slot names (e.g. "gun deck") are flavor only and impose no restriction on what can fill them.
- **Fitting** — the single, unified concept for anything that occupies a slot: crew members, weapons, cargo/quarters, or other fantasy entities (creatures, magical objects). Deliberately not split into parallel type systems. A fitting has a size, an effective visibility, a name, and a passive and/or active (auto-triggering) effect.
- **Cargo** — the one special-cased fitting: stackable, generic, effect-less filler that consumes capacity but contributes no combat effect.
- **Cargo capacity** — a baseline ship stat, adjusted up or down by which slots get allocated to cargo vs. other fittings.
- **Fit rule** — a fitting may only occupy a slot of the exact matching size (see ADR-0004 for why, and for the flagged extension point).
- **Effective visibility** — a fitting's visibility as actually observed by an opponent (e.g. when scouting a ghost snapshot), resolved through a three-layer precedence: slot base visibility → fitting-level override → ship/captain-level forced override. See ADR-0005.
- **Captain** — a run-start choice, structurally separate from the slot system (not a fitting, consumes no slot). Can influence a ship's slot limits/structure and grants additional manual per-round captain actions.

### Map & run structure

- **Run** — one playable attempt from Start to Goal (or to permadeath). Not resumable/saved — save/resume and meta-progression between runs are not yet specified.
- **Point** — a single hand-placed location on the run's map. Points carry no edges/adjacency to each other — from any visited point, the player may travel to any other point. See ADR-0007.
  _Avoid_: node, tile.
- **Zone** — one of three fixed difficulty bands a point belongs to, in a fixed linear order: Coastal (nearest Start, easiest) → Open Sea (mid) → The Deep (nearest Goal, hardest). Both encounter difficulty and reward quality scale with zone.
- **Start** — the run's origin point; also doubles as the home port.
- **Goal** — the run's destination point. Reaching it with HP > 0 wins the run. Carries no port and no encounter of its own.
- **Port** — a safe, no-battle point where the player spends starting treasure. One per zone plus Start, four total.
- **Encounter** — a non-port point assigned exactly one Encounter kind, which triggers automatically (no decline option) when the ship arrives there. The only way to avoid an encounter is to route around its point.
- **Encounter kind** — the type of interaction an encounter presents: Ship Battle, Upgrade Offer, or Stat Trade.
- **Ship Battle** — an encounter kind: a full battle against a game-configured opponent ship, resolved via the phased-round combat system (ADR-0006). Mechanically identical to a future ghost-PvP battle; this slice's opponents are not real players' stored snapshots.
- **Upgrade Offer** — an encounter kind: choose one of a few options to upgrade one of the ship's starting fittings.
- **Stat Trade** — an encounter kind: a permanent stat-for-stat or stat-for-cargo trade-off (e.g. +Durability for −Speed).

## Vertical-slice scope (see GitHub issue #4)

- One fixed ship template: 6 slots — 2 medium exposed ("top deck", "top crew"), 1 large exposed ("gun deck"), 3 small concealed.
- Fixed starting loadout: "Top Crew", "Captain's Quarters", "Gun Deck" fill the exposed slots; cargo fills the 3 concealed slots by default.
- Findable content is limited to upgraded variants of those same three fittings (e.g. "Upgraded Gun Deck") — no separate fitting roster.
- Exactly one captain.
- Map: Start/home port → Coastal → Open Sea → The Deep (one port + 4 encounter points each) → Goal. 12 encounter points total, split evenly across Ship Battle / Upgrade Offer / Stat Trade. See ADR-0007.
