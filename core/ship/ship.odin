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

Slot :: struct {
	name:            string,
	size:            Slot_Size,
	base_visibility: Visibility,
}

// Effect is the numeric strength of a fitting's passive/active combat
// contribution. What magnitude means is decided by the combat resolver
// (ADR-0006, core/combat) from the owning fitting's Category; the concrete
// fitting roster and its balance values belong to the vertical-slice content
// ticket (issue #23), not this data model.
Effect :: struct {
	magnitude: int,
}

Fitting :: struct {
	name:                string,
	size:                Slot_Size,
	// category is which round phase (ADR-0006) this fitting's active effect
	// triggers in. Meaningless for cargo, which carries no effects.
	category:            Category,
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

// Ship holds the run-persistent top-level stats (HP, Durability, Speed,
// starting treasure) plus the fixed layout of slots that carries its combat
// power. See CONTEXT.md's Ship & crew model glossary and ADR-0004.
Ship :: struct {
	hp:                  int,
	durability:          int,
	speed:               int,
	starting_treasure:   int,
	base_cargo_capacity: int,
	layout:              []Layout_Slot,
	// captain is the run-start ship<->captain relationship (issue #18): a
	// captain can influence a ship's slot limits/structure and grants
	// additional manual per-round captain actions. The content of a concrete
	// captain (what it actually does) is out of scope here — see issue #23.
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

// ship_cargo_capacity adjusts the ship's baseline cargo stat by the slots
// currently allocated to cargo. Per-size contribution values are an
// arbitrary placeholder balancing choice, not backed by any ADR yet.
ship_cargo_capacity :: proc(s: Ship) -> int {
	capacity := s.base_cargo_capacity
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

// Captain is structurally separate from the slot system: not a fitting,
// consumes no slot. A run-start choice that can influence a ship's slot
// limits/structure and grants additional manual per-round captain actions —
// that behavior is content for a specific captain (issue #23) and isn't
// modeled yet.
Captain :: struct {
	name: string,
}
