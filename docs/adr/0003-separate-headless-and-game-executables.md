# Separate `headless` and `game` executables, not one binary with a flag

The rendering library hadn't been chosen yet (a separate open question) when this was decided, and we wanted headless tests/simulation to never depend on that choice — including never needing a windowing system or GPU driver present, since raylib/SDL/sokol-style init can behave unpredictably on headless CI runners even when render is never called.

We considered a single executable with a runtime `--headless` flag that skips window/renderer init and swaps in a no-op event sink. We rejected it because the guarantee "headless never touches rendering" would only hold by convention — a runtime branch that happens to skip a call, not something the compiler enforces. A bug that let a rendering-dependent call leak into the "headless" branch would only surface at runtime, if at all.

Instead, `cmd/headless/main.odin` and `cmd/game/main.odin` are two separate `main` packages, both importing the shared core/Sim package and calling `run_session` with mode-appropriate `Input_Source`/`Event_Sink` implementations. Only `cmd/game` imports the rendering library — Odin's package import graph makes the decoupling a compile-time fact, not a runtime discipline. Because `run_session` already holds all the shared loop logic (see ADR-0002), each `main.odin` is a thin adapter, so splitting doesn't create an ongoing maintenance burden.

See GitHub issue #3 for the full design discussion.
