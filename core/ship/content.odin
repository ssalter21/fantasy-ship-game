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

// HOSTILE_FILL_PERCENT is how full a hostile's spare slots are stowed with cargo
// (ship_fill_empty_slots_with_cargo, ADR-0020, #176): a flat 50% of each empty
// slot's capacity — Small 5, Medium 10, Large 20 — so a hostile's purse (and thus
// its weight, and thus its Speed) falls out of its loadout uniformly, no per-slot
// authoring. This is a **placeholder standing exactly where hostile ship templates
// will land** (#176, out of scope): templates derive richness from what kind of
// ship a hostile is, and half-full is the neutral default until then. The *player's*
// stow is amount-driven instead (ship_stow_treasure, smallest-first, #172) — the two
// rules are deliberately different (a proportional hostile fill vs a designed player
// default). Pushing this toward 100% breaches the weight-floor budget (#175); the
// floor test is the tripwire.
HOSTILE_FILL_PERCENT :: 50

// STARTING_HULL is a **scale**, and #151 (ADR-0017) found the old 20 could not
// express a survivable fight. Hull persists all run with no healing and a run meets
// ~5 fights, so a fight must cost ~20% of the pool; over the ~6 rounds a fight
// should last (the escape gate is at BASELINE_ROUND_COUNT = 5), that is 0.67 damage
// a round — below 1, the smallest number the model has. At 20 the only expressible
// outcomes were a 2-round burst and the 20-round cap, which is exactly what the
// game did.
//
// Everything denominated in Hull scales with it: the roster's four Modify_Max_Hull
// items, and Trade's two Hull-denominated swing rows (run.odin). **Durability does
// not** — it is denominated in *raw damage*, which did not move — which is why
// STARTING_DURABILITY is still 2 and #146's Durability residue is still there.
STARTING_HULL :: 100
STARTING_DURABILITY :: 2

// STARTING_SPEED is the Speed the starting ship **reads**, not a field it carries
// (ADR-0020, #158): Speed is derived now — `base + Σ modifiers − weight/10` — so
// STARTING_SPEED stopped being the Speed a ship *has* and became the Speed it
// *reads*. It is the calibration target BASE_SPEED is solved against, and the
// reference the (out-of-scope) forward-ported straddle test pins the player's
// purse to (#177). Nothing initialises a ship's raw speed field to it any more.
STARTING_SPEED :: 4

// BASE_SPEED is the uniform `base` term every ship's Speed is read from (ADR-0020,
// #158/#180): `effective = BASE_SPEED + Σ Modify_Speed − weight/10`. It is a
// **calibration, not a free parameter** — BASE_SPEED = STARTING_SPEED + the
// starting ship's weight / 10 — chosen so the starting ship (its loadout plus the
// 50-treasure purse) reads exactly STARTING_SPEED, empty holds read 9, and a full
// hold reads 0 ("sails in"). With #194's authored per-item weights the starting
// loadout weighs 72 (Captain's Quarters 18 + Top Crew 16 + Gun Deck 38) and the
// purse 50, so weight 122, 122/10 = 12, and 4 + 12 = **16 holds** — the value the
// prototype's placeholder band already predicted. Uniform across ships (#158): the
// same base is set on the player and on every hostile, whose Speed then falls out
// of its weight like the player's. the_starting_ship_reads_the_starting_speed pins
// the calibration; if a starting fitting's weight moves, that test re-solves this.
BASE_SPEED :: 16

// STARTING_CARGO is the treasure a fresh ship is stowed with, and
// CAPTAIN_STARTING_CARGO the extra the one captain (Odessa) names on top
// (ADR-0020, #172): 40 + 10 = the starting 50, no longer a Ship.starting_treasure
// field but treasure actually stowed into the holds (ship_stow_treasure). The
// 40/10 split is what makes the captain lever live rather than ornamental — the
// captain names part of the amount, and it lands as real treasure in the hull's
// headroom (ship_cargo_capacity reads 90). "A full purse" is now derived from
// this sum, not a constant (see content_test's Deep-item affordability check).
STARTING_CARGO :: 40
CAPTAIN_STARTING_CARGO :: 10

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
	return Fitting{name = "Top Crew", size = .Medium, weight = 16, category = .Buff, tags = {.Crew}, active = Effect{magnitude = TOP_CREW_BUFF_MAGNITUDE}}
}

