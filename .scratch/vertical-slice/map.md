# Vertical Slice PRD — Fantasy Age-of-Sail Roguelike

## Destination

A combined PRD (game design + technical architecture) for a very small vertical slice: one playable run end-to-end, in a custom Odin game engine — playable via a UI, and also runnable headless (no UI) for simulation. Minimal crew/ship model, one encounter-resolution system shared by PvE and ghost-based async PvP (auto-battler core + one captain decision per round), and a basic hand-placed open-map run structure. Enough spec to start building; depth, content variety, live ghost-fetching infrastructure, and agent-driven balancing tooling are explicitly out of scope or fog for later maps.

## Notes

- Domain: fantasy age-of-sail 2D roguelike, inspired by The Bazaar (auto-battler, item builds) and Slay the Spire (run structure, roguelike escalation).
- Engine: custom, written in Odin — no existing game engine/framework (Unity, Godot, etc.).
- Combat model: auto-battler core (items/crew trigger automatically), plus exactly one captain decision per battle round.
- PvP model: asynchronous, resolved as a deterministic battle against a *snapshot* of another player's build (a "ghost"), not live netcode or matchmaking.
- Run structure: a small, hand-placed, open (non-node-graph) spatial map with a danger gradient — not procedurally generated for this slice.
- Standing practice: write unit tests alongside every module as it's developed (TDD), to catch regressions from later features. Invoke `/tdd` for implementation-flavored tickets.
- Use `/grilling` and `/domain-modeling` for grilling-type tickets; capture resolved terminology/decisions into `CONTEXT.md` / `docs/adr/` per `docs/agents/domain.md` as they firm up.

## Decisions so far

(none yet — map just charted)

## Not yet specified

- Meta-progression between runs, and save/resume of an in-progress run — not ruled out, but not sharp enough to ticket until the core systems (ship/crew model, combat resolution) exist.
- Art/visual style for the UI.
- Stat-balancing specifics (numbers, tuning) — depends on the systems designed in the open tickets below.

## Out of scope

- Procedurally-generated open map with weekly/per-lobby regeneration and a tuned danger-gradient generator — the full-game vision; this slice uses a small hand-placed stand-in instead.
- Live ghost-fetching infrastructure (a server/matchmaking layer that supplies real other-players' snapshots) — the slice needs only a way to resolve a battle against *some* stored snapshot, not to fetch one live.
- Agent-driven balancing tooling (agents that play the game with controllable playstyles to tune balance) — a later map, once the headless engine exists to build it on.
- Full crew-class / item-economy content variety — this slice needs the *systems*, not breadth of content.
