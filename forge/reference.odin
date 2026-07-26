package forge

import "core:fmt"
import combat "../core/combat"
import ship "../core/ship"
import voyage "../core/voyage"
import rl "vendor:raylib"

// The ship template and the balance constants, **read-only**. They are not the Forge's to
// edit, but they belong on screen: the layout drives ship_count_peaks, so it is what every
// synergy in the roster is priced against, and the stakes ladder is what every bake reads.

// The stakes table's geometry: a label column, then one mono column per primitive's reading
// of a site. stakes_column answers where column `index` ends, so the headings and the
// numbers under them are placed by the same rule and the tier band that follows the last of
// them starts where it actually left off.
STAKES_LABEL_W :: 100
STAKES_COLUMN_W :: 7

@(private = "file")
stakes_column :: proc(x: f32, index: int) -> f32 {
	return x + STAKES_LABEL_W + f32(index + 1) * STAKES_COLUMN_W * mono_advance
}

// The trade swing table's own two columns; a swing is written as "<stat> <amount>", so its
// column is wider than the stakes table's bare numbers.
SWING_LABEL_W :: 100
SWING_COLUMN_W :: 125

reference_draw :: proc(f: ^Forge, area: rl.Rectangle) {
	cols := forge_columns(f, area, 3)
	template_pane(cols[0])
	constants_pane(cols[1])
	stakes_pane(cols[2])
}

@(private = "file")
template_pane :: proc(bounds: rl.Rectangle) {
	inner := panel(bounds, "Ship template")
	form := form_begin(inner)

	layout := ship.ship_template_layout()
	for layout_slot, index in layout {
		form_note_mono(
			&form,
			fmt.tprintf("%d  %-12s %-7v %v", index, layout_slot.slot.name, layout_slot.slot.size, layout_slot.slot.base_visibility),
			layout_slot.slot.base_visibility == .Exposed ? FORGE_TEXT : FORGE_TEXT_DIM,
		)
	}
	form_note(&form, "slots are exposed-first within each size, which is what makes loadout order authoring", FORGE_TEXT_DIM)

	form_line(&form, "pricing census (ship_count_peaks)")
	peaks := ship.ship_count_peaks()
	for tag in ship.Tag {
		reference_row(&form, fmt.tprintf("Tag %v", tag), peaks.tag[tag])
	}
	for size in ship.Slot_Size {
		reference_row(&form, fmt.tprintf("Size %v", size), peaks.size[size])
	}
	for seen in ship.Visibility {
		reference_row(&form, fmt.tprintf("Visibility %v", seen), peaks.visibility[seen])
	}
	form_note(&form, "re-sizing a hold re-prices every counting item in the roster", FORGE_TEXT_DIM)
}

@(private = "file")
constants_pane :: proc(bounds: rl.Rectangle) {
	inner := panel(bounds, "Constants")
	form := form_begin(inner)

	form_line(&form, "ship")
	reference_row(&form, "STARTING_HULL", ship.STARTING_HULL)
	reference_row(&form, "STARTING_SPEED", ship.STARTING_SPEED)
	reference_row(&form, "BASE_SPEED", ship.BASE_SPEED)
	form_note(&form, "  a calibration, not a free parameter: STARTING_SPEED + the starting ship's weight/10", FORGE_TEXT_DIM)
	reference_row(&form, "STARTING_CARGO", ship.STARTING_CARGO)
	reference_row(&form, "CAPTAIN_STARTING_CARGO", ship.CAPTAIN_STARTING_CARGO)
	reference_row(&form, "HOSTILE_FILL_PERCENT", ship.HOSTILE_FILL_PERCENT)
	reference_row(&form, "SHIP_MAX_SLOTS", ship.SHIP_MAX_SLOTS)
	reference_row(&form, "FITTING_MAX_EFFECTS", ship.FITTING_MAX_EFFECTS)

	form_line(&form, "budget")
	reference_row(&form, "POINT", int(ship.POINT))
	reference_row(&form, "BUDGET_BAND_PERCENT", ship.BUDGET_BAND_PERCENT)
	reference_row(&form, "WEIGHT_PER_POINT", ship.WEIGHT_PER_POINT)
	reference_row(&form, "WEIGHT_DEVIATION_PERCENT", ship.WEIGHT_DEVIATION_PERCENT)
	reference_row(&form, "CAPACITY_PER_POINT", ship.CAPACITY_PER_POINT)
	reference_row(&form, "PEAK_OUTPUT_CAP", ship.PEAK_OUTPUT_CAP)
	reference_row(&form, "GATE_FACTOR_SOFT", ship.GATE_FACTOR_SOFT)
	reference_row(&form, "GATE_FACTOR_REMOTE", ship.GATE_FACTOR_REMOTE)
	reference_row(&form, "GATE_SOFT_HULL_PERCENT", ship.GATE_SOFT_HULL_PERCENT)
	reference_row(&form, "GATE_SOFT_ROUND", ship.GATE_SOFT_ROUND)
	reference_row(&form, "EXPR_MAX_NODES", ship.EXPR_MAX_NODES)

	form_line(&form, "content")
	reference_row(&form, "ITEM_ROSTER_SIZE", ship.ITEM_ROSTER_SIZE)
	reference_row(&form, "ITEM_OFFER_OPTION_COUNT", voyage.ITEM_OFFER_OPTION_COUNT)
	reference_row(&form, "ENCOUNTER_MAX_STAGES", voyage.ENCOUNTER_MAX_STAGES)
	reference_row(&form, "SHOP_SHELF_SIZE", voyage.SHOP_SHELF_SIZE)
	reference_row(&form, "SHOP_STOCK_MAX", voyage.SHOP_STOCK_MAX)
	reference_row(&form, "DEPTH_STEPS", voyage.DEPTH_STEPS)
	reference_row(&form, "BASELINE_ROUND_COUNT", combat.BASELINE_ROUND_COUNT)
}

