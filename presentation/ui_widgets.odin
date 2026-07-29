#+private
package presentation

import "core:fmt"
import rl "vendor:raylib"

// The vocabulary the screens have been hand-rolling.
//
// ui.odin is a colour list and two font handles. There is no panel, no card, no button — so
// every screen builds "a rectangle with text in it" from scratch, and there are five
// independent implementations of that one component. With that vocabulary the aesthetic
// ceiling is *well-arranged rectangles*, and well-arranged rectangles is what the screens
// have hit.
//
// The component set is the one four independently-constrained designs of the Shop actually
// reached for, rather than the one that seemed likely — docs/ui/mock/shop/README.md records
// which design asked for what.
//
// Two axes and a scale run through all of it:
//
//   Emphasis    how loudly a thing speaks. Unavailable is a value on this axis rather than
//               three coordinated tone choices at a call site, because a block that dims two
//               of its three rows and ships is the failure that keeps happening.
//   Elevation   how far a thing sits off its ground. Inset is carved rather than laid on: a
//               blit only makes a thing sit *above* its ground, which says nothing when the
//               thing behind is the same material.
//   Space       a named scale. A screen that spaces itself off bare numbers cannot be
//               re-rhythmed without finding every one of them.
//
// **The guide's rules are baked in, so a call site cannot break them through these procs.**
// Nothing here takes an rl.Color, a font size, or a raw spacing: a caller names a role and
// the widget resolves it. That is the enforcement — a screen can still reach for a raw
// DrawRectangleRec today, and #496 is where that stops.
//
// **The screens draw through these, and a test enforces it** — no_screen_strokes_its_own_chrome
// (ui_contract_test.odin) fails the build on a hand-stroked rectangle outside a reasoned
// exemption list.

// Ui_Emphasis is how loudly a thing speaks, and it is the only rank there is. Colour carries
// hierarchy in this game, so this axis is what colour means.
Ui_Emphasis :: enum {
	Primary,
	Secondary,
	Muted,
	// Unavailable is a thing that is present and cannot be taken — an unaffordable card, a
	// control that is not offered. It is the faintest rank rather than a fifth kind of thing,
	// which is what lets a block demote every one of its rows by one step and have the last
	// row still have somewhere to go.
	//
	// It dims **by tone, never by alpha**: over a bright sea, translucency costs a surface its
	// own ground and the water reads through it as a stain (ADR-0032).
	Unavailable,
}

// Ui_Elevation is how far a surface sits off the one behind it.
Ui_Elevation :: enum {
	// Carved into its ground rather than laid on it — the only elevation that reads when the
	// thing behind is the same material.
	Inset,
	Flush,
	Raised,
	// Raised far enough to cast. The shadow is a second rectangle, which is what raylib has.
	Floating,
}

// Ui_Ground is what a widget is being drawn onto, because it decides what ink is legible.
// The guide's two ink rules are the whole of this axis: dark ink on parchment, light over
// water, and never the other way round.
Ui_Ground :: enum {
	Parchment,
	Water,
}

// Ui_Space is the spacing scale, named. Every gap, inset and pitch a widget takes comes from
// here, so re-rhythming a screen is a change of names rather than a hunt for numbers.
Ui_Space :: enum {
	None,
	Hair,
	Tight,
	Snug,
	Base,
	Wide,
	Loose,
	Vast,
}

// `:=` rather than `::`: Odin cannot index a constant array with a runtime value, and
// these are looked up by a value the caller supplies. Immutable by convention.
UI_SPACE := [Ui_Space]f32 {
	.None  = 0,
	.Hair  = 2,
	.Tight = 4,
	.Snug  = 8,
	.Base  = 12,
	.Wide  = 16,
	.Loose = 24,
	.Vast  = 32,
}

// Ui_Level is the type scale, whole, and it is reachable only through here. A screen that can
// name a size can invent one, and an invented size is an atlas nobody baked (ui.odin).
//
// Ordered largest first, so a level is a rank: Display leads a screen, Title leads a block,
// Body is everything else.
Ui_Level :: enum {
	Display,
	Title,
	Body,
}