ship_fitting_captains_quarters :: proc() -> Fitting {
	return Fitting{name = "Captain's Quarters", size = .Medium, weight = 18, category = .Defensive, tags = {.Crew}, active = Effect{magnitude = CAPTAINS_QUARTERS_DEFENSE_MAGNITUDE}}
}

ship_fitting_gun_deck :: proc() -> Fitting {
	return Fitting{name = "Gun Deck", size = .Large, weight = 38, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = GUN_DECK_OFFENSE_MAGNITUDE}}
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
// The Item Offer and the Port shop sample these: an offer reads only the
// `fitting` (tier's power is already baked into the item's magnitudes), while a
// shop reads `tier` to price it (ship_item_cost). Keeping tier out of Fitting is
// what lets the same Fitting round-trip through a Ghost_Snapshot (ADR-0008)
// unchanged.
Roster_Item :: struct {
	fitting: Fitting,
	tier:    Tier,
}

// ITEM_COST_SPLASH / _SHALLOW / _DEEP are the Port-shop prices of a roster item
// by its authored Tier (#98, ADR-0012: "tier scales an item's power and its shop
// cost"). Graded weakest-to-strongest like the tiers themselves, and scaled
// against the starting purse (STARTING_CARGO + CAPTAIN_STARTING_CARGO = 50) so
// the fixed budget actually bites — the starting purse buys one Deep item (and
// little else), a couple of Shallow ones, or a
// handful of Splash ones, so an unaffordable item is a real, reachable state
// rather than a theoretical one. Placeholder economy tuning like every other
// balance constant here, expected to move in playtest (ADR-0012).
ITEM_COST_SPLASH :: 10
ITEM_COST_SHALLOW :: 25
ITEM_COST_DEEP :: 45

