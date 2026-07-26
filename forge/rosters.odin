package forge

import "core:fmt"
import combat "../core/combat"
import ship "../core/ship"
import voyage "../core/voyage"
import rl "vendor:raylib"

// The other content rosters: hostile archetypes, trade axes and stock pools. The two
// surfaces lean on all three, so balancing items and encounters without them is half a
// job.

Roster_Tab :: enum {
	Archetypes,
	Trade_Axes,
	Stock_Pools,
}

Roster_View :: struct {
	tab:       Roster_Tab,
	archetype: int,
	trade:     int,
	stock:     int,
}

rosters_draw :: proc(f: ^Forge, area: rl.Rectangle) {
	tabs := rl.Rectangle{area.x, area.y, area.width, FORGE_ROW}
	x := area.x + FORGE_PAD
	for tab in Roster_Tab {
		label := fmt.tprintf("%v", tab)
		width := text_width(label) + 2 * FORGE_PAD
		if ui_button(&f.ui, {x, tabs.y + 1, width, FORGE_ROW - 2}, label, "the content rosters the two surfaces lean on") {
			f.rosters.tab = tab
		}
		if tab == f.rosters.tab {
			rl.DrawRectangleRec({x, tabs.y + FORGE_ROW - 3, width, 2}, color_of(FORGE_ACCENT))
		}
		x += width + FORGE_GAP
	}

	body := rl.Rectangle{area.x, area.y + FORGE_ROW, area.width, area.height - FORGE_ROW}
	switch f.rosters.tab {
	case .Archetypes:
		archetypes_draw(f, body)
	case .Trade_Axes:
		trades_draw(f, body)
	case .Stock_Pools:
		stocks_draw(f, body)
	}
}

rosters_emit :: proc(f: ^Forge) -> string {
	switch f.rosters.tab {
	case .Archetypes:
		if f.content.archetype_count == 0 {
			return ""
		}
		return emit_archetype(f.content, f.content.archetypes[clamp(f.rosters.archetype, 0, f.content.archetype_count - 1)])
	case .Trade_Axes:
		if f.content.trade_count == 0 {
			return ""
		}
		return emit_trade(f.content.trades[clamp(f.rosters.trade, 0, f.content.trade_count - 1)])
	case .Stock_Pools:
		pool := voyage.Stock_Pool(clamp(f.rosters.stock, 0, len(voyage.Stock_Pool) - 1))
		return emit_stock(pool, f.content.stocks[pool])
	}
	unreachable()
}

// archetypes_draw edits a hostile build as what it is: an **ordered** list of roster item
// names. Order is authoring — placement is first-empty-fit into a template whose slots are
// exposed-first within each size — so the resolved placement is rendered beside the list
// rather than left for the author to work out.
@(private = "file")
archetypes_draw :: proc(f: ^Forge, area: rl.Rectangle) {
	cols := forge_columns(f, area, 3)

	list := panel(cols[0], fmt.tprintf("Hostile archetypes  (%d)", f.content.archetype_count))
	form := form_begin(list)
	if ui_button(&f.ui, form_row(&form), "+ append archetype", "an archetype is character; the site supplies the power") {
		if index, ok := content_append_archetype(&f.content); ok {
			f.rosters.archetype = index
		}
	}
	for i in 0 ..< f.content.archetype_count {
		row := form_row(&form)
		if i == f.rosters.archetype {
			rl.DrawRectangleRec(row, color_of(FORGE_PANEL_ALT))
		}
		if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(), row) {
			f.rosters.archetype = i
		}
		draft := f.content.archetypes[i]
		draw_text(name_text(draft.name), row.x + 4, row.y + 4, color_of(i == f.rosters.archetype ? FORGE_TEXT : FORGE_TEXT_DIM))
		draw_mono_right(fmt.tprintf("%d items", draft.count), row.x + row.width - 4, row.y + 4, color_of(FORGE_TEXT_DIM))
	}

	if f.content.archetype_count == 0 {
		return
	}
	draft := &f.content.archetypes[clamp(f.rosters.archetype, 0, f.content.archetype_count - 1)]

	editor := panel(cols[1], "Build")
	form = form_begin(editor)
	ui_name(&f.ui, form_field(&form, "name"), &draft.name, "the archetype's name, carried into the Fight it bakes")
	form_line(&form, "items, in placement order")

	for i in 0 ..< draft.count {
		row := form_row(&form)
		options, count := item_name_options(f.content)
		pick := draft.items[i]
		if ui_enum(&f.ui, {row.x, row.y, row.width - REORDER_WIDTH - FORGE_GAP, row.height}, options, &pick, count, "picked from the live roster, so a dangling item name is unauthorable") {
			draft.items[i] = pick
		}
		switch ui_reorder(
			&f.ui,
			{row.x + row.width - REORDER_WIDTH, row.y, REORDER_WIDTH, row.height},
			i,
			draft.count,
			"order is authoring: an item placed earlier lands on deck",
			"order is authoring: an item placed later falls back to the concealed hold",
		) {
		case .None:
		case .Up:
			draft.items[i], draft.items[i - 1] = draft.items[i - 1], draft.items[i]
		case .Down:
			draft.items[i], draft.items[i + 1] = draft.items[i + 1], draft.items[i]
		case .Remove:
			for k in i ..< draft.count - 1 {
				draft.items[k] = draft.items[k + 1]
			}
			draft.count -= 1
		}
	}
	if draft.count < ARCHETYPE_MAX_ITEMS {
		if ui_button(&f.ui, form_row(&form), "+ item", "the template has to have a free slot of the item's size to place it") {
			draft.items[draft.count] = 0
			draft.count += 1
		}
	}

	placement_pane(f, cols[2], draft^)
}

