@echo off
rem Build and launch the game with `odin run` -- double-clickable on Windows.
rem
rem Unlike run.ps1, a .cmd file executes directly from Explorer (double-click)
rem and from cmd.exe without any execution-policy prompt. Resolves the repo root
rem from the script's own location (%~dp0 = scripts\, so .. is the repo root) so
rem it works regardless of where it's launched from.
rem
rem   run.cmd            builds and launches cmd/game (the raylib UI)
rem   run.cmd -Headless  builds and runs cmd/headless (no window)

setlocal
pushd "%~dp0.."

if /I "%~1"=="-Headless" (
    odin run cmd/headless
) else (
    odin run cmd/game
)
set EXITCODE=%ERRORLEVEL%

popd
rem Keep the console open on failure so a double-click user can read the error.
if not "%EXITCODE%"=="0" (
    echo.
    echo odin run failed with exit code %EXITCODE%.
    pause
)
endlocal
