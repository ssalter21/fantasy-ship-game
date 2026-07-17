package sim

import "../combat"
import "../voyage"
import "../ship"
import "core:math/rand"
import "core:mem"
import "core:mem/virtual"

// Phase is the kind of captain decision the Sim is (or is about to be) awaiting.
// run_session passes it into Input_Source.get_captain_choice (ADR-0002) so adapters
// route straight to the right decision UI instead of re-deriving it from the Event
// stream.
//
// A Phase names a *kind of decision*, not a stage primitive (ADR-0014): an encounter's
// stages are walked by one generic path (sim_encounter.odin) that parks in whichever
// phase the stage under the cursor asks for, so adding a stage primitive must not add a
// phase. Each survivor earns its place on a distinct decision *shape*:
//   - Awaiting_Travel_Choice — the routing choice *between* encounters, which no stage
//     list can express.
//   - Awaiting_Battle_Command — a multi-round sub-mode over combat.Command (ADR-0006),
//     not a one-shot pick from a list.
//   - Awaiting_Option_Choice — "pick one of a few, or decline", shared by every
//     option-list stage (an Offer's items, a Shop's shelf).
//   - Awaiting_Trade_Choice — a one-bargain accept/reject: two answers over no list, so
//     not the "pick one of N, or decline" shape. A second accept/reject primitive must
//     reuse it rather than add its neighbour.
//   - Awaiting_Refit — a sub-mode over the loadout, shared by every stage that hands the
//     player an item.
//   - Ended is terminal.
Phase :: enum {
	Awaiting_Travel_Choice,
	Awaiting_Battle_Command,
	Awaiting_Option_Choice,
	Awaiting_Trade_Choice,
	Awaiting_Refit,
	Ended,
}

// Node_ID identifies a node in voyage_map.nodes by position, crossing the Sim boundary
// via Command_Travel_To and Event_Travel_Options. An alias of voyage.Node_ID: run owns
// the Map and so owns the canonical distinct type (ADR-0011), and aliasing lets that one
// type cross the run/sim boundary with no int conversion.
Node_ID :: voyage.Node_ID

// Option_Index identifies one of an option-list stage's presented options by position —
// distinct from a plain int (ADR-0011) so it can't be passed where a node id or slot
// index belongs. Indexes stage_options, an Offer's items or a Shop's shelf alike.
Option_Index :: distinct int

// STAGE_OPTION_MAX is the width of the one presented list every option-list stage shares
// (Event_Options_Presented, Sim.stage_options). Derived from the primitives' own counts
// rather than picked, so a roomier stage can never overflow the array the Sim stages it in.
STAGE_OPTION_MAX :: max(voyage.ITEM_OFFER_OPTION_COUNT, voyage.SHOP_SHELF_SIZE)

// Stage_Option is one line of an option-list stage's presented list — the fitting on offer
// and what it costs in cargo, nil when free. An alias of voyage.Stage_Option: voyage owns
// the option list's content and prices it (voyage_shop_option), so it owns the canonical
// type (ADR-0011), and aliasing lets that one type cross the Sim's Event seam and reach
// presentation with no repacking.
Stage_Option :: voyage.Stage_Option

