package forge

import "core:c"
import "core:fmt"
import ship "../core/ship"
import rl "vendor:raylib"

// The Forge's visual language, which is **not the game's**.
//
// docs/ui/style-guide.md governs the shipped game and **none of it applies here**: those
// rules exist to make the game feel like a game, and a content tool that felt like a game
// would be worse at its job. What this file authors instead is the register of an IDE or
// a spreadsheet inspector: a neutral high-contrast surface, one accent, semantic colour
// and nothing decorative, and a tight spacing grid that puts rows of numbers next to each
// other rather than giving each of them room to breathe.
//
// The separate forge/ package is what makes that a fact rather than a promise: nothing
// here can leak into a game screen, because presentation/ cannot see it.

// The spacing grid. Every rectangle in the tool is laid out in multiples of these, so
// density is a property of the grid rather than of each screen's judgement.
//
// The grid is sized off FORGE_TEXT_SIZE rather than the other way round: the tool is read
// for hours at a stretch, so the type is set at a size a person can read without leaning
// in, and the rows are then given whatever room that costs. Density is still the point —
// these are the tightest rows the type fits in, not roomy ones.
FORGE_ROW :: 24
FORGE_PAD :: 10
FORGE_GAP :: 6
FORGE_LABEL_W :: 150
FORGE_TEXT_SIZE :: 16
FORGE_HEADER :: 34
FORGE_STATUS :: 30

// FORGE_FIELD_H is a control's height within a row: the row's pitch, less the hairline
// that keeps two stacked controls from sharing a border.
FORGE_FIELD_H :: FORGE_ROW - 2

// FORGE_TEXT_DY and FORGE_CHECK_DY centre a line of text and a checkbox's box inside that
// height. Every caption in the tool is offset by one of these rather than by a literal, so
// changing the type size above re-centres the whole tool instead of shearing it.
FORGE_TEXT_DY :: (FORGE_FIELD_H - FORGE_TEXT_SIZE) / 2
FORGE_CHECK :: 15
FORGE_CHECK_DY :: (FORGE_FIELD_H - FORGE_CHECK) / 2

// The two field widths the forms are built from: FORGE_VALUE_W holds a bounded integer and
// its spin buttons, FORGE_ENUM_W holds the longest member name of a closed enum plus the
// combo box's position indicator. Naming them is what keeps a form's fields in one column
// down the whole tool instead of each pane guessing a number.
FORGE_VALUE_W :: 96
FORGE_ENUM_W :: 150

// Colour is semantic only: what passed, what is at fault, what wants attention, and what
// is derived and therefore unauthorable. There is no fifth meaning and no decorative use.
FORGE_SURFACE :: u32(0x14161AFF)
FORGE_PANEL :: u32(0x1B1E24FF)
FORGE_PANEL_ALT :: u32(0x22262DFF)
FORGE_LINE :: u32(0x2E333BFF)
FORGE_TEXT :: u32(0xC9D1D9FF)
FORGE_TEXT_DIM :: u32(0x8A939EFF)
FORGE_ACCENT :: u32(0x4C9AFFFF)
FORGE_PASS :: u32(0x3FB950FF)
FORGE_FAULT :: u32(0xF85149FF)
FORGE_WARN :: u32(0xD29922FF)
FORGE_DERIVED :: u32(0x6E7681FF)

// gui_color reinterprets one of the palette entries above as the packed integer raygui
// stores a colour property in; the top bit is a colour channel, not a sign.
gui_color :: proc(hex: u32) -> c.int {
	return transmute(c.int)hex
}

color_of :: proc(hex: u32) -> rl.Color {
	return rl.Color{u8(hex >> 24), u8(hex >> 16), u8(hex >> 8), u8(hex)}
}

// Typography. The tool wears the two faces a developer's own tools wear: an anti-aliased
// proportional face for prose and captions, and a true monospace for every number column
// and for the Odin it emits. raylib's built-in face is a 10px bitmap and is legible at
// exactly one size, which is what made the tool small and hard to read.
//
// Both faces are loaded **from the system** rather than embedded. ADR-0009's
// self-contained-exe rule is about the *game*, which goes to a playtester's machine; the
// Forge never leaves this repo, and the faces worth wearing here are ones the repo may not
// redistribute. The candidate lists are tried in order and raylib's default is the last
// resort, so a machine carrying none of them gets a working tool rather than no tool.
@(rodata)
FORGE_UI_FACES := [?]cstring {
	"C:/Windows/Fonts/segoeui.ttf",
	"C:/Windows/Fonts/calibri.ttf",
	"C:/Windows/Fonts/tahoma.ttf",
	"C:/Windows/Fonts/arial.ttf",
}

