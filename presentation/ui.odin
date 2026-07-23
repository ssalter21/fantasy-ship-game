#+private
package presentation

import rl "vendor:raylib"

// The palette from docs/ui/style-guide.md. The guide's table is the source of truth;
// these are it.
//
// There is one palette, and it is a depth ramp: hue falls and value rises as water
// shallows, measured off menu-ui-mock.png's chart (H222 V0.15 -> H212 V0.19 ->
// H200 V0.25) and corroborated at its deep end by ship-night (H230) and ship-battle
// (H234) and at its bright end by wave (H186). The ground the chrome sits on and the
// deepest water are one colour, not two.
COLOUR_DEEP :: rl.Color{8, 17, 39, 255} // ramp stop 1 (H222): the dominant field, and zone Deep
COLOUR_MID :: rl.Color{10, 28, 48, 255} // ramp stop 2 (H212): open water
COLOUR_SHALLOW :: rl.Color{14, 46, 63, 255} // ramp stop 3 (H200): where water meets land
COLOUR_VIGNETTE :: rl.Color{5, 11, 24, 255} // below the ramp; frames the screen

// NO_MOUSE is a pointer position no widget can be under: every hover test is a
// containment check against a real rect, so an off-screen point reads as "nothing
// hovered". Capture has no mouse and must photograph each screen at rest, and the
// draw-only call sites (a route preview, a fight frame) have no pointer to pass.
NO_MOUSE :: rl.Vector2{-1, -1}

// COLOUR_GROUND is the chrome name for the ramp's first stop, so a call site that reads
// as "ground" still says so.
COLOUR_GROUND :: COLOUR_DEEP
COLOUR_AMBER :: rl.Color{247, 167, 43, 255} // reserved for "the thing you can act on right now"
COLOUR_INK :: rl.Color{8, 18, 43, 255} // the only text colour that goes on amber
COLOUR_STEEL :: rl.Color{138, 169, 214, 255} // unselected controls: border and label
COLOUR_CREAM :: rl.Color{231, 210, 163, 255} // titles and headings only
COLOUR_CYAN :: rl.Color{111, 224, 236, 255} // subtitles and taglines; the eye's rest point
COLOUR_CYAN_DIM :: rl.Color{87, 181, 195, 255} // hints and secondary help text
COLOUR_BLUE_RECESSIVE :: rl.Color{58, 90, 130, 255} // present but never read first

// The guide's bright roster — the sea, the sky it sits under, and the warm neutrals of land
// and timber. The navy ramp above is the superseded direction the other screens still draw
// from; these are the swatches the ship screen paints its galleon and its water from, and
// every screen re-coloured after it will take them too.
//
// The names track the guide's roster rows, with one forced rename: the roster's "Shallow" is
// COLOUR_SEA_SHALLOW here, because COLOUR_SHALLOW is already the navy ramp's third stop.
COLOUR_SEA :: rl.Color{31, 169, 208, 255} // the world backdrop, and the sea itself
COLOUR_SEA_BRIGHT :: rl.Color{44, 195, 222, 255} // near-surface water, highlights
COLOUR_SEA_SHALLOW :: rl.Color{99, 226, 236, 255} // brightest cool; where water meets land
COLOUR_SEA_DEEP :: rl.Color{23, 134, 188, 255} // distance, and interactive borders on parchment
COLOUR_FOAM :: rl.Color{242, 251, 251, 255} // whitecaps and dividers; the brightest thing allowed

COLOUR_SKY_HIGH :: rl.Color{63, 121, 192, 255}
COLOUR_SKY :: rl.Color{90, 147, 210, 255}
COLOUR_HAZE :: rl.Color{143, 188, 232, 255} // the band of sky just above the horizon
COLOUR_CLOUD :: rl.Color{238, 241, 248, 255}
COLOUR_CLOUD_SHADOW :: rl.Color{183, 188, 224, 255}

COLOUR_PARCHMENT :: rl.Color{235, 217, 166, 255} // the ground for text: panels and cards
COLOUR_SAND :: rl.Color{210, 169, 104, 255} // panel shade, dividers, gilding
COLOUR_CLIFF :: rl.Color{185, 138, 80, 255} // deeper sand; borders, and weather-deck timber
COLOUR_ROCK :: rl.Color{126, 92, 58, 255} // the darkest warm; hull planking
COLOUR_TRUNK :: rl.Color{135, 95, 56, 255} // masts, yards, spars

