package forge

import ship "../core/ship"
import voyage "../core/voyage"

// The Forge's editable copy of the game's content tables.
//
// Every draft below is the authored shape of one core table row, held as plain data the
// tool can mutate a field at a time. The Forge is **linked against core**, so a draft is
// loaded by calling the table's own accessor (ship_item_roster, voyage_recipe_catalog,
// …) rather than by parsing source, and it is checked by calling core's own arithmetic
// (roster_check, expr_peak). Nothing here re-states a magnitude, a rate or a bound.
//
// Content is one flat value with fixed-capacity arrays and no pointers into itself
// except the name strings, which are re-pointed every frame by content_sync_names. That
// is what lets undo be a wholesale struct copy (Undo) instead of a per-field journal.

// FORGE_MAX_ITEMS is the roster plus the headroom an authoring session appends into.
// The tool never inserts mid-array — roster order is load-bearing for seed stability —
// so growth is always at the end and a fixed cap is a real bound rather than a guess.
FORGE_MAX_ITEMS :: ship.ITEM_ROSTER_SIZE + 16
FORGE_MAX_RECIPES :: 32
FORGE_MAX_ARCHETYPES :: 24
FORGE_MAX_TRADES :: 16

// FORGE_NAME_MAX bounds an authored name. A name is edited as bytes and read as a
// string pointing back into those bytes (content_sync_names), so the buffer travels
// with the draft and a Content copy carries its own names.
FORGE_NAME_MAX :: 48

// ARCHETYPE_MAX_ITEMS is one hostile build's item list, bounded by the slots the one
// ship template has to place them in (ship_fit_first_empty_slot).
ARCHETYPE_MAX_ITEMS :: ship.SHIP_MAX_SLOTS

// Name is an authored string as the editor holds it: the bytes, how many are live, and a
// string view onto them.
//
// The view is carried rather than derived on read because a Content is copied wholesale —
// into an undo slot and back — and a proc taking a Content *by value* could only slice its
// own dying copy. content_sync_names re-points every view at the canonical Content once a
// frame, so a value copy of a Name carries a pointer that is still good.
Name :: struct {
	buf:  [FORGE_NAME_MAX]u8,
	len:  int,
	text: string,
}

name_text :: proc(n: Name) -> string {
	return n.text
}

// name_sync re-points a name's view at its own bytes. Takes a pointer, because that is the
// only way to get the address of the canonical buffer rather than of a copy.
name_sync :: proc(n: ^Name) {
	n.len = clamp(n.len, 0, FORGE_NAME_MAX - 1)
	n.text = string(n.buf[:n.len])
}

name_set :: proc(n: ^Name, text: string) {
	n.len = min(len(text), FORGE_NAME_MAX - 1)
	copy(n.buf[:n.len], text[:n.len])
	name_sync(n)
}

// Item_Draft is one row of ship_item_roster under edit. `item.fitting.name` is a view
// onto `name` and is never assigned from anywhere else.
//
// `appended` marks a row this session added past the loaded roster: those are the only
// rows an emit writes as new table lines, and the only ones a delete may remove — an
// existing row's index is a seed, so removing it would move every item after it.
Item_Draft :: struct {
	name:     Name,
	item:     ship.Roster_Item,
	appended: bool,
}

// Recipe_Pool is which of the two authored pools a recipe is written into. The split is
// the bucket model: the catalog's recipes are filtered into buckets by stage count,
// while the Port bucket is bespoke-placed and exempt from that mapping.
Recipe_Pool :: enum {
	Catalog,
	Port,
}

Recipe_Draft :: struct {
	name:     Name,
	pool:     Recipe_Pool,
	stages:   [voyage.ENCOUNTER_MAX_STAGES]voyage.Stage_Spec,
	count:    int,
	appended: bool,
}

// Archetype_Draft holds its items as **indices into Content.items** rather than as
// names, which is what makes a dangling item unauthorable: the editor picks from the
// live roster and there is no spelling to get wrong. Order is authoring — placement is
// first-empty-fit into an exposed-first template — so the list order is preserved
// exactly as edited.
Archetype_Draft :: struct {
	name:     Name,
	items:    [ARCHETYPE_MAX_ITEMS]int,
	count:    int,
	appended: bool,
}

Trade_Draft :: struct {
	name:     Name,
	gain:     voyage.Trade_Stat,
	cost:     voyage.Trade_Stat,
	appended: bool,
}

// Stock_Draft splits Stock.families' Maybe into a set plus the flag that says whether
// it is set at all: nil families means *no filter*, not *every family*, and the two read
// identically as a bit_set once every Tag is authored. Keeping the flag separate is what
// lets the editor offer "unfiltered" as its own control rather than as an empty set.
Stock_Draft :: struct {
	name:     Name,
	families: bit_set[ship.Tag],
	filtered: bool,
	depth:    int,
}

