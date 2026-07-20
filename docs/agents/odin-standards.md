# Odin coding standards

The house style for Odin in this repo. `/code-review`'s **Standards axis** checks diffs against this file; a deviation should be fixed or justified in the PR. These are conventions, not laws — a rule that fights a specific case can be broken with a one-line note saying why. Drifting off them silently is what's not acceptable.

## Comments: describe the code, not its history or its content

A comment earns its place by explaining **what the code does** or **why a non-obvious constraint holds right now** — not by narrating how the code got here, and not by restating what the code already says. The reader is trying to understand the code in front of them; a paragraph about what it used to be, or a prose copy of the data sitting right below, is noise between them and that goal.

**Cut** — these describe the past or roads not taken, and belong in git history, the PR, or the issue, never in the source:

- **Iteration history** — "used to be an authored field", "was retired with #194", "this replaced the one-opponent template", "originally we…". If a sentence only makes sense to someone who watched the code change, cut it.
- **Rejected alternatives** — "we don't do X because…", "rather than Y", "instead of Z" — unless the rejected option is one a reader would *actively try to add back today*, in which case keep one tight line as a guardrail (see below).
- **Change-log narration** — issue and ADR numbers used as a timeline ("as of #151", "three guns as of…"). An ADR reference is fine as a *pointer to a still-true decision*; it's noise as a date stamp.

**Keep**, tightened to the fewest lines that carry it:

- **What the code does** — the plain description of behavior, especially where the mechanism isn't obvious from the names.
- **Still-true, non-obvious rationale** — the "why" a reader needs *now* to avoid breaking something: an invariant, an ordering dependency, a footgun. Keep it if it's both true today and non-obvious; drop it if it's obvious from the code or no longer holds. A live guardrail ("order is authoring — placement decides deck vs hold") stays; the story of how we learned it goes.

**Don't narrate the data.** The code and its literals are the source of truth; a comment that restates them just duplicates a fact that drifts the moment the data changes. Cut anything a reader can read directly off the construct the comment sits on:

- **Counts and members** — "eight entries", or listing an enum's cases / a roster's rows in prose. The literal is right there and authoritative.
- **Field values and per-entry attributes** — describing each archetype's items or an entry's flavor when the struct literal already shows them. The name and fields *are* the description; a per-row comment that only re-says them is deleted.
- **Current game state** — what a particular entry *is* thematically ("guns, no tricks", "the fastest ship in the game"). That's content, and it lives in the data — a name, a field — not narrated above it. It also isn't what the code *does*.

Comment the **structure and mechanics** instead: the role a type plays, the invariant *every* entry must satisfy, how a proc transforms its inputs, the non-obvious wiring — the things that stay true no matter what the content happens to be today. Describe what the code *does and represents*, not the state of the game it currently produces.

**Salvage, don't spill.** When a comment is really an undocumented design *decision* — load-bearing "why" that outlives this file — capture it in an ADR (`docs/adr/`) and leave a one-line pointer (`// deck-vs-hold placement: ADR-00NN`) rather than an essay. Everything else that's cut is simply deleted; `git blame` preserves it.

**Two tests:** *"does this help me understand or safely change the code as it is?"* — if it only tells a story about the code, delete it. And *"would this still be correct if someone added a row or renamed one?"* — if editing the data nearby would falsify the comment, the comment is narrating the data, so cut it down to the part that survives (the structure, the invariant) or cut it entirely. Prefer a two-line comment that a reader finishes over a twenty-line one they skip.

## Naming

- **Types** `Ada_Case` — `Slot_Size`, `Effect_Kind`, `Node_ID`, `Layout_Slot`.
- **Procs** `snake_case`, prefixed by their subject noun — `ship_fit`, `sim_tick`, `run_travel_options`. Odin has no methods; these free procs are the methods, and the prefix is what groups them.
- **Constants** `SCREAMING_SNAKE_CASE` — `STARTING_HP`, `ITEM_ROSTER_SIZE`.
- **Enum members** `Ada_Case` — `.Awaiting_Travel_Choice`, `.Modify_Max_Hull`.

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
