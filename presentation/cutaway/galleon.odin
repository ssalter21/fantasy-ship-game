package cutaway

import "core:math"
import ship "../../core/ship"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

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
// How high she floats. The waterline is world y=0 and cannot move — the camera sits on it and
// the sea plane is edge-on from there, so every point at y=0 lands on one screen row and the sea
// is drawn along it. Her draught is therefore the keel's depth, and it was 1.15 against a hull
// only 1.33 deep from keel to weather deck: she swam with 86% of herself under, which is a wreck
// settling rather than a ship at anchor. A laden galleon draws a little under half her depth.
//
// Both constants are lifted by the same 0.32 so the lift is rigid. Everything else on this ship —
// the hold floor, the rooms, the sheer, the masts, the bowsprit — is spelled relative to one of
// these two, so nothing else needs touching and nothing shifts inside her.
GALLEON_HALF_BEAM :: f32(1.05)
GALLEON_KEEL_Y :: f32(-0.83) // deepest point of the hull, amidships — and her draught
GALLEON_DECK_Y :: f32(0.50) // main (weather) deck: ceiling of the holds, floor of the waist
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
GALLEON_CAM_LOOK :: f32(1.14) // target height, which tilts the view up
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

// Room is one berth's chamber in hull space, open on the cut (-z) side and on top. `half` is
// the half-extent on each axis, and `half_aft`/`half_fore` are how far outboard it actually
// reaches at its after and forward ends — a taper, because the hull is not a tube.
//
// The taper is the whole reason this is not a box. A compartment sized to one width has to
// pick a width, and every choice is wrong somewhere: size it to its widest station and its
// narrow end stands *through* her planking, which is what put ragged holes in the bow and the
// stern; size it to its narrowest and the middle of the ship goes hollow. A room that carries
// its own two ends fills the space it stands in and never leaves it. `half.z` is the larger of
// the two, so anything wanting a single bounding number still has one.
Room :: struct {
	slot:      ship.Slot_Index,
	centre:    rl.Vector3,
	half:      rl.Vector3,
	half_aft:  f32,
	half_fore: f32,
	kind:      Room_Kind,
}

// galleon_room_half_z is how far outboard the room reaches at length x — its taper, read
// anywhere along it. Both the painter and the picker go through this, so the planking of a
// compartment and the opening the cursor tests against are the same surface.
galleon_room_half_z :: proc(room: Room, x: f32) -> f32 {
	f := clamp((x - (room.centre.x - room.half.x)) / max(2 * room.half.x, 0.001), 0, 1)
	return room.half_aft + (room.half_fore - room.half_aft) * f
}

// View is everything needed to put a point in hull space onto the screen: the camera, the
// matrix it projects through, and the size of the frame that lands in. The frame size is
// carried rather than read from the window on purpose — the game composes at a fixed logical
// size into a render texture and blits that to a larger borderless-fullscreen surface, so a
// projection that asked the window would land in a different coordinate system from the
// (logical-space) mouse.
//
// The **projection is carried as a matrix** rather than left implicit in the camera, and that is
// what lets a view sit between two projections (galleon_view_between, ADR-0032). Everything that
// puts a world point on this screen — the room openings, the picking, the wake, the foam standing
// up her planking — goes through galleon_project, so all of it stays registered to her however far
// the projection has been blended.
View :: struct {
	camera:        rl.Camera3D,
	projection:    rl.Matrix,
	width, height: i32,
}

