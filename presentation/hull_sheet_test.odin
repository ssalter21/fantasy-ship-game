package presentation

import "core:fmt"
import "core:math"
import "core:testing"
import cutaway "./cutaway"

// The hull sheet's own windowless sliver: which eyes it holds, that each stands where its name
// says, which paints it takes them in, and that the grid tiles the sheet. The drawing half can't
// be tested here for the same reason capture's can't — rl.IsWindowReady() is false under
// `odin test`, and hull_sheet_main guards on it. What a rendered sheet looks like is checked by
// looking at one.

@(test)
hull_sheet_holds_six_named_eyes :: proc(t: ^testing.T) {
	eyes := hull_sheet_eyes()
	seen: map[string]bool
	defer delete(seen)
	for tile in eyes {
		testing.expect(t, tile.name != "", "an eye needs a name to be labelled and reasoned about by")
		testing.expectf(t, !seen[tile.name], "two tiles share the name %s", tile.name)
		seen[tile.name] = true
	}

	// The six are canonical: a session told to read the sheet is told these names, so dropping or
	// renaming one is a change to the instrument rather than a tweak to a table.
	for named in ([?]string{"bow", "stern", "beam", "quarter", "above", "below"}) {
		testing.expectf(t, seen[named], "%s should be one of the sheet's eyes", named)
	}
}

// Every eye in every paint, and each row one paint. The rows are the reading: a face that is a
// wrong colour in normal paint is only a defect if the shaded tile directly above it is the same
// hull from the same place, and a mode the sheet skipped is a mode a headless session cannot see
// at all.
@(test)
hull_sheet_takes_every_eye_in_every_paint :: proc(t: ^testing.T) {
	tiles := hull_sheet_tiles()
	seen: map[string]bool
	defer delete(seen)
	for tile, index in tiles {
		// A tile the fill skipped is left zeroed, which is a nameless eye in the shaded paint.
		testing.expectf(t, tile.name != "", "tile %d was never filled", index)

		key := fmt.tprintf("%s/%v", tile.name, tile.paint)
		testing.expectf(t, !seen[key], "two tiles are %s", key)
		seen[key] = true

		// Row is paint, column is eye — the grid the cells lay out below.
		cell := hull_sheet_cell(index)
		testing.expectf(
			t,
			cell.y == f32(int(tile.paint) * WINDOW_HEIGHT),
			"the %v tiles should share one row (%s is at y %.0f)",
			tile.paint,
			tile.name,
			cell.y,
		)
	}

	for eye in hull_sheet_eyes() {
		for paint in Ship_Paint {
			testing.expectf(t, seen[fmt.tprintf("%s/%v", eye.name, paint)], "%s is missing in %v", eye.name, paint)
		}
	}
}

// Each tile says which paint it is, not just which eye — a tile read cropped out of the sheet or
// scaled to a thumbnail is worth nothing if its row's mode is only knowable from its neighbours.
@(test)
hull_sheet_names_every_paint_it_takes :: proc(t: ^testing.T) {
	seen: map[string]bool
	defer delete(seen)
	for paint in Ship_Paint {
		name := ship_debug_paint_name(paint)
		testing.expectf(t, name != "", "%v needs a name to caption its row with", paint)
		testing.expectf(t, !seen[name], "two paints are captioned %s", name)
		seen[name] = true
	}
}

// The framing is the shipped one, moved: her standoff, the height it looks at and the lens are
// GALLEON_EYE's, and an angle is all a tile's name means. This is the test that stops the sheet
// becoming a second source of camera constants — tuning a tile would have to break it.
@(test)
hull_sheet_eyes_come_off_the_shipped_framing :: proc(t: ^testing.T) {
	shipped := cutaway.GALLEON_EYE
	for tile in hull_sheet_eyes() {
		testing.expectf(t, tile.eye.fov == shipped.fov, "%s should look through the shipped lens", tile.name)
		testing.expectf(t, tile.eye.look == shipped.look, "%s should look at the shipped height", tile.name)
		testing.expectf(t, tile.eye.pan == 0, "%s has nothing to leave room for, so it does not pan", tile.name)
		_, flat := tile.eye.ortho.?
		testing.expectf(t, !flat, "%s should be the shipped perspective, not a flattened one", tile.name)

		// The swing rotates the standoff about the point the eye looks at, so every eye stands the
		// same distance off her however far over or under her it has been carried.
		rise := tile.eye.height - tile.eye.look
		standoff := math.sqrt(tile.eye.dist * tile.eye.dist + rise * rise)
		shipped_rise := shipped.height - shipped.look
		shipped_standoff := math.sqrt(shipped.dist * shipped.dist + shipped_rise * shipped_rise)
		testing.expectf(
			t,
			abs(standoff - shipped_standoff) < 0.001,
			"%s should stand off her the shipped distance, not one of its own (%.3f vs %.3f)",
			tile.name,
			standoff,
			shipped_standoff,
		)
	}
}

// The quarter tile is the shipped framing itself, unrounded: the sheet's whole claim is that five
// eyes are the sixth one moved, and one of the six being the screen the game actually draws is
// what makes the other five readable against it.
@(test)
hull_sheet_shows_the_shipped_framing_itself :: proc(t: ^testing.T) {
	for tile in hull_sheet_eyes() {
		if tile.name == "quarter" {
			testing.expect_value(t, tile.eye, cutaway.GALLEON_EYE)
			testing.expect_value(
				t,
				cutaway.galleon_view_from(tile.eye, WINDOW_WIDTH, WINDOW_HEIGHT),
				cutaway.galleon_view(WINDOW_WIDTH, WINDOW_HEIGHT),
			)
		}
	}
}

