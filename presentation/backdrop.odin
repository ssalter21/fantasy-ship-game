#+private
package presentation

import "core:math"
import rl "vendor:raylib"

// The one art resolution everything behind the chrome is drawn at — sky, sun, cloud, island,
// sea. The register is 16-bit pixel art, and that is a claim about *resolution* before it is one
// about colour: hard edges, flat blocks, no gradients, limited ramps per hue. The style guide
// states the rule (docs/ui/style-guide.md, "The backdrop is drawn at one art resolution"); this
// file is the only place that implements it, so the decision cannot be re-taken at a call site.
//
// Four logical pixels to the art pixel puts a 311x175 art frame inside the 1244x700 logical one.
// Both axes divide exactly, so the lattice reaches all four edges with no part-pixel to hide.
BACKDROP_PIXEL :: f32(4)

// BACKDROP_DITHER is the ordered threshold matrix, indexed in art pixels and holding a
// permutation of 0..15. It is what lets a grade cross between two ramp stops without ruling a
// band across the frame: cells whose threshold falls under the crossing fraction take the next
// stop, the rest keep the current one. The cell being one art pixel is the whole point — the sky
// then dissolves in the same currency the sea's chop is drawn in.
BACKDROP_DITHER := [4][4]f32 {
	{0, 8, 2, 10},
	{12, 4, 14, 6},
	{3, 11, 1, 9},
	{15, 7, 13, 5},
}

// backdrop_snap floors a logical coordinate onto the lattice; backdrop_ceil raises one onto it.
// A mark takes the first for its near edges and the second for its far ones, so snapping never
// eats a mark that started smaller than an art pixel.
backdrop_snap :: proc(v: f32) -> f32 {
	return math.floor(v / BACKDROP_PIXEL) * BACKDROP_PIXEL
}

backdrop_ceil :: proc(v: f32) -> f32 {
	return math.ceil(v / BACKDROP_PIXEL) * BACKDROP_PIXEL
}

// backdrop_rect puts a rectangle on the lattice, keeping at least one art pixel in each axis:
// one art pixel is the smallest thing the backdrop is allowed to say, and a wave crest that
// rounds away to zero width is a hole in the water rather than a finer detail.
backdrop_rect :: proc(rect: rl.Rectangle) -> rl.Rectangle {
	x, y := backdrop_snap(rect.x), backdrop_snap(rect.y)
	return rl.Rectangle {
		x = x,
		y = y,
		width = max(backdrop_ceil(rect.x + rect.width) - x, BACKDROP_PIXEL),
		height = max(backdrop_ceil(rect.y + rect.height) - y, BACKDROP_PIXEL),
	}
}

// backdrop_block is the only way a backdrop mark reaches the screen: a rectangle snapped to the
// lattice first. Every cloud step, island block, wave, glitter fleck and scrap of foam goes
// through it.
backdrop_block :: proc(rect: rl.Rectangle, colour: rl.Color) {
	rl.DrawRectangleRec(backdrop_rect(rect), colour)
}

// backdrop_stop is the colour of ramp stop `i` of `steps` between two roster swatches. A grade
// paints these and nothing between them, which is what "limited ramps per hue" means in code:
// `steps + 1` distinct colours down a whole sky, not one per screen row.
backdrop_stop :: proc(from, to: rl.Color, i, steps: int) -> rl.Color {
	return colour_mix(from, to, f32(clamp(i, 0, steps)) / f32(steps))
}

// backdrop_grade paints a vertical grade the only way the house style allows one: `steps` flat
// stops between two swatches, the crossings between stops dissolved by the ordered dither.
//
// This stands in for rl.DrawRectangleGradientV, which interpolates per *screen* pixel and so
// paints a smooth vector sky behind pixel-art clouds however carefully the clouds are placed.
backdrop_grade :: proc(x, y, width, height: f32, from, to: rl.Color, steps: int) {
	left, right := backdrop_snap(x), backdrop_ceil(x + width)
	top, bottom := backdrop_snap(y), backdrop_ceil(y + height)
	span := max(bottom - top, BACKDROP_PIXEL)

	row := 0
	for py := top; py < bottom; py += BACKDROP_PIXEL {
		// The row's place along the ramp, taken at its centre: a whole art pixel is one colour,
		// so there is no sub-pixel position for it to be taken at.
		place := (py + BACKDROP_PIXEL * 0.5 - top) / span * f32(steps)
		stop := clamp(int(place), 0, steps - 1)
		fraction := clamp(place - f32(stop), 0, 1)

		rl.DrawRectangleRec({left, py, right - left, BACKDROP_PIXEL}, backdrop_stop(from, to, stop, steps))

		// The crossing, laid in runs. The threshold pattern repeats every four art pixels, so
		// neighbouring cells that both cross are drawn as one rectangle rather than as two that
		// share an edge — on a full-frame sky that is the difference between thousands of draw
		// calls and tens of thousands.
		next := backdrop_stop(from, to, stop + 1, steps)
		run := left
		running := false
		col := 0
		for px := left; px < right; px += BACKDROP_PIXEL {
			on := (BACKDROP_DITHER[row % 4][col % 4] + 0.5) / 16 < fraction
			if on && !running {
				run, running = px, true
			} else if !on && running {
				rl.DrawRectangleRec({run, py, px - run, BACKDROP_PIXEL}, next)
				running = false
			}
			col += 1
		}
		if running {
			rl.DrawRectangleRec({run, py, right - run, BACKDROP_PIXEL}, next)
		}
		row += 1
	}
}

// backdrop_disc is a circle with no curve in it: filled row by row on the lattice, so it steps
// where everything around it steps. rl.DrawCircleV draws a smooth-edged polygon fan, and it is
// the one shape in the sky that cannot be put right by snapping its arguments.
backdrop_disc :: proc(centre: rl.Vector2, radius: f32, colour: rl.Color) {
	cx, cy := backdrop_snap(centre.x), backdrop_snap(centre.y)
	r := backdrop_ceil(radius)
	for py := cy - r; py < cy + r; py += BACKDROP_PIXEL {
		dy := py + BACKDROP_PIXEL * 0.5 - cy
		half := backdrop_ceil(math.sqrt(max(r * r - dy * dy, 0)))
		if half <= 0 {
			continue
		}
		rl.DrawRectangleRec({cx - half, py, half * 2, BACKDROP_PIXEL}, colour)
	}
}