// Eye is a whole framing of this ship as a value: the five knobs above, plus the two a framing
// off her three-quarter bow never needed.
//
// The game builds two — the moored eye the ship screen is composed around, and the alongside
// eye an Offer or Shop presents her under (ADR-0032). The tools build the rest off those: the
// workbench flies one under the mouse, and the hull contact sheet swings the moored one to six
// named angles. Both shipped ones are settled and tuned by eye; neither is a thing a tool may
// move, and a tool that wants a different angle takes the shipped eye and turns it.
//
// `pan` slides the eye **and its target together** along the camera's right axis, in world
// units. Moving both is what makes it a pan rather than a turn: the view direction is left
// untouched, so a broadside stays a broadside however far she slides out of frame centre.
//
// `ortho`, when present, is the **vertical extent of the view volume in world units** — the same
// number raylib reads Camera3D.fovy as under an orthographic projection — and its absence is an
// ordinary perspective camera. Orthographic is not a detail of the alongside framing, it is the
// point of it: it is the only projection with no convergence anywhere, so every bulkhead is a
// true rectangle however far off-axis she sits.
Eye :: struct {
	yaw, dist, height, look, fov: f32,
	pan:                          f32,
	ortho:                        Maybe(f32),
}

GALLEON_EYE :: Eye {
	yaw    = GALLEON_CAM_YAW,
	dist   = GALLEON_CAM_DIST,
	height = GALLEON_CAM_HEIGHT,
	look   = GALLEON_CAM_LOOK,
	fov    = GALLEON_CAM_FOV,
}

// GALLEON_ALONGSIDE_EYE is the stage framing: dead broadside on the negative-z beam — the side
// her cutaway is opened on — orthographic, and panned to starboard so she drifts to port of frame
// centre and leaves the other half of it clear. Tuned by eye against the rendered ship, like the
// moored knobs above. Why orthographic and why panned rather than turned: ADR-0032.
//
// Under an orthographic projection `dist` no longer sets her size — `ortho` does — and only has
// to keep her in front of the near plane. `height` must equal `look`; galleon_view_from asserts
// it and says why.
GALLEON_ALONGSIDE_EYE :: Eye {
	yaw    = 0,
	dist   = 9.0,
	height = 1.05,
	look   = 1.05,
	fov    = GALLEON_CAM_FOV,
	pan    = 3.00,
	ortho  = 8.5,
}

// The view volume's cull distances. rlgl's own defaults, spelled here because a projection
// matrix built as a *value* has to name them, and rlgl only carries them once a window is
// open — these views are built in unit tests with no window at all.
@(private)
GALLEON_NEAR :: f32(rlgl.CULL_DISTANCE_NEAR)
@(private)
GALLEON_FAR :: f32(rlgl.CULL_DISTANCE_FAR)

// galleon_view is the baked view over a frame of the given size, derived from the tuning knobs.
galleon_view :: proc(width, height: i32) -> View {
	return galleon_view_from(GALLEON_EYE, width, height)
}

// galleon_view_from is the view an arbitrary eye sees. The yaw swings the camera around the
// target toward the open (-z) side, so the bow angles at the viewer.
galleon_view_from :: proc(eye: Eye, width, height: i32) -> View {
	yaw := math.to_radians(eye.yaw)
	target := rl.Vector3{0.2, eye.look, 0}
	position := rl.Vector3{target.x + eye.dist * math.sin(yaw), eye.height, -eye.dist * math.cos(yaw)}
	up := rl.Vector3{0, 1, 0}

	// The pan, along the camera's own right axis. With `up` vertical that axis is horizontal, so
	// panning never changes either height and the invariant below survives any amount of it.
	if eye.pan != 0 {
		right := rl.Vector3Normalize(rl.Vector3CrossProduct(target - position, up)) * eye.pan
		position += right
		target += right
	}

	camera := rl.Camera3D {
		position   = position,
		target     = target,
		up         = up,
		fovy       = eye.fov,
		projection = .PERSPECTIVE,
	}
	if extent, flat := eye.ortho.?; flat {
		// Under an orthographic projection a water plane oblique to the view axis has no horizon
		// at all: parallel rays each meet the plane exactly once, so a plane even slightly off
		// edge-on projects over the *entire* frame, and asking where its edge falls is a question
		// with no answer — the whole frame is sea. A horizontal view axis is the case that does
		// have an answer: the plane is exactly edge-on, world y maps linearly to screen y, and the
		// sea's edge is wherever y = 0 lands (galleon_horizon_y).
		assert(eye.height == eye.look, "an orthographic framing needs a horizontal view axis")
		camera.projection = .ORTHOGRAPHIC
		camera.fovy = extent
	}

	return View {
		camera = camera,
		projection = galleon_projection(eye, width, height),
		width = width,
		height = height,
	}
}

