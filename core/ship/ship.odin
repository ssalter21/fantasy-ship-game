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

// Category is a fitting's round phase (ADR-0006, amended by ADR-0025): every round
// resolves Brace -> Fire, and Category is which of the two a fitting triggers in. It
// lives in this package rather than core/combat because layout order — this package's
// data — is what fixes the phase grouping combat resolves by.
Category :: enum {
	Brace,
	Fire,
}

// Tag is a fitting's family membership: the axis synergy effects count fittings
// along, independent of combat phase (Category) — a Beast may brace or fire. Multi-tag
// is allowed (selector_matches counts a fitting under each of its tags).
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

// Magnitude is an Effect's strength, distinct from a plain int (ADR-0011) so it
// can't be confused at a call site with an index or other bare-int domain value.
// A caller that folds it into a raw combat total casts back to int explicitly
// (see core/combat's combat_phase_output).
Magnitude :: distinct int

// Effect_Kind is what an Effect's resolved magnitude does. The zero value,
// Phase_Contribution, feeds the owning fitting's combat phase (its Category,
// ADR-0006); the Modify_* kinds instead adjust one of the owning ship's
// effective stats (ship_effective_speed / _max_hull), so a fitting can raise a
// stat without contributing to a phase. Modify_Durability died with the
// Durability stat itself (ADR-0026).
Effect_Kind :: enum {
	Phase_Contribution,
	Modify_Speed,
	Modify_Max_Hull,
}

// Selector picks the fittings a synergy effect counts (ADR-0012): its magnitude
// scales with how many installed fittings match. One axis per selector — a Tag
// family, a Slot_Size, an effective Visibility, or a round Category — modeled as a
// tagged union whose variant *is* the criterion value and whose type is the
// discriminant. Plain data, so it round-trips through a Ghost_Snapshot (ADR-0008).
Selector :: union {
	Tag,
	Slot_Size,
	Visibility,
	Category,
}

// Condition gates a conditional effect's magnitude on a battle- or ship-state
// trigger (ADR-0012): the effect contributes its full magnitude the rounds its
// Condition holds and nothing otherwise, re-evaluated every round (condition_met).
// A tagged union — the trigger is its parameters, its type the discriminant; plain
// data for a Ghost_Snapshot (ADR-0008). The battle-state triggers read
// Effect_Context.battle, nil outside combat, so they are unmet off the battlefield.
Condition :: union {
	Condition_Hull_Below,
	Condition_Round_At_Least,
	Condition_Self_Visibility,
	Condition_Opponent_Faster,
	Condition_Opponent_Slower,
}

// Condition_Hull_Below holds while the owner's current Hull is strictly below
// `percent` percent of its max Hull ("below half Hull" is `percent = 50`).
// Compared against the raw Ship.max_hull, not ship_effective_max_hull: an
// effective read would recurse (a Hull-conditional Modify_Max_Hull effect would
// re-enter this check) — and the threshold means the base ceiling anyway (ADR-0008).
Condition_Hull_Below :: struct {
	percent: int,
}

// Condition_Round_At_Least holds from battle `round` onward (1-based, matching
// Battle.round). A battle-state trigger: unmet when resolved outside combat.
Condition_Round_At_Least :: struct {
	round: int,
}

// Condition_Self_Visibility holds while the fitting carrying the effect has the
// given effective visibility (ship_effective_visibility). Reads
// Effect_Context.self_slot, the slot the effect is being resolved for, so it is
// unmet when resolved without a self slot.
Condition_Self_Visibility :: struct {
	visibility: Visibility,
}

// Condition_Opponent_Faster / _Slower hold while the opponent's effective Speed
// is strictly greater / less than the owner's, compared against the live speeds
// combat captures into Effect_Context.battle. Battle-state triggers: unmet
// outside combat.
Condition_Opponent_Faster :: struct {}
Condition_Opponent_Slower :: struct {}

