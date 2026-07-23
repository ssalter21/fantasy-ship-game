#+private
package presentation

// PROTOTYPE — THROWAWAY. Branch worktree-prototype-ship-side-view; never merges to main.
//
// Round 5. The verdict kept the true-3D open-room look but re-architected it as a real ship
// rather than a stack of equal decks. The berths now map onto ship structure:
//   - the four concealed holds share ONE below-deck floor, split into compartments whose
//     width follows each hold's slot size;
//   - the exposed berths become the weather-deck structures: a forecastle at the bow, the
//     open waist amidships (one slot), and a sterncastle with a poop deck above it, aft.
// The camera sits off the bow quarter — a ~16-degree yaw so the bow angles toward the viewer
// — and a little above, so we read the side profile and look into every open room. Each room
// is empty by design: a placeholder chamber for the bespoke per-slot / per-fitting art to come.
//
//   Current      — today's flat navy cutaway, untouched, as the baseline to flip against.
//   Ship_Cutaway — the chosen direction, and the default: the 3/4 galleon cutaway.
//
// Hovering a room highlights that slot's open face and pops a description tooltip — nothing
// labels the ship at rest, so the hull is never obscured. Rooms are empty by design — the art
// that fills them is what we are NOT building yet. Drag-refit is inert (read-only prototype).
//
// The new-roster colours are PROTO_* locals here on purpose: the style guide leaves the
// shipped COLOUR_* constants navy until the real migration, and a throwaway must not front-run
// it.

import "core:fmt"
import "core:math"
import ship "../core/ship"
import sim "../core/sim"
import rl "vendor:raylib"

// --- The new roster (style-guide values, prototype-local) --------------------------------

PROTO_SEA :: rl.Color{31, 169, 208, 255}
PROTO_SEA_BRIGHT :: rl.Color{44, 195, 222, 255}
PROTO_SHALLOW :: rl.Color{99, 226, 236, 255}
PROTO_SEA_DEEP :: rl.Color{23, 134, 188, 255}
PROTO_FOAM :: rl.Color{242, 251, 251, 255}
PROTO_SKY_HIGH :: rl.Color{63, 121, 192, 255}
PROTO_SKY :: rl.Color{90, 147, 210, 255}
PROTO_HAZE :: rl.Color{143, 188, 232, 255}
PROTO_CLOUD :: rl.Color{238, 241, 248, 255}
PROTO_CLOUD_SHADOW :: rl.Color{183, 188, 224, 255}
PROTO_PARCHMENT :: rl.Color{235, 217, 166, 255}
PROTO_SAND :: rl.Color{210, 169, 104, 255}
PROTO_CLIFF :: rl.Color{185, 138, 80, 255}
PROTO_ROCK :: rl.Color{126, 92, 58, 255}
PROTO_TRUNK :: rl.Color{135, 95, 56, 255}
PROTO_INK :: rl.Color{18, 51, 63, 255}
PROTO_INK_MUTED :: rl.Color{76, 115, 133, 255}
PROTO_INK_FADED :: rl.Color{156, 138, 99, 255}
PROTO_CREAM :: rl.Color{243, 230, 196, 255}

Proto_Variant :: enum {
	Current,
	Ship_Cutaway,
}

// The chosen direction is the default: opening the ship screen shows the 3D cutaway.
proto_variant: Proto_Variant = .Ship_Cutaway

// Live camera-tuning knobs — the floating slider panel writes these every frame so the camera can
// be dialled in by hand instead of by re-editing constants. Throwaway, like the rest of the file.
// The defaults reproduce the round-13 shot: ~50-degree yaw, backed off, low, wide.
proto_cam_yaw: f32 = 49.6 // bow-toward-viewer swing, degrees
proto_cam_dist: f32 = 8.27 // horizontal distance from the target (dolly / zoom)
proto_cam_height: f32 = 1.0 // camera height above the origin plane (waterline closeness)
proto_cam_look: f32 = 0.4 // target height — tilts the view up or down
proto_cam_fov: f32 = 60 // field of view, degrees
proto_slider_active := -1 // which slider owns the current drag, or -1

proto_variant_label :: proc(v: Proto_Variant) -> string {
	switch v {
	case .Current:
		return "Current — navy cutaway"
	case .Ship_Cutaway:
		return "Ship cutaway — 3/4 galleon"
	}
	return ""
}

proto_cycle :: proc(dir: int) {
	n := len(Proto_Variant)
	proto_variant = Proto_Variant((int(proto_variant) + dir + n) % n)
}

// proto_poll is the switcher's whole input: arrow keys and the two bar arrows. Called at
// the top of the Home and Refit loops; the bar sits in a strip (y < 40) no live control
// shares, so its click never doubles as a drag or a chart raise.
proto_poll :: proc() {
	if !rl.IsWindowReady() {
		return
	}
	if rl.IsKeyPressed(.LEFT) {
		proto_cycle(-1)
	}
	if rl.IsKeyPressed(.RIGHT) {
		proto_cycle(1)
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		m := rl.GetMousePosition()
		if rl.CheckCollisionPointRec(m, proto_arrow_rect(false)) {
			proto_cycle(-1)
		} else if rl.CheckCollisionPointRec(m, proto_arrow_rect(true)) {
			proto_cycle(1)
		}
	}
}

