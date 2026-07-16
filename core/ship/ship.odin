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
// a trigger): rather than extend this enum they attach to the magnitude seam
// (effect_magnitude) as their own Effect fields — synergy is the Maybe(Selector)
// added by #93, conditional the Maybe(Condition) added by #94 — so this set
// stays "what the magnitude does" and the context-sensitivity of how it is
// computed lives beside it, not inside it.
Effect_Kind :: enum {
	Phase_Contribution,
	Modify_Durability,
	Modify_Speed,
	Modify_Max_HP,
}

// Selector picks the fittings a synergy effect counts (issue #93, ADR-0012):
// magnitude scales with how many installed fittings match it. It ranges over
// four axes — a Tag family, a Slot_Size, an (effective) Visibility, or a round
// Category — one axis per selector. Modeled as a tagged union of those four
// enum types (the house idiom for a closed variant set whose variants carry
// their own payload — see Effect_Kind's comment, which anticipated this exact
// case: a synergy "carries its own payload, a selector"): the selector *is* its
// criterion value, and its type is the discriminant. Plain data, so it
// round-trips through a Ghost_Snapshot (ADR-0008) like the rest of an Effect.
Selector :: union {
	Tag,
	Slot_Size,
	Visibility,
	Category,
}

// Condition gates a conditional effect's magnitude on a battle- or ship-state
// trigger (issue #94, ADR-0012): a conditional effect contributes its full
// magnitude the rounds its Condition holds and nothing the rounds it does not,
// re-evaluated every round against live state (effect_magnitude / condition_met).
// Modeled as a tagged union of the trigger variants — the house idiom for a
// closed variant set whose members carry their own payload (see Effect_Kind's
// comment, which anticipated this exact case: a conditional "carries its own
// payload, a trigger") — so the trigger *is* its parameters and its type is the
// discriminant. Plain data, so it round-trips through a Ghost_Snapshot
// (ADR-0008) like the rest of an Effect. The four axes required by #94:
//   - HP threshold        -> Condition_HP_Below      (a ship-state trigger)
//   - round number        -> Condition_Round_At_Least (a battle-state trigger)
//   - own concealment     -> Condition_Self_Visibility (a ship-state trigger)
//   - opponent faster/slower -> Condition_Opponent_Faster / _Slower (battle-state)
// The two battle-state triggers read Effect_Context.battle, which is nil outside
// combat, so they are simply unmet when an effect resolves off the battlefield
// (e.g. an effective-stat read between encounters).
Condition :: union {
	Condition_HP_Below,
	Condition_Round_At_Least,
	Condition_Self_Visibility,
	Condition_Opponent_Faster,
	Condition_Opponent_Slower,
}

// Condition_HP_Below holds while the owner's current HP is strictly below
// `percent` percent of its max HP — "below half HP" is `percent = 50`. Compared
// against the raw Ship.max_hp field, not ship_effective_max_hp: an effective
// read would recurse (a Modify_Max_HP effect that is itself HP-conditional would
// re-enter this check), and the run-persistent HP ceiling a threshold means is
// the base field anyway (ADR-0008).
Condition_HP_Below :: struct {
	percent: int,
}

// Condition_Round_At_Least holds from battle `round` onward (1-based, matching
// Battle.round). A battle-state trigger: unmet when resolved outside combat.
Condition_Round_At_Least :: struct {
	round: int,
}

// Condition_Self_Visibility holds while the fitting carrying the effect has the
// given effective visibility (ship_effective_visibility) — "own concealment" is
// `visibility = .Concealed`. Reads Effect_Context.self_slot, the slot the effect
// is being resolved for, so it is unmet when resolved without a self slot.
Condition_Self_Visibility :: struct {
	visibility: Visibility,
}

// Condition_Opponent_Faster / _Slower hold while the opponent's effective Speed
// is strictly greater / less than the owner's, compared against the live speeds
// combat captures into Effect_Context.battle (own_speed / opponent_speed, which
// already fold in this round's Man the Sails and any Jettison bonuses). Battle-
// state triggers: unmet outside combat.
Condition_Opponent_Faster :: struct {}
Condition_Opponent_Slower :: struct {}