// galleon_projection is the matrix an eye projects through, as a value. raylib builds the same
// one inside BeginMode3D and again inside GetWorldToScreenEx and hands back neither, which is
// no use to a framing that has to blend two of them.
@(private)
galleon_projection :: proc(eye: Eye, width, height: i32) -> rl.Matrix {
	aspect := f32(width) / f32(height)
	if extent, flat := eye.ortho.?; flat {
		top := extent / 2
		return rl.MatrixOrtho(-top * aspect, top * aspect, -top, top, GALLEON_NEAR, GALLEON_FAR)
	}
	return rl.MatrixPerspective(math.to_radians(eye.fov), aspect, GALLEON_NEAR, GALLEON_FAR)
}

// galleon_view_between is the view part-way from one framing to another, and the reason the
// travel to a stage reads as one continuous move rather than a pan followed by a snap.
//
// The camera's own knobs simply interpolate. **The projection cannot** — the two ends do not
// share one — so the projection *matrix* is blended instead: a perspective matrix divides by -z
// and an orthographic one does not, and blending them component-wise gives a valid projective
// transform whose convergence falls off smoothly with `k`. Both ends stay exact. Why not switch
// at the end: ADR-0032.
galleon_view_between :: proc(a, b: Eye, k: f32, width, height: i32) -> View {
	if k <= 0 {
		return galleon_view_from(a, width, height)
	}
	if k >= 1 {
		return galleon_view_from(b, width, height)
	}

	// Mid-move the camera stays a perspective one — `ortho` left absent — because the matrix below
	// is what actually draws, and a camera claiming to be orthographic without the horizontal
	// axis that makes one meaningful would trip galleon_view_from's assert on every frame of a
	// move whose whole job is to arrive at that axis.
	mix :: proc(from, to, k: f32) -> f32 {return from + (to - from) * k}
	between := Eye {
		yaw    = mix(a.yaw, b.yaw, k),
		dist   = mix(a.dist, b.dist, k),
		height = mix(a.height, b.height, k),
		look   = mix(a.look, b.look, k),
		fov    = a.fov,
		pan    = mix(a.pan, b.pan, k),
	}

	view := galleon_view_from(between, width, height)
	from := galleon_projection(a, width, height)
	to := galleon_projection(b, width, height)
	for r in 0 ..< 4 {
		for c in 0 ..< 4 {
			view.projection[r, c] = mix(from[r, c], to[r, c], k)
		}
	}
	return view
}

// galleon_project puts one point in hull space onto the view's frame, through the matrix the
// view carries. This is raylib's own GetWorldToScreenEx arithmetic with the projection taken
// from the view rather than rebuilt from the camera — which is the whole difference, since a
// blended projection is not a thing a camera can describe.
galleon_project :: proc(point: rl.Vector3, view: View) -> rl.Vector2 {
	eye_space := rl.GetCameraMatrix(view.camera) * [4]f32{point.x, point.y, point.z, 1}
	clip := view.projection * eye_space
	// Normalized device coordinates, y inverted: screen y runs down where clip y runs up.
	return rl.Vector2 {
		(clip.x / clip.w + 1) / 2 * f32(view.width),
		(-clip.y / clip.w + 1) / 2 * f32(view.height),
	}
}

