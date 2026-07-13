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

// ship_fitting_cargo builds one of the ship template's default cargo
// fillers (issue #23: "cargo fills the 3 concealed slots by default").
// name lets a caller flavor multiple cargo instances (e.g. a PvE opponent's
// "Spoils") without a separate fitting type (ADR-0004).
ship_fitting_cargo :: proc(name: string) -> Fitting {
	return Fitting{name = name, size = .Small, tags = {.Cargo}, is_cargo = true, stack_count = CARGO_STACK_COUNT}
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
// ship_fit_starting_loadout fits every slot of ship_starting_ship's fixed
// loadout (issue #54: an or_return chain replacing 6 hand-threaded
// ok/assert pairs — a false return here means the template and its starting
// fittings have drifted out of sync, a content bug caught immediately by
// this package's own tests, not a real runtime condition).
ship_fit_starting_loadout :: proc(layout: []Layout_Slot) -> bool {
	ship_fit(&layout[0], ship_fitting_captains_quarters()) or_return
	ship_fit(&layout[1], ship_fitting_top_crew()) or_return
	ship_fit(&layout[2], ship_fitting_gun_deck()) or_return
	ship_fit(&layout[3], ship_fitting_cargo("Cargo")) or_return
	ship_fit(&layout[4], ship_fitting_cargo("Cargo")) or_return
	return ship_fit(&layout[5], ship_fitting_cargo("Cargo"))
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
