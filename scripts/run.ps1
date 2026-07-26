#Requires -Version 5.1
<#
.SYNOPSIS
    Build and launch the game locally with `odin run`.

.DESCRIPTION
    Convenience wrapper for local playtesting: compiles and runs cmd/game (the
    raylib UI executable) in one step from anywhere, resolving the repo root
    relative to this script so the caller's current directory doesn't matter.

    Unlike scripts/release.ps1 this is an unoptimized debug run with a console
    window -- it is for iterating locally, not for cutting a shippable build.

    Pass -Headless to run cmd/headless (the no-rendering executable) instead,
    or -Forge to run cmd/forge (the content authoring tool). Any extra arguments
    after -- are forwarded to the built program.

.PARAMETER Headless
    Run cmd/headless (scripted/seeded simulation, no window) instead of the UI
    game.

.PARAMETER Forge
    Run cmd/forge (the item and encounter authoring tool) instead of the game.

.EXAMPLE
    scripts/run.ps1
    Builds and launches the raylib UI game.

.EXAMPLE
    scripts/run.ps1 -Headless
    Builds and runs the headless simulation executable.

.EXAMPLE
    scripts/run.ps1 -Forge
    Builds and launches the Forge, the content authoring tool.
#>
[CmdletBinding()]
param(
    [switch]$Headless,
    [switch]$Forge,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ProgramArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# scripts/run.ps1 -> repo root is one level up from the script directory, so the
# run works regardless of the caller's current directory.
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    if ($Headless -and $Forge) { throw 'pass at most one of -Headless and -Forge' }
    $pkg = if ($Headless) { 'cmd/headless' } elseif ($Forge) { 'cmd/forge' } else { 'cmd/game' }

    Write-Host "Running $pkg (odin run)"
    if ($ProgramArgs) {
        & odin run $pkg -- @ProgramArgs
    } else {
        & odin run $pkg
    }
    if ($LASTEXITCODE -ne 0) { throw "odin run failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}
