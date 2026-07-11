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
ship_fitting_top_crew :: proc() -> Fitting {
	return Fitting{name = "Top Crew", size = .Medium, category = .Buff, active = Effect{magnitude = TOP_CREW_BUFF_MAGNITUDE}}
}

ship_fitting_captains_quarters :: proc() -> Fitting {
	return Fitting{name = "Captain's Quarters", size = .Medium, category = .Defensive, active = Effect{magnitude = CAPTAINS_QUARTERS_DEFENSE_MAGNITUDE}}
}

ship_fitting_gun_deck :: proc() -> Fitting {
	return Fitting{name = "Gun Deck", size = .Large, category = .Offensive, active = Effect{magnitude = GUN_DECK_OFFENSE_MAGNITUDE}}
}

// ship_fitting_upgraded_top_crew, _captains_quarters, and _gun_deck are the
// only findable content this slice has (ADR-0004: "no fitting roster beyond
// the 3 starting fittings plus their upgraded variants") — an upgraded
// variant keeps its base's size/category and adds bonus on top of the base
// magnitude. bonus is a caller-supplied scale (issue #23: an Upgrade Offer's
// quality rises by zone, so a deeper point's upgrade should be worth more,
// and a PvE opponent's gun deck scales the same way — see core/run's
// content.odin), not a fixed constant.
ship_fitting_upgraded_top_crew :: proc(bonus: int) -> Fitting {
	f := ship_fitting_top_crew()
	f.name = "Upgraded Top Crew"
	f.active = Effect{magnitude = TOP_CREW_BUFF_MAGNITUDE + bonus}
	return f
}

ship_fitting_upgraded_captains_quarters :: proc(bonus: int) -> Fitting {
	f := ship_fitting_captains_quarters()
	f.name = "Upgraded Captain's Quarters"
	f.active = Effect{magnitude = CAPTAINS_QUARTERS_DEFENSE_MAGNITUDE + bonus}
	return f
}

ship_fitting_upgraded_gun_deck :: proc(bonus: int) -> Fitting {
	f := ship_fitting_gun_deck()
	f.name = "Upgraded Gun Deck"
	f.active = Effect{magnitude = GUN_DECK_OFFENSE_MAGNITUDE + bonus}
	return f
}

// ship_fitting_cargo builds one of the ship template's default cargo
// fillers (issue #23: "cargo fills the 3 concealed slots by default").
// name lets a caller flavor multiple cargo instances (e.g. a PvE opponent's
// "Spoils") without a separate fitting type (ADR-0004).
ship_fitting_cargo :: proc(name: string) -> Fitting {
	return Fitting{name = name, size = .Small, is_cargo = true, stack_count = CARGO_STACK_COUNT}
}

// ship_template_layout is the vertical slice's one ship template (issue #23,
// CONTEXT.md): 6 slots — 2 medium exposed ("top deck", "top crew"), 1 large
// exposed ("gun deck"), 3 small concealed. Caller owns the returned slice.
ship_template_layout :: proc() -> []Layout_Slot {
	layout := make([]Layout_Slot, 6)
	layout[0] = Layout_Slot{slot = Slot{name = "top deck", size = .Medium, base_visibility = .Exposed}}
	layout[1] = Layout_Slot{slot = Slot{name = "top crew", size = .Medium, base_visibility = .Exposed}}
	layout[2] = Layout_Slot{slot = Slot{name = "gun deck", size = .Large, base_visibility = .Exposed}}
	layout[3] = Layout_Slot{slot = Slot{name = "hold 1", size = .Small, base_visibility = .Concealed}}
	layout[4] = Layout_Slot{slot = Slot{name = "hold 2", size = .Small, base_visibility = .Concealed}}
	layout[5] = Layout_Slot{slot = Slot{name = "hold 3", size = .Small, base_visibility = .Concealed}}
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
// slot, cargo filling the three small concealed slots by default — plus the
// one captain. Hand-placement of Captain's Quarters into "top deck" and Top
// Crew into "top crew" is a flavor-only pairing (ADR-0004: slot names impose
// no restriction on what fills them). Caller owns the returned Ship's
// layout slice.
ship_starting_ship :: proc() -> Ship {
	layout := ship_template_layout()

	ok: bool
	ok = ship_fit(&layout[0], ship_fitting_captains_quarters())
	assert(ok, "starting loadout: Captain's Quarters must fit \"top deck\"")
	ok = ship_fit(&layout[1], ship_fitting_top_crew())
	assert(ok, "starting loadout: Top Crew must fit \"top crew\"")
	ok = ship_fit(&layout[2], ship_fitting_gun_deck())
	assert(ok, "starting loadout: Gun Deck must fit \"gun deck\"")
	ok = ship_fit(&layout[3], ship_fitting_cargo("Cargo"))
	assert(ok, "starting loadout: default cargo must fit \"hold 1\"")
	ok = ship_fit(&layout[4], ship_fitting_cargo("Cargo"))
	assert(ok, "starting loadout: default cargo must fit \"hold 2\"")
	ok = ship_fit(&layout[5], ship_fitting_cargo("Cargo"))
	assert(ok, "starting loadout: default cargo must fit \"hold 3\"")

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