Sim :: struct {
	// rng is kept per ADR-0001 (Sim owns its own seeded RNG for deterministic replay).
	// Nothing in the domain logic is random yet — map layout and combat are deterministic —
	// but the field stays because ADR-0001 commits to it as Sim's shape.
	rng:               rand.Default_Random_State,
	voyage_map:           voyage.Map,
	// public_nodes is the masked view of voyage_map.nodes the Sim broadcasts at voyage start
	// (the hiding contract, ADR-0009): a copy that nils every hidden encounter's stage list
	// while preserving graph shape and landmarks, so presentation cannot leak what a node
	// holds before arrival. An encounter with a revealing stage (ADR-0014) passes through
	// unmasked — asked of the stage list alone, never the node's kind. Content is revealed
	// per-node on arrival via Event_Arrived_At_Node. See sim_mask_encounters.
	public_nodes:      []voyage.Node,
	player:            ship.Ship,
	current:           Node_ID, // index into voyage_map.nodes; Start is always 0
	// resolved is parallel to voyage_map.nodes: true once the encounter at that node has been
	// walked to the end — every stage completed, or one halted (ADR-0014). Node-level and
	// once, for every encounter alike; sim_walk_encounter is its only writer. []bool rather
	// than bit_set because bit_set needs a compile-time-bounded index, but resolved is indexed
	// by Node_ID, sized at runtime off voyage_map_create's node count.
	resolved:          []bool,
	// visited is parallel to voyage_map.nodes: true once the ship has been at a node (Start
	// counts from the outset). Distinct from resolved — a node holding no encounter (Start,
	// Haven) is visited but never resolved — and it is what voyage_travel_options consults to
	// decide which backward-retrace moves are legal.
	visited:           []bool,
	// travel_options stages the legal travel destinations broadcast on Event_Travel_Options
	// when awaiting a travel choice: run-scoped arena storage, cleared and refilled from
	// voyage_travel_options once per travel decision and borrowed by the emitted event.
	travel_options:    [dynamic]Node_ID,
	steps:             int, // Ghost_Snapshot progress counter, +1 per travel
	status:            voyage.Voyage_Status,
	phase:             Phase,
	awaiting_decision: bool,
	pending_command:   Maybe(Command),
	battle:            combat.Battle,
	active_encounter:  voyage.Stage_Fight,
	// stage_options is the option list the stage under the cursor is presenting — an Offer's
	// items or a Shop's shelf. Filled by sim_enter_stage, broadcast on Event_Options_Presented,
	// and indexed by a Command_Choose_Option's Option_Index to resolve the selection back to
	// its fitting and price. A nil slot is a position with no option (a Shop shelf past the
	// deck's tail, or any slot past a narrower stage's count), never selectable.
	stage_options:     [STAGE_OPTION_MAX]Maybe(Stage_Option),
	// shop_visit is the working state of the one Shop stage under the cursor — a single visit,
	// not a row per node. sim_advance_stage clears it as the cursor leaves the stage, so the
	// next Shop reached always deals itself a fresh shelf.
	shop_visit:        Shop_Visit,
	// active_trade is the bargain the Trade stage under the cursor is offering: staged as the
	// cursor lands on it and broadcast on Event_Trade_Presented, then applied by a
	// Command_Trade_Choice that accepts. The choice arrives a tick after entry, so the stage's
	// baked content must outlive the entry. A plain value, not a Maybe: only ever read while
	// the phase says a trade is on screen.
	active_trade:      voyage.Stage_Trade,
	// refit_pending is the incoming fitting an open Refit was opened to place: set by
	// sim_open_refit, consumed when a Refit_Install lands it in a slot, and nil'd when the
	// refit finishes without installing it — there is no inventory to hold it (ADR-0012). nil
	// for a rearrange-only refit or once the item is placed.
	refit_pending:     Maybe(ship.Fitting),
	// arena is the Sim's run-scoped allocator: every allocation that lives no longer than the
	// Sim — the map's Nodes, each Battle opponent's layout, the player's layout, every
	// Ghost_Snapshot handed out via Event_Encounter_Resolved — comes from here, so sim_destroy
	// reclaims it all in one call (ADR-0010).
	arena:             virtual.Arena,
}

// Command is the only way presentation may mutate the Sim (ADR-0001). Which
// variant is valid depends on Sim's current Phase; the Phase's processor asserts
// the pending Command is the variant it expects as it unwraps it (sim_take_pending).
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

// Command_Choose_Option answers whichever option-list stage is under the cursor, valid only
// in the Awaiting_Option_Choice phase. `selection` is the option the captain took (an
// Option_Index into stage_options), or nil to **decline** — skipping an Offer, leaving a
// Shop. A Maybe rather than a sentinel index, so declining is a distinct, unmistakable value.
Command_Choose_Option :: struct {
	selection: Maybe(Option_Index),
}

