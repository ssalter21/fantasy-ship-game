package presentation

import "core:slice"
import "core:testing"
import sim "../core/sim"

// This covers the windowless sliver of capture that is the package's own — the
// scripted player it answers decisions with is tested where it lives, in core/sim.
// The drawing half can't be tested here for the same reason the menu loops can't:
// rl.IsWindowReady() is false under `odin test`, and every shot guards on it.

@(test)
capture_phase_slug_names_every_phase_distinctly :: proc(t: ^testing.T) {
	seen: map[string]bool
	defer delete(seen)

	for phase in sim.Phase {
		slug := capture_phase_slug(phase)
		testing.expect(t, slug != "unknown", "every phase should name its own screen")
		testing.expect(t, !seen[slug], "two phases should not share a filename")
		seen[slug] = true
	}
}

@(test)
capture_shots_name_every_shot_once :: proc(t: ^testing.T) {
	seen: map[string]bool
	defer delete(seen)

	for shot in capture_shots {
		testing.expect(t, shot.name != "", "a shot needs a name to be asked for by")
		testing.expectf(t, shot.frame != nil, "%s needs the proc that composes it", shot.name)
		testing.expectf(t, !seen[shot.name], "two shots share the name %s", shot.name)
		seen[shot.name] = true
	}
}

// A state a mouse reaches is shootable only for as long as it is an entry, so the ones the
// registry exists to carry — a hover, a drag, an animation caught mid-raise — are named
// here rather than left to be hard-coded into a frame for one run.
@(test)
capture_shots_name_the_states_a_mouse_reaches :: proc(t: ^testing.T) {
	names := make([dynamic]string, 0, len(capture_shots))
	defer delete(names)
	for shot in capture_shots {
		append(&names, shot.name)
	}

	for named in ([?]string {
			"chart-table-hover", // a hovered button
			"build-hover", // a hovered berth
			"build-placing", // a drag in flight
			"home-chart-rising", // an animation caught mid-raise
		}) {
		testing.expectf(t, slice.contains(names[:], named), "%s should be a shot, not a source edit", named)
	}
}

// A targeted shot has to land on the file a full --capture run would write, so a shot's
// number is its position in the table.
@(test)
capture_shot_for_numbers_shots_in_walk_order :: proc(t: ^testing.T) {
	for shot, i in capture_shots {
		found, number, ok := capture_shot_for(shot.name)
		testing.expectf(t, ok, "%s should be findable by name", shot.name)
		testing.expectf(t, number == i, "%s should carry number %d", shot.name, i)
		testing.expectf(t, found.name == shot.name, "%s should find the shot it names", shot.name)
	}
}

@(test)
capture_shot_for_rejects_an_unknown_name :: proc(t: ^testing.T) {
	_, _, ok := capture_shot_for("no-such-screen")
	testing.expect(t, !ok, "an unnamed screen should not resolve to a shot")
}

// The walk's own screens are asked for by the same name their files carry, so every phase
// slug is a name --shot answers to. Their numbers fall out of the walk rather than a table,
// which is why they are looked up by name alone.
@(test)
capture_voyage_named_takes_every_phase :: proc(t: ^testing.T) {
	for phase in sim.Phase {
		slug := capture_phase_slug(phase)
		testing.expectf(t, capture_voyage_named(slug), "%s should be askable for by name", slug)
	}
	testing.expect(t, !capture_voyage_named("no-such-screen"), "an unnamed screen is not a voyage screen")
}

// The two halves of the gallery share one run of numbers: the walk's first shot takes the
// number after the registry's last, so no walked shot can land on a standalone one's file.
// This is what makes a targeted walk — which shoots none of the registry — write the same
// filename the full gallery gives that screen.
@(test)
capture_voyage_numbers_run_on_from_the_registry :: proc(t: ^testing.T) {
	testing.expect_value(t, capture_voyage_number(0), len(capture_shots))
	for _, i in capture_shots {
		testing.expectf(
			t,
			capture_voyage_number(0) > i,
			"the walk's first shot should number past %s",
			capture_shots[i].name,
		)
	}

	// Passing a screen spends its number whether or not it is the one being shot, so the
	// count is of screens reached rather than of shots written.
	testing.expect_value(t, capture_voyage_number(3) - capture_voyage_number(2), 1)
}

// A name has to mean exactly one screen: the two classes are tried in order, so a name in
// both would make the standalone entry shadow the voyage screen and a --shot for it would
// silently photograph the wrong thing.
@(test)
capture_names_belong_to_one_class :: proc(t: ^testing.T) {
	for shot in capture_shots {
		testing.expectf(
			t,
			!capture_voyage_named(shot.name),
			"%s names both a standalone shot and a voyage screen",
			shot.name,
		)
	}
}

@(test)
capture_shot_arg_reads_the_requested_name :: proc(t: ^testing.T) {
	name, requested := capture_shot_arg({"--shot", "build"})
	testing.expect(t, requested, "--shot <name> is a shot request")
	testing.expect(t, name == "build", "the name follows the flag")

	name, requested = capture_shot_arg({"--shot=build-hover"})
	testing.expect(t, requested, "--shot=<name> is a shot request")
	testing.expect(t, name == "build-hover", "the name follows the equals")

	// A bare --shot is still a request, and falls into the same unknown-name report
	// that lists what can be asked for.
	name, requested = capture_shot_arg({"--shot"})
	testing.expect(t, requested, "a bare --shot is a shot request")
	testing.expect(t, name == "", "a bare --shot names nothing")

	name, requested = capture_shot_arg({"--shot", "--capture"})
	testing.expect(t, requested, "--shot before another flag is still a request")
	testing.expect(t, name == "", "a following flag is not this flag's name")

	_, requested = capture_shot_arg({"--capture"})
	testing.expect(t, !requested, "the scripted walk is not a shot request")
}

// A shot has to be the same frame twice or a hash of it records only that time passed, so the
// clock the chart's idle motion rides is one capture pins rather than reads.
@(test)
capture_pins_the_clock_the_chart_rides :: proc(t: ^testing.T) {
	defer juice_clock_pinned = nil

	juice_clock_pinned = nil
	juice_clock_pin(CAPTURE_CLOCK)
	testing.expect(t, juice_now() == CAPTURE_CLOCK, "a pinned clock reads back the instant it was pinned at")
	testing.expect(t, juice_now() == juice_now(), "two frames of one shot see one instant")

	// Off the zero crossing, so the moored hull photographs mid-rock rather than at rest.
	bob, heel := ship_rock(CAPTURE_CLOCK, false)
	testing.expect(t, bob != 0, "a shot should catch the ship off its bob's zero crossing")
	testing.expect(t, heel != 0, "a shot should catch the ship heeled")
}

// --shots renders the whole registry and --shot names one of it. They share a prefix, so
// the flag that takes a name must not swallow the flag that takes none — a --shots run
// read as a shot request would go looking for a screen and exit 1 without shooting any.
@(test)
capture_shots_flag_is_not_a_targeted_shot :: proc(t: ^testing.T) {
	_, requested := capture_shot_arg({"--shots"})
	testing.expect(t, !requested, "--shots asks for the whole set, not for one screen")

	testing.expect(t, capture_shots_arg({"--shots"}), "--shots asks for the whole set")
	testing.expect(t, !capture_shots_arg({"--shot", "build"}), "one named screen is not the whole set")
	testing.expect(t, !capture_shots_arg({"--capture"}), "the scripted walk is not the whole set")
}
