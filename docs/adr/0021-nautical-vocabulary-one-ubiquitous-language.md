# ADR-0021: The nautical vocabulary — one ubiquitous language

## Status

Accepted. **Supersedes the domain terms** carried in the prose of earlier ADRs — ADR-0006/0017's `Buff`/`Defensive`/`Offensive`, `soak`, `Boost`, and `Leave Combat`; ADR-0009's `Goal`; ADR-0007/0009's `Run` (the domain noun); and the `HP` and `treasure`/`money`/`purse` vocabulary throughout. It supersedes the **words, not the decisions**.

Earlier ADRs are **not rewritten** — this repo amends by addition (CONTEXT.md already cites "ADR-0008, amended by ADR-0018"), so ADR-0006/0017's Buff/Defensive/Offensive reasoning and ADR-0020's `HP`/`treasure` prose stay as the point-in-time records they are. This ADR is the dictionary they are now read through: where an earlier ADR says `HP`, read **Hull**; where it says the `Buff` phase, read **Muster**. Recorded **after** the renames landed (the six conflict-free rename commits combined in PR #215, plus the `core/run` → `core/voyage` package move in PR #216), so it describes the code as it actually is — the inverse of ADR-0014/ADR-0020, which recorded canon *before* the code.

## Context

The game had accreted engine-flavored placeholder names while the mechanics were being argued out: `HP`, the `Buff`/`Defensive`/`Offensive` combat phases, `Run` for a playthrough, `Goal` for its destination, `soak`, `Boost`, `Leave Combat`, and a tangle of `treasure`/`money`/`purse`/`reward` words for the one resource. Two problems compounded:

- **They are gamey, not nautical.** A sea game whose central health stat is "HP" and whose captain "Boosts" his "Offensive" phase is speaking spreadsheet, not ship. The domain deserved words a captain would actually say.
- **Some collide with the engine's own domain-free vocabulary (ADR-0001).** `Run` did double duty as the *domain noun* (a playthrough) and the *engine prefix* (`run_session`, `run_fight_opponent_*`). The engine core is domain-free on purpose; a term that means both a voyage and an engine loop blurs exactly the boundary ADR-0001 draws.

The rename was charted as its own effort (the `effort:nautical-vocabulary` map, #171) and worked **one ticket at a time, one commit and one PR each** — the renames are independent by design, and a stacked mega-rename would be unreviewable and unbisectable. The two genuinely-open naming questions (the goal node's name, and whether the resource collapses to one word) were grilled as their own tickets (#181, #188) and gated the tasks that depended on them; everything else was already argued out in the table below and was pure execution.

## Decision

### The vocabulary

Every renamed term, its replacement, and why the new word earns its place:

| Old | New | Rationale |
| --- | --- | --- |
| `HP` / `Max HP` | **Hull** / **Max Hull** | The hull is literally what reaches zero and sinks, and it persists across a Voyage the way HP did. ([#183](https://github.com/ssalter21/fantasy-ship-game/issues/183)) |
| `Buff` / `Defensive` / `Offensive` — the three round phases *and* the fitting categories | **Muster** / **Brace** / **Fire** | Three things a captain would actually yell, in the order he'd yell them: muster the crew, brace for impact, fire the guns. ([#184](https://github.com/ssalter21/fantasy-ship-game/issues/184)) |
| `Run` — the domain noun | **Voyage** | Disambiguates from the `run_*` engine prefix (ADR-0001): Voyage takes the domain sense, `run_session` keeps the engine sense. ([#185](https://github.com/ssalter21/fantasy-ship-game/issues/185), package move [#213](https://github.com/ssalter21/fantasy-ship-game/issues/213)) |
| `Goal` | **Haven** | The safe harbour you are *bound for* — a refuge, which the trading ports are not. Dodges the `Port` collision that sank the *Port of Call* candidate, and the "home port" one that `Start` already owns. ([#181](https://github.com/ssalter21/fantasy-ship-game/issues/181), applied [#187](https://github.com/ssalter21/fantasy-ship-game/issues/187)) |
| `Leave Combat` | **Break Off** | "Break off the engagement" is the phrase; *Leave Combat* is a UI verb. ([#182](https://github.com/ssalter21/fantasy-ship-game/issues/182)) |
| `money` / `treasure` / the reward payout / `purse` / `Starting treasure` | **Cargo** | **There is no money aboard — you carry cargo, and it has value only in trade.** One resource, one word, used as a mass noun like "gold"; **hold** stays the collective capacity. Adopts ADR-0020's landed "money is cargo" words (`STARTING_CARGO`, the Cargo fitting). The `Reward` **stage primitive is kept** (it names the act, not the resource); the `Treasure` **Trade axis → `Cargo`**. ([#188](https://github.com/ssalter21/fantasy-ship-game/issues/188), rename [#207](https://github.com/ssalter21/fantasy-ship-game/issues/207)) |
| `soak` | **Bulwark** | The ship's side that takes the hit: `final_damage = max(0, raw − bulwark)`. ([#182](https://github.com/ssalter21/fantasy-ship-game/issues/182)) |
| `Boost` | **Press** | A captain "presses" a phase — presses the guns, presses the crew. Spelled `Command_Press`, a deliberate shared word with the `Press Gang` recipe but no shared symbol. ([#182](https://github.com/ssalter21/fantasy-ship-game/issues/182)) |

### The engine core keeps its domain-free names (ADR-0001)

The rename stops precisely at the boundary ADR-0001 draws. `Sim`, `Command`, `Event`, `Tick`, `run_session`, `Input_Source`, and `Event_Sink` know nothing about ships and keep looking that way — a nautical `Sim` is a `Sim` that only *looks* like it knows about ships. The `run_*` engine prefix survives untouched (`run_session`, the combat-test helper `run_five_rounds`), as does the **run-scoped** arena vocabulary of ADR-0010 and the `run`/`sim` boundary. Only the domain side — the `core/run` package, now `core/voyage` — took the `Voyage` rename.

### Two collisions, held apart by design

- **`Press` the Command vs. the `Press Gang` recipe / `Stock_Pool.Press_Gang`.** The word is shared; no symbol is. This is the tolerable collision #171 anticipated, and it needs no disambiguation.
- **`Cargo` the Trade axis vs. `Tag.Cargo` the fitting family.** Distinct enums, no collision; `Trade_Stat.Cargo` and the Cargo tag family coexist.

### Renames considered and rejected

Recorded here so they are not re-litigated. The frontier stopped at the destination; each of these sits past it.

| Considered | Rejected because |
| --- | --- |
| **Engine core** (`Sim`, `Command`, `Event`, `Tick`, `run_session`, `Input_Source`, `Event_Sink`) | ADR-0001 draws that boundary deliberately — the engine knows nothing about ships and should keep looking like it. |
| `Durability` → **Plating** | Collides with the existing **Iron Plating** item (which grants +1 Durability); the stat and the item would share a name. `Timbers`/`Scantlings` dodge it, but Durability is neutral rather than wrong, so it stays. |
| `Slot` → **Berth** | Berth's mooring sense collides with `Port`, and `Slot`/`Fitting` already pair cleanly. |
| `Speed` → **Way** | Nautical, but a terrible identifier — `ship.way` reads badly. |
| `Recipe` | A cooking word in a sea game, but an unambiguous *authoring* term. The alternatives (Yarn, Manifest, Chart) collide with the map or are too cute to type. |
| `Edge` → **Leg** | `Edge` is precise graph vocabulary, and CONTEXT leans on graph reasoning ("connected graph", "edges are only generated forward"); the rename loses precision. |

## Consequences

- **CONTEXT.md now reads in this vocabulary throughout**, not just in a term list: `HP` → Hull, `Run` → Voyage, `Buff`/`Defensive`/`Offensive` → Muster/Brace/Fire, `treasure`/`purse`/`money` → Cargo, across every entry and cross-reference. The retired words are recorded in the relevant `_Avoid_` lines so they don't creep back.
- **Earlier ADRs are read through this dictionary, never edited.** ADR-0006/0017 still say `Buff`/`Defensive`/`Offensive`; ADR-0020 still says `HP` and `treasure`. That is correct — they are point-in-time records, and this ADR supersedes their *terms* while leaving their *reasoning* to stand. A reader meeting an old term maps it through the table above.
- **Live identifiers moved; historical citations did not.** Where CONTEXT names live code it now names the current symbol (`voyage_finish_ship_battle`, `voyage_fight_opponent_hull`, `ship_stow_cargo`); where it cites something retired (`Ship.starting_treasure`, `STARTING_TREASURE`) it keeps the old name, because the point is that it *was* retired.
- **Some words were deliberately kept.** The `Reward` stage primitive (it names the act, not the resource), the `"Treasure Vault"` flavor name, and the `Smuggler's Run` recipe name are flavor or authoring vocabulary, not the domain noun, and survive the rename.
- **No mechanics changed.** Every ticket in this effort was a pure token rename with its test suite green (see the per-ticket PRs); the goal node stayed a shop-less landmark, the phases resolve in the same order, the resource behaves exactly as ADR-0020 defined it. This ADR renames; it does not redesign.

See the `effort:nautical-vocabulary` map ([#171](https://github.com/ssalter21/fantasy-ship-game/issues/171)) for the effort and its per-term tickets, and [#186](https://github.com/ssalter21/fantasy-ship-game/issues/186) for this recording. Read through by every prior ADR; supersedes their domain terms, edits none of their prose.
