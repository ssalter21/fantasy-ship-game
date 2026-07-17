# ADR-0022: `main` owns the loop above `run_session` — a session is N voyages

## Status

Accepted. **Amends ADR-0002's wording, not its decision.** ADR-0002's guarantee — exactly one driver loop for tick → dispatch → await → submit, shared by headless and UI so the two can never drift — carries forward untouched, as do its blocking-modal-loop pattern and its `Input_Source`/`Event_Sink` proc-pointer tables. What retires is ADR-0002's claim that `run_session` is the **outermost** loop and that `main` calls it exactly once: `main` now calls it once **per voyage**. Per this repo's amend-by-addition convention (recorded in ADR-0021), ADR-0002 is not rewritten — it carries a pointer here. Touches **ADR-0009 (playtest distribution)**'s WASM reasoning in degree but not in kind (see Consequences). `cmd/headless` is unaffected, so ADR-0003 stands.

## Context

Issue #278 named the **Chart Table**: the one screen above a voyage — a title, *Begin a voyage*, *Quit*, and nothing else. The exe boots into it, and it is **stateless**: a voyage draws its own ending (Haven or a sinking), then hands back to a Chart Table unchanged from boot.

That collides with ADR-0002 as written. ADR-0002 makes `run_session` the *outermost* loop: `main` calls it exactly once, and every render loop lives *inside* the UI's blocking callbacks. A screen you return to when a voyage ends needs something that outlives `run_session` and calls it repeatedly — and there is nothing above `run_session` to be that thing.

The collision is real, but it is **narrower than it looks, and the narrowness is the finding.** ADR-0002 bought exactly one thing: the tick → dispatch → await → submit sequence is written once, so headless and UI cannot drift apart and quietly break the identical-run guarantee ghost-battle replay depends on. The Chart Table duplicates **none** of that sequence, because while it is on screen **there is no `Sim` at all** — #278 made it stateless and made it *precede* any voyage. It has no phase to await, no events to dispatch, nothing to tick. It cannot drift from `run_session`, because there is nothing for it to drift from.

So what ADR-0002 *decided* is untouched. What is falsified is only its **description of where `run_session` sits in the process**.

## Decision

### `main` gains an outer loop; `run_session` stays the voyage's driver

```odin
main :: proc() {
	if capture_requested() {
		capture_main()
		return
	}

	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Fantasy Ship Game")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	for chart_table_loop() == .Begin {
		run_voyage()
	}
}

// run_voyage is one voyage, boot to ending: its own Sim, its own Game_State, one
// run_session. Both die with the proc, so the next voyage starts from nothing.
run_voyage :: proc() {
	s := sim.sim_create(VOYAGE_SEED)
	defer sim.sim_destroy(&s)

	state := Game_State{}
	defer delete(state.visited)
	defer delete(state.positions)
	defer delete(state.voyage_map.nodes)

	input := sim.Input_Source{data = &state, get_captain_choice = get_captain_choice}
	sink := sim.Event_Sink{data = &state, dispatch = dispatch}

	sim.run_session(&s, input, sink)
}
```

`run_session` is not edited, not wrapped, and not re-entered mid-flight. It stops being the outermost thing *in the process*; it does not stop being the single driver loop. The window is initialised **above** the loop and outlives every voyage: one window per process, N voyages through it.

### The Chart Table is a blocking modal loop, but not a callback

Two of the shapes #279 put up for grilling turn out to answer different questions rather than compete.

- **A third `Input_Source`-style mode** is rejected outright. `get_captain_choice` is handed a `Phase` — *a `Sim`'s* phase — and answers with a `Command` *the `Sim` submits*. At the Chart Table there is no `Sim` to have a phase or to take a command. Adopting this shape means inventing a fake `Phase` and a fake `Command` for a screen that precedes the very thing they belong to.
- **"Another blocking modal loop, in the same family as `play_beat` and the `*_menu_loop`s"** is right about *how* and wrong about *where*. Those are all blocking modal loops **inside `run_session`'s callbacks**. The Chart Table uses the same technique in a different position: above `run_session`, in `main`, called by nothing but `main`. Same pattern, not the same family.

So the answer is both, and they do not conflict: **`main` gains the outer loop (where), and the Chart Table is a blocking modal render loop within it (how).**

### A voyage's state is per-voyage, not per-process

`main` today creates the `Sim` and the `Game_State` once and `defer`s their teardown to process exit — correct when a process is one voyage, wrong the moment it is N. Extracting `run_voyage` is what turns those `defer`s from per-process into per-voyage; that is the whole reason it is a proc rather than a loop body.

ADR-0010's run-scoped arena makes the `Sim` half free — `sim_destroy` reclaims every run-lifetime allocation wholesale. The `Game_State` half is the explicit deletes of `visited` / `positions` / `voyage_map.nodes` that already exist, just moved. **#278's stateless Chart Table is what makes this safe**: nothing is meant to survive a voyage, so there is nothing to carry over and nothing to reset.

