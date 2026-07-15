# PROTOTYPE NOTES — #158, the weight→Speed curve

**Throwaway.** Delete `cmd/proto_speed_curve/` once #158 is answered and the ADR lands.

Run it: `odin run cmd/proto_speed_curve`. Full output committed alongside as `OUTPUT.txt`.

## The question

Under the weight model, does a **derived** hostile Speed spread still straddle the
player's 4 — the property #135 hand-authored and pinned by test?

## The answer: no — not from loadout. Yes — from the purse.

### 1. Loadout cannot carry the spread, because `fittings + capacity` is constant

| archetype | #135 | fittings | capacity | **fit+cap** |
|---|---|---|---|---|
| Coastal Privateer | 4 | 77 | 90 | **167** |
| Broadside Company | 4 | 40 | 120 | **160** |
| Deepwater Menagerie | 3 | 32 | 130 | **162** |
| Smuggler's Run | 5 | 72 | 90 | **162** |
| Ironclad Hulk | 2 | 119 | 60 | **179** |
| Boarding Party | 4 | 43 | 120 | **163** |
| Death Throes | 3 | 45 | 120 | **165** |
| Reef Skimmer | 6 | 69 | 90 | **159** |

Heavy items sit in big slots, so a heavy build has **less room for money**. The two
terms anti-correlate and their sum lands in a 20-point band across all eight.

This is not a discovery so much as **#156's own prediction, confirmed** — it anchored
the authored weight band *on* capacity ("a fully-laden ship weighs ~170 whatever its
loadout"), and this prototype's weights were authored to that rule. The prototype's
contribution is showing what that costs: **a fully-laden hostile's Speed carries no
information about what kind of ship it is.**

### 2. At today's ladenness the model reproduces #135's original bug, mirrored

A hostile's "Spoils" cargo is `CARGO_STACK_COUNT :: 1` — essentially empty. So a
derived hostile weighs only its fittings (32–119) while the player weighs
**122** (72 of fittings + the 50-treasure purse).

**Straddle check at 0% laden: 0 slower / 8 faster, under every divisor tested.**

The player, carrying money, is the heaviest thing afloat. Every hostile is
escape-eligible and bolts; the player can never take Leave Combat; the roster's
`Condition_Opponent_Slower` items never fire. That is precisely the flat
`FIGHT_OPPONENT_SPEED :: 5` bug #135 removed — restored silently, two commits later,
and nothing asserts against it. **This is exactly the failure #158 was written to
look for, and it is real.**

The straddle only appears in a narrow band of hostile ladenness (~50–75%), which is
a number nobody has authored and no ticket currently owns.

### 3. The fix: an archetype authors its **treasure**, not its Speed

Replace `Hostile_Archetype.speed: int` with an authored purse. Speed then derives.

**#135's exact spread (4,4,3,5,2,4,3,6) is reproducible under every divisor tested,
and every required purse fits inside that archetype's own holds.** At `weight/10`:

| archetype | #135 | purse needed | capacity |
|---|---|---|---|
| Coastal Privateer | 4 | 43–52 | 90 |
| Broadside Company | 4 | 80–89 | 120 |
| Deepwater Menagerie | 3 | 98–107 | 130 |
| Smuggler's Run | 5 | 68–77 | 90 |
| Ironclad Hulk | 2 | 21–30 | 60 |
| Boarding Party | 4 | 77–86 | 120 |
| Death Throes | 3 | 85–94 | 120 |
| Reef Skimmer | 6 | 61–70 | 90 |

So #135's hard-won spread is **not** lost — it survives re-derivation, expressed in a
different currency. Its eight numbers were never really Speeds; they were a proxy for
how much ship there was to haul.

**And the authored purse is the same number as the spoils you win by sinking it
(#159).** One authored number does both jobs: a fat merchant is slow *and* worth
robbing; a lean raider is fast *and* worth nothing. That is the pirate fantasy falling
out of the weight model for free — but it couples #158 to #159 hard.

### 4. The divisor is the exchange rate, and 10 is the granular pick

Points of Speed bought by heaving a **full** hold overboard:

| divisor | Small (10) | Medium (20) | Large (40) |
|---|---|---|---|
| **10** | **1** | **2** | **4** |
| 15 | 0 | 1 | 2 |
| 20 | 0 | 1 | 2 |
| 25 | 0 | 0 | 1 |

At any divisor above 10, **jettisoning the smallest hold buys nothing** — a no-op
Jettison Cargo, which is worse than the `JETTISON_SPEED_BONUS :: 1` it replaces.

At 10 the capacity table *is* the Speed table divided by ten: #156's ×10-and-doubling
(10/20/40) reads straight through as 1/2/4 Speed. One table, both jobs.

Cost: `base` calibrates to **16** for the player's starting ship to read 4, and
full-laden ships hit 0 or **−1** — so the curve needs the floor #136 already
established as precedent.

Player dynamic range at `16 + mods − weight/10`: **9 when broke, 4 at start, 0 when
rich** — which is the destination's sentence stated as arithmetic ("getting rich is
what makes you catchable").

### 5. `base` is one constant, not per-hull

The slice has exactly one hull (`ship_template_layout`), so per-hull base is moot
today. It should stay one constant regardless: under this model `base` is *calibration
of the curve*, and a ship's character is expressed by its items and its purse — which
is the whole point of the model.

## Caveats

- The ~50 item weights here are **placeholders authored for this prototype**, in
  #156's band, aimed at character (iron heavy, canvas light). The *shape* of the
  findings is robust to their exact values — finding 1 follows from #156's band rule
  itself, and finding 2 has an 8–0 margin. Finding 3's purse windows would shift.
- No battles are driven. #135's precedent is that the band is not eye-checkable and
  wants a real-battle test; that belongs to the execution ticket, not here.
