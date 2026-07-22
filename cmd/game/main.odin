package main

import presentation "../../presentation"

// The thin adapter ADR-0003 wants each executable to be: every screen, the session
// loop and capture mode live in the presentation package (#433), and this main only
// picks which of its entries the process runs — the scripted capture walk behind
// --capture, or the player-facing session.
main :: proc() {
	if presentation.capture_requested() {
		presentation.capture_main()
		return
	}
	presentation.run()
}
