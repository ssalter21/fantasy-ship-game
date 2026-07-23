package cutaway

import "core:math"
import ship "../../core/ship"
import rl "vendor:raylib"

// The galleon is the ship screen's three-quarter cutaway: the same "where does this slot
// sit" answer cutaway_slot_rects gives the encounter stages, in three dimensions. World
// axes are x = ship length (stern -x, bow +x), y = up, z = beam; the port side (-z) is cut
// open and faces the camera, so every room is looked into rather than at.
//
// The berths become ship architecture. The concealed holds share ONE below-deck floor, cut
// into compartments whose length follows each hold's slot size. The exposed berths become
// the weather-deck structures, taken in layout order: sterncastle, the poop deck above it,
// the open waist amidships, and the forecastle at the bow.
//
// Drawing and picking both ask this file, so the painted room and the hovered room cannot
// drift apart. Painting stays with the caller — this package decides *where*, never how it
// looks.

// The hull's frame: her extent along each axis, and the height of the weather deck. The rooms
// are placed against these, and the painter hangs its planking, rig and ornament off them.
GALLEON_HALF_BEAM :: f32(1.05)
GALLEON_KEEL_Y :: f32(-1.15) // deepest point of the hull, amidships
GALLEON_DECK_Y :: f32(0.18) // main (weather) deck: ceiling of the holds, floor of the waist
GALLEON_STERN_X :: f32(-3.5)
GALLEON_BOW_X :: f32(3.7)

// The camera: off the port bow quarter, drawn in close, right down at the waterline and
// tilted up, so the bow looms on the left and the stern recedes with the vanishing point in
// frame. The five values were dialled in by eye against the rendered ship, not derived — they
// stay spelled as the knobs they were tuned as, and galleon_view builds the Camera3D from
// them.
GALLEON_CAM_YAW :: f32(55.75) // bow-toward-viewer swing, degrees
GALLEON_CAM_DIST :: f32(6.92) // horizontal distance from the target
GALLEON_CAM_HEIGHT :: f32(0.0) // camera height — level with the waterline
GALLEON_CAM_LOOK :: f32(0.92) // target height, which tilts the view up
GALLEON_CAM_FOV :: f32(55.24) // field of view, degrees

// Room_Kind is what a berth became when it was mapped onto the hull. The painter reads it to
// decide a room's timber and whether it has walls at all — the waist is the open weather
// deck, so it is planking and nothing else.
Room_Kind :: enum {
	Hold,
	Waist,
	Forecastle,
	Sterncastle,
	Poop,
}

// Room is one berth's chamber: a box in hull space, open on the cut (-z) side and on top.
// `half` is the half-extent on each axis, so the open face spans centre ± half in x and y at
// z = centre.z - half.z.
Room :: struct {
	slot:   ship.Slot_Index,
	centre: rl.Vector3,
	half:   rl.Vector3,
	kind:   Room_Kind,
}

// View is everything needed to put a point in hull space onto the screen: the camera, and the
// size of the frame it is projected into. The frame size is carried rather than read from the
// window on purpose — the game composes at a fixed logical size into a render texture and
// blits that to a larger borderless-fullscreen surface, so a projection that asked the window
// would land in a different coordinate system from the (logical-space) mouse.
View :: struct {
	camera:        rl.Camera3D,
	width, height: i32,
}

// galleon_view is the baked view over a frame of the given size, derived from the five tuning
// knobs. The yaw swings the camera around the target toward the open (-z) side, so the bow
// angles at the viewer.
galleon_view :: proc(width, height: i32) -> View {
	yaw := math.to_radians(GALLEON_CAM_YAW)
	target := rl.Vector3{0.2, GALLEON_CAM_LOOK, 0}
	return View {
		camera = rl.Camera3D {
			position = rl.Vector3 {
				target.x + GALLEON_CAM_DIST * math.sin(yaw),
				GALLEON_CAM_HEIGHT,
				-GALLEON_CAM_DIST * math.cos(yaw),
			},
			target = target,
			up = rl.Vector3{0, 1, 0},
			fovy = GALLEON_CAM_FOV,
			projection = .PERSPECTIVE,
		},
		width = width,
		height = height,
	}
}

// galleon_project puts one point in hull space onto the view's frame.
galleon_project :: proc(point: rl.Vector3, view: View) -> rl.Vector2 {
	return rl.GetWorldToScreenEx(point, view.camera, view.width, view.height)
}

