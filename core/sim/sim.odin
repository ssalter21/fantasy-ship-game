package sim

import "../combat"
import "../run"
import "../ship"
import "core:math/rand"
import "core:mem"
import "core:mem/virtual"

// Phase is what kind of captain decision Sim is (or is about to be) awaiting
// (issue #24 — wiring core/run/core/combat under the shared run_session
// loop, ADR-0002). run_session passes sim.phase into
// Input_Source.get_captain_choice (issue #39) so adapters route to the
// right decision UI directly instead of re-deriving it from the Event
// stream themselves.
//
// There is deliberately **no phase per stage primitive** (issue #131, ADR-0014).
// A Phase names a *kind of decision*, and an encounter's stages are walked by one
// generic path (sim_encounter.odin) that parks in whichever phase the stage under
// the cursor asks for. Awaiting_Item_Choice and Awaiting_Shop_Choice — the same
// "pick from a small option list" decision, written twice — collapsed into
// Awaiting_Option_Choice; adding a primitive must not add a phase.
//
// The survivors each earn their place on a decision shape, not on a kind:
//   - Awaiting_Travel_Choice is not a stage decision at all — it is the routing
//     choice *between* encounters, which no stage list can express.
//   - Awaiting_Battle_Command is a multi-round sub-mode over a foreign command
//     vocabulary (combat.Command, ADR-0006), not a one-shot pick from a list.
//   - Awaiting_Trade_Choice is a one-bargain accept/reject (issue #136) — two
//     answers over no list, which is genuinely not the "pick one of N, or decline"
//     shape Awaiting_Option_Choice names. It is the closest thing here to a phase
//     per primitive, and it is worth being honest that it sits in tension with the
//     rule above: it earns its keep on the decision's *arity*, and a second
//     accept/reject primitive must reuse it rather than add its neighbour.
//   - Awaiting_Refit is a sub-mode over the loadout, and is **shared** by every
//     stage that hands the player an item (an Offer's pick, a Shop's buy) — the
//     opposite of a per-kind phase.
//   - Ended is terminal.
Phase :: enum {
	Awaiting_Travel_Choice,
	Awaiting_Battle_Command,
	// Awaiting_Option_Choice is the "pick one of a few, or decline" decision every
	// option-list stage parks in (issue #131): an Offer's items (pick to place, or
	// skip) and a Shop's shelf (buy against the ship's hold, or leave) are the
	// same decision differing only in whether an option carries a price
	// (Stage_Option.cost), so they share one phase, one Command, and one Event.
	// What a selection *means* is the primitive's own business and belongs to the
	// stage under the cursor, not to the phase: an Offer's pick completes the stage
	// and a skip halts it, while a Shop's buy keeps the stage open (the multi-buy
	// loop) and only leaving completes it.
	Awaiting_Option_Choice,
	// Awaiting_Trade_Choice is the Trade decision (issue #136, ADR-0014): the ship
	// arrived at a Trade stage and is accepting or rejecting the bargain it drew
	// from the axis roster. Accepting **completes** the stage; rejecting **halts**
	// it — so a rejected [Trade, Reward] never reaches the Reward, which is the
	// distinction #136 could describe but not yet enforce, since it predated the
	// cursor (issue #131) and every recipe was one stage long.
	//
	// This phase is new. A Trade used to have no decision at all — it applied on
	// arrival, "matching no-decline" — so it never waited on the captain for
	// anything. Under ADR-0014 a Trade is a stage like any other and its outcome is
	// the player's.
	Awaiting_Trade_Choice,
	// Awaiting_Refit is the manual-loadout mode (issue #95, ADR-0012): the ship
	// is rearranged through install / move / remove commands, ended by a finish
	// command. Opened by sim_open_refit — which any stage that hands the player an
	// item calls once it is picked or bought.
	Awaiting_Refit,
	Ended,
}

// Node_ID identifies a node in run_map.nodes by position — used across the Sim
// boundary via Command_Travel_To and Event_Travel_Options. It is an alias of
// run.Node_ID (issue #112): run owns the Map, so it owns the canonical distinct
// type (see run.odin for the ADR-0011 rationale); aliasing here means one
// distinct type crosses the run/sim boundary with no int conversion.
Node_ID :: run.Node_ID

// Option_Index identifies one of an option-list stage's presented options by
// position (issue #54: distinct from a plain int for the same reason as Node_ID,
// so an option index can't be passed where a node id or slot index belongs). It
// indexes the options the Sim stages in stage_options — an Offer's items or a
// Shop's shelf cards alike, since #131 collapsed those into one presented list.
Option_Index :: distinct int

