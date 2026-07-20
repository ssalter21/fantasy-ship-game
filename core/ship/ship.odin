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

// Effect_Kind is an Effect's **verb**: what its resolved magnitude does, and thereby
// which consumer reads it. Two kinds feed a combat phase and one adjusts a ship stat:
//
//   - Phase_Contribution (the zero value) is the damage a Fire fitting deals.
//   - Repair is the Hull a Brace fitting restores, capped at the ship's maximum
//     (ADR-0027).
//   - Modify_Speed adjusts the owning ship's effective Speed (ship_effective_speed)
//     rather than feeding a phase, so it is the one kind that rides on either
//     category.
//
// ship_phase_verb is the pairing between the two phase-feeding kinds and the phase
// that consumes each.
Effect_Kind :: enum {
	Phase_Contribution,
	Repair,
	Modify_Speed,
}

// ship_phase_verb is the Effect_Kind a phase's fittings resolve through (ADR-0027):
// Fire deals damage, Brace repairs. It is the single statement of that pairing —
// combat's per-phase totals read it, and the roster is authored against it, so an
// effect whose kind is a phase verb belongs on the phase that consumes it.
ship_phase_verb :: proc(phase: Category) -> Effect_Kind {
	switch phase {
	case .Brace:
		return .Repair
	case .Fire:
		return .Phase_Contribution
	}
	unreachable()
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
// per-slot by every resolve site that iterates a layout (ship_effective_speed,
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
	// weight is the fitting's own mass (ADR-0020) — an authored per-item balance
	// knob that makes a strong item pay for its strength. It is not the whole of
	// what the fitting adds to its ship: cargo weighs 1:1 on top of it, so the
	// effective figure is `weight + cargo_held` (ship_fitting_weight).
	weight:              int,
	// bulk is the *volume* the fitting's own machinery takes inside its slot, and
	// the leftover — `ship_cargo_slot_contribution(size) − bulk` — is what it can
	// carry (ship_fitting_capacity). Weight is mass, bulk is volume: keeping them
	// apart is what makes a gun that also carries authorable at all. An ordinary
	// item authors its full slot contribution and so carries nothing; a hold
	// authors 0 and is the degenerate corner of the axis. **Its zero value is the
	// carrying end**, so every authored fitting must name it — ship_item_roster's
	// no-capacity assertion is what holds that until the roster moves to per-item
	// procs with a defaulted parameter.
	bulk:                int,
	// category is which round phase (ADR-0006) this fitting's active effect
	// triggers in. Meaningless for cargo, which carries no effects.
	category:            Category,
	// tags is the fitting's family membership (see Tag).
	tags:                bit_set[Tag],
	visibility_override: Maybe(Visibility),
	passive:             Maybe(Effect),
	active:              Maybe(Effect),
	// cargo_held is the cargo stowed inside this fitting (ADR-0020): one unit is one
	// unit of cargo and one unit of weight, and summed across the layout it is the
	// ship's cargo (ship_cargo) — a ship's money is nothing but this. It is the one
	// field of a Fitting that moves at runtime; everything else is authored, which
	// is what lets a selector read tags without reading state the budget cannot see.
	// "This fitting is carrying" is `cargo_held > 0`; "this fitting's job is
	// carrying" is Tag.Cargo, authored and never derived from this field.
	cargo_held:          int,
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
	// persistent value combat depletes and repair restores, and max_hull is the ceiling
	// neither may pass. No fitting moves it — a Trade axis is the one thing that does —
	// so it is read directly rather than through an effective-stat reader, and it is
	// what a Ghost_Snapshot resets hull to on capture.
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
// ADR-0004's fit rule, independent of current occupancy: an exact size match, no
// downsizing. The cargo half of the old rule ("stackable and effect-less") is gone
// with the special-cased cargo fitting — carrying is an axis every fitting sits on
// now, so there is no kind of fitting left to hold to a different standard. It is
// the single statement of the fit rule that both ship_fit and ship_replace_fitting
// share, so the two admit exactly the same fittings.
ship_fitting_fits :: proc(size: Slot_Size, fitting: Fitting) -> bool {
	return fitting.size == size
}

// ship_fitting_is_hold reports whether `fitting` is a bare hold — the degenerate
// corner of the cargo axis ship_fitting_hold mints: no bulk, no mass of its own, no
// effects, and Cargo the whole of what it is. Read structurally rather than off a
// flag: an `is_hold: bool` would be the deleted `is_cargo` under a new name, and a
// hold is fully described by its field values.
//
// It exists for the two places that must tell "this slot is spent" from "this slot
// is free": a hold backfills a vacated slot (ship_remove) and a move may land on one
// (ship_move), because a hold is free and unowned and displacing it costs nobody
// anything.
ship_fitting_is_hold :: proc(fitting: Fitting) -> bool {
	if fitting.bulk != 0 || fitting.weight != 0 || fitting.tags != {.Cargo} {
		return false
	}
	_, has_passive := fitting.passive.?
	_, has_active := fitting.active.?
	return !has_passive && !has_active
}

// ship_fitting_capacity is how much cargo one fitting can carry: its slot's size
// contribution less the volume its own machinery takes — `contribution − bulk`,
// clamped to the contribution at both ends so an out-of-band authored bulk reads as
// one of the two corners rather than as a negative hold or an oversized one.
// Derived, never stored, so capacity and bulk cannot drift apart.
//
// Reads the fitting's own size, not the slot's: the fit rule is an exact size match
// (ship_fitting_fits), so an installed fitting's size *is* its slot's.
ship_fitting_capacity :: proc(fitting: Fitting) -> int {
	contribution := ship_cargo_slot_contribution(fitting.size)
	return clamp(contribution - fitting.bulk, 0, contribution)
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
// count, so a phase verb never leaks into a stat total.
ship_fitting_stat_contribution :: proc(fitting: Fitting, kind: Effect_Kind, ctx: Effect_Context) -> int {
	total := 0
	for slot in ([2]Maybe(Effect){fitting.passive, fitting.active}) {
		if effect, ok := slot.?; ok && effect.kind == kind {
			total += int(effect_magnitude(effect, ctx))
		}
	}
	return total
}

// ship_effective_speed is a ship's Speed as combat and escape read it: the raw base
// field, plus every installed fitting's Modify_Speed contribution, less its weight
// (ADR-0020) — `base + Σ Modify_Speed − weight/10`, so no ship's Speed can be read
// without asking what it carries. self_slot is set per iteration so a conditional
// modifier gated on its own concealment resolves against the slot it actually sits in;
// the context carries no battle state, so a battle-state-gated modifier is unmet here.
//
// The `/10` divisor is the cargo↔Speed exchange rate (a full Small hold = 1 Speed,
// Medium = 2, Large = 4) and is forced: any coarser divisor makes jettisoning a Small
// hold buy 0 Speed. Weight is a subtrahend, never a clamp — authoring keeps
// `base − weight/10 >= 0` at every ship's realistic full hold (the floor invariant),
// so `max(0, …)` is never written.
ship_effective_speed :: proc(s: ^Ship) -> int {
	modifiers := 0
	ctx := ship_effect_context(s)
	for layout_slot in s.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
			ctx.self_slot = layout_slot
			modifiers += ship_fitting_stat_contribution(fitting, .Modify_Speed, ctx)
		}
	}
	return s.speed + modifiers - ship_weight(s^) / 10
}

