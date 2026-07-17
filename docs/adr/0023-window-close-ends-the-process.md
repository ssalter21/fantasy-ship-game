# ADR-0023: A window close ends the process; presentation cannot wind a voyage down

## Status

Accepted. **Amends ADR-0022's *Closing the window quits the process; the Chart Table's fallback is `Quit`* section — both its mechanism and its decision.** Everything else ADR-0022 decided stands untouched: `main` owns the loop above `run_session`, a session is N voyages, a voyage's state is per-voyage, the seed stays `0`, capture keeps its own entry, and the Chart Table is built split. Per this repo's amend-by-addition convention (ADR-0021), ADR-0022 is not rewritten — it carries a pointer here. Touches no other ADR's decision; ADR-0001's Command/Event boundary is what this ADR reasons *from*, not something it changes.

## Context

ADR-0022 asserted a mechanism and derived a rule from it. Issue [#290](https://github.com/ssalter21/fantasy-ship-game/issues/290) went to measure the mechanism and found the rule resting on a chain of three claims, none of which had been run.

**Claim 1 — "`rl.WindowShouldClose()` latches."** ADR-0022 said the flag stays true until `rl.SetWindowShouldClose(false)` clears it. #281 measured the opposite and called it *consume-on-read*: true on exactly one call, false after. **Both are wrong.** Probed against raylib 5.5: three back-to-back reads in one frame all return `true`; the first read after an `EndDrawing` returns `false`. The flag is neither latched nor consumed on read — raylib clears it in `EndDrawing`'s event poll, so it **survives exactly one frame**.

**Claim 2 — a close reaches only one loop.** #290 reasoned that the first loop to read the flag eats it, so the next loop reads `false` and blocks forever. It does not. Because a loop that sees the flag exits *without drawing*, no `EndDrawing` runs, so the flag stays true and **every** subsequent loop sees it. Probed directly (loop A sees the close and returns; loop B, with nothing drawn in between, sees it on iteration 0). The cascade ADR-0022 predicted is real.

**Claim 3 — the fallback "winds the voyage down cleanly on quit."** This is the one that matters, and it was never true. `travel_menu_loop`'s own comment said it, and ADR-0022 quoted it. But **presentation has no way to end a voyage.** ADR-0001's boundary gives it five Commands — `Travel_To`, `Battle_Choice`, `Choose_Option`, `Trade_Choice`, `Refit` — and none of them stops a voyage; a voyage ends only by reaching Haven or by sinking. Every close-fallback is therefore a legal *move*, which hands the Sim the next decision rather than winding anything down.

So the cascade runs, and the voyage never ends. Measured with a `WM_CLOSE` sent mid-voyage: **108,277 flag reads, 108,275 of them `travel_menu_loop`** — travel's fallback sails to the first legal neighbour, the Sim asks where to sail next, and the game wanders the map forever at ~11k decisions/sec. This is a **livelock, not a block**, and it reproduces on `main` at `fa12293`, before the Chart Table existed. Closing the window mid-voyage has never quit this game.

The falsified claim is the load-bearing one. ADR-0022's rule (the Chart Table's fallback is `Quit`, never `Begin`) is correct but irrelevant: control never reaches the Chart Table to use it.

## Decision

### A close is answered by ending the process, at one choke point

```odin
window_quit_if_closed :: proc() {
	if rl.IsWindowReady() && rl.WindowShouldClose() {
		os.exit(0)
	}
}
```

Every blocking render loop calls it once per frame, in place of testing `rl.WindowShouldClose()` in its `for` condition. It **exits rather than reports**, because exiting is the only thing presentation can do that actually stops: there is no Command for "this voyage is over", and inventing one is a game-design decision (it is most of ESC-as-abandon, which ADR-0022 ruled out and this ADR keeps out).

The `IsWindowReady` guard is load-bearing, not defensive: `rl.WindowShouldClose()` returns `true` when there is no window, so without it `odin test` would `exit(0)` mid-run and report success.

### No loop has a close-fallback any more

Every fallback is deleted — travel's first-emitted-option (and the assert propping it up), battle's `Hold`, the option list's decline, trade's reject, refit's finish. They were answers to a question no longer asked: a loop is now exited only by a player's choice, or not at all. Each loop becomes `for { window_quit_if_closed(); … }`.

### Closing and clicking *Quit* are different paths, deliberately

Clicking *Quit* returns `.Quit` to `main`, which falls out of its outer loop and runs every `defer` on the way out — `sim_destroy`, the `Game_State` deletes, `ui_fonts_unload`, `rl.CloseWindow`. Closing the window runs none of them. That asymmetry is accepted: the process is about to die and the OS reclaims all of it, and the clean path is still the one a player takes on purpose, so it stays exercised rather than rotting.

## Consequences

- **Closing the window mid-voyage now quits the game.** Verified against the real window with synthetic Win32 input: `WM_CLOSE` mid-voyage exits 0 where it previously livelocked. The X button working is new behaviour, not restored behaviour — ADR-0022 described it as already true, and it never was.
- **ESC and X stay indistinguishable, and both still quit** — unchanged from ADR-0022's ruling, except that they now quit *immediately* rather than auto-answering decisions forever. ESC-as-abandon remains out of scope and is now the *only* thing a "quit requested" Command would buy.
- **`Chart_Table_Choice.Quit` stays the zero value, for a weaker reason.** ADR-0022 called the ordering load-bearing because a close arrived as a fallback; a close no longer arrives as a value at all. Both variants now mean a deliberate click, and the ordering is left as a safe default rather than a rule.
- **This is the second time this map's ADR asserted an unmeasured mechanism** (`rl.WindowShouldClose` in ADR-0022, and #290's own re-diagnosis of it). Both survived review because they were plausible and cheap to believe. The probes that settled it took minutes; `.claude/skills/run-game/SKILL.md` records the technique and now records the corrected behaviour.
- **ADR-0009's playtest build gets a working close.** A tester who closes the window mid-voyage got a process that never exited; that was live in every playtest build shipped to date.
- **`cmd/headless` is untouched** — it links no raylib and has no loop of this kind. ADR-0003 stands.

See GitHub issues [#275](https://github.com/ssalter21/fantasy-ship-game/issues/275) (the effort's map), [#290](https://github.com/ssalter21/fantasy-ship-game/issues/290) (this decision), [#281](https://github.com/ssalter21/fantasy-ship-game/issues/281) (which measured the flag while building the Chart Table), and [#279](https://github.com/ssalter21/fantasy-ship-game/issues/279)/ADR-0022 (the decision amended here). Reasons from ADR-0001's Command/Event boundary; leaves ADR-0002, ADR-0003 and ADR-0010 untouched.
