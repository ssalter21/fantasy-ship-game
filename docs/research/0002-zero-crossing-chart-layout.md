# Zero-crossing Chart layout: approach decision

Scoped by GitHub issue [#338](https://github.com/ssalter21/fantasy-ship-game/issues/338)
(effort: parchment treasure-map Chart, [#334](https://github.com/ssalter21/fantasy-ship-game/issues/334)).

**Question.** How do we lay the voyage graph out so **connected nodes sit physically
adjacent and no two route lines ever cross** — a strict zero-crossing (planar leveled)
embedding? Two candidate approaches were posed: **(a)** constrain the generator
(`core/voyage/generation.odin`) to only emit planar graphs, or **(b)** compute a planar
embedding + positions at render time from the existing layered graph
(`compute_node_positions` in `cmd/game/view.odin`).

## Decision

**Adopt approach (a): make zero-crossing a generation-time invariant.** Constrain the
wiring in `core/voyage/generation.odin` so the graph is *level-planar by construction*;
then the existing render-time layout (`x = layer`, `y = lane`, straight lines) draws it
crossing-free with **no** repositioning or crossing-minimization pass. Approach (b) alone
is rejected: it **cannot guarantee** strict zero crossings, only reduce them.

## Why (b) alone cannot guarantee zero

The Chart is a strict **leveled DAG**: forward edges connect only *adjacent* layers, and
`view.odin` places each node at `x = layer`, `y = lane` and draws straight lines between
node centres. Under that fixed leveled, straight-line drawing:

1. **Random forward wiring produces non-level-planar structure.** Today
   `generation.odin` picks each forward edge's target by *uniform-random lane* with no
   ordering constraint. Two forward edges between the same layer pair cross whenever their
   lane order inverts. Worse, the guaranteed-connectivity + branching rules readily create a
   **C₄ / K₂,₂** between two adjacent layers (parents `a<b` both linking children `c<d`).
   In a leveled straight-line drawing the edges `a→d` and `b→c` cross **for every ordering
   of the four nodes** — no lane reordering removes it. A leveled graph is drawable without
   crossings iff each consecutive-layer bipartite subgraph is a *caterpillar forest*;
   random wiring violates this, so the graph is simply **not level-planar** and no
   repositioning can fix it.

2. **Same-layer laterals pass *through* nodes.** Lateral edges join two nodes in the *same*
   column (same `x`). A straight segment between lanes `i` and `j` runs *over* every node
   whose lane lies strictly between them — `|i − j| − 1` nodes. This is unremovable by any
   choice of `lane`-derived position; it is a property of the edge existing at all.

So the strongest thing (b) could offer is a **level-planarity test + embedding**
(Jünger–Leipert–Mutzel, linear-time) that succeeds *only when the generated graph happens
to be level-planar* — which the current generator does not guarantee — falling back to
barycenter crossing-*minimization* (non-zero) otherwise. That is more render-time code for
a weaker guarantee. Guarantee ⇒ constrain generation.

## The constraint (approach a)

Three localized changes to `core/voyage/generation.odin`; `compute_node_positions` is left
**unchanged** (`layer`/`lane` are already the two layout axes).

1. **Monotone forward wiring (the core rule).** Between layer *l* (width `wl`, lanes
   `0..wl-1`) and *l+1* (width `wl1`), tile the child-lane axis into `wl` **contiguous,
   monotone blocks**, one per parent, adjacent blocks sharing exactly their boundary child.
   Parent `p` connects to its block `[start[p] .. start[p+1]]`. Because blocks are ordered
   and overlap only at a single shared child, for any parents `p1<p2` *every* child of `p1`
   has lane ≤ every child of `p2` → **no lane inversion → zero forward crossings**, while
   still allowing branching (block width) and full coverage (blocks tile the axis). This is
   the Slay-the-Spire "no crossed diagonals" invariant generalized to variable-width layers.
2. **Restrict laterals to adjacent lanes.** Allow same-layer edges only between lanes `i`
   and `i+1` (drop, or curve, anything wider). Adjacent-lane laterals are short segments
   with no node between their endpoints, so they overlap nothing.
3. **Preserve connectivity monotonically.** The out-degree cap (`OUT_DEGREE_MAX = 4`) can
   skip children in a wide block; re-attach any skipped child to *its own block's parent*
   (`start[p] ≤ c ≤ start[p+1]`), which stays inside the monotone bound and so keeps the
   zero-crossing guarantee.

**"Connected nodes adjacent" falls out for free:** monotone blocks make every edge span a
small lane delta, so parents and children sit close vertically — short routes, no long
diagonals. That directly serves the ship-animation ticket (#339), whose ship travels along
these short, non-crossing segments.

## Proof on generated maps

A rough prototype ([`assets/0002-planar-proto.py`](assets/0002-planar-proto.py)) replicates
generation at the level of detail that governs crossings — variable-width layers (4–6),
adjacent-layer forward edges with the out/in guarantees + capped branching, and same-layer
laterals — then measures crossings the way `view.odin` draws them (straight leveled lines;
two forward edges cross on lane inversion; a lateral over lanes `i..j` crosses `|i−j|−1`
intermediate nodes). Over **200 generated maps (~52 nodes each)**:

| wiring | avg forward crossings | max forward | avg lateral through-nodes |
|---|---|---|---|
| **RANDOM** (today) | **140.7** | 237 | **23.3** |
| **CONSTRAINED** (planar) | **0.00** | **0** | **0.00** |

The constrained generator produced **exactly zero** crossings and overlaps on *every* seed,
and a coverage check confirmed it kept full connectivity (every non-Start node has an
incoming edge, every non-Haven node an outgoing one) on all 200 maps. This is the concrete
evidence that strict zero-crossing **is** achievable — but only with the generation-time
constraint, not by repositioning the current random graph.

## Consequences / handoff

- **Cost.** Localized edits to the forward-wiring and lateral loops in
  `generation.odin` (~lines 196–251); `compute_node_positions` untouched; the `Node`/`Map`
  data model (`layer`, `lane`, symmetric `edges`) is unchanged. One build session.
- **Risk.** The monotone in-guarantee must be implemented as described so the degree cap
  never orphans a node; the prototype's coverage check is the acceptance test to port.
- **Is strict zero always achievable?** Only under the generation constraint. An arbitrary
  leveled graph is not always level-planar, so "just reposition" has no guarantee; the
  monotone-tiling generator makes level-planarity an invariant, so zero crossings is
  guaranteed by construction.
- **Feeds:** #339 (ship sails a short, non-crossing route) and #340 (spec consolidation).
