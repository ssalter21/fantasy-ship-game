package ship

// Vertical-slice content (issue #23, ADR-0004): the one ship template, its fixed
// starting loadout, the one captain, the roster items an Offer/Shop draws from, and
// the shop-economy constants. Every magnitude here is a placeholder like the rest of
// the codebase's balance constants — expected to move in playtest.

TOP_CREW_MUSTER_MAGNITUDE :: 3
CAPTAINS_QUARTERS_DEFENSE_MAGNITUDE :: 2
GUN_DECK_OFFENSE_MAGNITUDE :: 5

// HOSTILE_FILL_PERCENT is the fraction of each empty slot's capacity a hostile stows
// with cargo (ship_fill_empty_slots_with_cargo, ADR-0020) — so a hostile's cargo, its
// weight, and thus its Speed fall out of its loadout uniformly, with no per-slot
// authoring. The player's stow is amount-driven instead (ship_stow_cargo), so the two
// rules differ by design. Pushing this toward 100% breaches the weight-floor budget;
// the floor test is the tripwire.
HOSTILE_FILL_PERCENT :: 50

// STARTING_HULL is a **scale** (ADR-0017): Hull persists all voyage with no healing
// across ~5 fights, so a fight must cost enough of the pool to stay expressible at
// integer granularity over the rounds it lasts. Everything denominated in Hull scales
// with it — the roster's Modify_Max_Hull items and Trade's Hull-denominated swings
// (voyage.odin). **Durability does not** — it is denominated in raw damage, which is
// why STARTING_DURABILITY stays small and independent of this.
STARTING_HULL :: 100
STARTING_DURABILITY :: 2

// STARTING_SPEED is the Speed the starting ship **reads**, not a field it carries
// (ADR-0020): Speed is derived — `base + Σ modifiers − weight/10`. It is the
// calibration target BASE_SPEED is solved against.
STARTING_SPEED :: 4

// BASE_SPEED is the uniform `base` term every ship's Speed is read from (ADR-0020):
// `effective = BASE_SPEED + Σ Modify_Speed − weight/10`. A **calibration, not a free
// parameter** — BASE_SPEED = STARTING_SPEED + the starting ship's weight / 10 — solved
// so the starting ship (its loadout plus its stowed cargo) reads exactly STARTING_SPEED,
// an empty hold reads faster, and a full hold reads 0 ("sails in"). The same base is set
// on the player and on every hostile, whose Speed then falls out of its weight like the
// player's. the_starting_ship_reads_the_starting_speed pins the calibration; if a
// starting fitting's weight moves, that test re-solves this.
BASE_SPEED :: 16

// STARTING_CARGO is the cargo a fresh ship is stowed with, and CAPTAIN_STARTING_CARGO
// the extra the one captain names on top (ADR-0020): 40 + 10 stowed as real cargo in
// the holds (ship_stow_cargo), not a Ship field. The split is what makes the captain
// lever live rather than ornamental — the captain names part of the amount, and it
// lands as real cargo in the hull's headroom. "A full cargo" is derived from this sum.
STARTING_CARGO :: 40
CAPTAIN_STARTING_CARGO :: 10

// The three starting fittings (issue #23) that fill the ship template's exposed slots.
// Their category assignment gives the starting loadout one active effect per round phase
// (ADR-0006): Top Crew musters, Captain's Quarters braces, Gun Deck fires. Each sits in
// exactly one Tag family (#90). The upgraded variants inherit these through
// ship_fitting_upgraded, which copies the base fitting whole.
ship_fitting_top_crew :: proc() -> Fitting {
	return Fitting{name = "Top Crew", size = .Medium, weight = 16, category = .Muster, tags = {.Crew}, active = Effect{magnitude = TOP_CREW_MUSTER_MAGNITUDE}}
}

ship_fitting_captains_quarters :: proc() -> Fitting {
	return Fitting{name = "Captain's Quarters", size = .Medium, weight = 18, category = .Brace, tags = {.Crew}, active = Effect{magnitude = CAPTAINS_QUARTERS_DEFENSE_MAGNITUDE}}
}