// galleon_keel_y is the hull's bottom at length x: deepest amidships, rising toward both ends.
galleon_keel_y :: proc(x: f32) -> f32 {
	d := galleon_length_fraction(x) - 0.44
	return GALLEON_KEEL_Y + d * d * 1.7
}

// galleon_sheer_y is the hull's top — the deck edge — at length x: the weather deck with a
// little sheer rising toward bow and stern.
galleon_sheer_y :: proc(x: f32) -> f32 {
	d := galleon_length_fraction(x) - 0.5
	return GALLEON_DECK_Y + d * d * 0.55
}

// galleon_length_fraction is x as 0 at the stern, 1 at the bow — the parameter both hull
// curves are shaped in.
@(private)
galleon_length_fraction :: proc(x: f32) -> f32 {
	return clamp((x - GALLEON_STERN_X) / (GALLEON_BOW_X - GALLEON_STERN_X), 0, 1)
}

// galleon_size_weight is how much of the below-deck floor's length one hold claims, by slot
// size — the compartment bulkheads land where these shares fall, so a Large hold reads as a
// bigger room without a number on it.
@(private)
galleon_size_weight :: proc(size: ship.Slot_Size) -> f32 {
	switch size {
	case .Small:
		return 1.0
	case .Medium:
		return 1.55
	case .Large:
		return 2.3
	}
	return 1.0
}

// GALLEON_STRUCTURES is where the four weather-deck structures sit, in the order exposed
// berths are taken from the layout. A layout with fewer exposed berths simply leaves the
// tail of it unbuilt.
@(private)
GALLEON_STRUCTURES :: [4]Room {
	{centre = {-2.45, GALLEON_DECK_Y + 0.36, 0}, half = {1.0, 0.36, GALLEON_HALF_BEAM - 0.12}, kind = .Sterncastle},
	{centre = {-2.7, GALLEON_DECK_Y + 0.92, 0}, half = {0.64, 0.3, GALLEON_HALF_BEAM - 0.2}, kind = .Poop},
	{centre = {0.45, GALLEON_DECK_Y + 0.4, 0}, half = {1.4, 0.4, GALLEON_HALF_BEAM - 0.06}, kind = .Waist},
	{centre = {2.72, GALLEON_DECK_Y + 0.34, 0}, half = {0.84, 0.34, GALLEON_HALF_BEAM - 0.12}, kind = .Forecastle},
}

// The below-deck floor's extent: it stops short of the stem and the transom, and is capped by
// the main deck above and floored a little clear of the keel.
@(private)
GALLEON_HOLD_FLOOR_Y :: GALLEON_KEEL_Y + 0.28
@(private)
GALLEON_HOLD_CEIL_Y :: GALLEON_DECK_Y - 0.05

// galleon_rooms places every slot into the hull: the concealed berths as compartments across
// one below-deck floor laid stern → bow, the exposed berths as the weather-deck structures in
// layout order. Rooms come back in placement order, not layout order — each carries the slot
// it belongs to — and `n` is how many of the MAX_SLOTS entries are live. A pure function of
// the layout, so drawing and picking ask it rather than sharing a local.
galleon_rooms :: proc(layout: []ship.Layout_Slot) -> (rooms: [MAX_SLOTS]Room, n: int) {
	live := min(len(layout), MAX_SLOTS)

	exposed, below: [MAX_SLOTS]ship.Slot_Index
	n_exposed, n_below: int
	for i in 0 ..< live {
		if layout[i].slot.base_visibility == .Exposed {
			exposed[n_exposed] = ship.Slot_Index(i)
			n_exposed += 1
		} else {
			below[n_below] = ship.Slot_Index(i)
			n_below += 1
		}
	}

	// One floor, cut into compartments whose length is each hold's share of the total weight.
	floor_x0 := GALLEON_STERN_X + 0.7
	floor_x1 := GALLEON_BOW_X - 0.9
	total: f32 = 0
	for k in 0 ..< n_below {
		total += galleon_size_weight(layout[below[k]].slot.size)
	}
	cursor := floor_x0
	for k in 0 ..< n_below {
		length := (floor_x1 - floor_x0) * galleon_size_weight(layout[below[k]].slot.size) / total
		rooms[n] = Room {
			slot   = below[k],
			centre = rl.Vector3{cursor + length / 2, (GALLEON_HOLD_FLOOR_Y + GALLEON_HOLD_CEIL_Y) / 2, 0},
			// A bulkhead's worth of gap in x keeps neighbouring compartments reading as two rooms.
			half   = rl.Vector3 {
				length / 2 - 0.06,
				(GALLEON_HOLD_CEIL_Y - GALLEON_HOLD_FLOOR_Y) / 2,
				GALLEON_HALF_BEAM - 0.1,
			},
			kind   = .Hold,
		}
		n += 1
		cursor += length
	}

	// The hull has four weather-deck structures and no more. A fifth exposed berth would be
	// placed nowhere — invisible on the ship, and unreachable by galleon_room_at, so nothing
	// could be dropped into it — which is a content bug worth failing loudly on.
	structures := GALLEON_STRUCTURES
	assert(n_exposed <= len(structures), "a layout may carry at most four exposed berths")
	for k in 0 ..< min(n_exposed, len(structures)) {
		room := structures[k]
		room.slot = exposed[k]
		rooms[n] = room
		n += 1
	}

	return rooms, n
}

