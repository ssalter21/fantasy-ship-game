@echo off
rem Build and launch the Forge (the content authoring tool) -- double-clickable
rem on Windows.
rem
rem run.cmd already knows how to do this, but only when handed -Forge; a double
rem click from Explorer passes no arguments at all. This file exists so the Forge
rem has an entry point you can double click, and it forwards to run.cmd so the
rem build command itself stays in one place.

setlocal
call "%~dp0run.cmd" -Forge
endlocal
