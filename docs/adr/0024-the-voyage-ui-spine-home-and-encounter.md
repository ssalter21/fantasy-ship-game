# ADR-0024: The voyage UI spine — Home and Encounter, one refit surface, one playback layer

## Status

Accepted. The **root decision** of the `effort:voyage-ui` map ([#299](https://github.com/ssalter21/fantasy-ship-game/issues/299)), written for [#300](https://github.com/ssalter21/fantasy-ship-game/issues/300): it fixes the navigation model every other screen in the effort is framed inside, so the Build ([#302](https://github.com/ssalter21/fantasy-ship-game/issues/302)), Chart ([#303](https://github.com/ssalter21/fantasy-ship-game/issues/303)), shared stage-frame ([#304](https://github.com/ssalter21/fantasy-ship-game/issues/304)) and Fight ([#305](https://github.com/ssalter21/fantasy-ship-game/issues/305)) tickets all block on it.

This is a **navigation-model sketch, not an implementation spec**: it decides where the screens sit, how the player moves between them, and where refit and event playback live. It deliberately leaves the Sim plumbing (which phase accepts what), the canvas layouts, and the battle animation to the tickets that block on it. It sits **above `run_session`** in the same place ADR-0022 put the Chart Table, and changes nothing ADR-0022 or ADR-0002 decided — it describes what the UI does *within* a voyage, where those ADRs describe the loop that drives it.

## Context

The whole `effort:voyage-ui` map hangs on one question: what is the top-level state model of the in-voyage UI? Today there is none to speak of. Every in-voyage screen is a **modal blocking loop entered reactively when the Sim awaits a decision** — `get_captain_choice(awaiting)` (`cmd/game/main.odin`) dispatches `Awaiting_Travel_Choice → travel_menu_loop`, `Awaiting_Refit → refit_menu_loop`, and three more, one per Sim phase. The Sim decides which screen is on by which phase it is awaiting; the player never chooses a screen, only answers the one they are handed.

That model cannot express what the effort wants: a **persistent Build screen, freely editable between encounters**, and a **Chart that reads as a real map**, which the player **flicks between**. A persistent, player-chosen home has no home in a model where the awaited phase picks the screen. And the settled going-in facts sharpen the collision: refit is freely editable *between* encounters and never during a battle, and the modal `refit_menu_loop` retires. Something has to own the between-encounters lull and let the player move around inside it.

## Decision

### Two top-level modes: Home and Encounter

The in-voyage UI is exactly two modes, and everything reduces to them.

**Home** — at anchor, between encounters. The Sim is awaiting the next travel choice; the player is free.

**Encounter** — walking a node's stage list. A focused, one-stage-at-a-time takeover, entered by sailing into a node and left when the walk completes or halts.

```
┌─ HOME (at anchor) ──────────┐
│  Build surface (editable)   │  the persistent ground
│  + chart overlay (swipe)    │  raise/lower, both live
│  chart is SAILABLE          │
└─────────────────────────────┘
        │ click a node → ship travels the edge → chart slides aside
        ▼
┌─ ENCOUNTER (stage walk) ────┐
│  current stage owns screen  │  Fight / Offer / Trade / Shop / Reward
│  chart swipe-able, VIEW-ONLY │
└─────────────────────────────┘
        │ walk completes / halts
        ▼   back to HOME at the node
```

### Home is the Build surface, with the chart as a raisable overlay

The **Build surface** — the ship, always in refit — is the persistent editable ground of Home: the main graphic you are looking at by default. The **chart** is not a separate screen you switch to; it is a layer that comes *over* the Build surface when the player **swipes** it across, framed so the Build screen still borders it. Swipe it back and the full Build surface returns.

Two properties make this a home rather than a pair of screens:

- **Both regions stay live.** With the chart raised, the map is an inset panel *and* the surrounding Build surface stays editable — the player can tweak a fitting and plan a route in the same breath. The flick does not hand control from one screen to another; it lays a second live surface over the first.
- **The chart is sailable only at Home.** A node click on the raised chart is the travel command. The ship marker then travels along the edge on the chart — the chart *is* the travel view — and on arrival the chart slides aside and the encounter's first stage takes over. Arriving at a landmark or an already-walked node has no encounter, so it simply returns to Home at the new node; **Haven with Hull > 0** ends the voyage with the won beat, and a **sinking** in a Fight ends it with the lost beat (both hand back to the Chart Table, per CONTEXT.md and ADR-0022).

### The flick is a swipe

The motion that raises and lowers the chart is a **swipe** — swipe the chart over, swipe it back — anchored by a corner tab or screen edge that hints and holds the gesture. For the first build, a *click* on that tab/edge is an acceptable stand-in for the swipe.

This introduces a **mouse drag** (press–drag–release) to a game the style guide describes as pure click-polling. That is a real addition, called out here so the Build and Chart prototypes know they are adding a drag gesture, not only clicks. It is the one new input primitive the spine asks for.

The chart overlay is **swipe-raisable everywhere in a voyage**; what changes by mode is only whether nodes are actionable. At Home the chart is **sailable** (nodes clickable). During an Encounter it is **view-only** — a reference for where you are and what lies ahead, with nodes greyed and unclickable, because travel is not a legal move again until the walk ends.

### One refit mechanic: the Build surface, optionally with a shelf

Refit is **one mechanic**, not several. The modal `refit_menu_loop` does not get a replacement — it **collapses into the Build surface**, which is reused everywhere refit happens:

| Where | Surface | Source beyond the ship | Cost |
| --- | --- | --- | --- |
| **Home** | Build surface | — (your slots only) | free |
| **Offer** stage | Build surface | a temporary **shelf** (the offered items) | free to take |
| **Shop** stage | Build surface | a temporary **shelf** (the stock) | a shelf→ship transfer spends cargo |
| **Trade** stage | — | (a stat-for-stat swap; presents no surface) | — |
| **Reward** stage | — | (auto-stows cargo; presents no surface) | — |
| **Fight** stage | — | **locked — the one place refit is unavailable** | — |

A Shop or Offer is the same Build surface with **an extra temporary container beside the ship's slots**: the shelf. Placing a shelf item is the same act as any refit move — pull one of your fittings off (discarded, since there is no inventory), move a shelf item into a slot — and moving a *shelf* item onto the ship is the only move that can carry a cost (Shop). The player may freely rearrange their own fittings during Offer and Shop too; it is refit, with a shelf.

So the settled "refit is freely editable between encounters, never during a battle" resolves precisely: **the Build surface is available everywhere except inside a Fight.** "Freely" (unprompted, free of charge) is Home; Offer and Shop are the same surface constrained only by a shelf and, for Shop, a cost. Every edit commits live — each install / move / remove is a command the Sim applies and emits an Event for, unchanged from today.

This gives the downstream tickets their organizing principle: **Offer and Shop are ship-plus-shelf screens** ([#304](https://github.com/ssalter21/fantasy-ship-game/issues/304), [#302](https://github.com/ssalter21/fantasy-ship-game/issues/302)), Trade is a stat-swap panel, Reward is a beat, and Fight is combat.

### One shared playback layer

Event playback is **not** each stage drawing its own beats. The spine defines a single, shared **playback layer**: a uniform, blocking beat overlay that any stage invokes on top of itself. Every `Event_Sink` beat renders through it — a Fight's per-round battle Events, the arrival beat on the sail→stage handoff, a Reward's grant, an encounter halt, a wreck's loot, and the voyage-end beat that precedes the return to the Chart Table.

The `Event_Sink`'s blocking-playback contract (ADR-0002, ADR-0022) is **unchanged** — the layer is a shared *surface* for its output, not a change to when or whether it blocks. The Fight ticket ([#305](https://github.com/ssalter21/fantasy-ship-game/issues/305)) designs battle animation *within* this layer's conventions rather than inventing a playback surface of its own.

### What the spine defers

- **The Sim plumbing for a live Build at Home.** For refit to be free at Home, the between-encounters await must accept **both** refit commands and a travel command in one "at anchor" beat — where today `Awaiting_Travel_Choice` accepts only travel and `Awaiting_Refit` is a separate phase Offer/Shop open. Whether that becomes one unified at-anchor phase or the UI orchestrating two is the Build ticket's ([#302](https://github.com/ssalter21/fantasy-ship-game/issues/302)) call; the spine only fixes the requirement.
- **The shared encounter frame** — any chrome persisting across a node's stages (a progress strip, ship status) — is [#304](https://github.com/ssalter21/fantasy-ship-game/issues/304)'s to design. The spine says only that stages are per-stage takeovers sharing the one playback layer.
- **Canvas layouts and the battle animation** — the Build, Chart, stage-frame and Fight tickets.

## Consequences

- **`refit_menu_loop` retires**, and with it the reactive one-loop-per-phase shape *for refit*: refit stops being a screen the Sim hands you and becomes a surface you always have (outside a Fight). The other menu loops are reframed by their stages' tickets, not deleted here.
- **A voyage now has a player-owned home**, which ADR-0022's outer loop already made room for above `run_session` without knowing what would fill it. The Chart Table hands to Home at Start; Home hands back to the Chart Table at either ending. Nothing about the N-voyages-per-session loop changes.
- **The map's fog is reshaped, not just cleared.** "The four menu-stage layouts" and "the grant → place on Build surfacing" now graduate against a known principle (Offer/Shop are ship + shelf), and "retiring the modal `refit_menu_loop`" becomes "build the one Build surface," owned by [#302](https://github.com/ssalter21/fantasy-ship-game/issues/302).
- **A drag gesture enters a click-polling game.** Small, but real: the input layer gains press–drag–release for the swipe. If it proves awkward, the corner-tab click stand-in is the fallback already named.

New `CONTEXT.md` glossary terms land with this ADR: **Home (at anchor)**, **Build surface / Build screen**, **the flick (the swipe)**, **the shelf**, and **the playback layer**.

See GitHub issues [#299](https://github.com/ssalter21/fantasy-ship-game/issues/299) (the effort's map), [#300](https://github.com/ssalter21/fantasy-ship-game/issues/300) (this decision), and [#302](https://github.com/ssalter21/fantasy-ship-game/issues/302)–[#305](https://github.com/ssalter21/fantasy-ship-game/issues/305) (the screens that block on it). Sits above `run_session` where ADR-0022 put the Chart Table; leaves ADR-0002's driver-loop and `Event_Sink` contract untouched.
