package presentation

import "core:slice"
import "core:testing"
import rl "vendor:raylib"

// The widget layer's contract. Drawing needs a window, so what is testable is the half that
// decides *what* is drawn — the axes resolving to tones, the scale, and the placement. That
// is also the half a screen can get wrong silently.

// The roster is law (docs/ui/style-guide.md). A widget resolving an emphasis to a colour that
// is not on it would be a way for every call site to leave the palette at once — which is the
// opposite of what baking the rules into the widgets is for.
@(private = "file")
ROSTER := [?]rl.Color {
	COLOUR_SEA,
	COLOUR_SEA_BRIGHT,
	COLOUR_SEA_SHALLOW,
	COLOUR_SEA_DEEP,
	COLOUR_FOAM,
	COLOUR_SKY_HIGH,
	COLOUR_SKY,
	COLOUR_HAZE,
	COLOUR_CLOUD,
	COLOUR_CLOUD_SHADOW,
	COLOUR_PARCHMENT,
	COLOUR_SAND,
	COLOUR_CLIFF,
	COLOUR_ROCK,
	COLOUR_TRUNK,
	COLOUR_GREEN_HIGHLIGHT,
	COLOUR_GREEN_LIGHT,
	COLOUR_GREEN,
	COLOUR_GREEN_DEEP,
	COLOUR_CORAL,
	COLOUR_INK_PRIMARY,
	COLOUR_INK_MUTED,
	COLOUR_CREAM_BRIGHT,
}

// A shade is colour_shade of a swatch — one factor over every channel, which is how the game
// gets a lit face and a shadowed one out of one swatch rather than out of two that have to be
// kept in step by hand.
//
// A channel may sit one off: the factor is recovered from a single channel, and the other two
// carry their own rounding. Two would let a colour drift far enough to be a different swatch.
// The same tolerance scripts/check-mock.py holds mockups to.
@(private = "file")
SHADE_TOLERANCE :: 1

@(private = "file")
on_the_roster :: proc(colour: rl.Color) -> bool {
	near :: proc(a, b: u8) -> bool {
		return abs(int(a) - int(b)) <= SHADE_TOLERANCE
	}
	for swatch in ROSTER {
		if swatch == colour {
			return true
		}
		// Recover the factor from the largest channel: the smallest carries the most rounding
		// error, and a zero channel carries no information at all.
		high := max(swatch.r, swatch.g, swatch.b)
		if high == 0 {
			continue
		}
		high_value := colour.r
		if swatch.g == high {
			high_value = colour.g
		} else if swatch.b == high {
			high_value = colour.b
		}
		factor := f32(high_value) / f32(high)
		if factor <= 0 || factor > 2 {
			continue
		}
		shaded := colour_shade(swatch, factor)
		if near(shaded.r, colour.r) && near(shaded.g, colour.g) && near(shaded.b, colour.b) {
			return true
		}
	}
	return false
}

@(test)
every_ink_a_widget_can_reach_is_on_the_roster :: proc(t: ^testing.T) {
	for ground in Ui_Ground {
		for emphasis in Ui_Emphasis {
			ink := ui_ink(ground, emphasis)
			testing.expectf(
				t,
				on_the_roster(ink),
				"%v on %v resolves to %v, which is not a roster swatch or a shade of one",
				emphasis,
				ground,
				ink,
			)
		}
	}
}

// Ink has to separate from what it is on, or the widget is drawing invisible text. The two
// grounds are opposite in value, which is why the axis exists at all.
@(test)
ink_reads_against_the_ground_it_names :: proc(t: ^testing.T) {
	luminance :: proc(c: rl.Color) -> f32 {
		return 0.299 * f32(c.r) + 0.587 * f32(c.g) + 0.114 * f32(c.b)
	}
	for emphasis in Ui_Emphasis {
		on_paper := luminance(ui_ink(.Parchment, emphasis))
		on_water := luminance(ui_ink(.Water, emphasis))
		testing.expectf(
			t,
			on_paper < luminance(COLOUR_PARCHMENT),
			"%v on parchment is lighter than the parchment under it",
			emphasis,
		)
		testing.expectf(t, on_water > on_paper, "%v over water should be the lighter of the two", emphasis)
	}
}

// Emphasis is a rank, so it has to actually rank: each step reads less loudly than the one
// before it. A pair that resolved to the same tone would be an axis with a value that does
// nothing.
@(test)
emphasis_ranks_rather_than_merely_differing :: proc(t: ^testing.T) {
	for ground in Ui_Ground {
		seen := make([dynamic]rl.Color, 0, len(Ui_Emphasis))
		defer delete(seen)
		for emphasis in Ui_Emphasis {
			ink := ui_ink(ground, emphasis)
			// Unavailable is allowed to share with Secondary: a thing you cannot take is not a
			// fourth loudness, it is a state, and its dimming is carried by the surface tint.
			if emphasis != .Unavailable {
				testing.expectf(t, !slice.contains(seen[:], ink), "%v on %v is not its own tone", emphasis, ground)
			}
			append(&seen, ink)
		}
	}
}

// A surface dims by tone rather than by alpha: over a bright sea, translucency costs a
// surface its own ground and the water reads through it as a stain (ADR-0032).
@(test)
an_unavailable_surface_dims_by_tone_not_alpha :: proc(t: ^testing.T) {
	for emphasis in Ui_Emphasis {
		tint := ui_surface_tint(emphasis)
		testing.expectf(t, tint.a == 255, "%v tints at alpha %d rather than by tone", emphasis, tint.a)
	}
	full := ui_surface_tint(.Primary)
	dim := ui_surface_tint(.Unavailable)
	testing.expect(t, dim.r < full.r && dim.g < full.g && dim.b < full.b, "unavailable is darker than primary")
}

