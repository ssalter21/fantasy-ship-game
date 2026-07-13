package ship

Slot_Size :: enum {
	Small,
	Medium,
	Large,
}

Visibility :: enum {
	Exposed,
	Concealed,
}

// Category is a fitting's round phase (ADR-0006): every round resolves
// Buff -> Defensive -> Offensive, and a fitting's Category is which of the
// three it triggers in. Effect's comment below says combat vocabulary
// belongs to core/combat, not this data model — Category is the deliberate
// exception: core/combat needs to group fittings by phase to resolve a
// round, and layout order (this package's data) is what fixes that
// grouping, so the enum lives here rather than as a lookup keyed some other
// way from core/combat.
Category :: enum {
	Buff,
	Defensive,
	Offensive,
}

// Tag is a fitting's family membership (#88 build-variance effort), the axis
// synergy effects will later count fittings along. It is independent of a
// fitting's combat phase (Category): a Beast may buff, defend, or attack, and
// two fittings in different phases can still share a family. Multi-tag is
// allowed but used sparingly — most fittings sit in exactly one family. No
// behavior counts on tags yet; this ticket (#90) only establishes the axis.
Tag :: enum {
	Crew,
	Weapon,
	Beast,
	Artifact,
	Cargo,
}

Slot :: struct {
	name:            string,
	size:            Slot_Size,
	base_visibility: Visibility,
}

// Magnitude is an Effect's strength (issue #54: distinct from a plain int so
// it can't be confused at a call site with an index or other bare-int
// domain value). Callers that fold it into a raw combat total cast it back
// to int explicitly (see core/combat's combat_phase_output).
Magnitude :: distinct int

// Effect_Kind is what an Effect's resolved magnitude does (issue #92). The
// zero value, Phase_Contribution, is the original bare-magnitude behavior:
// the magnitude feeds the owning fitting's combat phase (its Category, decided
// by the combat resolver — ADR-0006, core/combat). The Modify_* kinds instead
// adjust one of the owning ship's effective stats (ship_effective_durability /
// _speed / _max_hp), so a fitting can raise Durability / Speed / Max HP
// without contributing to a phase (issue #88: "fittings may modify ship
// stats"). Kept as an enum rather than a tagged union — the house idiom for a
// closed variant set — because for this ticket's closed set every kind carries
// the same payload (a single magnitude), so a union would be four identical
// variants; the enum encodes both "it's a stat modifier" and "which stat" in
// one field, avoiding a conditionally-meaningful parallel `stat` field. The
// synergy / conditional kinds of #93/#94 carry their own payload (a selector,
// a trigger); if they extend this set rather than attaching to the magnitude
// seam (effect_magnitude), revisit whether a tagged union fits better then.
Effect_Kind :: enum {
	Phase_Contribution,
	Modify_Durability,
	Modify_Speed,
	Modify_Max_HP,
}

// Effect is a fitting's data-driven passive/active contribution, resolved
// against an Effect_Context at the point of use rather than baked in as a bare
// constant (issue #92, #88). It stays plain data — no function pointers — so a
// Ghost_Snapshot (ADR-0008) can carry it. `kind` decides what the resolved
// magnitude does; `magnitude` is flat today and is the seam where later
// build-variance tickets (#88: synergy counts, battle-state conditionals) make
// magnitude context-sensitive by changing only effect_magnitude. The concrete
// fitting roster and its balance values belong to the content tickets (issue
// #23), not this data model.
Effect :: struct {
	kind:      Effect_Kind,
	magnitude: Magnitude,
}

// Effect_Context is everything an Effect may resolve its magnitude against
// (issue #92): the owning ship today. The combat battle/opponent state that
// synergy and conditional effects (issue #88) will read is the documented
// extension point — added by those tickets, not a field here yet — mirroring
// how the third visibility layer (ship_effective_visibility) is documented
// ahead of implementation.
Effect_Context :: struct {
	owner: ^Ship,
}

// effect_magnitude resolves `effect`'s magnitude against `ctx` (issue #92).
// Flat today — it returns the stored constant and ignores ctx — but every
// magnitude read (combat phase output, the effective-stat readers) goes
// through here, so later tickets (#88) can make magnitude context-sensitive
// (synergy counts, conditionals) by changing only this proc, leaving combat
// and the stat readers untouched.
effect_magnitude :: proc(effect: Effect, ctx: Effect_Context) -> Magnitude {
	return effect.magnitude
}

// ship_effect_context builds the Effect_Context an effect resolves against for
// ship s (issue #92). The single place that shape is constructed — combat's
// phase output and the effective-stat readers both call it — so the
// battle/opponent fields the synergy/conditional tickets (#93/#94) add land
// here, not at every resolve site.
ship_effect_context :: proc(s: ^Ship) -> Effect_Context {
	return Effect_Context{owner = s}
}