// ship_item_cost prices a roster item for a Port shop from its Tier (#98): the
// one place tier becomes treasure, so the shop's stock carries a plain int cost
// and nothing downstream re-derives it. A Fitting has no tier of its own (it
// rides on Roster_Item), so a shop prices an item while it still has the
// Roster_Item in hand, before it decays to a bare Fitting in the stock.
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
// Medium x3 / Small x3). Each also authors a **weight** (#194) in its size band
// (Large 30-45, Medium 15-25, Small 5-12) — a per-item balance choice that decides
// what the item costs a ship in Speed (ship_fitting_weight → ship_effective_speed):
// a big gun is permanently heavy, a beast lighter than iron of the same size. The
// catalog is a data table — read it top to bottom per tier rather than as prose.
ship_item_roster :: proc() -> [ITEM_ROSTER_SIZE]Roster_Item {
	return [ITEM_ROSTER_SIZE]Roster_Item {
		// ---- Splash (Coastal-grade): light, cheap, forgiving ----
		{tier = .Splash, fitting = Fitting{name = "Deckhands", size = .Small, weight = 6, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Swivel Guns", size = .Small, weight = 8, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 3}}},
		{tier = .Splash, fitting = Fitting{name = "Deck Cannon", size = .Medium, weight = 18, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 4}}},
		// Multi-tag: counts for both a Weapon and a Crew synergy.
		{tier = .Splash, fitting = Fitting{name = "Boarding Pikes", size = .Small, weight = 6, category = .Offensive, tags = {.Weapon, .Crew}, active = Effect{magnitude = 2}}},
		{tier = .Splash, fitting = Fitting{name = "Snapping Eels", size = .Small, weight = 7, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 3}}},
		// Stat-modifier: raises effective Durability rather than feeding a phase.
		{tier = .Splash, fitting = Fitting{name = "Iron Plating", size = .Medium, weight = 24, category = .Defensive, tags = {.Artifact}, passive = Effect{kind = .Modify_Durability, magnitude = 1}}},
		// Cargo family carries a stat-modifier without being a cargo filler.
		{tier = .Splash, fitting = Fitting{name = "Ballast Stones", size = .Small, weight = 12, category = .Defensive, tags = {.Cargo}, passive = Effect{kind = .Modify_Durability, magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Spare Rigging", size = .Small, weight = 5, category = .Buff, tags = {.Artifact}, passive = Effect{kind = .Modify_Speed, magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Salt Provisions", size = .Small, weight = 7, category = .Defensive, tags = {.Cargo}, passive = Effect{kind = .Modify_Max_Hull, magnitude = 8}}},
		{tier = .Splash, fitting = Fitting{name = "Boarding Nets", size = .Small, weight = 5, category = .Defensive, tags = {.Crew}, active = Effect{magnitude = 1}}},
		{tier = .Splash, fitting = Fitting{name = "Barricades", size = .Medium, weight = 20, category = .Defensive, tags = {.Artifact}, active = Effect{magnitude = 2}}},
		// Synergy over a Tag family: buff per Weapon aboard.
		{tier = .Splash, fitting = Fitting{name = "Powder Monkeys", size = .Small, weight = 6, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 1, synergy = Selector(Tag.Weapon)}}},
		// Synergy over Visibility: buff per Concealed fitting.
		{tier = .Splash, fitting = Fitting{name = "Smuggler's Crates", size = .Small, weight = 7, category = .Buff, tags = {.Cargo}, active = Effect{magnitude = 1, synergy = Selector(Visibility.Concealed)}}},
		// Conditional on own Hull threshold.
		{tier = .Splash, fitting = Fitting{name = "War Hound", size = .Small, weight = 7, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 3, conditional = Condition_Hull_Below{percent = 50}}}},
		// Conditional on opponent being faster.
		{tier = .Splash, fitting = Fitting{name = "Lookout Nest", size = .Small, weight = 5, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 2, conditional = Condition_Opponent_Faster{}}}},
		// Conditional on the round number.
		{tier = .Splash, fitting = Fitting{name = "Bilge Rats", size = .Small, weight = 5, category = .Buff, tags = {.Beast}, active = Effect{magnitude = 2, conditional = Condition_Round_At_Least{round = 3}}}},
		// Multi-tag flat: a crude beast-hunting weapon (Weapon + Beast).
		{tier = .Splash, fitting = Fitting{name = "Harpoon Line", size = .Small, weight = 6, category = .Offensive, tags = {.Weapon, .Beast}, active = Effect{magnitude = 3}}},

		// ---- Shallow (Open-Sea-grade): mid power, real trade-offs ----
		{tier = .Shallow, fitting = Fitting{name = "Long Nines", size = .Large, weight = 42, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 8}}},
		{tier = .Shallow, fitting = Fitting{name = "Carronade", size = .Medium, weight = 22, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 6}}},
		// Multi-tag flat offense (Crew + Weapon).
		{tier = .Shallow, fitting = Fitting{name = "Naval Gun Crew", size = .Medium, weight = 20, category = .Offensive, tags = {.Crew, .Weapon}, active = Effect{magnitude = 6}}},
		{tier = .Shallow, fitting = Fitting{name = "Sea Drake", size = .Large, weight = 34, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 7}}},
		{tier = .Shallow, fitting = Fitting{name = "Ramming Prow", size = .Large, weight = 40, category = .Offensive, tags = {.Artifact}, active = Effect{magnitude = 7}}},
		{tier = .Shallow, fitting = Fitting{name = "War Drums", size = .Small, weight = 6, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 3}}},
		// Stat-modifiers across all three stats.
		{tier = .Shallow, fitting = Fitting{name = "Reinforced Hull", size = .Medium, weight = 25, category = .Defensive, tags = {.Artifact}, passive = Effect{kind = .Modify_Durability, magnitude = 2}}},
		{tier = .Shallow, fitting = Fitting{name = "Copper Sheathing", size = .Medium, weight = 16, category = .Buff, tags = {.Artifact}, passive = Effect{kind = .Modify_Speed, magnitude = 2}}},
		{tier = .Shallow, fitting = Fitting{name = "Ship's Surgeon", size = .Medium, weight = 16, category = .Defensive, tags = {.Crew}, passive = Effect{kind = .Modify_Max_Hull, magnitude = 16}}},
		// Synergy composed onto a stat-modifier: +Speed per Small fitting aboard.
		{tier = .Shallow, fitting = Fitting{name = "Outriggers", size = .Small, weight = 5, category = .Buff, tags = {.Artifact}, passive = Effect{kind = .Modify_Speed, magnitude = 1, synergy = Selector(Slot_Size.Small)}}},
		// Synergy over a Tag family: buff per Weapon.
		{tier = .Shallow, fitting = Fitting{name = "Gun Captain", size = .Medium, weight = 16, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 2, synergy = Selector(Tag.Weapon)}}},
		// Synergy over Category: offense per Offensive fitting aboard.
		{tier = .Shallow, fitting = Fitting{name = "Master Gunner", size = .Medium, weight = 16, category = .Offensive, tags = {.Crew}, active = Effect{magnitude = 2, synergy = Selector(Category.Offensive)}}},
		// Synergy over a Tag family: buff per Cargo aboard.
		{tier = .Shallow, fitting = Fitting{name = "Contraband Hold", size = .Medium, weight = 18, category = .Buff, tags = {.Cargo}, active = Effect{magnitude = 2, synergy = Selector(Tag.Cargo)}}},
		// Conditional on own Hull threshold.
		{tier = .Shallow, fitting = Fitting{name = "Kraken Spawn", size = .Medium, weight = 20, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 8, conditional = Condition_Hull_Below{percent = 50}}}},
		// Conditional on own concealment.
		{tier = .Shallow, fitting = Fitting{name = "Ghost Lantern", size = .Small, weight = 5, category = .Buff, tags = {.Artifact}, active = Effect{magnitude = 4, conditional = Condition_Self_Visibility{visibility = .Concealed}}}},
		// Conditional on opponent being slower (press the advantage).
		{tier = .Shallow, fitting = Fitting{name = "Storm Sails", size = .Medium, weight = 15, category = .Buff, tags = {.Artifact}, active = Effect{magnitude = 4, conditional = Condition_Opponent_Slower{}}}},
		// Conditional on opponent being faster (chain shot fouls a runner's rigging).
		{tier = .Shallow, fitting = Fitting{name = "Chain & Bar Shot", size = .Medium, weight = 21, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 7, conditional = Condition_Opponent_Faster{}}}},

		// ---- Deep (The-Deep-grade): strongest, greediest ----
		{tier = .Deep, fitting = Fitting{name = "Great Bombard", size = .Large, weight = 45, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 12}}},
		{tier = .Deep, fitting = Fitting{name = "Leviathan", size = .Large, weight = 38, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 11}}},
		// Stat-modifiers across all three stats, Deep-scaled.
		{tier = .Deep, fitting = Fitting{name = "Dragon Turtle", size = .Large, weight = 40, category = .Defensive, tags = {.Beast}, passive = Effect{kind = .Modify_Durability, magnitude = 3}}},
		{tier = .Deep, fitting = Fitting{name = "Adamant Bulwark", size = .Medium, weight = 25, category = .Defensive, tags = {.Artifact}, passive = Effect{kind = .Modify_Durability, magnitude = 3}}},
		{tier = .Deep, fitting = Fitting{name = "Enchanted Keel", size = .Medium, weight = 15, category = .Buff, tags = {.Artifact}, passive = Effect{kind = .Modify_Speed, magnitude = 3}}},
		{tier = .Deep, fitting = Fitting{name = "Titan's Heart", size = .Large, weight = 36, category = .Defensive, tags = {.Artifact}, passive = Effect{kind = .Modify_Max_Hull, magnitude = 32}}},
		// Cargo family, Deep stat-modifier.
		{tier = .Deep, fitting = Fitting{name = "Treasure Vault", size = .Medium, weight = 22, category = .Defensive, tags = {.Cargo}, passive = Effect{kind = .Modify_Max_Hull, magnitude = 24}}},
		// Synergy over a Tag family: buff per Crew aboard.
		{tier = .Deep, fitting = Fitting{name = "Admiral's Guard", size = .Medium, weight = 17, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 3, synergy = Selector(Tag.Crew)}}},
		// Multi-tag synergy: offense per Weapon, itself a Crew + Weapon.
		{tier = .Deep, fitting = Fitting{name = "Broadside Master", size = .Large, weight = 36, category = .Offensive, tags = {.Crew, .Weapon}, active = Effect{magnitude = 3, synergy = Selector(Tag.Weapon)}}},
		// Synergy over a Tag family: offense per Beast aboard.
		{tier = .Deep, fitting = Fitting{name = "Hunter's Pack", size = .Medium, weight = 18, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 3, synergy = Selector(Tag.Beast)}}},
		// Synergy over Slot_Size: buff per Large fitting aboard.
		{tier = .Deep, fitting = Fitting{name = "Flagship Colors", size = .Medium, weight = 15, category = .Buff, tags = {.Artifact}, active = Effect{magnitude = 3, synergy = Selector(Slot_Size.Large)}}},
		// Synergy over Visibility: buff per Concealed fitting aboard.
		{tier = .Deep, fitting = Fitting{name = "Storm Caller", size = .Small, weight = 6, category = .Buff, tags = {.Artifact}, active = Effect{magnitude = 3, synergy = Selector(Visibility.Concealed)}}},
		// Multi-tag conditional: hits hardest while concealed (Artifact + Weapon).
		{tier = .Deep, fitting = Fitting{name = "Wraith Cannon", size = .Medium, weight = 22, category = .Offensive, tags = {.Artifact, .Weapon}, active = Effect{magnitude = 10, conditional = Condition_Self_Visibility{visibility = .Concealed}}}},
		// Conditional on own Hull threshold.
		{tier = .Deep, fitting = Fitting{name = "Cornered Beast", size = .Large, weight = 38, category = .Offensive, tags = {.Beast}, active = Effect{magnitude = 12, conditional = Condition_Hull_Below{percent = 50}}}},
		// Conditional on the round number (siege guns warm up late).
		{tier = .Deep, fitting = Fitting{name = "Siege Battery", size = .Large, weight = 44, category = .Offensive, tags = {.Weapon}, active = Effect{magnitude = 11, conditional = Condition_Round_At_Least{round = 5}}}},
		// Conditional on opponent being faster.
		{tier = .Deep, fitting = Fitting{name = "Sea Witch", size = .Medium, weight = 16, category = .Buff, tags = {.Crew}, active = Effect{magnitude = 6, conditional = Condition_Opponent_Faster{}}}},
	}
}