// Each name has to mean the place it says, or the sheet mislabels her and a session reads the
// wrong end of the ship as a defect. Checked where the eye actually ends up — through
// galleon_view_from, which is the only thing that turns an Eye into a camera.
@(test)
hull_sheet_eyes_stand_where_their_names_say :: proc(t: ^testing.T) {
	at :: proc(name: string) -> (position: [3]f32, found: bool) {
		for tile in hull_sheet_eyes() {
			if tile.name == name {
				return cutaway.galleon_view_from(tile.eye, WINDOW_WIDTH, WINDOW_HEIGHT).camera.position, true
			}
		}
		return {}, false
	}

	bow, found := at("bow")
	testing.expect(t, found, "bow should be one of the sheet's eyes")
	testing.expectf(t, bow.x > cutaway.GALLEON_BOW_X, "the bow eye should stand ahead of her stem (x %.2f)", bow.x)

	stern, _ := at("stern")
	testing.expectf(t, stern.x < cutaway.GALLEON_STERN_X, "the stern eye should stand astern of her (x %.2f)", stern.x)

	// The cut runs down her port (-z) side, so a beam eye that is not on it looks at planking.
	beam, _ := at("beam")
	testing.expectf(t, beam.z < -cutaway.GALLEON_HALF_BEAM, "the beam eye should stand off her open side (z %.2f)", beam.z)
	testing.expectf(t, abs(beam.x) < cutaway.GALLEON_BOW_X, "the beam eye should stand abreast of her (x %.2f)", beam.x)

	// Over her rig and under her keel: anything short of that is another quarter view.
	above, _ := at("above")
	testing.expectf(t, above.y > cutaway.GALLEON_DECK_Y, "the above eye should stand over her deck (y %.2f)", above.y)

	below, _ := at("below")
	testing.expectf(t, below.y < cutaway.GALLEON_KEEL_Y, "the below eye should stand under her keel (y %.2f)", below.y)
}

// Six eyes are only worth six tiles if they are six *different* eyes. A copy would cost a tile of
// the sheet and say nothing, and a swing or a yaw that failed to apply is exactly the mistake this
// catches.
@(test)
hull_sheet_eyes_look_from_six_different_places :: proc(t: ^testing.T) {
	tiles := hull_sheet_eyes()
	for tile, i in tiles {
		for other in tiles[i + 1:] {
			here := cutaway.galleon_view_from(tile.eye, WINDOW_WIDTH, WINDOW_HEIGHT).camera.position
			there := cutaway.galleon_view_from(other.eye, WINDOW_WIDTH, WINDOW_HEIGHT).camera.position
			testing.expectf(
				t,
				here != there,
				"%s and %s photograph her from the same place",
				tile.name,
				other.name,
			)
		}
	}
}

// The grid has to spend the whole sheet exactly once: an overlap paints one eye over another, and
// a gap leaves the ground colour to be read as a tile that rendered black.
@(test)
hull_sheet_cells_tile_the_sheet_exactly :: proc(t: ^testing.T) {
	covered := f32(0)
	for index in 0 ..< HULL_SHEET_TILES {
		cell := hull_sheet_cell(index)
		testing.expectf(t, cell.x >= 0 && cell.y >= 0, "tile %d starts off the sheet", index)
		testing.expectf(
			t,
			cell.x + cell.width <= HULL_SHEET_W && cell.y + cell.height <= HULL_SHEET_H,
			"tile %d runs off the sheet",
			index,
		)
		covered += cell.width * cell.height

		for other in 0 ..< index {
			overlap := hull_sheet_cell(other)
			apart :=
				cell.x >= overlap.x + overlap.width ||
				overlap.x >= cell.x + cell.width ||
				cell.y >= overlap.y + overlap.height ||
				overlap.y >= cell.y + cell.height
			testing.expectf(t, apart, "tiles %d and %d overlap", index, other)
		}
	}
	testing.expect_value(t, covered, f32(HULL_SHEET_W) * f32(HULL_SHEET_H))
}

// --hull-sheet takes no name, so it is a whole-word flag like --shots — and it must not be read as
// either of the two flags it shares a window and a directory with, or a sheet run would go looking
// for a screen instead.
@(test)
hull_sheet_arg_is_its_own_flag :: proc(t: ^testing.T) {
	testing.expect(t, hull_sheet_arg({"--hull-sheet"}), "--hull-sheet asks for the sheet")
	testing.expect(t, !hull_sheet_arg({"--shots"}), "the standalone set is not the sheet")
	testing.expect(t, !hull_sheet_arg({"--shot", "build"}), "one named screen is not the sheet")
	testing.expect(t, !hull_sheet_arg({"--workbench"}), "the workbench is not the sheet")

	_, requested := capture_shot_arg({"--hull-sheet"})
	testing.expect(t, !requested, "the sheet is not a request for one named screen")
	testing.expect(t, !capture_shots_arg({"--hull-sheet"}), "the sheet is not the standalone set")
}
