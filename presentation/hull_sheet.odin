package presentation

import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import cutaway "./cutaway"
import rl "vendor:raylib"

// The hull contact sheet: `game.exe --hull-sheet`. One PNG holding the galleon from every named
// eye in every paint mode, so a session working on the hull sees the whole thing in a single
// `Read` rather than reasoning about her geometry by text.
//
// It exists because a geometry bug on this screen is invisible rather than small: a wrongly-wound
// face draws *nothing at all*, so a resting shot from the shipped quarter looks fine and the bug
// ships. Six angles at once is the cheapest thing that makes a hole in her visible — a face that is
// missing from one eye and solid from its opposite is a winding, and nothing else.
//
// The sheet is also a shot-manifest entry (`docs/ui/shot-manifest.txt`, written by scripts/shot.py):
// one hash over every tile, so a hole that opens on any of them names itself the way a moved 2D
// screen does. That is why two runs must write byte-identical pixels — the check re-renders it.
//
// The rows are what make it a diagnosis rather than a sighting. Shaded, a face turned the wrong
// way is a slightly-off shade at best and *identical* at worst, because every surface here is lit
// from whichever side the eye is on — so the other rows are not a nicety, they are the only place
// that defect appears at all. The modes are the workbench's own (Ship_Paint, ship_debug.odin, which
// says what each one shows), taken where there is no keyboard to press them with.
//
// It is capture, not a fourth kind of thing: capture_open's window and pinned clock, the
// registry's own staged ship, and draw_ship_cutaway untouched. Where a shot photographs the
// framebuffer, this composes tiles into an image — which is the whole difference, since a grid of
// frames does not fit in one window.
//
// The framing is the *shipped* one, moved: every eye here comes off cutaway.GALLEON_EYE through
// galleon_view_from, the same way the workbench flies its camera. An angle is all a tile's name
// means, and the shipped eyes are not a thing a tool may move (Eye, in cutaway/galleon.odin) — so
// this must not grow a framing of its own to tune.

@(private)
HULL_SHEET_FILE :: "hull-sheet.png"

// How many eyes the sheet holds, in how many paint modes. hull_sheet_eyes names the eyes, and
// every mode there is gets a row — a mode the ship can be painted in that the sheet did not
// photograph is one a headless session cannot reach at all.
@(private)
HULL_SHEET_EYES :: 6
@(private)
HULL_SHEET_MODES :: len(Ship_Paint)
@(private)
HULL_SHEET_TILES :: HULL_SHEET_EYES * HULL_SHEET_MODES

// The grid, and the sheet it makes. Each tile is one logical frame at full size — the size the
// game composes at — so every tile is the real screen rather than a resized one, and the 2D
// backdrop behind her lands where it does in play.
//
// A row is a paint mode and a column is an eye, which is the axis the reading runs along: the
// same hull in three paints, stacked, so a face that is a wrong colour in one row is compared
// against the shaded frame directly above it rather than against a memory of it. That makes the
// sheet a long strip, and a reader scaling it to fit its longest side spends less of that budget
// per tile than a squarer grid would — this finds *which* surface is wrong, and the workbench is
// where you go to look at it closely.
@(private)
HULL_SHEET_COLS :: HULL_SHEET_EYES
@(private)
HULL_SHEET_ROWS :: HULL_SHEET_MODES
@(private)
HULL_SHEET_W :: WINDOW_WIDTH * HULL_SHEET_COLS
@(private)
HULL_SHEET_H :: WINDOW_HEIGHT * HULL_SHEET_ROWS

// How far over her and under her the two elevated eyes stand. One angle, spent twice: the
// shipped standoff carried up and carried down by the same amount, so above and below are a pair
// rather than two separately dialled framings.
@(private)
HULL_SHEET_ELEVATION :: f32(60)

// Hull_Sheet_Eye is one eye of the sheet: the name it is labelled and reasoned about by, and
// the framing it sees her from.
@(private)
Hull_Sheet_Eye :: struct {
	name: string,
	eye:  cutaway.Eye,
}

// Hull_Sheet_Tile is one frame of the sheet: an eye, in one paint.
@(private)
Hull_Sheet_Tile :: struct {
	name:  string,
	eye:   cutaway.Eye,
	paint: Ship_Paint,
}

// hull_sheet_tiles is the sheet, in the order it is tiled: a mode at a time, so each row is one
// paint across every eye and each column is one eye through every paint.
@(private)
hull_sheet_tiles :: proc() -> [HULL_SHEET_TILES]Hull_Sheet_Tile {
	tiles: [HULL_SHEET_TILES]Hull_Sheet_Tile
	index := 0
	for paint in Ship_Paint {
		for eye in hull_sheet_eyes() {
			tiles[index] = Hull_Sheet_Tile{name = eye.name, eye = eye.eye, paint = paint}
			index += 1
		}
	}
	return tiles
}

