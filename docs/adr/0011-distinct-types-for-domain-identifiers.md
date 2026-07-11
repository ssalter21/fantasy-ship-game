# ADR-0011: Domain identifiers are `distinct` types, not bare `int`

## Status

Accepted (implemented by issue #54)

## Context

Several distinct domain identifiers in the Sim are all typed as bare `int`: the current-point index (`Sim.current`) and `Command_Travel_To.point_id`, `Command_Jettison_Cargo.slot_index`, `Command_Pick_Upgrade.option_index`, and `Effect.magnitude`. Because they share a type, the compiler will silently accept passing a slot index where a point index belongs, an option index where a slot index belongs, and so on. These are exactly the confusions that produce quiet, hard-to-spot logic bugs — the value is a plausible small integer in every case, so nothing crashes; it just addresses the wrong thing.

Odin provides `distinct` type aliases (`Point_ID :: distinct int`) that are layout-identical to their base type — zero runtime cost, no boxing — but are not implicitly interconvertible. The compiler then rejects cross-assignment between two `distinct int` types, turning a class of index-mixup bugs into compile errors.

We considered leaving them as `int` (status quo) and relying on parameter names and care. Rejected: the type system can enforce this for free, and the domain is rich enough — an ADR-backed glossary of Points, Slots, Zones, Encounters — that the identifiers are genuinely different kinds of thing, not interchangeable counters.

## Decision

**Confusable domain identifiers get their own `distinct` type.** Where a value identifies a *kind of domain thing* and could be mistaken for another such identifier at a call site, it is a `distinct int` (or `distinct` over whatever the base type is), not a bare `int`. This applies to the point/slot/option identifiers and `Effect.magnitude` above; it does not mean every integer field in the codebase becomes distinct — a plain count, a stat like HP or Speed, or a loop counter stays `int` unless it is a confusable identifier.

The rule is about *confusability*, not ceremony: reach for `distinct` when mixing two `int`s up would compile today and be wrong; leave it `int` when there is nothing to confuse it with.

## Consequences

- Passing a slot index where a point index is expected (and the other permutations) becomes a compile error instead of a silent misbehaviour.
- Conversions become explicit at the few genuine boundaries (e.g. indexing a slice by a `Point_ID`), which reads as intentional rather than accidental.
- No runtime cost and no memory-layout change — `distinct int` is an `int`.
- New identifier-shaped fields are expected to follow this rule; it is part of `docs/agents/odin-standards.md`.

See GitHub issue #54 for the implementation.
