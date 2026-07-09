# One shared `run_session` driver loop; UI nests its own render loop inside it

We needed headless and UI modes to drive the Sim through the same sequence (Tick → dispatch events → await/submit a decision → Tick again) without duplicating that loop, since drift between two hand-written copies would quietly break the "identical run in either mode" guarantee that ghost-battle replay depends on.

We considered giving the UI its own top-level 60fps render loop that non-blockingly "pumps" the Sim forward once per frame, with headless keeping a separate tight loop. We rejected this because it reintroduces two loop implementations — just one level up from where the split was — and the UI's `Sim`-pumping logic would need to reimplement the same tick/await/submit sequencing `run_session` already handles.

Instead, `run_session(sim, input, sink)` is the single driver loop, used by both modes via a proc-pointer-table style `Input_Source`/`Event_Sink` (Odin has no interfaces). Headless mode's `Input_Source`/`Event_Sink` return instantly, so `run_session` spins through an entire run near-instantly. UI mode's implementations are blocking calls that internally run their own nested render loop — poll input, draw a frame, repeat — until an animation finishes or the player clicks, then return control to `run_session`. This is the standard "blocking modal loop" pattern in immediate-mode/raylib-style code, and it means there really is exactly one driver loop, not two loops kept in sync by convention.

This is surprising on first read because it inverts the usual "game owns a 60fps frame loop, and the simulation is pumped from inside it" shape — here the Sim's driver loop is outermost, and real-time rendering lives *inside* the UI's callback implementations instead.

See GitHub issue #3 for the full design discussion.