// Command_Trade_Choice answers the Trade stage under the cursor, valid only in the
// Awaiting_Trade_Choice phase. `accept` takes the bargain — paying its cost for its gain,
// permanently — and completes the stage; false rejects it, changing nothing and **halting**
// the encounter, so a stage behind a rejected Trade is never reached.
//
// A plain bool, not a Maybe: a trade is one bargain with exactly two answers, so there is no
// "decline distinct from every index" to represent.
//
// Accepting a trade the ship cannot pay for (voyage_trade_can_accept) is a driver bug, not a
// runtime rejection: the Sim broadcasts can_accept on Event_Trade_Presented, so presentation
// knows not to offer it.
Command_Trade_Choice :: struct {
	accept: bool,
}

// Command_Refit carries one loadout operation during a Refit, valid only in the
// Awaiting_Refit phase. The inner Refit_Command says which operation. Wrapped as a single
// Command variant (not four) so the Sim's Command/Phase vocabulary — and every exhaustive
// switch over it — gains one case, not four, mirroring Command_Battle_Choice, which likewise
// carries an inner (combat) union.
Command_Refit :: struct {
	command: Refit_Command,
}

// Refit_Command is the closed set of loadout operations a Refit accepts. Install places the
// pending incoming fitting into an empty slot and Replace swaps it into a filled one; Move
// and Remove act on already-installed fittings; Finish ends the refit. Every operation
// enforces ADR-0004's exact-size fit rule and is rejected without disturbing the layout
// (Event_Refit_Rejected) when it cannot apply.
Refit_Command :: union {
	Refit_Install,
	Refit_Replace,
	Refit_Move,
	Refit_Remove,
	Refit_Finish,
}

// Refit_Install places the refit's pending incoming fitting into `slot`. Rejected if there is
// no pending fitting, the slot is occupied, or the sizes differ (ADR-0004).
Refit_Install :: struct {
	slot: ship.Slot_Index,
}

// Refit_Replace swaps the refit's pending incoming fitting into `slot`, discarding whatever
// occupied it (no inventory — ADR-0012). The place-or-swap counterpart to Refit_Install:
// Install targets an empty slot, Replace a filled one, so presentation names the operation by
// the slot's state. Rejected — layout untouched — if there is no pending fitting or the sizes
// differ (ADR-0004).
Refit_Replace :: struct {
	slot: ship.Slot_Index,
}

// Refit_Move relocates the fitting in `from` into the empty, same-size `to` (ADR-0004).
// Rejected without disturbing the layout when the source is empty, the destination is
// occupied, or the sizes differ.
Refit_Move :: struct {
	from: ship.Slot_Index,
	to:   ship.Slot_Index,
}

// Refit_Remove discards the fitting in `slot` — there is no inventory, so a removed fitting is
// gone (ADR-0012). Rejected if the slot is already empty.
Refit_Remove :: struct {
	slot: ship.Slot_Index,
}

// Refit_Finish ends the refit and returns Sim to awaiting a travel choice. Any pending
// incoming fitting still unplaced is discarded.
Refit_Finish :: struct {}

// Event is the only way presentation learns what happened inside the Sim
// (ADR-0001).
Event :: union {
	Event_Voyage_Started,
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
	Event_Voyage_Ended,
}

// Event_Voyage_Started is dispatched exactly once, on the first sim_tick. voyage_map carries
// the full graph shape and always-visible landmarks (Start/Port/Haven), but non-revealing
// Encounter nodes have their *stages* withheld — it carries the masked public_nodes, not the
// private voyage_map. This is the hiding contract (ADR-0009): what a node holds is revealed
// only on arrival via Event_Arrived_At_Node, unless the encounter has a revealing stage
// (ADR-0014). Withholding is a guaranteed data property of the event, not a courtesy.
Event_Voyage_Started :: struct {
	voyage_map: voyage.Map,
	ship:    ship.Ship,
}

