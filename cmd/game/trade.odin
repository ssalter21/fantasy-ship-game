package main

import "core:fmt"
import voyage "../../core/voyage"
import sim "../../core/sim"
import rl "vendor:raylib"

// The Trade stage (#318, #310, ADR-0024): a permanent stat-for-stat swap, drawn as two cards
// inside the shared encounter frame. The bargain's name is a cyan subtitle under the ochre
// Trade header; below it sit the give card (left, the cost) and the get card (right, the gain),
// a single steel transform arrow between them saying the swap is one irreversible motion. Both
// cards take the same recessive-blue inert border — a Trade has no red/green "bad side / good
// side"; it is one bargain you weigh whole.
//
// Each card projects its stat before→after off Event_Trade_Presented (trade_cost_read /
// trade_gain_read), so the view never recomputes effective stats: a bright delta headline
// (`Durability -3`) over a dim-cyan consequence (`5 -> 2`). That consequence is where the
// Durability / Max Hull the top-right stat line hides becomes visible, and where a Cargo gain
// above capacity shows its #157 waste as an after that stalls short of before+amount.
//
// Accept (left) is the one amber on the screen — but only when the ship can pay; an unaffordable
// bargain dims it to inert recessive-blue and won't click, the give card's after sits below its
// floor, and a dim-cyan shortfall hint names the stat that falls short. No warm warning colour:
// the screen says "you can't" by withholding the amber, not by turning red. Decline (right) is a
// steel control, one clean click, no confirm — declining a Trade halts the encounter (ADR-0014),
// and #304's no-preview rule keeps a forfeit warning off it.
//
// Split composition (draw_trade) from polling (trade_menu_loop) like every other stage, so
// --capture photographs it at rest (#277).

TRADE_NAME_Y :: 70

TRADE_CARD_W :: 300
TRADE_CARD_H :: 150
TRADE_CARD_Y :: 168
TRADE_CARD_GAP :: 124 // room for the transform arrow between the two cards

TRADE_BUTTON_W :: 200
TRADE_BUTTON_H :: 56
TRADE_BUTTON_Y :: 400
TRADE_BUTTON_GAP :: 40

// trade_give_card_rect / trade_get_card_rect are the two cards' slots, the pair centred with a
// gap between them for the arrow. Pure functions of the window so drawing and any hit-test ask
// the same source (the split that lets capture draw a screen it never polls).
trade_give_card_rect :: proc() -> rl.Rectangle {
	total := f32(TRADE_CARD_W * 2 + TRADE_CARD_GAP)
	return rl.Rectangle {
		x      = (WINDOW_WIDTH - total) / 2,
		y      = TRADE_CARD_Y,
		width  = TRADE_CARD_W,
		height = TRADE_CARD_H,
	}
}

trade_get_card_rect :: proc() -> rl.Rectangle {
	give := trade_give_card_rect()
	return rl.Rectangle {
		x      = give.x + TRADE_CARD_W + TRADE_CARD_GAP,
		y      = give.y,
		width  = TRADE_CARD_W,
		height = TRADE_CARD_H,
	}
}

// trade_accept_rect / trade_decline_rect are the two answers, centred as a pair below the cards.
// Accept sits left (the amber, when payable), Decline right (steel) — Decline is never the
// default, so it never takes the amber (the amber rule).
trade_accept_rect :: proc() -> rl.Rectangle {
	total := f32(TRADE_BUTTON_W * 2 + TRADE_BUTTON_GAP)
	return rl.Rectangle {
		x      = (WINDOW_WIDTH - total) / 2,
		y      = TRADE_BUTTON_Y,
		width  = TRADE_BUTTON_W,
		height = TRADE_BUTTON_H,
	}
}

trade_decline_rect :: proc() -> rl.Rectangle {
	accept := trade_accept_rect()
	return rl.Rectangle {
		x      = accept.x + TRADE_BUTTON_W + TRADE_BUTTON_GAP,
		y      = accept.y,
		width  = TRADE_BUTTON_W,
		height = TRADE_BUTTON_H,
	}
}

// trade_stat_label names a tradeable stat for the player (issue #136): the enum's own spelling
// (Max_Hull) isn't presentable, and it is Title-cased so it reads as a card heading and in the
// "Not enough X" shortfall alike.
trade_stat_label :: proc(stat: voyage.Trade_Stat) -> string {
	switch stat {
	case .Hull:
		return "Hull"
	case .Max_Hull:
		return "Max Hull"
	case .Durability:
		return "Durability"
	case .Cargo:
		return "Cargo"
	}
	return "?"
}