Content :: struct {
	items:           [FORGE_MAX_ITEMS]Item_Draft,
	item_count:      int,
	recipes:         [FORGE_MAX_RECIPES]Recipe_Draft,
	recipe_count:    int,
	archetypes:      [FORGE_MAX_ARCHETYPES]Archetype_Draft,
	archetype_count: int,
	trades:          [FORGE_MAX_TRADES]Trade_Draft,
	trade_count:     int,
	stocks:          [voyage.Stock_Pool]Stock_Draft,
}

// content_load reads every table the Forge edits out of core. It is the only direction
// data crosses that boundary: the tool never writes back into core, it emits source
// (emit.odin) for a human to paste.
content_load :: proc(c: ^Content) {
	c^ = {}

	for item in ship.ship_item_roster() {
		draft := &c.items[c.item_count]
		name_set(&draft.name, item.fitting.name)
		draft.item = item
		c.item_count += 1
	}

	for recipe in voyage.voyage_recipe_catalog() {
		content_load_recipe(c, recipe, .Catalog)
	}
	for recipe in voyage.voyage_port_bucket() {
		content_load_recipe(c, recipe, .Port)
	}

	for archetype in voyage.voyage_hostile_roster() {
		draft := &c.archetypes[c.archetype_count]
		name_set(&draft.name, archetype.name)
		for item_name in archetype.items {
			index, found := content_item_index(c^, item_name)
			assert(found, "a hostile archetype names an item that is not in the roster")
			draft.items[draft.count] = index
			draft.count += 1
		}
		c.archetype_count += 1
	}

	for axis in voyage.voyage_trade_roster() {
		draft := &c.trades[c.trade_count]
		name_set(&draft.name, axis.name)
		draft.gain = axis.gain
		draft.cost = axis.cost
		c.trade_count += 1
	}

	for pool in voyage.Stock_Pool {
		stock := voyage.voyage_stock_pool(pool)
		draft := &c.stocks[pool]
		name_set(&draft.name, stock.name)
		draft.families, draft.filtered = stock.families.?
		draft.depth = stock.depth
	}

	content_sync_names(c)
}

@(private = "file")
content_load_recipe :: proc(c: ^Content, recipe: voyage.Recipe, pool: Recipe_Pool) {
	draft := &c.recipes[c.recipe_count]
	name_set(&draft.name, recipe.name)
	draft.pool = pool
	draft.count = len(recipe.stages)
	for spec, i in recipe.stages {
		draft.stages[i] = spec
	}
	c.recipe_count += 1
}

// content_sync_names re-points every authored name at its own draft's byte buffer.
// A Content is copied wholesale — into an undo slot, back out of one — and a copy's
// string headers still address the buffers of whatever Content they were made from, so
// the strings are re-derived from the bytes rather than trusted after any copy. Called
// once per frame, which makes "the name is the buffer" true by construction rather than
// by every edit site remembering.
content_sync_names :: proc(c: ^Content) {
	for i in 0 ..< c.item_count {
		name_sync(&c.items[i].name)
		c.items[i].item.fitting.name = name_text(c.items[i].name)
	}
	for i in 0 ..< c.recipe_count {
		name_sync(&c.recipes[i].name)
	}
	for i in 0 ..< c.archetype_count {
		name_sync(&c.archetypes[i].name)
	}
	for i in 0 ..< c.trade_count {
		name_sync(&c.trades[i].name)
	}
	for pool in voyage.Stock_Pool {
		name_sync(&c.stocks[pool].name)
	}
}

// content_item_index finds a draft item by name — the lookup an archetype's item list
// and the name-collision checks go through.
content_item_index :: proc(c: Content, name: string) -> (index: int, ok: bool) {
	for i in 0 ..< c.item_count {
		if name_text(c.items[i].name) == name {
			return i, true
		}
	}
	return 0, false
}

// content_name_collides reports whether `name` is already taken by something an item may
// not share a name with: another roster item, or a trade axis. A Trade is not a thing you
// install, so the two tables share one namespace.
content_name_collides :: proc(c: Content, name: string, except_item: int) -> bool {
	for i in 0 ..< c.item_count {
		if i != except_item && name_text(c.items[i].name) == name {
			return true
		}
	}
	for i in 0 ..< c.trade_count {
		if name_text(c.trades[i].name) == name {
			return true
		}
	}
	return false
}