@(rodata)
FORGE_MONO_FACES := [?]cstring {
	"C:/Windows/Fonts/consola.ttf",
	"C:/Windows/Fonts/lucon.ttf",
	"C:/Windows/Fonts/cour.ttf",
}

// forge_font is prose — a caption, a name, a reason. forge_mono is every number column and
// the emitted source. One rl.Font is one atlas at one size, and the tool has one type size,
// so these are two fonts rather than two sizes of one.
forge_font: rl.Font
forge_mono: rl.Font

// font_load bakes both atlases. Must run after InitWindow — an atlas is a GPU texture —
// and before any draw; font_unload pairs with it.
font_load :: proc() {
	forge_font = font_first(FORGE_UI_FACES[:])
	forge_mono = font_first(FORGE_MONO_FACES[:])
}

// font_unload releases both. raylib's UnloadFont declines to free the default face, so a
// fallback that never loaded a file is safe to pass here.
font_unload :: proc() {
	rl.UnloadFont(forge_font)
	rl.UnloadFont(forge_mono)
}

// font_first bakes the first candidate that loads. The test is against the default face
// rather than IsFontValid: LoadFontEx *succeeds* with the default font when a path will not
// load, so a valid font is not evidence the requested one was found.
@(private = "file")
font_first :: proc(faces: []cstring) -> rl.Font {
	for face in faces {
		if !rl.FileExists(face) {
			continue
		}
		font := rl.LoadFontEx(face, FORGE_TEXT_SIZE, nil, 0)
		if font.texture.id == rl.GetFontDefault().texture.id {
			continue
		}
		// The atlas is only ever drawn at the size it was baked at, so point sampling is
		// exact here and bilinear would soften glyphs that already land on the pixel grid.
		rl.SetTextureFilter(font.texture, .POINT)
		return font
	}
	return rl.GetFontDefault()
}

// FORGE_TEXT_SPACING is the gap draw_text adds between glyphs. A real typeface carries its
// own sidebearings, so the answer is none — the extra pixel raylib's bitmap face needed to
// stay legible now only loosens words.
FORGE_TEXT_SPACING :: f32(0)

// mono_advance is the fixed per-glyph step the number columns are drawn on, measured off
// the font at startup rather than assumed. Numbers are drawn glyph by glyph at this step
// (draw_mono), which is what lines a column's decimal points up exactly — a budget panel
// is an equation and has to read like one.
mono_advance: f32

// glyph_width is every printable ASCII glyph's own advance, measured once. draw_mono
// centres each glyph inside the fixed cell using it, so a column stays aligned without
// narrow glyphs like '.' and '-' sitting hard against the left of their cell. A genuine
// monospace face makes that centring a no-op; the default-face fallback still needs it.
glyph_width: [128]f32