// Effect is a fitting's data-driven contribution, resolved against an
// Effect_Context at the point of use rather than baked in as a bare constant. It
// stays plain data — no function pointers — so a Ghost_Snapshot (ADR-0008) can
// carry it. `kind` decides what the resolved magnitude does; `magnitude` is the
// per-unit strength; `synergy` (see Selector) and `conditional` (see Condition),
// when set, make the resolved magnitude context-sensitive at the magnitude seam
// (effect_magnitude), each orthogonal to `kind`. The two compose.
Effect :: struct {
	kind:        Effect_Kind,
	magnitude:   Magnitude,
	synergy:     Maybe(Selector),
	conditional: Maybe(Condition),
}

// Effect_Context is everything an Effect may resolve its magnitude against: the
// owning ship, the slot being resolved for (for self-referential triggers like own
// concealment), and the live battle state. `battle` is nil outside a battle, where
// the round-number and opponent-speed triggers are simply unmet; `self_slot` is set
// per-slot by every resolve site that iterates a layout (ship_effective_stat,
// combat_phase_output).
Effect_Context :: struct {
	owner:     ^Ship,
	self_slot: Maybe(Layout_Slot),
	battle:    Maybe(Battle_State),
}

// Battle_State is the slice of live combat state a conditional effect may read,
// built by core/combat and carried on Effect_Context.battle. Speeds are captured
// by combat (combat_effective_speed) rather than recomputed here, so this stays
// plain data and the comparison can't re-enter effect resolution.
Battle_State :: struct {
	round:          int,
	own_speed:      int,
	opponent_speed: int,
}

// effect_magnitude resolves `effect`'s magnitude against `ctx`: a flat effect
// returns its stored constant; a conditional effect returns that constant the
// rounds its Condition holds and 0 otherwise (condition_met); a synergy effect
// scales it by the count of matching fittings. Every magnitude read (combat phase
// output, the effective-stat readers) goes through this seam.
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
// `selector`. Tag matches on each of a multi-tag fitting's tags; Visibility tests
// the fitting's *effective* visibility (ship_effective_visibility, ADR-0005) —
// which is why this takes the whole Layout_Slot, not a bare Fitting. An empty slot
// matches nothing, so callers may pass every slot without pre-filtering.
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

