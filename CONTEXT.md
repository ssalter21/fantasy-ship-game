# Context: Fantasy Ship Game

Single-context repo. See `docs/adr/` for the decisions behind these terms.

## Glossary

- **Ship** — a run's vessel. Owns a small set of top-level stats (HP, Durability, Speed, starting treasure) and a fixed **layout**. Combat power itself comes from what's installed in the layout, not from the ship directly.
- **HP** — the ship's per-battle health. Reaching 0 ends the battle in a loss. Restored/reset between encounters (exact rule TBD in combat resolution).
- **Durability** — a damage-reduction/resistance stat applied to all incoming damage instances. Not a separate decaying resource — it modifies HP loss, it isn't a second health pool.
- **Speed** — the ship's initiative/turn-order stat in the auto-battler.
- **Starting treasure** — a one-time amount of starting capital the ship begins a run with. Not a capacity.
- **Layout** — the fixed set of **slots** a ship template defines. No grid/coordinates and no shape packing — slots are discrete, sized, named containers.
- **Slot** — a single unit of ship layout. Has a **size** (small / medium / large) and a **base visibility** (exposed / concealed). Slot names (e.g. "gun deck") are flavor only and impose no restriction on what can fill them.
- **Fitting** — the single, unified concept for anything that occupies a slot: crew members, weapons, cargo/quarters, or other fantasy entities (creatures, magical objects). Deliberately not split into parallel type systems. A fitting has a size, an effective visibility, a name, and a passive and/or active (auto-triggering) effect.
- **Cargo** — the one special-cased fitting: stackable, generic, effect-less filler that consumes capacity but contributes no combat effect.
- **Cargo capacity** — a baseline ship stat, adjusted up or down by which slots get allocated to cargo vs. other fittings.
- **Fit rule** — a fitting may only occupy a slot of the exact matching size (see ADR-0001 for why, and for the flagged extension point).
- **Effective visibility** — a fitting's visibility as actually observed by an opponent (e.g. when scouting a ghost snapshot), resolved through a three-layer precedence: slot base visibility → fitting-level override → ship/captain-level forced override. See ADR-0002.
- **Captain** — a run-start choice, structurally separate from the slot system (not a fitting, consumes no slot). Can influence a ship's slot limits/structure and grants additional manual per-round captain actions.

## Vertical-slice scope (see `.scratch/vertical-slice/issues/02-ship-crew-model.md`)

- One fixed ship template: 6 slots — 2 medium exposed ("top deck", "top crew"), 1 large exposed ("gun deck"), 3 small concealed.
- Fixed starting loadout: "Top Crew", "Captain's Quarters", "Gun Deck" fill the exposed slots; cargo fills the 3 concealed slots by default.
- Findable content is limited to upgraded variants of those same three fittings (e.g. "Upgraded Gun Deck") — no separate fitting roster.
- Exactly one captain.
