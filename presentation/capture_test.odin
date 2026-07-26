package presentation

import "core:testing"
import sim "../core/sim"

// This covers the windowless sliver of capture that is the package's own — the
// scripted player it answers decisions with is tested where it lives, in core/sim.
// The drawing half can't be tested here for the same reason the menu loops can't:
// rl.IsWindowReady() is false under `odin test`, and capture_shot guards on it.

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
capture_shot_groups_name_every_shot_once :: proc(t: ^testing.T) {
	seen: map[string]bool
	defer delete(seen)

	for group in capture_shot_groups {
		testing.expect(t, group.shoot != nil, "every group needs the proc that shoots it")
		testing.expect(t, len(group.names) > 0, "a group that writes no shot cannot be asked for")
		for name in group.names {
			testing.expect(t, name != "", "a shot needs a name to be asked for by")
			testing.expectf(t, !seen[name], "two shots share the name %s", name)
			seen[name] = true
		}
	}
}

// A targeted shot has to land on the file a full --capture run would write, so the
// group's start index must be its position in the flattened walk order.
@(test)
capture_shot_group_for_numbers_groups_in_walk_order :: proc(t: ^testing.T) {
	walked := 0
	for group in capture_shot_groups {
		for name, offset in group.names {
			found, start, ok := capture_shot_group_for(name)
			testing.expectf(t, ok, "%s should be findable by name", name)
			testing.expectf(t, start == walked, "%s should start its group at %d", name, walked)
			testing.expectf(
				t,
				len(found.names) == len(group.names) && found.names[offset] == name,
				"%s should find the group that writes it",
				name,
			)
		}
		walked += len(group.names)
	}
}

@(test)
capture_shot_group_for_rejects_an_unknown_name :: proc(t: ^testing.T) {
	_, _, ok := capture_shot_group_for("no-such-screen")
	testing.expect(t, !ok, "an unnamed screen should not resolve to a group")
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

	_, requested = capture_shot_arg({"--capture"})
	testing.expect(t, !requested, "the scripted walk is not a shot request")
}