// condition_met reports whether `condition` holds against `ctx`, re-evaluated at
// every magnitude read so a conditional tracks live state round to round. The two
// battle-state triggers read ctx.battle and are unmet when it is nil (resolved
// outside combat); the self-visibility trigger reads ctx.self_slot and is unmet
// without one.
condition_met :: proc(condition: Condition, ctx: Effect_Context) -> bool {
	switch c in condition {
	case Condition_Hull_Below:
		return ctx.owner.hull * 100 < ctx.owner.max_hull * c.percent
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

// ship_count_matching counts s's installed fittings that satisfy `selector`; the
// synergy magnitude scales with this. Cargo is not special-cased out — it carries a
// real Tag, size, and visibility, so a size/visibility or "for each Cargo" synergy
// legitimately counts it (only its Category axis is meaningless for cargo).
ship_count_matching :: proc(s: ^Ship, selector: Selector) -> int {
	count := 0
	for layout_slot in s.layout {
		if selector_matches(layout_slot, selector) {
			count += 1
		}
	}
	return count
}

// ship_effect_context builds the off-battle Effect_Context for ship s: owner only,
// no battle state. The effective-stat readers use it, filling self_slot per
// iteration; combat builds the in-battle shape with ship_effect_context_in_battle.
ship_effect_context :: proc(s: ^Ship) -> Effect_Context {
	return Effect_Context{owner = s}
}

// ship_effect_context_in_battle builds the in-combat Effect_Context: the owning
// ship plus the live `battle` state its round-number and opponent-speed triggers
// read (callers still fill self_slot per slot). Takes the whole Battle_State rather
// than its fields loose, so the caller names each at the construction site — two
// positional speeds would be silently swappable.
ship_effect_context_in_battle :: proc(s: ^Ship, battle: Battle_State) -> Effect_Context {
	return Effect_Context{owner = s, battle = battle}
}

Fitting :: struct {
	name:                string,
	size:                Slot_Size,
	// weight is what this fitting adds to its ship's weight (ADR-0020) — an
	// authored per-item balance knob that makes a strong item pay for its strength.
	// Only read for non-cargo fittings: a cargo fitting weighs its cargo
	// (stack_count) instead, so ship_fitting_weight ignores this field when
	// is_cargo.
	weight:              int,
	// category is which round phase (ADR-0006) this fitting's active effect
	// triggers in. Meaningless for cargo, which carries no effects.
	category:            Category,
	// tags is the fitting's family membership (see Tag).
	tags:                bit_set[Tag],
	visibility_override: Maybe(Visibility),
	passive:             Maybe(Effect),
	active:              Maybe(Effect),
	// is_cargo marks the one special-cased fitting kind (ADR-0004): stackable and
	// effect-less, and the fitting a ship's money lives in (ADR-0020) — a cargo
	// fitting *is* its cargo. ship_fit enforces both halves: no passive/active
	// effects, and a stack_count of at least 1.
	is_cargo:            bool,
	// stack_count is the cargo this cargo fitting holds (ADR-0020): one stacked unit
	// is one unit of cargo and one unit of weight. Summed across a ship's cargo
	// fittings it is the ship's cargo (ship_cargo). Only meaningful when is_cargo.
	stack_count:         int,
}

Layout_Slot :: struct {
	slot:    Slot,
	fitting: Maybe(Fitting),
}

// Slot_Index identifies a Layout_Slot by position in a Ship's layout, distinct
// from a plain int (ADR-0011) so a slot position can't be passed where a node id
// or upgrade option index belongs (e.g. Command_Jettison_Cargo's slot_index in
// core/combat).
Slot_Index :: distinct int

// Ship holds the voyage-persistent top-level stats (Hull, Speed) plus
// the fixed layout of slots that carries its combat power. A ship's money is *not*
// a field: the cargo it carries is stowed in its cargo fittings (ship_cargo), so no
// number on a ship represents money (ADR-0020, ADR-0004).
Ship :: struct {
	hull:     int,
	// max_hull is the ship's undamaged Hull ceiling (ADR-0008): hull is the voyage-
	// persistent value combat depletes, max_hull never changes during a voyage and
	// is what a Ghost_Snapshot resets hull to on capture.
	max_hull: int,
	// speed is the `base` term of the derived Speed reading (ADR-0020): effective
	// Speed is `speed + Σ Modify_Speed − weight/10` (ship_effective_speed), not this
	// field alone. Set to BASE_SPEED uniformly across ships (a ship's character is
	// its items and cargo, not a per-hull base); kept as a field so Modify_Speed
	// modifiers have a base to act on.
	speed:  int,
	layout: []Layout_Slot,
	// captain is the voyage-start ship<->captain relationship: a captain can
	// influence a ship's slot limits/structure and grants additional manual per-
	// round captain actions. The vertical slice's one concrete captain is
	// ship_starting_captain in content.odin.
	captain: Maybe(Captain),
}

// ship_fitting_fits reports whether `fitting` may occupy a slot of `size` under
// ADR-0004's fit rule, independent of current occupancy: an exact size match (no
// downsizing), plus — for a cargo fitting — the "stackable and effect-less" rule
// (no passive/active effect, stack_count at least 1). It is the single statement
// of the fit rule that both ship_fit and ship_replace_fitting share, so the two
// admit exactly the same fittings.
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

// ship_replace_fitting swaps `fitting` into layout_slot under the same fit rule as
// ship_fit (ship_fitting_fits, ADR-0004) but — unlike install — accepts an
// occupied slot, discarding whatever it held (place-or-swap; there is no inventory,
// ADR-0012, so the displaced fitting is the caller's to announce removed). A size-
// or cargo-rule mismatch is refused and leaves the slot untouched.
ship_replace_fitting :: proc(layout_slot: ^Layout_Slot, fitting: Fitting) -> bool {
	if !ship_fitting_fits(layout_slot.slot.size, fitting) {
		return false
	}
	layout_slot.fitting = fitting
	return true
}

// ship_effective_visibility resolves a fitting's visibility as an opponent would
// actually observe it (ADR-0005): the slot's base visibility, overridden by the
// fitting's own override when it has one.
ship_effective_visibility :: proc(layout_slot: Layout_Slot) -> Visibility {
	if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
		if override, has_override := fitting.visibility_override.?; has_override {
			return override
		}
	}
	return layout_slot.slot.base_visibility
}

// ship_fitting_stat_contribution sums the resolved magnitude of a fitting's stat-
// modifier effects of `kind`. Both the passive and active effect are considered,
// so a stat modifier may sit in either slot; only effects whose Effect_Kind matches
// count, so a Phase_Contribution never leaks into a stat total.
ship_fitting_stat_contribution :: proc(fitting: Fitting, kind: Effect_Kind, ctx: Effect_Context) -> int {
	total := 0
	for slot in ([2]Maybe(Effect){fitting.passive, fitting.active}) {
		if effect, ok := slot.?; ok && effect.kind == kind {
			total += int(effect_magnitude(effect, ctx))
		}
	}
	return total
}

// ship_effective_stat is the shared shape behind ship_effective_speed /
// _max_hull: the raw base stat plus every installed fitting's matching
// stat-modifier contribution. `base` is the ship's own field and `kind` the
// Modify_* kind that targets it. self_slot is set per iteration so a conditional
// stat modifier gated on its own concealment resolves against the slot it actually
// sits in. The context carries no battle state, so a conditional stat modifier
// gated on a battle-state trigger is unmet through this off-battle path.
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

// ship_effective_speed / _max_hull return a ship's stat after its installed
// fittings' stat-modifier effects apply on top of the raw Ship field. Combat reads
// these rather than the raw fields (ADR-0008's ghost capture resets hull to
// effective max Hull), so a fitting can raise Speed / Max Hull.
//
// ship_effective_speed derives a ship's Speed from its weight (ADR-0020):
// `base + Σ Modify_Speed − weight/10`, so no ship's Speed can be read without
// asking what it carries. The `/10` divisor is the money↔Speed exchange rate (a
// full Small hold = 1 Speed, Medium = 2, Large = 4) and is forced: any coarser
// divisor makes jettisoning a Small hold buy 0 Speed. Weight is a subtrahend,
// never a clamp — authoring keeps `base − weight/10 >= 0` at every ship's realistic
// full hold (the floor invariant), so `max(0, …)` is never written.
ship_effective_speed :: proc(s: ^Ship) -> int {
	return ship_effective_stat(s, s.speed, .Modify_Speed) - ship_weight(s^) / 10
}

// ship_fitting_weight is what one fitting adds to its ship's weight (ADR-0020): a
// cargo fitting weighs its cargo (its stack_count — an empty hold weighs nothing, a
// full one weighs its contents 1:1), a non-cargo fitting its authored
// Fitting.weight. Guns are permanently heavy, cargo heavy only while full, so
// emptiness — not loadout — is what varies a ship's weight.
ship_fitting_weight :: proc(f: Fitting) -> int {
	if f.is_cargo {
		return f.stack_count
	}
	return f.weight
}

// ship_weight is a ship's total weight: every installed fitting's contribution
// (ship_fitting_weight). It is the subtrahend in ship_effective_speed (ADR-0020).
ship_weight :: proc(s: Ship) -> int {
	total := 0
	for layout_slot in s.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
			total += ship_fitting_weight(fitting)
		}
	}
	return total
}

