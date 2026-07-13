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

// Tier is the catalog-authoring power/cost grade a roster item is written at
// (ADR-0012, #97): Splash (lightest / cheapest) -> Shallow (mid) -> Deep
// (strongest), echoing the Coastal -> Open Sea -> The Deep run progression. It
// is deliberately *not* a field on Fitting: tier scales an item's authored
// magnitudes and (once #98 lands) its shop cost, but combat resolution and a
// Ghost_Snapshot never read it, so it rides alongside the fitting on Roster_Item
// rather than inside the runtime combat data. Ordered weakest-to-strongest so a
// consumer can compare tiers (`item.tier < .Deep`) if it wants to.
Tier :: enum {
	Splash,
	Shallow,
	Deep,
}

// Roster_Item pairs a catalog Fitting with the Tier it was authored at (#97).
// The Item Offer and (later) the Port shop sample these: an offer reads only the
// `fitting` (tier's power is already baked into the item's magnitudes), while a
// shop reads `tier` to price it. Keeping tier out of Fitting is what lets the
// same Fitting round-trip through a Ghost_Snapshot (ADR-0008) unchanged.
Roster_Item :: struct {
	fitting: Fitting,
	tier:    Tier,
}

// ITEM_ROSTER_SIZE is how many distinct items ship_item_roster hands back — the
// pool an Item Offer samples its options from (run.run_item_offer_options). Must
// stay at least run.ITEM_OFFER_OPTION_COUNT so an offer can present that many
// distinct items. The target is ADR-0012's "~50" (#97).
ITEM_ROSTER_SIZE :: 50

