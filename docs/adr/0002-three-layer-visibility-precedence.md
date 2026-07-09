# ADR-0002: Three-layer precedence for fitting visibility

## Status

Accepted (layers 1-2 implemented in the vertical slice; layer 3 is a documented extensibility point only, not implemented)

## Context

Slots have a base visibility (exposed / concealed) as part of the ship layout (see ADR-0001), used to decide what an opponent can see when scouting a ghost snapshot before battle. Two refinements came up:

1. A fitting itself might need to force its own visibility regardless of which slot it's placed in — e.g. a large, unmissable magical artifact that can't be hidden even below deck, or (symmetrically) a fitting that stays hidden even in an exposed slot.
2. A future ship or captain special capability might need to force certain slots to always be concealed (or exposed), regardless of what fitting occupies them or that fitting's own override.

Building the full three-layer system now would mean writing code/data for a capability that nothing in the vertical slice (one ship template, one captain) actually uses yet.

## Decision

Effective visibility for a fitting resolves through three layers, evaluated in order (each layer, if present, overrides the previous):

1. **Slot base visibility** — exposed or concealed, defined by the ship layout.
2. **Fitting-level override** — a fitting may optionally force itself to always-exposed or always-concealed, overriding its slot. Symmetric (either direction). **Implemented in the vertical slice.**
3. **Ship/captain-level forced override** — a future ship or captain capability may force certain slots to a fixed visibility regardless of the fitting's own override. **Not implemented in this slice** — documented here so the model doesn't need reworking when a ship/captain with this trait is built.

## Consequences

- The vertical slice only needs to build layers 1-2.
- When a future ship or captain introduces a forced-visibility capability, it slots into an already-anticipated precedence position rather than requiring a rework of the fitting/slot visibility model.
