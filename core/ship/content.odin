package ship

// Vertical-slice content (issue #23): the one hand-authored ship template,
// its fixed starting loadout, the one captain, and the upgraded variants of
// the three starting fittings that comprise all findable content (ADR-0004:
// "no fitting roster beyond the 3 starting fittings plus their upgraded
// variants"). Every numeric magnitude below is a placeholder, like every
// other balance constant in this codebase — expected to move during
// playtesting, not final balance.

TOP_CREW_BUFF_MAGNITUDE :: 3
CAPTAINS_QUARTERS_DEFENSE_MAGNITUDE :: 2
GUN_DECK_OFFENSE_MAGNITUDE :: 5
CARGO_STACK_COUNT :: 1

STARTING_HP :: 20
STARTING_DURABILITY :: 2
STARTING_SPEED :: 4
STARTING_TREASURE :: 50
STARTING_BASE_CARGO_CAPACITY :: 2

// CAPTAIN_CARGO_CAPACITY_BONUS is the one captain's cargo_capacity_bonus —
// see the Captain struct's doc comment for the design rationale.
CAPTAIN_CARGO_CAPACITY_BONUS :: 1

// ship_fitting_top_crew, ship_fitting_captains_quarters, and
// ship_fitting_gun_deck are the three starting fittings (issue #23) that
// fill the ship template's three exposed slots. Their category assignment
// gives the starting loadout one active effect per round phase (ADR-0006):
// Top Crew buffs, Captain's Quarters defends, Gun Deck attacks.
// The tags below are each fitting's family membership (#90): Top Crew and
// Captain's Quarters are Crew, Gun Deck is a Weapon, cargo is Cargo. Each
// starting fitting sits in exactly one family — multi-tag is reserved for the
// roster to come (#88). The upgraded variants inherit these through
// ship_fitting_upgraded, which copies the base fitting whole.
ship_fitting_top_crew :: proc() -> Fitting {
	return Fitting{name = "Top Crew", size = .Medium, category = .Buff, tags = {.Crew}, active = Effect{magnitude = TOP_CREW_BUFF_MAGNITUDE}}
}

ship_fitting_captains_quarters :: proc() -> Fitting {
	return Fitting{name = "Captain's Quarters", size = .Medium, category = .Defensive, tags = {.Crew}, active = Effect{magnitude = CAPTAINS_QUARTERS_DEFENSE_MAGNITUDE}}
}

ship_fitting_gun_deck :: proc() -> Fitting {
	return Fitting{name = "Gun Deck", size = .Large, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = GUN_DECK_OFFENSE_MAGNITUDE}}
}

// ship_fitting_upgraded is the shared shape behind ship_fitting_upgraded_top_crew,
// _captains_quarters, and _gun_deck below: an upgraded variant keeps its
// base's size/category and adds bonus on top of the base magnitude. bonus is
// a caller-supplied scale (issue #23: an Upgrade Offer's quality rises by
// zone, so a deeper node's upgrade should be worth more, and a PvE
// opponent's gun deck scales the same way — see core/run's content.odin),
// not a fixed constant.
ship_fitting_upgraded :: proc(base: Fitting, upgraded_name: string, bonus: int) -> Fitting {
	f := base
	f.name = upgraded_name
	base_active, _ := base.active.?
	// Carry the base effect's kind through unchanged (all three starting
	// fittings are Phase_Contribution) so an upgrade only scales magnitude.
	f.active = Effect{kind = base_active.kind, magnitude = base_active.magnitude + Magnitude(bonus)}
	return f
}

// ship_fitting_upgraded_top_crew, _captains_quarters, and _gun_deck are the
// only findable content this slice has (ADR-0004: "no fitting roster beyond
// the 3 starting fittings plus their upgraded variants").
ship_fitting_upgraded_top_crew :: proc(bonus: int) -> Fitting {
	return ship_fitting_upgraded(ship_fitting_top_crew(), "Upgraded Top Crew", bonus)
}

ship_fitting_upgraded_captains_quarters :: proc(bonus: int) -> Fitting {
	return ship_fitting_upgraded(ship_fitting_captains_quarters(), "Upgraded Captain's Quarters", bonus)
}

ship_fitting_upgraded_gun_deck :: proc(bonus: int) -> Fitting {
	return ship_fitting_upgraded(ship_fitting_gun_deck(), "Upgraded Gun Deck", bonus)
}

