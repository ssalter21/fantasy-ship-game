#Requires -Version 5.1
<#
.SYNOPSIS
    One-command local release build of the game executable.

.DESCRIPTION
    Compiles cmd/game release-optimized (-o:speed) and windowed
    (-subsystem:windows, so no console window flashes up for testers), stamps
    it with the current git short SHA via issue #44's GIT_SHA define, and drops
    a runnable game.exe into dist/.

    The SHA carries a -dirty suffix whenever the working tree has uncommitted
    changes, so the stamp never misrepresents the shipped code.

    Only the game is shipped -- cmd/headless is never built here.

    Self-containment: Odin's vendor:raylib links statically on Windows, so the
    produced exe needs no raylib DLL beside it (verified: launches from a folder
    containing only game.exe). There is therefore no DLL to bundle into dist/.

    This script stops at producing a correct local artifact; publishing it (e.g.
    to itch) is a separate step.

.PARAMETER OutDir
    Output directory for the build, relative to the repo root. Defaults to dist.

.EXAMPLE
    scripts/release.ps1
    Builds dist/game.exe stamped with the current commit.
#>
[CmdletBinding()]
param(
    [string]$OutDir = 'dist'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# scripts/release.ps1 -> repo root is one level up from the script directory,
# so the build works regardless of the caller's current directory.
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    # 1. Compute the build stamp: current short SHA, plus a -dirty suffix when
    #    the working tree has uncommitted (tracked or untracked) changes.
    $sha = (git rev-parse --short HEAD).Trim()
    if (git status --porcelain) { $sha = "$sha-dirty" }

    # 2. Prepare the output directory and target path.
    $dist = Join-Path $RepoRoot $OutDir
    New-Item -ItemType Directory -Force $dist | Out-Null
    $exe = Join-Path $dist 'game.exe'

    # 3. Build the game: release optimization, no console window, SHA-stamped.
    Write-Host "Building cmd/game -> $exe  (GIT_SHA=$sha)"
    & odin build cmd/game -out:$exe -o:speed -subsystem:windows -define:GIT_SHA=$sha
    if ($LASTEXITCODE -ne 0) { throw "odin build failed (exit $LASTEXITCODE)" }

    Write-Host "Release build ready: $exe"
} finally {
    Pop-Location
}