// Event_Travel_Options is dispatched every time the Sim begins awaiting a travel choice:
// options carries the Node_IDs legally reachable from the current position, state the Sim
// already computes (voyage_travel_options) so presentation and tests need not re-derive it off
// a shadow map (ADR-0001). The slice borrows the Sim's run-scoped travel_options buffer: valid
// across this tick's dispatch batch, overwritten at the next travel decision, so a sink that
// needs it later must copy it out.
Event_Travel_Options :: struct {
	options: []Node_ID,
}

Event_Arrived_At_Node :: struct {
	node: voyage.Node,
}

// Event_Ship_Battle_Sighted is dispatched once, when a Ship Battle starts: the opponent's full
// ship data. The UI applies ship.ship_effective_visibility per slot itself when rendering it
// (see Event_Voyage_Started for why Sim doesn't gate this).
Event_Ship_Battle_Sighted :: struct {
	opponent: ship.Ship,
}

// Event_Battle_Menu is dispatched every time a battle command decision is about to be asked
// for (battle start, and after every round that doesn't end the battle): may_break_off is
// Battle-internal state (depends on this round's not-yet-reset temp Speed bonuses) the UI has
// no other way to derive.
Event_Battle_Menu :: struct {
	may_break_off: bool,
}

// Event_Battle_Event wraps one event emitted by core/combat's combat_resolve_round for a
// single round (Event_Damage_Dealt, Event_Ship_Sunk, Event_Cargo_Jettisoned,
// Event_Battle_Ended) — the ADR-0002 "UI plays this batch back with animation" case.
Event_Battle_Event :: struct {
	inner: combat.Event,
}

// Event_Ship_Updated carries a plain (non-ghost) copy of the player's ship, at voyage start
// and whenever its stats/layout change (a combat round, an accepted Trade, an Upgrade). Needed
// because Ghost_Snapshot resets hull to max_hull on capture (ADR-0008), so
// Event_Encounter_Resolved's snapshot is unsuitable for an accurate live Hull readout.
Event_Ship_Updated :: struct {
	ship: ship.Ship,
}

// Event_Wreck_Looted is dispatched when a won Fight pays out the sunk opponent's hold: `gross`
// is the wreck's whole cargo, `spilled` how much fell overboard because the player's hold was
// near capacity. The ship change itself rides Event_Ship_Updated; this is the extra fact
// presentation needs to say what happened. It carries the amounts rather than the ship because
// the spilled cargo is by definition not on the post-payout ship, so it cannot be re-derived
// from Event_Ship_Updated's copy. `spilled` is 0 for the common in-capacity payout.
Event_Wreck_Looted :: struct {
	gross:   int,
	spilled: int,
}

// Event_Stage_Entered says where the encounter's walk is: the cursor has landed on `index` of
// `count` stages, and that stage is a `kind`. Dispatched by sim_walk_encounter as it enters
// each stage. The cursor is the one fact about a walk presentation cannot hold a copy of —
// Event_Arrived_At_Node hands over the node's whole Encounter, but that copy's cursor is frozen
// at arrival while the walk advances the Sim's *private* map. It is not a "which screen" signal:
// that is Phase's job.
//
// `kind` and `count` ride along despite being derivable from that copy because the event stream
// is itself an artifact — cmd/headless prints every event, and pinned voyages are read by
// people, so `{kind = .Reward, index = 1, count = 2}` says what happened where a bare index
// would not. Re-entering a stage re-emits this (shared with Event_Options_Presented): a Shop's
// buy routes back through the walk to re-present the refilled shelf.
Event_Stage_Entered :: struct {
	kind:  voyage.Stage_Kind,
	index: int,
	count: int,
}