// ship_item_by_name finds a roster item by its authored name — the lookup that
// lets a content table elsewhere name the items it is built from ("Long Nines")
// instead of duplicating their magnitudes or pointing at roster indices. A linear
// scan of ITEM_ROSTER_SIZE, called only at map generation, so the roster stays a
// plain authored table with no lookup structure to keep in sync with it.
//
// The (T, bool) return is the house idiom for a fallible read, but a miss here is
// a *content* bug — an author's typo — not a runtime condition, so callers assert
// rather than handle it. core/run's hostile roster (#135) is checked name by name
// by its own test, which is what turns "this compiles" into "these items exist".
ship_item_by_name :: proc(name: string) -> (item: Roster_Item, ok: bool) {
	for candidate in ship_item_roster() {
		if candidate.fitting.name == name {
			return candidate, true
		}
	}
	return {}, false
}

// ship_fit_first_empty_slot fits `fitting` into the first still-empty slot whose
// size matches it, reporting false if the layout has no room left for that size.
// It is what lets a caller author a loadout as an ordered *list of fittings*
// rather than as slot assignments — the hostile roster (#135) names the items an
// archetype carries and leaves placement to this, so an archetype survives a
// template resize (ship_template_layout) without re-indexing every entry.
//
// **First-empty is a content-visible rule, not an implementation detail.** The
// template lists its slots exposed-first within each size, so earlier items in a
// loadout land in exposed slots and later ones fall back to the concealed hold.
// Since visibility drives real effects — Condition_Self_Visibility, a
// Selector(Visibility.Concealed) synergy — *order is authoring*: an archetype that
// wants its Wraith Cannon concealed authors two other Medium items ahead of it.
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