PROTO_BAR_W :: 460
PROTO_BAR_H :: 30

proto_bar_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle{x = (WINDOW_WIDTH - PROTO_BAR_W) / 2, y = 6, width = PROTO_BAR_W, height = PROTO_BAR_H}
}

proto_arrow_rect :: proc(right: bool) -> rl.Rectangle {
	bar := proto_bar_rect()
	x := right ? bar.x + bar.width - 34 : bar.x + 4
	return rl.Rectangle{x = x, y = bar.y + 3, width = 30, height = bar.height - 6}
}

// draw_proto_switcher is the floating variant bar: pure white on near-black, high contrast,
// obviously not part of the game's palette — the point is that it reads as scaffolding.
draw_proto_switcher :: proc(mouse: rl.Vector2) {
	bar := proto_bar_rect()
	rl.DrawRectangleRec(bar, rl.Color{0, 0, 0, 220})
	rl.DrawRectangleLinesEx(bar, 2, rl.WHITE)

	for right in ([2]bool{false, true}) {
		arrow := proto_arrow_rect(right)
		if rl.CheckCollisionPointRec(mouse, arrow) {
			rl.DrawRectangleRec(arrow, rl.Color{255, 255, 255, 60})
		}
		glyph := right ? cstring(">") : cstring("<")
		rl.DrawTextEx(ui_font_body, glyph, rl.Vector2{arrow.x + 11, arrow.y + 3}, UI_BODY_SIZE, 1, rl.WHITE)
	}

	label := fmt.ctprintf("%s", proto_variant_label(proto_variant))
	lw := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1).x
	rl.DrawTextEx(ui_font_body, label, rl.Vector2{bar.x + (bar.width - lw) / 2, bar.y + 7}, UI_BODY_SIZE, 1, rl.WHITE)

	hint := cstring("PROTOTYPE - arrows switch")
	hw := rl.MeasureTextEx(ui_font_body, hint, UI_BODY_SIZE, 1).x
	rl.DrawTextEx(ui_font_body, hint, rl.Vector2{bar.x + (bar.width - hw) / 2, bar.y + bar.height + 4}, UI_BODY_SIZE, 1, rl.Color{255, 255, 255, 140})
}

// proto_lines is the one description formatter: title, the spec line (size · phase · tags),
// the effect intent, and the material facts (weight, cargo, berth).
proto_lines :: proc(ls: ship.Layout_Slot) -> (title, spec, intent, extra: string) {
	fitting, filled := ls.fitting.?
	if !filled {
		title = fmt.tprintf("(empty %v)", ls.slot.size)
		spec = fmt.tprintf("%v berth", ls.slot.size)
		intent = "nothing installed"
		extra = fmt.tprintf("%s · %v", ls.slot.name, ls.slot.base_visibility)
		return
	}
	title = fitting.name
	spec, intent = fitting_summary_lines(fitting)
	extra = fmt.tprintf(
		"wt %d · %d/%d · %s · %v",
		fitting.weight,
		fitting.cargo_held,
		ship.ship_fitting_capacity(fitting),
		ls.slot.name,
		ls.slot.base_visibility,
	)
	return
}

proto_slot_title :: proc(ls: ship.Layout_Slot) -> string {
	if fitting, filled := ls.fitting.?; filled {
		return fitting.name
	}
	return fmt.tprintf("(empty %v)", ls.slot.size)
}

proto_slot_is_hold :: proc(ls: ship.Layout_Slot) -> bool {
	fitting, filled := ls.fitting.?
	return filled && ship.ship_fitting_is_hold(fitting)
}

draw_ship_prototype :: proc(state: ^Game_State, mouse: rl.Vector2) {
	switch proto_variant {
	case .Current:
	// unreachable — the hook only enters on a non-Current variant
	case .Ship_Cutaway:
		draw_proto_ship_cutaway(state, mouse)
	}
}

// --- Shared paint helpers ----------------------------------------------------------------

// proto_shade multiplies a colour's rgb by f (clamped) — one base wood tone lit several ways.
proto_shade :: proc(c: rl.Color, f: f32) -> rl.Color {
	m :: proc(v: u8, f: f32) -> u8 {
		r := f32(v) * f
		if r > 255 {r = 255}
		if r < 0 {r = 0}
		return u8(r)
	}
	return rl.Color{m(c.r, f), m(c.g, f), m(c.b, f), c.a}
}

// draw_proto_cloud stacks three blocky rects — a pixel cloud, no curves.
draw_proto_cloud :: proc(cx, cy: f32) {
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 70, y = cy + 14, width = 150, height = 22}, PROTO_CLOUD_SHADOW)
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 60, y = cy, width = 120, height = 24}, PROTO_CLOUD)
	rl.DrawRectangleRec(rl.Rectangle{x = cx - 28, y = cy - 14, width = 62, height = 18}, PROTO_CLOUD)
}

PROTO_HORIZON :: f32(300) // 2D sea horizon behind the ship