// Loft is every number that shapes her, as opposed to the five that size her. Her extent and
// her deck height are fixed above — that is the ship's scale, and the camera is framed to it —
// but the curves inside that box are all tuning, and tuning is what a number in source is worst
// at. Held as a value rather than as constants so the hull workbench (game.exe --workbench) can
// drag them and watch her change, then emit the result back as source. GALLEON_LOFT is the
// shipped set, so the game draws exactly what it drew when these were constants.
Loft :: struct {
	// The keel: how deep the camber is, and where along her length its lowest point falls.
	keel_camber: f32,
	keel_low:    f32,
	// The sheer: how far the rail stands above the deck amidships, and how hard it sweeps up
	// toward her ends.
	sheer_rise:   f32,
	sheer_camber: f32,
	// The plan. The entry begins fining at entry_start of her length and closes to nothing at
	// the stem, along a curve of entry_power. Aft she is filling out from the transom, which
	// carries run_fill of her beam and reaches full within run_span.
	entry_start: f32,
	entry_power: f32,
	run_fill:    f32,
	run_span:    f32,
	run_power:   f32,
	// The section: where her greatest beam falls on a frame, how much beam she still carries
	// down at the garboard beside the keel, how the turn of the bilge rises to the wale, and how
	// far the topsides fall back in above it.
	wale_t:     f32,
	garboard:   f32,
	rise_power: f32,
	tumblehome: f32,
}

GALLEON_LOFT :: Loft {
	keel_camber  = 1.7,
	keel_low     = 0.44,
	sheer_rise   = 0.17,
	sheer_camber = 0.75,
	entry_start  = 0.60,
	entry_power  = 1.45,
	run_fill     = 0.74,
	run_span     = 0.30,
	run_power    = 0.65,
	wale_t       = 0.68,
	garboard     = 0.10,
	rise_power   = 0.55,
	tumblehome   = 0.19,
}

// galleon_loft is the loft in force. One package-level value rather than a parameter threaded
// through thirty call sites: the hull is a property of the ship, every proc here describes the
// same one, and the workbench is the only thing that ever writes it.
galleon_loft := GALLEON_LOFT

// galleon_keel_y is the hull's bottom at length x: deepest amidships, rising toward both ends.
galleon_keel_y :: proc(x: f32) -> f32 {
	d := galleon_length_fraction(x) - galleon_loft.keel_low
	return GALLEON_KEEL_Y + d * d * galleon_loft.keel_camber
}

// galleon_sheer_y is the hull's top — the rail, capping the bulwark that stands round the
// weather deck — at length x. It carries real sheer: highest at the bow and the stern, lowest
// amidships, which is the line that reads as a ship from any distance. The deck itself is flat
// at GALLEON_DECK_Y, so the gap between the two *is* the bulwark, deepest where the sheer runs
// up at her ends.
galleon_sheer_y :: proc(x: f32) -> f32 {
	d := galleon_length_fraction(x) - 0.5
	return GALLEON_DECK_Y + galleon_loft.sheer_rise + d * d * galleon_loft.sheer_camber
}

// galleon_length_fraction is x as 0 at the stern, 1 at the bow — the parameter both hull
// curves are shaped in.
@(private)
galleon_length_fraction :: proc(x: f32) -> f32 {
	return clamp((x - GALLEON_STERN_X) / (GALLEON_BOW_X - GALLEON_STERN_X), 0, 1)
}

// galleon_half_beam is her waterline plan: how much of the full beam the hull carries at length
// x. She holds her greatest beam over the middle of her length, fines away to a sharp stem
// forward, and comes aft to a broad transom — a plan, where a constant would be a plank.
galleon_half_beam :: proc(x: f32) -> f32 {
	f := galleon_length_fraction(x)
	// Forward of three-fifths she fines away into the stem; aft of a third she is still filling
	// out from the transom. The narrower of the two shapes her at any station.
	//
	// The entry closes to *nothing* at the stem, and it starts closing early and eases in rather
	// than pinching at the last moment. Both matter. A taper that stops a hand's breadth short
	// leaves a little transom on the front of the ship, and one that does all its work in the
	// last fifth of her length arrives at that point as a corner: the bow has to be a curve the
	// eye can follow the whole way in, or it does not read as a bow at all.
	l := galleon_loft
	entry := 1 - math.pow(clamp((f - l.entry_start) / max(1 - l.entry_start, 0.001), 0, 1), l.entry_power)
	run := l.run_fill + (1 - l.run_fill) * math.pow(clamp(f / max(l.run_span, 0.001), 0, 1), l.run_power)
	return GALLEON_HALF_BEAM * min(entry, run)
}