Fitting :: struct {
	name:                string,
	size:                Slot_Size,
	// category is which round phase (ADR-0006) this fitting's active effect
	// triggers in. Meaningless for cargo, which carries no effects.
	category:            Category,
	// tags is the fitting's family membership (see Tag): a set, since a fitting
	// may belong to more than one family. Empty for a fitting that carries none.
	tags:                bit_set[Tag],
	visibility_override: Maybe(Visibility),
	passive:             Maybe(Effect),
	active:              Maybe(Effect),
	// is_cargo marks the one special-cased fitting kind (ADR-0004): stackable
	// and effect-less, and the thing ship_cargo_capacity looks for when
	// adjusting the ship's baseline cargo stat. ship_fit enforces both halves
	// of that special-casing: no passive/active effects, and a stack_count
	// of at least 1.
	is_cargo:            bool,
	// stack_count is the quantity of stacked cargo units this fitting
	// represents (ADR-0004: cargo is "stackable"). Only meaningful when
	// is_cargo is true; ignored for every other fitting kind.
	stack_count:         int,
}

Layout_Slot :: struct {
	slot:    Slot,
	fitting: Maybe(Fitting),
}

// Slot_Index identifies a Layout_Slot by position in a Ship's layout (issue
// #54: distinct from a plain int so a slot position can't be passed where a
// node id or upgrade option index belongs, e.g. Command_Jettison_Cargo's
// slot_index in core/combat).
Slot_Index :: distinct int

// Ship holds the run-persistent top-level stats (HP, Durability, Speed,
// starting treasure) plus the fixed layout of slots that carries its combat
// power. See CONTEXT.md's Ship & crew model glossary and ADR-0004.
Ship :: struct {
	hp:                  int,
	// max_hp is the ship's undamaged HP ceiling (ADR-0008): hp is the
	// run-persistent value combat depletes, max_hp never changes during a
	// run and is what a Ghost_Snapshot resets hp to on capture.
	max_hp:              int,
	durability:          int,
	speed:               int,
	starting_treasure:   int,
	base_cargo_capacity: int,
	layout:              []Layout_Slot,
	// captain is the run-start ship<->captain relationship (issue #18): a
	// captain can influence a ship's slot limits/structure and grants
	// additional manual per-round captain actions. The vertical slice's one
	// concrete captain (issue #23) is ship_starting_captain in content.odin.
	captain:             Maybe(Captain),
}

// ship_fit installs `fitting` into `layout_slot` under the exact-size-match
// fit rule (ADR-0004): no downsizing, and an already-occupied slot is
// rejected. Cargo fittings are additionally validated against ADR-0004's
// "stackable and effect-less" rule: a cargo fitting must carry no
// passive/active effect and must have a stack_count of at least 1.
ship_fit :: proc(layout_slot: ^Layout_Slot, fitting: Fitting) -> bool {
	if fitting.size != layout_slot.slot.size {
		return false
	}
	if _, occupied := layout_slot.fitting.?; occupied {
		return false
	}
	if fitting.is_cargo {
		_, has_passive := fitting.passive.?
		_, has_active := fitting.active.?
		if has_passive || has_active || fitting.stack_count < 1 {
			return false
		}
	}
	layout_slot.fitting = fitting
	return true
}

// ship_effective_visibility resolves a fitting's visibility as an opponent
// would actually observe it (ADR-0005): slot base visibility, overridden by
// the fitting's own override if it has one. A third layer — a ship/captain-
// level forced override that would take precedence over the fitting's own
// override — is a documented extension point only; it is not implemented in
// this slice.
ship_effective_visibility :: proc(layout_slot: Layout_Slot) -> Visibility {
	if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
		if override, has_override := fitting.visibility_override.?; has_override {
			return override
		}
	}
	return layout_slot.slot.base_visibility
}

// ship_fitting_stat_contribution sums the resolved magnitude of a fitting's
// Stat_Modifier effects of `kind` (issue #92). Both the passive and active
// effect are considered, so a stat modifier may sit in either slot; only
// effects whose Effect_Kind matches count, so a Phase_Contribution never
// leaks into a stat total.
ship_fitting_stat_contribution :: proc(fitting: Fitting, kind: Effect_Kind, ctx: Effect_Context) -> int {
	total := 0
	for slot in ([2]Maybe(Effect){fitting.passive, fitting.active}) {
		if effect, ok := slot.?; ok && effect.kind == kind {
			total += int(effect_magnitude(effect, ctx))
		}
	}
	return total
}