// Effect is a fitting's data-driven passive/active contribution, resolved
// against an Effect_Context at the point of use rather than baked in as a bare
// constant (issue #92, #88). It stays plain data — no function pointers — so a
// Ghost_Snapshot (ADR-0008) can carry it. `kind` decides what the resolved
// magnitude does; `magnitude` is the effect's per-unit strength. `synergy` and
// `conditional`, when set, make the resolved magnitude context-sensitive at the
// magnitude seam (effect_magnitude), each orthogonal to `kind` — either may feed
// a combat phase or modify a stat — rather than being further Effect_Kinds:
//   - synergy (issue #93) scales `magnitude` by the count of installed fittings
//     the Selector matches, so it tracks the owning ship's current build ("for
//     each Weapon, +Offense").
//   - conditional (issue #94) gates the whole magnitude on a battle-/ship-state
//     trigger, yielding it the rounds the Condition holds and 0 otherwise
//     ("below half HP, +Offense").
// The two compose (a gated synergy resolves to 0 while its Condition is unmet,
// its build-scaled count otherwise). The concrete fitting roster and its balance
// values belong to the content tickets (issue #23), not this data model.
Effect :: struct {
	kind:        Effect_Kind,
	magnitude:   Magnitude,
	synergy:     Maybe(Selector),
	conditional: Maybe(Condition),
}

// Effect_Context is everything an Effect may resolve its magnitude against: the
// owning ship (issue #92); the slot the effect is being resolved for, for self-
// referential triggers like own concealment (issue #94); and the live battle
// state, present only during combat (issue #94). `battle` is the extension point
// #92 documented ahead of implementation — a conditional's round-number and
// opponent-speed triggers read it, and it is nil for any resolve outside a
// battle (the effective-stat readers between encounters), where those triggers
// are simply unmet. `self_slot` is set per-slot by every resolve site that
// iterates a layout (ship_effective_stat, combat_phase_output).
Effect_Context :: struct {
	owner:     ^Ship,
	self_slot: Maybe(Layout_Slot),
	battle:    Maybe(Battle_State),
}

// Battle_State is the slice of live combat state a conditional effect may read
// (issue #94), built by core/combat and carried on Effect_Context.battle. Speeds
// are captured by combat (combat_effective_speed) rather than recomputed here so
// this stays plain data and the comparison can't re-enter effect resolution.
Battle_State :: struct {
	round:          int,
	own_speed:      int,
	opponent_speed: int,
}

// effect_magnitude resolves `effect`'s magnitude against `ctx` (issue #92, #94).
// A flat effect returns its stored constant and ignores ctx; a conditional
// effect (effect.conditional set) returns that constant the rounds its Condition
// holds against ctx and 0 otherwise (condition_met). Every magnitude read
// (combat phase output, the effective-stat readers) goes through here, so those
// call sites stay untouched as this seam gains context-sensitive kinds (#88).
effect_magnitude :: proc(effect: Effect, ctx: Effect_Context) -> Magnitude {
	if condition, is_conditional := effect.conditional.?; is_conditional {
		if !condition_met(condition, ctx) {
			return 0
		}
	}
	magnitude := effect.magnitude
	if selector, is_synergy := effect.synergy.?; is_synergy {
		magnitude *= Magnitude(ship_count_matching(ctx.owner, selector))
	}
	return magnitude
}

// selector_matches reports whether layout_slot's installed fitting satisfies
// `selector` (issue #93). Each Selector axis reads the fitting's corresponding
// property: a Tag tests family membership (a multi-tag fitting matches on each
// of its tags — ADR-0012); a Slot_Size / Category tests the fitting's own
// field; a Visibility tests the fitting's *effective* visibility as an opponent
// would observe it (ship_effective_visibility, ADR-0005), which is why this
// takes the whole Layout_Slot rather than a bare Fitting. An empty slot matches
// nothing: the has_fitting guard below owns that case, so callers may pass every
// slot without pre-filtering (ship_count_matching does).
selector_matches :: proc(layout_slot: Layout_Slot, selector: Selector) -> bool {
	fitting, has_fitting := layout_slot.fitting.?
	if !has_fitting {
		return false
	}
	switch criterion in selector {
	case Tag:
		return criterion in fitting.tags
	case Slot_Size:
		return fitting.size == criterion
	case Visibility:
		return ship_effective_visibility(layout_slot) == criterion
	case Category:
		return fitting.category == criterion
	}
	return false
}