draw_proto_backdrop :: proc() {
	rl.ClearBackground(PROTO_SKY_HIGH)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = 96, width = WINDOW_WIDTH, height = 96}, PROTO_SKY)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = 192, width = WINDOW_WIDTH, height = PROTO_HORIZON - 192}, PROTO_HAZE)
	draw_proto_cloud(220, 92)
	draw_proto_cloud(1010, 70)

	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_HORIZON, width = WINDOW_WIDTH, height = 24}, PROTO_SEA_DEEP)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_HORIZON + 24, width = WINDOW_WIDTH, height = WINDOW_HEIGHT - PROTO_HORIZON - 24}, PROTO_SEA)
	rl.DrawRectangleRec(rl.Rectangle{x = 0, y = PROTO_HORIZON, width = WINDOW_WIDTH, height = 2}, PROTO_FOAM)
	for i in 0 ..< 64 {
		sx := f32((i * 211) % 1180) + 30
		sy := PROTO_HORIZON + 36 + f32((i * 137) % 340)
		tone := i % 3 == 0 ? PROTO_SHALLOW : PROTO_SEA_BRIGHT
		rl.DrawRectangleRec(rl.Rectangle{x = sx, y = sy, width = 22, height = 3}, rl.Fade(tone, 0.5))
	}
}

// draw_proto_room_base picks a room's wood tone: a rich warm oak for the exposed decks, a
// greyer stowage timber for the holds below deck.
draw_proto_room_base :: proc(ls: ship.Layout_Slot) -> rl.Color {
	if proto_slot_is_hold(ls) {
		return rl.Color{138, 118, 84, 255}
	}
	return rl.Color{156, 104, 58, 255} // rich warm oak
}

// --- The 3/4 galleon cutaway -------------------------------------------------------------
// World axes: x = ship length (stern -x, bow +x), y = up, z = beam. The port side (-z) is cut
// open and faces the camera; the camera sits off the port bow quarter and a little above, so the
// bow angles toward the viewer on the left and we look into every open room. The berths become
// architecture: the holds share one below-deck floor, split by size; the exposed berths become
// the forecastle, the open waist, the sterncastle, and the poop deck above it.

PROTO_ZB :: f32(1.05) // half-beam
PROTO_KEEL_Y :: f32(-1.15) // deepest point of the hull, amidships
PROTO_WATER_Y :: f32(-0.6) // waterline — low on the hull, so the ship rides high and proud
PROTO_DECK_Y :: f32(0.18) // main (weather) deck: ceiling of the holds, floor of the waist
PROTO_STERN_X :: f32(-3.5)
PROTO_BOW_X :: f32(3.7)

Proto_Room_Kind :: enum {
	Hold,
	Waist,
	Forecastle,
	Sterncastle,
	Poop,
}

Proto_Room :: struct {
	slot:       int,
	c:          rl.Vector3,
	hx, hy, hz: f32,
	kind:       Proto_Room_Kind,
}

// proto_size_weight is how much length one hold claims on the below-deck floor, by slot size.
proto_size_weight :: proc(sz: ship.Slot_Size) -> f32 {
	#partial switch sz {
	case .Medium:
		return 1.55
	case .Large:
		return 2.3
	}
	return 1.0
}

// proto_keel_y is the hull bottom at length x: deepest amidships, rising toward bow and stern.
proto_keel_y :: proc(x: f32) -> f32 {
	t := clamp((x - PROTO_STERN_X) / (PROTO_BOW_X - PROTO_STERN_X), 0, 1)
	d := t - 0.44
	return PROTO_KEEL_Y + d * d * 1.7
}

// proto_sheer_y is the hull top (deck edge) at length x: the weather deck, with a little sheer
// rising toward the ends.
proto_sheer_y :: proc(x: f32) -> f32 {
	t := clamp((x - PROTO_STERN_X) / (PROTO_BOW_X - PROTO_STERN_X), 0, 1)
	d := t - 0.5
	return PROTO_DECK_Y + d * d * 0.55
}

// proto_build_rooms turns the layout into placed rooms: the concealed holds across one
// below-deck floor (split by slot size, stern -> bow), and the exposed berths into the four
// weather-deck structures — assigned in layout order, which runs sterncastle, poop, waist,
// forecastle for the template roster. Returns the count actually placed.
proto_build_rooms :: proc(layout: []ship.Layout_Slot) -> (rooms: [8]Proto_Room, count: int) {
	n := min(len(layout), 8)
	ex: [8]int
	nex := 0
	hd: [8]int
	nhd := 0
	for i in 0 ..< n {
		if layout[i].slot.base_visibility == .Exposed {
			ex[nex] = i
			nex += 1
		} else {
			hd[nhd] = i
			nhd += 1
		}
	}

	ri := 0

	// Below deck: one floor, split into compartments by slot size, laid stern -> bow.
	hold_x0 := PROTO_STERN_X + 0.7
	hold_x1 := PROTO_BOW_X - 0.9
	floor_y := PROTO_KEEL_Y + 0.28
	ceil_y := PROTO_DECK_Y - 0.05
	total := f32(0)
	for k in 0 ..< nhd {
		total += proto_size_weight(layout[hd[k]].slot.size)
	}
	if total <= 0 {
		total = 1
	}
	cursor := hold_x0
	for k in 0 ..< nhd {
		w := (hold_x1 - hold_x0) * proto_size_weight(layout[hd[k]].slot.size) / total
		rooms[ri] = Proto_Room {
			slot = hd[k],
			c    = rl.Vector3{cursor + w / 2, (floor_y + ceil_y) / 2, 0},
			hx   = w / 2 - 0.06,
			hy   = (ceil_y - floor_y) / 2,
			hz   = PROTO_ZB - 0.1,
			kind = .Hold,
		}
		ri += 1
		cursor += w
	}

	// Exposed berths -> weather-deck structures, in layout order.
	slots := [4]Proto_Room {
		{c = {-2.45, PROTO_DECK_Y + 0.36, 0}, hx = 1.0, hy = 0.36, hz = PROTO_ZB - 0.12, kind = .Sterncastle},
		{c = {-2.7, PROTO_DECK_Y + 0.92, 0}, hx = 0.64, hy = 0.3, hz = PROTO_ZB - 0.2, kind = .Poop},
		{c = {0.45, PROTO_DECK_Y + 0.4, 0}, hx = 1.4, hy = 0.4, hz = PROTO_ZB - 0.06, kind = .Waist},
		{c = {2.72, PROTO_DECK_Y + 0.34, 0}, hx = 0.84, hy = 0.34, hz = PROTO_ZB - 0.12, kind = .Forecastle},
	}
	for k in 0 ..< min(nex, 4) {
		r := slots[k]
		r.slot = ex[k]
		rooms[ri] = r
		ri += 1
	}

	return rooms, ri
}