// trade_delta_headline is a card's bright top line: the stat and the signed swing it takes
// (`Durability -3` on the give side, `+15 Cargo` read as `Cargo +15` on the get side). A
// Trade_Term stores only the positive magnitude — the side supplies the sign — so `gain` picks
// "+" for the get card, "-" for the give card.
trade_delta_headline :: proc(term: voyage.Trade_Term, gain: bool) -> string {
	return fmt.tprintf("%s %s%d", trade_stat_label(term.stat), gain ? "+" : "-", term.amount)
}

// trade_consequence_text is the dim-cyan line under the headline: the stat's reading before the
// swap and after it. ASCII "->" rather than "→": Pixelify Sans carries no U+2192, so the glyph
// would render as a blank box (see UI_FONT_EXTRA_CODEPOINTS) — the transform mark between the
// cards carries the arrow as a drawn shape instead.
trade_consequence_text :: proc(read: voyage.Trade_Reading) -> string {
	return fmt.tprintf("%d -> %d", read.before, read.after)
}

// trade_shortfall_text names the stat an unaffordable bargain falls short in, shown dim-cyan
// beneath the answers only while can_accept is false (#310). It is the one place the screen says
// why Accept is dark — there is no warm warning, just the missing amber and this line.
trade_shortfall_text :: proc(stat: voyage.Trade_Stat) -> string {
	return fmt.tprintf("Not enough %s", trade_stat_label(stat))
}

// trade_menu_loop is the Trade screen's blocking loop (issue #136, ADR-0014), the two-card
// successor to the old accept/reject boxes: it renders the bargain and returns a
// Command_Trade_Choice when the player accepts (only when trade_can_accept) or declines.
// Accepting applies the swap permanently and completes the stage; declining halts the encounter,
// changing nothing.
//
// An unaffordable Accept is drawn inert and is **not** clickable — the opposite of the shop's
// unaffordable card. A shop has an Event_Purchase_Rejected to say no with and stays open for
// another choice; a Trade's only other answer is to decline, so a Sim-side refusal would have
// nowhere to return to, and submitting one is a driver bug the Sim asserts on.
trade_menu_loop :: proc(state: ^Game_State) -> sim.Command {
	if !rl.IsWindowReady() {
		// No live window (e.g. under `odin test`): decline rather than permanently swap a
		// stat the test harness never chose.
		return sim.Command(sim.Command_Trade_Choice{accept = false})
	}

	for {
		window_quit_if_closed()
		mouse := rl.GetMousePosition()
		draw_trade(state, mouse)

		if rl.IsMouseButtonPressed(.LEFT) {
			if state.trade_can_accept && rl.CheckCollisionPointRec(mouse, trade_accept_rect()) {
				return sim.Command(sim.Command_Trade_Choice{accept = true})
			}
			if rl.CheckCollisionPointRec(mouse, trade_decline_rect()) {
				return sim.Command(sim.Command_Trade_Choice{accept = false})
			}
		}
	}
}

// draw_trade draws one whole frame of the Trade screen: the bargain name, the two projection
// cards with the transform arrow between them, the Accept/Decline answers, the shortfall hint
// when unaffordable, and the shared encounter chrome over it all. Split from trade_menu_loop so
// composing and polling are separate acts — capture draws and never polls (#277).
draw_trade :: proc(state: ^Game_State, mouse: rl.Vector2) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	defer free_all(context.temp_allocator)

	rl.ClearBackground(COLOUR_DEEP)

	trade := state.active_trade

	// The bargain name, a cyan subtitle centred under the ochre Trade header.
	name := fmt.ctprintf("%s", trade.name)
	nsize := rl.MeasureTextEx(ui_font_title, name, UI_TITLE_SIZE, 1)
	rl.DrawTextEx(ui_font_title, name, rl.Vector2{(WINDOW_WIDTH - nsize.x) / 2, TRADE_NAME_Y}, UI_TITLE_SIZE, 1, COLOUR_CYAN)

	// The two cards: give (cost) left, get (gain) right, each an inert recessive-blue panel with
	// its stat's before→after projection. No red/green — both take the same border.
	draw_trade_card(trade_give_card_rect(), "You give", trade_delta_headline(trade.cost, false), state.trade_cost_read)
	draw_trade_card(trade_get_card_rect(), "You get", trade_delta_headline(trade.gain, true), state.trade_gain_read)

	// The transform mark between them: a steel arrow drawn as a shape (shaft + head), saying the
	// swap is one irreversible motion, left to right.
	give := trade_give_card_rect()
	get := trade_get_card_rect()
	arrow_mid := rl.Vector2{(give.x + give.width + get.x) / 2, give.y + give.height / 2}
	draw_trade_arrow(arrow_mid, get.x - (give.x + give.width) - 24, COLOUR_STEEL)

	draw_trade_accept(state.trade_can_accept, mouse)
	draw_trade_decline(mouse)

	// The shortfall hint, only while the bargain can't be paid: the one line that says why Accept
	// is dark, dim-cyan and centred below the answers. No warm warning colour (#310).
	if !state.trade_can_accept {
		hint := fmt.ctprintf("%s", trade_shortfall_text(trade.cost.stat))
		hsize := rl.MeasureTextEx(ui_font_body, hint, UI_BODY_SIZE, 1)
		rl.DrawTextEx(ui_font_body, hint, rl.Vector2{(WINDOW_WIDTH - hsize.x) / 2, TRADE_BUTTON_Y + TRADE_BUTTON_H + 18}, UI_BODY_SIZE, 1, COLOUR_CYAN_DIM)
	}

	draw_encounter_chrome(state, .Trade)
}

