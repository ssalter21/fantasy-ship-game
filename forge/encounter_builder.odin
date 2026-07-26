package forge

import "core:fmt"
import "core:math/rand"
import ship "../core/ship"
import voyage "../core/voyage"
import rl "vendor:raylib"

// Surface 2: the Encounter Builder. A Recipe is a name plus an order over Stage_Specs,
// and a Stage_Spec is a kind plus a Maybe(Stock_Pool) — that is the whole authoring
// alphabet, so the builder edits exactly that: add, remove, reorder and re-kind stages,
// up to ENCOUNTER_MAX_STAGES.
//
// The catalog's conventions are documented in catalog.odin and enforced by tests. They are
// checked **as you compose** here rather than at `odin test`, so an anti-shape is a red
// line on the row you just wrote instead of a failing build twenty minutes later.
//
// The model is deliberately narrow and this builder is written against it as it stands. A
// widened Stage_Spec would mean new controls on the stage row, not a new tool.

// Builder is the surface's view state: which recipe and stage are selected, and the site
// and seed the bake preview is taken at.
Builder :: struct {
	selected: int,
	stage:    int,
	zone:     voyage.Zone,
	depth:    int,
	seed:     int,
}

builder_init :: proc() -> Builder {
	return Builder{zone = .Open_Sea, depth = 1}
}

// The recipe list's two columns, and the stage row's three. A stage row is a fixed sequence
// — its ordinal, what kind it is, which hold it sells from, and the reorder controls — so
// the columns are named once here rather than counted out at each call site.
RECIPE_NAME_W :: 180
STAGE_NUMBER_W :: 20
STAGE_KIND_W :: 124
STAGE_STOCK_W :: 150

// stage_stock_x is where the stock column starts, which both the authored control and the
// "no pool" read-out that stands in for it have to agree on.
@(private = "file")
stage_stock_x :: proc(row: rl.Rectangle) -> f32 {
	return row.x + STAGE_NUMBER_W + STAGE_KIND_W + FORGE_GAP
}

builder_draw :: proc(f: ^Forge, area: rl.Rectangle) {
	cols := forge_columns(f, area, 3)
	recipe_list(f, cols[0])

	editor, lint := forge_rows(cols[1], 0.62)
	recipe_editor(f, editor)
	lint_pane(f, lint)

	bake, emit := forge_rows(cols[2], 0.74)
	bake_pane(f, bake)
	emit_pane(f, emit, builder_emit(f))
}

builder_emit :: proc(f: ^Forge) -> string {
	if f.content.recipe_count == 0 {
		return ""
	}
	return emit_recipe(f.content.recipes[clamp(f.builder.selected, 0, f.content.recipe_count - 1)])
}

@(private = "file")
builder_recipe :: proc(f: ^Forge) -> ^Recipe_Draft {
	f.builder.selected = clamp(f.builder.selected, 0, max(f.content.recipe_count - 1, 0))
	return &f.content.recipes[f.builder.selected]
}