// STAGE_OPTION_MAX is how many options the largest option-list stage can present,
// and so the width of the one presented list every such stage shares
// (Event_Options_Presented, Sim.stage_options). Derived from the primitives'
// own counts rather than picked, so a roomier stage can never quietly overflow
// the array the Sim stages it in: a Shop's shelf is the widest today.
STAGE_OPTION_MAX :: max(run.ITEM_OFFER_OPTION_COUNT, run.SHOP_SHELF_SIZE)

// Stage_Option is one line of an option-list stage's presented list (issue #131):
// the `fitting` on offer, and what it `cost`s in treasure — nil when the option is
// free.
//
// That Maybe is the *entire* difference between an Item Offer's options and a Port
// shop's shelf cards, which is why they are one type and not two. Both present a
// few distinct roster items and ask the captain to take one or decline; a Shop's
// carry a price and an Offer's don't. A nil cost is not "free" as a magic zero — it
// says there is no price to check, so sim_process_option_choice skips
// affordability entirely rather than comparing against 0 and hoping the purse is
// never negative.
Stage_Option :: struct {
	fitting: ship.Fitting,
	cost:    Maybe(int),
}

Sim :: struct {
	// rng is kept per ADR-0001 ("Sim owns its own seeded RNG... for
	// deterministic replay"); nothing in this vertical slice's domain logic
	// is actually random yet (map layout and combat resolution are both
	// fully deterministic), but the field/seed stays since ADR-0001 commits
	// to it as Sim's shape, not something this ticket revisits.
	rng:               rand.Default_Random_State,
	run_map:           run.Map,
	// public_nodes is the masked view of run_map.nodes the Sim broadcasts at run
	// start (the hiding contract): a copy that nils every hidden encounter's stage
	// list while preserving graph shape and landmarks, so presentation cannot leak
	// what a node holds before the ship arrives. An encounter holding a revealing
	// stage (ADR-0014) passes through unmasked — that is what makes it visible on the
	// map, and it is asked of the stage list alone, never of the node's kind. Content
	// is revealed per-node on arrival via Event_Arrived_At_Node, which carries the
	// full Node. The edges it pairs with are shared (borrowed) from run_map. See
	// sim_mask_encounters.
	public_nodes:      []run.Node,
	player:            ship.Ship,
	current:           Node_ID, // index into run_map.nodes; Start is always 0
	// resolved is parallel to run_map.nodes; true once the encounter at that node has
	// been walked to the end — every stage completed, or one of them halted (issue
	// #131, ADR-0014). It stays **node-level and once**, for every encounter alike:
	// sim_walk_encounter is the only writer, so "resolved" means exactly "this node's
	// walk is over" rather than whatever each per-kind path used to mean by it. A Port
	// is no exception any more — it is walked and resolved like anything else.
	// Deliberately []bool rather than bit_set (issue #54): bit_set needs a
	// compile-time-bounded index, but resolved is indexed by Node_ID, sized at runtime
	// off run_map_create's generated node count.
	resolved:          []bool,
	// visited is parallel to run_map.nodes; true once the ship has been at a
	// node (Start counts as visited from the outset). Distinct from resolved —
	// a node holding no encounter (Start, Goal) is visited but never resolved — and it is what
	// run_travel_options consults to decide which backward-retrace moves are
	// legal, so the Sim's travel gate reads it every travel choice.
	visited:           []bool,
	// travel_options stages the legal travel destinations the Sim broadcasts on
	// Event_Travel_Options every time it begins awaiting a travel choice (issue
	// #83): run-scoped arena storage (created under the arena in sim_create),
	// cleared and refilled from run_travel_options once per travel decision and
	// borrowed by the emitted event, so adapters and tests consume the moves the
	// Sim already computed instead of re-deriving legality off a shadow map.
	travel_options:    [dynamic]Node_ID,
	steps:             int, // Ghost_Snapshot progress counter, +1 per travel
	status:            run.Run_Status,
	phase:             Phase,
	awaiting_decision: bool,
	pending_command:   Maybe(Command),
	battle:            combat.Battle,
	active_encounter:  run.Stage_Fight,
	// stage_options is the option list the stage under the cursor is presenting
	// (issue #131) — an Offer's items or a Shop's shelf, staged the same way because
	// they are the same decision. Filled by sim_enter_stage as the cursor lands on an
	// option-list stage, broadcast on Event_Options_Presented, and indexed by a
	// Command_Choose_Option's Option_Index to resolve the selection back to its
	// fitting and price. A nil slot is a position with no option on it (a Shop shelf
	// past the deck's tail, or any slot past a narrower stage's count), never
	// selectable.
	stage_options:     [STAGE_OPTION_MAX]Maybe(Stage_Option),
	// shop_visit is the working state of the Shop stage under the cursor, and only
	// that one (issue #131) — a single visit, not a row per node. sim_advance_stage
	// clears it as the cursor leaves the stage, so the next Shop reached (a later
	// stage of the same recipe, or another node's) always deals itself a fresh shelf.
	//
	// This is what retires ADR-0013's cross-visit persistence, and it is the generic
	// walk that forces it: an encounter is walked once and marked resolved, so a Port
	// no longer has a second visit for a draw-down to persist *into* — keeping
	// port_shelves would have left a per-node array no arrival could ever read twice.
	// The multi-buy loop within a visit survives untouched (#137 owns the stock-pool
	// rework and recording the supersession).
	shop_visit:        Shop_Visit,
	// active_trade is the bargain the Trade stage under the cursor is offering (issue
	// #136): staged from the stage as the cursor lands on it and broadcast on
	// Event_Trade_Presented, then applied by a Command_Trade_Choice that accepts. The
	// choice arrives a tick after the stage is entered, so the stage's baked content
	// has to outlive the entry. A plain value, not a Maybe: it is only ever read while
	// the phase says a trade is on screen.
	active_trade:      run.Stage_Trade,
	// refit_pending is the incoming fitting an open Refit (Awaiting_Refit) was
	// opened to place (issue #95): set by sim_open_refit, consumed when a
	// Refit_Install lands it in a slot, and discarded (nil) when the refit
	// finishes without installing it — there is no inventory to hold it
	// (ADR-0012). nil for a rearrange-only refit or once the item is placed.
	refit_pending:     Maybe(ship.Fitting),
	// arena is the Sim's run-scoped allocator (issue #52): every allocation
	// that lives no longer than the Sim itself — the map's Nodes and each
	// Ship Battle opponent's layout, the player's own layout, and every
	// Ghost_Snapshot handed out via Event_Encounter_Resolved — comes from here,
	// so sim_destroy can reclaim all of it in one call instead of a hand-written
	// per-field delete list.
	arena:             virtual.Arena,
}