// proto_project maps a world point to logical screen coordinates. It must use GetWorldToScreen
// *Ex* with the fixed 1244x700 logical size, NOT plain GetWorldToScreen: the frame renders into
// a 1244x700 render texture while the window is a larger borderless-fullscreen surface, and
// plain GetWorldToScreen would project against the window size — leaving hover-picking and the
// mouse (which is remapped into logical space) in different coordinate systems.
proto_project :: proc(p: rl.Vector3, cam: rl.Camera3D) -> rl.Vector2 {
	return rl.GetWorldToScreenEx(p, cam, WINDOW_WIDTH, WINDOW_HEIGHT)
}

// proto_room_hit reports whether the mouse is over a room's open front face — the slot you
// look into. It projects the four front-face corners and does a point-in-quad test, so the
// hover tracks the actual fitting slot rather than a loose bounding box around the whole room.
proto_room_hit :: proc(mouse: rl.Vector2, r: Proto_Room, cam: rl.Camera3D) -> bool {
	q: [4]rl.Vector2
	q[0] = proto_project(rl.Vector3{r.c.x - r.hx, r.c.y - r.hy, r.c.z - r.hz}, cam)
	q[1] = proto_project(rl.Vector3{r.c.x + r.hx, r.c.y - r.hy, r.c.z - r.hz}, cam)
	q[2] = proto_project(rl.Vector3{r.c.x + r.hx, r.c.y + r.hy, r.c.z - r.hz}, cam)
	q[3] = proto_project(rl.Vector3{r.c.x - r.hx, r.c.y + r.hy, r.c.z - r.hz}, cam)

	// Ray-cast point-in-polygon across the four projected corners.
	inside := false
	j := 3
	for i in 0 ..< 4 {
		a, b := q[i], q[j]
		if (a.y > mouse.y) != (b.y > mouse.y) {
			x := a.x + (mouse.y - a.y) / (b.y - a.y) * (b.x - a.x)
			if mouse.x < x {
				inside = !inside
			}
		}
		j = i
	}
	return inside
}

draw_proto_ship_cutaway :: proc(state: ^Game_State, mouse: rl.Vector2) {
	draw_proto_backdrop()

	rooms, nrooms := proto_build_rooms(state.player.layout[:])

	// Off the port bow quarter, low and wide, but every lever is live: the slider panel drives yaw
	// (bow swing toward the viewer at -z), distance (dolly), height (waterline closeness), the look
	// height (pitch), and the field of view. The camera is derived from those knobs each frame.
	yaw := proto_cam_yaw * math.PI / 180
	target := rl.Vector3{0.2, proto_cam_look, 0}
	camera := rl.Camera3D {
		position   = rl.Vector3 {
			target.x + proto_cam_dist * math.sin(yaw),
			proto_cam_height,
			-proto_cam_dist * math.cos(yaw),
		},
		target     = target,
		up         = rl.Vector3{0, 1, 0},
		fovy       = proto_cam_fov,
		projection = .PERSPECTIVE,
	}

	// Hover keys off the open front face of the fitting slot — you highlight a berth by pointing
	// into the room itself — and when two slots overlap on screen the nearer one wins. Nothing is
	// labelled until you hover, so the ship is never obscured by nameplates or leader lines.
	hovered := -1
	best := f32(1e30)
	for i in 0 ..< nrooms {
		if proto_room_hit(mouse, rooms[i], camera) {
			d := rl.Vector3Distance(camera.position, rooms[i].c)
			if d < best {
				best = d
				hovered = i
			}
		}
	}

	rl.BeginMode3D(camera)

	draw_proto_hull_body()

	for i in 0 ..< nrooms {
		r := rooms[i]
		ls := state.player.layout[r.slot]
		base := draw_proto_room_base(ls)
		if i == hovered {
			base = PROTO_SEA_BRIGHT
		}
		draw_proto_deck_room(r.c, r.hx, r.hy, r.hz, base, r.kind)
	}

	draw_proto_ornament()
	draw_proto_rig()

	rl.EndMode3D()

	// Only the hovered slot draws over the scene: its outline and a description card. The ship
	// itself carries no labels, so nothing obscures the hull.
	if hovered >= 0 {
		draw_proto_slot_outline(rooms[hovered], camera)
		draw_proto_tooltip(state, rooms[hovered], camera)
	}
	draw_build_heading("At Anchor")
	draw_proto_stat_strip(state)
	draw_proto_cam_sliders(mouse)
}

