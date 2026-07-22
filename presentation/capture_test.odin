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
