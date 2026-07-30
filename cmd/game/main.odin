package main

import "core:os"
import presentation "../../presentation"

// The thin adapter ADR-0003 wants each executable to be: every screen, the session
// loop, capture mode and the hull workbench live in the presentation package (#433),
// and this main only picks which of its entries the process runs — one named screen
// behind --shot, the scripted capture walk behind --capture, the hull contact sheet
// behind --hull-sheet, the hull or a named 2D screen behind --workbench, or the
// player-facing session.
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
		// A short set is a failure too: the manifest check reads these back, and a missing
		// shot leaves the stale PNG it would have overwritten to be compared in its place.
		if !presentation.capture_shots_main() {
			os.exit(1)
		}
		return
	}
	if presentation.hull_sheet_requested() {
		// A sheet that could not be written is a failure like any other shot: exit non-zero so a
		// session asking for the hull's six angles never reads a stale sheet as this run's.
		if !presentation.hull_sheet_main() {
			os.exit(1)
		}
		return
	}
	// PROTOTYPE — throwaway, and this dispatch goes out with it. The world-register
	// prototype for issue #512: nine frames of the galleon in three structurally
	// different worlds, as a sheet, or steerable in the real window.
	if presentation.world_proto_requested() {
		if !presentation.world_proto_main() {
			os.exit(1)
		}
		return
	}
	if presentation.world_proto_live_requested() {
		if !presentation.world_proto_live_main() {
			os.exit(1)
		}
		return
	}
	if presentation.capture_requested() {
		presentation.capture_main()
		return
	}
	if presentation.workbench_requested() {
		// A screen the workbench does not know is a failure like an unknown --shot: exit
		// non-zero rather than silently opening the hull instead of what was asked for.
		if !presentation.workbench_main() {
			os.exit(1)
		}
		return
	}
	presentation.run()
}