ship_effective_max_hull :: proc(s: ^Ship) -> int {
	return ship_effective_stat(s, s.max_hull, .Modify_Max_Hull)
}

// ship_cargo_capacity is the cargo a ship can carry: the size contribution of
// every slot *not* carrying a non-cargo fitting — empty and cargo-filled slots both
// count, a slot spent on a gun does not (ADR-0020). Overflow above this is lost
// (ship_stow_cargo), never stored: cargo lives only in cargo fittings, which live
// only in finite slots.
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

// ship_cargo_slot_contribution is how much cargo a slot of `size` can hold — and,
// since money is weight (ADR-0020), how much a full one weighs. The ×10-and-
// doubling scale makes weight, capacity, and money one commensurable system.
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

// ship_cargo is what a ship carries: the cargo summed across its cargo fittings
// (ADR-0020 — a cargo fitting's stack_count *is* its cargo). A ship with no cargo
// fittings carries nothing.
ship_cargo :: proc(s: Ship) -> int {
	cargo := 0
	for layout_slot in s.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting && fitting.is_cargo {
			cargo += fitting.stack_count
		}
	}
	return cargo
}

// ship_stow_cargo re-stows `amount` cargo across `layout`, smallest slots first
// (ADR-0020). It first clears every existing cargo fitting — reallocation is free
// outside battle, so a re-stow rebuilds the hold from scratch — then fills the
// empty, non-gun slots smallest-first, each up to its capacity, until `amount` is
// exhausted. The caller passes the desired total, not a delta, so this serves both
// the bootstrap stow and every out-of-battle cargo change (a Reward gain, a Shop or
// Trade spend).
//
// Overflow above capacity is lost and returned as `spilled` (0 when everything fit),
// so the one place the loss actually happens is the one place that reports it — no
// caller re-derives it from a before/after subtraction or a capacity re-computation.
//
// Smallest-first keeps the granularity property: fine change lives in the small
// slots, so the richer you get the coarser the only cargo you can heave.
ship_stow_cargo :: proc(layout: []Layout_Slot, amount: int) -> (spilled: int) {
	for &layout_slot in layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting && fitting.is_cargo {
			layout_slot.fitting = nil
		}
	}
	remaining := amount
	for size in ([3]Slot_Size{.Small, .Medium, .Large}) {
		for &layout_slot in layout {
			if remaining <= 0 {
				return 0
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
	return remaining // the cargo that found no slot — lost above capacity, never stored
}

// ship_stow_spill reports how much of a prospective new total `amount` would fall
// overboard (ADR-0020, #157) — the overflow a stow would drop — without touching the
// hold. It reads the same capacity ship_stow_cargo fills, so it equals the `spilled`
// that stow would return. It exists for the caller that must name the loss *before*
// the stow happens (the Reward beat), where ship_stow_cargo's after-the-fact return
// is out of reach.
ship_stow_spill :: proc(s: Ship, amount: int) -> int {
	return max(0, amount - ship_cargo_capacity(s))
}

// ship_remove takes the fitting out of layout_slot, leaving the slot empty, and
// returns it (ADR-0012's manual loadout). There is no inventory: the returned
// fitting is the caller's to discard. Returns false (and a zero Fitting) when the
// slot was already empty, so a remove of nothing is a caller-visible rejection
// rather than a silent no-op.
ship_remove :: proc(layout_slot: ^Layout_Slot) -> (Fitting, bool) {
	fitting, occupied := layout_slot.fitting.?
	if !occupied {
		return {}, false
	}
	layout_slot.fitting = nil
	return fitting, true
}

// ship_move relocates the fitting in `from` into the empty `to` under ADR-0004's
// exact-size fit rule: the source must hold a fitting, the destination must be
// empty, and the two slots must be the same size. Any of those unmet leaves both
// slots untouched and returns false. On success the moved fitting is returned and
// the source is left empty. Takes the two slots by pointer, like ship_fit /
// ship_remove, so the caller resolves and bounds-checks the indices itself.
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

// Captain is structurally separate from the slot system: not a fitting, consumes
// no slot. A voyage-start choice that can influence a ship's starting state and
// grants additional manual per-round captain actions. starting_cargo_bonus is this
// slice's one concrete lever: cargo the captain adds to the ship's bootstrap stow
// on top of STARTING_CARGO, filling the headroom the hull already has.
Captain :: struct {
	name:                 string,
	starting_cargo_bonus: int,
}