// The scale has to be a scale: strictly increasing, starting at nothing. A step that did not
// increase would give two names to one gap and the rhythm would stop being nameable.
@(test)
the_spacing_scale_is_a_scale :: proc(t: ^testing.T) {
	testing.expect_value(t, ui_space(.None), 0)
	previous := f32(-1)
	for space in Ui_Space {
		value := ui_space(space)
		testing.expectf(t, value > previous, "%v (%.0f) does not step past the one before it", space, previous)
		testing.expectf(t, value == f32(int(value)), "%v is %.1f, not a whole pixel", space, value)
		previous = value
	}
}

@(test)
an_inset_takes_the_space_off_every_side :: proc(t: ^testing.T) {
	inset := ui_inset({x = 100, y = 50, width = 200, height = 80}, .Base)
	pad := ui_space(.Base)
	testing.expect_value(t, inset.x, 100 + pad)
	testing.expect_value(t, inset.y, 50 + pad)
	testing.expect_value(t, inset.width, 200 - 2 * pad)
	testing.expect_value(t, inset.height, 80 - 2 * pad)

	// A rect too small to inset collapses rather than inverting: a negative width draws
	// nothing in raylib but hit-tests as an unbounded region.
	tiny := ui_inset({x = 0, y = 0, width = 4, height = 4}, .Vast)
	testing.expect(t, tiny.width >= 0 && tiny.height >= 0, "an over-inset rect has no negative size")
}

// The type scale is reachable only through a level, so a screen cannot ask for an atlas
// nobody baked (ui.odin bakes exactly these sizes).
@(test)
every_level_is_a_size_that_was_actually_baked :: proc(t: ^testing.T) {
	baked := [?]f32{UI_TITLE_SIZE, UI_BODY_SIZE}
	for level in Ui_Level {
		testing.expectf(
			t,
			slice.contains(baked[:], UI_LEVEL_SIZE[level]),
			"%v is %.0fpx, which no atlas was baked at",
			level,
			UI_LEVEL_SIZE[level],
		)
	}
}

@(test)
text_anchors_where_it_is_told_and_on_whole_pixels :: proc(t: ^testing.T) {
	box := rl.Rectangle{x = 100, y = 40, width = 200, height = 40}
	size := rl.Vector2{50, 16}

	left := ui_text_origin(box, size, .Left)
	centre := ui_text_origin(box, size, .Centre)
	right := ui_text_origin(box, size, .Right)

	testing.expect_value(t, left.x, 100)
	testing.expect_value(t, centre.x, 175)
	testing.expect_value(t, right.x, 250)
	// Vertically centred in the box, whatever the anchor.
	for origin in ([?]rl.Vector2{left, centre, right}) {
		testing.expect_value(t, origin.y, 52)
		testing.expect(t, origin.x == f32(int(origin.x)), "a glyph starts on a whole pixel")
	}
}

// An odd remainder still lands on a whole pixel rather than a half — the case that softens a
// POINT-filtered face without ever looking obviously wrong.
@(test)
a_centred_string_with_an_odd_remainder_still_lands_whole :: proc(t: ^testing.T) {
	origin := ui_text_origin({x = 0, y = 0, width = 101, height = 41}, {50, 16}, .Centre)
	testing.expect_value(t, origin.x, 26)
	testing.expect_value(t, origin.y, 13)
}

// A divider is whichever of its two dimensions is the long one, so a call site names a run
// rather than naming an orientation it could get wrong.
@(test)
a_divider_weighs_what_it_is_told :: proc(t: ^testing.T) {
	testing.expect(t, UI_WEIGHT_PX[.Rule] > UI_WEIGHT_PX[.Hair], "a rule is heavier than a hair")
	for weight in Ui_Weight {
		testing.expect(t, UI_WEIGHT_PX[weight] >= 1, "a divider at least a pixel thick is a divider")
	}
}

// Every widget is safe to call with no window. That is not a nicety: a raylib draw call with
// no window touches an uninitialised batch and takes the process down, so without the guard a
// screen's own test could not call the draw proc it is testing at all.
@(test)
the_widgets_are_inert_without_an_atlas :: proc(t: ^testing.T) {
	testing.expect(t, !ui_drawable(), "there is no window under `odin test`")
	testing.expect_value(t, ui_font_body.texture.id, 0)
	testing.expect_value(t, ui_text_size("Long Nines", .Body), rl.Vector2{})

	rect := rl.Rectangle{10, 10, 200, 60}
	ui_panel(rect, .Raised)
	ui_card(rect, .Unavailable, .Floating)
	ui_button(rect, "Leave", .Rest)
	ui_heading(rect, "Market", .Title, .Parchment)
	ui_divider(rect, .Rule, .Parchment)
	ui_icon({10, 10, 14, 14}, .Crate, .Parchment)
	ui_text(rect, "18", .Body, .Water, .Muted, .Right)
}

// Nothing is migrated in this ticket, so the Shop still draws from its own constants and the
// shot manifest does not move. The widgets land beside the hand-rolled draws, not over them.
@(test)
no_screen_has_been_migrated_yet :: proc(t: ^testing.T) {
	testing.expect_value(t, offer_shop_layout, OFFER_SHOP_LAYOUT)
}
