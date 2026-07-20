package ship

// The roster (ADR-0012): the pool an Item Offer and a Port shop draw from, one proc per
// item, listed in ROSTER_AUTHORS. It is in-proc Odin rather than a data file because an
// item's magnitude is an expression tree built by expr.odin's helper procs, which nothing
// outside the language can call.
//
// **New items append to the end of ROSTER_AUTHORS, always.** Roster order is load-bearing
// for seed stability — shop baking and the offer draw index into it — so a mid-array
// insert silently changes which item an existing seed offers. Tier is a field each item's
// proc names, never a position in the list.

// roster_item is the one way an entry is authored: the item's tier, the fitting's authored
// fields, and its effects, which must number between one and FITTING_MAX_EFFECTS and are
// written through the effect_* verb helpers (each of which names the phase that consumes it
// and an honest site_scale of 100).
//
// `bulk` defaults to the size's **full slot contribution**, so an entry that does not name
// it carries nothing. That default is the whole reason this seam exists: bulk's zero value
// is the *carrying* end of the axis (ship_fitting_capacity), so a plain Fitting literal that
// omits it bolts a free full-slot hold onto a gun and hands the power budget capacity it
// never priced. An item that means to carry names the bulk it means.
//
// Its other authoring invariants: a size the ship template can hold, and a weight in its
// size band — which is what the item costs its ship in Speed (ship_fitting_weight →
// ship_effective_speed).
roster_item :: proc(
	tier: Tier,
	name: string,
	size: Slot_Size,
	weight: int,
	tags: bit_set[Tag],
	effects: []Effect,
	bulk: Maybe(int) = nil,
) -> Roster_Item {
	return Roster_Item {
		tier = tier,
		fitting = ship_fitting_with_effects(
			Fitting {
				name = name,
				size = size,
				weight = weight,
				tags = tags,
				bulk = bulk.? or_else ship_cargo_slot_contribution(size),
			},
			..effects,
		),
	}
}

roster_deckhands :: proc() -> Roster_Item {
	return roster_item(.Splash, "Deckhands", .Small, 6, {.Crew}, {effect_phase_contribution(expr_const(1))})
}

roster_swivel_guns :: proc() -> Roster_Item {
	return roster_item(.Splash, "Swivel Guns", .Small, 8, {.Weapon}, {effect_phase_contribution(expr_const(3))})
}

roster_deck_cannon :: proc() -> Roster_Item {
	return roster_item(.Splash, "Deck Cannon", .Medium, 18, {.Weapon}, {effect_phase_contribution(expr_const(4))})
}

roster_boarding_pikes :: proc() -> Roster_Item {
	return roster_item(.Splash, "Boarding Pikes", .Small, 6, {.Weapon, .Crew}, {effect_phase_contribution(expr_const(2))})
}

roster_snapping_eels :: proc() -> Roster_Item {
	return roster_item(.Splash, "Snapping Eels", .Small, 7, {.Beast}, {effect_phase_contribution(expr_const(3))})
}

roster_oakum_and_pitch :: proc() -> Roster_Item {
	return roster_item(.Splash, "Oakum & Pitch", .Medium, 24, {.Artifact}, {effect_repair(expr_const(5))})
}

roster_spare_timbers :: proc() -> Roster_Item {
	return roster_item(.Splash, "Spare Timbers", .Small, 12, {.Cargo}, {effect_repair(expr_const(3))})
}

roster_spare_rigging :: proc() -> Roster_Item {
	return roster_item(.Splash, "Spare Rigging", .Small, 5, {.Artifact}, {effect_modify_speed(expr_const(1))})
}

roster_salt_provisions :: proc() -> Roster_Item {
	return roster_item(.Splash, "Salt Provisions", .Small, 7, {.Cargo}, {effect_repair(expr_const(3))})
}

roster_carpenters_mate :: proc() -> Roster_Item {
	return roster_item(.Splash, "Carpenter's Mate", .Small, 5, {.Crew}, {effect_repair(expr_const(2))})
}

roster_deck_pumps :: proc() -> Roster_Item {
	return roster_item(.Splash, "Deck Pumps", .Medium, 20, {.Artifact}, {effect_repair(expr_const(4))})
}

