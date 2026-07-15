// PROTOTYPE — THROWAWAY. Delete me once #158 is answered.
//
// Question (#158): under the weight model, does a *derived* hostile Speed spread
// still straddle the player's 4 — the property #135 hand-authored and pinned?
//
// Method: build every archetype's real layout out of the real roster items and the
// real template, author candidate weights in #156's band, run candidate curves over
// the result, and print the eight Speeds against the player's. No production code is
// touched; this reads core/ship and core/run and prints.
#+feature dynamic-literals
package main

import "../../core/run"
import "../../core/ship"
import "core:fmt"

// Authored weights, in #156's band (Large 30-45, Medium 15-25, Small 5-12), aimed at
// character: iron is heavy, canvas is light. Placeholders — the point is the *shape*
// of the spread, not these numbers.
item_weights := map[string]int {
	// Large
	"Long Nines"        = 42, // a big gun, all iron
	"Ramming Prow"      = 40,
	"Gun Deck"          = 38,
	// Medium
	"Reinforced Hull"   = 25,
	"Iron Plating"      = 24,
	"Carronade"         = 22,
	"Wraith Cannon"     = 22,
	"Naval Gun Crew"    = 20,
	"Kraken Spawn"      = 20,
	"Deck Cannon"       = 18,
	"Hunter's Pack"     = 18,
	"Captain's Quarters" = 18,
	"Admiral's Guard"   = 17,
	"Copper Sheathing"  = 16,
	"Top Crew"          = 16,
	"Storm Sails"       = 15, // canvas
	// Small
	"Ballast Stones"    = 12, // stones. heavy by definition
	"Swivel Guns"       = 8,
	"Snapping Eels"     = 7,
	"War Hound"         = 7,
	"Boarding Pikes"    = 6,
	"Powder Monkeys"    = 6,
	"Deckhands"         = 6,
	"Boarding Nets"     = 5,
	"Spare Rigging"     = 5,
	"Ghost Lantern"     = 5,
}

// Fallback for any roster item this prototype didn't author: band midpoint by size.
size_default :: proc(size: ship.Slot_Size) -> int {
	switch size {
	case .Small:
		return 8
	case .Medium:
		return 20
	case .Large:
		return 38
	}
	return 0
}

fitting_weight :: proc(f: ship.Fitting) -> int {
	if w, ok := item_weights[f.name]; ok {
		return w
	}
	return size_default(f.size)
}