// draw_proto_cam_sliders is the floating camera-tuning panel: white-on-near-black scaffolding in
// the top-right sky, one slider each for yaw, distance, height, look and fov, with the live value
// printed beside every label so the dialled-in numbers can be read straight off. Hidden during
// capture (no real mouse), so screenshots stay clean.
draw_proto_cam_sliders :: proc(mouse: rl.Vector2) {
	if mouse == NO_MOUSE {
		return
	}
	if rl.IsMouseButtonReleased(.LEFT) {
		proto_slider_active = -1
	}

	pw, ph := f32(238), f32(214)
	px, py := WINDOW_WIDTH - pw - 10, f32(86)
	panel := rl.Rectangle{px, py, pw, ph}
	rl.DrawRectangleRec(panel, rl.Color{0, 0, 0, 190})
	rl.DrawRectangleLinesEx(panel, 2, rl.WHITE)
	rl.DrawTextEx(ui_font_body, "PROTOTYPE camera", rl.Vector2{px + 12, py + 8}, UI_BODY_SIZE, 1, rl.Color{255, 255, 255, 150})

	tx := px + 14
	tw := pw - 28
	th := f32(10)
	y := py + 52
	proto_cam_yaw = proto_slider(0, rl.Rectangle{tx, y, tw, th}, mouse, "yaw", proto_cam_yaw, 0, 90)
	y += 34
	proto_cam_dist = proto_slider(1, rl.Rectangle{tx, y, tw, th}, mouse, "dist", proto_cam_dist, 3, 16)
	y += 34
	proto_cam_height = proto_slider(2, rl.Rectangle{tx, y, tw, th}, mouse, "height", proto_cam_height, -0.5, 5)
	y += 34
	proto_cam_look = proto_slider(3, rl.Rectangle{tx, y, tw, th}, mouse, "look", proto_cam_look, -1, 3)
	y += 34
	proto_cam_fov = proto_slider(4, rl.Rectangle{tx, y, tw, th}, mouse, "fov", proto_cam_fov, 25, 90)
}

// proto_slider is one immediate-mode slider: it captures the drag on mouse-down over its (padded)
// track, follows the mouse while held, draws track/fill/handle and "label value", and returns the
// updated value. proto_slider_active keeps one slider from stealing another's drag.
proto_slider :: proc(id: int, track: rl.Rectangle, mouse: rl.Vector2, label: string, value, lo, hi: f32) -> f32 {
	v := value
	hit := rl.Rectangle{track.x - 4, track.y - 8, track.width + 8, track.height + 16}
	if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, hit) {
		proto_slider_active = id
	}
	if proto_slider_active == id && rl.IsMouseButtonDown(.LEFT) {
		t := clamp((mouse.x - track.x) / track.width, 0, 1)
		v = lo + t * (hi - lo)
	}

	frac := clamp((v - lo) / (hi - lo), 0, 1)
	rl.DrawRectangleRec(track, rl.Color{255, 255, 255, 45})
	rl.DrawRectangleRec(rl.Rectangle{track.x, track.y, track.width * frac, track.height}, rl.Color{255, 255, 255, 120})
	hx := track.x + track.width * frac
	rl.DrawRectangleRec(rl.Rectangle{hx - 3, track.y - 4, 6, track.height + 8}, rl.WHITE)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s  %.2f", label, v), rl.Vector2{track.x, track.y - 17}, UI_BODY_SIZE, 1, rl.WHITE)
	return v
}

// draw_proto_slot_outline traces the hovered slot's open front face with a bright line, so the
// berth under the cursor reads unmistakably as selected — the room you point at, outlined.
draw_proto_slot_outline :: proc(r: Proto_Room, cam: rl.Camera3D) {
	q: [4]rl.Vector2
	q[0] = proto_project(rl.Vector3{r.c.x - r.hx, r.c.y - r.hy, r.c.z - r.hz}, cam)
	q[1] = proto_project(rl.Vector3{r.c.x + r.hx, r.c.y - r.hy, r.c.z - r.hz}, cam)
	q[2] = proto_project(rl.Vector3{r.c.x + r.hx, r.c.y + r.hy, r.c.z - r.hz}, cam)
	q[3] = proto_project(rl.Vector3{r.c.x - r.hx, r.c.y + r.hy, r.c.z - r.hz}, cam)
	for i in 0 ..< 4 {
		rl.DrawLineEx(q[i], q[(i + 1) % 4], 2.5, PROTO_FOAM)
	}
}

