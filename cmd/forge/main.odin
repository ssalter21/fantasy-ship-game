package main

import forge "../../forge"

// The thin adapter ADR-0003 wants each executable to be: the Forge's window, its screens
// and its authoring model all live in the forge package, and this main only starts it.
//
// It is the third executable in the repo, beside cmd/headless and cmd/game. It links
// against core and forge and **not** against presentation, which is what keeps the tool's
// widgets out of the shipped game.
//
// This package deliberately carries no tests (the standards' every-package rule): there is
// nothing here but the call below, and everything it reaches is tested in-package in
// forge.
main :: proc() {
	forge.run()
}
