package cutaway

import ship "../../core/ship"
import rl "vendor:raylib"

// The cutaway module owns where the ship's cross-section puts every slot (#426): given a
// layout and a Region, cutaway_slot_rects is the one answer to "where does this slot sit",
// and drawing and hit-testing both ask it — the two can no longer disagree by convention.
// The slot-geometry constants live here, unexported, so no screen can grow a private copy.
// Painting stays with the callers: this package decides *where*, never *how it looks*.

// MAX_SLOTS bounds a laid-out cutaway — the vertical-slice ship's 8 (#91). Exported because
// it is the size of cutaway_slot_rects' value-array return.
MAX_SLOTS :: 8

@(private)
SLOT_GAP :: 18

// The Home/Build cross-section lines (cutaway_home_region). The keel sits clear above the
// Build surface's stats ledger (y 650).
@(private)
HOME_DECK_Y :: 100
@(private)
HOME_WATERLINE_Y :: 290
@(private)
HOME_HOLD_Y :: 312
@(private)
HOME_KEEL_Y :: 610

// Region is where a ship's cross-section sits on screen: the horizontal span the rows
// centre in, the four heights the geography hangs off — deck (exposed stations), waterline
// (the exposed/concealed split, ADR-0030), hold (concealed berths), keel — and the uniform
// card scale. One value per screen, spelled once, so a screen's draw and hit-test read the
// same cutaway. `scale` has no meaningful zero: a Region literal that forgot it is a driver
// bug, asserted in cutaway_slot_rects.
Region :: struct {
	x, w:        f32,
	deck_y:      f32,
	waterline_y: f32,
	hold_y:      f32,
	keel_y:      f32,
	scale:       f32,
}

// cutaway_home_region is the full-window region Home and a granted Refit draw at scale 1 —
// the canonical cutaway, whose lines the encounter screens compress. `w` is the window's
// width; the caller owns the window, so the one thing the region can't decide comes in.
cutaway_home_region :: proc(w: f32) -> Region {
	return Region {
		x           = 0,
		w           = w,
		deck_y      = HOME_DECK_Y,
		waterline_y = HOME_WATERLINE_Y,
		hold_y      = HOME_HOLD_Y,
		keel_y      = HOME_KEEL_Y,
		scale       = 1,
	}
}

// cutaway_card_dims is a card's footprint by slot size — Large > Medium > Small — so size
// reads off the card's own size (#302), no number needed. `scale` shrinks the whole
// size-language uniformly, so the encounter stages (#312) can sit the same ship beside a
// shelf without re-deciding what a Large card is.
cutaway_card_dims :: proc(size: ship.Slot_Size, scale: f32 = 1) -> (w: f32, h: f32) {
	switch size {
	case .Small:
		return 140 * scale, 110 * scale
	case .Medium:
		return 190 * scale, 130 * scale
	case .Large:
		return 250 * scale, 150 * scale
	}
	return 140 * scale, 110 * scale
}

// cutaway_slot_rects lays every slot out into two centred rows — exposed stations on the
// deck, concealed holds in the belly, so geography carries the split (ADR-0030) — in layout
// order within each row, card size tracking slot size. A pure function of (layout, region),
// so draw and hit-test both ask for it rather than sharing a local (the split that lets
// capture draw a screen it never clicks). Value array, no allocation; `n` is how many of the
// MAX_SLOTS entries are live.
cutaway_slot_rects :: proc(
	layout: []ship.Layout_Slot,
	region: Region,
) -> (
	rects: [MAX_SLOTS]rl.Rectangle,
	n: int,
) {
	assert(region.scale > 0, "a Region literal must spell its scale")
	n = min(len(layout), MAX_SLOTS)
	gap := SLOT_GAP * region.scale

	// A row is centred: sum its cards' widths and the gaps between them, then start it so
	// the whole run is centred in the region.
	row_width :: proc(layout: []ship.Layout_Slot, want: ship.Visibility, n: int, gap, scale: f32) -> f32 {
		total: f32 = 0
		count := 0
		for ls, i in layout {
			if i >= n || ls.slot.base_visibility != want {
				continue
			}
			w, _ := cutaway_card_dims(ls.slot.size, scale)
			total += w
			count += 1
		}
		if count > 1 {
			total += f32(count - 1) * gap
		}
		return total
	}

	place_row :: proc(
		layout: []ship.Layout_Slot,
		rects: ^[MAX_SLOTS]rl.Rectangle,
		want: ship.Visibility,
		row_y: f32,
		region: Region,
		gap: f32,
		n: int,
	) {
		x := region.x + (region.w - row_width(layout, want, n, gap, region.scale)) / 2
		for ls, i in layout {
			if i >= n || ls.slot.base_visibility != want {
				continue
			}
			w, h := cutaway_card_dims(ls.slot.size, region.scale)
			rects[i] = rl.Rectangle{x = x, y = row_y, width = w, height = h}
			x += w + gap
		}
	}

	place_row(layout, &rects, .Exposed, region.deck_y, region, gap, n)
	place_row(layout, &rects, .Concealed, region.hold_y, region, gap, n)
	return rects, n
}

// cutaway_slot_at returns the slot whose card the point is over, or nil — the hit-test half
// of the one answer: it consults the same laid-out slots the drawing used.
cutaway_slot_at :: proc(layout: []ship.Layout_Slot, region: Region, point: rl.Vector2) -> Maybe(ship.Slot_Index) {
	rects, n := cutaway_slot_rects(layout, region)
	for i in 0 ..< n {
		if rl.CheckCollisionPointRec(point, rects[i]) {
			return ship.Slot_Index(i)
		}
	}
	return nil
}
