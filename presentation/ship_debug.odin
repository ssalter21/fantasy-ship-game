#+private
package presentation

// The hooks the hull workbench drives the ship screen through, and nothing else does. Both are
// inert in the game — the flags are false — so draw_ship_cutaway composes exactly the frame it
// composed before they existed.
//
// Flying the camera is no longer one of them: the framing is chosen by the caller (#476), so the
// workbench simply hands draw_ship_cutaway a framing built from its own eye, and there is no
// package-level override for the shipped view to be dragged off by.
//
// They are here rather than inside the workbench because they are read on the *drawing* path,
// which is the whole point of them. Every hard bug on this screen so far has been something
// drawn that could not be seen: a surface facing the wrong way, a room standing through the
// planking, a window cut into a part of the ship with nothing behind it. None of those look
// wrong in a screenshot — they look slightly dull, or slightly odd — and finding them meant
// reading pixel values back through the lighting arithmetic to work out which face was on
// screen. These three hooks turn each of those into something visible at a glance.

// ship_debug_normals paints every surface by the normal it is actually being lit from rather
// than by its timber, so a face turned the wrong way is a wrong colour instead of a dull one.
ship_debug_normals: bool

// ship_debug_wires draws the ship as its own wireframe: the loft's resolution, any quad gone
// degenerate, and — the one that matters — daylight between two pieces that ought to meet.
ship_debug_wires: bool