// condition_met reports whether `condition` holds against `ctx` (issue #94),
// re-evaluated at every magnitude read so a conditional tracks live state round
// to round. The two battle-state triggers read ctx.battle and are unmet when it
// is nil (resolved outside combat); the self-visibility trigger reads
// ctx.self_slot and is unmet without one.
condition_met :: proc(condition: Condition, ctx: Effect_Context) -> bool {
	switch c in condition {
	case Condition_HP_Below:
		return ctx.owner.hp * 100 < ctx.owner.max_hp * c.percent
	case Condition_Round_At_Least:
		battle, in_battle := ctx.battle.?
		return in_battle && battle.round >= c.round
	case Condition_Self_Visibility:
		self_slot, has_self := ctx.self_slot.?
		return has_self && ship_effective_visibility(self_slot) == c.visibility
	case Condition_Opponent_Faster:
		battle, in_battle := ctx.battle.?
		return in_battle && battle.opponent_speed > battle.own_speed
	case Condition_Opponent_Slower:
		battle, in_battle := ctx.battle.?
		return in_battle && battle.opponent_speed < battle.own_speed
	}
	return false
}

// ship_count_matching counts s's installed fittings that satisfy `selector`
// (issue #93): the synergy magnitude scales with this. Cargo is not special-
// cased out — it carries a real Tag / size / visibility, so a "for each Cargo"
// or size/visibility synergy legitimately counts it (its Category field is the
// one meaningless axis for cargo, a known data caveat, not something guarded
// here). Called every time a synergy effect resolves (effect_magnitude), so the
// count reflects the layout as it stands at that moment.
ship_count_matching :: proc(s: ^Ship, selector: Selector) -> int {
	count := 0
	for layout_slot in s.layout {
		if selector_matches(layout_slot, selector) {
			count += 1
		}
	}
	return count
}

// ship_effect_context builds the off-battle Effect_Context for ship s (issue
// #92): owner only, no battle state, no self slot. The effective-stat readers
// use it (they fill self_slot per iteration). Combat builds the in-battle shape
// with ship_effect_context_in_battle instead.
ship_effect_context :: proc(s: ^Ship) -> Effect_Context {
	return Effect_Context{owner = s}
}

// ship_effect_context_in_battle builds the Effect_Context a conditional effect
// resolves against during combat (issue #94): the owning ship plus the live
// `battle` state its round-number and opponent-speed triggers read. Callers
// still fill self_slot per slot before resolving each fitting's effect. Takes
// the whole Battle_State (round and the live effective speeds combat has already
// computed via combat_effective_speed) rather than its fields loose, so the
// caller names each at the construction site — two positional speeds would be
// silently swappable.
ship_effect_context_in_battle :: proc(s: ^Ship, battle: Battle_State) -> Effect_Context {
	return Effect_Context{owner = s, battle = battle}
}