// Event_Encounter_Halted reports a stage resolving to .Halted (ADR-0014): the encounter ends
// at stage `index` of `count`, and the stages behind it are never reached. `at` is the
// primitive that halted — a Fight escaping (ADR-0006), an Offer skipped, a Trade rejected.
//
// Only the halt is announced, and the asymmetry is the point: a completion needs no event
// because it is already visible (the next stage arrives, or the walk ends and
// Event_Travel_Options returns the captain to the map), whereas a halt is the one outcome with
// nothing to show, so a captain who flees a [Fight, Reward] can't otherwise tell "you gave that
// up" from "the game forgot". What was forfeited is not carried: presentation names it off the
// Encounter it was handed at arrival (stages `index+1 ..< count`); `index` and `count` pick
// that range out.
Event_Encounter_Halted :: struct {
	at:    voyage.Stage_Kind,
	index: int,
	count: int,
}

// Event_Options_Presented carries the option list of whichever option-list stage the cursor
// just landed on — an Offer's roster items or a Shop's shelf cards. Dispatched as the stage is
// entered, and again on each return from a buy's Refit so a shop's live draw-down stays visible.
//
// Each slot is a Maybe(Stage_Option): the option there, or nil for a position carrying nothing
// (a Shop shelf past the deck's tail, or a slot past a narrower stage's count). A slot's index
// is its Command_Choose_Option Option_Index, so presentation must keep positions, not compact
// the list. Affordability is measured against the ship's hold (ship_cargo) read off the latest
// Event_Ship_Updated, not duplicated here, so the two can't disagree.
Event_Options_Presented :: struct {
	options: [STAGE_OPTION_MAX]Maybe(Stage_Option),
}

// Event_Trade_Presented carries the bargain a Trade stage is offering, dispatched as the cursor
// lands on a Trade stage. `trade` is the axis the node drew at generation, with both sides'
// magnitudes baked from its site. `can_accept` is whether the ship can pay the cost in full
// (voyage_trade_can_accept): Sim-side state, since it depends on the ship's *effective* stats,
// which the base fields on Event_Ship_Updated aren't enough to re-derive. This is the trade
// counterpart of Event_Battle_Menu's may_break_off.
Event_Trade_Presented :: struct {
	trade:      voyage.Stage_Trade,
	can_accept: bool,
}

// Event_Purchase_Rejected reports a buy the ship could not afford: the option's cost exceeds
// the current hold (ship_cargo), so no cargo is spent and no Refit opens — the stage stays open
// for another choice. `option` echoes the refused line at its price so presentation can explain
// it. Only a priced option can be rejected, so the echoed option's cost is always set.
Event_Purchase_Rejected :: struct {
	option: Stage_Option,
}

// Event_Refit_Started brackets the opening of a Refit: `incoming` is the fitting the refit was
// opened to place (from an Offer or Shop), or nil for a rearrange-only refit. Presentation
// opens its loadout-editing menu on this and closes it on Event_Refit_Finished.
Event_Refit_Started :: struct {
	incoming: Maybe(ship.Fitting),
}

// Event_Fitting_Installed / _Moved / _Removed each describe one applied loadout change during a
// Refit. _Removed's fitting is discarded (no inventory — ADR-0012); it is carried only so
// presentation can name what was dropped.
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

// Event_Refit_Rejected reports a loadout command that violated the fit rule (ADR-0004) and was
// refused without disturbing the layout: a size mismatch, an occupied or empty target, or an
// install with nothing pending. `command` echoes the refused operation.
Event_Refit_Rejected :: struct {
	command: Refit_Command,
}

// Event_Refit_Finished brackets the close of a Refit: Sim returns to awaiting a travel choice
// and any still-unplaced incoming fitting is discarded.
Event_Refit_Finished :: struct {}

// Event_Encounter_Resolved carries a resolved encounter's Ghost_Snapshot (ADR-0008) out through
// Sim's Event boundary. The snapshot (including its cloned layout) is allocated from the Sim's
// run-scoped arena: valid as long as the Sim and reclaimed in one shot by sim_destroy. A sink
// that needs it to outlive the Sim must copy it out.
//
// Once per encounter — per *node*, not per stage (ADR-0008 as amended): the ship the captain
// leaves the node with, whatever the whole stage list made of it. A [Fight, Reward] emits one
// snapshot taken post-loot; an Offer or Shop emits one carrying what was taken aboard; a halt
// emits one (the fled ship is a real ship); a **sinking emits none**, because the walk stops
// dead and the node is never resolved. Event_Ship_Updated — not this — reports each individual
// change on the way through.
Event_Encounter_Resolved :: struct {
	snapshot: voyage.Ghost_Snapshot,
}