// placement_pane resolves the build the way generation does — first-empty-fit into the one
// ship template — and then fights it, because the roster's authoring rule has two walls
// and both of them are about how a fight with a starting player actually goes.
@(private = "file")
placement_pane :: proc(f: ^Forge, bounds: rl.Rectangle, draft: Archetype_Draft) {
	inner := panel(bounds, "Resolved placement and both walls")
	form := form_begin(inner)

	names := make([]string, draft.count)
	for i in 0 ..< draft.count {
		names[i] = name_text(f.content.items[draft.items[i]].name)
	}
	archetype := voyage.Hostile_Archetype{name = name_text(draft.name), items = names}

	// Entries are authored at Open Sea weight, so the placement is shown at the site the
	// roster is written against.
	site := voyage.Scaling_Site{zone = .Open_Sea, depth = 0}
	layout := ship.ship_template_layout()
	if !voyage.voyage_fit_hostile_loadout(layout, archetype, voyage.voyage_fight_opponent_power(site)) {
		form_note(&form, "this build asks for more slots of a size than the template has", FORGE_FAULT)
		return
	}
	hostile := voyage.voyage_make_opponent_ship(site)
	hostile.layout = layout

	for layout_slot in layout {
		fitting, installed := layout_slot.fitting.?
		if !installed {
			continue
		}
		form_note(
			&form,
			fmt.tprintf("%-10s %-10v %s", layout_slot.slot.name, layout_slot.slot.base_visibility, fitting.name),
			layout_slot.slot.base_visibility == .Exposed ? FORGE_TEXT : FORGE_TEXT_DIM,
		)
	}
	form_note(
		&form,
		fmt.tprintf("hull %d, weight %d, speed %d", hostile.hull, ship.ship_weight(hostile), ship.ship_effective_speed(&hostile)),
		FORGE_TEXT,
	)

	form_line(&form, "the two walls, fought at Coastal")
	rounds, sank_the_player, scratched, ended := archetype_walls(archetype)
	form_note(
		&form,
		fmt.tprintf("the fight resolves in %d rounds; the escape gate opens at %d", rounds, combat.BASELINE_ROUND_COUNT),
		rounds >= combat.BASELINE_ROUND_COUNT ? FORGE_PASS : FORGE_FAULT,
	)
	if !scratched {
		form_note(&form, "floor: a starting player cannot scratch this build - a fight with no risk", FORGE_FAULT)
	}
	if sank_the_player && rounds < combat.BASELINE_ROUND_COUNT {
		form_note(&form, "ceiling: this build sinks a starting ship before Break Off comes off the bench", FORGE_FAULT)
	}
	if !ended {
		form_note(&form, "this build and a starting player cannot finish a fight at Coastal", FORGE_FAULT)
	}
}

// ARCHETYPE_WALL_ROUND_CAP is where a fight has stopped being one. It bounds the walls
// preview's loop, which is a real battle rather than a formula.
ARCHETYPE_WALL_ROUND_CAP :: 30