// Command is the only way presentation may mutate the Sim (ADR-0001). Which
// variant is valid depends on Sim's current Phase; sim_submit_captain_choice
// asserts the submitted Command matches.
Command :: union {
	Command_Travel_To,
	Command_Battle_Choice,
	Command_Choose_Option,
	Command_Trade_Choice,
	Command_Refit,
}

Command_Travel_To :: struct {
	node_id: Node_ID,
}

Command_Battle_Choice :: struct {
	combat_command: combat.Command,
}

// Command_Choose_Option answers whichever option-list stage is under the cursor
// (issue #131), valid only while Sim is in the Awaiting_Option_Choice phase.
// `selection` is the option the captain took (an Option_Index into the presented
// stage_options), or nil to **decline** — skipping an Offer, leaving a Shop. A
// Maybe rather than a sentinel index, so declining is a distinct, unmistakable
// value.
//
// It is one Command rather than the pick/buy pair it replaces because the pair
// were the same message: identical Maybe(Option_Index) shapes, differing only in
// which phase accepted them. What the answer *does* is the stage's business, not
// the Command's — the same selection completes an Offer and loops a Shop — so a
// new option-list primitive needs no new Command.
Command_Choose_Option :: struct {
	selection: Maybe(Option_Index),
}

// Command_Trade_Choice answers the Trade stage under the cursor (issue #136,
// ADR-0014), valid only while Sim is in the Awaiting_Trade_Choice phase. `accept`
// takes the bargain — paying its cost for its gain, permanently — and completes the
// stage; false rejects it, changing nothing and **halting** the encounter, so a
// stage behind a rejected Trade is never reached.
//
// A plain bool rather than Command_Choose_Option's Maybe: an option list picks one
// of N *or* declines, so "decline" needs to be a value distinct from every index,
// whereas a trade is one bargain with exactly two answers. There is nothing for a
// Maybe to hold — which is also why it does not fold into Command_Choose_Option.
//
// Accepting a trade the ship cannot pay for (run_trade_can_accept — the cost
// would break the stat's floor) is a driver bug, not a runtime rejection: the
// Sim broadcasts can_accept on Event_Trade_Presented, so presentation knows not
// to offer it.
Command_Trade_Choice :: struct {
	accept: bool,
}

// Command_Refit carries one loadout operation during a Refit (issue #95,
// ADR-0012), valid only while Sim is in the Awaiting_Refit phase. The inner
// Refit_Command says which operation. Wrapped as a single Command variant
// (rather than four) so the Sim's Command/Phase vocabulary — and every
// exhaustive switch over it — gains one case, not four, mirroring
// Command_Battle_Choice, which likewise carries an inner (combat) union.
Command_Refit :: struct {
	command: Refit_Command,
}