Fitting :: struct {
	name:                string,
	size:                Slot_Size,
	// weight is what this fitting adds to its ship's weight (ADR-0020, #194): an
	// authored per-item balance choice — the knob that makes a strong item pay for
	// its strength — in #156's size band (Large ~30-45, Medium ~15-25, Small ~5-12).
	// **Only read for non-cargo fittings**: a cargo fitting weighs its treasure
	// (stack_count, #156), so ship_fitting_weight ignores this field when is_cargo.
	// See content.odin, where every roster item and starting fitting authors one.
	weight:              int,
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
	// and effect-less, and the fitting a ship's money lives in (ADR-0020) — a
	// cargo fitting *is* its treasure. ship_fit enforces both halves of that
	// special-casing: no passive/active effects, and a stack_count of at least 1.
	is_cargo:            bool,
	// stack_count is the treasure this cargo fitting holds (ADR-0020, #156: one
	// stacked unit is one unit of treasure, and one unit of weight). Summed
	// across a ship's cargo fittings it is the ship's purse (ship_treasure).
	// Only meaningful when is_cargo is true; ignored for every other fitting kind.
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

// Ship holds the run-persistent top-level stats (HP, Durability, Speed) plus
// the fixed layout of slots that carries its combat power. A ship's money is
// **not** a field: its purse is the treasure stowed in its cargo fittings
// (ship_treasure), so there is no number on a ship representing money (ADR-0020,
// #156). See CONTEXT.md's Ship & crew model glossary and ADR-0004.
Ship :: struct {
	hp:                  int,
	// max_hp is the ship's undamaged HP ceiling (ADR-0008): hp is the
	// run-persistent value combat depletes, max_hp never changes during a
	// run and is what a Ghost_Snapshot resets hp to on capture.
	max_hp:              int,
	durability:          int,
	// speed is the `base` term of the derived Speed reading (ADR-0020, #158/#180):
	// effective Speed is `speed + Σ Modify_Speed − weight/10` (ship_effective_speed),
	// so this field no longer *is* a ship's Speed — it is a calibration initialised
	// to BASE_SPEED uniformly across ships (a ship's character is its items and its
	// purse, not a per-hull base). It survives as a field (not collapsed to a
	// literal) because Modify_Speed fittings and, later, captains act through the
	// additive modifier term on top of it.
	speed:               int,
	layout:              []Layout_Slot,
	// captain is the run-start ship<->captain relationship (issue #18): a
	// captain can influence a ship's slot limits/structure and grants
	// additional manual per-round captain actions. The vertical slice's one
	// concrete captain (issue #23) is ship_starting_captain in content.odin.
	captain:             Maybe(Captain),
}

// ship_fitting_fits reports whether `fitting` may occupy a slot of `size` under
// ADR-0004's fit rule, independent of current occupancy: an exact size match (no
// downsizing), plus — for a cargo fitting — the "stackable and effect-less" rule
// (no passive/active effect, stack_count at least 1). It is the single statement
// of the fit rule that both ship_fit (install into an empty slot) and
// ship_replace_fitting (swap into any slot) share, so the two admit exactly the
// same fittings.
ship_fitting_fits :: proc(size: Slot_Size, fitting: Fitting) -> bool {
	if fitting.size != size {
		return false
	}
	if fitting.is_cargo {
		_, has_passive := fitting.passive.?
		_, has_active := fitting.active.?
		if has_passive || has_active || fitting.stack_count < 1 {
			return false
		}
	}
	return true
}

// ship_fit installs `fitting` into `layout_slot` under the fit rule
// (ship_fitting_fits, ADR-0004) with the additional install-only constraint that
// an already-occupied slot is rejected — installing never displaces. A fitting
// that fails either check leaves the slot untouched.
ship_fit :: proc(layout_slot: ^Layout_Slot, fitting: Fitting) -> bool {
	if _, occupied := layout_slot.fitting.?; occupied {
		return false
	}
	if !ship_fitting_fits(layout_slot.slot.size, fitting) {
		return false
	}
	layout_slot.fitting = fitting
	return true
}

// ship_replace_fitting swaps `fitting` into layout_slot under the same fit rule
// as ship_fit (ship_fitting_fits, ADR-0004) but — unlike install — accepts an
// occupied slot, discarding whatever it held (issue #111's place-or-swap; there
// is no inventory, ADR-0012, so the displaced fitting is the caller's to
// announce removed). A size- or cargo-rule mismatch is refused and leaves the
// slot untouched.
ship_replace_fitting :: proc(layout_slot: ^Layout_Slot, fitting: Fitting) -> bool {
	if !ship_fitting_fits(layout_slot.slot.size, fitting) {
		return false
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
// field and `kind` the Modify_* kind that targets it. self_slot is set per
// iteration (issue #94) so a conditional stat modifier gated on its own
// concealment resolves against the slot it actually sits in. The context here
// carries no battle state, so a conditional stat modifier gated on a battle-
// state trigger (round / opponent speed) is unmet through this off-battle path.
ship_effective_stat :: proc(s: ^Ship, base: int, kind: Effect_Kind) -> int {
	total := base
	ctx := ship_effect_context(s)
	for layout_slot in s.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
			ctx.self_slot = layout_slot
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

// ship_effective_speed derives a ship's Speed from its weight (ADR-0020, #158):
// `base + Σ Modify_Speed − weight/10`. The base and the additive Modify_Speed
// modifiers come through ship_effective_stat exactly as Durability and Max HP do;
// the new term is `− ship_weight/10`, so **no ship's Speed can be read without
// asking what it is carrying** (the destination test). The `/10` divisor is the
// money↔Speed exchange rate — #156's ×10-and-doubling capacity table read as a
// Speed table (a full Small hold = 1 Speed, Medium = 2, Large = 4) — and it is
// forced (#158): any coarser divisor makes jettisoning a Small hold buy 0 Speed.
// It lives only here. Speed stays an `int` (every escape gate and tie-break
// compares Speeds with `>`); weight is a subtrahend, never a clamp — authoring
// keeps `base − weight/10 >= 0` for every ship at its realistic full hold (#175,
// the floor invariant), so `max(0, …)` is never written.
ship_effective_speed :: proc(s: ^Ship) -> int {
	return ship_effective_stat(s, s.speed, .Modify_Speed) - ship_weight(s^) / 10
}

// ship_fitting_weight is what one fitting adds to its ship's weight (ADR-0020): a
// cargo fitting weighs its treasure (its stack_count, #156 — so an empty hold
// weighs nothing and a full one weighs its contents 1:1), while a non-cargo
// fitting weighs its **authored** weight (Fitting.weight, #194). That weight is a
// per-item balance choice in #156's size band (Large ~30-45, Medium ~15-25, Small
// ~5-12), authored beside each item in content.odin — the knob that makes a strong
// item pay for its strength. Guns are permanently heavy, cargo heavy only while
// full, so emptiness — not loadout — is what varies (ADR-0020).
ship_fitting_weight :: proc(f: Fitting) -> int {
	if f.is_cargo {
		return f.stack_count
	}
	return f.weight
}

// ship_weight is a ship's total weight: every installed fitting's contribution
// (ship_fitting_weight). This is the subtrahend in ship_effective_speed, so a
// ship's Speed falls as it loads treasure or heavy fittings and rises as it sheds
// them — getting rich is what makes you catchable (ADR-0020).
ship_weight :: proc(s: Ship) -> int {
	total := 0
	for layout_slot in s.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
			total += ship_fitting_weight(fitting)
		}
	}
	return total
}

ship_effective_max_hp :: proc(s: ^Ship) -> int {
	return ship_effective_stat(s, s.max_hp, .Modify_Max_HP)
}

// ship_cargo_capacity is the treasure a ship can carry: the size contribution
// of every slot **not** carrying a non-cargo fitting — empty slots and
// cargo-filled slots both count, a slot spent on a gun does not (ADR-0020,
// #157). So a broke ship still reads its full structural ceiling (the 8-slot
// starting hull with its three exposed guns reads 90), and a slot spent on a
// fitting is money the ship can no longer carry — the refit tension. Overflow
// above this is lost (ship_stow_treasure), never stored: treasure lives only in
// cargo fittings, which live only in finite slots.
ship_cargo_capacity :: proc(s: Ship) -> int {
	capacity := 0
	for layout_slot in s.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting && !fitting.is_cargo {
			continue
		}
		capacity += ship_cargo_slot_contribution(layout_slot.slot.size)
	}
	return capacity
}

// ship_cargo_slot_contribution is how much treasure a slot of `size` can hold —
// and, since money is weight (ADR-0020), how much a full one weighs. The ×10-
// and-doubling scale (#156) is what makes weight, capacity, and money one
// commensurable system, and it is also the Speed table ×10 (a full Large is
// worth four Smalls and, once Speed reads weight, costs four Smalls of Speed).
ship_cargo_slot_contribution :: proc(size: Slot_Size) -> int {
	switch size {
	case .Small:
		return 10
	case .Medium:
		return 20
	case .Large:
		return 40
	}
	return 0
}

// ship_treasure is a ship's purse: the treasure stowed across its cargo fittings
// (ADR-0020, #156 — a cargo fitting's stack_count *is* its treasure, one unit
// each). This is what "the purse" means now that no scalar money field rides on
// a ship; a ship with no cargo fittings carries nothing.
ship_treasure :: proc(s: Ship) -> int {
	treasure := 0
	for layout_slot in s.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting && fitting.is_cargo {
			treasure += fitting.stack_count
		}
	}
	return treasure
}