// It allocates two layouts and a round's events from context.allocator and frees none of
// them: a frame scopes that to the temp allocator it reclaims at the frame boundary, and a
// caller outside a frame scopes its own.
//
// archetype_walls fights the build against a starting ship at Coastal — the state the
// player is actually in when they meet their first hostile, and the state the roster's
// band is authored against. Both sides Hold, so what it measures is the damage the two
// loadouts produce rather than how escape was played.
archetype_walls :: proc(archetype: voyage.Hostile_Archetype) -> (rounds: int, sank_the_player: bool, scratched: bool, ended: bool) {
	site := voyage.Scaling_Site{zone = .Coastal, depth = 0}
	player := ship.ship_starting_ship()
	hostile := voyage.voyage_make_opponent_ship(site)
	hostile.layout = ship.ship_template_layout()
	if !voyage.voyage_fit_hostile_loadout(hostile.layout, archetype, voyage.voyage_fight_opponent_power(site)) {
		return 0, false, false, false
	}
	full_hull := hostile.hull

	battle := combat.combat_battle_create(&player, &hostile)
	events: [dynamic]combat.Event
	hold := [combat.Side]Maybe(combat.Command) {
		.A = combat.Command(combat.Command_Hold{}),
		.B = combat.Command(combat.Command_Hold{}),
	}
	for !battle.ended && battle.round < ARCHETYPE_WALL_ROUND_CAP {
		combat.combat_resolve_round(&battle, hold, &events)
	}
	return battle.round, player.hull <= 0, hostile.hull < full_hull, battle.ended
}

// item_name_options is the live roster as a combo list, which is what makes a dangling
// item name unauthorable: an archetype picks an index, never a spelling.
@(private = "file")
item_name_options :: proc(c: Content) -> (options: string, count: int) {
	text := ""
	for i in 0 ..< c.item_count {
		if i > 0 {
			text = fmt.tprintf("%s;%s", text, name_text(c.items[i].name))
			continue
		}
		text = name_text(c.items[i].name)
	}
	return text, c.item_count
}

// trades_draw edits the Trade roster. An axis carries no magnitudes — those are the site's
// swing — so an axis is authored purely as "what for what".
@(private = "file")
trades_draw :: proc(f: ^Forge, area: rl.Rectangle) {
	cols := forge_columns(f, area, 2)

	list := panel(cols[0], fmt.tprintf("Trade axes  (%d)", f.content.trade_count))
	form := form_begin(list)
	if ui_button(&f.ui, form_row(&form), "+ append axis", "a trade is authored as a pair of stats; the zone decides how big") {
		if index, ok := content_append_trade(&f.content); ok {
			f.rosters.trade = index
		}
	}
	for i in 0 ..< f.content.trade_count {
		row := form_row(&form)
		if i == f.rosters.trade {
			rl.DrawRectangleRec(row, color_of(FORGE_PANEL_ALT))
		}
		if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(), row) {
			f.rosters.trade = i
		}
		draft := f.content.trades[i]
		fault := trade_fault(f.content, i)
		rl.DrawRectangleRec({row.x, row.y + 2, 3, row.height - 4}, color_of(fault == .None ? FORGE_PASS : FORGE_FAULT))
		draw_text(
			fmt.tprintf("%s - gain %v for %v", name_text(draft.name), draft.gain, draft.cost),
			row.x + 8,
			row.y + 4,
			color_of(i == f.rosters.trade ? FORGE_TEXT : FORGE_TEXT_DIM),
		)
	}

	if f.content.trade_count == 0 {
		return
	}
	draft := &f.content.trades[clamp(f.rosters.trade, 0, f.content.trade_count - 1)]

	editor := panel(cols[1], "Axis")
	form = form_begin(editor)
	ui_name(&f.ui, form_field(&form, "name"), &draft.name, "a Trade is not a thing you install: names must not collide with the item roster")

	stat_options, stat_count := enum_options(voyage.Trade_Stat)
	gain := int(draft.gain)
	if ui_enum(&f.ui, form_field(&form, "gain", 120), stat_options, &gain, stat_count, "the stat this bargain pays out") {
		draft.gain = voyage.Trade_Stat(gain)
	}
	cost := int(draft.cost)
	if ui_enum(&f.ui, form_field(&form, "cost", 120), stat_options, &cost, stat_count, "the stat it takes; Hull may never sit here") {
		draft.cost = voyage.Trade_Stat(cost)
	}

	form_line(&form, "swing by zone (voyage_trade_swing)")
	for zone in voyage.Zone {
		form_note(
			&form,
			fmt.tprintf(
				"%-10v gain %d %v for %d %v",
				zone,
				voyage.voyage_trade_swing(zone, draft.gain),
				draft.gain,
				voyage.voyage_trade_swing(zone, draft.cost),
				draft.cost,
			),
			FORGE_TEXT_DIM,
		)
	}

	form_line(&form, "guardrails")
	switch trade_fault(f.content, f.rosters.trade) {
	case .None:
		form_note(&form, "clean", FORGE_PASS)
	case .Unnamed:
		form_note(&form, "a trade needs a name; presentation says which bargain this is from it", FORGE_FAULT)
	case .Name_Collides:
		form_note(&form, "that name is taken by a roster item - a Trade is not a thing you install", FORGE_FAULT)
	case .Hull_Is_Gain_Only:
		form_note(&form, "Hull is gain-only: nothing else in the game heals, and a trade that damages you is a Fight without the fight", FORGE_FAULT)
	case .Same_Stat_Both_Sides:
		form_note(&form, "both sides name the same stat, so the trade nets to nothing", FORGE_FAULT)
	}
	form_note(&form, "Speed is not tradeable: it is a derived read-out of weight, so it is absent from Trade_Stat", FORGE_TEXT_DIM)
}

