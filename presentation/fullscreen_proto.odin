#+private
// PROTOTYPE — THROWAWAY (branch prototype/fullscreen-chart). Question being answered:
// can the game go borderless-fullscreen on the player's monitor with the chart map
// fitting the screen, without re-laying-out the absolute-coordinate UI?
//
// Approach: every frame still draws at the fixed 1024x700 logical size, but into an
// offscreen render texture; frame_end blits that texture scaled-to-fit (letterboxed)
// onto the real monitor-sized framebuffer, and the mouse is remapped into logical
// coordinates so every GetMousePosition caller keeps working untouched. When the
// prototype isn't initialised (capture mode, tests), frame_begin/frame_end degrade
// to plain Begin/EndDrawing.
package presentation

import rl "vendor:raylib"

proto_target: rl.RenderTexture2D
proto_active: bool

// proto_fullscreen_init flips the freshly created window to borderless fullscreen
// and allocates the logical-resolution target. Must run after InitWindow.
proto_fullscreen_init :: proc() {
	rl.ToggleBorderlessWindowed()
	proto_target = rl.LoadRenderTexture(WINDOW_WIDTH, WINDOW_HEIGHT)
	// Non-integer upscale (e.g. 1024 -> 2560-wide) with POINT would shimmer; BILINEAR
	// trades a hint of softness for even scaling. Part of what the prototype evaluates.
	rl.SetTextureFilter(proto_target.texture, .BILINEAR)
	proto_active = true
}

proto_fullscreen_shutdown :: proc() {
	if !proto_active {
		return
	}
	rl.UnloadRenderTexture(proto_target)
	proto_active = false
}

// proto_letterbox is the scale-to-fit mapping from the 1024x700 logical frame to the
// current screen: one uniform scale factor and the centred destination rectangle.
proto_letterbox :: proc() -> (scale: f32, dst: rl.Rectangle) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	scale = min(sw / WINDOW_WIDTH, sh / WINDOW_HEIGHT)
	w := f32(WINDOW_WIDTH) * scale
	h := f32(WINDOW_HEIGHT) * scale
	dst = rl.Rectangle{(sw - w) / 2, (sh - h) / 2, w, h}
	return
}

// frame_begin replaces rl.BeginDrawing at every render-loop site: it points the frame
// at the logical target and remaps the hardware mouse into logical coordinates
// (virtual = (real + offset) * scale), so hit-testing against 1024x700 rects still works.
frame_begin :: proc() {
	if !proto_active {
		rl.BeginDrawing()
		return
	}
	scale, dst := proto_letterbox()
	rl.SetMouseOffset(i32(-dst.x), i32(-dst.y))
	rl.SetMouseScale(1 / scale, 1 / scale)
	rl.BeginTextureMode(proto_target)
}

// frame_end replaces rl.EndDrawing: closes the logical frame, then presents it
// scaled-to-fit on black letterbox bars.
frame_end :: proc() {
	if !proto_active {
		rl.EndDrawing()
		return
	}
	rl.EndTextureMode()
	_, dst := proto_letterbox()
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	src := rl.Rectangle{0, 0, f32(WINDOW_WIDTH), -f32(WINDOW_HEIGHT)} // render textures are y-flipped
	rl.DrawTexturePro(proto_target.texture, src, dst, rl.Vector2{0, 0}, 0, rl.WHITE)
	rl.EndDrawing()
}