// recipe_list is both authored pools at once, because which pool a recipe is written into
// is the one place bucket membership is authored rather than derived — a reader has to be
// able to see the split.
@(private = "file")
recipe_list :: proc(f: ^Forge, bounds: rl.Rectangle) {
	inner := panel(bounds, fmt.tprintf("Recipes  (%d)", f.content.recipe_count))
	form := form_begin(inner)

	buttons := form_row(&form)
	catalog_w := text_width("+ catalog recipe") + 3 * FORGE_PAD
	if ui_button(&f.ui, {buttons.x, buttons.y, catalog_w, buttons.height}, "+ catalog recipe", "the zones deal from the catalog, filtered into buckets by stage count") {
		if index, ok := content_append_recipe(&f.content, .Catalog); ok {
			f.builder.selected = index
		}
	}
	if ui_button(&f.ui, {buttons.x + catalog_w + FORGE_GAP, buttons.y, text_width("+ port recipe") + 3 * FORGE_PAD, buttons.height}, "+ port recipe", "the Port bucket is bespoke-placed and exempt from the stage-count mapping") {
		if index, ok := content_append_recipe(&f.content, .Port); ok {
			f.builder.selected = index
		}
	}

	table := form_remaining(&form)
	focused := ui_focus_region(&f.ui, table, "up/down selects a recipe; the colour is the live authoring lint")
	if focused {
		if key_pressed(.DOWN) {
			f.builder.selected += 1
		}
		if key_pressed(.UP) {
			f.builder.selected -= 1
		}
		f.builder.selected = clamp(f.builder.selected, 0, max(f.content.recipe_count - 1, 0))
	}

	pool := Recipe_Pool.Catalog
	y := table.y
	for i in 0 ..< f.content.recipe_count {
		draft := f.content.recipes[i]
		if i == 0 || draft.pool != pool {
			pool = draft.pool
			draw_text(
				pool == .Port ? "port_bucket" : "recipe_catalog",
				table.x,
				y + FORGE_TEXT_DY,
				color_of(FORGE_TEXT_DIM),
			)
			y += FORGE_ROW
		}
		row := rl.Rectangle{table.x, y, table.width, FORGE_FIELD_H}
		if y > table.y + table.height - FORGE_ROW {
			break
		}
		if i == f.builder.selected {
			rl.DrawRectangleRec(row, color_of(FORGE_PANEL_ALT))
		}
		if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(), row) {
			f.builder.selected = i
		}
		finding := recipe_lint(f.content, i)
		rl.DrawRectangleRec({row.x, row.y + 2, 3, row.height - 4}, color_of(finding == .None ? FORGE_PASS : FORGE_FAULT))
		draw_text_clipped(name_text(draft.name), row.x + FORGE_PAD, row.y + FORGE_TEXT_DY, RECIPE_NAME_W - FORGE_PAD, color_of(i == f.builder.selected ? FORGE_TEXT : FORGE_TEXT_DIM))
		draw_text_clipped(shape_text(draft), row.x + RECIPE_NAME_W, row.y + FORGE_TEXT_DY, row.width - RECIPE_NAME_W, color_of(FORGE_TEXT_DIM))
		y += FORGE_ROW
	}
}