roster_powder_monkeys :: proc() -> Roster_Item {
	return roster_item(
		.Splash,
		"Powder Monkeys",
		.Small,
		6,
		{.Crew},
		{effect_phase_contribution(expr_const(1), Selector(Tag.Weapon))},
	)
}

roster_smugglers_crates :: proc() -> Roster_Item {
	return roster_item(
		.Splash,
		"Smuggler's Crates",
		.Small,
		7,
		{.Cargo},
		{effect_phase_contribution(expr_const(1), Selector(Visibility.Concealed))},
	)
}

roster_war_hound :: proc() -> Roster_Item {
	return roster_item(.Splash, "War Hound", .Small, 7, {.Beast}, {effect_phase_contribution(expr_below_hull_percent(50, 3))})
}

roster_lookout_nest :: proc() -> Roster_Item {
	return roster_item(.Splash, "Lookout Nest", .Small, 5, {.Crew}, {effect_phase_contribution(expr_while_opponent_faster(2))})
}

roster_bilge_rats :: proc() -> Roster_Item {
	return roster_item(.Splash, "Bilge Rats", .Small, 5, {.Beast}, {effect_phase_contribution(expr_from_round(3, 2))})
}

roster_harpoon_line :: proc() -> Roster_Item {
	return roster_item(.Splash, "Harpoon Line", .Small, 6, {.Weapon, .Beast}, {effect_phase_contribution(expr_const(3))})
}

roster_long_nines :: proc() -> Roster_Item {
	return roster_item(.Shallow, "Long Nines", .Large, 42, {.Weapon}, {effect_phase_contribution(expr_const(8))})
}

roster_carronade :: proc() -> Roster_Item {
	return roster_item(.Shallow, "Carronade", .Medium, 22, {.Weapon}, {effect_phase_contribution(expr_const(6))})
}

roster_naval_gun_crew :: proc() -> Roster_Item {
	return roster_item(.Shallow, "Naval Gun Crew", .Medium, 20, {.Crew, .Weapon}, {effect_phase_contribution(expr_const(6))})
}

roster_sea_drake :: proc() -> Roster_Item {
	return roster_item(.Shallow, "Sea Drake", .Large, 34, {.Beast}, {effect_phase_contribution(expr_const(7))})
}

roster_ramming_prow :: proc() -> Roster_Item {
	return roster_item(.Shallow, "Ramming Prow", .Large, 40, {.Artifact}, {effect_phase_contribution(expr_const(7))})
}

roster_war_drums :: proc() -> Roster_Item {
	return roster_item(.Shallow, "War Drums", .Small, 6, {.Crew}, {effect_phase_contribution(expr_const(3))})
}

roster_shipwrights_kit :: proc() -> Roster_Item {
	return roster_item(.Shallow, "Shipwright's Kit", .Medium, 25, {.Artifact}, {effect_repair(expr_const(7))})
}

roster_copper_sheathing :: proc() -> Roster_Item {
	return roster_item(.Shallow, "Copper Sheathing", .Medium, 16, {.Artifact}, {effect_modify_speed(expr_const(2))})
}

roster_ships_surgeon :: proc() -> Roster_Item {
	return roster_item(.Shallow, "Ship's Surgeon", .Medium, 16, {.Crew}, {effect_repair(expr_const(6))})
}

roster_outriggers :: proc() -> Roster_Item {
	return roster_item(
		.Shallow,
		"Outriggers",
		.Small,
		5,
		{.Artifact},
		{effect_modify_speed(expr_const(1), Selector(Slot_Size.Small))},
	)
}

roster_gun_captain :: proc() -> Roster_Item {
	return roster_item(
		.Shallow,
		"Gun Captain",
		.Medium,
		16,
		{.Crew},
		{effect_phase_contribution(expr_const(2), Selector(Tag.Weapon))},
	)
}

// Master Gunner counts the medium berths — a gunner for every gun deck the ship saw fit to
// build at fighting size. A phase is not a countable axis (see Selector), so a "per Fire
// fitting" reading is not one an item can be authored against.
roster_master_gunner :: proc() -> Roster_Item {
	return roster_item(
		.Shallow,
		"Master Gunner",
		.Medium,
		16,
		{.Crew},
		{effect_phase_contribution(expr_const(2), Selector(Slot_Size.Medium))},
	)
}