// Refit_Command is the closed set of loadout operations a Refit accepts (issue
// #95). Install places the refit's pending incoming fitting into an empty slot
// and Replace swaps it into a filled one; Move and Remove act on already-
// installed fittings; Finish ends the refit. Every operation enforces ADR-0004's
// exact-size fit rule and is rejected without disturbing the layout
// (Event_Refit_Rejected) when it cannot apply.
Refit_Command :: union {
	Refit_Install,
	Refit_Replace,
	Refit_Move,
	Refit_Remove,
	Refit_Finish,
}

// Refit_Install places the refit's pending incoming fitting into `slot` (issue
// #95). Rejected if there is no pending fitting, the slot is occupied, or the
// sizes differ (ADR-0004).
Refit_Install :: struct {
	slot: ship.Slot_Index,
}

// Refit_Replace swaps the refit's pending incoming fitting into `slot`,
// discarding whatever occupied it (no inventory — ADR-0012). It is the
// place-or-swap counterpart to Refit_Install: Install targets an empty slot,
// Replace a filled one, so presentation names the operation by the slot's state
// without re-checking the fit itself (issue #111). Rejected — layout untouched —
// if there is no pending fitting or the sizes differ (ADR-0004).
Refit_Replace :: struct {
	slot: ship.Slot_Index,
}

// Refit_Move relocates the fitting in `from` into the empty, same-size `to`
// (issue #95, ADR-0004's fit rule). Rejected without disturbing the layout
// when the source is empty, the destination is occupied, or the sizes differ.
Refit_Move :: struct {
	from: ship.Slot_Index,
	to:   ship.Slot_Index,
}

// Refit_Remove discards the fitting in `slot` (issue #95) — there is no
// inventory, so a removed fitting is gone (ADR-0012). Rejected if the slot is
// already empty.
Refit_Remove :: struct {
	slot: ship.Slot_Index,
}

// Refit_Finish ends the refit and returns Sim to awaiting a travel choice
// (issue #95). Any pending incoming fitting still unplaced is discarded.
Refit_Finish :: struct {}

// Event is the only way presentation learns what happened inside the Sim
// (ADR-0001).
Event :: union {
	Event_Run_Started,
	Event_Travel_Options,
	Event_Arrived_At_Node,
	Event_Ship_Battle_Sighted,
	Event_Battle_Menu,
	Event_Battle_Event,
	Event_Ship_Updated,
	Event_Wreck_Looted,
	Event_Stage_Entered,
	Event_Encounter_Halted,
	Event_Options_Presented,
	Event_Trade_Presented,
	Event_Purchase_Rejected,
	Event_Refit_Started,
	Event_Fitting_Installed,
	Event_Fitting_Moved,
	Event_Fitting_Removed,
	Event_Refit_Rejected,
	Event_Refit_Finished,
	Event_Encounter_Resolved,
	Event_Run_Ended,
}

// Event_Run_Started is dispatched exactly once, on the very first sim_tick
// call. run_map carries the full graph shape (nodes, edges, zones, layer/lane
// layout) and the always-visible landmarks (Start/Port/Goal), but its
// non-revealing Encounter nodes have their *stages* withheld — run_map.nodes is
// the Sim's masked public_nodes, not its private run_map. This is the hiding
// contract (ADR-0009): what a node holds is a surprise revealed only on arrival,
// via Event_Arrived_At_Node carrying that node's full Node, unless the encounter
// contains a revealing stage (ADR-0014). Withholding is a guaranteed data
// property of the emitted event, not a presentation courtesy.
Event_Run_Started :: struct {
	run_map: run.Map,
	ship:    ship.Ship,
}

// Event_Travel_Options is dispatched every time the Sim begins awaiting a
// travel choice (run start, and after each arrival/encounter that returns to
// Awaiting_Travel_Choice): options carries the Node_IDs legally reachable from
// the current position. This is the travel analogue of Event_Battle_Menu's
// may_leave — the legal-move set is state the Sim already computes
// (run_travel_options, once per travel decision) that presentation and tests
// otherwise have to re-derive off a shadow map/visited set they maintain
// themselves (issue #83, ADR-0001's "presentation learns only through Events").
// The slice borrows the Sim's run-scoped travel_options buffer: valid across
// this tick's whole dispatch batch, overwritten only at the next travel
// decision, so a sink that needs it past then must copy it out.
Event_Travel_Options :: struct {
	options: []Node_ID,
}

Event_Arrived_At_Node :: struct {
	node: run.Node,
}

// Event_Ship_Battle_Sighted is dispatched once, when a Ship Battle starts:
// the opponent's full ship data (issue #24: the UI applies
// ship.ship_effective_visibility per slot itself when rendering it — see
// Event_Run_Started's doc comment for why Sim doesn't gate this itself).
Event_Ship_Battle_Sighted :: struct {
	opponent: ship.Ship,
}

