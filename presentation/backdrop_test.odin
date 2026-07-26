package presentation

import "core:math"
import "core:testing"

import rl "vendor:raylib"

// The backdrop's contracts, all of them about the same risk: this is the file that holds the
// screen to one art resolution, and every way it can quietly stop doing so is invisible at 1:1
// and only shows up under magnification on a capture shot.

@(test)
the_lattice_divides_the_logical_frame :: proc(t: ^testing.T) {
	// A lattice that does not divide the frame leaves a part-pixel column and row at two of the
	// edges, which is a second resolution living in the last four pixels of the screen.
	testing.expectf(
		t,
		math.mod(f32(WINDOW_WIDTH), BACKDROP_PIXEL) == 0,
		"window width %v is not a whole number of %v-pixel cells",
		WINDOW_WIDTH,
		BACKDROP_PIXEL,
	)
	testing.expectf(
		t,
		math.mod(f32(WINDOW_HEIGHT), BACKDROP_PIXEL) == 0,
		"window height %v is not a whole number of %v-pixel cells",
		WINDOW_HEIGHT,
		BACKDROP_PIXEL,
	)
}

@(test)
every_edge_of_a_snapped_rect_lands_on_the_lattice :: proc(t: ^testing.T) {
	awkward := []rl.Rectangle {
		{0, 0, 1244, 700},
		{206.4, 96.5, 168.7, 20.2},
		{-30.9, 411.1, 7.3, 1.0},
		{1042.5, 74.25, 138.5, 22.75},
	}
	for rect in awkward {
		snapped := backdrop_rect(rect)
		edges := [4]struct {
			name:  string,
			value: f32,
		}{{"x", snapped.x}, {"y", snapped.y}, {"width", snapped.width}, {"height", snapped.height}}
		for edge in edges {
			testing.expectf(
				t,
				math.mod(edge.value, BACKDROP_PIXEL) == 0,
				"%v of %v snapped to %v, which is off the lattice",
				edge.name,
				rect,
				edge.value,
			)
		}
	}
}

@(test)
a_mark_thinner_than_an_art_pixel_survives_snapping :: proc(t: ^testing.T) {
	// The sea's finest chop and the glitter path are drawn a logical pixel or two thick. Rounding
	// those to nothing would not be a finer sea; it would be holes in the water.
	hairline := backdrop_rect({100.2, 200.9, 0.4, 1})
	testing.expect(t, hairline.width == BACKDROP_PIXEL, "a sub-pixel width was rounded away")
	testing.expect(t, hairline.height == BACKDROP_PIXEL, "a sub-pixel height was rounded away")
}

@(test)
a_grade_paints_only_its_ramp_stops :: proc(t: ^testing.T) {
	// The whole point of the ramp: a sky the height of the frame reaches for a handful of colours,
	// not one per screen row. Anything that reintroduces per-pixel interpolation breaks this.
	STOPS :: 6
	seen: map[rl.Color]bool
	defer delete(seen)
	for i in 0 ..= STOPS {
		seen[backdrop_stop(COLOUR_SKY_HIGH, COLOUR_HAZE, i, STOPS)] = true
	}
	testing.expectf(t, len(seen) == STOPS + 1, "%v stops gave %v distinct colours", STOPS, len(seen))

	// And the ramp still starts and ends on the roster swatches it was asked for, so the tropical
	// palette is preserved exactly rather than approached.
	testing.expect(t, backdrop_stop(COLOUR_SKY_HIGH, COLOUR_HAZE, 0, STOPS) == COLOUR_SKY_HIGH, "ramp start drifted")
	testing.expect(t, backdrop_stop(COLOUR_SKY_HIGH, COLOUR_HAZE, STOPS, STOPS) == COLOUR_HAZE, "ramp end drifted")
}

@(test)
the_dither_matrix_is_an_ordered_one :: proc(t: ^testing.T) {
	// An ordered dither needs every threshold in 0..15 exactly once. A repeated or missing one
	// clumps its cells, and a crossing then reads as a blotch rather than as an even scatter.
	present: [16]int
	for row in BACKDROP_DITHER {
		for cell in row {
			testing.expectf(t, cell >= 0 && cell < 16, "threshold %v is outside 0..15", cell)
			present[int(cell)] += 1
		}
	}
	for count, threshold in present {
		testing.expectf(t, count == 1, "threshold %v appears %v times, not once", threshold, count)
	}
}