// galleon_frame_half_beam is her section: how wide she is at height y on the frame at length x.
// Narrow at the garboard beside the keel, widening through the turn of the bilge to her
// greatest beam at the wale, and falling in again above it — the tumblehome a ship of the line
// carries, which is what makes a hull read as a hull and not a bathtub.
galleon_frame_half_beam :: proc(x, y: f32) -> f32 {
	l := galleon_loft
	keel := galleon_keel_y(x)
	sheer := galleon_sheer_y(x)
	t := clamp((y - keel) / max(sheer - keel, 0.001), 0, 1)
	rise := math.pow(clamp(t / max(l.wale_t, 0.001), 0, 1), l.rise_power)
	tumble := clamp((t - l.wale_t) / max(1 - l.wale_t, 0.001), 0, 1)
	return galleon_half_beam(x) * (l.garboard + (1 - l.garboard) * rise - l.tumblehome * tumble * tumble)
}

// GALLEON_ROOM_INSET is how far inside her frames a compartment stands: the thickness of the
// planking it is cut into, plus enough clearance that a corner never shows through it.
GALLEON_ROOM_INSET :: f32(0.06)

// galleon_room_half_beam is how far outboard a compartment may reach at length x with its floor
// at y — the beam her frame carries there, less the planking. It is asked at each end of a room
// rather than once for the whole of it, which is what makes the cut openings follow the hull in
// toward the bow the way the cut in a real cutaway drawing does.
galleon_room_half_beam :: proc(x, floor_y: f32) -> f32 {
	return max(galleon_frame_half_beam(x, floor_y) - GALLEON_ROOM_INSET, 0.08)
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
	// The poop's floor is the sterncastle's roof, so it is placed to stand *on* that roof rather
	// than at a height of its own. Sunk into it — which is where the first placement put it — its
	// own deck is buried and the two read as one lump with a step in it.
	{centre = {-2.7, GALLEON_DECK_Y + 1.08, 0}, half = {0.64, 0.3, GALLEON_HALF_BEAM - 0.2}, kind = .Poop},
	{centre = {0.45, GALLEON_DECK_Y + 0.4, 0}, half = {1.4, 0.4, GALLEON_HALF_BEAM - 0.06}, kind = .Waist},
	{centre = {2.45, GALLEON_DECK_Y + 0.34, 0}, half = {0.70, 0.34, GALLEON_HALF_BEAM - 0.12}, kind = .Forecastle},
}

// The below-deck floor's extent: it stops short of the stem and the transom, and is capped by
// the main deck above and floored a little clear of the keel. Exported because the painter cuts
// the port planking to just under this floor — the cut has to be where the compartments are, or
// it opens onto nothing.
GALLEON_HOLD_FLOOR_Y :: GALLEON_KEEL_Y + 0.28
GALLEON_HOLD_CEIL_Y :: GALLEON_DECK_Y - 0.05

// Where that floor begins and ends. Both stop well inside the point where her rising floors come
// up to meet it — carried further the flat deck comes out through the bottom of the hull — and
// the painter needs them too: the sole runs between them and a peak bulkhead closes each end, so
// the below-deck space has ends of its own rather than fading away into the bow.
GALLEON_HOLD_X0 :: GALLEON_STERN_X + 0.7
GALLEON_HOLD_X1 :: GALLEON_BOW_X - 1.7

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
	floor_x0 := GALLEON_HOLD_X0
	floor_x1 := GALLEON_HOLD_X1
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
		galleon_fit_room_to_hull(&rooms[n])
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
		galleon_fit_room_to_hull(&rooms[n])
		n += 1
	}

	return rooms, n
}

// galleon_fit_room_to_hull pulls a room's outboard reach in to the frames around it, end by end,
// and never pushes it out: the placements above spell the widest a chamber would like to be, and
// the hull says how much of that it can have at each of its ends. Measured at the floor, which is
// where the frames around a compartment are tightest. Doing it here, once, is what keeps the
// painted room and the picked room inside the same planking.
@(private)
galleon_fit_room_to_hull :: proc(room: ^Room) {
	floor := room.centre.y - room.half.y
	room.half_aft = min(room.half.z, galleon_room_half_beam(room.centre.x - room.half.x, floor))
	room.half_fore = min(room.half.z, galleon_room_half_beam(room.centre.x + room.half.x, floor))
	room.half.z = max(room.half_aft, room.half_fore)
}