// Event_Battle_Menu is dispatched every time a battle command decision is
// about to be asked for (battle start, and after every round that doesn't
// end the battle): may_leave is genuinely Battle-internal state (depends on
// this-round's not-yet-reset temp Speed bonuses) the UI has no other way to
// derive, unlike which slots are cargo (derivable from Event_Ship_Updated's
// own ship copy).
Event_Battle_Menu :: struct {
	may_leave: bool,
}

// Event_Battle_Event wraps one event emitted by core/combat's
// combat_resolve_round for a single round (Event_Damage_Dealt,
// Event_Ship_Sunk, Event_Cargo_Jettisoned, Event_Battle_Ended) — the
// canonical ADR-0002 "UI plays this batch back with animation" case.
Event_Battle_Event :: struct {
	inner: combat.Event,
}

// Event_Ship_Updated carries a plain (non-ghost) copy of the player's ship,
// dispatched at run start and whenever its stats/layout change (after a
// combat round, an accepted Trade, or an Upgrade applied). Needed because
// Ghost_Snapshot always resets hull to max_hull on capture (ADR-0008), which
// makes Event_Encounter_Resolved's snapshot unsuitable for an accurate live
// Hull readout.
Event_Ship_Updated :: struct {
	ship: ship.Ship,
}

// Event_Wreck_Looted is dispatched when a won Fight pays out the sunk opponent's
// hold (#159, #196): `gross` is the wreck's whole treasure, `spilled` how much of
// it fell overboard because the player's hold was already near capacity (#157).
// The `ship` change itself still rides Event_Ship_Updated (the panel re-renders off
// that alone); this is the extra fact presentation needs to *say what happened* —
// naming the haul, and any spill, on the beat a Reward payout gets from its own
// stage-entry beat. It carries the amounts rather than the ship because the spilled
// treasure is by definition not on the post-payout ship: it is the difference
// between what the wreck held and what actually fit, so it cannot be re-derived
// from Event_Ship_Updated's copy. `spilled` is 0 for the common in-capacity payout.
Event_Wreck_Looted :: struct {
	gross:   int,
	spilled: int,
}

// Event_Stage_Entered says where the encounter's walk is: the cursor has landed on
// `index` of `count` stages, and that stage is a `kind` (issue #139). Dispatched by
// sim_walk_encounter as it enters each stage, before whatever that primitive presents.
//
// The **cursor is the fact** here, and it is the one thing about a walk that
// presentation cannot hold a copy of. Event_Arrived_At_Node already hands over the
// node's whole Encounter — its stage list is right there, and the map view reads it to
// label the node (ADR-0016) — but that copy's cursor is frozen at the moment of
// arrival, because the walk advances the Sim's *private* map. So presentation knows the
// encounter's shape and needs to be told its position, which is exactly what this
// carries. It is not a "which screen do I show" signal: that is Phase's job (issue
// #39), and a stage that presents something presents it on its own event.
//
// `kind` and `count` are on it despite being derivable from that copy, because the
// event stream is itself an artifact — cmd/headless prints every event, and the runs
// pinned per seed are read by people. `Event_Stage_Entered{kind = .Reward, index = 1,
// count = 2}` says what happened; a bare index does not, unless the reader
// cross-references a map they were handed several hundred lines earlier. They cannot
// drift from the copy either: a walk moves the cursor and nothing else.
//
// **Re-entering a stage re-emits this**, which is deliberate and shared with
// Event_Options_Presented: a Shop's buy routes back through the walk to re-present the
// refilled shelf, and re-stating "still stage 2 of 3" is the honest account of that.
Event_Stage_Entered :: struct {
	kind:  run.Stage_Kind,
	index: int,
	count: int,
}

// Event_Encounter_Halted reports a stage resolving to .Halted (issue #139, ADR-0014):
// the encounter ends at stage `index` of `count`, and the stages behind it are never
// reached. `at` is the primitive that halted — a Fight taking ADR-0006's escape, an
// Offer skipped, a Trade rejected.
//
// **Only the halt is announced, and the asymmetry is the point.** A completion needs no
// event because it is already visible: the next stage arrives and says so, or the walk
// ends and Event_Travel_Options puts the captain back on the map. A halt is the one
// outcome with *nothing to show* — the stages that should have followed simply don't —
// so a captain who flees a [Fight, Reward] watches the loot not happen and has no way
// to tell "you gave that up" from "the game forgot". That is the difference between
// learning the rule and filing a bug, and it is why complete-or-halt needs a voice here
// but not a symmetric pair of events.
//
// What was forfeited is *not* carried: presentation names it off the Encounter it was
// handed at arrival (stages `index+1 ..< count`), the same copy the map view already
// labels nodes from. `index` and `count` are what pick that range out, and they are all
// the walk knows that the copy doesn't.
Event_Encounter_Halted :: struct {
	at:    run.Stage_Kind,
	index: int,
	count: int,
}

