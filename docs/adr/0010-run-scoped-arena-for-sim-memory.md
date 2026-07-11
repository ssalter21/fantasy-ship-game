# ADR-0010: Run-scoped arena for Sim memory — teardown, not per-field frees

## Status

Accepted (implemented by issue #52)

## Context

Odin has no garbage collector; memory ownership is manual and explicit. As the run model has grown, the Sim's teardown has become a hand-maintained list of frees spread across several procedures: `sim_destroy` deletes the player layout, `resolved`, and both battle `jettisoned` records; `run_map_destroy` walks the map deleting each Ship Battle opponent's layout; and `Ghost_Snapshot` carries a per-recipient "you now own this, call `run_ghost_snapshot_destroy`" contract threaded through comments in `sim.odin` and `ghost.odin`.

This pattern scales badly. Every new owned allocation adds another line to a `*_destroy` proc and another chance to leak (forget the free) or double-free / use-after-free (free it in the wrong place). The ownership comments are load-bearing documentation standing in for something the language could enforce structurally. Meanwhile the UI layer already demonstrates the idiomatic Odin answer: it allocates transient per-frame data from `context.temp_allocator` and calls `free_all` once per frame, so no individual UI allocation is ever hand-freed.

We considered three options:

- **Keep per-object `*_destroy` procs** (status quo). Rejected: it doesn't scale, and it makes correctness a matter of remembering to update teardown in lockstep with every new allocation.
- **Reference counting / a GC shim.** Rejected: against the grain of Odin, heavier machinery than a single-owner run needs, and it hides allocation cost the project deliberately keeps visible.
- **A run-scoped arena** owned by the Sim. Chosen.

## Decision

**The Sim owns a run-scoped arena, and all run-lifetime internal allocations come from it.** The player's layout, each map opponent's layout, `resolved`, and the battle `jettisoned` records allocate into the Sim's arena rather than the general heap. `sim_destroy` tears the arena down in one call; `run_map_destroy`'s per-opponent delete loop and `sim_destroy`'s per-field deletes collapse into that single teardown. No bespoke `*_destroy` proc is added for anything whose lifetime is the run.

**Transient per-tick scratch is a separate lifetime, handled by the temp allocator.** The `[dynamic]` event/scratch buffers that live only within a single Tick + event dispatch do not belong in the run arena — they use `context.temp_allocator`, freed at the `run_session` loop boundary (the same pattern the UI already uses per frame). That change is sequenced separately (issue #53) but the split is part of this decision: three lifetimes — *run* (arena), *tick* (temp allocator), *escapes the run* (below).

**`Ghost_Snapshot` is the one allocation that escapes the Sim, and its ownership is the open follow-up this ADR does not close.** A snapshot is handed to the `Event_Sink`, and ADR-0008's product vision has snapshots eventually synced to a lobby and outliving the run. Issue #52 resolves which of two mechanisms applies, and this ADR is updated to record the choice once made:

- **Arena-backed within the run** — the snapshot lives in the run arena, the per-recipient `run_ghost_snapshot_destroy` contract is deleted, and any consumer needing a snapshot past `sim_destroy` copies/serialises it out at that boundary (already a data-source concern per ADR-0008, out of scope here); or
- **Copy-out at the boundary** — snapshots keep an explicit owned lifetime so a sink can retain one beyond the run without a serialise step.

Until #52 lands, the existing `run_ghost_snapshot_destroy` contract stands.

## Consequences

- Adding a new run-lifetime allocation requires no teardown edit — it goes in the arena and is freed with everything else. The class of "forgot to free / freed twice" bugs for run memory is designed out rather than reviewed for.
- The ownership comments in `sim.odin`/`ghost.odin` shrink to one place (the arena's lifetime) instead of being restated per allocation.
- Memory is not reclaimed mid-run — the arena only grows until `sim_destroy`. This is fine: a run's allocations are bounded and small, and the whole point is that they share the run's lifetime. Anything that genuinely churns within a run belongs on the temp allocator, not the arena.
- The three-lifetime split (run / tick / escapes) becomes the mental model every future allocation is classified against — see `docs/agents/odin-standards.md`.

See GitHub issue #52 for the implementation.
