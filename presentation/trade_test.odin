package presentation

import "core:testing"
import voyage "../core/voyage"
import rl "vendor:raylib"

// The Trade screen's text and layout helpers, tested as pure functions (#318) — no window, so
// `odin test` exercises how the give→get cards read and where the answers sit without a render
// loop, the same split offer_shop_test.odin uses.

@(test)
trade_delta_headline_signs_the_give_and_get_sides :: proc(t: ^testing.T) {
	// The give card loses its cost; the get card gains its amount. A Trade_Term stores only the
	// magnitude, so the sign is the side's, not the term's.
	give := trade_delta_headline(voyage.Trade_Term{stat = .Max_Hull, amount = 3}, false)
	testing.expect(t, give == "Max Hull -3")

	get := trade_delta_headline(voyage.Trade_Term{stat = .Cargo, amount = 30}, true)
	testing.expect(t, get == "Cargo +30")
}

@(test)
trade_stat_label_titlecases_max_hull_and_cargo :: proc(t: ^testing.T) {
	// Card headings and the shortfall hint both read the stat, so it is Title-cased (the old
	// mid-sentence lowercase "cargo" would look wrong as a heading).
	testing.expect(t, trade_stat_label(.Max_Hull) == "Max Hull")
	testing.expect(t, trade_stat_label(.Cargo) == "Cargo")
}

@(test)
trade_consequence_text_reads_before_to_after :: proc(t: ^testing.T) {
	// ASCII "->" not "→": Pixelify Sans carries no U+2192 (the transform mark is a drawn shape).
	testing.expect(t, trade_consequence_text(voyage.Trade_Reading{before = 5, after = 2}) == "5 -> 2")
	// An unaffordable give card projects below the floor, shown honestly.
	testing.expect(t, trade_consequence_text(voyage.Trade_Reading{before = 2, after = -3}) == "2 -> -3")
}

@(test)
trade_shortfall_text_names_the_short_stat :: proc(t: ^testing.T) {
	testing.expect(t, trade_shortfall_text(.Max_Hull) == "Not enough Max Hull")
}

@(test)
trade_cards_and_answers_do_not_overlap :: proc(t: ^testing.T) {
	// The two cards sit side by side with the transform arrow between them; the two answers do
	// too. A layout regression that slid one onto the other would make a hit-test ambiguous.
	give := trade_give_card_rect()
	get := trade_get_card_rect()
	testing.expect(t, !rl.CheckCollisionRecs(give, get))
	testing.expect(t, give.x + give.width < get.x) // room for the arrow

	accept := trade_accept_rect()
	decline := trade_decline_rect()
	testing.expect(t, !rl.CheckCollisionRecs(accept, decline))
	testing.expect(t, accept.x < decline.x)

	// The answers sit below the cards, never over them.
	testing.expect(t, accept.y > give.y + give.height)
}