// draw_proto_hull_body paints the wooden ship the rooms are cut into: the far inner wall and
// the underside as strips following the hull silhouette, the main deck plank, and the bow stem
// and stern transom that cap the ends. The near side is left open — that is the cutaway.
draw_proto_hull_body :: proc() {
	hull :: rl.Color{104, 66, 38, 255} // deep, warm hull timber
	dark := proto_shade(hull, 0.9)
	darker := proto_shade(hull, 0.66)
	deck_cx := (PROTO_STERN_X + PROTO_BOW_X) / 2

	// Far inner wall as vertical strips following the hull silhouette (keel up to the sheer),
	// each strip a touch darker toward the aft so the interior falls into shadow.
	strip := f32(0.16)
	for x := PROTO_STERN_X; x < PROTO_BOW_X - 0.001; x += strip {
		xm := x + strip / 2
		b := proto_keel_y(xm)
		tp := proto_sheer_y(xm)
		if tp - b < 0.05 {
			continue
		}
		t := clamp((xm - PROTO_STERN_X) / (PROTO_BOW_X - PROTO_STERN_X), 0, 1)
		shade := 0.78 + t * 0.28 // aft in shadow, bow catching light
		rl.DrawCube(rl.Vector3{xm, (b + tp) / 2, PROTO_ZB}, strip + 0.006, tp - b, 0.09, proto_shade(hull, shade))
	}

	// Hull bottom: strips spanning the beam, following the keel curve — the ship's underside.
	for x := PROTO_STERN_X; x < PROTO_BOW_X - 0.001; x += strip {
		xm := x + strip / 2
		b := proto_keel_y(xm)
		rl.DrawCube(rl.Vector3{xm, b - 0.05, 0}, strip + 0.006, 0.14, 2 * PROTO_ZB, darker)
	}

	// Main (weather) deck plank spanning the hull: ceiling of the holds, floor of the waist.
	rl.DrawCube(rl.Vector3{deck_cx, PROTO_DECK_Y, 0}, PROTO_BOW_X - PROTO_STERN_X - 0.4, 0.08, 2 * PROTO_ZB, proto_shade(hull, 1.15))

	// A gilded wale and a dark rubbing strake band the hull just below the sheer — flagship trim.
	wale_len := PROTO_BOW_X - PROTO_STERN_X - 0.5
	rl.DrawCube(rl.Vector3{deck_cx, PROTO_DECK_Y - 0.09, PROTO_ZB - 0.05}, wale_len, 0.07, 0.05, PROTO_SAND)
	rl.DrawCube(rl.Vector3{deck_cx, PROTO_DECK_Y - 0.19, PROTO_ZB - 0.05}, wale_len, 0.06, 0.05, darker)

	// Bow stem and stern transom, capping the ends above the waterline.
	rl.DrawCube(rl.Vector3{PROTO_BOW_X - 0.14, proto_sheer_y(PROTO_BOW_X) - 0.1, 0}, 0.28, 0.95, 2 * PROTO_ZB - 0.04, dark)
	rl.DrawCube(rl.Vector3{PROTO_STERN_X + 0.12, proto_sheer_y(PROTO_STERN_X) - 0.05, 0}, 0.24, 1.05, 2 * PROTO_ZB - 0.04, dark)
}

// draw_proto_deck_room paints one empty room. The open (-z) front and the top are open, so the
// camera looks in from the port bow quarter. The waist is special: it is the open weather deck,
// so it draws only its planking — no back or end walls stand up in the middle of the main deck.
draw_proto_deck_room :: proc(c: rl.Vector3, hx, hy, hz: f32, base: rl.Color, kind: Proto_Room_Kind) {
	t :: f32(0.05)
	wire := rl.Fade(PROTO_INK, 0.6)

	// The floor reads for every room, and the hover tint lands on it.
	rl.DrawCube(rl.Vector3{c.x, c.y - hy, c.z}, 2 * hx, t, 2 * hz, proto_shade(base, 0.44)) // floor
	rl.DrawCubeWires(rl.Vector3{c.x, c.y - hy, c.z}, 2 * hx, t, 2 * hz, wire)

	if kind == .Waist {
		return // open weather deck: planking only, no walls
	}

	// Back wall on the far (+z) side, with fore and aft end walls — the enclosed rooms. Wide
	// spread between the lit fore end and the deep-shadowed floor and aft corner models the room.
	rl.DrawCube(rl.Vector3{c.x, c.y, c.z + hz}, 2 * hx, 2 * hy, t, proto_shade(base, 0.82)) // back (far)
	rl.DrawCube(rl.Vector3{c.x - hx, c.y, c.z}, t, 2 * hy, 2 * hz, proto_shade(base, 0.58)) // aft end (shadow)
	rl.DrawCube(rl.Vector3{c.x + hx, c.y, c.z}, t, 2 * hy, 2 * hz, proto_shade(base, 1.14)) // fore end (lit)
	rl.DrawCubeWires(rl.Vector3{c.x, c.y, c.z + hz}, 2 * hx, 2 * hy, t, wire)
}