// `:=` rather than `::`: Odin cannot index a constant array with a runtime value, and
// these are looked up by a value the caller supplies. Immutable by convention.
UI_LEVEL_SIZE := [Ui_Level]f32 {
	.Display = UI_DISPLAY_SIZE,
	.Title   = UI_TITLE_SIZE,
	.Body    = UI_BODY_SIZE,
}

// Ui_Anchor is where a string sits in the rect it is given. Named by three of the four
// mockups independently: a right-aligned price and a centred label are a MeasureTextEx at the
// call site today, or they are wrong.
Ui_Anchor :: enum {
	Left,
	Centre,
	Right,
}

// Ui_Weight is a divider's weight, and weight is the signal: whether a line separates two
// things or *is* a control. A screen can carry its whole structure on rules alone.
Ui_Weight :: enum {
	Hair,
	Rule,
}

// `:=` rather than `::`: Odin cannot index a constant array with a runtime value, and
// these are looked up by a value the caller supplies. Immutable by convention.
UI_WEIGHT_PX := [Ui_Weight]f32 {
	.Hair = 1,
	.Rule = 2,
}

// Ui_Icon is the marks that are shapes rather than text. The guide holds that a codepoint
// above Latin-1 cannot be depended on, so these are drawn (style guide, "Glyphs are shapes,
// not text"). The crate was asked for by two mockups and appears on every screen with a price.
Ui_Icon :: enum {
	Crate,
	Caret,
}

// ui_drawable reports whether there is anything to draw into. Every widget below opens with
// it, because a raylib draw call with no window touches an uninitialised batch and takes the
// process down — and unlike the screens, whose loops already guard, a widget is small enough
// that a test will reasonably want to call one and see that it did no harm.
ui_drawable :: proc() -> bool {
	return rl.IsWindowReady()
}

// ui_emphasis_down is one step down the rank — what a block does to every one of its rows
// when the whole block is unavailable. Emphasis is ordered, so demotion is arithmetic rather
// than a second table that could disagree with the first; the faintest rank stays put rather
// than running off the end.
ui_emphasis_down :: proc(emphasis: Ui_Emphasis) -> Ui_Emphasis {
	return Ui_Emphasis(min(int(emphasis) + 1, int(max(Ui_Emphasis))))
}

// ui_space is a named gap in pixels.
ui_space :: proc(space: Ui_Space) -> f32 {
	return UI_SPACE[space]
}

// ui_inset shrinks a rect by a named space on every side — the rule a widget's content
// follows so its padding is the scale's and not its own.
ui_inset :: proc(rect: rl.Rectangle, space: Ui_Space) -> rl.Rectangle {
	pad := ui_space(space)
	return rl.Rectangle {
		x = rect.x + pad,
		y = rect.y + pad,
		width = max(0, rect.width - 2 * pad),
		height = max(0, rect.height - 2 * pad),
	}
}

// ui_ink is the text tone for an emphasis on a ground.
//
// The water column is the ramp a container-less mockup had to derive for itself: parchment
// carries three ink levels and water carried exactly one, so it borrowed swatches the roster
// names as *surfaces* and used them as ink. Naming the ramp here is what stops four call
// sites each deciding privately that sand is a text colour.
//
// A switch rather than an [Ui_Ground][Ui_Emphasis]rl.Color table, which is otherwise this
// file's idiom: two entries are colour_shade of a swatch, and a package-level initialiser has
// no context to call it with. Kept as a shade rather than spelled as a literal so the
// relationship to the swatch survives — it is what every-ink-is-on-the-roster checks.
ui_ink :: proc(ground: Ui_Ground, emphasis: Ui_Emphasis) -> rl.Color {
	switch ground {
	case .Parchment:
		switch emphasis {
		case .Primary:
			return COLOUR_INK_PRIMARY
		case .Secondary:
			return COLOUR_INK_MUTED
		case .Muted:
			return colour_shade(COLOUR_INK_MUTED, 1.35)
		case .Unavailable:
			return colour_shade(COLOUR_INK_MUTED, 1.6)
		}
	case .Water:
		switch emphasis {
		case .Primary:
			return COLOUR_CREAM_BRIGHT
		case .Secondary:
			return COLOUR_PARCHMENT
		case .Muted:
			return COLOUR_SAND
		case .Unavailable:
			return COLOUR_CLIFF
		}
	}
	return COLOUR_INK_PRIMARY
}