ship_fitting_gun_deck :: proc() -> Fitting {
	return Fitting{name = "Gun Deck", size = .Large, weight = 38, category = .Fire, tags = {.Weapon}, active = Effect{magnitude = GUN_DECK_OFFENSE_MAGNITUDE}}
}

// ship_fitting_upgraded is the shared shape behind the three upgraded-variant procs
// below: an upgraded variant keeps its base's size/category and adds bonus on top of
// the base magnitude. bonus is a caller-supplied scale (issue #23: a deeper node's
// upgrade is worth more, and a PvE opponent's gun deck scales the same way), not a
// fixed constant.
ship_fitting_upgraded :: proc(base: Fitting, upgraded_name: string, bonus: int) -> Fitting {
	f := base
	f.name = upgraded_name
	base_active, _ := base.active.?
	// Carry the base effect's kind through unchanged (all three starting fittings are
	// Phase_Contribution) so an upgrade only scales magnitude.
	f.active = Effect{kind = base_active.kind, magnitude = base_active.magnitude + Magnitude(bonus)}
	return f
}

ship_fitting_upgraded_top_crew :: proc(bonus: int) -> Fitting {
	return ship_fitting_upgraded(ship_fitting_top_crew(), "Upgraded Top Crew", bonus)
}

ship_fitting_upgraded_captains_quarters :: proc(bonus: int) -> Fitting {
	return ship_fitting_upgraded(ship_fitting_captains_quarters(), "Upgraded Captain's Quarters", bonus)
}

ship_fitting_upgraded_gun_deck :: proc(bonus: int) -> Fitting {
	return ship_fitting_upgraded(ship_fitting_gun_deck(), "Upgraded Gun Deck", bonus)
}

// Tier is the catalog-authoring power/cost grade a roster item is written at (ADR-0012):
// Splash (lightest) → Shallow → Deep (strongest). Deliberately *not* a field on Fitting:
// tier scales an item's authored magnitudes and its shop cost, but combat resolution and
// a Ghost_Snapshot never read it, so it rides alongside the fitting on Roster_Item rather
// than inside the runtime combat data. Ordered weakest-to-strongest so a consumer can
// compare tiers (`item.tier < .Deep`).
Tier :: enum {
	Splash,
	Shallow,
	Deep,
}

// Roster_Item pairs a catalog Fitting with the Tier it was authored at. An Item Offer
// reads only the `fitting` (tier's power is already baked into the item's magnitudes),
// while a shop reads `tier` to price it (ship_item_cost). Keeping tier out of Fitting is
// what lets the same Fitting round-trip through a Ghost_Snapshot (ADR-0008) unchanged.
Roster_Item :: struct {
	fitting: Fitting,
	tier:    Tier,
}

// ITEM_COST_SPLASH / _SHALLOW / _DEEP are a roster item's Port-shop price by its authored
// Tier (ADR-0012: "tier scales an item's power and its shop cost"), graded
// weakest-to-strongest like the tiers themselves and scaled against the starting cargo so
// the fixed budget bites — an unaffordable item is a real, reachable state. Placeholder
// economy tuning like every other balance constant here.
ITEM_COST_SPLASH :: 10
ITEM_COST_SHALLOW :: 25
ITEM_COST_DEEP :: 45

// ship_item_cost prices a roster item for a Port shop from its Tier — the one place tier
// becomes cargo, so the shop's stock carries a plain int cost and nothing downstream
// re-derives it. A Fitting has no tier of its own (it rides on Roster_Item), so a shop
// must price an item while it still has the Roster_Item in hand.
ship_item_cost :: proc(tier: Tier) -> int {
	switch tier {
	case .Splash:
		return ITEM_COST_SPLASH
	case .Shallow:
		return ITEM_COST_SHALLOW
	case .Deep:
		return ITEM_COST_DEEP
	}
	return 0
}