// #156's capacity table: x10 and doubling.
slot_capacity :: proc(size: ship.Slot_Size) -> int {
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

Build :: struct {
	name:           string,
	authored_speed: int, // #135's hand-authored number, for comparison
	fitting_weight: int, // the guns/armour: permanent
	cargo_capacity: int, // how much money the empty holds could hold
	speed_modifier: int, // sum of Modify_Speed passives (Storm Sails, Spare Rigging...)
}

// weight_at returns the build's total weight when its holds are `laden_percent` full.
weight_at :: proc(b: Build, laden_percent: int) -> int {
	return b.fitting_weight + (b.cargo_capacity * laden_percent) / 100
}

build_from_layout :: proc(name: string, authored_speed: int, layout: []ship.Layout_Slot) -> Build {
	b := Build{name = name, authored_speed = authored_speed}
	for layout_slot in layout {
		fitting, has_fitting := layout_slot.fitting.?
		if !has_fitting {
			continue
		}
		if fitting.is_cargo {
			// A hold weighs its contents; empty it weighs nothing. Its *capacity* is
			// what the slot could hold.
			b.cargo_capacity += slot_capacity(layout_slot.slot.size)
		} else {
			b.fitting_weight += fitting_weight(fitting)
			// Modify_Speed rides on the passive (unscaled by the site) — the
			// "+ modifiers" term the destination insists must still land.
			if effect, ok := fitting.passive.?; ok && effect.kind == .Modify_Speed {
				b.speed_modifier += int(effect.magnitude)
			}
		}
	}
	return b
}

hostile_builds :: proc(allocator := context.allocator) -> []Build {
	roster := run.run_hostile_roster()
	builds := make([dynamic]Build, allocator)
	for archetype in roster {
		layout := ship.ship_template_layout()
		defer delete(layout)
		// power_percent is irrelevant to weight (it scales magnitudes, not sizes);
		// 100 = Open Sea, the zone the table is authored at.
		ok := run.run_fit_hostile_loadout(layout, archetype, 100)
		assert(ok, "prototype: hostile loadout failed to fit")
		append(&builds, build_from_layout(archetype.name, archetype.speed, layout))
	}
	return builds[:]
}

player_build :: proc() -> Build {
	s := ship.ship_starting_ship()
	defer delete(s.layout)
	return build_from_layout("PLAYER (starting ship)", ship.STARTING_SPEED, s.layout)
}

// ---- the curves ----------------------------------------------------------------

// Linear divisor: speed = base - weight/divisor, base calibrated so that the player's
// starting ship (3 fittings + the 50-treasure purse) reads exactly STARTING_SPEED.
Curve :: struct {
	divisor: int,
	base:    int,
}

// speed = base + modifiers - weight/divisor. The destination's shape:
// weight is a subtrahend, modifiers still land, the result is an int.
curve_speed :: proc(c: Curve, weight: int, modifier: int) -> int {
	return c.base + modifier - weight / c.divisor
}

// purse_window returns the range of purses that make this build read exactly
// `target` Speed under `c` — the inverse of curve_speed. Reports whether that
// window intersects what the build's holds can physically carry [0, capacity].
purse_window :: proc(c: Curve, b: Build, target: int) -> (lo: int, hi: int, fits: bool) {
	// target = base + mod - (fittings+purse)/divisor  =>  (fittings+purse)/divisor = k
	k := c.base + b.speed_modifier - target
	if k < 0 {
		return 0, 0, false // unreachable: build is faster than target even at zero weight
	}
	lo = k * c.divisor - b.fitting_weight
	hi = k * c.divisor + c.divisor - 1 - b.fitting_weight
	lo = max(lo, 0)
	fits = lo <= hi && lo <= b.cargo_capacity
	return lo, hi, fits
}

// pad renders an int right-aligned in `width` without fmt's zero-padding.
pad :: proc(v: int, width: int) -> string {
	s := fmt.tprintf("%d", v)
	for len(s) < width {
		s = fmt.tprintf(" %s", s)
	}
	return s
}

calibrate :: proc(divisor: int, player_weight: int) -> Curve {
	// base such that curve_speed(player_weight) == STARTING_SPEED
	return Curve{divisor = divisor, base = ship.STARTING_SPEED + player_weight / divisor}
}

main :: proc() {
	player := player_build()
	// The player starts with STARTING_TREASURE in the holds.
	player_start_weight := player.fitting_weight + ship.STARTING_TREASURE

	fmt.println("=== #158 PROTOTYPE: does a derived hostile Speed spread still straddle 4? ===")
	fmt.println()
	fmt.printf(
		"PLAYER starting ship: fittings %d + purse %d = weight %d   (holds could take %d)\n",
		player.fitting_weight,
		ship.STARTING_TREASURE,
		player_start_weight,
		player.cargo_capacity,
	)
	fmt.printf(
		"  broke (empty holds): %d      rich (holds full): %d\n",
		player.fitting_weight,
		player.fitting_weight + player.cargo_capacity,
	)
	fmt.println()

	builds := hostile_builds()
	defer delete(builds)

	fmt.println("--- The exchange rate: what does jettisoning one hold buy? ---")
	fmt.printf("%-10s %14s %14s %14s\n", "divisor", "Small (10)", "Medium (20)", "Large (40)")
	for divisor in ([?]int{10, 15, 20, 25}) {
		fmt.printf(
			"%-10s %14s %14s %14s\n",
			pad(divisor, 10),
			pad(10 / divisor, 14),
			pad(20 / divisor, 14),
			pad(40 / divisor, 14),
		)
	}
	fmt.println("  (points of Speed bought by heaving a FULL hold of that size overboard)")
	fmt.println()

	fmt.println("--- The eight archetypes: what they weigh ---")
	fmt.printf(
		"%-22s %5s %5s %9s %9s %7s %7s %8s\n",
		"archetype",
		"#135",
		"+spd",
		"fittings",
		"capacity",
		"@0%",
		"@100%",
		"fit+cap",
	)
	for b in builds {
		fmt.printf(
			"%-22s %5s %5s %9s %9s %7s %7s %8s\n",
			b.name,
			pad(b.authored_speed, 5),
			pad(b.speed_modifier, 5),
			pad(b.fitting_weight, 9),
			pad(b.cargo_capacity, 9),
			pad(weight_at(b, 0), 7),
			pad(weight_at(b, 100), 7),
			pad(b.fitting_weight + b.cargo_capacity, 8),
		)
	}
	fmt.println()
	fmt.println("  NOTE the last column: fittings+capacity is near-constant across all eight.")
	fmt.println("  Heavy items sit in big slots, so a heavy build has less room for money.")
	fmt.println()

	// The load-bearing unknown: how laden is a hostile? Today its "Spoils" cargo is
	// CARGO_STACK_COUNT :: 1 — i.e. essentially empty. #159 owns the real answer.
	ladens := [?]int{0, 25, 50, 75, 100}
	// The divisor IS the exchange rate: how much treasure buys one point of Speed.
	// 10 is the granularity floor worth testing — a Small hold holds 10, and if
	// jettisoning the smallest hold buys 0 Speed, jettison is a no-op.
	divisors := [?]int{10, 15, 20, 25}

	for divisor in divisors {
		curve := calibrate(divisor, player_start_weight)
		fmt.printf(
			"=== CURVE: speed = %d - weight/%d  (calibrated so player start = %d) ===\n",
			curve.base,
			curve.divisor,
			ship.STARTING_SPEED,
		)
		fmt.printf("%-22s %5s", "archetype", "#135")
		for laden in ladens {
			fmt.printf("  laden%3d%%", laden)
		}
		fmt.println()
		for b in builds {
			fmt.printf("%-22s %5s", b.name, pad(b.authored_speed, 5))
			for laden in ladens {
				fmt.printf("  %9s", pad(curve_speed(curve, weight_at(b, laden), b.speed_modifier), 9))
			}
			fmt.println()
		}
		// The straddle check, per ladenness: does the spread put hostiles on BOTH
		// sides of the player's 4?
		fmt.printf("%-22s %5s", "-> straddles 4?", "")
		for laden in ladens {
			slower, faster := 0, 0
			for b in builds {
				sp := curve_speed(curve, weight_at(b, laden), b.speed_modifier)
				if sp < ship.STARTING_SPEED {
					slower += 1
				}
				if sp > ship.STARTING_SPEED {
					faster += 1
				}
			}
			verdict := "NO"
			if slower > 0 && faster > 0 {
				verdict = "yes"
			}
			fmt.printf("  %4s %d/%d", verdict, slower, faster)
		}
		fmt.println()
		fmt.println("     (verdict, then how many are slower than the player / faster than the player)")
		fmt.println()
	}

	// ---- The proposal: the archetype authors its PURSE, not its Speed -----------
	//
	// If a hostile's money is authored per archetype, Speed falls out of it. Can the
	// purse reproduce #135's hand-authored spread exactly — and does the required
	// purse fit in the archetype's own holds?
	fmt.println("=== PROPOSAL: archetype authors treasure, Speed is derived ===")
	fmt.println("What purse must each archetype carry to read exactly #135's authored Speed?")
	fmt.println()
	for divisor in divisors {
		curve := calibrate(divisor, player_start_weight)
		fmt.printf("--- curve: speed = %d + mods - weight/%d ---\n", curve.base, curve.divisor)
		fmt.printf(
			"%-22s %5s %9s %9s %9s\n",
			"archetype",
			"#135",
			"purse lo",
			"purse hi",
			"capacity",
		)
		all_fit := true
		for b in builds {
			lo, hi, fits := purse_window(curve, b, b.authored_speed)
			verdict := "ok"
			if !fits {
				verdict = "IMPOSSIBLE"
				all_fit = false
			} else if hi > b.cargo_capacity {
				verdict = "ok (hi clipped to capacity)"
			}
			fmt.printf(
				"%-22s %5s %9s %9s %9s  %s\n",
				b.name,
				pad(b.authored_speed, 5),
				pad(lo, 9),
				pad(hi, 9),
				pad(b.cargo_capacity, 9),
				verdict,
			)
		}
		if all_fit {
			fmt.println("  => #135's ENTIRE SPREAD IS REPRODUCIBLE from authored purses.")
		} else {
			fmt.println("  => some entries cannot reach their authored Speed at any purse.")
		}
		fmt.println()
	}
}
