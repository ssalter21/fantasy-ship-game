#+private
package presentation

import cutaway "./cutaway"

// The hooks the hull workbench drives the ship screen through, and nothing else does. All of
// them are inert in the game: the flags are false and the eye is absent, so draw_ship_cutaway
// composes exactly the frame it composed before they existed.
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

// ship_debug_eye flies the camera off the shipped framing. Absent in the game, and it must
// stay absent: the five knobs in cutaway/galleon.odin are the composition every other element
// on this screen is placed against. This is for walking round her to find out whether a thing
// is solid, then coming back.
ship_debug_eye: Maybe(cutaway.Eye)