// hull_sheet_eyes is the six angles, in the order they are laid across a row — an order the
// *reading* depends on: they go in pairs of opposites, because a face solid from one eye and
// missing from the eye facing it is a winding and nothing else.
@(private)
hull_sheet_eyes :: proc() -> [HULL_SHEET_EYES]Hull_Sheet_Eye {
	return {
		{name = "bow", eye = hull_sheet_eye(90, 0)},
		{name = "stern", eye = hull_sheet_eye(-90, 0)},
		// Dead broadside onto the cut, and *not* GALLEON_ALONGSIDE_EYE: the stage framing is panned
		// to leave a column of parchment half the frame, which would stand her off-centre in a tile
		// that has nothing to leave room for.
		{name = "beam", eye = hull_sheet_eye(0, 0)},
		{name = "quarter", eye = hull_sheet_eye(cutaway.GALLEON_EYE.yaw, 0)},
		// Elevated off the *beam*, not the quarter: from over her quarter the near end of a hull
		// seven units long is a third of the standoff away and the far end twice that, so she runs
		// diagonally out of the corner of the frame.
		{name = "above", eye = hull_sheet_eye(0, HULL_SHEET_ELEVATION)},
		{name = "below", eye = hull_sheet_eye(0, -HULL_SHEET_ELEVATION)},
	}
}

// hull_sheet_eye is one tile's framing: the shipped eye swung round her to `yaw` and carried over
// her (or under her) to `elevation`. Nothing else is touched — her standoff, the height it looks
// at and the lens are the shipped ones.
//
// The yaw is the workbench's own cam-yaw slider, measured toward the open (-z) side: 0 is dead
// onto the cut, 90 is from ahead and -90 from astern.
//
// The elevation rotates that standoff about the point the eye already looks at, so she frames the
// same size from above and below as she does from the quarter. An eye carries a *horizontal*
// distance and an absolute height (galleon_view_from), so the rotation is spelled in those two
// terms rather than as an angle Eye has no field for. It is measured off where the shipped eye
// already stands — which looks slightly up at her — so an elevation of nothing is the shipped
// framing exactly rather than a rounded copy of it.
@(private)
hull_sheet_eye :: proc(yaw, elevation: f32) -> cutaway.Eye {
	eye := cutaway.GALLEON_EYE
	eye.yaw = yaw
	if elevation == 0 {
		return eye
	}

	rise := eye.height - eye.look
	standoff := math.sqrt(eye.dist * eye.dist + rise * rise)
	angle := math.atan2(rise, eye.dist) + math.to_radians(elevation)
	eye.dist = standoff * math.cos(angle)
	eye.height = eye.look + standoff * math.sin(angle)
	return eye
}

// hull_sheet_cell is where one tile lands on the sheet, filled left to right and top to bottom.
@(private)
hull_sheet_cell :: proc(index: int) -> rl.Rectangle {
	col, row := index % HULL_SHEET_COLS, index / HULL_SHEET_COLS
	return rl.Rectangle {
		x = f32(col * WINDOW_WIDTH),
		y = f32(row * WINDOW_HEIGHT),
		width = WINDOW_WIDTH,
		height = WINDOW_HEIGHT,
	}
}

// hull_sheet_requested reports whether the process was started to render the hull sheet. It
// takes no name, so it is a whole-word match like --shots.
hull_sheet_requested :: proc() -> bool {
	return hull_sheet_arg(os.args[1:])
}

@(private)
hull_sheet_arg :: proc(args: []string) -> bool {
	return slice.contains(args, "--hull-sheet")
}

