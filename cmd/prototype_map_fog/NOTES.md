# PROTOTYPE notes — issue #62

**Question:** What does the player actually see on the map before and after
arrival, given hidden/randomized encounter kinds and a connected ~50-node
graph (map #59)?

**Run it:** `odin run cmd/prototype_map_fog` — Left/Right arrows switch
variant, `1`-`4` travel (forward into new territory or back along an edge
to an already-visited node), `R` resets the walk, `G` rolls a new graph.

## Layout: lanes, not free rows (fixes both a bug and a legibility problem)

Two pieces of feedback, one fix: "not all connected nodes I seem to be able
to travel to" (a real bug -- see below) and "make it look like stepping
stones, not overlapping connections, closer together, fewer connections."

The original generator picked each node's vertical position as an even
spread within its own layer, independent of neighboring layers, and
allowed edges to any random node in the next layer. That produced two
problems: (1) node count/edge count could push a single node's travel
options past 4, past what the `1`-`4` keys can select, while every edge in
the graph was still drawn in Variant A regardless -- some visibly-connected
nodes genuinely weren't reachable; (2) with row position uncorrelated
between layers, edges crossed the whole vertical band constantly, reading
as a dense tangle rather than a path.

Fix: every node now gets a **lane** (0..`LANES`-1, `LANES` = 3) instead of
a free row, and `connect_stepping` (`graph.odin`) only ever wires a node to
an **adjacent lane** (±1) one layer over, picking whichever candidate has
the fewest outgoing edges so far (load-balanced) rather than a random
target. Typical out-degree is now 1-2, occasional 3 in edge cases. Layout
positions y purely by lane, so a node's vertical position is stable
relative to its neighbors layer to layer -- edges stay short and mostly
non-crossing, closer to a stepping-stone path than a mesh. `nodes_per_zone`
dropped 17 → 8 (24 encounters total instead of 51) so the sparser look
reads clearly at this window size; the real count is #60/#63's call, not
this ticket's.

Belt-and-suspenders: `main.odin` now hard-caps drawn/selectable travel
options at 4 (`all_options[:min(len(all_options), 4)]`) so a numbered node
on screen is always actually travelable, regardless of what degree the
generator produces.

## Movement is no longer forward-only (design change, not just visual)

Map #59's Notes originally chartered "Movement is forward-only — no
backtracking to a previously-visited node" as a standing decision, and #60
(closed) picked its generation algorithm assuming that. Per direction
during this prototype's review, that's now reversed: the player can travel
back along an edge to any node they've already visited, not just forward
into new territory. Revisiting a node **never re-triggers its encounter**
— only the first arrival fires one (`will_trigger` in `graph.odin`).

This doesn't change #60's generated graph shape at all — edges are still
only ever *created* forward, layer `i` → `i+1` (that's about generation,
not traversal). What changes is which destinations are legal to travel to
at runtime: previously only outgoing edges from the current node, now also
incoming edges from already-visited neighbors. That's a `core/run`/`sim`
travel-legality rule, not a graph-generation concern, so #60 doesn't need
re-opening — flagged on it for visibility only. Posted to #59 (Notes
correction) and #60 (flag) as comments per the wayfinder convention of
appending decisions rather than editing map bodies.

All three variants now color-code travel options: **yellow** ring/card =
stepping there fires a fresh encounter, **skyblue** = it won't (revisit or
landmark). A status line at the bottom of the window reports the same for
wherever you currently are.

## Zone-progression background (visual, issue #62 scope)

All three variants now paint a Coastal→Open_Sea→Deep background gradient
(`draw_zone_gradient_h`/`_v` in `variants.odin`) behind their content —
horizontal for A/B (matching left-to-right Start→Goal node layout),
vertical for C (matching its stacked zone-progress rows) — so zone
progression reads as an ambient background cue, not just per-node color.

## Landmark rule (added after initial pass)

Start, Port, and Goal nodes are landmarks, not encounters — they carry no
hidden kind, so there's nothing about them for a hiding mechanism to
protect. All three variants now always reveal their position + label,
regardless of visited/fog/horizon state. Only Encounter nodes (and, in B,
the edges leading to a not-yet-revealed encounter) are subject to each
variant's hiding rule. In B this means a far-off port's position is
visible before the path to it is; in C it's a standing "route spine" above
the zone progress bars showing every port's rough position alongside Start
and Goal.

## Three variants

- **A — Full graph, kind hidden.** Every node position and edge is drawn
  from the start. Unvisited encounters show only a small zone-tinted dot —
  no kind color, no label. Visiting a node permanently flips it to its
  resolved kind color+label (route history), same as today's dimming
  behavior. Directly-reachable nodes get a numbered highlight ring.
- **B — Fog by graph-distance (horizon).** Only visited nodes, the current
  node, and its direct neighbors are fully drawn and connected by edges.
  One more hop out is shown as faint, unconnected "horizon" dots; anything
  further isn't drawn at all. Landmarks are the exception (see above).
- **C — Zone progress + local choice fan.** The graph is never drawn. A
  slim per-zone progress strip shows coarse completion; the main area is a
  decision fan of only the current node and its immediate reachable options
  as picker cards — structurally a menu, not a map. Landmarks appear on a
  route spine above the bars (see above).

## Recommendation: Variant A

Map #59's Notes commit to "real branching route choice — multiple viable
paths from Start to Goal, not one critical path with cosmetic dead-ends" as
a standing decision. That only matters to the player if they can *see*
enough of the graph to plan a route across it. B and C both remove that:
B can't be route-planned around because you don't know where a path leads
until you're already near it; C removes the graph from view entirely, so
the connectedness the generation algorithm (#60) works to guarantee is
invisible to the player. A is the only variant where the 50-node
topology's branching is legible and plannable while encounter kind stays a
surprise.

A is also the smallest change from today: `cmd/game/view.odin`'s
`draw_map`/`point_marker` already draws every point; this variant only
changes what an unvisited node's marker shows (generic zone dot vs. kind
reveal) plus adds edges and a reachable-next affordance, both new because
of the graph redesign itself, not because of this ticket's decision.

Open follow-up for whoever implements this: at full 50-node scale on a
1024×700 window (`cmd/game/main.odin`'s `WINDOW_WIDTH/HEIGHT`), a straight
left-to-right layered layout gets visually tight — worth checking a
zoom/pan or a viewport-follows-current-position scheme before locking in
the drawing code, but that's an implementation concern, not this ticket's
design question.

## Status

Not yet posted as the issue's `## Answer` — recommendation above is mine;
leaving the issue open for a look before closing it, since "what should
this look like" is exactly the kind of call this prototype exists to let a
human make by eye. Delete this directory (or fold Variant A's approach
into `cmd/game/view.odin`) once #62 closes.