// recipe_editor is the stage list, which is the whole of what a recipe authors.
@(private = "file")
recipe_editor :: proc(f: ^Forge, bounds: rl.Rectangle) {
	if f.content.recipe_count == 0 {
		panel(bounds, "Recipe")
		return
	}
	draft := builder_recipe(f)
	inner := panel(bounds, "Recipe")
	form := form_begin(inner)

	ui_name(&f.ui, form_field(&form, "name"), &draft.name, "a recipe's identity is its shape plus its name")
	pool := int(draft.pool)
	pool_options, pool_count := enum_options(Recipe_Pool)
	if ui_enum(&f.ui, form_field(&form, "pool", FORGE_ENUM_W), pool_options, &pool, pool_count, "the catalog is filtered into buckets by stage count; the Port bucket is placed bespoke") {
		draft.pool = Recipe_Pool(pool)
	}
	form_derived(
		&form,
		"bucket",
		FORGE_ENUM_W,
		draft.pool == .Port ? "Port" : fmt.tprintf("%v", bucket_of(draft.count)),
		draft.pool == .Port ? "bespoke-placed, exempt from the stage-count mapping" : "derived from the stage count; there is no bucket field",
	)
	form_derived(
		&form,
		"reveals",
		FORGE_ENUM_W,
		draft.count > 0 && voyage.voyage_stage_kind_reveals(draft.stages[0].kind) ? "yes" : "no",
		"an encounter reveals iff its first stage reveals",
	)

	form_line(&form, "stages")
	f.builder.stage = clamp(f.builder.stage, 0, max(draft.count - 1, 0))
	for i in 0 ..< draft.count {
		row := form_row(&form)
		if i == f.builder.stage {
			rl.DrawRectangleRec({row.x - 2, row.y - 1, row.width + 4, row.height + 2}, color_of(FORGE_PANEL_ALT))
		}
		draw_mono(fmt.tprintf("%d", i + 1), row.x, row.y + FORGE_TEXT_DY, color_of(FORGE_TEXT_DIM))

		kind_options, kind_count := enum_options(voyage.Stage_Kind)
		kind := int(draft.stages[i].kind)
		if ui_enum(&f.ui, {row.x + STAGE_NUMBER_W, row.y, STAGE_KIND_W, row.height}, kind_options, &kind, kind_count, "the closed primitive alphabet; a sixth value is an ADR-sized decision") {
			draft.stages[i].kind = voyage.Stage_Kind(kind)
			// A pool is authored iff the primitive is a Shop, asserted both directions in
			// voyage_bake_stage — so a kind change clears or supplies it here.
			draft.stages[i].stock = draft.stages[i].kind == .Shop ? voyage.Stock_Pool.Chandlery : nil
			f.builder.stage = i
		}

		if pool_value, is_shop := draft.stages[i].stock.?; is_shop {
			stock_options, stock_count := enum_options(voyage.Stock_Pool)
			stock := int(pool_value)
			if ui_enum(&f.ui, {stage_stock_x(row), row.y, STAGE_STOCK_W, row.height}, stock_options, &stock, stock_count, "which hold this shop sells from") {
				draft.stages[i].stock = voyage.Stock_Pool(stock)
			}
		} else {
			// No reason beside the box: this is a table row, and the reorder controls own the
			// space a reason would run into. The rule is on the hint and in the lint panel.
			ui_derived({stage_stock_x(row), row.y, STAGE_STOCK_W, row.height}, "no pool", "", row.x + row.width)
		}

		switch ui_reorder(
			&f.ui,
			{stage_stock_x(row) + STAGE_STOCK_W + FORGE_GAP, row.y, REORDER_WIDTH, row.height},
			i,
			draft.count,
			"reorder: costs are authored ahead of the boons they pay for",
			"reorder: costs are authored ahead of the boons they pay for",
		) {
		case .None:
		case .Up:
			draft.stages[i], draft.stages[i - 1] = draft.stages[i - 1], draft.stages[i]
			f.builder.stage = i - 1
		case .Down:
			draft.stages[i], draft.stages[i + 1] = draft.stages[i + 1], draft.stages[i]
			f.builder.stage = i + 1
		case .Remove:
			for k in i ..< draft.count - 1 {
				draft.stages[k] = draft.stages[k + 1]
			}
			draft.count -= 1
		}
	}

	if draft.count < voyage.ENCOUNTER_MAX_STAGES {
		row := form_row(&form)
		if ui_button(&f.ui, {row.x + STAGE_NUMBER_W, row.y, STAGE_KIND_W, row.height}, "+ stage", "an encounter holds at most ENCOUNTER_MAX_STAGES stages") {
			draft.stages[draft.count] = voyage.Stage_Spec{kind = .Reward}
			draft.count += 1
		}
	}
}

// lint_pane reports the catalog's authoring conventions against the live tables, one
// finding at a time in the order the conventions are written.
@(private = "file")
lint_pane :: proc(f: ^Forge, bounds: rl.Rectangle) {
	inner := panel(bounds, "Authoring lint")
	form := form_begin(inner)
	if f.content.recipe_count == 0 {
		return
	}
	finding := recipe_lint(f.content, f.builder.selected)
	if finding == .None {
		form_note(&form, "clean: this recipe satisfies every convention the catalog's tests check", FORGE_PASS)
	} else {
		form_note(&form, LINT_REASON[finding], FORGE_FAULT)
	}

	form_line(&form, "the conventions")
	form_note(&form, "costs precede boons - Fight and Trade can be declined, and a halt is an exit", FORGE_TEXT_DIM)
	form_note(&form, "one recipe per stage-kind sequence - a differing pool does not rescue a collision", FORGE_TEXT_DIM)
	form_note(&form, "only the Port bucket opens on a Shop - Shop is the revealing primitive", FORGE_TEXT_DIM)
	form_note(&form, fmt.tprintf("the 1-stage bucket is capped at %d, permanently", ONE_STAGE_BUCKET_CAP), FORGE_TEXT_DIM)
}

