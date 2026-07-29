#+private
// Borderless fullscreen for the player session (#449). Every frame draws unchanged at
// the fixed 1244x700 logical size, but into an offscreen render texture; frame_end
// blits that texture scaled-to-fit (letterboxed on black) onto the monitor-sized
// framebuffer, and the hardware mouse is remapped into logical coordinates so every
// GetMousePosition hit-test against 1244x700 rects works untouched. When fullscreen
// isn't initialised (capture mode, tests), frame_begin/frame_end degrade to plain
// Begin/EndDrawing — capture keeps shooting frames at exact logical size.
package presentation

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

fullscreen_target: rl.RenderTexture2D
fullscreen_active: bool

// fullscreen_init flips the freshly created window to borderless fullscreen and
// allocates the logical-resolution target. Must run after InitWindow.
fullscreen_init :: proc() {
	rl.ToggleBorderlessWindowed()
	fullscreen_target = rl.LoadRenderTexture(WINDOW_WIDTH, WINDOW_HEIGHT)
	// A non-integer upscale with POINT would shimmer; BILINEAR trades a hint of
	// softness for even scaling.
	rl.SetTextureFilter(fullscreen_target.texture, .BILINEAR)
	fullscreen_active = true
}

fullscreen_shutdown :: proc() {
	if !fullscreen_active {
		return
	}
	rl.UnloadRenderTexture(fullscreen_target)
	fullscreen_active = false
}

// letterbox_fit is the scale-to-fit mapping from the 1244x700 logical frame to a
// screen_w x screen_h screen: one uniform scale factor and the centred destination
// rectangle, letterboxed on whichever axis has room to spare.
letterbox_fit :: proc(screen_w, screen_h: f32) -> (scale: f32, dst: rl.Rectangle) {
	scale = min(screen_w / WINDOW_WIDTH, screen_h / WINDOW_HEIGHT)
	w := f32(WINDOW_WIDTH) * scale
	h := f32(WINDOW_HEIGHT) * scale
	dst = rl.Rectangle{x = (screen_w - w) / 2, y = (screen_h - h) / 2, width = w, height = h}
	return
}

// frame_begin stands in for rl.BeginDrawing at every render site: it points the frame
// at the logical target and remaps the hardware mouse into logical coordinates
// (raylib applies virtual = (real + offset) * scale). Remapped every frame, not once,
// so a monitor or resolution change picks up the new mapping on the next frame.
frame_begin :: proc() {
	if !fullscreen_active {
		rl.BeginDrawing()
		return
	}
	scale, dst := letterbox_fit(f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()))
	rl.SetMouseOffset(i32(-dst.x), i32(-dst.y))
	rl.SetMouseScale(1 / scale, 1 / scale)
	rl.BeginTextureMode(fullscreen_target)
}

// frame_overlay is drawn into every logical frame just before it is presented, and is nil in
// every player session. A screen owns its own frame boundaries, so a tool that draws *over*
// one — the workbench's slider panel — has to be let in rather than sequenced after it. The
// game sets this nowhere; only the workbench does, and only for as long as it runs.
frame_overlay: proc()

// frame_end stands in for rl.EndDrawing: closes the logical frame, then presents it
// scaled-to-fit over black letterbox bars.
frame_end :: proc() {
	if frame_overlay != nil {
		frame_overlay()
	}
	if !fullscreen_active {
		rl.EndDrawing()
		return
	}
	rl.EndTextureMode()
	_, dst := letterbox_fit(f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()))
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	src := rl.Rectangle{width = WINDOW_WIDTH, height = -WINDOW_HEIGHT} // render textures are y-flipped
	// The blit takes the target's colour verbatim and throws its alpha away. It has to:
	// raylib's default blend multiplies *alpha* by alpha as well as colour, so a render
	// texture starting opaque loses alpha wherever anything translucent is drawn into it
	// (a=0.85 over a=1 leaves 0.87, and it compounds). Composite that against the black
	// letterbox and every soft mark on screen — the sun's haze, the glitter on the water,
	// foam, highlight washes — comes back up to a fifth darker than it was drawn. The
	// colour in the texture was always right; only the alpha it was carried in was wrong,
	// so the fix is to stop asking about it. Windowed play never saw this (no texture),
	// which is exactly why --capture cannot photograph the bug.
	rlgl.SetBlendFactorsSeparate(rlgl.ONE, rlgl.ZERO, rlgl.ONE, rlgl.ZERO, rlgl.FUNC_ADD, rlgl.FUNC_ADD)
	rl.BeginBlendMode(.CUSTOM_SEPARATE)
	rl.DrawTexturePro(fullscreen_target.texture, src, dst, rl.Vector2{0, 0}, 0, rl.WHITE)
	rl.EndBlendMode()
	rl.EndDrawing()
}
