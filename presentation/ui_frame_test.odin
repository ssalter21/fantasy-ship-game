package presentation

import "core:testing"
import rl "vendor:raylib"

// The blit itself needs a window and an atlas, so what is testable here is the arithmetic
// that decides where a frame lands — which is also where the pixel grid is won or lost.

// A frame on a half pixel is resampled across the seam whatever the filter, so a rect is
// snapped before it is blitted.
@(test)
a_frame_lands_on_whole_pixels :: proc(t: ^testing.T) {
	snapped := ui_pixel_rect({x = 10.4, y = 20.6, width = 30.5, height = 40.5})
	testing.expect_value(t, snapped.x, 10)
	testing.expect_value(t, snapped.y, 21)
	for edge in ([?]f32{snapped.x, snapped.y, snapped.width, snapped.height}) {
		testing.expectf(t, edge == f32(int(edge)), "%.3f is a whole pixel", edge)
	}
}

// Edges are rounded, never the origin and the size separately: rounded apart, a rect drifts
// a pixel wider or narrower as it slides, and a row of them stops sharing edges.
@(test)
a_frame_keeps_its_size_as_it_moves :: proc(t: ^testing.T) {
	WIDTH :: f32(100)
	for step in 0 ..< 10 {
		x := 5 + f32(step) * 0.1
		snapped := ui_pixel_rect({x = x, y = 0, width = WIDTH, height = 20})
		testing.expectf(t, snapped.width == WIDTH, "at x=%.1f the width is %.0f, not %.0f", x, snapped.width, WIDTH)
	}
}

// Two rects that meet still meet after snapping, or a stack of cards grows hairlines
// between them at some positions and not others.
@(test)
two_frames_that_meet_still_meet :: proc(t: ^testing.T) {
	for step in 0 ..< 10 {
		y := 40 + f32(step) * 0.1
		above := ui_pixel_rect({x = 0, y = y, width = 50, height = 32.5})
		below := ui_pixel_rect({x = 0, y = y + 32.5, width = 50, height = 32.5})
		testing.expectf(t, above.y + above.height == below.y, "at y=%.1f a seam opened", y)
	}
}

// Every state the button frame is asked for has to exist in the strip, or a hover blits
// whatever sits past the texture's right edge.
@(test)
the_button_frame_carries_every_state :: proc(t: ^testing.T) {
	testing.expect_value(t, int(UI_FRAME_BUTTON.states), len(Ui_Button_State))
	for state in Ui_Button_State {
		testing.expectf(t, int(state) < int(UI_FRAME_BUTTON.states), "%v is in the strip", state)
	}
}

// A frame's inset is what its corner art was authored to (scripts/make-ui-frames.py); an
// inset of zero would stretch the corners with everything else and shear them.
@(test)
every_frame_reserves_its_corners :: proc(t: ^testing.T) {
	for frame in ([?]Ui_Frame{UI_FRAME_PANEL, UI_FRAME_CARD, UI_FRAME_BUTTON}) {
		testing.expect(t, frame.inset > 0, "a frame whose corners are not reserved is a stretched rectangle")
		testing.expect(t, frame.states >= 1, "a frame carries at least one state")
		testing.expect(t, frame.texture != nil, "a frame names the atlas it lives in")
	}
}

// Without a window every texture is the zero value, and blitting one would draw a white box
// over the screen. The guard is what lets a draw proc be called under `odin test`.
@(test)
a_frame_with_no_atlas_draws_nothing :: proc(t: ^testing.T) {
	testing.expect_value(t, ui_frame_panel_tex.id, 0)
	ui_nine_slice(UI_FRAME_PANEL, rl.Rectangle{0, 0, 100, 100})
}