// Trade_Fault is what one authored trade axis got wrong.
Trade_Fault :: enum {
	None,
	Unnamed,
	Name_Collides,
	Hull_Is_Gain_Only,
	Same_Stat_Both_Sides,
}

trade_fault :: proc(c: Content, index: int) -> Trade_Fault {
	draft := c.trades[index]
	if draft.name.len == 0 {
		return .Unnamed
	}
	if _, taken := content_item_index(c, name_text(draft.name)); taken {
		return .Name_Collides
	}
	if draft.cost == .Hull {
		return .Hull_Is_Gain_Only
	}
	if draft.gain == draft.cost {
		return .Same_Stat_Both_Sides
	}
	return .None
}

// stocks_draw edits the five authored holds. The Stock_Pool set itself is closed — a pool
// reaches a node by being *named by a recipe*, so adding one is a catalog edit as well as
// a table edit — and the editor edits what each one is made of.
@(private = "file")
stocks_draw :: proc(f: ^Forge, area: rl.Rectangle) {
	cols := forge_columns(f, area, 2)

	list := panel(cols[0], "Stock pools")
	form := form_begin(list)
	for pool in voyage.Stock_Pool {
		row := form_row(&form)
		if int(pool) == f.rosters.stock {
			rl.DrawRectangleRec(row, color_of(FORGE_PANEL_ALT))
		}
		if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(), row) {
			f.rosters.stock = int(pool)
		}
		draft := f.content.stocks[pool]
		draw_text(name_text(draft.name), row.x + 4, row.y + 4, color_of(int(pool) == f.rosters.stock ? FORGE_TEXT : FORGE_TEXT_DIM))
		draw_mono_right(fmt.tprintf("depth %d", draft.depth), row.x + row.width - 4, row.y + 4, color_of(FORGE_TEXT_DIM))
	}

	pool := voyage.Stock_Pool(clamp(f.rosters.stock, 0, len(voyage.Stock_Pool) - 1))
	draft := &f.content.stocks[pool]

	editor := panel(cols[1], fmt.tprintf("%v", pool))
	form = form_begin(editor)
	ui_name(&f.ui, form_field(&form, "name"), &draft.name, "what this business is called")

	filter_row := form_field(&form, "families")
	ui_check(&f.ui, {filter_row.x, filter_row.y + 2, 12, 12}, "filtered", &draft.filtered, "unfiltered means no filter, not every family: an unfiltered shop keeps stocking a sixth Tag the day one is authored")
	if draft.filtered {
		ui_tag_set(
			&f.ui,
			{filter_row.x + 90, filter_row.y, filter_row.width - 90, filter_row.height},
			&draft.families,
			"an item carrying any of the pool's families is stocked",
		)
	}

	ui_value(&f.ui, form_field(&form, "depth", 72), &draft.depth, 0, voyage.SHOP_STOCK_MAX, "how many cards deep the hold is; SHOP_STOCK_MAX caps it")

	form_line(&form, "derived")
	_, candidates := voyage.voyage_stock_candidates(content_stock(draft^))
	ui_derived(form_field(&form, "candidates", 72), fmt.tprintf("%d", candidates), "roster items this pool may stock")
	reserve := draft.depth - voyage.SHOP_SHELF_SIZE
	ui_derived(
		form_field(&form, "reserve", 72),
		fmt.tprintf("%d", reserve),
		reserve <= 0 ? "at or below the shelf: this shop can be bought out in one visit" : "cards behind the shelf, which is the only thing standing between a shop and exhaustion",
	)
	if candidates < draft.depth {
		form_note(&form, "the pool holds fewer candidates than its depth, so a shelf will come up short", FORGE_WARN)
	}
}