// UI_SURFACE_TINT is how far a blitted frame dims at each rank. A tint multiplies, so one
// factor carries the whole frame — its field and its border together — where the hand-rolled
// version dimmed the two separately and could dim one and ship.
//
// `:=` rather than `::`: Odin cannot index a constant array with a runtime value, and this is
// looked up by a value the caller supplies. Immutable by convention.
UI_SURFACE_TINT := [Ui_Emphasis]f32 {
	.Primary     = 1,
	.Secondary   = 1,
	.Muted       = 0.95,
	.Unavailable = 0.90,
}

// ui_surface_tint is UI_SURFACE_TINT's factor as a tint colour.
ui_surface_tint :: proc(emphasis: Ui_Emphasis) -> rl.Color {
	return colour_shade(rl.WHITE, UI_SURFACE_TINT[emphasis])
}

// UI_SHADOW_OFFSET is how far a Floating surface throws its shadow, and UI_SHADOW_ALPHA how
// dark. A cast shadow, not a glow: the sea is bright, so the only way paper sits above it is
// to darken what is under the paper.
UI_SHADOW_OFFSET :: Ui_Space.Tight
UI_SHADOW_ALPHA :: 0.45

// ui_shadow lays the rectangle a Floating surface sits on. Drawn before the surface, by the
// widget, so no call site has to remember the offset.
ui_shadow :: proc(rect: rl.Rectangle) {
	if !ui_drawable() {
		return
	}
	drop := ui_space(UI_SHADOW_OFFSET)
	rl.DrawRectangleRec(
		{rect.x + drop, rect.y + drop + 1, rect.width, rect.height},
		rl.Fade(COLOUR_SEA_DEEP, UI_SHADOW_ALPHA),
	)
}

// ui_surface blits one frame with an elevation and an emphasis — the shared body of ui_panel
// and ui_card, which differ only in which frame they are.
ui_surface :: proc(frame: Ui_Frame, rect: rl.Rectangle, emphasis: Ui_Emphasis, elevation: Ui_Elevation) {
	if elevation == .Floating {
		ui_shadow(rect)
	}
	tint := ui_surface_tint(emphasis)
	if elevation == .Inset {
		// Carved rather than laid on: the same frame, darkened, so it reads as a well pressed
		// into the surface behind rather than a second sheet lying on it.
		tint = colour_shade(tint, 0.92)
	}
	ui_nine_slice(frame, rect, 0, tint)
}

// ui_panel is a surface that holds other things: the heaviest chrome there is.
ui_panel :: proc(rect: rl.Rectangle, elevation: Ui_Elevation, emphasis := Ui_Emphasis.Primary) {
	ui_surface(UI_FRAME_PANEL, rect, emphasis, elevation)
}

// ui_card is a thing *in* a panel, or on the world — flatter than a panel, and the component
// five screens have each written their own version of.
ui_card :: proc(rect: rl.Rectangle, emphasis: Ui_Emphasis, elevation: Ui_Elevation) {
	ui_surface(UI_FRAME_CARD, rect, emphasis, elevation)
}

