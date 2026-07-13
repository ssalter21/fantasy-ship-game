# Odin coding standards

The house style for Odin in this repo. `/code-review`'s **Standards axis** checks diffs against this file; a deviation should be fixed or justified in the PR. These are conventions, not laws — a rule that fights a specific case can be broken with a one-line note saying why. Drifting off them silently is what's not acceptable.

## Naming

- **Types** `Ada_Case` — `Slot_Size`, `Effect_Kind`, `Node_ID`, `Layout_Slot`.
- **Procs** `snake_case`, prefixed by their subject noun — `ship_fit`, `sim_tick`, `run_travel_options`. Odin has no methods; these free procs are the methods, and the prefix is what groups them.
- **Constants** `SCREAMING_SNAKE_CASE` — `STARTING_HP`, `ITEM_ROSTER_SIZE`.
- **Enum members** `Ada_Case` — `.Awaiting_Travel_Choice`, `.Modify_Durability`.

## Memory: classify every allocation by lifetime

Three lifetimes, three homes (ADR-0010). Pick lifetime by scoping `context.allocator` (e.g. `context.allocator = sim_arena_allocator(sim)`), **not** by threading an `allocator:` param down the call chain.

- **Run** — lives as long as the Sim (player/opponent layouts, `resolved`, battle records). Allocate from the **Sim's run arena**; freed by arena teardown in `sim_destroy`. Don't add a bespoke `*_destroy` or per-field `delete` for it.
- **Tick** — transient scratch within one Tick + dispatch (the `[dynamic]` event/scratch buffers). Allocate from `context.temp_allocator`; reclaimed by `free_all(context.temp_allocator)` at the `run_session` loop boundary. Don't hand-`delete`.
- **Escapes the run** — data handed out past the Sim (`Ghost_Snapshot` to an `Event_Sink`). Follows ADR-0010's ownership rule; until settled, honour the `run_ghost_snapshot_destroy` contract.

The first review question on any allocation is "which lifetime?" — if it's "run" or "tick", it should not be hand-freed.

## Types

- **`distinct` for confusable identifiers** (ADR-0011): point/slot/option/node indices, effect magnitude — anything of the same shape that would compile-but-be-wrong if swapped at a call site. Plain counts and stats (HP, Speed, a loop index) stay `int`.
- **Named-field struct literals** past a trivial one/two fields — `Ship{hp = …, max_hp = …}`, never positional. Positional literals reintroduce exactly the confusability `distinct` fights.
- **Zero-value-is-meaningful**: arrange the type so Odin's default-zero is the sensible default rather than requiring explicit init — `Effect_Kind`'s zero `Phase_Contribution` is the base behavior; a zero `Fitting`/`Effect` is valid data.

## Idioms: use the ones Odin gives you

- **Tagged unions + exhaustive `switch`** for closed variant sets (`Command`, `Event`). Let the compiler check coverage; no `default` that swallows new variants.
- **`Maybe(T)`** for optional values, not sentinels or parallel bools. Read with `if v, ok := m.?; ok { … }`.
- **`(T, bool)` return** for fallible ops that yield a value (`ship_remove`, `ship_move`); bare `bool` + **`or_return`** to propagate failure instead of hand-threading success flags.
- **`assert` vs `bool`**: `assert` for invariants / driver bugs a caller can only hit through misuse (`sim_tick` while a decision is outstanding); return a `bool`/`ok` (and emit an Event) for legitimate runtime rejections a caller is expected to hit (`ship_fit` → `Event_Refit_Rejected`).
- **Enumerated arrays `[Enum]T`** for enum-indexed data (`[Side]^Ship`), not `int`-indexed arrays with a which-index comment.
- **`bit_set`** for genuine sets-of-enum. Don't force it onto runtime-length parallel arrays — evaluate, then decide.
- **`for &x in slice`** to mutate in place; plain value iteration to read. Mutating a value copy is a silent Odin footgun.
- **`when`** for compile-time platform/config forks (`when ODIN_OS == .Windows`), not a runtime `if`.

## Structure

- **Headless stays render-free.** Nothing under `core/` or `cmd/headless` imports `vendor:raylib` — the split is a compile-time guarantee (ADR-0003), not a runtime flag.
- **Sim boundary is Command/Event only** (ADR-0001). Presentation mutates via Commands and learns state via Events — never by reaching into Sim internals.

## Tests

- Every package carries in-package `core:testing` tests (`*_test.odin`, so they reach unexported symbols): `@(test)` procs asserting with `testing.expect` / `expectf`. `odin test` passes for all.
- A test using `expect_assert` must guard with `when testutil.SKIP_WINDOWS_ASSERT_BUG { return }` (issue #35).
- Headless and UI both build, and a full run completes, before a change is done.