// Lint is one authoring finding against the catalog's conventions, `.None` when a recipe
// satisfies all of them.
Lint :: enum {
	None,
	Unnamed,
	Duplicate_Name,
	No_Stages,
	Shop_Without_A_Pool,
	Pool_Without_A_Shop,
	Cost_Behind_A_Boon,
	Duplicate_Shape,
	Catalog_Opens_On_A_Shop,
	One_Stage_Bucket_Full,
}

@(rodata)
LINT_REASON := [Lint]string {
	.None                    = "",
	.Unnamed                 = "a name is not decoration: a recipe's identity is its shape plus its name",
	.Duplicate_Name          = "another recipe already carries this name",
	.No_Stages               = "a recipe must author at least one stage",
	.Shop_Without_A_Pool     = "a Shop spec names the hold it sells from; voyage_bake_stage asserts it",
	.Pool_Without_A_Shop     = "only a Shop authors a stock pool: no other primitive has one to draw from",
	.Cost_Behind_A_Boon      = "a declinable cost behind a boon is a free escape from paying for it",
	.Duplicate_Shape         = "another recipe authors the same stage kinds: nothing downstream can tell them apart",
	.Catalog_Opens_On_A_Shop = "only the Port bucket opens on a Shop - a merchant earns its Shop by putting a stage in front of it",
	.One_Stage_Bucket_Full   = "the 1-stage bucket is capped: a further entry could only duplicate a shape",
}

// ONE_STAGE_BUCKET_CAP is the permanent size of the Coastal bucket: one shape per
// primitive, less the [Shop] the Port bucket reserves.
ONE_STAGE_BUCKET_CAP :: len(voyage.Stage_Kind) - 1

// recipe_lint checks one recipe against every convention, reporting the first finding.
//
// **Shape means the kind sequence and nothing else.** A differing stock pool does not
// rescue a collision: a baked Stage_Shop carries its cards but not the pool that dealt
// them, so two recipes with the same kinds are one indistinguishable encounter on the map,
// in a Ghost_Snapshot, and to the recipe recovery that matches on kinds. That is stricter
// than authoring wants and is the rule the catalog's own test enforces.
recipe_lint :: proc(c: Content, index: int) -> Lint {
	draft := c.recipes[index]

	if draft.name.len == 0 {
		return .Unnamed
	}
	if draft.count <= 0 {
		return .No_Stages
	}
	for i in 0 ..< c.recipe_count {
		if i != index && name_text(c.recipes[i].name) == name_text(draft.name) {
			return .Duplicate_Name
		}
	}

	for i in 0 ..< draft.count {
		_, authored := draft.stages[i].stock.?
		if draft.stages[i].kind == .Shop && !authored {
			return .Shop_Without_A_Pool
		}
		if draft.stages[i].kind != .Shop && authored {
			return .Pool_Without_A_Shop
		}
	}

	seen_boon := false
	for i in 0 ..< draft.count {
		if stage_kind_is_cost(draft.stages[i].kind) {
			if seen_boon {
				return .Cost_Behind_A_Boon
			}
			continue
		}
		seen_boon = true
	}

	if draft.pool == .Catalog && draft.stages[0].kind == .Shop {
		return .Catalog_Opens_On_A_Shop
	}

	for i in 0 ..< c.recipe_count {
		other := c.recipes[i]
		if i == index || other.pool != draft.pool || other.count != draft.count {
			continue
		}
		same := true
		for k in 0 ..< draft.count {
			if other.stages[k].kind != draft.stages[k].kind {
				same = false
				break
			}
		}
		if same {
			return .Duplicate_Shape
		}
	}

	if draft.pool == .Catalog && draft.count == 1 {
		one_stage := 0
		for i in 0 ..< c.recipe_count {
			if c.recipes[i].pool == .Catalog && c.recipes[i].count == 1 {
				one_stage += 1
			}
		}
		if one_stage > ONE_STAGE_BUCKET_CAP {
			return .One_Stage_Bucket_Full
		}
	}
	return .None
}