// Event_Options_Presented carries the option list of whichever option-list stage
// the cursor just landed on (issue #131) — an Offer's distinct roster items or a
// Shop's shelf cards, one event because they are one presentation. Dispatched as
// the stage is entered, and again on each return from a buy's Refit so a shop's
// live draw-down is always visible.
//
// Each `options` slot is a Maybe(Stage_Option): the option on that position, or nil
// for a position carrying nothing — a Shop shelf past the deck's tail (the graceful
// short-deck case, never reached at the real roster size) or any slot past a
// narrower stage's count (an Offer presents ITEM_OFFER_OPTION_COUNT of
// STAGE_OPTION_MAX). A slot's index is its Command_Choose_Option Option_Index, so
// presentation must keep positions, not compact the list.
//
// Presentation renders each option's tags, phase, size, effect intent — and its
// cost where it has one — and offers a take-one-or-decline choice; taking a priced
// option it can afford, or any free one, opens a Refit (Event_Refit_Started). The
// purse affordability is measured against is the ship's hold (ship_treasure), read
// off the latest Event_Ship_Updated — not duplicated here, so the two can't disagree.
Event_Options_Presented :: struct {
	options: [STAGE_OPTION_MAX]Maybe(Stage_Option),
}

// Event_Trade_Presented carries the bargain a Trade stage is offering (issue
// #136, ADR-0014), dispatched as the cursor lands on a Trade stage. `trade` is
// the axis the node drew from the roster at generation, with both sides'
// magnitudes already baked from its site — presentation renders it as "gain this,
// cost that" off the two terms' stats and amounts, and offers accept-or-reject.
//
// `can_accept` is whether the ship can pay the cost in full (run_trade_can_accept):
// genuinely Sim-side state, since it depends on the ship's *effective* stats — the
// base fields on the last Event_Ship_Updated aren't enough to re-derive it, so
// presentation would have to reimplement the floor rule to know whether accept is
// a legal answer. This is the trade counterpart of Event_Battle_Menu's may_leave,
// for the same reason.
Event_Trade_Presented :: struct {
	trade:      run.Stage_Trade,
	can_accept: bool,
}

// Event_Purchase_Rejected reports a buy the ship could not afford (issue #98): the
// option's cost exceeds the current hold (ship_treasure), so no treasure is spent and
// no Refit opens — the stage simply stays open for another choice. `option` echoes
// the refused line, at the price it was refused at, so presentation can explain it
// — mirroring Event_Refit_Rejected's echo of a refused loadout command. Only a
// priced option can be rejected, so the echoed option's cost is always set.
Event_Purchase_Rejected :: struct {
	option: Stage_Option,
}

// Event_Refit_Started brackets the opening of a Refit (issue #95): `incoming`
// is the fitting the refit was opened to place (from an Item Offer or Port
// shop — #96/#98), or nil for a rearrange-only refit. Presentation opens its
// loadout-editing menu on this and closes it on Event_Refit_Finished.
Event_Refit_Started :: struct {
	incoming: Maybe(ship.Fitting),
}

// Event_Fitting_Installed / _Moved / _Removed each describe one applied loadout
// change during a Refit (issue #95). _Removed's fitting is discarded (no
// inventory — ADR-0012); it is carried here only so presentation can name what
// was dropped, not because anything still holds it.
Event_Fitting_Installed :: struct {
	slot:    ship.Slot_Index,
	fitting: ship.Fitting,
}

Event_Fitting_Moved :: struct {
	from:    ship.Slot_Index,
	to:      ship.Slot_Index,
	fitting: ship.Fitting,
}

Event_Fitting_Removed :: struct {
	slot:    ship.Slot_Index,
	fitting: ship.Fitting,
}

// Event_Refit_Rejected reports a loadout command that violated the fit rule
// (ADR-0004) and was refused without disturbing the layout (issue #95): a size
// mismatch, an occupied or empty target, or an install with nothing pending.
// `command` echoes the refused operation so presentation can explain it.
Event_Refit_Rejected :: struct {
	command: Refit_Command,
}

// Event_Refit_Finished brackets the close of a Refit (issue #95): Sim returns
// to awaiting a travel choice and any still-unplaced incoming fitting is
// discarded.
Event_Refit_Finished :: struct {}

