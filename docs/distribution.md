# Playtest distribution (itch.io private)

How a Windows `game.exe` gets from this repo into a friend's hands, and how to
prove the whole path works. Background and decisions: GitHub issues #43 and #46.

The delivery model: one local command (`scripts/release.ps1`) builds a
release, SHA-stamped `game.exe` and `butler push`es it to a **private** itch.io
project. Friends open a per-friend download-key link, run the exe, and quote the
on-screen git-SHA stamp when they report anything.

## One-time human setup

These steps are done once, by hand, on the dev machine. They can't be scripted
because they involve an itch.io account, an auth login, and per-person keys.

1. **Create the itch.io project — restricted/private.**
   On itch.io, create a new project for the game. Under _Visibility & access_,
   set it to **Restricted** so it is **not publicly listed** but still serves
   builds to holders of a download key. (Avoid _Draft_: a draft page behaves
   differently for key-based access.) Note the project URL:
   `https://<user>.itch.io/<project>`. The butler target is `<user>/<project>`.

2. **Install and authenticate butler.**
   `butler` is itch.io's command-line upload tool. Install it (via the itch app,
   or the standalone download), make sure it is on `PATH`, then:

   ```powershell
   butler login
   ```

   This opens a browser once to authorize the machine; the credential is cached
   for future pushes. Verify with `butler status <user>/<project>`.

3. **Point the release script at your project.**
   The private itch slug is kept out of version control. Set it once, per
   machine, as an environment variable:

   ```powershell
   setx ITCH_TARGET "yourname/fantasy-ship-game"
   ```

   (Open a new shell after `setx` so it takes effect. Alternatively pass
   `-ItchTarget yourname/fantasy-ship-game` to the script each time.)

4. **Generate a per-friend download key.**
   In the itch project's _Distribute → Download keys_ section, create a key per
   tester. This yields a private link (`.../<project>?download_key=…`) that
   serves the latest pushed build without making the page public. Send each
   friend their own link.

## Cutting and pushing a release

Once setup is done, publishing a build is one command from the repo root:

```powershell
scripts/release.ps1
```

This:

1. Computes the git short SHA (`-dirty` suffix if the tree has uncommitted
   changes) — the same stamp #44 bakes into the exe and draws on-screen.
2. Builds `cmd/game` release-optimized and windowed into `dist/game.exe`.
3. Pushes `dist/` to `<ITCH_TARGET>:windows` with `--userversion <sha>`, so the
   itch build's version matches the exe's on-screen stamp exactly.

`scripts/release.ps1 -SkipPush` builds the local artifact only (no publish),
for local iteration.

## Smoke test (prove the path end-to-end)

The point of building this pipeline on the current placeholder build is to
separate "does delivery work?" from "is the game good?". Run this once to prove
delivery:

1. Push the current placeholder build: `scripts/release.ps1`.
2. On a machine/account that is **not** the dev's (a friend's machine, or a
   second account), open the per-friend **download-key** link and download the
   build.
3. Run `game.exe`. Windows SmartScreen will warn on the unsigned exe:
   **"Windows protected your PC" → More info → Run anyway.** This is the
   expected, documented install step for testers (no code signing — see #43).
4. Read the on-screen **git-SHA stamp** in the corner of the window and confirm
   it matches the SHA the script pushed. This confirms the exe is genuinely
   self-contained off the dev machine (no stray DLL dependency) and that the
   version friends see maps back to an exact commit.

When testers report anything, they only need to quote that on-screen stamp.
