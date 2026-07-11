# Odin coding standards

The house style for Odin in this repo. `/code-review`'s **Standards axis** checks diffs against this file: new code is expected to follow these, and a deviation should be either fixed or justified in the PR.

These are conventions, not laws — a rule that fights a specific case can be broken with a one-line note saying why. What's not acceptable is drifting off them silently.

## Memory: classify every allocation by lifetime

Three lifetimes, three homes (see ADR-0010):

- **Run** — lives as long as the Sim (player/opponent layouts, `resolved`, battle records). Allocate from the **Sim's run arena**. Freed by arena teardown in `sim_destroy`; do **not** add a bespoke `*_destroy` proc or a per-field `delete` for run-lifetime memory.
- **Tick** — transient scratch that lives only within one Tick + event dispatch (the `[dynamic]` event/scratch buffers). Allocate from `context.temp_allocator`; it's reclaimed by `free_all(context.temp_allocator)` at the `run_session` loop boundary. Don't hand-`delete` these.
- **Escapes the run** — data handed out past the Sim's lifetime (`Ghost_Snapshot` to an `Event_Sink`). Follows the ownership rule ADR-0010 settles; until then, honour the documented `run_ghost_snapshot_destroy` contract.

When you add an allocation, the first question in review is "which lifetime?" — if the answer is "run" or "tick", it should not be hand-freed.

## Types: `distinct` for confusable identifiers

Domain identifiers that could be mixed up at a call site are `distinct` types, not bare `int` (see ADR-0011): point/slot/option indices, effect magnitude, and anything of the same shape. Plain counts and stats (HP, Speed, a loop index) stay `int`. The test is confusability — would swapping two `int`s compile today and be wrong?

## Idioms: use the ones Odin gives you

- **Tagged unions + exhaustive `switch`** for closed variant sets (`Command`, `Event`). Let the compiler check case coverage; don't add a `default` that swallows new variants.
- **`Maybe(T)`** for optional values, not sentinel numbers or parallel bools.
- **Enumerated arrays `[Enum]T`** for data indexed by an enum (`[Side]^Ship`), not `int`-indexed arrays with a comment saying which index is which.
- **`or_return`** to propagate failure out of the bool/`ok`-returning procs instead of hand-threading success flags.
- **`bit_set`** for genuine sets-of-enum. Don't force it onto dynamic-length parallel arrays where it doesn't fit — evaluate, then decide.

## Structure

- **Headless stays render-free.** Nothing under `core/` or `cmd/headless` imports `vendor:raylib` — the headless/UI split is a compile-time guarantee (ADR-0003), not a runtime flag. A rendering import creeping into core is a Standards failure.
- **Sim boundary is Command/Event only** (ADR-0001). Presentation mutates the Sim through Commands and learns state through Events — never by reaching into Sim internals.

## Tests

- Every package carries `core:testing` tests; `odin test` passes for all of them.
- Headless and UI both build, and a full run completes, before a change is considered done.