// style_init authors the raygui style sheet. raygui ships a look of its own and the game
// ships another; the tool wears neither, so every property a control reads is set here.
style_init :: proc() {
	for code in 32 ..< 127 {
		glyph := [2]u8{u8(code), 0}
		glyph_width[code] = rl.MeasureTextEx(forge_mono, cstring(&glyph[0]), FORGE_TEXT_SIZE, 0).x
	}
	mono_advance = glyph_width['0'] + 1

	// raygui draws every control's caption itself, so it is handed the same prose face the
	// tool draws with; a control lettered differently from the label beside it would read as
	// two tools stitched together.
	rl.GuiSetFont(forge_font)
	rl.GuiSetStyle(.DEFAULT, c.int(rl.GuiDefaultProperty.TEXT_SIZE), FORGE_TEXT_SIZE)
	rl.GuiSetStyle(.DEFAULT, c.int(rl.GuiDefaultProperty.TEXT_SPACING), c.int(FORGE_TEXT_SPACING))
	rl.GuiSetStyle(.DEFAULT, c.int(rl.GuiDefaultProperty.BACKGROUND_COLOR), gui_color(FORGE_SURFACE))
	rl.GuiSetStyle(.DEFAULT, c.int(rl.GuiDefaultProperty.LINE_COLOR), gui_color(FORGE_LINE))
	rl.GuiSetStyle(.DEFAULT, c.int(rl.GuiControlProperty.BORDER_WIDTH), 1)
	rl.GuiSetStyle(.DEFAULT, c.int(rl.GuiControlProperty.TEXT_PADDING), 6)
	rl.GuiSetStyle(.DEFAULT, c.int(rl.GuiControlProperty.TEXT_ALIGNMENT), c.int(rl.GuiTextAlignment.TEXT_ALIGN_LEFT))

	style_control(.DEFAULT, FORGE_LINE, FORGE_PANEL, FORGE_TEXT)
	style_control(.BUTTON, FORGE_LINE, FORGE_PANEL_ALT, FORGE_TEXT)
	style_control(.DROPDOWNBOX, FORGE_LINE, FORGE_PANEL_ALT, FORGE_TEXT)
	style_control(.VALUEBOX, FORGE_LINE, FORGE_PANEL, FORGE_TEXT)
	style_control(.SPINNER, FORGE_LINE, FORGE_PANEL, FORGE_TEXT)
	style_control(.TEXTBOX, FORGE_LINE, FORGE_PANEL, FORGE_TEXT)
	style_control(.CHECKBOX, FORGE_LINE, FORGE_PANEL, FORGE_TEXT)
	style_control(.LISTVIEW, FORGE_LINE, FORGE_PANEL, FORGE_TEXT)
	style_control(.SLIDER, FORGE_LINE, FORGE_PANEL_ALT, FORGE_TEXT)
	style_control(.TOGGLE, FORGE_LINE, FORGE_PANEL_ALT, FORGE_TEXT)

	// Labels carry no chrome of their own: a form's structure comes from its grid, not
	// from a box drawn around every caption.
	rl.GuiSetStyle(.LABEL, c.int(rl.GuiControlProperty.TEXT_COLOR_NORMAL), gui_color(FORGE_TEXT_DIM))
	rl.GuiSetStyle(.LABEL, c.int(rl.GuiControlProperty.TEXT_COLOR_DISABLED), gui_color(FORGE_DERIVED))

	// Density: raygui's stock control heights and paddings are sized for a settings
	// dialog. These are sized for a table.
	rl.GuiSetStyle(.LISTVIEW, c.int(rl.GuiListViewProperty.LIST_ITEMS_HEIGHT), FORGE_ROW)
	rl.GuiSetStyle(.LISTVIEW, c.int(rl.GuiListViewProperty.LIST_ITEMS_SPACING), 0)
	rl.GuiSetStyle(.LISTVIEW, c.int(rl.GuiListViewProperty.SCROLLBAR_WIDTH), 12)
	rl.GuiSetStyle(.CHECKBOX, c.int(rl.GuiCheckBoxProperty.CHECK_PADDING), 3)
	// A checkbox's caption belongs after its box, which raygui spells as the text being
	// right-aligned relative to the control.
	rl.GuiSetStyle(.CHECKBOX, c.int(rl.GuiControlProperty.TEXT_ALIGNMENT), c.int(rl.GuiTextAlignment.TEXT_ALIGN_RIGHT))
	rl.GuiSetStyle(.SPINNER, c.int(rl.GuiSpinnerProperty.SPIN_BUTTON_WIDTH), 20)
	rl.GuiSetStyle(.DROPDOWNBOX, c.int(rl.GuiDropdownBoxProperty.ARROW_PADDING), 10)
	// Wide enough for the position indicator on the longest list a combo box carries, which
	// is the whole item roster.
	rl.GuiSetStyle(.COMBOBOX, c.int(rl.GuiComboBoxProperty.COMBO_BUTTON_WIDTH), 48)
}

// style_control sets one control's nine state colours from three: focused lifts the
// border to the accent, pressed lifts the fill, and disabled drops both to the derived
// grey — so a locked field reads as locked everywhere without each call site saying so.
@(private = "file")
style_control :: proc(control: rl.GuiControl, border: u32, base: u32, text: u32) {
	rl.GuiSetStyle(control, c.int(rl.GuiControlProperty.BORDER_COLOR_NORMAL), gui_color(border))
	rl.GuiSetStyle(control, c.int(rl.GuiControlProperty.BASE_COLOR_NORMAL), gui_color(base))
	rl.GuiSetStyle(control, c.int(rl.GuiControlProperty.TEXT_COLOR_NORMAL), gui_color(text))
	rl.GuiSetStyle(control, c.int(rl.GuiControlProperty.BORDER_COLOR_FOCUSED), gui_color(FORGE_ACCENT))
	rl.GuiSetStyle(control, c.int(rl.GuiControlProperty.BASE_COLOR_FOCUSED), gui_color(FORGE_PANEL_ALT))
	rl.GuiSetStyle(control, c.int(rl.GuiControlProperty.TEXT_COLOR_FOCUSED), gui_color(FORGE_TEXT))
	rl.GuiSetStyle(control, c.int(rl.GuiControlProperty.BORDER_COLOR_PRESSED), gui_color(FORGE_ACCENT))
	rl.GuiSetStyle(control, c.int(rl.GuiControlProperty.BASE_COLOR_PRESSED), gui_color(FORGE_LINE))
	rl.GuiSetStyle(control, c.int(rl.GuiControlProperty.TEXT_COLOR_PRESSED), gui_color(FORGE_ACCENT))
	rl.GuiSetStyle(control, c.int(rl.GuiControlProperty.BORDER_COLOR_DISABLED), gui_color(FORGE_LINE))
	rl.GuiSetStyle(control, c.int(rl.GuiControlProperty.BASE_COLOR_DISABLED), gui_color(FORGE_PANEL))
	rl.GuiSetStyle(control, c.int(rl.GuiControlProperty.TEXT_COLOR_DISABLED), gui_color(FORGE_DERIVED))
}