// ship_stow_treasure re-stows `amount` treasure across `layout`, smallest slots
// first (ADR-0020, #172). It first clears every existing cargo fitting —
// reallocation is free outside battle (#157), so a re-stow rebuilds the hold
// from scratch — then fills the empty, non-gun slots smallest-first, each up to
// its capacity, until `amount` is exhausted. **Overflow above capacity is lost**
// (#157): treasure with no slot to land in simply drops. Used for the player's
// bootstrap stow and for every out-of-battle purse change (a Reward gain, a Shop
// or Trade spend): the caller passes the desired total, not a delta.
//
// Smallest-first is the rule, not authored numbers: the starting 50 falls out as
// three Smalls at 10 + a Medium at 20, the Large left empty as headroom, and it
// keeps #157's granularity property — fine change lives in the Smalls, so the
// richer you get the coarser the only thing you can heave.
ship_stow_treasure :: proc(layout: []Layout_Slot, amount: int) {
	for &layout_slot in layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting && fitting.is_cargo {
			layout_slot.fitting = nil
		}
	}
	remaining := amount
	for size in ([3]Slot_Size{.Small, .Medium, .Large}) {
		for &layout_slot in layout {
			if remaining <= 0 {
				return
			}
			if _, occupied := layout_slot.fitting.?; occupied {
				continue
			}
			if layout_slot.slot.size != size {
				continue
			}
			stow := min(remaining, ship_cargo_slot_contribution(size))
			layout_slot.fitting = ship_fitting_cargo("Cargo", size, stow)
			remaining -= stow
		}
	}
}

