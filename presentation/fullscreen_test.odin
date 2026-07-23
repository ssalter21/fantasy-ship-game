package presentation

import "core:testing"
import rl "vendor:raylib"

@(test)
letterbox_fit_pillarboxes_a_wide_screen :: proc(t: ^testing.T) {
	// Ultrawide monitor is wider than the 1244x700 logical frame: height fills exactly,
	// equal black bars either side.
	scale, dst := letterbox_fit(2560, 1080)
	testing.expect_value(t, scale, f32(1080) / WINDOW_HEIGHT)
	testing.expect_value(t, dst.height, f32(1080))
	testing.expect_value(t, dst.y, f32(0))
	testing.expect_value(t, dst.width, WINDOW_WIDTH * scale)
	testing.expect_value(t, dst.x, (2560 - dst.width) / 2)
}

@(test)
letterbox_fit_fills_a_16x9_monitor :: proc(t: ^testing.T) {
	// The acceptance monitor (#451): 1244x700 is within half a pixel of 16:9 at this
	// scale, so the frame fills 1920x1080 edge-to-edge with at most sub-pixel bars.
	_, dst := letterbox_fit(1920, 1080)
	testing.expect_value(t, dst.height, f32(1080))
	testing.expect(t, dst.width > 1918, "frame spans the screen width")
	testing.expect(t, dst.x < 1, "pillar bars are sub-pixel")
}

@(test)
letterbox_fit_letterboxes_a_tall_screen :: proc(t: ^testing.T) {
	// Screen taller than the logical aspect: width fills exactly, equal bars above
	// and below.
	scale, dst := letterbox_fit(WINDOW_WIDTH, 2000)
	testing.expect_value(t, scale, f32(1))
	testing.expect_value(t, dst.width, f32(WINDOW_WIDTH))
	testing.expect_value(t, dst.x, f32(0))
	testing.expect_value(t, dst.height, f32(WINDOW_HEIGHT))
	testing.expect_value(t, dst.y, (2000 - f32(WINDOW_HEIGHT)) / 2)
}

@(test)
letterbox_fit_is_identity_at_logical_size :: proc(t: ^testing.T) {
	// A screen exactly the logical size maps 1:1 with no bars — what capture mode
	// and a windowed fallback would see.
	scale, dst := letterbox_fit(WINDOW_WIDTH, WINDOW_HEIGHT)
	testing.expect_value(t, scale, f32(1))
	testing.expect_value(t, dst, rl.Rectangle{width = WINDOW_WIDTH, height = WINDOW_HEIGHT})
}

@(test)
letterbox_fit_shrinks_to_a_smaller_screen :: proc(t: ^testing.T) {
	// Scale-to-fit also scales down: on a screen smaller than logical the whole
	// frame stays visible rather than cropping.
	scale, dst := letterbox_fit(800, 600)
	testing.expect_value(t, scale, f32(800) / WINDOW_WIDTH)
	// 800/1244 isn't exact in f32, so scaling back up lands within a whisker of 800
	// rather than on it.
	testing.expect(t, abs(dst.width - 800) < 0.001, "frame fills the screen width")
	testing.expect_value(t, dst.height, WINDOW_HEIGHT * scale)
	testing.expect(t, dst.height <= 600, "scaled frame fits inside the screen")
}