// Event_Encounter_Resolved carries a resolved encounter's Ghost_Snapshot
// (ADR-0008) out through Sim's own Event boundary. The snapshot (including its
// cloned layout) is allocated from the Sim's own run-scoped arena (issue #52):
// valid for as long as the Sim itself and reclaimed in one shot by
// sim_destroy, not owned or freed per-recipient. A sink that needs a snapshot
// to outlive the Sim must copy it out explicitly.
//
// **Once per encounter** — per *node*, not per stage (issue #162, ADR-0008 as
// amended): the ship the captain leaves the node with, whatever the whole stage
// list made of it. So a [Fight, Reward] emits one snapshot, taken post-loot; an
// Offer or a Shop emits one carrying what was taken aboard; a halt emits one (the
// fled ship is a real ship); and a **sinking emits none**, because the walk stops
// dead and the node is never resolved. Snapshot count per run is therefore the
// number of encounter nodes resolved, and Event_Ship_Updated — not this — is what
// reports each individual change on the way through.
Event_Encounter_Resolved :: struct {
	snapshot: run.Ghost_Snapshot,
}

Event_Run_Ended :: struct {
	status: run.Run_Status,
}

sim_create :: proc(seed: u64) -> Sim {
	s: Sim
	arena_err := virtual.arena_init_growing(&s.arena)
	assert(arena_err == nil, "failed to initialize the Sim's run-scoped arena")
	context.allocator = virtual.arena_allocator(&s.arena)

	s.rng = rand.create_u64(seed)
	s.run_map = run.run_map_create(seed)
	s.public_nodes = sim_mask_encounters(s.run_map.nodes)
	s.player = ship.ship_starting_ship()
	s.resolved = make([]bool, len(s.run_map.nodes))
	s.visited = make([]bool, len(s.run_map.nodes))
	s.visited[0] = true // the ship starts at Start (id 0), so retrace to it is legal from the outset.
	s.travel_options = make([dynamic]Node_ID, 0, 8) // arena-backed (context.allocator is the arena here); reused every travel decision.
	s.status = .In_Progress
	s.phase = .Awaiting_Travel_Choice
	return s
}

// sim_mask_encounters builds the masked public view of nodes (the hiding
// contract): a fresh copy in which every hidden encounter's content is withheld
// (encounter = nil), while landmarks and revealing encounters pass through fully
// described. Graph shape (zone, layer, lane, id) is preserved on every node.
// Allocated from whatever allocator is in scope (the Sim's run-scoped arena at
// sim_create time).
//
// What gets withheld is asked of the **stage list and nothing else**
// (run.run_encounter_reveals, ADR-0014/ADR-0016): an encounter whose **first** stage
// reveals shows itself on the map before arrival, so it passes through unmasked, and
// a node with no encounter has nothing to withhold. The node *kind* is not consulted
// at all — that is the point. It is what lets a Port be an ordinary node that happens
// to carry a [Shop] recipe (visible because Shop reveals, not because .Port is
// exempt), and what keeps a merchant vessel at sea — which carries a Shop but puts a
// stage in front of it — masked on the same rule, with no branch of its own.
//
// Since only the Port bucket opens on a Shop (catalog.odin), what survives this mask
// today is exactly the six Ports plus Start and Goal. That is a *derived* constant,
// not a stored one: author one [Shop, Fight] and it stops being true, which is why
// the question is still asked of the stages rather than answered from the kind. See
// ADR-0016 — that distinction is thinner than it reads, and deliberately kept.
//
// Withholding stays a guaranteed data property of the emitted event, not a
// presentation courtesy (ADR-0009): a masked node's stages are absent from the
// Event_Run_Started payload, so presentation cannot leak what it never received.
sim_mask_encounters :: proc(nodes: []run.Node) -> []run.Node {
	masked := make([]run.Node, len(nodes))
	for p, i in nodes {
		masked[i] = p
		enc, has_encounter := p.encounter.?
		if !has_encounter || run.run_encounter_reveals(enc) {
			continue
		}
		masked[i].encounter = nil
	}
	return masked
}

// sim_destroy tears down the Sim's run-scoped arena in one call (issue #52):
// every run-lifetime allocation — the map's Nodes and each Ship Battle
// opponent's layout, the player's own layout, and any outstanding
// Ghost_Snapshot — lives in it, so there's nothing left to free by hand.
sim_destroy :: proc(sim: ^Sim) {
	virtual.arena_destroy(&sim.arena)
}

// sim_arena_allocator is the Sim's run-scoped allocator (issue #52), shared
// by every sim_process_* call site that scopes context.allocator to it
// around one arena-backed allocation (a Ghost_Snapshot capture).
sim_arena_allocator :: proc(sim: ^Sim) -> mem.Allocator {
	return virtual.arena_allocator(&sim.arena)
}