// The minimal item roster (issue #96): a handful of distinct roster items the
// Item Offer draws from until the full ~50-item roster lands (#97, ADR-0012).
// Deliberately small but spread across the axes build variance turns on — the
// five tag families, all three sizes and phases, and the full effect vocabulary
// (flat, stat-modifier, synergy, conditional, and a multi-tag fitting) — so an
// offer is already a meaningful build choice, not the old three fixed upgrades.
// Every magnitude is placeholder tuning like the rest of this file. Sizes are
// chosen so each item fits somewhere in the template (Medium x3 / Large x2 /
// Small x3).
CANNON_BATTERY_OFFENSE :: 6
REINFORCED_HULL_DURABILITY :: 2
WAR_SERPENT_OFFENSE :: 8
POWDER_MONKEYS_BUFF_PER_WEAPON :: 2
SWIFT_RIGGING_SPEED :: 2
MARINE_BOARDERS_OFFENSE :: 4

// ITEM_ROSTER_SIZE is how many distinct items ship_item_roster hands back — the
// pool an Item Offer samples its options from (run.run_item_offer_options). Must
// stay at least run.ITEM_OFFER_OPTION_COUNT so an offer can present that many
// distinct items.
ITEM_ROSTER_SIZE :: 6

// ship_item_roster returns the minimal roster pool (issue #96) as value data —
// built in the proc body (not a top-level constant) so its synergy Selector
// literal resolves at runtime, sidestepping the const-fold regression the CI
// pin documents. Caller owns the returned array by value (Fittings hold only
// value fields and static-string names, so there is nothing to free).
ship_item_roster :: proc() -> [ITEM_ROSTER_SIZE]Fitting {
	return [ITEM_ROSTER_SIZE]Fitting {
		// Flat weapon: the plain-offense baseline, a large gun.
		Fitting {
			name = "Cannon Battery",
			size = .Large,
			category = .Offensive,
			tags = {.Weapon},
			active = Effect{magnitude = CANNON_BATTERY_OFFENSE},
		},
		// Stat-modifier: raises effective Durability rather than feeding a phase.
		Fitting {
			name = "Reinforced Hull",
			size = .Medium,
			category = .Defensive,
			tags = {.Artifact},
			passive = Effect{kind = .Modify_Durability, magnitude = REINFORCED_HULL_DURABILITY},
		},
		// Conditional: a beast that only bites once the ship is below half HP.
		Fitting {
			name = "War Serpent",
			size = .Large,
			category = .Offensive,
			tags = {.Beast},
			active = Effect{magnitude = WAR_SERPENT_OFFENSE, conditional = Condition_HP_Below{percent = 50}},
		},
		// Synergy: buff scaling with how many Weapons are aboard.
		Fitting {
			name = "Powder Monkeys",
			size = .Small,
			category = .Buff,
			tags = {.Crew},
			active = Effect{magnitude = POWDER_MONKEYS_BUFF_PER_WEAPON, synergy = Selector(Tag.Weapon)},
		},
		// Stat-modifier: raises effective Speed (better escape / tie-break).
		Fitting {
			name = "Swift Rigging",
			size = .Small,
			category = .Buff,
			tags = {.Artifact},
			passive = Effect{kind = .Modify_Speed, magnitude = SWIFT_RIGGING_SPEED},
		},
		// Multi-tag flat: a boarding party that is both Crew and Weapon, so it
		// feeds a Weapon synergy while itself being plain offense.
		Fitting {
			name = "Marine Boarders",
			size = .Medium,
			category = .Offensive,
			tags = {.Crew, .Weapon},
			active = Effect{magnitude = MARINE_BOARDERS_OFFENSE},
		},
	}
}

// ship_fitting_scaled returns a copy of base with `bonus` added to its effect
// magnitude — the Item Offer's zone-and-depth quality knob applied to a roster
// item (issue #96), the roster analogue of ship_fitting_upgraded's per-node
// scaling. bonus lands on whichever of the passive/active effect the item
// carries (roster items carry exactly one), leaving the effect's kind, selector,
// and condition intact so its flat / stat-modifier / synergy / conditional
// character is preserved and only its strength moves. A cargo filler (no effect)
// is returned unchanged.
ship_fitting_scaled :: proc(base: Fitting, bonus: int) -> Fitting {
	f := base
	if effect, ok := f.passive.?; ok {
		effect.magnitude += Magnitude(bonus)
		f.passive = effect
	}
	if effect, ok := f.active.?; ok {
		effect.magnitude += Magnitude(bonus)
		f.active = effect
	}
	return f
}

// ship_fitting_cargo builds one of the ship template's default cargo fillers
// (issue #23: "cargo fills the concealed slots by default"). name lets a
// caller flavor multiple cargo instances (e.g. a PvE opponent's "Spoils")
// without a separate fitting type (ADR-0004). size is caller-supplied so cargo
// can fill a slot of any size under the exact-size-match fit rule (issue #91:
// every empty slot, not just the small holds, can be spent on cargo capacity —
// a larger slot's cargo is worth more, see ship_cargo_slot_contribution). Cargo
// carries the Cargo tag family (#90).
ship_fitting_cargo :: proc(name: string, size: Slot_Size) -> Fitting {
	return Fitting{name = name, size = size, tags = {.Cargo}, is_cargo = true, stack_count = CARGO_STACK_COUNT}
}