Event_Voyage_Ended :: struct {
	status: voyage.Voyage_Status,
}

sim_create :: proc(seed: u64) -> Sim {
	s: Sim
	arena_err := virtual.arena_init_growing(&s.arena)
	assert(arena_err == nil, "failed to initialize the Sim's run-scoped arena")
	context.allocator = virtual.arena_allocator(&s.arena)

	s.rng = rand.create_u64(seed)
	s.voyage_map = voyage.voyage_map_create(seed)
	s.public_nodes = sim_mask_encounters(s.voyage_map.nodes)
	s.player = ship.ship_starting_ship()
	s.resolved = make([]bool, len(s.voyage_map.nodes))
	s.visited = make([]bool, len(s.voyage_map.nodes))
	s.visited[0] = true // the ship starts at Start (id 0), so retrace to it is legal from the outset.
	s.travel_options = make([dynamic]Node_ID, 0, 8) // arena-backed; reused every travel decision.
	s.status = .In_Progress
	s.phase = .Awaiting_Travel_Choice
	return s
}

// sim_mask_encounters builds the masked public view of nodes (the hiding contract, ADR-0009):
// a fresh copy in which every hidden encounter's content is withheld (encounter = nil), while
// landmarks and revealing encounters pass through fully described. Graph shape (zone, layer,
// lane, id) is preserved on every node. Allocated from whatever allocator is in scope (the
// Sim's run-scoped arena at sim_create time), so a masked node's stages are absent from the
// Event_Voyage_Started payload and presentation cannot leak what it never received.
//
// What gets withheld is asked of the **stage list and nothing else**
// (voyage.voyage_encounter_reveals, ADR-0014/ADR-0016): an encounter whose first stage reveals
// shows itself on the map before arrival and passes through unmasked; a node with no encounter
// has nothing to withhold. The node *kind* is not consulted at all — that is what lets a Port
// be an ordinary node carrying a [Shop] recipe (visible because Shop reveals, not because .Port
// is exempt), and keeps a merchant vessel that fronts its Shop with another stage masked on the
// same rule.
sim_mask_encounters :: proc(nodes: []voyage.Node) -> []voyage.Node {
	masked := make([]voyage.Node, len(nodes))
	for p, i in nodes {
		masked[i] = p
		enc, has_encounter := p.encounter.?
		if !has_encounter || voyage.voyage_encounter_reveals(enc) {
			continue
		}
		masked[i].encounter = nil
	}
	return masked
}

// sim_destroy tears down the Sim's run-scoped arena in one call: every run-lifetime allocation
// — the map's Nodes, each Battle opponent's layout, the player's layout, any outstanding
// Ghost_Snapshot — lives in it, so there is nothing left to free by hand.
sim_destroy :: proc(sim: ^Sim) {
	virtual.arena_destroy(&sim.arena)
}

// sim_arena_allocator is the Sim's run-scoped allocator, shared by every sim_process_* call site
// that scopes context.allocator to it around an arena-backed allocation (a Ghost_Snapshot
// capture).
sim_arena_allocator :: proc(sim: ^Sim) -> mem.Allocator {
	return virtual.arena_allocator(&sim.arena)
}