// ui_button draws a control and its label. Hit-testing stays with the caller: a screen lays
// its own rects out and asks them what the mouse is over, which is the split that lets
// capture draw a screen it never clicks.
//
// No colour argument, because no colour on the roster means "act here" — the guide holds that
// controls do not have a signal colour, and a widget that accepted one would be the way that
// rule gets broken.
ui_button :: proc(rect: rl.Rectangle, label: string, state: Ui_Button_State, emphasis := Ui_Emphasis.Primary) {
	ui_nine_slice(UI_FRAME_BUTTON, rect, int(state), ui_surface_tint(emphasis))
	// The frame's field is parchment, so a button's label is always on parchment whatever the
	// button is standing on.
	ui_text(rect, label, .Body, .Parchment, emphasis, .Centre)
}

// ui_heading is a title over a block. The size is a level rather than a number, so a screen
// cannot ask for an atlas nobody baked.
ui_heading :: proc(
	rect: rl.Rectangle,
	text: string,
	level: Ui_Level,
	ground: Ui_Ground,
	emphasis := Ui_Emphasis.Primary,
	anchor := Ui_Anchor.Left,
) {
	ui_text(rect, text, level, ground, emphasis, anchor)
}

// ui_divider is a line across a block. `rect` gives where it runs and how far; the weight
// gives how heavy, and heavy is what it means.
ui_divider :: proc(rect: rl.Rectangle, weight: Ui_Weight, ground: Ui_Ground, emphasis := Ui_Emphasis.Secondary) {
	if !ui_drawable() {
		return
	}
	thickness := UI_WEIGHT_PX[weight]
	tone := ground == .Parchment ? COLOUR_SAND : COLOUR_FOAM
	if emphasis == .Muted || emphasis == .Unavailable {
		tone = ground == .Parchment ? COLOUR_CLIFF : COLOUR_SEA_DEEP
	}
	// Horizontal or vertical is read off the rect rather than named twice: a divider is
	// whichever of its two dimensions is the long one.
	if rect.width >= rect.height {
		rl.DrawRectangleRec(ui_pixel_rect({rect.x, rect.y, rect.width, thickness}), tone)
	} else {
		rl.DrawRectangleRec(ui_pixel_rect({rect.x, rect.y, thickness, rect.height}), tone)
	}
}

// ui_icon draws one of the marks that are shapes rather than glyphs, fitted to `rect`.
ui_icon :: proc(rect: rl.Rectangle, icon: Ui_Icon, ground: Ui_Ground, emphasis := Ui_Emphasis.Primary) {
	if !ui_drawable() {
		return
	}
	tone := ui_ink(ground, emphasis)
	box := ui_pixel_rect(rect)
	switch icon {
	case .Crate:
		// A bound bale: a crate with a cross through it, so it reads as goods rather than an
		// empty square.
		rl.DrawRectangleLinesEx(box, 1, tone)
		rl.DrawLineEx({box.x + box.width / 2, box.y}, {box.x + box.width / 2, box.y + box.height}, 1, tone)
		rl.DrawLineEx({box.x, box.y + box.height / 2}, {box.x + box.width, box.y + box.height / 2}, 1, tone)
	case .Caret:
		// Vertex order is raylib's counter-clockwise requirement — reverse it and the triangle
		// is culled, drawing nothing at all.
		rl.DrawTriangle(
			{box.x, box.y},
			{box.x, box.y + box.height},
			{box.x + box.width, box.y + box.height / 2},
			tone,
		)
	}
}

// UI_ALARM_WASH is how strongly a destructive target washes at rest, and UI_ALARM_LIT when
// the cursor is over it — the difference is what says a release *here* is the one that acts.
UI_ALARM_WASH :: 0.2
UI_ALARM_LIT :: 0.4