### The seed becomes a per-voyage input, and stays `0`

`sim_create(seed)` moves inside the loop, so a seed is now something a voyage is **handed** rather than a constant the process picks once.

**What that seed should be is deliberately not decided here.** It is hardcoded `0` today, which already means every launch deals the identical map — a pre-existing wart this ADR neither creates nor fixes. The outer loop makes it *more visible* (two voyages back-to-back, identical) without making it new. Choosing a seeding policy is a game-design question with its own grilling to do, and it is not on the way to "Claude can build good UI" (#275). Note also that `--capture` and `cmd/headless` both *depend* on seed `0` for their scripted walks, so whatever policy eventually lands has to keep a fixed seed reachable.

### Closing the window quits the process; the Chart Table's fallback is `Quit`

This is the rule that stops the outer loop spinning forever, and it is load-bearing.

Every menu loop is `for !rl.WindowShouldClose()`, and on close each one returns a **fallback command** rather than propagating a quit — `travel_menu_loop` returns the first emitted option, "a legal move that winds the voyage down cleanly on quit." Closing the window therefore does not stop `run_session`; it makes it sprint to `Event_Voyage_Ended` on auto-answered decisions. **The process then exits only because `main` returns immediately afterward.** That is undocumented behaviour which works *precisely because* `run_session` was outermost — and the outer loop takes it away.

The fix is one rule: **the Chart Table's window-close fallback is `Quit`, never `Begin`.** `rl.WindowShouldClose()` latches — once the flag is set it stays true until `rl.SetWindowShouldClose(false)` clears it, and nothing does — so a close mid-voyage winds the voyage down, returns to `main`, and the Chart Table's loop sees the flag on its very first frame and answers `Quit`. The process exits, exactly as it does today. Had the fallback been `Begin`, it would start a voyage that instantly winds down, then start another, forever.

**ESC and X stay indistinguishable, and both quit.** raylib raises the same flag for the close button and for the ESC key, so no loop in the game can currently tell them apart. Making ESC mean "abandon this voyage, back to the Chart Table" while X means "quit the game" is a genuinely nicer game — and it is new plumbing through every voyage screen to distinguish "the captain bailed" from "the voyage ended". Voyage screens are out of #275's scope. Behaviour is therefore unchanged: ESC or X, anywhere, ends the process.

### Capture is unaffected, and the Chart Table must be built split

`capture_main` calls `run_session` directly and never enters the Chart Table's loop, so it keeps its own `main`-level entry (`--capture`) and needs no outer loop of its own. #278 established that the Chart Table is honestly photographed at **frame 0** — no voyage, no script, and none of the 75s of un-photographable beats #277 measured.

That only works if the Chart Table's **composition is split from its click-polling** — a `draw_chart_table(…)` that both the blocking loop and capture call — per #277's finding that a screen whose chrome is welded inside its poll loop cannot be photographed whole. The Chart Table is new, so it is built split from the start rather than retrofitted.

## Consequences

- **`cmd/headless` does not change.** It calls `run_session` directly, has no Chart Table, and never had a loop above it. ADR-0003's thin-adapter claim survives intact — this amendment touches exactly one `main`.
- **The WASM cost ADR-0009 knowingly paid moves in degree, not in kind.** ADR-0009 rejected web because a browser has no equivalent of a blocking call on the main thread, leaving only "invert `run_session` into a resumable state machine" (which undoes ADR-0002) or emscripten `-sASYNCIFY`. Both still apply, unchanged: the outer loop adds one more frame to a stack ASYNCIFY already has to unwind whole, and inverting `run_session` is neither easier nor harder for being called N times rather than once. Worth naming that the debt is entirely the *voyage's* — the Chart Table, a plain render loop over no `Sim`, is the one screen in the game that would port as-is.
- **A session is now N voyages, and each starts from nothing.** The invariant making that true is #278's stateless Chart Table. If meta-progression is ever built (`CONTEXT.md` records it as unspecified, and #278 named the Chart Table as where it would attach), it is precisely this ADR's per-voyage teardown that it must negotiate with — revisit this decision then rather than working around it.
- **The code's ADR-0002 references stay accurate.** `run_session.odin`, `sim.odin`, `menu.odin` and `capture.odin` cite ADR-0002 for the single-driver-loop, the blocking-modal-loop pattern, and the `Input_Source`/`Event_Sink` tables — none of them claim outermost-ness. That claim lives only in ADR-0002's prose, and only there is it amended.

See GitHub issues #275 (the effort's map), #278 (what the Chart Table is), #279 (this decision), and #277 (the capture seam and the welded-chrome finding). Amends ADR-0002; touches ADR-0009 (playtest distribution) in degree only; builds on ADR-0010's run-scoped arena; leaves ADR-0003 untouched.