// draw_trade_card renders one bargain card: a small steel role label ("You give" / "You get"), a
// bright cream delta headline, and the dim-cyan before→after consequence beneath. The border is
// recessive-blue — inert, because a Trade card is a statement of the swap, not a control you
// operate (the answers below are the controls).
draw_trade_card :: proc(rect: rl.Rectangle, role: string, headline: string, read: voyage.Trade_Reading) {
	rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, 0.5))
	draw_subpanel_border(rect, false)

	x := rect.x + 18
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", role), rl.Vector2{x, rect.y + 16}, UI_BODY_SIZE, 1, COLOUR_STEEL)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", headline), rl.Vector2{x, rect.y + 62}, UI_BODY_SIZE, 1, COLOUR_CREAM)
	rl.DrawTextEx(ui_font_body, fmt.ctprintf("%s", trade_consequence_text(read)), rl.Vector2{x, rect.y + 100}, UI_BODY_SIZE, 1, COLOUR_CYAN_DIM)
}

// draw_trade_arrow draws the steel transform mark as a shape (style guide: glyphs are shapes):
// a shaft with a filled arrowhead pointing right. The head is wound the same way the chart
// caret proved survives raylib's clockwise cull.
draw_trade_arrow :: proc(mid: rl.Vector2, length: f32, colour: rl.Color) {
	half := length / 2
	tail := rl.Vector2{mid.x - half, mid.y}
	tip := rl.Vector2{mid.x + half, mid.y}
	base := rl.Vector2{tip.x - 12, tip.y} // where the shaft meets the head
	rl.DrawLineEx(tail, base, 4, colour)
	rl.DrawTriangle(
		rl.Vector2{base.x - 7, base.y - 11},
		rl.Vector2{base.x - 7, base.y + 11},
		tip,
		colour,
	)
}

// draw_trade_accept draws the left answer. Payable, it is the screen's one amber — a filled
// amber panel with an ink label, the default action offered. Unaffordable, it dims to an inert
// recessive-blue outline with a dimmed label: no amber on screen, and the loop won't click it
// (#310). It never carries a hover scrim, because when it is live it is already the brightest
// thing here.
draw_trade_accept :: proc(can_accept: bool, mouse: rl.Vector2) {
	rect := trade_accept_rect()
	if can_accept {
		rl.DrawRectangleRec(rect, COLOUR_AMBER)
		draw_trade_button_label(rect, "Accept", COLOUR_INK)
	} else {
		rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, 0.4))
		rl.DrawRectangleLinesEx(rect, 2, COLOUR_BLUE_RECESSIVE)
		draw_trade_button_label(rect, "Accept", COLOUR_BLUE_RECESSIVE)
	}
}

// draw_trade_decline draws the right answer: a steel control whose scrim lifts on hover (hover
// carried by the scrim, not by amber — the amber rule). One clean click, no confirm.
draw_trade_decline :: proc(mouse: rl.Vector2) {
	rect := trade_decline_rect()
	hovered := rl.CheckCollisionPointRec(mouse, rect)
	rl.DrawRectangleRec(rect, rl.Fade(COLOUR_GROUND, hovered ? 0.75 : 0.55))
	rl.DrawRectangleLinesEx(rect, 2, COLOUR_STEEL)
	draw_trade_button_label(rect, "Decline", COLOUR_STEEL)
}

// draw_trade_button_label centres a label in an answer button, the shared layout so Accept and
// Decline read identically bar their tone.
draw_trade_button_label :: proc(rect: rl.Rectangle, label: string, tone: rl.Color) {
	text := fmt.ctprintf("%s", label)
	size := rl.MeasureTextEx(ui_font_body, text, UI_BODY_SIZE, 1)
	rl.DrawTextEx(
		ui_font_body,
		text,
		rl.Vector2{rect.x + (rect.width - size.x) / 2, rect.y + (rect.height - UI_BODY_SIZE) / 2},
		UI_BODY_SIZE,
		1,
		tone,
	)
}