roster_contraband_hold :: proc() -> Roster_Item {
	return roster_item(
		.Shallow,
		"Contraband Hold",
		.Medium,
		18,
		{.Cargo},
		{effect_phase_contribution(expr_const(2), Selector(Tag.Cargo))},
	)
}

roster_kraken_spawn :: proc() -> Roster_Item {
	return roster_item(.Shallow, "Kraken Spawn", .Medium, 20, {.Beast}, {effect_phase_contribution(expr_below_hull_percent(50, 8))})
}

roster_ghost_lantern :: proc() -> Roster_Item {
	return roster_item(.Shallow, "Ghost Lantern", .Small, 5, {.Artifact}, {effect_phase_contribution(expr_while_concealed(4))})
}

roster_storm_sails :: proc() -> Roster_Item {
	return roster_item(
		.Shallow,
		"Storm Sails",
		.Medium,
		15,
		{.Artifact},
		{effect_phase_contribution(expr_while_opponent_slower(4))},
	)
}

roster_chain_and_bar_shot :: proc() -> Roster_Item {
	return roster_item(
		.Shallow,
		"Chain & Bar Shot",
		.Medium,
		21,
		{.Weapon},
		{effect_phase_contribution(expr_while_opponent_faster(7))},
	)
}

roster_great_bombard :: proc() -> Roster_Item {
	return roster_item(.Deep, "Great Bombard", .Large, 45, {.Weapon}, {effect_phase_contribution(expr_const(12))})
}

roster_leviathan :: proc() -> Roster_Item {
	return roster_item(.Deep, "Leviathan", .Large, 38, {.Beast}, {effect_phase_contribution(expr_const(11))})
}

roster_dragon_turtle :: proc() -> Roster_Item {
	return roster_item(.Deep, "Dragon Turtle", .Large, 40, {.Beast}, {effect_repair(expr_const(12))})
}

roster_adamant_sigil :: proc() -> Roster_Item {
	return roster_item(.Deep, "Adamant Sigil", .Medium, 25, {.Artifact}, {effect_repair(expr_const(10))})
}

roster_enchanted_keel :: proc() -> Roster_Item {
	return roster_item(.Deep, "Enchanted Keel", .Medium, 15, {.Artifact}, {effect_modify_speed(expr_const(3))})
}

roster_titans_heart :: proc() -> Roster_Item {
	return roster_item(.Deep, "Titan's Heart", .Large, 36, {.Artifact}, {effect_repair(expr_const(11))})
}

roster_shipwrights_stores :: proc() -> Roster_Item {
	return roster_item(.Deep, "Shipwright's Stores", .Medium, 22, {.Cargo}, {effect_repair(expr_const(9))})
}

roster_admirals_guard :: proc() -> Roster_Item {
	return roster_item(
		.Deep,
		"Admiral's Guard",
		.Medium,
		17,
		{.Crew},
		{effect_phase_contribution(expr_const(3), Selector(Tag.Crew))},
	)
}

roster_broadside_master :: proc() -> Roster_Item {
	return roster_item(
		.Deep,
		"Broadside Master",
		.Large,
		36,
		{.Crew, .Weapon},
		{effect_phase_contribution(expr_const(3), Selector(Tag.Weapon))},
	)
}

roster_hunters_pack :: proc() -> Roster_Item {
	return roster_item(
		.Deep,
		"Hunter's Pack",
		.Medium,
		18,
		{.Beast},
		{effect_phase_contribution(expr_const(3), Selector(Tag.Beast))},
	)
}

roster_flagship_colors :: proc() -> Roster_Item {
	return roster_item(
		.Deep,
		"Flagship Colors",
		.Medium,
		15,
		{.Artifact},
		{effect_phase_contribution(expr_const(3), Selector(Slot_Size.Large))},
	)
}

roster_storm_caller :: proc() -> Roster_Item {
	return roster_item(
		.Deep,
		"Storm Caller",
		.Small,
		6,
		{.Artifact},
		{effect_phase_contribution(expr_const(3), Selector(Visibility.Concealed))},
	)
}

roster_wraith_cannon :: proc() -> Roster_Item {
	return roster_item(
		.Deep,
		"Wraith Cannon",
		.Medium,
		22,
		{.Artifact, .Weapon},
		{effect_phase_contribution(expr_while_concealed(10))},
	)
}