// ui_alarm marks a surface as the destructive one: the reserved coral, washed over a surface
// already laid down, with a border in the same tone.
//
// **This is the only place coral is drawn as chrome, and that is the point.** The roster keeps
// `COLOUR_CORAL` for danger and damage, and scarcity is a rule that gets remembered rather
// than enforced — until there is exactly one proc that spends it and every destructive target
// on every screen goes through that proc.
ui_alarm :: proc(rect: rl.Rectangle, lit: bool) {
	if !ui_drawable() {
		return
	}
	box := ui_pixel_rect(rect)
	rl.DrawRectangleRec(box, rl.Fade(COLOUR_CORAL, lit ? UI_ALARM_LIT : UI_ALARM_WASH))
	rl.DrawRectangleLinesEx(box, UI_WEIGHT_PX[.Rule], COLOUR_CORAL)
}

// ui_text_size measures a string at a level. Zero before the atlases are baked (under
// `odin test`, and before art_load), so a layout computed without a window is zero rather
// than whatever an unbaked font reports.
ui_text_size :: proc(text: string, level: Ui_Level) -> rl.Vector2 {
	font := ui_font_for(level)
	if font.texture.id == 0 {
		return {}
	}
	return rl.MeasureTextEx(font, fmt.ctprintf("%s", text), UI_LEVEL_SIZE[level], 1)
}

// ui_text places a string in a rect, anchored, and vertically centred in it. This is the
// measure-and-place helper three of the four mockups asked for independently — with no box to
// align inside, every centred label and every right-aligned price is a MeasureTextEx at the
// call site, or it is wrong.
ui_text :: proc(
	rect: rl.Rectangle,
	text: string,
	level: Ui_Level,
	ground: Ui_Ground,
	emphasis := Ui_Emphasis.Primary,
	anchor := Ui_Anchor.Left,
) {
	font := ui_font_for(level)
	if !ui_drawable() || font.texture.id == 0 {
		return
	}
	size := ui_text_size(text, level)
	rl.DrawTextEx(
		font,
		fmt.ctprintf("%s", text),
		ui_text_origin(rect, size, anchor),
		UI_LEVEL_SIZE[level],
		1,
		ui_ink(ground, emphasis),
	)
}

// ui_text_tinted places a string at an explicit tone, and it is the one procedure here that
// takes a colour. It exists for the voyage screens the guide has not re-coloured
// (ui_contract_test.odin's exemption list), whose stage headers carry a category hue no
// Ui_Emphasis names — and it takes a **level**, not a size, so the one rule that is absolute
// stays absolute: no screen can name a size, and there is no atlas nobody baked.
//
// A re-coloured screen has no business calling this. Reach for ui_text.
ui_text_tinted :: proc(
	rect: rl.Rectangle,
	text: string,
	level: Ui_Level,
	tone: rl.Color,
	anchor := Ui_Anchor.Left,
) {
	font := ui_font_for(level)
	if !ui_drawable() || font.texture.id == 0 {
		return
	}
	rl.DrawTextEx(
		font,
		fmt.ctprintf("%s", text),
		ui_text_origin(rect, ui_text_size(text, level), anchor),
		UI_LEVEL_SIZE[level],
		1,
		tone,
	)
}

// ui_text_origin is where a measured string starts, given its box and its anchor. Pure, so
// the placement is testable without a window — which is the half of text drawing that goes
// wrong.
ui_text_origin :: proc(rect: rl.Rectangle, size: rl.Vector2, anchor: Ui_Anchor) -> rl.Vector2 {
	x: f32
	switch anchor {
	case .Left:
		x = rect.x
	case .Centre:
		x = rect.x + (rect.width - size.x) / 2
	case .Right:
		x = rect.x + rect.width - size.x
	}
	origin := rl.Vector2{x, rect.y + (rect.height - size.y) / 2}
	// Whole pixels: a glyph landing on a half pixel is resampled, which is the whole thing a
	// pixel face is chosen to avoid.
	return {f32(int(origin.x + 0.5)), f32(int(origin.y + 0.5))}
}

ui_font_for :: proc(level: Ui_Level) -> rl.Font {
	switch level {
	case .Display:
		return ui_font_display
	case .Title:
		return ui_font_title
	case .Body:
		return ui_font_body
	}
	return ui_font_body
}
