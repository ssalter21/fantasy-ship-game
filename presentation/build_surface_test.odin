package presentation

import "core:testing"

import rl "vendor:raylib"

// Seam 2 of spec 0001's testing contract: the screen-model toggle logic is a pure function over
// the window's rects, so the two-state chart toggle is asserted here without a live window
// (ADR-0003 keeps pixels out of unit tests). #351 adds the click-outside-margin dismiss.

@(test)
home_chart_page_is_centred_with_a_four_sided_build_margin :: proc(t: ^testing.T) {
	// Spec §1: the unfurled page is dominant but never window-edge-to-edge — the Build
	// surface frames it on all four sides, and that cutaway is what the new dismiss clicks.
	page := home_chart_page_rect(1)
	testing.expect_value(t, page.x, WINDOW_WIDTH - (page.x + page.width))
	testing.expect(t, page.x > 0, "a left/right Build margin is visible beside the page")
	testing.expect(t, page.y > 0, "a Build margin is visible above the page")
	testing.expect(t, page.y + page.height < WINDOW_HEIGHT, "a Build margin is visible below the page")
}

@(test)
home_chart_page_rides_the_chart_offset_down_when_lowered :: proc(t: ^testing.T) {
	// The page hit-test asks about the page the eye sees, so it must carry the same
	// chart_offset draw_map_page is drawn under: fully lowered, it sits below the window.
	lowered := home_chart_page_rect(0)
	testing.expect_value(t, lowered.y, home_chart_page_rect(1).y + CHART_RISE_TRAVEL)
	testing.expect(t, lowered.y >= WINDOW_HEIGHT, "a lowered page is entirely off the visible area")
}

@(test)
clicking_the_build_margin_rolls_the_chart_down :: proc(t: ^testing.T) {
	// #351's new affordance: a click anywhere on the visible Build margin is a "leave"
	// gesture, on every one of the four sides.
	page := home_chart_page_rect(1)
	testing.expect(t, home_chart_roll_down(rl.Vector2{page.x / 2, WINDOW_HEIGHT / 2}), "left margin")
	testing.expect(t, home_chart_roll_down(rl.Vector2{page.x + page.width + 1, WINDOW_HEIGHT / 2}), "right margin")
	testing.expect(t, home_chart_roll_down(rl.Vector2{WINDOW_WIDTH / 2, page.y / 2}), "top margin")
	testing.expect(t, home_chart_roll_down(rl.Vector2{WINDOW_WIDTH / 2, page.y + page.height + 1}), "bottom margin")
}

@(test)
clicking_the_chart_tab_rolls_the_chart_down :: proc(t: ^testing.T) {
	// The other half of the two-state toggle: a re-tap of the tab that unfurled the map
	// rolls it back. The tab sits inside the page rect at Home (it clears the stats
	// ledger), so it would not be caught by the margin test above — both exits must read.
	tab := home_chart_tab_rect()
	centre := rl.Vector2{tab.x + tab.width / 2, tab.y + tab.height / 2}
	testing.expect(t, rl.CheckCollisionPointRec(centre, home_chart_page_rect(1)), "the Home tab overlays the page")
	testing.expect(t, home_chart_roll_down(centre), "re-tapping the tab rolls the map down")
}

@(test)
clicking_the_page_itself_leaves_the_chart_up :: proc(t: ^testing.T) {
	// Only the margin dismisses: a click on the parchment away from the tab belongs to the
	// node hit-test, so the map must stay unfurled rather than rolling down under it. Sampled
	// mid-page rather than at the rect's corner — the corner is inside the bounding box but
	// outside the torn sheet (measured Build navy there, not Parchment #EBD9A6), so it would
	// assert the fringe rather than the parchment.
	page := home_chart_page_rect(1)
	mid := rl.Vector2{page.x + page.width / 2, page.y + page.height * 0.67}
	testing.expect(t, !home_chart_roll_down(mid), "a click on the parchment keeps the map up")
}