// draw_proto_rig is the full ship rig of a flagship of the line: three masts — fore, main
// (tallest) and mizzen — each carrying stacked square sails that narrow as they climb, a
// pennant streaming from every masthead, and a bowsprit with its spritsail. This is the
// silhouette that says "grand ship of the line" over the cutaway rooms.
draw_proto_rig :: proc() {
	deck := PROTO_DECK_Y + 0.04
	masts := [3]f32{1.85, 0.4, -1.15} // fore (bow), main (centre), mizzen (stern)
	heights := [3]f32{3.1, 3.9, 2.8}
	tiers := [3]int{2, 3, 2} // sails carried per mast
	for mx, mi in masts {
		h := heights[mi]
		rl.DrawCylinder(rl.Vector3{mx, deck, 0}, 0.05, 0.09, h, 10, PROTO_TRUNK)

		// Stacked square sails: a course low and wide, topsails narrowing above it. They start
		// high on the mast so they ride clear above the lowered castles.
		nt := tiers[mi]
		base_w := f32(1.75)
		tier_h := h * 0.26
		for ti in 0 ..< nt {
			frac := f32(ti) / f32(max(nt, 1))
			sw := base_w * (1.0 - frac * 0.4)
			sy := deck + h * 0.5 + f32(ti) * tier_h
			// Square sails hang athwartships from a yard that crosses the mast: the sail spans the
			// beam (z) and faces fore-and-aft (thin in x), so from the bow quarter we read it at an
			// angle, the way a square-rigger's canvas actually sits.
			rl.DrawCube(rl.Vector3{mx, sy, 0}, 0.04, tier_h * 0.86, sw, PROTO_CREAM)
			rl.DrawCubeWires(rl.Vector3{mx, sy, 0}, 0.04, tier_h * 0.86, sw, PROTO_SAND)
			// Yard crossing the mast athwartships, above the sail.
			rl.DrawCube(rl.Vector3{mx, sy + tier_h * 0.48, 0}, 0.05, 0.05, sw + 0.18, PROTO_TRUNK)
		}

		// Pennant streaming from the masthead.
		rl.DrawCube(rl.Vector3{mx + 0.32, deck + h + 0.1, 0}, 0.6, 0.13, 0.02, PROTO_SEA_DEEP)
		rl.DrawCube(rl.Vector3{mx, deck + h + 0.02, 0}, 0.05, 0.22, 0.05, PROTO_TRUNK)
	}

	// Bowsprit angling up off the bow, with a small spritsail.
	rl.DrawCylinderEx(
		rl.Vector3{PROTO_BOW_X - 0.2, PROTO_DECK_Y + 0.5, 0},
		rl.Vector3{PROTO_BOW_X + 1.25, PROTO_DECK_Y + 1.2, 0},
		0.05,
		0.03,
		8,
		PROTO_TRUNK,
	)
	rl.DrawCube(rl.Vector3{PROTO_BOW_X + 0.7, PROTO_DECK_Y + 0.95, 0}, 0.03, 0.5, 0.7, PROTO_CREAM)
	rl.DrawCubeWires(rl.Vector3{PROTO_BOW_X + 0.7, PROTO_DECK_Y + 0.95, 0}, 0.03, 0.5, 0.7, PROTO_SAND)
}

// draw_proto_ornament is the flagship's finery: gilded caps along the tops of the castles, a
// stern lantern crowning the poop, lit great-cabin windows in the sterncastle, and a figurehead
// at the bow. These are the touches that lift the hull from "a ship" to "the flagship".
draw_proto_ornament :: proc() {
	gold := PROTO_SAND

	// Gilded trim capping the tops of the three deck structures. (Positions track the slots
	// array in proto_build_rooms.)
	rl.DrawCube(rl.Vector3{-2.45, PROTO_DECK_Y + 0.74, 0}, 2.08, 0.07, 2 * (PROTO_ZB - 0.12), gold) // sterncastle
	rl.DrawCube(rl.Vector3{-2.7, PROTO_DECK_Y + 1.24, 0}, 1.34, 0.07, 2 * (PROTO_ZB - 0.2), gold) // poop
	rl.DrawCube(rl.Vector3{2.72, PROTO_DECK_Y + 0.7, 0}, 1.74, 0.07, 2 * (PROTO_ZB - 0.12), gold) // forecastle

	// Stern lantern crowning the poop.
	rl.DrawCube(rl.Vector3{-2.7, PROTO_DECK_Y + 1.4, 0}, 0.2, 0.3, 0.2, PROTO_PARCHMENT)
	rl.DrawCube(rl.Vector3{-2.7, PROTO_DECK_Y + 1.6, 0}, 0.1, 0.12, 0.1, gold)

	// Lit great-cabin windows across the sterncastle's inner (far) wall — the stern gallery.
	for wx := f32(-3.2); wx <= -1.7; wx += 0.36 {
		rl.DrawCube(rl.Vector3{wx, PROTO_DECK_Y + 0.38, PROTO_ZB - 0.16}, 0.22, 0.32, 0.03, PROTO_SHALLOW)
		rl.DrawCubeWires(rl.Vector3{wx, PROTO_DECK_Y + 0.38, PROTO_ZB - 0.16}, 0.22, 0.32, 0.03, gold)
	}

	// Figurehead and beakhead ornament at the bow.
	rl.DrawCube(rl.Vector3{PROTO_BOW_X - 0.02, PROTO_DECK_Y + 0.14, 0}, 0.34, 0.34, 0.44, PROTO_PARCHMENT)
	rl.DrawCubeWires(rl.Vector3{PROTO_BOW_X - 0.02, PROTO_DECK_Y + 0.14, 0}, 0.34, 0.34, 0.44, gold)
}