// stage_kind_is_cost partitions the alphabet the way the convention does: a cost is a
// stage that both costs something and can be **declined**, so its halt is a free exit from
// everything downstream. Shop is a boon despite spending cargo — it never halts.
stage_kind_is_cost :: proc(kind: voyage.Stage_Kind) -> bool {
	switch kind {
	case .Fight, .Trade:
		return true
	case .Offer, .Shop, .Reward:
		return false
	}
	unreachable()
}

// bucket_of is the zone a stage count files a catalog recipe into. Derived and never
// authored, which is why a recipe cannot be filed in the wrong bucket — it isn't filed.
bucket_of :: proc(stage_count: int) -> voyage.Zone {
	switch stage_count {
	case 1:
		return .Coastal
	case 2:
		return .Open_Sea
	}
	return .Deep
}

shape_text :: proc(draft: Recipe_Draft) -> string {
	text := "["
	for i in 0 ..< draft.count {
		if i > 0 {
			text = fmt.tprintf("%s, ", text)
		}
		text = fmt.tprintf("%s%v", text, draft.stages[i].kind)
		if pool, is_shop := draft.stages[i].stock.?; is_shop {
			text = fmt.tprintf("%s:%v", text, pool)
		}
	}
	return fmt.tprintf("%s]", text)
}

// bake_pane runs the recipe through voyage_encounter_from_recipe at a chosen site and
// seed and renders what each stage actually baked. This is where "is this encounter any
// good at this depth" gets answered — re-roll the seed to see the spread.
@(private = "file")
bake_pane :: proc(f: ^Forge, bounds: rl.Rectangle) {
	inner := panel(bounds, "Bake preview")
	form := form_begin(inner)
	if f.content.recipe_count == 0 {
		return
	}
	draft := builder_recipe(f)

	// One row: where the bake is taken, and the seed it is taken with. Each caption is
	// measured rather than allotted, so the row packs to whatever the face makes it.
	site_row := form_row(&form)
	zone_options, zone_count := enum_options(voyage.Zone)
	zone := int(f.builder.zone)
	x := site_row.x
	if ui_enum(&f.ui, {x, site_row.y, FORGE_ENUM_W, site_row.height}, zone_options, &zone, zone_count, "which stakes band the node sits in") {
		f.builder.zone = voyage.Zone(zone)
	}
	x += FORGE_ENUM_W + FORGE_PAD

	draw_text("depth", x, site_row.y + FORGE_TEXT_DY, color_of(FORGE_TEXT_DIM))
	x += text_width("depth") + FORGE_GAP
	ui_value(&f.ui, {x, site_row.y, FORGE_VALUE_W - 2 * FORGE_PAD, site_row.height}, &f.builder.depth, 0, voyage.DEPTH_STEPS, "normalized depth-within-zone")
	x += FORGE_VALUE_W - 2 * FORGE_PAD + FORGE_PAD

	draw_text("seed", x, site_row.y + FORGE_TEXT_DY, color_of(FORGE_TEXT_DIM))
	x += text_width("seed") + FORGE_GAP
	ui_value(&f.ui, {x, site_row.y, FORGE_VALUE_W, site_row.height}, &f.builder.seed, 0, 9999, "re-roll to see the spread the site produces")

	site := voyage.Scaling_Site{zone = f.builder.zone, depth = f.builder.depth}
	if draft.count == 0 {
		return
	}

	// The bake allocates a layout per Fight stage. That is frame scratch, reclaimed at the
	// frame boundary (forge_frame), so nothing here destroys the encounter it drew.
	state := rand.create(u64(f.builder.seed))
	encounter := voyage.voyage_encounter_from_recipe(content_recipe(draft), site, rand.default_random_generator(&state))

	for i in 0 ..< encounter.count {
		form_line(&form, fmt.tprintf("stage %d - %v", i + 1, voyage.voyage_stage_kind(encounter.stages[i])))
		bake_stage(&form, encounter.stages[i], site)
	}
}