// ship_template_layout is the vertical slice's one ship template (issue #91,
// CONTEXT.md): 8 slots — Large x2, Medium x3, Small x3, split 4 exposed / 4
// concealed. The three exposed combat slots ("top deck", "top crew", "gun
// deck") keep their sizes so the starting loadout still fits; the expansion
// adds a second exposed Large ("forecastle") and grows the concealed hold from
// three small slots to one medium plus three small. Caller owns the returned
// slice.
ship_template_layout :: proc() -> []Layout_Slot {
	layout := make([]Layout_Slot, 8)
	layout[0] = Layout_Slot{slot = Slot{name = "top deck", size = .Medium, base_visibility = .Exposed}}
	layout[1] = Layout_Slot{slot = Slot{name = "top crew", size = .Medium, base_visibility = .Exposed}}
	layout[2] = Layout_Slot{slot = Slot{name = "gun deck", size = .Large, base_visibility = .Exposed}}
	layout[3] = Layout_Slot{slot = Slot{name = "forecastle", size = .Large, base_visibility = .Exposed}}
	layout[4] = Layout_Slot{slot = Slot{name = "hold 1", size = .Medium, base_visibility = .Concealed}}
	layout[5] = Layout_Slot{slot = Slot{name = "hold 2", size = .Small, base_visibility = .Concealed}}
	layout[6] = Layout_Slot{slot = Slot{name = "hold 3", size = .Small, base_visibility = .Concealed}}
	layout[7] = Layout_Slot{slot = Slot{name = "hold 4", size = .Small, base_visibility = .Concealed}}
	return layout
}

// ship_starting_captain is the vertical slice's one captain (issue #23,
// CONTEXT.md: "Exactly one captain").
ship_starting_captain :: proc() -> Captain {
	return Captain{name = "Captain Odessa Vane", cargo_capacity_bonus = CAPTAIN_CARGO_CAPACITY_BONUS}
}

// ship_starting_ship assembles the run's starting Ship (issue #23): the one
// template, filled with its fixed starting loadout — Captain's Quarters and
// Top Crew in the two medium exposed slots, Gun Deck in the large exposed
// slot, cargo filling every remaining slot by default (issue #91) — plus the
// one captain. Hand-placement of Captain's Quarters into "top deck" and Top
// Crew into "top crew" is a flavor-only pairing (ADR-0004: slot names impose
// no restriction on what fills them). Caller owns the returned Ship's
// layout slice.
// ship_fit_starting_loadout fits the fixed combat loadout into ship_starting_ship's
// exposed slots and hands the rest to ship_fill_empty_slots_with_cargo (issue
// #54: an or_return chain replacing hand-threaded ok/assert pairs — a false
// return here means the template and its starting fittings have drifted out of
// sync, a content bug caught immediately by this package's own tests, not a
// real runtime condition).
ship_fit_starting_loadout :: proc(layout: []Layout_Slot) -> bool {
	ship_fit(&layout[0], ship_fitting_captains_quarters()) or_return
	ship_fit(&layout[1], ship_fitting_top_crew()) or_return
	ship_fit(&layout[2], ship_fitting_gun_deck()) or_return
	return ship_fill_empty_slots_with_cargo(layout, "Cargo")
}

// ship_fill_empty_slots_with_cargo fills every still-empty slot of `layout`
// with a size-matching cargo filler (issue #91: once the combat fittings are
// placed, all remaining slots — whatever their size or visibility — go to
// cargo capacity rather than sitting idle). Each filler takes its slot's own
// size so it satisfies the exact-size-match fit rule (ADR-0004), so ship_fit
// only fails here on a genuine content bug, never a size mismatch. Both the
// starting loadout and the PvE-opponent loadout share this, so a template
// resize needs no per-slot edits at either call site.
ship_fill_empty_slots_with_cargo :: proc(layout: []Layout_Slot, name: string) -> bool {
	for &layout_slot in layout {
		if _, occupied := layout_slot.fitting.?; occupied {
			continue
		}
		ship_fit(&layout_slot, ship_fitting_cargo(name, layout_slot.slot.size)) or_return
	}
	return true
}

ship_starting_ship :: proc() -> Ship {
	layout := ship_template_layout()
	assert(ship_fit_starting_loadout(layout), "starting loadout: a fitting failed to fit its template slot")

	return Ship{
		hp                  = STARTING_HP,
		max_hp              = STARTING_HP,
		durability          = STARTING_DURABILITY,
		speed               = STARTING_SPEED,
		starting_treasure   = STARTING_TREASURE,
		base_cargo_capacity = STARTING_BASE_CARGO_CAPACITY,
		layout              = layout,
		captain             = ship_starting_captain(),
	}
}
