Type: grilling
Status: resolved

## Question

What is the minimal ship & crew model needed for the vertical slice? Define: what a "ship" consists of (stats, slots/capacity), what a "crew member" consists of (role, stats, how they attach to a ship), and how many of each the slice needs to feel like a real crew-building loop without content bloat.

## Answer

Full terminology and decisions captured in `CONTEXT.md`, `docs/adr/0001-unified-fitting-and-sized-slot-layout.md`, and `docs/adr/0002-three-layer-visibility-precedence.md`. Summary:

**Ship stats:** HP (per-battle health, loss condition), Durability (damage-reduction/resistance applied to all incoming damage), Speed (initiative), starting treasure (one-time capital).

**Layout:** a fixed list of slots per ship template, each with a size (small/medium/large) and base visibility (exposed/concealed). No grid/coordinates, no shape packing. Fit rule is exact size match. Slot names are flavor only. Cargo capacity is a baseline stat adjusted by which slots are allocated away from cargo.

**Crew members generalize to "fittings":** one unified concept covers crew, weapons, cargo/quarters, and other fantasy entities — no parallel type systems. A fitting has a size, an effective visibility, a name, and a passive and/or active (auto-triggering) effect. Cargo is the effect-less, stackable special case.

**Visibility precedence (three layers):** slot base visibility → fitting-level override (built in this slice) → ship/captain-level forced override (documented extensibility point only, not built in this slice).

**Captain:** structurally separate from the slot system, chosen once at run start, can affect ship slot limits/structure and grant extra manual per-round actions. One captain for this slice.

**Vertical-slice content:** one ship template (6 slots — 2 medium exposed "top deck"/"top crew", 1 large exposed "gun deck", 3 small concealed); fixed starting loadout ("Top Crew", "Captain's Quarters", "Gun Deck" in the exposed slots, cargo filling the concealed slots); findable content limited to upgraded variants of those same three fittings; one captain only.
