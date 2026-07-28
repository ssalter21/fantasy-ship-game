#+private
package presentation

// The paint mode the ship screen draws its surfaces in, and nothing else the hull tools reach
// into. It is inert in the game — the zero value is the shipped shading — so draw_ship_cutaway
// composes exactly the frame it composed before this existed.
//
// It lives here rather than inside the workbench because it is read on the *drawing* path, which
// is the whole point of it. Every hard bug on this screen so far has been something drawn that
// could not be seen: a surface facing the wrong way, a room standing through the planking, a
// window cut into a part of the ship with nothing behind it. None of those look wrong in a
// screenshot — they look slightly dull, or slightly odd — and finding them meant reading pixel
// values back through the lighting arithmetic to work out which face was on screen.
//
// It is one value rather than a flag per mode because the modes are exclusive — a wireframe
// coloured by normal is neither diagnosis — and because it has two drivers, only one of which has
// a keyboard: the workbench sets it from a key press, and the hull sheet sets it per tile so a
// headless run can photograph every mode.
Ship_Paint :: enum {
	// The game's own lighting: her timber under this sun.
	Shaded,
	// Every surface painted by the way it faces — +x red, +y green, +z blue, each negative dark —
	// so a face turned the wrong way is a wrong colour rather than a dull one.
	Normals,
	// The ship as its own wireframe: the loft's resolution, any quad gone degenerate, and — the
	// one that matters — daylight between two pieces that ought to meet.
	Wires,
}

ship_debug_paint: Ship_Paint

// ship_debug_paint_name is the name a mode is labelled by, on the sheet's tiles and in the
// workbench's panel. Enumerated, so a mode added without a label is a compile error rather than a
// row of blank captions.
ship_debug_paint_name :: proc(paint: Ship_Paint) -> string {
	names := [Ship_Paint]string {
		.Shaded  = "shaded",
		.Normals = "normal paint",
		.Wires   = "wireframe",
	}
	return names[paint]
}