// sim_tick resolves one unit of work and batch-emits the resulting events.
// What that unit of work is depends on Phase: applying a just-submitted
// travel choice (which may itself trigger an encounter), resolving one
// battle round, or applying an upgrade pick. Calling sim_tick again while
// still awaiting a decision is a driver bug (ADR-0001), same as before.
sim_tick :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	assert(!sim.awaiting_decision, "sim_tick called while a captain decision is still outstanding")

	switch sim.phase {
	case .Awaiting_Travel_Choice:
		sim_process_travel(sim, events)
	case .Awaiting_Battle_Command:
		sim_process_battle_round(sim, events)
	case .Awaiting_Option_Choice:
		sim_process_option_choice(sim, events)
	case .Awaiting_Trade_Choice:
		sim_process_trade_choice(sim, events)
	case .Awaiting_Refit:
		sim_process_refit(sim, events)
	case .Ended:
		assert(false, "sim_tick called after the run already ended")
	}

	if sim.phase == .Ended {
		return
	}

	sim.status = run.run_status(&sim.player, sim.run_map.nodes[sim.current])
	if sim.status != .In_Progress {
		sim.phase = .Ended
		append(events, Event(Event_Run_Ended{status = sim.status}))
		return
	}

	// Whatever unit of work just ran, if the Sim is now awaiting a travel choice
	// (run start, or a battle/upgrade/trade that returned to it) broadcast the
	// legal destinations so consumers pick from what the Sim computed, not a
	// re-derivation (issue #83). Concentrating the emit here — rather than at
	// each phase-transition site — is why every path back to a travel choice
	// carries the options with no per-site repetition.
	if sim.phase == .Awaiting_Travel_Choice {
		sim_emit_travel_options(sim, events)
	}

	sim.awaiting_decision = true
}

// sim_emit_travel_options computes the legal destinations from the current
// node — run_travel_options, the single legality predicate, called once per
// travel decision (issue #83) — stages them (as Node_IDs) in the Sim's
// run-scoped travel_options buffer, and emits them on Event_Travel_Options.
// run_travel_options' own returned slice is Tick-lifetime temp_allocator
// scratch, reclaimed at the run_session free_all boundary; the reused buffer
// is what the event borrows, so the emitted payload survives the tick's whole
// dispatch batch yet isn't a fresh arena allocation per decision (which would
// pile up unreclaimed until sim_destroy).
sim_emit_travel_options :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	options := run.run_travel_options(sim.run_map, sim.current, sim.visited)

	clear(&sim.travel_options)
	for id in options {
		append(&sim.travel_options, id)
	}
	append(events, Event(Event_Travel_Options{options = sim.travel_options[:]}))
}

// sim_submit_captain_choice validates cmd against Sim's current Phase (the
// same assert-and-store shape as before, just per-phase now) and stores it
// for the next sim_tick call to consume.
sim_submit_captain_choice :: proc(sim: ^Sim, cmd: Command) {
	assert(sim.awaiting_decision, "submitted a captain choice while the sim wasn't awaiting one")

	switch sim.phase {
	case .Awaiting_Travel_Choice:
		_, ok := cmd.(Command_Travel_To)
		assert(ok, "expected a Command_Travel_To while awaiting a travel choice")
	case .Awaiting_Battle_Command:
		_, ok := cmd.(Command_Battle_Choice)
		assert(ok, "expected a Command_Battle_Choice while awaiting a battle command")
	case .Awaiting_Option_Choice:
		_, ok := cmd.(Command_Choose_Option)
		assert(ok, "expected a Command_Choose_Option while awaiting an option choice")
	case .Awaiting_Trade_Choice:
		_, ok := cmd.(Command_Trade_Choice)
		assert(ok, "expected a Command_Trade_Choice while awaiting a trade choice")
	case .Awaiting_Refit:
		_, ok := cmd.(Command_Refit)
		assert(ok, "expected a Command_Refit while awaiting a refit command")
	case .Ended:
		assert(false, "submitted a captain choice after the run ended")
	}

	sim.pending_command = cmd
	sim.awaiting_decision = false
}

// sim_emit_encounter_resolved captures the ship the captain is leaving this node
// with as a Ghost_Snapshot on the Sim's run-scoped arena, and emits it (issue #82,
// ADR-0008). run_ghost_snapshot_of describes the ship with a *borrowed* layout;
// run_ghost_snapshot_capture clones that layout under the arena so it outlives the
// tick (issue #52) and lives as long as the Sim. Concentrating the arena ritual
// here is why the make-scratch / scope-arena / forward dance appears once.
//
// Called from exactly one place — sim_walk_encounter, as the cursor runs off the
// end of the node's stage list (issue #162) — so run_ghost_snapshot_of has one call
// site and both halves of #82's borrowed-vs-owned handoff sit in one proc. That is
// also why it takes no site or step count: at the walk's end the node the ship is
// standing at *is* the node being snapshotted, so the two are simply at hand.
sim_emit_encounter_resolved :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	context.allocator = sim_arena_allocator(sim)
	captured := run.run_ghost_snapshot_capture(
		run.run_ghost_snapshot_of(&sim.player, sim.steps, sim_current_site(sim)),
	)
	append(events, Event(Event_Encounter_Resolved{snapshot = captured}))
}