// galleon_room_face is a room's open front face projected onto the frame — the four corners of
// the opening you look into, in winding order.
galleon_room_face :: proc(room: Room, view: View) -> [4]rl.Vector2 {
	z := room.centre.z - room.half.z
	corners := [4]rl.Vector3 {
		{room.centre.x - room.half.x, room.centre.y - room.half.y, z},
		{room.centre.x + room.half.x, room.centre.y - room.half.y, z},
		{room.centre.x + room.half.x, room.centre.y + room.half.y, z},
		{room.centre.x - room.half.x, room.centre.y + room.half.y, z},
	}
	face: [4]rl.Vector2
	for corner, i in corners {
		face[i] = galleon_project(corner, view)
	}
	return face
}

// galleon_face_centre is the middle of a projected opening — where a leader line is tied, and
// the point a cursor has to be on to be pointing into that room.
galleon_face_centre :: proc(face: [4]rl.Vector2) -> rl.Vector2 {
	return (face[0] + face[1] + face[2] + face[3]) / 4
}

// galleon_room_for_slot finds the room a slot became. Rooms come back in placement order
// rather than layout order, so the slot is looked up rather than indexed.
galleon_room_for_slot :: proc(rooms: [MAX_SLOTS]Room, n: int, slot: ship.Slot_Index) -> (Room, bool) {
	for i in 0 ..< n {
		if rooms[i].slot == slot {
			return rooms[i], true
		}
	}
	return {}, false
}

// galleon_room_at returns the slot whose open face the point is over, or nil. Picking keys off
// the face rather than a bounding box, so pointing *into* a room is what selects that berth.
// Where two openings overlap on screen the nearer opening wins — measured to the face, not the
// room's centre, since it is the face the cursor is on.
galleon_room_at :: proc(layout: []ship.Layout_Slot, point: rl.Vector2, view: View) -> Maybe(ship.Slot_Index) {
	rooms, n := galleon_rooms(layout)
	hit: Maybe(ship.Slot_Index)
	nearest := max(f32)
	for i in 0 ..< n {
		room := rooms[i]
		if !point_in_quad(point, galleon_room_face(room, view)) {
			continue
		}
		face_centre := rl.Vector3{room.centre.x, room.centre.y, room.centre.z - room.half.z}
		if distance := rl.Vector3Distance(view.camera.position, face_centre); distance < nearest {
			nearest = distance
			hit = room.slot
		}
	}
	return hit
}

// point_in_quad is a ray-cast point-in-polygon over four projected corners. Perspective keeps
// a face a convex quad but not a rectangle, so the test has to be against the quad itself.
@(private)
point_in_quad :: proc(point: rl.Vector2, quad: [4]rl.Vector2) -> bool {
	inside := false
	j := len(quad) - 1
	for i in 0 ..< len(quad) {
		a, b := quad[i], quad[j]
		if (a.y > point.y) != (b.y > point.y) {
			crossing := a.x + (point.y - a.y) / (b.y - a.y) * (b.x - a.x)
			if point.x < crossing {
				inside = !inside
			}
		}
		j = i
	}
	return inside
}

// galleon_horizon_y is where the sea's horizon crosses the screen for this camera: the
// vanishing point of the water plane, found by projecting a point at eye height far down the
// view. The backdrop's horizon is drawn there rather than at a guessed height, which is what
// puts the waterline across the lower hull instead of through the deck.
galleon_horizon_y :: proc(view: View) -> f32 {
	FAR :: f32(10000)
	forward := view.camera.target - view.camera.position
	forward.y = 0 // level with the eye: the water plane's vanishing direction
	return galleon_project(view.camera.position + rl.Vector3Normalize(forward) * FAR, view).y
}