// stakes_pane is the gradient every bake reads, laid out as the table it is: one row per
// site, one column per primitive's reading of it.
@(private = "file")
stakes_pane :: proc(bounds: rl.Rectangle) {
	inner := panel(bounds, "Stakes by site")
	form := form_begin(inner)

	header := form_row(&form)
	draw_text("site", header.x, header.y + FORGE_TEXT_DY, color_of(FORGE_TEXT_DIM))
	for label, index in ([]string{"hull", "power%", "offer", "reward"}) {
		draw_mono_right(label, stakes_column(header.x, index), header.y + FORGE_TEXT_DY, color_of(FORGE_TEXT_DIM))
	}

	for zone in voyage.Zone {
		for depth in 0 ..= voyage.DEPTH_STEPS {
			site := voyage.Scaling_Site{zone = zone, depth = depth}
			row := form_row(&form)
			draw_text(fmt.tprintf("%v %d", zone, depth), row.x, row.y + FORGE_TEXT_DY, color_of(FORGE_TEXT))
			values := [4]int {
				voyage.voyage_fight_opponent_hull(site),
				voyage.voyage_fight_opponent_power(site),
				voyage.voyage_offer_item_quality(site),
				voyage.voyage_reward_cargo(site),
			}
			for value, index in values {
				draw_mono_right(fmt.tprintf("%d", value), stakes_column(row.x, index), row.y + FORGE_TEXT_DY, color_of(FORGE_TEXT_DIM))
			}
			band := voyage.voyage_offer_tier_band(site)
			band_x := stakes_column(row.x, 3) + FORGE_PAD
			draw_text_clipped(tier_band_text(band), band_x, row.y + FORGE_TEXT_DY, row.x + row.width - band_x, color_of(FORGE_TEXT_DIM))
		}
	}

	form_line(&form, "trade swing by zone")
	for zone in voyage.Zone {
		row := form_row(&form)
		draw_text(fmt.tprintf("%v", zone), row.x, row.y + FORGE_TEXT_DY, color_of(FORGE_TEXT))
		for stat, index in voyage.Trade_Stat {
			draw_mono_right(
				fmt.tprintf("%v %d", stat, voyage.voyage_trade_swing(zone, stat)),
				row.x + SWING_LABEL_W + f32(index + 1) * SWING_COLUMN_W,
				row.y + FORGE_TEXT_DY,
				color_of(FORGE_TEXT_DIM),
			)
		}
	}
	form_note(&form, "Trade reads the zone alone: a swing is an exchange rate with no room for a depth axis", FORGE_TEXT_DIM)
}

// tier_band_text writes an Offer's band as the shelves it draws from. The bit_set's own
// formatting spells its type as well as its members, which is more than a column this
// narrow can carry.
@(private = "file")
tier_band_text :: proc(band: bit_set[ship.Tier]) -> string {
	text := ""
	for tier in ship.Tier {
		if tier not_in band {
			continue
		}
		if len(text) > 0 {
			text = fmt.tprintf("%s, ", text)
		}
		text = fmt.tprintf("%s%v", text, tier)
	}
	return text
}

@(private = "file")
reference_row :: proc(form: ^Form, label: string, value: int) {
	row := form_row(form)
	draw_text(label, row.x, row.y + FORGE_TEXT_DY, color_of(FORGE_TEXT_DIM))
	draw_mono_right(fmt.tprintf("%d", value), row.x + row.width, row.y + FORGE_TEXT_DY, color_of(FORGE_TEXT))
}