// galleon_room_face is a room's open front face projected onto the frame — the four corners of
// the opening you look into, in winding order.
galleon_room_face :: proc(room: Room, view: View) -> [4]rl.Vector2 {
	aft := room.centre.x - room.half.x
	fore := room.centre.x + room.half.x
	z_aft := room.centre.z - room.half_aft
	z_fore := room.centre.z - room.half_fore
	corners := [4]rl.Vector3 {
		{aft, room.centre.y - room.half.y, z_aft},
		{fore, room.centre.y - room.half.y, z_fore},
		{fore, room.centre.y + room.half.y, z_fore},
		{aft, room.centre.y + room.half.y, z_aft},
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
//
// "Nearer" is depth **along the view axis**, not distance from the eye. The two agree closely
// for a camera pointed at the middle of the ship and disagree under an orthographic one, where
// the eye is a direction rather than a place: a panned orthographic camera is metres to one side
// of everything it draws, so ranking by distance from it would put the rooms nearest the pan in
// front of the rooms actually closest to the plane of the screen. Depth along the axis is what a
// depth buffer measures, and it is right under both projections.
galleon_room_at :: proc(layout: []ship.Layout_Slot, point: rl.Vector2, view: View) -> Maybe(ship.Slot_Index) {
	rooms, n := galleon_rooms(layout)
	axis := rl.Vector3Normalize(view.camera.target - view.camera.position)
	hit: Maybe(ship.Slot_Index)
	nearest := max(f32)
	for i in 0 ..< n {
		room := rooms[i]
		if !point_in_quad(point, galleon_room_face(room, view)) {
			continue
		}
		face_centre := rl.Vector3{room.centre.x, room.centre.y, room.centre.z - room.half.z}
		depth := rl.Vector3DotProduct(face_centre - view.camera.position, axis)
		if depth < nearest {
			nearest = depth
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

// galleon_waterline_y is the screen row she floats on: where world y = 0 lands abreast of her.
// Everything the sea does *to the hull* — the foam standing up her planking, the stream turning
// at her stem — belongs on this row rather than on the horizon, because from an eye off the
// water plane the two are different lines.
galleon_waterline_y :: proc(view: View) -> f32 {
	return galleon_project({0, 0, 0}, view).y
}

// galleon_horizon_y is where the sea's edge crosses the screen for this view — the backdrop's
// sky/sea join, drawn there rather than at a guessed height, which is what puts the water across
// her lower planking instead of through her deck.
//
// The two projections answer differently, and it is not a special case bolted on — it is what
// removing the perspective divide *means*. Under perspective the edge is the water plane's
// vanishing point, found by projecting a point at eye height far down the view. Under an
// orthographic projection there is no vanishing point at all: parallel rays each meet the plane
// exactly once, so a far point is no more informative than a near one. What an edge-on plane has
// instead is one screen row, which is galleon_waterline_y — and galleon_view_from's assert is
// what guarantees the plane is edge-on enough for that row to exist.
//
// A view part-way through galleon_view_between has **no answer worth having**: the vanishing
// point of a nearly-orthographic blend is real but rockets off frame as k approaches 1, where
// the true edge is most of the way down it. A caller travelling between two framings asks for
// galleon_waterline_y instead — continuous the whole way, and equal to this at both ends.
galleon_horizon_y :: proc(view: View) -> f32 {
	if view.camera.projection == .ORTHOGRAPHIC {
		return galleon_waterline_y(view)
	}
	FAR :: f32(10000)
	forward := view.camera.target - view.camera.position
	forward.y = 0 // level with the eye: the water plane's vanishing direction
	return galleon_project(view.camera.position + rl.Vector3Normalize(forward) * FAR, view).y
}