@(private = "file")
bake_stage :: proc(form: ^Form, stage: voyage.Stage, site: voyage.Scaling_Site) {
	switch baked in stage {
	case voyage.Stage_Fight:
		opponent := baked.opponent
		form_note(
			form,
			fmt.tprintf(
				"hull %d, speed %d, output scaled to %d%%",
				opponent.hull,
				ship.ship_effective_speed(&opponent),
				voyage.voyage_fight_opponent_power(site),
			),
			FORGE_TEXT,
		)
		for layout_slot in opponent.layout {
			fitting, installed := layout_slot.fitting.?
			if !installed {
				continue
			}
			form_note_mono(
				form,
				fmt.tprintf(
					"  %-10s %-20s %v  fire %d  cargo %d",
					layout_slot.slot.name,
					fitting.name,
					layout_slot.slot.base_visibility,
					fitting_output(fitting),
					fitting.cargo_held,
				),
				FORGE_TEXT_DIM,
			)
		}
	case voyage.Stage_Offer:
		form_note(form, fmt.tprintf("band %v", voyage.voyage_offer_tier_band(site)), FORGE_TEXT_DIM)
		for option in baked.options {
			form_note(form, fmt.tprintf("  %s - showcase %d", option.name, fitting_output(option)), FORGE_TEXT)
		}
	case voyage.Stage_Trade:
		form_note(
			form,
			fmt.tprintf("%s: gain %d %v for %d %v", baked.name, baked.gain.amount, baked.gain.stat, baked.cost.amount, baked.cost.stat),
			FORGE_TEXT,
		)
	case voyage.Stage_Shop:
		form_note(
			form,
			fmt.tprintf("%d cards - %d on the shelf, %d in reserve", baked.count, min(baked.count, voyage.SHOP_SHELF_SIZE), max(baked.count - voyage.SHOP_SHELF_SIZE, 0)),
			FORGE_TEXT,
		)
		for i in 0 ..< baked.count {
			form_note_mono(
				form,
				fmt.tprintf(
					"  %s %s (%v, %d cargo)",
					i < voyage.SHOP_SHELF_SIZE ? "shelf " : "hold  ",
					baked.stock[i].fitting.name,
					baked.stock[i].tier,
					ship.ship_item_cost(baked.stock[i].tier),
				),
				i < voyage.SHOP_SHELF_SIZE ? FORGE_TEXT : FORGE_TEXT_DIM,
			)
		}
	case voyage.Stage_Reward:
		form_note(form, fmt.tprintf("%d cargo", baked.cargo), FORGE_TEXT)
	}
}

// fitting_output is a fitting's Fire contribution as an item card reads it — the showcase
// magnitude of every Phase_Contribution effect, which is what carries a Fight site's
// scaling.
@(private = "file")
fitting_output :: proc(fitting: ship.Fitting) -> int {
	total := 0
	for i in 0 ..< fitting.effect_count {
		if fitting.effects[i].verb == .Phase_Contribution {
			total += ship.effect_showcase_magnitude(fitting.effects[i])
		}
	}
	return total
}