// content_append_item adds a row at the **end** of the roster and returns its index.
// Appending is the only growth the roster admits: shop baking and the Offer draw index
// into it, so a mid-array insert would silently re-deal every existing seed.
content_append_item :: proc(c: ^Content) -> (index: int, ok: bool) {
	if c.item_count >= FORGE_MAX_ITEMS {
		return 0, false
	}
	index = c.item_count
	draft := &c.items[index]
	draft^ = Item_Draft{appended = true}
	name_set(&draft.name, "New Item")
	draft.item = ship.roster_item(.Splash, name_text(draft.name), .Small, ship.WEIGHT_DEFAULT[.Small], {.Artifact}, {ship.effect_phase_contribution(ship.expr_const(1))})
	c.item_count += 1
	content_sync_names(c)
	return index, true
}

content_append_recipe :: proc(c: ^Content, pool: Recipe_Pool) -> (index: int, ok: bool) {
	if c.recipe_count >= FORGE_MAX_RECIPES {
		return 0, false
	}
	index = c.recipe_count
	draft := &c.recipes[index]
	draft^ = Recipe_Draft{pool = pool, appended = true, count = 1}
	name_set(&draft.name, "New Recipe")
	draft.stages[0] = voyage.Stage_Spec{kind = .Fight}
	c.recipe_count += 1
	return index, true
}

content_append_archetype :: proc(c: ^Content) -> (index: int, ok: bool) {
	if c.archetype_count >= FORGE_MAX_ARCHETYPES {
		return 0, false
	}
	index = c.archetype_count
	draft := &c.archetypes[index]
	draft^ = Archetype_Draft{appended = true}
	name_set(&draft.name, "New Archetype")
	c.archetype_count += 1
	return index, true
}

content_append_trade :: proc(c: ^Content) -> (index: int, ok: bool) {
	if c.trade_count >= FORGE_MAX_TRADES {
		return 0, false
	}
	index = c.trade_count
	draft := &c.trades[index]
	draft^ = Trade_Draft{appended = true, gain = .Hull, cost = .Max_Hull}
	name_set(&draft.name, "New Trade")
	c.trade_count += 1
	return index, true
}

// content_recipe returns a draft as the voyage.Recipe core reads, borrowing the draft's
// own stage array. The result lives exactly as long as the draft it points at, which is
// why every caller bakes with it inside the same frame.
content_recipe :: proc(draft: ^Recipe_Draft) -> voyage.Recipe {
	return voyage.Recipe{name = name_text(draft.name), stages = draft.stages[:draft.count]}
}

// content_stock returns a draft as the voyage.Stock core reads, folding the two fields
// back into the Maybe that carries "no filter".
content_stock :: proc(draft: Stock_Draft) -> voyage.Stock {
	stock := voyage.Stock{name = name_text(draft.name), depth = draft.depth}
	if draft.filtered {
		stock.families = draft.families
	}
	return stock
}

// UNDO_DEPTH is how far back a session can step. Each slot is a whole Content, so this
// is the one place the tool trades memory for the "no confirm dialogs for reversible
// edits" rule: every edit is reversible, so none of them asks.
UNDO_DEPTH :: 64

// Undo is a ring of whole-Content snapshots with a cursor. `pos` indexes the state
// currently live, so an undo walks back and a fresh edit truncates whatever was ahead.
Undo :: struct {
	states: [UNDO_DEPTH]Content,
	base:   int,
	len:    int,
	pos:    int,
}

@(private = "file")
undo_slot :: proc(u: ^Undo, i: int) -> int {
	return (u.base + i) % UNDO_DEPTH
}

// undo_reset seeds the history with the state the session starts from.
undo_reset :: proc(u: ^Undo, c: Content) {
	u.base, u.len, u.pos = 0, 1, 0
	u.states[0] = c
}

// undo_commit records `c` as the new current state, dropping any redo tail and, once the
// ring is full, the oldest state. Called after a frame that changed anything.
undo_commit :: proc(u: ^Undo, c: Content) {
	if u.pos + 1 >= UNDO_DEPTH {
		u.base = undo_slot(u, 1)
		u.pos -= 1
	}
	u.pos += 1
	u.len = u.pos + 1
	u.states[undo_slot(u, u.pos)] = c
}

undo_can_undo :: proc(u: Undo) -> bool {
	return u.pos > 0
}

undo_can_redo :: proc(u: Undo) -> bool {
	return u.pos + 1 < u.len
}

undo_undo :: proc(u: ^Undo) -> (c: Content, ok: bool) {
	if !undo_can_undo(u^) {
		return {}, false
	}
	u.pos -= 1
	return u.states[undo_slot(u, u.pos)], true
}

undo_redo :: proc(u: ^Undo) -> (c: Content, ok: bool) {
	if !undo_can_redo(u^) {
		return {}, false
	}
	u.pos += 1
	return u.states[undo_slot(u, u.pos)], true
}
