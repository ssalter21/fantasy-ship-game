package cutaway

import "core:testing"

import ship "../../core/ship"
import rl "vendor:raylib"

// The layout contract, asserted without a window (ADR-0003 keeps pixels out of unit
// tests): rows land on the region's lines, centre in its span, scale uniformly, and
// hit-testing consults the same rects the drawing is handed.

@(private = "file")
TEST_REGION :: Region {
	x           = 100,
	w           = 1000,
	deck_y      = 80,
	waterline_y = 200,
	hold_y      = 220,
	keel_y      = 400,
	scale       = 1,
}

// Two exposed, two concealed, mixed sizes — enough to exercise both rows and the
// size-tracking footprints.
@(private = "file")
test_layout :: proc() -> [4]ship.Layout_Slot {
	return [4]ship.Layout_Slot {
		{slot = ship.Slot{name = "fore", size = .Large, base_visibility = .Exposed}},
		{slot = ship.Slot{name = "aft", size = .Small, base_visibility = .Exposed}},
		{slot = ship.Slot{name = "hold 1", size = .Medium, base_visibility = .Concealed}},
		{slot = ship.Slot{name = "hold 2", size = .Small, base_visibility = .Concealed}},
	}
}

@(test)
rows_land_on_the_regions_lines :: proc(t: ^testing.T) {
	layout := test_layout()
	rects, n := cutaway_slot_rects(layout[:], TEST_REGION)
	testing.expect_value(t, n, 4)

	// Geography carries the exposed/concealed split (ADR-0030): deck row for exposed,
	// hold row for concealed, whatever order the layout interleaves them in.
	testing.expect_value(t, rects[0].y, TEST_REGION.deck_y)
	testing.expect_value(t, rects[1].y, TEST_REGION.deck_y)
	testing.expect_value(t, rects[2].y, TEST_REGION.hold_y)
	testing.expect_value(t, rects[3].y, TEST_REGION.hold_y)

	// A card's footprint tracks its slot size.
	for ls, i in layout {
		w, h := cutaway_card_dims(ls.slot.size)
		testing.expect_value(t, rects[i].width, w)
		testing.expect_value(t, rects[i].height, h)
	}
}

@(test)
rows_centre_in_the_region :: proc(t: ^testing.T) {
	layout := test_layout()
	rects, _ := cutaway_slot_rects(layout[:], TEST_REGION)

	// A centred row leaves equal margins: left gap to the region's start, right gap to
	// its end — on both rows.
	region_r := TEST_REGION.x + TEST_REGION.w
	testing.expect_value(t, rects[0].x - TEST_REGION.x, region_r - (rects[1].x + rects[1].width))
	testing.expect_value(t, rects[2].x - TEST_REGION.x, region_r - (rects[3].x + rects[3].width))
}

@(test)
scale_shrinks_the_whole_size_language_uniformly :: proc(t: ^testing.T) {
	layout := test_layout()
	full, _ := cutaway_slot_rects(layout[:], TEST_REGION)
	region := TEST_REGION
	region.scale = 0.5
	half, n := cutaway_slot_rects(layout[:], region)

	for i in 0 ..< n {
		testing.expect_value(t, half[i].width, full[i].width / 2)
		testing.expect_value(t, half[i].height, full[i].height / 2)
	}
}

@(test)
slot_at_answers_from_the_same_laid_out_slots :: proc(t: ^testing.T) {
	layout := test_layout()
	rects, n := cutaway_slot_rects(layout[:], TEST_REGION)

	// The centre of every drawn card hit-tests back to that card's slot — the one-answer
	// property the module exists for.
	for i in 0 ..< n {
		centre := rl.Vector2{rects[i].x + rects[i].width / 2, rects[i].y + rects[i].height / 2}
		hit, over := cutaway_slot_at(layout[:], TEST_REGION, centre).?
		testing.expect(t, over, "the centre of a laid-out card is over its slot")
		testing.expect_value(t, hit, ship.Slot_Index(i))
	}

	// Open water — left of the region — is over nothing.
	_, over := cutaway_slot_at(layout[:], TEST_REGION, rl.Vector2{0, TEST_REGION.deck_y}).?
	testing.expect(t, !over, "a point outside every card hit-tests to nil")
}