// ship_remove takes the fitting out of layout_slot, leaving the slot empty,
// and returns it (issue #95, ADR-0012's manual loadout). There is no inventory:
// the returned fitting is the caller's to discard — a refit remove drops it on
// the floor (Event_Fitting_Removed) and nothing holds it afterward. Returns
// false (and a zero Fitting) when the slot was already empty, so a remove of
// nothing is a caller-visible rejection rather than a silent no-op.
ship_remove :: proc(layout_slot: ^Layout_Slot) -> (Fitting, bool) {
	fitting, occupied := layout_slot.fitting.?
	if !occupied {
		return {}, false
	}
	layout_slot.fitting = nil
	return fitting, true
}

// ship_move relocates the fitting in `from` into the empty `to` under
// ADR-0004's exact-size fit rule (issue #95): the source must hold a fitting,
// the destination must be empty, and the two slots must be the same size. Any
// of those unmet leaves both slots untouched and returns false — a rejected
// move never disturbs the layout. On success the moved fitting is returned (for
// the emitted Event_Fitting_Moved) and the source is left empty. Takes the two
// slots by pointer, like ship_fit / ship_remove, so a refit's caller resolves
// (and bounds-checks) the indices itself rather than passing bare ints through.
ship_move :: proc(from, to: ^Layout_Slot) -> (Fitting, bool) {
	fitting, occupied := from.fitting.?
	if !occupied {
		return {}, false
	}
	if _, dest_occupied := to.fitting.?; dest_occupied {
		return {}, false
	}
	if fitting.size != to.slot.size {
		return {}, false
	}
	from.fitting = nil
	to.fitting = fitting
	return fitting, true
}

// Captain is structurally separate from the slot system: not a fitting,
// consumes no slot. A run-start choice that can influence a ship's starting
// state and grants additional manual per-round captain actions.
// starting_cargo_bonus is the vertical slice's one captain's concrete lever
// (issue #23, #172): treasure the captain adds to the ship's bootstrap stow on
// top of STARTING_CARGO, so the starting 50 is 40 (ship) + 10 (Odessa). Unlike
// the deleted cargo_capacity_bonus — which promised room no slot provides and
// so was unfillable (#157) — this is **fillable**: it adds treasure into the
// headroom the 8-slot hull already has (#172), which is what revives the captain
// from vestigial. This captain grants no additional per-round action beyond the
// standard Command set: ADR-0006 already notes this slice's one captain uses the
// full Boost/Man-the-Sails/Jettison-Cargo/Leave-Combat menu as its action set,
// so there is nothing further to define here.
Captain :: struct {
	name:                 string,
	starting_cargo_bonus: int,
}