// hull_sheet_main renders every tile into one PNG and returns — no mouse, no keyboard, one
// process that draws and exits, the same sense in which the rest of capture is headless.
//
// Reports whether the sheet landed in the capture directory, and never names a file it did not
// write. The
// sheet an earlier run left is still on disk after a failure, so the report is what says whether
// the one there is this run's.
hull_sheet_main :: proc() -> bool {
	capture_open("Fantasy Ship Game (hull sheet)")
	defer capture_close()

	if !rl.IsWindowReady() {
		fmt.eprintln("capture: the hull sheet needs a window to render into")
		return false
	}

	// The registry's own staged ship — the real starting layout, so the rooms on the sheet are
	// the rooms the game places.
	scene := Capture_Scene{}
	defer capture_scene_destroy(&scene)
	capture_stage_refit(&scene)

	// The sheet is built without an alpha channel, and so is every tile drawn into it. Not a size
	// saving: a frame composed into a render texture comes back with its colour right and its alpha
	// eroded wherever anything translucent was drawn (frame_end says why), so blending such a tile
	// onto the sheet would pull the sheet's ground up through the sun's haze, the foam and every
	// highlight wash. Dropping alpha on both sides makes the copy a copy.
	sheet := rl.GenImageColor(HULL_SHEET_W, HULL_SHEET_H, COLOUR_INK_PRIMARY)
	defer rl.UnloadImage(sheet)
	rl.ImageFormat(&sheet, .UNCOMPRESSED_R8G8B8)

	frame := rl.LoadRenderTexture(WINDOW_WIDTH, WINDOW_HEIGHT)
	defer rl.UnloadRenderTexture(frame)

	for tile, index in hull_sheet_tiles() {
		hull_sheet_draw(&scene, frame, tile)

		// One draw is enough here, unlike a shot: this reads the render texture back directly
		// rather than screenshotting a presented framebuffer, so there is no second buffer to be
		// a frame behind.
		shot := rl.LoadImageFromTexture(frame.texture)
		defer rl.UnloadImage(shot)
		rl.ImageFlipVertical(&shot) // a render texture reads back bottom-up
		rl.ImageFormat(&shot, .UNCOMPRESSED_R8G8B8)
		whole := rl.Rectangle{x = 0, y = 0, width = WINDOW_WIDTH, height = WINDOW_HEIGHT}
		rl.ImageDraw(&sheet, shot, whole, hull_sheet_cell(index), rl.WHITE)
	}

	// rl.ExportImage takes the path it is given, unlike rl.TakeScreenshot — so the sheet is
	// written where it belongs and there is nothing to move afterwards.
	path := fmt.tprintf("%s/%s", capture_dir(), HULL_SHEET_FILE)
	capture_keep_previous(path)
	if !rl.ExportImage(sheet, strings.clone_to_cstring(path, context.temp_allocator)) {
		fmt.eprintfln("capture: could not write %s", path)
		return false
	}
	fmt.printfln("capture: wrote %s", path)
	return true
}

// hull_sheet_draw composes one tile: the real ship screen through this tile's eye, in this tile's
// paint, captioned. No cursor and no drag — the sheet is about her surfaces, and a hovered berth's
// card would stand over the hull it is describing.
//
// The paint mode is state the drawing path reads rather than an argument it takes, so this sets it
// for the tile and puts back whatever was standing: a mode left set would paint every tile after
// this one, and the sheet's whole claim is that its rows differ only in this.
//
// Each tile is its own BeginTextureMode/EndTextureMode, and both ends of that flush the render
// batch — which is what keeps the wireframe row a row. Wire mode is a GL polygon-mode switch over
// geometry rlgl has only queued, so a tile whose geometry was still in flight when the next tile
// switched modes would come out part solid, part mesh. draw_ship_cutaway brackets its own 3D pass
// the same way; between them nothing crosses a tile edge.
@(private)
hull_sheet_draw :: proc(scene: ^Capture_Scene, frame: rl.RenderTexture2D, tile: Hull_Sheet_Tile) {
	rl.BeginTextureMode(frame)
	defer rl.EndTextureMode()

	standing := ship_debug_paint
	ship_debug_paint = tile.paint
	defer ship_debug_paint = standing

	framing := ship_framing_from(cutaway.galleon_view_from(tile.eye, WINDOW_WIDTH, WINDOW_HEIGHT))
	draw_ship_cutaway(&scene.game, framing, Build_Drag{}, NO_MOUSE, describe = false)
	hull_sheet_caption(tile)
}

// hull_sheet_caption names the eye a tile was taken from and the paint it was taken in. It is the
// sheet's own chrome rather than the game's, so it is set at the title size on an opaque plate:
// a grid of views of one ship is only comparable if you can tell which is which, and a name laid
// straight onto the sky reads from some of these eyes and vanishes into the glare from others.
//
// Every tile carries its row's mode rather than the row carrying it once, so a tile still says
// which paint it is when it is read cropped out of the sheet or scaled down to a thumbnail.
@(private)
hull_sheet_caption :: proc(tile: Hull_Sheet_Tile) {
	PAD :: f32(12)
	text := fmt.ctprintf("%s — %s", tile.name, ship_debug_paint_name(tile.paint))
	size := rl.MeasureTextEx(ui_font_title, text, UI_TITLE_SIZE, 1)
	plate := rl.Rectangle{x = 0, y = 0, width = size.x + 2 * PAD, height = size.y + 2 * PAD}
	rl.DrawRectangleRec(plate, COLOUR_INK_PRIMARY)
	rl.DrawTextEx(ui_font_title, text, {PAD, PAD}, UI_TITLE_SIZE, 1, COLOUR_FOAM)
}