COLOUR_CORAL :: rl.Color{225, 85, 43, 255} // scarce by law: danger and damage

COLOUR_INK_PRIMARY :: rl.Color{18, 51, 63, 255} // titles and body on parchment; deep teal, not black
COLOUR_INK_MUTED :: rl.Color{76, 115, 133, 255} // secondary and help text on parchment

// colour_shade multiplies a colour's channels by `factor`, clamped to the byte range. A lit
// face and a shadowed one are then the same roster swatch under different light, rather than
// two swatches that have to be kept in step by hand.
colour_shade :: proc(colour: rl.Color, factor: f32) -> rl.Color {
	channel :: proc(value: u8, factor: f32) -> u8 {
		return u8(clamp(f32(value) * factor, 0, 255))
	}
	return rl.Color{channel(colour.r, factor), channel(colour.g, factor), channel(colour.b, factor), colour.a}
}

// The size scale, whole. Pixel Operator is a native-16px pixel face: measured 0.0%
// antialiased at 16 and 32 (both integer multiples of its pixel em) and mush off that
// grid — 86% at 20px, 40% at 40px. The scale is therefore 32/16, the two crisp sizes
// nearest the old 40/20. Hierarchy is still carried by colour, not size: that is the
// house style, no longer a workaround for a face with no clean small size.
UI_TITLE_SIZE :: 32
UI_BODY_SIZE :: 16

// PIXEL_OPERATOR_TTF is the UI typeface, compiled into the binary rather than shipped
// beside it: ADR-0009 (playtest distribution) commits to a self-contained game.exe
// proven against a real tester's machine, which a sidecar font file breaks.
// CC0 1.0 (public domain) — see assets/fonts/PixelOperator-LICENSE.txt.
PIXEL_OPERATOR_TTF :: #load("../assets/fonts/PixelOperator.ttf")

// ui_font_title and ui_font_body are the same face baked at the scale's two sizes.
// One rl.Font is one glyph atlas rasterized at one size, so a size is a font here:
// drawing 20px text from the 40px atlas resamples it and gives up the pixel-exactness
// that picking a pixel face was for.
ui_font_title: rl.Font
ui_font_body: rl.Font

// ui_fonts_load bakes both atlases. Must run after InitWindow (the atlas is a GPU
// texture) and before any draw; ui_fonts_unload pairs with it.
ui_fonts_load :: proc() {
	ui_font_title = ui_font_bake(UI_TITLE_SIZE)
	ui_font_body = ui_font_bake(UI_BODY_SIZE)
}

ui_fonts_unload :: proc() {
	rl.UnloadFont(ui_font_title)
	rl.UnloadFont(ui_font_body)
}

// ui_font_bake rasterizes the embedded face at one size. The POINT filter is what
// keeps a pixel font pixel-crisp — raylib's default bilinear filter softens the atlas
// on upload and undoes the measurement the size scale rests on.
//
// The codepoint list is explicit rather than nil: LoadFontFromMemory's default set is
// ASCII 32-126, which omits the middot "·" (U+00B7) and em-dash "—" (U+2014) — both of
// which the face carries and the guide notes need an explicit list, not just the font, to
// reach the atlas. The Build surface's ledger and item specs separate with "·", so a nil
// list would render them as the missing-glyph box. (The projection arrow the Shop's cargo
// preview reads, #312, is plain ASCII "->": Pixel Operator carries no U+2192 either.)
UI_FONT_EXTRA_CODEPOINTS :: [?]rune{'·', '—'}

ui_font_bake :: proc(size: i32) -> rl.Font {
	ASCII_LO :: 32
	ASCII_HI :: 126
	extra := UI_FONT_EXTRA_CODEPOINTS
	codepoints: [(ASCII_HI - ASCII_LO + 1) + len(extra)]rune
	for i in 0 ..< (ASCII_HI - ASCII_LO + 1) {
		codepoints[i] = rune(ASCII_LO + i)
	}
	for c, i in extra {
		codepoints[(ASCII_HI - ASCII_LO + 1) + i] = c
	}

	font := rl.LoadFontFromMemory(
		".ttf",
		raw_data(PIXEL_OPERATOR_TTF),
		i32(len(PIXEL_OPERATOR_TTF)),
		size,
		raw_data(codepoints[:]),
		i32(len(codepoints)),
	)
	rl.SetTextureFilter(font.texture, .POINT)
	return font
}
