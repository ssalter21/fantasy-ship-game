# ADR-0009: Playtest distribution — native Windows build via private itch.io

## Status

Accepted

## Context

Issue #43 asked for an easy, repeatable way to put Windows builds of the game in front of a couple of friends and keep updating them as development continues, without building any of the heavier machinery (CI, code signing, cross-platform builds, in-game feedback capture) a wider release would eventually need. The tracking issue broke this into a build-and-stamp step (#44), a local release script (#45), and itch.io push plus an end-to-end smoke test (#46) — all of which shipped before this ADR was written, so this ADR records the decision and rationale after the fact, and points at the runbook that describes what actually shipped.

The distribution channel question directly runs into ADR-0002: that ADR committed the project to a single blocking `run_session` driver loop, with the UI's `Input_Source`/`Event_Sink` implementations blocking on their own nested render loop until an animation finishes or the player acts. Any web/WASM distribution option has to reckon with that loop shape, since a browser has no equivalent of a blocking call on the main thread.

## Decision

**Channel.** A native, self-contained Windows `game.exe` (release-optimized, windowed — no console flash), distributed through a **private** itch.io project. Friends receive a per-friend download-key link rather than a public page, so nothing is publicly listed while still being trivially shareable. itch → Steam is the well-trodden indie path, so nothing here is wasted toward an eventual Steam release.

**Pipeline.** One local PowerShell script (`scripts/release.ps1`) builds and pushes a release in a single command. No CI — a single dev machine cutting builds by hand is sufficient at this scale and avoids standing up build infrastructure for a two-or-three-tester audience.

**Versioning and feedback.** The exe bakes in a git short-SHA (issue #44), drawn on-screen and passed to `butler push --userversion`, so the itch build version and the in-game stamp always match and never lie about what's running. This is also the whole feedback loop: testers give informal feedback (whatever chat channel is already in use) and only need to quote the on-screen stamp; the maintainer triages that feedback into GitHub issues by hand. No in-game feedback capture is built.

**Why web/WASM was rejected.** raylib does support a web/WASM target, but per the loop conflict noted in Context, running `run_session` in WASM would mean either inverting it into a non-blocking, resumable state machine (undoing the whole point of ADR-0002, which chose one blocking loop specifically to avoid two loop implementations drifting apart) or compiling through emscripten's `-sASYNCIFY`, which carries real size and performance cost and its own class of bugs. Web distribution is also not on the path to the eventual Steam release this pipeline is built toward. It's deferred as an optional future channel, to be taken on knowingly if ever, not ruled out permanently.

**Runbook.** The full runbook — one-time itch.io/butler setup, the one command to cut and push a build, and the tester's install/run steps (including the Windows SmartScreen "More info → Run anyway" path for the unsigned exe) — lives in [`docs/distribution.md`](../distribution.md) rather than duplicated here, so there is exactly one place to keep it current as the pipeline evolves. That doc was written and proven against the smoke test in issue #46: pushing the placeholder build, downloading it via a per-friend key from a non-dev machine, and reading the in-game git-SHA stamp back to confirm the exe is genuinely self-contained.

**Out of scope (deliberate).** Code signing (testers use the unsigned-exe SmartScreen path), Mac/Linux builds (all current testers are on Windows), CI/GitHub Actions automation, in-game feedback capture, and auto-update beyond what the itch app already provides. All of these are cheap to add later without reworking this pipeline; none were needed to get a build into a friend's hands.

## Consequences

- Cutting a playtest build is one command (`scripts/release.ps1`) from a dev machine; no CI pipeline exists or is needed at this scale.
- The on-screen git-SHA stamp is the entire version-tracking and bug-report mechanism — testers never need to know a build number, only to read and quote what's already on screen.
- Web/WASM distribution remains unbuilt and would require either an architectural change to `run_session` (revisiting ADR-0002) or an emscripten ASYNCIFY build, so it stays a deferred, knowingly-paid-for option rather than a near-term addition.
- Because the itch project is restricted/private with per-friend keys, adding or removing a tester is an itch.io dashboard action, not a code or script change.
- Code signing, cross-platform builds, and CI remain explicit, undesigned gaps — expected to be picked up only if the tester pool or platform mix grows beyond a couple of Windows-using friends.

See GitHub issues #43, #44, #45, #46, and #47 for the full design discussion.