// sim_tick resolves one unit of work and batch-emits the resulting events. What that unit is
// depends on Phase: applying a just-submitted travel choice (which may trigger an encounter),
// resolving one battle round, or applying an upgrade pick. Calling sim_tick again while awaiting
// a decision is a driver bug (ADR-0001).
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
		assert(false, "sim_tick called after the voyage already ended")
	}

	if sim.phase == .Ended {
		return
	}

	sim.status = voyage.voyage_status(&sim.player, sim.voyage_map.nodes[sim.current])
	if sim.status != .In_Progress {
		sim.phase = .Ended
		append(events, Event(Event_Voyage_Ended{status = sim.status}))
		return
	}

	// If the Sim is now awaiting a travel choice, broadcast the legal destinations so consumers
	// pick from what the Sim computed, not a re-derivation. Concentrating the emit here — rather
	// than at each phase-transition site — is why every path back to a travel choice carries the
	// options with no per-site repetition.
	if sim.phase == .Awaiting_Travel_Choice {
		sim_emit_travel_options(sim, events)
	}

	sim.awaiting_decision = true
}

// sim_emit_travel_options computes the legal destinations from the current node
// (voyage_travel_options, the single legality predicate, once per travel decision), stages them
// in the Sim's run-scoped travel_options buffer, and emits them on Event_Travel_Options.
// voyage_travel_options' own slice is Tick-lifetime temp_allocator scratch; the reused buffer is
// what the event borrows, so the payload survives the tick's dispatch batch without a fresh
// arena allocation per decision (which would pile up unreclaimed until sim_destroy).
sim_emit_travel_options :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	options := voyage.voyage_travel_options(sim.voyage_map, sim.current, sim.visited)

	clear(&sim.travel_options)
	for id in options {
		append(&sim.travel_options, id)
	}
	append(events, Event(Event_Travel_Options{options = sim.travel_options[:]}))
}

// sim_submit_captain_choice stores cmd for the next sim_tick to consume. It does not check cmd
// against the current Phase: the Phase's own processor asserts that as it unwraps the pending
// command (sim_take_pending), so the Phase→Command pairing is stated once — at dispatch — rather
// than duplicated in a validation switch here that had to stay in lockstep with sim_tick's.
sim_submit_captain_choice :: proc(sim: ^Sim, cmd: Command) {
	assert(sim.awaiting_decision, "submitted a captain choice while the sim wasn't awaiting one")
	sim.pending_command = cmd
	sim.awaiting_decision = false
}

// sim_take_pending consumes the pending command as variant T: it asserts a command is pending
// and is that variant, clears it, and returns the unwrapped value. Every sim_process_* opens
// with one call to it in place of the repeated fetch-assert-cast-clear ritual.
//
// A pending command of the wrong variant is a driver bug — presentation submitted a Command the
// current Phase never asked for (ADR-0001) — and traps here, at the single point the Phase's
// processor unwraps it. That is why sim_submit_captain_choice needs no validation switch of its
// own: the Phase→Command pairing lives only in which processor sim_tick dispatches to and the T
// it unwraps, enumerated once rather than in two switches kept in lockstep.
sim_take_pending :: proc(sim: ^Sim, $T: typeid) -> T {
	pending, has_pending := sim.pending_command.?
	assert(has_pending, "a phase processor ran with no pending command to consume")
	cmd, ok := pending.(T)
	assert(ok, "the pending command does not match the phase awaiting it")
	sim.pending_command = nil
	return cmd
}

// sim_emit_encounter_resolved captures the ship the captain is leaving this node with as a
// Ghost_Snapshot on the Sim's run-scoped arena, and emits it (ADR-0008). voyage_ghost_snapshot_of
// describes the ship with a *borrowed* layout; voyage_ghost_snapshot_capture clones that layout
// under the arena so it outlives the tick and lives as long as the Sim. Called from exactly one
// place — sim_walk_encounter, as the cursor runs off the end of the node's stage list — which is
// why it takes no site or step count: at the walk's end the node the ship stands at *is* the node
// being snapshotted.
sim_emit_encounter_resolved :: proc(sim: ^Sim, events: ^[dynamic]Event) {
	context.allocator = sim_arena_allocator(sim)
	captured := voyage.voyage_ghost_snapshot_capture(
		voyage.voyage_ghost_snapshot_of(&sim.player, sim.steps, sim_current_site(sim)),
	)
	append(events, Event(Event_Encounter_Resolved{snapshot = captured}))
}
