# PROTOTYPE notes — issue #62

**Question:** What does the player actually see on the map before and after
arrival, given hidden/randomized encounter kinds and a connected ~50-node
graph (map #59)?

**Run it:** `odin run cmd/prototype_map_fog` — Left/Right arrows switch
variant, `1`-`4` travel (forward into new territory or back along an edge
to an already-visited node), `R` resets the walk, `G` rolls a new graph.

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