// ship_fitting_output_scaled returns a copy of base with its combat **output**
// scaled to `percent` percent of what was authored — the multiplicative sibling of
// ship_fitting_scaled's additive bonus, and the shape core/run's Fight stakes reads
// with (issue #165: an additive bonus can only ever add, so it gives a gradient no
// way *down*). 100 returns the fitting as authored; 50 halves what it deals.
//
// **Only an active Phase_Contribution effect moves, and that is the definition of
// output rather than a courtesy.** combat_phase_output sums exactly these; the
// Modify_* kinds act through the effective-stat readers instead
// (ship_effective_speed and friends), so a fitting's Speed / Durability / Max Hull
// contribution is not output and is left exactly as authored. That distinction is
// load-bearing for the hostile roster: Category is a combat *phase*, so `.Buff`
// holds both the buff phase's fittings (Powder Monkeys) and every Modify_Speed item
// in the roster (Spare Rigging, Copper Sheathing, Outriggers, Enchanted Keel) — and
// a hostile's Speed is its archetype's axis, explicitly not a stakes reading
// (core/run's Hostile_Archetype.speed). A caller that scales a whole category
// therefore cannot be trusted to have meant the speed items; this proc is what makes
// "scale its output" mean only that.
//
// Rounds half-up, so a scale-down cannot silently disarm the roster's smallest
// fittings: Powder Monkeys' magnitude of 1 at 50% is 1, not 0. Any percent >= 50
// holds that for every authored magnitude.
//
// The percent lands on the **authored magnitude**, ahead of effect_magnitude's
// synergy and conditional seams, which is what makes the scaling proportional to
// what the fitting deals rather than to the build around it: a Selector's
// per-match magnitude scales and its match count does not, so `(m x pct) x count`
// is `pct x (m x count)`. An additive bonus has no such property — it is
// multiplied by the count (see run_fit_hostile_loadout).
ship_fitting_output_scaled :: proc(base: Fitting, percent: int) -> Fitting {
	f := base
	if effect, ok := f.active.?; ok && effect.kind == .Phase_Contribution {
		effect.magnitude = Magnitude((int(effect.magnitude) * percent + 50) / 100)
		f.active = effect
	}
	return f
}

