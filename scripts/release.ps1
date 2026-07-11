#Requires -Version 5.1
<#
.SYNOPSIS
    One-command local release build of the game, then push to itch.io.

.DESCRIPTION
    Compiles cmd/game release-optimized (-o:speed) and windowed
    (-subsystem:windows, so no console window flashes up for testers), stamps
    it with the current git short SHA via issue #44's GIT_SHA define, drops a
    runnable game.exe into dist/, and pushes that dist/ to the private itch.io
    project's Windows channel via butler (issue #46).

    The SHA carries a -dirty suffix whenever the working tree has uncommitted
    changes, so the stamp never misrepresents the shipped code. The same stamp
    is fed to butler as --userversion, so an itch build's version matches the
    exe's on-screen stamp exactly.

    Only the game is shipped -- cmd/headless is never built here.

    Self-containment: Odin's vendor:raylib links statically on Windows, so the
    produced exe needs no raylib DLL beside it (verified: launches from a folder
    containing only game.exe). There is therefore no DLL to bundle into dist/.

    One-time human setup (private itch project, butler login, per-friend
    download keys, SmartScreen note) is documented in docs/distribution.md.

.PARAMETER OutDir
    Output directory for the build, relative to the repo root. Defaults to dist.

.PARAMETER ItchTarget
    The butler push target in <user>/<project> form (channel is appended
    automatically). Defaults to the ITCH_TARGET environment variable so the
    private itch slug stays out of version control. Ignored with -SkipPush.

.PARAMETER SkipPush
    Build the local artifact only; do not push to itch. Use for local
    iteration when you don't want to publish.

.EXAMPLE
    scripts/release.ps1
    Builds dist/game.exe and pushes it to $env:ITCH_TARGET's windows channel.

.EXAMPLE
    scripts/release.ps1 -SkipPush
    Builds dist/game.exe stamped with the current commit, no publish.

.EXAMPLE
    scripts/release.ps1 -ItchTarget yourname/fantasy-ship-game
    Builds and pushes to an explicit itch target.
#>
[CmdletBinding()]
param(
    [string]$OutDir = 'dist',
    [string]$ItchTarget = $env:ITCH_TARGET,
    [switch]$SkipPush
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The itch channel we publish to. Single self-contained Windows exe (see #43).
$Channel = 'windows'

# scripts/release.ps1 -> repo root is one level up from the script directory,
# so the build works regardless of the caller's current directory.
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    # 1. Compute the build stamp: current short SHA, plus a -dirty suffix when
    #    the working tree has uncommitted (tracked or untracked) changes.
    $sha = (git rev-parse --short HEAD).Trim()
    if (git status --porcelain) { $sha = "$sha-dirty" }

    # 2. Validate publish preconditions before the expensive build, so a missing
    #    butler / unset target fails fast rather than after a full -o:speed build.
    if (-not $SkipPush) {
        if (-not (Get-Command butler -ErrorAction SilentlyContinue)) {
            throw "butler is not installed or not on PATH. Install it and run 'butler login' (see docs/distribution.md), or re-run with -SkipPush."
        }
        if ([string]::IsNullOrWhiteSpace($ItchTarget)) {
            throw "No itch target. Set the ITCH_TARGET environment variable (e.g. yourname/fantasy-ship-game) or pass -ItchTarget, or re-run with -SkipPush. See docs/distribution.md."
        }
    }

    # 3. Prepare the output directory and target path.
    $dist = Join-Path $RepoRoot $OutDir
    New-Item -ItemType Directory -Force $dist | Out-Null
    $exe = Join-Path $dist 'game.exe'

    # 4. Build the game: release optimization, no console window, SHA-stamped.
    Write-Host "Building cmd/game -> $exe  (GIT_SHA=$sha)"
    & odin build cmd/game -out:$exe -o:speed -subsystem:windows -define:GIT_SHA=$sha
    if ($LASTEXITCODE -ne 0) { throw "odin build failed (exit $LASTEXITCODE)" }

    Write-Host "Release build ready: $exe"

    # 5. Publish: push dist/ to the itch project's Windows channel, tagged with
    #    the same SHA stamp as --userversion. Skippable for local-only builds.
    if ($SkipPush) {
        Write-Host "Skipping itch push (-SkipPush)."
        return
    }

    if ($sha -like '*-dirty') {
        Write-Warning "Pushing a -dirty build ($sha): the itch version will not map to a clean commit."
    }

    $pushTarget = "${ItchTarget}:$Channel"
    Write-Host "Pushing $dist -> $pushTarget  (--userversion $sha)"
    & butler push $dist $pushTarget --userversion $sha
    if ($LASTEXITCODE -ne 0) { throw "butler push failed (exit $LASTEXITCODE)" }

    Write-Host "Published $sha to $pushTarget"
} finally {
    Pop-Location
}
