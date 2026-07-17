package main

import rl "vendor:raylib"

// The palette from docs/ui/style-guide.md. The guide's table is the source of truth;
// these are it.
//
// There is one palette, and it is a depth ramp: hue falls and value rises as water
// shallows, measured off menu-ui-mock.png's chart (H222 V0.15 -> H212 V0.19 ->
// H200 V0.25) and corroborated at its deep end by ship-night (H230) and ship-battle
// (H234) and at its bright end by wave (H186). #280 split this into a "chrome"
// palette and a "world" palette from two different sources; #294 found that was the
// disunity rather than the cure, because the two sources sit in hue families 31.8°
// apart. The three ramp stops below are also zone_tint's three zones (view.odin) —
// the ground the chrome sits on and the deepest water are one colour, not two.
COLOUR_DEEP :: rl.Color{8, 17, 39, 255} // ramp stop 1 (H222): the dominant field, and zone Deep
COLOUR_MID :: rl.Color{10, 28, 48, 255} // ramp stop 2 (H212): open water
COLOUR_SHALLOW :: rl.Color{14, 46, 63, 255} // ramp stop 3 (H200): where water meets land
COLOUR_VIGNETTE :: rl.Color{5, 11, 24, 255} // below the ramp; frames the screen

// COLOUR_GROUND / COLOUR_GROUND_MID were the chrome names for the ramp's first two
// stops, kept as aliases so the call sites that read as "ground" still say so.
COLOUR_GROUND :: COLOUR_DEEP
COLOUR_GROUND_MID :: COLOUR_MID
COLOUR_AMBER :: rl.Color{247, 167, 43, 255} // reserved for "the thing you can act on right now"
COLOUR_INK :: rl.Color{8, 18, 43, 255} // the only text colour that goes on amber
COLOUR_STEEL :: rl.Color{138, 169, 214, 255} // unselected controls: border and label
COLOUR_CREAM :: rl.Color{231, 210, 163, 255} // titles and headings only
COLOUR_CYAN :: rl.Color{111, 224, 236, 255} // subtitles and taglines; the eye's rest point
COLOUR_CYAN_DIM :: rl.Color{87, 181, 195, 255} // hints and secondary help text
COLOUR_BLUE_RECESSIVE :: rl.Color{58, 90, 130, 255} // present but never read first

// The size scale, whole. The guide measures Pixelify Sans as 2% antialiased at 20px
// and 78% at 10px: there is no clean size below 20px, so hierarchy is carried by
// colour rather than by size.
UI_TITLE_SIZE :: 40
UI_BODY_SIZE :: 20

// PIXELIFY_SANS_TTF is the UI typeface, compiled into the binary rather than shipped
// beside it: ADR-0009 (playtest distribution) commits to a self-contained game.exe
// proven against a real tester's machine, which a sidecar font file breaks.
// SIL OFL 1.1 — see assets/fonts/OFL.txt.
PIXELIFY_SANS_TTF :: #load("../../assets/fonts/PixelifySans.ttf")

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
// A nil codepoint list bakes the default set (ASCII 32-126). U+2014, which the guide
// notes retires view.odin's em-dash workaround, is outside that set and would need an
// explicit list; nothing here draws one yet.
ui_font_bake :: proc(size: i32) -> rl.Font {
	font := rl.LoadFontFromMemory(
		".ttf",
		raw_data(PIXELIFY_SANS_TTF),
		i32(len(PIXELIFY_SANS_TTF)),
		size,
		nil,
		0,
	)
	rl.SetTextureFilter(font.texture, .POINT)
	return font
}