// ship_fitting_cargo builds a cargo fitting holding `treasure` (ADR-0020: a
// cargo fitting *is* its treasure, so stack_count carries the amount — #156).
// name lets a caller flavor multiple cargo instances (e.g. a PvE opponent's
// "Spoils") without a separate fitting type (ADR-0004). size is caller-supplied
// so cargo can fill a slot of any size under the exact-size-match fit rule (issue
// #91: every empty slot, not just the small holds, can hold treasure — a larger
// slot's cargo is worth more, see ship_cargo_slot_contribution). Callers that
// stow a purse (ship_stow_treasure) pass the treasure that fits the slot;
// treasure must be at least 1 (an empty hold is an *empty slot*, #157, not a
// zero-count cargo fitting — ship_fitting_fits rejects stack_count < 1). Cargo
// carries the Cargo tag family (#90).
ship_fitting_cargo :: proc(name: string, size: Slot_Size, treasure: int) -> Fitting {
	return Fitting{name = name, size = size, tags = {.Cargo}, is_cargo = true, stack_count = treasure}
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
	return Captain{name = "Captain Odessa Vane", starting_cargo_bonus = CAPTAIN_STARTING_CARGO}
}

// ship_starting_ship assembles the run's starting Ship (issue #23): the one
// template, filled with its fixed starting loadout — Captain's Quarters and
// Top Crew in the two medium exposed slots, Gun Deck in the large exposed
// slot, the starting purse stowed into the rest (ADR-0020, #172) — plus the
// one captain. Hand-placement of Captain's Quarters into "top deck" and Top
// Crew into "top crew" is a flavor-only pairing (ADR-0004: slot names impose
// no restriction on what fills them). Caller owns the returned Ship's
// layout slice.
// ship_fit_starting_loadout fits the fixed combat loadout into ship_starting_ship's
// exposed slots (issue #54: an or_return chain — a false return means the
// template and its starting fittings have drifted out of sync, a content bug
// caught immediately by this package's own tests, not a real runtime condition)
// and stows `treasure` across the remaining slots smallest-first
// (ship_stow_treasure), which leaves the Large forecastle empty as headroom.
ship_fit_starting_loadout :: proc(layout: []Layout_Slot, treasure: int) -> bool {
	ship_fit(&layout[0], ship_fitting_captains_quarters()) or_return
	ship_fit(&layout[1], ship_fitting_top_crew()) or_return
	ship_fit(&layout[2], ship_fitting_gun_deck()) or_return
	ship_stow_treasure(layout, treasure)
	return true
}

// ship_fill_empty_slots_with_cargo fills every still-empty slot of `layout`
// with a size-matching cargo filler, each stowed to HOSTILE_FILL_PERCENT of its
// capacity (issue #91, #176: once the combat fittings are placed, all remaining
// slots — whatever their size or visibility — go to cargo rather than sitting
// idle, half-full). Each filler takes its slot's own size so it satisfies the
// exact-size-match fit rule (ADR-0004), so ship_fit only fails here on a genuine
// content bug, never a size mismatch. This is the **hostile's** stow (the PvE
// opponent's spare slots, run_fit_hostile_loadout); the player's is amount-driven
// (ship_stow_treasure), so the two no longer share a rule — a template resize needs
// no per-slot edits here, and the flat 50% is #176's placeholder for hostile ship
// templates. A slot filled at 50% weighs half its capacity, so this is what a
// hostile's Speed reads its weight from (ship_effective_speed).
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

ship_starting_ship :: proc() -> Ship {
	captain := ship_starting_captain()
	layout := ship_template_layout()
	// The captain names part of the starting purse (#172), so the stow amount is
	// STARTING_CARGO + the captain's bonus — 40 + 10 = 50, stowed into the holds.
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