// ship_fitting_weight is what one fitting adds to its ship's weight (ADR-0020): its
// own authored mass plus the cargo stowed in it, 1:1. The two used to be
// alternatives — a cargo fitting weighed its stack, everything else its authored
// figure — but once any fitting can carry, they are terms of one sum: a bare hold
// contributes only its cargo (mass 0), a gun only its mass (it carries nothing), and
// a laden gun both. Guns are permanently heavy and cargo heavy only while stowed, so
// emptiness — not loadout — is still what varies a ship's weight.
ship_fitting_weight :: proc(f: Fitting) -> int {
	return f.weight + f.cargo_held
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

// ship_cargo_capacity is the cargo a ship can carry: the summed capacity of its
// **installed fittings** (ship_fitting_capacity), so a hold contributes its whole
// slot, a gun contributes nothing, and a hybrid contributes its leftover. Overflow
// above this is lost (ship_stow_cargo), never stored: cargo lives inside fittings,
// which live only in finite slots.
//
// An **empty slot carries nothing**, which is forced rather than chosen: were an
// empty slot still to contribute, a free zero-bulk hold would be byte-identical to
// leaving the slot empty and would exist purely as a farmable Cargo-tagged token. The
// accepted consequence is that an empty slot is wasted rather than neutral — which is
// why the starting ship ships with holds and why removing a fitting backfills one
// (ship_remove), so an empty slot is never something a captain has to manage.
ship_cargo_capacity :: proc(s: Ship) -> int {
	capacity := 0
	for layout_slot in s.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
			capacity += ship_fitting_capacity(fitting)
		}
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

// ship_cargo is what a ship carries: the cargo summed across every installed
// fitting (ADR-0020). No filter on *which* fittings — carrying is an axis, so the
// question "does this one count" no longer arises; a fitting that carries nothing
// contributes 0 on its own.
ship_cargo :: proc(s: Ship) -> int {
	cargo := 0
	for layout_slot in s.layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
			cargo += fitting.cargo_held
		}
	}
	return cargo
}