// draw_mono draws `text` on the fixed monospace step, so every numeric column in the tool
// aligns digit for digit regardless of the font's own advances.
draw_mono :: proc(text: string, x: f32, y: f32, color: rl.Color) {
	pen := x
	for r in text {
		width := r >= 0 && r < 128 ? glyph_width[r] : mono_advance
		rl.DrawTextCodepoint(forge_mono, r, {pen + (mono_advance - width) / 2, y}, FORGE_TEXT_SIZE, color)
		pen += mono_advance
	}
}

// draw_mono_right draws `text` ending at `right`. Numbers are right-aligned in their
// column, and every price is written to two decimals, so the decimal points line up.
draw_mono_right :: proc(text: string, right: f32, y: f32, color: rl.Color) {
	draw_mono(text, right - f32(len(text)) * mono_advance, y, color)
}

// draw_text draws prose — a caption, a name, a reason — in the proportional font. Numbers
// never come through here.
draw_text :: proc(text: string, x: f32, y: f32, color: rl.Color) {
	rl.DrawTextEx(forge_font, fmt.ctprintf("%s", text), {x, y}, FORGE_TEXT_SIZE, FORGE_TEXT_SPACING, color)
}

// draw_text_clipped draws prose that must not run into the column beside it, cut to the
// width it is given. A pane in this tool is narrow and dense, so a line that overran would
// land on top of the number it is explaining.
draw_text_clipped :: proc(text: string, x: f32, y: f32, max_width: f32, color: rl.Color) {
	if max_width <= 0 || len(text) == 0 {
		return
	}
	width := text_width(text)
	if width <= max_width {
		draw_text(text, x, y, color)
		return
	}
	keep := clamp(int(f32(len(text)) * max_width / width) - 1, 0, len(text))
	draw_text(text[:keep], x, y, color)
}

// text_width is what draw_text will occupy, for the few places prose has to be measured
// (a tab's width, a right-aligned caption).
text_width :: proc(text: string) -> f32 {
	return rl.MeasureTextEx(forge_font, fmt.ctprintf("%s", text), FORGE_TEXT_SIZE, FORGE_TEXT_SPACING).x
}

// panel fills one pane's background and rules its edge. Panes are separated by a line and
// a tone step rather than by whitespace, which is what keeps three of them on screen at
// once.
panel :: proc(bounds: rl.Rectangle, title: string) -> (inner: rl.Rectangle) {
	rl.DrawRectangleRec(bounds, color_of(FORGE_PANEL))
	rl.DrawRectangleLinesEx(bounds, 1, color_of(FORGE_LINE))
	if len(title) == 0 {
		return rect_inset(bounds, FORGE_PAD)
	}
	header := rl.Rectangle{bounds.x + 1, bounds.y + 1, bounds.width - 2, FORGE_ROW}
	rl.DrawRectangleRec(header, color_of(FORGE_PANEL_ALT))
	draw_text(title, header.x + FORGE_PAD, header.y + (FORGE_ROW - FORGE_TEXT_SIZE) / 2, color_of(FORGE_TEXT))
	return rl.Rectangle {
		bounds.x + FORGE_PAD,
		bounds.y + FORGE_ROW + FORGE_PAD,
		bounds.width - 2 * FORGE_PAD,
		bounds.height - FORGE_ROW - 2 * FORGE_PAD,
	}
}

rect_inset :: proc(r: rl.Rectangle, by: f32) -> rl.Rectangle {
	return rl.Rectangle{r.x + by, r.y + by, r.width - 2 * by, r.height - 2 * by}
}

// points_text writes a Points value in the unit the budget publishes it in: hundredths of
// a point, always to two decimals so a column of them is decimal-aligned.
points_text :: proc(p: ship.Points) -> string {
	value := int(p)
	sign := ""
	if value < 0 {
		sign = "-"
		value = -value
	}
	return fmt.tprintf("%s%d.%02d", sign, value / 100, value % 100)
}
