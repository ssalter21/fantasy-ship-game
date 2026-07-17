package main

import rl "vendor:raylib"

// The chrome palette from docs/ui/style-guide.md — the colours drawn on top of the
// world (panels, buttons, borders, text, states), as opposed to zone_tint's world
// colours in view.odin. The guide's table is the source of truth; these are it.
COLOUR_GROUND :: rl.Color{8, 17, 39, 255} // the dominant field; replaces RAYWHITE as the canvas
COLOUR_GROUND_MID :: rl.Color{10, 28, 48, 255} // one step up from ground; large calm areas
COLOUR_VIGNETTE :: rl.Color{5, 11, 24, 255} // darkest tone; frames the screen
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