// ship_item_roster returns the full roster pool (issue #97, ADR-0012) as value
// data — ~50 distinct items spanning the five tag families, all three sizes and
// combat phases, the three tiers, and the whole effect vocabulary (flat /
// stat-modifier / synergy / conditional, plus multi-tag items). It is built in
// the proc body (not a top-level constant) so its synergy Selector literals
// resolve at runtime, sidestepping the const-fold regression the CI pin
// documents. Caller owns the returned array by value (Fittings hold only value
// fields and static-string names, so there is nothing to free).
//
// Every magnitude below is placeholder tuning like the rest of this file, graded
// loosely by tier (Splash light, Shallow mid, Deep heavy); the numbers are
// expected to move in playtest without touching this structure. Each item
// carries exactly one effect and a size the template can hold (Large x2 /
// Medium x3 / Small x3). The catalog is a data table — read it top to bottom
// per tier rather than as prose.
ship_item_roster :: proc() -> [ITEM_ROSTER_SIZE]Roster_Item {
	return [ITEM_ROSTER_SIZE]Roster_Item {
		// ---- Splash (Coastal-grade): light, cheap, forgiving ----
		{tier = .Splash, fitting = Fitting{name = "Deckhands", size = .Small, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Swivel Guns", size = .Small, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 3}}},
		{tier = .Splash, fitting = Fitting{name = "Deck Cannon", size = .Medium, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 4}}},
		// Multi-tag: counts for both a Weapon and a Crew synergy.
		{tier = .Splash, fitting = Fitting{name = "Boarding Pikes", size = .Small, category = .Offensive, tags = {.Weapon, .Crew}, active = Effect{magnitude = 2}}},
		{tier = .Splash, fitting = Fitting{name = "Snapping Eels", size = .Small, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 3}}},
		// Stat-modifier: raises effective Durability rather than feeding a phase.
		{tier = .Splash, fitting = Fitting{name = "Iron Plating", size = .Medium, category = .Defensive, tags = {.Artifact}, passive = Effect{kind = .Modify_Durability, magnitude = 1}}},
		// Cargo family carries a stat-modifier without being a cargo filler.
		{tier = .Splash, fitting = Fitting{name = "Ballast Stones", size = .Small, category = .Defensive, tags = {.Cargo}, passive = Effect{kind = .Modify_Durability, magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Spare Rigging", size = .Small, category = .Buff, tags = {.Artifact}, passive = Effect{kind = .Modify_Speed, magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Salt Provisions", size = .Small, category = .Defensive, tags = {.Cargo}, passive = Effect{kind = .Modify_Max_HP, magnitude = 2}}},
		{tier = .Splash, fitting = Fitting{name = "Boarding Nets", size = .Small, category = .Defensive, tags = {.Crew}, active = Effect{magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Barricades", size = .Medium, category = .Defensive, tags = {.Artifact}, active = Effect{magnitude = 2}}},
		// Synergy over a Tag family: buff per Weapon aboard.
		{tier = .Splash, fitting = Fitting{name = "Powder Monkeys", size = .Small, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 1, synergy = Selector(Tag.Weapon)}}},
		// Synergy over Visibility: buff per Concealed fitting.
		{tier = .Splash, fitting = Fitting{name = "Smuggler's Crates", size = .Small, category = .Buff, tags = {.Cargo}, active = Effect{magnitude = 1, synergy = Selector(Visibility.Concealed)}}},
		// Conditional on own HP threshold.
		{tier = .Splash, fitting = Fitting{name = "War Hound", size = .Small, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 3, conditional = Condition_HP_Below{percent = 50}}}},
		// Conditional on opponent being faster.
		{tier = .Splash, fitting = Fitting{name = "Lookout Nest", size = .Small, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 2, conditional = Condition_Opponent_Faster{}}}},
		// Conditional on the round number.
		{tier = .Splash, fitting = Fitting{name = "Bilge Rats", size = .Small, category = .Buff, tags = {.Beast}, active = Effect{magnitude = 2, conditional = Condition_Round_At_Least{round = 3}}}},
		// Multi-tag flat: a crude beast-hunting weapon (Weapon + Beast).
		{tier = .Splash, fitting = Fitting{name = "Harpoon Line", size = .Small, category = .Offensive, tags = {.Weapon, .Beast}, active = Effect{magnitude = 3}}},

		// ---- Shallow (Open-Sea-grade): mid power, real trade-offs ----
		{tier = .Shallow, fitting = Fitting{name = "Long Nines", size = .Large, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 8}}},
		{tier = .Shallow, fitting = Fitting{name = "Carronade", size = .Medium, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 6}}},
		// Multi-tag flat offense (Crew + Weapon).
		{tier = .Shallow, fitting = Fitting{name = "Naval Gun Crew", size = .Medium, category = .Offensive, tags = {.Crew, .Weapon}, active = Effect{magnitude = 6}}},
		{tier = .Shallow, fitting = Fitting{name = "Sea Drake", size = .Large, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 7}}},
		{tier = .Shallow, fitting = Fitting{name = "Ramming Prow", size = .Large, category = .Offensive, tags = {.Artifact}, active = Effect{magnitude = 7}}},
		{tier = .Shallow, fitting = Fitting{name = "War Drums", size = .Small, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 3}}},
		// Stat-modifiers across all three stats.
		{tier = .Shallow, fitting = Fitting{name = "Reinforced Hull", size = .Medium, category = .Defensive, tags = {.Artifact}, passive = Effect{kind = .Modify_Durability, magnitude = 2}}},
		{tier = .Shallow, fitting = Fitting{name = "Copper Sheathing", size = .Medium, category = .Buff, tags = {.Artifact}, passive = Effect{kind = .Modify_Speed, magnitude = 2}}},
		{tier = .Shallow, fitting = Fitting{name = "Ship's Surgeon", size = .Medium, category = .Defensive, tags = {.Crew}, passive = Effect{kind = .Modify_Max_HP, magnitude = 4}}},
		// Synergy composed onto a stat-modifier: +Speed per Small fitting aboard.
		{tier = .Shallow, fitting = Fitting{name = "Outriggers", size = .Small, category = .Buff, tags = {.Artifact}, passive = Effect{kind = .Modify_Speed, magnitude = 1, synergy = Selector(Slot_Size.Small)}}},
		// Synergy over a Tag family: buff per Weapon.
		{tier = .Shallow, fitting = Fitting{name = "Gun Captain", size = .Medium, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 2, synergy = Selector(Tag.Weapon)}}},
		// Synergy over Category: offense per Offensive fitting aboard.
		{tier = .Shallow, fitting = Fitting{name = "Master Gunner", size = .Medium, category = .Offensive, tags = {.Crew}, active = Effect{magnitude = 2, synergy = Selector(Category.Offensive)}}},
		// Synergy over a Tag family: buff per Cargo aboard.
		{tier = .Shallow, fitting = Fitting{name = "Contraband Hold", size = .Medium, category = .Buff, tags = {.Cargo}, active = Effect{magnitude = 2, synergy = Selector(Tag.Cargo)}}},
		// Conditional on own HP threshold.
		{tier = .Shallow, fitting = Fitting{name = "Kraken Spawn", size = .Medium, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 8, conditional = Condition_HP_Below{percent = 50}}}},
		// Conditional on own concealment.
		{tier = .Shallow, fitting = Fitting{name = "Ghost Lantern", size = .Small, category = .Buff, tags = {.Artifact}, active = Effect{magnitude = 4, conditional = Condition_Self_Visibility{visibility = .Concealed}}}},
		// Conditional on opponent being slower (press the advantage).
		{tier = .Shallow, fitting = Fitting{name = "Storm Sails", size = .Medium, category = .Buff, tags = {.Artifact}, active = Effect{magnitude = 4, conditional = Condition_Opponent_Slower{}}}},
		// Conditional on opponent being faster (chain shot fouls a runner's rigging).
		{tier = .Shallow, fitting = Fitting{name = "Chain & Bar Shot", size = .Medium, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 7, conditional = Condition_Opponent_Faster{}}}},

		// ---- Deep (The-Deep-grade): strongest, greediest ----
		{tier = .Deep, fitting = Fitting{name = "Great Bombard", size = .Large, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 12}}},
		{tier = .Deep, fitting = Fitting{name = "Leviathan", size = .Large, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 11}}},
		// Stat-modifiers across all three stats, Deep-scaled.
		{tier = .Deep, fitting = Fitting{name = "Dragon Turtle", size = .Large, category = .Defensive, tags = {.Beast}, passive = Effect{kind = .Modify_Durability, magnitude = 3}}},
		{tier = .Deep, fitting = Fitting{name = "Adamant Bulwark", size = .Medium, category = .Defensive, tags = {.Artifact}, passive = Effect{kind = .Modify_Durability, magnitude = 3}}},
		{tier = .Deep, fitting = Fitting{name = "Enchanted Keel", size = .Medium, category = .Buff, tags = {.Artifact}, passive = Effect{kind = .Modify_Speed, magnitude = 3}}},
		{tier = .Deep, fitting = Fitting{name = "Titan's Heart", size = .Large, category = .Defensive, tags = {.Artifact}, passive = Effect{kind = .Modify_Max_HP, magnitude = 8}}},
		// Cargo family, Deep stat-modifier.
		{tier = .Deep, fitting = Fitting{name = "Treasure Vault", size = .Medium, category = .Defensive, tags = {.Cargo}, passive = Effect{kind = .Modify_Max_HP, magnitude = 6}}},
		// Synergy over a Tag family: buff per Crew aboard.
		{tier = .Deep, fitting = Fitting{name = "Admiral's Guard", size = .Medium, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 3, synergy = Selector(Tag.Crew)}}},
		// Multi-tag synergy: offense per Weapon, itself a Crew + Weapon.
		{tier = .Deep, fitting = Fitting{name = "Broadside Master", size = .Large, category = .Offensive, tags = {.Crew, .Weapon}, active = Effect{magnitude = 3, synergy = Selector(Tag.Weapon)}}},
		// Synergy over a Tag family: offense per Beast aboard.
		{tier = .Deep, fitting = Fitting{name = "Hunter's Pack", size = .Medium, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 3, synergy = Selector(Tag.Beast)}}},
		// Synergy over Slot_Size: buff per Large fitting aboard.
		{tier = .Deep, fitting = Fitting{name = "Flagship Colors", size = .Medium, category = .Buff, tags = {.Artifact}, active = Effect{magnitude = 3, synergy = Selector(Slot_Size.Large)}}},
		// Synergy over Visibility: buff per Concealed fitting aboard.
		{tier = .Deep, fitting = Fitting{name = "Storm Caller", size = .Small, category = .Buff, tags = {.Artifact}, active = Effect{magnitude = 3, synergy = Selector(Visibility.Concealed)}}},
		// Multi-tag conditional: hits hardest while concealed (Artifact + Weapon).
		{tier = .Deep, fitting = Fitting{name = "Wraith Cannon", size = .Medium, category = .Offensive, tags = {.Artifact, .Weapon}, active = Effect{magnitude = 10, conditional = Condition_Self_Visibility{visibility = .Concealed}}}},
		// Conditional on own HP threshold.
		{tier = .Deep, fitting = Fitting{name = "Cornered Beast", size = .Large, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 12, conditional = Condition_HP_Below{percent = 50}}}},
		// Conditional on the round number (siege guns warm up late).
		{tier = .Deep, fitting = Fitting{name = "Siege Battery", size = .Large, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 11, conditional = Condition_Round_At_Least{round = 5}}}},
		// Conditional on opponent being faster.
		{tier = .Deep, fitting = Fitting{name = "Sea Witch", size = .Medium, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 6, conditional = Condition_Opponent_Faster{}}}},
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