// ship_effective_stat is the shared shape behind ship_effective_durability /
// _speed / _max_hp (issue #92): the raw base stat plus every installed
// fitting's matching Stat_Modifier contribution. `base` is the ship's own
// field and `kind` the Modify_* kind that targets it.
ship_effective_stat :: proc(s: ^Ship, base: int, kind: Effect_Kind) -> int {
	total := base
	ctx := ship_effect_context(s)
	for layout_slot in s.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
			total += ship_fitting_stat_contribution(fitting, kind, ctx)
		}
	}
	return total
}

// ship_effective_durability / _speed / _max_hp return a ship's stat after its
// installed fittings' Stat_Modifier effects apply on top of the raw Ship field
// (issue #92). Combat reads these rather than the raw fields (see core/combat's
// combat_effective_speed and its damage calc; ADR-0008's ghost capture resets
// hp to effective max HP), so a fitting can raise Durability / Speed / Max HP.
ship_effective_durability :: proc(s: ^Ship) -> int {
	return ship_effective_stat(s, s.durability, .Modify_Durability)
}

ship_effective_speed :: proc(s: ^Ship) -> int {
	return ship_effective_stat(s, s.speed, .Modify_Speed)
}

ship_effective_max_hp :: proc(s: ^Ship) -> int {
	return ship_effective_stat(s, s.max_hp, .Modify_Max_HP)
}

// ship_cargo_capacity adjusts the ship's baseline cargo stat by the slots
// currently allocated to cargo and by the ship's captain, if any
// (Captain.cargo_capacity_bonus — issue #23). Per-size slot contribution
// values are an arbitrary placeholder balancing choice, not backed by any
// ADR yet.
ship_cargo_capacity :: proc(s: Ship) -> int {
	capacity := s.base_cargo_capacity
	if captain, has_captain := s.captain.?; has_captain {
		capacity += captain.cargo_capacity_bonus
	}
	for layout_slot in s.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting && fitting.is_cargo {
			capacity += ship_cargo_slot_contribution(layout_slot.slot.size)
		}
	}
	return capacity
}

ship_cargo_slot_contribution :: proc(size: Slot_Size) -> int {
	switch size {
	case .Small:
		return 1
	case .Medium:
		return 2
	case .Large:
		return 3
	}
	return 0
}

// ship_slot_by_category finds the one layout slot currently holding a
// non-cargo fitting of the given Category (issue #24: an Upgrade Offer pick
// targets "the slot holding my current Top Crew/Captain's Quarters/Gun Deck",
// not a literal slot name — unambiguous in this slice's fixed 3-fitting
// loadout, since exactly one slot holds each of Buff/Defensive/Offensive).
// Returns nil if no slot currently holds a matching fitting.
ship_slot_by_category :: proc(s: ^Ship, category: Category) -> ^Layout_Slot {
	for &layout_slot in s.layout {
		fitting, has_fitting := layout_slot.fitting.?
		if has_fitting && !fitting.is_cargo && fitting.category == category {
			return &layout_slot
		}
	}
	return nil
}

// ship_replace_fitting swaps out layout_slot's current fitting for a new one
// (issue #24: applying an Upgrade Offer pick — ship_fit alone rejects an
// already-occupied slot, so a bare clear-then-fit would be needed at every
// call site without this). Still enforces the exact-size-match rule
// (ADR-0004): checked before clearing, so a size-mismatched fitting is
// rejected without disturbing what was already installed.
ship_replace_fitting :: proc(layout_slot: ^Layout_Slot, fitting: Fitting) -> bool {
	if fitting.size != layout_slot.slot.size {
		return false
	}
	layout_slot.fitting = nil
	return ship_fit(layout_slot, fitting)
}

// Captain is structurally separate from the slot system: not a fitting,
// consumes no slot. A run-start choice that can influence a ship's slot
// limits/structure and grants additional manual per-round captain actions.
// cargo_capacity_bonus is the vertical slice's one captain's concrete
// slot-limit/structure influence (issue #23): added to the ship's cargo
// capacity (ship_cargo_capacity) alongside base_cargo_capacity and any
// cargo-filled slots — the closest existing "slot limit" stat for a captain
// to move (CONTEXT.md: cargo capacity is "a baseline ship stat, adjusted...
// by which slots get allocated to cargo"). This captain grants no
// additional per-round action beyond the standard Command set: ADR-0006
// already notes this slice's one captain uses the full
// Boost/Man-the-Sails/Jettison-Cargo/Leave-Combat menu as its action set, so
// there is nothing further to define here.
Captain :: struct {
	name:                 string,
	cargo_capacity_bonus: int,
}
