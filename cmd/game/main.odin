package main

import "core:os"
import presentation "../../presentation"

// The thin adapter ADR-0003 wants each executable to be: every screen, the session
// loop, capture mode and the hull workbench live in the presentation package (#433),
// and this main only picks which of its entries the process runs — one named screen
// behind --shot, the scripted capture walk behind --capture, the hull workbench behind
// --workbench, or the player-facing session.
//
// This package deliberately carries no tests (the standards' every-package rule):
// there is nothing here but the dispatch below, and everything it calls is tested
// in-package in presentation.
main :: proc() {
	if name, requested := presentation.capture_shot_requested(); requested {
		// A shot that does not land is a failure, not a blank run: exit non-zero so a
		// script asking for a screen fails rather than reads a stale PNG.
		if !presentation.capture_shot_main(name) {
			os.exit(1)
		}
		return
	}
	if presentation.capture_shots_requested() {
		// Same reason, over the whole set: the manifest check reads these back, and a
		// missing shot must fail the run rather than leave a stale PNG to be compared.
		if !presentation.capture_shots_main() {
			os.exit(1)
		}
		return
	}
	if presentation.capture_requested() {
		presentation.capture_main()
		return
	}
	if presentation.workbench_requested() {
		presentation.workbench_main()
		return
	}
	presentation.run()
}