// ITEM_ROSTER_SIZE is how many distinct items ship_item_roster hands back — the pool an
// Item Offer samples its options from (voyage.voyage_item_offer_options). Must stay at
// least voyage.ITEM_OFFER_OPTION_COUNT so an offer can present that many distinct items.
ITEM_ROSTER_SIZE :: 50

// ship_item_roster returns the full roster pool (ADR-0012) as value data. It is built in
// the proc body (not a top-level constant) so its synergy Selector literals resolve at
// runtime, sidestepping the const-fold regression the CI pin documents. Caller owns the
// returned array by value — Fittings hold only value fields and static-string names, so
// there is nothing to free.
//
// Authoring invariants every entry must satisfy: exactly one effect, a size the template
// can hold, and a weight in its size band (which decides what the item costs a ship in
// Speed, via ship_fitting_weight → ship_effective_speed). Magnitudes are placeholders,
// graded loosely by tier. Read it as a data table, top to bottom per tier.
ship_item_roster :: proc() -> [ITEM_ROSTER_SIZE]Roster_Item {
	return [ITEM_ROSTER_SIZE]Roster_Item {
		// ---- Splash ----
		{tier = .Splash, fitting = Fitting{name = "Deckhands", size = .Small, weight = 6, category = .Muster, tags = {.Crew}, active = Effect{magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Swivel Guns", size = .Small, weight = 8, category = .Fire, tags = {.Weapon}, active = Effect{magnitude = 3}}},
		{tier = .Splash, fitting = Fitting{name = "Deck Cannon", size = .Medium, weight = 18, category = .Fire, tags = {.Weapon}, active = Effect{magnitude = 4}}},
		{tier = .Splash, fitting = Fitting{name = "Boarding Pikes", size = .Small, weight = 6, category = .Fire, tags = {.Weapon, .Crew}, active = Effect{magnitude = 2}}},
		{tier = .Splash, fitting = Fitting{name = "Snapping Eels", size = .Small, weight = 7, category = .Fire, tags = {.Beast}, active = Effect{magnitude = 3}}},
		{tier = .Splash, fitting = Fitting{name = "Iron Plating", size = .Medium, weight = 24, category = .Brace, tags = {.Artifact}, passive = Effect{kind = .Modify_Durability, magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Ballast Stones", size = .Small, weight = 12, category = .Brace, tags = {.Cargo}, passive = Effect{kind = .Modify_Durability, magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Spare Rigging", size = .Small, weight = 5, category = .Muster, tags = {.Artifact}, passive = Effect{kind = .Modify_Speed, magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Salt Provisions", size = .Small, weight = 7, category = .Brace, tags = {.Cargo}, passive = Effect{kind = .Modify_Max_Hull, magnitude = 8}}},
		{tier = .Splash, fitting = Fitting{name = "Boarding Nets", size = .Small, weight = 5, category = .Brace, tags = {.Crew}, active = Effect{magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Barricades", size = .Medium, weight = 20, category = .Brace, tags = {.Artifact}, active = Effect{magnitude = 2}}},
		{tier = .Splash, fitting = Fitting{name = "Powder Monkeys", size = .Small, weight = 6, category = .Muster, tags = {.Crew}, active = Effect{magnitude = 1, synergy = Selector(Tag.Weapon)}}},
		{tier = .Splash, fitting = Fitting{name = "Smuggler's Crates", size = .Small, weight = 7, category = .Muster, tags = {.Cargo}, active = Effect{magnitude = 1, synergy = Selector(Visibility.Concealed)}}},
		{tier = .Splash, fitting = Fitting{name = "War Hound", size = .Small, weight = 7, category = .Fire, tags = {.Beast}, active = Effect{magnitude = 3, conditional = Condition_Hull_Below{percent = 50}}}},
		{tier = .Splash, fitting = Fitting{name = "Lookout Nest", size = .Small, weight = 5, category = .Muster, tags = {.Crew}, active = Effect{magnitude = 2, conditional = Condition_Opponent_Faster{}}}},
		{tier = .Splash, fitting = Fitting{name = "Bilge Rats", size = .Small, weight = 5, category = .Muster, tags = {.Beast}, active = Effect{magnitude = 2, conditional = Condition_Round_At_Least{round = 3}}}},
		{tier = .Splash, fitting = Fitting{name = "Harpoon Line", size = .Small, weight = 6, category = .Fire, tags = {.Weapon, .Beast}, active = Effect{magnitude = 3}}},

		// ---- Shallow ----
		{tier = .Shallow, fitting = Fitting{name = "Long Nines", size = .Large, weight = 42, category = .Fire, tags = {.Weapon}, active = Effect{magnitude = 8}}},
		{tier = .Shallow, fitting = Fitting{name = "Carronade", size = .Medium, weight = 22, category = .Fire, tags = {.Weapon}, active = Effect{magnitude = 6}}},
		{tier = .Shallow, fitting = Fitting{name = "Naval Gun Crew", size = .Medium, weight = 20, category = .Fire, tags = {.Crew, .Weapon}, active = Effect{magnitude = 6}}},
		{tier = .Shallow, fitting = Fitting{name = "Sea Drake", size = .Large, weight = 34, category = .Fire, tags = {.Beast}, active = Effect{magnitude = 7}}},
		{tier = .Shallow, fitting = Fitting{name = "Ramming Prow", size = .Large, weight = 40, category = .Fire, tags = {.Artifact}, active = Effect{magnitude = 7}}},
		{tier = .Shallow, fitting = Fitting{name = "War Drums", size = .Small, weight = 6, category = .Muster, tags = {.Crew}, active = Effect{magnitude = 3}}},
		{tier = .Shallow, fitting = Fitting{name = "Reinforced Hull", size = .Medium, weight = 25, category = .Brace, tags = {.Artifact}, passive = Effect{kind = .Modify_Durability, magnitude = 2}}},
		{tier = .Shallow, fitting = Fitting{name = "Copper Sheathing", size = .Medium, weight = 16, category = .Muster, tags = {.Artifact}, passive = Effect{kind = .Modify_Speed, magnitude = 2}}},
		{tier = .Shallow, fitting = Fitting{name = "Ship's Surgeon", size = .Medium, weight = 16, category = .Brace, tags = {.Crew}, passive = Effect{kind = .Modify_Max_Hull, magnitude = 16}}},
		{tier = .Shallow, fitting = Fitting{name = "Outriggers", size = .Small, weight = 5, category = .Muster, tags = {.Artifact}, passive = Effect{kind = .Modify_Speed, magnitude = 1, synergy = Selector(Slot_Size.Small)}}},
		{tier = .Shallow, fitting = Fitting{name = "Gun Captain", size = .Medium, weight = 16, category = .Muster, tags = {.Crew}, active = Effect{magnitude = 2, synergy = Selector(Tag.Weapon)}}},
		{tier = .Shallow, fitting = Fitting{name = "Master Gunner", size = .Medium, weight = 16, category = .Fire, tags = {.Crew}, active = Effect{magnitude = 2, synergy = Selector(Category.Fire)}}},
		{tier = .Shallow, fitting = Fitting{name = "Contraband Hold", size = .Medium, weight = 18, category = .Muster, tags = {.Cargo}, active = Effect{magnitude = 2, synergy = Selector(Tag.Cargo)}}},
		{tier = .Shallow, fitting = Fitting{name = "Kraken Spawn", size = .Medium, weight = 20, category = .Fire, tags = {.Beast}, active = Effect{magnitude = 8, conditional = Condition_Hull_Below{percent = 50}}}},
		{tier = .Shallow, fitting = Fitting{name = "Ghost Lantern", size = .Small, weight = 5, category = .Muster, tags = {.Artifact}, active = Effect{magnitude = 4, conditional = Condition_Self_Visibility{visibility = .Concealed}}}},
		{tier = .Shallow, fitting = Fitting{name = "Storm Sails", size = .Medium, weight = 15, category = .Muster, tags = {.Artifact}, active = Effect{magnitude = 4, conditional = Condition_Opponent_Slower{}}}},
		{tier = .Shallow, fitting = Fitting{name = "Chain & Bar Shot", size = .Medium, weight = 21, category = .Fire, tags = {.Weapon}, active = Effect{magnitude = 7, conditional = Condition_Opponent_Faster{}}}},

		// ---- Deep ----
		{tier = .Deep, fitting = Fitting{name = "Great Bombard", size = .Large, weight = 45, category = .Fire, tags = {.Weapon}, active = Effect{magnitude = 12}}},
		{tier = .Deep, fitting = Fitting{name = "Leviathan", size = .Large, weight = 38, category = .Fire, tags = {.Beast}, active = Effect{magnitude = 11}}},
		{tier = .Deep, fitting = Fitting{name = "Dragon Turtle", size = .Large, weight = 40, category = .Brace, tags = {.Beast}, passive = Effect{kind = .Modify_Durability, magnitude = 3}}},
		{tier = .Deep, fitting = Fitting{name = "Adamant Bulwark", size = .Medium, weight = 25, category = .Brace, tags = {.Artifact}, passive = Effect{kind = .Modify_Durability, magnitude = 3}}},
		{tier = .Deep, fitting = Fitting{name = "Enchanted Keel", size = .Medium, weight = 15, category = .Muster, tags = {.Artifact}, passive = Effect{kind = .Modify_Speed, magnitude = 3}}},
		{tier = .Deep, fitting = Fitting{name = "Titan's Heart", size = .Large, weight = 36, category = .Brace, tags = {.Artifact}, passive = Effect{kind = .Modify_Max_Hull, magnitude = 32}}},
		{tier = .Deep, fitting = Fitting{name = "Treasure Vault", size = .Medium, weight = 22, category = .Brace, tags = {.Cargo}, passive = Effect{kind = .Modify_Max_Hull, magnitude = 24}}},
		{tier = .Deep, fitting = Fitting{name = "Admiral's Guard", size = .Medium, weight = 17, category = .Muster, tags = {.Crew}, active = Effect{magnitude = 3, synergy = Selector(Tag.Crew)}}},
		{tier = .Deep, fitting = Fitting{name = "Broadside Master", size = .Large, weight = 36, category = .Fire, tags = {.Crew, .Weapon}, active = Effect{magnitude = 3, synergy = Selector(Tag.Weapon)}}},
		{tier = .Deep, fitting = Fitting{name = "Hunter's Pack", size = .Medium, weight = 18, category = .Fire, tags = {.Beast}, active = Effect{magnitude = 3, synergy = Selector(Tag.Beast)}}},
		{tier = .Deep, fitting = Fitting{name = "Flagship Colors", size = .Medium, weight = 15, category = .Muster, tags = {.Artifact}, active = Effect{magnitude = 3, synergy = Selector(Slot_Size.Large)}}},
		{tier = .Deep, fitting = Fitting{name = "Storm Caller", size = .Small, weight = 6, category = .Muster, tags = {.Artifact}, active = Effect{magnitude = 3, synergy = Selector(Visibility.Concealed)}}},
		{tier = .Deep, fitting = Fitting{name = "Wraith Cannon", size = .Medium, weight = 22, category = .Fire, tags = {.Artifact, .Weapon}, active = Effect{magnitude = 10, conditional = Condition_Self_Visibility{visibility = .Concealed}}}},
		{tier = .Deep, fitting = Fitting{name = "Cornered Beast", size = .Large, weight = 38, category = .Fire, tags = {.Beast}, active = Effect{magnitude = 12, conditional = Condition_Hull_Below{percent = 50}}}},
		{tier = .Deep, fitting = Fitting{name = "Siege Battery", size = .Large, weight = 44, category = .Fire, tags = {.Weapon}, active = Effect{magnitude = 11, conditional = Condition_Round_At_Least{round = 5}}}},
		{tier = .Deep, fitting = Fitting{name = "Sea Witch", size = .Medium, weight = 16, category = .Muster, tags = {.Crew}, active = Effect{magnitude = 6, conditional = Condition_Opponent_Faster{}}}},
	}
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

// ship_fit_first_empty_slot fits `fitting` into the first still-empty slot whose size
// matches it, reporting false if the layout has no room left for that size. It is what
// lets a caller author a loadout as an ordered *list of fittings* rather than as slot
// assignments — the hostile roster names the items an archetype carries and leaves
// placement to this, so an archetype survives a template resize without re-indexing.
//
// **First-empty is a content-visible rule, not an implementation detail.** The template
// lists its slots exposed-first within each size, so earlier items in a loadout land in
// exposed slots and later ones fall back to the concealed hold. Since visibility drives
// real effects — Condition_Self_Visibility, a Selector(Visibility.Concealed) synergy —
// *order is authoring*: an item authored later lands concealed.
ship_fit_first_empty_slot :: proc(layout: []Layout_Slot, fitting: Fitting) -> bool {
	for &layout_slot in layout {
		if _, occupied := layout_slot.fitting.?; occupied {
			continue
		}
		if ship_fit(&layout_slot, fitting) {
			return true
		}
	}
	return false
}

// ship_fitting_scaled returns a copy of base with `bonus` added to its effect magnitude —
// the Item Offer's zone-and-depth quality knob applied to a roster item (issue #96), the
// additive analogue of ship_fitting_upgraded's per-node scaling. bonus lands on whichever
// of the passive/active effect the item carries (roster items carry exactly one), leaving
// the effect's kind, selector, and condition intact so only its strength moves. A cargo
// filler (no effect) is returned unchanged.
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

// ship_fitting_output_scaled returns a copy of base with its combat **output** scaled to
// `percent` percent of what was authored — the multiplicative sibling of
// ship_fitting_scaled's additive bonus, and the shape core/voyage's Fight stakes reads with
// (issue #165: an additive bonus can only ever add). 100 returns the fitting as authored.
//
// **Only an active Phase_Contribution effect moves** — combat_phase_output sums exactly
// these, while the Modify_* kinds act through the effective-stat readers, so a fitting's
// Speed / Durability / Max Hull contribution is not output. That distinction is load-bearing
// for the hostile roster: Category is a combat *phase*, so `.Muster` holds both muster
// fittings and every Modify_Speed item — yet a hostile's Speed is its archetype's own axis,
// not a stakes reading. A caller scaling a whole category cannot be trusted to have meant the
// speed items; this proc is what makes "scale its output" mean only that.
//
// Rounds half-up, so a scale-down cannot silently disarm the smallest fittings: magnitude 1
// at 50% is 1, not 0, and any percent >= 50 holds that. The percent lands on the **authored
// magnitude**, ahead of effect_magnitude's synergy and conditional seams, keeping the scaling
// proportional to what the fitting deals rather than the build around it: a Selector's
// per-match magnitude scales and its match count does not, so `(m x pct) x count` is
// `pct x (m x count)`. An additive bonus has no such property (see voyage_fit_hostile_loadout).
ship_fitting_output_scaled :: proc(base: Fitting, percent: int) -> Fitting {
	f := base
	if effect, ok := f.active.?; ok && effect.kind == .Phase_Contribution {
		effect.magnitude = Magnitude((int(effect.magnitude) * percent + 50) / 100)
		f.active = effect
	}
	return f
}

// ship_fitting_cargo builds a cargo fitting holding `cargo` (ADR-0020: a cargo fitting *is*
// its cargo, so stack_count carries the amount). name lets a caller flavor multiple cargo
// instances (a PvE opponent's "Spoils") without a separate fitting type; size is
// caller-supplied so cargo can fill a slot of any size under the exact-size-match fit rule
// (a larger slot's cargo is worth more — see ship_cargo_slot_contribution). cargo must be
// at least 1 — an empty hold is an *empty slot*, not a zero-count cargo fitting
// (ship_fitting_fits rejects stack_count < 1). Cargo carries the Cargo tag family.
ship_fitting_cargo :: proc(name: string, size: Slot_Size, cargo: int) -> Fitting {
	return Fitting{name = name, size = size, tags = {.Cargo}, is_cargo = true, stack_count = cargo}
}

// ship_template_layout is the vertical slice's one ship template (issue #91): 8 slots split
// 4 exposed / 4 concealed, in the three sizes the roster is authored against, with the
// three exposed combat slots sized so the starting loadout fits. Caller owns the returned
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

// ship_starting_captain is the vertical slice's one captain (issue #23).
ship_starting_captain :: proc() -> Captain {
	return Captain{name = "Captain Odessa Vane", starting_cargo_bonus = CAPTAIN_STARTING_CARGO}
}

// ship_fit_starting_loadout fits the fixed combat loadout into the exposed slots and stows
// `cargo` across the remaining slots smallest-first (ship_stow_cargo), which leaves the
// Large forecastle empty as headroom. The or_return chain means a false return signals the
// template and its starting fittings have drifted out of sync — a content bug this
// package's tests catch, not a real runtime condition. Slot-name pairing is flavor only:
// names impose no restriction on what fills them (ADR-0004).
ship_fit_starting_loadout :: proc(layout: []Layout_Slot, cargo: int) -> bool {
	ship_fit(&layout[0], ship_fitting_captains_quarters()) or_return
	ship_fit(&layout[1], ship_fitting_top_crew()) or_return
	ship_fit(&layout[2], ship_fitting_gun_deck()) or_return
	ship_stow_cargo(layout, cargo)
	return true
}

// ship_fill_empty_slots_with_cargo fills every still-empty slot of `layout` with a
// size-matching cargo filler, each stowed to HOSTILE_FILL_PERCENT of its capacity (issue
// #91): once the combat fittings are placed, all remaining slots go to cargo rather than
// sitting idle. Each filler takes its slot's own size, satisfying the exact-size-match fit
// rule, so ship_fit only fails here on a genuine content bug. This is the **hostile's**
// stow (voyage_fit_hostile_loadout); the player's is amount-driven (ship_stow_cargo), so
// the two do not share a rule. A slot filled at 50% weighs half its capacity, so this is
// what a hostile's Speed reads its weight from (ship_effective_speed).
ship_fill_empty_slots_with_cargo :: proc(layout: []Layout_Slot, name: string) -> bool {
	for &layout_slot in layout {
		if _, occupied := layout_slot.fitting.?; occupied {
			continue
		}
		fill := ship_cargo_slot_contribution(layout_slot.slot.size) * HOSTILE_FILL_PERCENT / 100
		ship_fit(&layout_slot, ship_fitting_cargo(name, layout_slot.slot.size, fill)) or_return
	}
	return true
}

// ship_starting_ship assembles the voyage's starting Ship (issue #23): the one template
// filled with its fixed loadout and stowed cargo, plus the one captain. Caller owns the
// returned Ship's layout slice.
ship_starting_ship :: proc() -> Ship {
	captain := ship_starting_captain()
	layout := ship_template_layout()
	// The captain names part of the starting cargo, so the stow amount sums STARTING_CARGO
	// and the captain's bonus, stowed into the holds.
	assert(
		ship_fit_starting_loadout(layout, STARTING_CARGO + captain.starting_cargo_bonus),
		"starting loadout: a fitting failed to fit its template slot",
	)

	return Ship{
		hull         = STARTING_HULL,
		max_hull     = STARTING_HULL,
		durability = STARTING_DURABILITY,
		speed      = BASE_SPEED,
		layout     = layout,
		captain    = captain,
	}
}
