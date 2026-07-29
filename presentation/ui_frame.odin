#+private
package presentation

import "core:math"
import rl "vendor:raylib"

// Blitted chrome: a frame is art, not a stroked rectangle.
//
// The best-looking thing in this game is a generated asset and the worst-looking thing sat
// directly on top of it — translucent scrims with a hairline border. A hairline is what a
// renderer can draw, not what the world looks like, and no amount of arranging rectangles
// gets past it. So the frames are pixel art, blitted, and a screen asks for one by name.
//
// A frame is 9-sliced: its four corners blit at native size, its four edges stretch along
// their own axis only, and its middle stretches both ways. That is what lets one 24px sprite
// be a panel of any size without its corner art shearing — and it is why the corner marks in
// the art stay inside the slice inset.

// Ui_Button_State is the three faces the button frame carries, in the strip's order.
Ui_Button_State :: enum {
	Rest,
	Hover,
	Press,
}

// Ui_Frame is one blittable frame: the texture it lives in, how far in from each edge its
// corner art reaches, and how many states sit side by side in that texture.
Ui_Frame :: struct {
	texture: ^rl.Texture2D,
	inset:   i32,
	states:  i32,
}

// The frames the screens draw with. Each names the inset its art was authored to
// (scripts/make-ui-frames.py); an inset that disagreed with the art would shear a corner.
UI_FRAME_PANEL := Ui_Frame {
	texture = &ui_frame_panel_tex,
	inset   = 7,
	states  = 1,
}

UI_FRAME_CARD := Ui_Frame {
	texture = &ui_frame_card_tex,
	inset   = 5,
	states  = 1,
}

UI_FRAME_BUTTON := Ui_Frame {
	texture = &ui_frame_button_tex,
	inset   = 5,
	states  = len(Ui_Button_State),
}

// ui_nine_slice blits a frame to an arbitrary rect, in the state named. `tint` is white for
// the frame as authored — a call site that wants a frame dimmed passes a shade of white
// rather than a second sprite.
ui_nine_slice :: proc(frame: Ui_Frame, rect: rl.Rectangle, state := 0, tint := rl.WHITE) {
	if frame.texture.id == 0 {
		// No window, so no atlas: under `odin test` and before art_load every texture is the
		// zero value, and blitting one draws a white box over whatever is there.
		return
	}

	width := f32(frame.texture.width) / f32(frame.states)
	source := rl.Rectangle {
		x      = f32(clamp(state, 0, int(frame.states) - 1)) * width,
		y      = 0,
		width  = width,
		height = f32(frame.texture.height),
	}
	patch := rl.NPatchInfo {
		source = source,
		left   = frame.inset,
		top    = frame.inset,
		right  = frame.inset,
		bottom = frame.inset,
		layout = .NINE_PATCH,
	}
	rl.DrawTextureNPatch(frame.texture^, patch, ui_pixel_rect(rect), rl.Vector2{0, 0}, 0, tint)
}

// ui_pixel_rect snaps a rect to whole pixels. A frame landing on a half pixel is resampled
// across the seam whatever the texture filter is, which is the one thing pixel art cannot
// survive — and the filter is POINT (art.odin), so nothing downstream softens it back.
//
// Edges are rounded, never the origin and the size separately: rounded apart, a rect drifts
// a pixel wider or narrower as it moves, and a row of them stops sharing edges.
ui_pixel_rect :: proc(rect: rl.Rectangle) -> rl.Rectangle {
	left, top := math.round(rect.x), math.round(rect.y)
	return rl.Rectangle {
		x = left,
		y = top,
		width = math.round(rect.x + rect.width) - left,
		height = math.round(rect.y + rect.height) - top,
	}
}

// ui_frame_min is the smallest rect a frame keeps its corners in: below it the four corners
// have no room to sit side by side and raylib crushes them into each other.
ui_frame_min :: proc(frame: Ui_Frame) -> f32 {
	return f32(frame.inset * 2)
}