roster_cornered_beast :: proc() -> Roster_Item {
	return roster_item(.Deep, "Cornered Beast", .Large, 38, {.Beast}, {effect_phase_contribution(expr_below_hull_percent(50, 12))})
}

roster_siege_battery :: proc() -> Roster_Item {
	return roster_item(.Deep, "Siege Battery", .Large, 44, {.Weapon}, {effect_phase_contribution(expr_from_round(5, 11))})
}

roster_sea_witch :: proc() -> Roster_Item {
	return roster_item(.Deep, "Sea Witch", .Medium, 16, {.Crew}, {effect_phase_contribution(expr_while_opponent_faster(6))})
}

// ROSTER_AUTHORS is the pool itself: each item's proc, in the order an Offer and a shop
// index it. Append only — see the note at the top of this file.
ROSTER_AUTHORS :: [?]proc() -> Roster_Item {
	roster_deckhands,
	roster_swivel_guns,
	roster_deck_cannon,
	roster_boarding_pikes,
	roster_snapping_eels,
	roster_oakum_and_pitch,
	roster_spare_timbers,
	roster_spare_rigging,
	roster_salt_provisions,
	roster_carpenters_mate,
	roster_deck_pumps,
	roster_powder_monkeys,
	roster_smugglers_crates,
	roster_war_hound,
	roster_lookout_nest,
	roster_bilge_rats,
	roster_harpoon_line,
	roster_long_nines,
	roster_carronade,
	roster_naval_gun_crew,
	roster_sea_drake,
	roster_ramming_prow,
	roster_war_drums,
	roster_shipwrights_kit,
	roster_copper_sheathing,
	roster_ships_surgeon,
	roster_outriggers,
	roster_gun_captain,
	roster_master_gunner,
	roster_contraband_hold,
	roster_kraken_spawn,
	roster_ghost_lantern,
	roster_storm_sails,
	roster_chain_and_bar_shot,
	roster_great_bombard,
	roster_leviathan,
	roster_dragon_turtle,
	roster_adamant_sigil,
	roster_enchanted_keel,
	roster_titans_heart,
	roster_shipwrights_stores,
	roster_admirals_guard,
	roster_broadside_master,
	roster_hunters_pack,
	roster_flagship_colors,
	roster_storm_caller,
	roster_wraith_cannon,
	roster_cornered_beast,
	roster_siege_battery,
	roster_sea_witch,
}

// ITEM_ROSTER_SIZE is how many distinct items ship_item_roster hands back — the pool an
// Item Offer samples its options from (voyage.voyage_item_offer_options), and the size of
// the index arrays core/voyage builds over it. Read off the list itself, so an appended
// item is one edit; must stay at least voyage.ITEM_OFFER_OPTION_COUNT so an offer can
// present that many distinct items, and the_item_roster_is_about_fifty_distinct_placeable_items
// is where a change to the count is answered for.
ITEM_ROSTER_SIZE :: len(ROSTER_AUTHORS)

// ship_item_roster builds the full roster pool as value data: every entry's fields and
// effect trees are assembled by its own proc at call time, so nothing here is a top-level
// constant a const-fold can mangle. Caller owns the returned array by value — Fittings hold
// only value fields and static-string names, so there is nothing to free.
ship_item_roster :: proc() -> [ITEM_ROSTER_SIZE]Roster_Item {
	roster: [ITEM_ROSTER_SIZE]Roster_Item
	for author, i in ROSTER_AUTHORS {
		roster[i] = author()
	}
	return roster
}

// ship_item_by_name finds a roster item by its authored name — the lookup that lets a
// content table elsewhere name the items it is built from ("Long Nines") instead of
// duplicating their magnitudes or pointing at roster indices. A linear scan, called only
// at map generation, so the roster stays a plain authored table with no lookup structure
// to keep in sync.
//
// The (T, bool) return is the house idiom for a fallible read, but a miss here is a
// *content* bug — an author's typo — not a runtime condition, so callers assert rather
// than handle it.
ship_item_by_name :: proc(name: string) -> (item: Roster_Item, ok: bool) {
	for candidate in ship_item_roster() {
		if candidate.fitting.name == name {
			return candidate, true
		}
	}
	return {}, false
}