// --- Nameplates, tooltip, stat strip (shared) --------------------------------------------

proto_nameplate_rect :: proc(center_x, y: f32, ls: ship.Layout_Slot) -> rl.Rectangle {
	label := fmt.ctprintf("%s", proto_slot_title(ls))
	w := rl.MeasureTextEx(ui_font_body, label, UI_BODY_SIZE, 1).x
	return rl.Rectangle{x = center_x - w / 2 - 8, y = y, width = w + 16, height = 22}
}

draw_proto_nameplate_at :: proc(rect: rl.Rectangle, ls: ship.Layout_Slot, hot: bool) {
	is_hold := proto_slot_is_hold(ls)
	rl.DrawRectangleRec(rect, rl.Fade(PROTO_PARCHMENT, hot ? 1.0 : 0.94))
	rl.DrawRectangleLinesEx(rect, hot ? 2 : 1, hot ? PROTO_SEA_DEEP : PROTO_CLIFF)
	rl.DrawTextEx(
		ui_font_body,
		fmt.ctprintf("%s", proto_slot_title(ls)),
		rl.Vector2{rect.x + 8, rect.y + 3},
		UI_BODY_SIZE,
		1,
		is_hold ? PROTO_INK_MUTED : PROTO_INK,
	)
}

// draw_proto_tooltip is the hovered slot's full description, projected off the hull into a clear
// margin and tied back to the slot by a leader line, so the card never occludes the ship. The
// card parks in whichever bottom corner is away from the bow, over open water.
draw_proto_tooltip :: proc(state: ^Game_State, r: Proto_Room, cam: rl.Camera3D) {
	tw, th := f32(300), f32(150)

	// Anchor the leader on the slot's open-face centre; drop the card into the bottom-right corner
	// over open water — the looming bow fills the left and the stat strip sits bottom-left, so the
	// right corner is the reliably clear one.
	anchor := proto_project(rl.Vector3{r.c.x, r.c.y, r.c.z - r.hz}, cam)
	card := rl.Rectangle{x = WINDOW_WIDTH - tw - 14, y = WINDOW_HEIGHT - th - 14, width = tw, height = th}

	tie := rl.Vector2{card.x + 12, card.y + 10}
	rl.DrawLineEx(anchor, tie, 2, rl.Fade(PROTO_INK, 0.7))
	rl.DrawCircleV(anchor, 5, rl.Fade(PROTO_FOAM, 0.9))
	rl.DrawCircleLinesV(anchor, 5, PROTO_SEA_DEEP)

	rl.DrawRectangleRec(card, PROTO_PARCHMENT)
	rl.DrawRectangleLinesEx(card, 2, PROTO_SEA_DEEP)

	title, spec, intent, extra := proto_lines(state.player.layout[r.slot])
	px := card.x + 14
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", title), rl.Vector2{px, card.y + 12}, UI_BODY_SIZE, 1, PROTO_INK)
	rl.DrawRectangleRec(rl.Rectangle{x = px, y = card.y + 34, width = card.width - 28, height = 2}, PROTO_SAND)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", intent), rl.Vector2{px, card.y + 46}, UI_BODY_SIZE, 1, PROTO_INK)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", spec), rl.Vector2{px, card.y + 74}, UI_BODY_SIZE, 1, PROTO_INK_MUTED)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", extra), rl.Vector2{px, card.y + 102}, UI_BODY_SIZE, 1, PROTO_INK_MUTED)
}

draw_proto_stat_strip :: proc(state: ^Game_State) {
	stat := fmt.ctprintf("%s", ship_stat_line(s = &state.player, weight = true))
	sw := rl.MeasureTextEx(ui_font_body, stat, UI_BODY_SIZE, 1).x
	strip := rl.Rectangle{x = 38, y = WINDOW_HEIGHT - 42, width = sw + 20, height = 26}
	rl.DrawRectangleRec(strip, rl.Fade(PROTO_PARCHMENT, 0.92))
	rl.DrawRectangleLinesEx(strip, 2, PROTO_CLIFF)
	rl.DrawTextEx(ui_font_body, stat, rl.Vector2{strip.x + 10, strip.y + 5}, UI_BODY_SIZE, 1, PROTO_INK)
}

// capture_shot_ship_prototypes photographs the cutaway the way capture_shot_home shoots Home:
// a throwaway Sim ticked once into a fresh Game_State, the global put back to Current after.
capture_shot_ship_prototypes :: proc(state: ^Capture_State) {
	if !rl.IsWindowReady() {
		return
	}

	s := sim.sim_create(VOYAGE_SEED)
	defer sim.sim_destroy(&s)

	game := Game_State{}
	defer delete(game.visited)
	defer delete(game.positions)
	defer delete(game.voyage_map.nodes)

	events: [dynamic]sim.Event
	defer delete(events)
	sim.sim_tick(&s, &events)
	for e in events {
		dispatch(&game, e)
	}
	map_width_set(&game, MAP_HOME_W)

	proto_variant = .Ship_Cutaway
	draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0)
	draw_home(&game, Build_Drag{}, nil, NO_MOUSE, 0)
	capture_write(state, "proto-ship-cutaway")
	proto_variant = .Current
}