// ship_stow_cargo re-stows `amount` cargo across `layout` by **water-filling**
// (ADR-0020): it empties every fitting first — reallocation is free outside battle,
// so a re-stow rebuilds the hold from scratch — then pours the amount out in equal
// absolute shares over everything with capacity, capping each at its own room and
// cascading the unused share to whoever can still take it. The odd units left when
// the shares no longer divide go to the largest remaining room, ties to the lower
// slot index. The caller passes the desired total, not a delta, so this serves both
// the bootstrap stow and every out-of-battle cargo change (a Reward gain, a Shop or
// Trade spend).
//
// Water-filling replaces smallest-slot-first, which put fine change in the small
// slots and so let a *poor* ship heave a full Small for a Speed gain a rich one had
// to buy with a whole Large. Filling evenly makes the small holds cap out first, so
// jettison granularity is a property of the **build** — how the captain authored
// `bulk` across the layout — rather than of how little they happen to be carrying.
//
// The result is a pure function of `(amount, the capacities present)`: arrangement
// moves nothing but the tie-break, so both the hold's total and the spill are
// independent of slot order. That is what lets every caller keep passing a scalar
// total and re-derive the arrangement from it.
//
// Overflow above capacity is lost and returned as `spilled` (0 when everything fit),
// so the one place the loss actually happens is the one place that reports it — no
// caller re-derives it from a before/after subtraction or a capacity re-computation.
ship_stow_cargo :: proc(layout: []Layout_Slot, amount: int) -> (spilled: int) {
	for &layout_slot in layout {
		if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
			fitting.cargo_held = 0
			layout_slot.fitting = fitting
		}
	}

	remaining := amount
	// Equal shares, pass after pass: each pass divides what is *still* unstowed
	// among the fittings that still have room, so a hold that caps out drops out and
	// its share falls to the rest. Terminates because a pass with a share of at
	// least 1 always stows at least that much.
	for remaining > 0 {
		with_room := 0
		for layout_slot in layout {
			if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
				if ship_fitting_capacity(fitting) > fitting.cargo_held {
					with_room += 1
				}
			}
		}
		share := remaining / max(with_room, 1)
		if with_room == 0 || share == 0 {
			break
		}
		for &layout_slot in layout {
			fitting, has_fitting := layout_slot.fitting.?
			if !has_fitting {
				continue
			}
			stow := min(share, ship_fitting_capacity(fitting) - fitting.cargo_held)
			if stow <= 0 {
				continue
			}
			fitting.cargo_held += stow
			layout_slot.fitting = fitting
			remaining -= stow
		}
	}

	// The remainder — fewer units than there are fittings with room, so no share
	// divides — settles into the largest room going, ties to the lower slot index.
	// Deterministic rather than principled: it is at most a handful of units, and
	// the alternative (leave them unstowed) would spill cargo the ship has room for.
	for remaining > 0 {
		best, best_room := -1, 0
		for layout_slot, index in layout {
			if fitting, has_fitting := layout_slot.fitting.?; has_fitting {
				if room := ship_fitting_capacity(fitting) - fitting.cargo_held; room > best_room {
					best, best_room = index, room
				}
			}
		}
		if best < 0 {
			break
		}
		fitting, _ := layout[best].fitting.?
		stow := min(remaining, best_room)
		fitting.cargo_held += stow
		layout[best].fitting = fitting
		remaining -= stow
	}

	return remaining // the cargo that found no room — lost above capacity, never stored
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

// ship_remove takes the fitting out of layout_slot and returns it (ADR-0012's
// manual loadout). There is no inventory: the returned fitting is the caller's to
// discard. Returns false (and a zero Fitting) when the slot was already empty, so a
// remove of nothing is a caller-visible rejection rather than a silent no-op.
//
// The vacated slot is **backfilled with a size-matched hold** rather than left
// empty. An empty slot carries nothing (ship_cargo_capacity), so leaving one would
// hand the captain a slot that is worse than useless and a rule to remember about
// it; backfilling makes the empty slot unreachable instead, and costs nothing —
// holds are free, untiered and outside the roster. Any cargo the removed fitting was
// carrying goes with it, so a caller that means to *conserve* the hold re-stows the
// prior total afterwards (sim_refit_remove).
ship_remove :: proc(layout_slot: ^Layout_Slot) -> (Fitting, bool) {
	fitting, occupied := layout_slot.fitting.?
	if !occupied {
		return {}, false
	}
	layout_slot.fitting = ship_fitting_hold(layout_slot.slot.size)
	return fitting, true
}

// ship_move relocates the fitting in `from` into `to` under ADR-0004's exact-size
// fit rule: the source must hold a fitting, the destination must be free, and the
// two slots must be the same size. Any of those unmet leaves both slots untouched
// and returns false. On success the moved fitting is returned and the source is
// backfilled with a size-matched hold, exactly as ship_remove does.
//
// "Free" means empty **or carrying nothing but a bare hold** (ship_fitting_is_hold).
// Once every vacated slot backfills, a genuinely empty slot is unreachable in play,
// so an empty-only rule would delete rearranging outright; and a hold is free and
// unowned, so displacing one takes nothing from anybody. A laden destination hold
// loses its cargo with it, so a caller that means to conserve the hold re-stows the
// prior total afterwards (sim_refit_move).
//
// Takes the two slots by pointer, like ship_fit / ship_remove, so the caller
// resolves and bounds-checks the indices itself.
ship_move :: proc(from, to: ^Layout_Slot) -> (Fitting, bool) {
	fitting, occupied := from.fitting.?
	if !occupied {
		return {}, false
	}
	if dest, dest_occupied := to.fitting.?; dest_occupied && !ship_fitting_is_hold(dest) {
		return {}, false
	}
	if fitting.size != to.slot.size {
		return {}, false
	}
	from.fitting = ship_fitting_hold(from.slot.size)
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
