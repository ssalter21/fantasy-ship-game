package presentation

import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:testing"

// **No screen strokes its own chrome.**
//
// Five screens each grew their own implementation of "a rectangle with text in it", and the
// cost was not the duplication — it was that a look change had to be made five times and
// therefore never was. The widget layer retires that, and this is what stops it coming back:
// the rule is checked rather than remembered, so a new screen cannot quietly reintroduce the
// pattern and a reviewer does not have to notice.
//
// It reads the package's own source. That is unusual, and it is the technique this repo
// already uses for facts about the code that no runtime value can carry — the manifest check
// (scripts/shot.py) is the same idea one level up. A screen calling rl.DrawRectangleRec to
// build chrome is a fact about the source, not about any value the program computes.

// The calls that build a rectangle by hand. A screen wanting one of these wants a widget.
//
// Every way raylib fills or outlines a rectangle, not just the two the migrations happened to
// use — a contract that named two spellings of the same act would be one rename away from
// nothing, and `rl.DrawRectangle` is the same chrome as `rl.DrawRectangleRec`.
//
// Deliberately absent: the gradient calls. `DrawRectangleGradientV/H` draw the vignette, the
// title scrim and the sky — atmosphere and world, which have no widget and should not. A
// screen that built a *panel* out of a gradient would slip through, and that is the known
// edge of this check rather than an oversight.
@(private = "file")
STROKED_CHROME := [?]string {
	"rl.DrawRectangle(",
	"rl.DrawRectangleRec(",
	"rl.DrawRectangleV(",
	"rl.DrawRectanglePro(",
	"rl.DrawRectangleLines(",
	"rl.DrawRectangleLinesEx(",
}

// Where a hand-stroked rectangle is still legitimate, and why. Every entry is a claim that
// the rectangles in that file are **not chrome** — and each one is worth re-reading when the
// file changes, which is the point of naming them here rather than leaving the rule to
// judgement.
@(private = "file")
Exempt :: struct {
	file:   string,
	reason: string,
}

@(private = "file")
EXEMPT := [?]Exempt {
	// The widget layer is where the rectangles went. It is the implementation of the rule, so
	// it cannot be subject to it.
	{"ui_widgets.odin", "the widgets themselves"},
	{"ui_frame.odin", "the blit the widgets are built on"},

	// World, not chrome: these draw the sea, the sky and the ship. A rectangle here is a band
	// of water or a hull's belly, and there is no widget for those and should not be.
	{"backdrop.odin", "the sky and sea bands — the world"},
	{"build_surface.odin", "the hull's belly shade — the world, drawn inside the cutaway"},
	{"ship_sea.odin", "the water around her"},

	// Tools, not screens. A player never sees these, and the guide's rules are about what a
	// player sees.
	{"workbench.odin", "the workbench's slider panel — a tool, never in a player session"},
	{"hull_sheet.odin", "the contact sheet's caption plate — a tool's output, not a screen"},
	// PROTOTYPE — throwaway, and this exemption goes out with it (#512). Its rectangles are
	// candidate sea, sky and island plates plus a caption, and no player session can reach it.
	{"world_proto.odin", "the world-register prototype's plates and caption — throwaway (#512)"},

	// The voyage screens the guide has not re-coloured yet. These draw on the superseded navy
	// ramp, and the widgets are parchment: migrating them is a re-colour, which the style
	// guide defers rather than this effort smuggling in. Named here so the debt is visible and
	// finite rather than invisible and assumed done.
	{"encounter_frame.odin", "not yet re-coloured off the navy ramp (style guide, out of scope)"},
	{"fight.odin", "not yet re-coloured off the navy ramp (style guide, out of scope)"},
	{"trade.odin", "not yet re-coloured off the navy ramp (style guide, out of scope)"},
	{"view.odin", "the chart's own marks and the voyage strip, not yet re-coloured"},
}

@(private = "file")
exempt_for :: proc(file: string) -> (reason: string, ok: bool) {
	for entry in EXEMPT {
		if entry.file == file {
			return entry.reason, true
		}
	}
	return "", false
}

// The screens that have been migrated cannot go back. This walks the package's sources and
// fails on a hand-stroked rectangle in any file the exemption list does not name — so adding
// one to a migrated screen fails the build, and adding a new screen that strokes its own
// chrome fails it too.
@(test)
no_screen_strokes_its_own_chrome :: proc(t: ^testing.T) {
	sources, found := package_sources()
	if !found {
		// `odin test` can be run from anywhere; without the sources there is nothing to check
		// and a pass here would be a lie, so say so.
		testing.fail_now(t, "could not read the package's sources to check the chrome contract")
	}
	for path in sources {
		file := filepath.base(path)
		if strings.has_suffix(file, "_test.odin") {
			continue
		}
		body, read := os.read_entire_file_from_path(path, context.temp_allocator)
		if read != nil {
			continue
		}

		strokes := false
		for call in STROKED_CHROME {
			if strings.contains(string(body), call) {
				strokes = true
			}
		}
		_, exempt := exempt_for(file)
		testing.expectf(
			t,
			!strokes || exempt,
			"%s strokes its own chrome. Use the widgets (ui_widgets.odin), or add %s to EXEMPT "+
			"with the reason its rectangles are not chrome.",
			file,
			file,
		)
	}
}

// An exemption naming a file that no longer exists is a rule nobody is following any more,
// and it would silently cover the next file to take that name.
@(test)
every_chrome_exemption_still_names_a_file :: proc(t: ^testing.T) {
	sources, found := package_sources()
	if !found {
		testing.fail_now(t, "could not read the package's sources to check the exemption list")
	}
	names := make([dynamic]string, 0, len(sources), context.temp_allocator)
	for path in sources {
		append(&names, filepath.base(path))
	}

	for entry in EXEMPT {
		testing.expectf(t, slice.contains(names[:], entry.file), "%s is exempted but does not exist", entry.file)
		testing.expectf(t, entry.reason != "", "%s is exempted without saying why", entry.file)
	}
}

// package_sources is every .odin file beside this one. The test runs with the package
// directory as its working directory under `odin test presentation`, and falls back to the
// path from the repo root so a run from anywhere else still finds them.
//
// Tick-lifetime: the paths come from the temp allocator and are reclaimed with it, so no
// caller hand-frees them (the standards' three lifetimes, ADR-0010).
@(private = "file")
package_sources :: proc() -> (paths: []string, ok: bool) {
	for root in ([?]string{".", "presentation"}) {
		pattern, join_err := filepath.join({root, "*.odin"}, context.temp_allocator)
		if join_err != nil {
			continue
		}
		matches, err := filepath.glob(pattern, context.temp_allocator)
		if err == nil && len(matches) > 0 {
			return matches, true
		}
	}
	return nil, false
}
