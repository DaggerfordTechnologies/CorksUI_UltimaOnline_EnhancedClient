@echo off
title Corks' UOAM Bridge
rem Runs the bridge from this folder. Extra arguments (e.g. --verbose) are passed on.
where py >nul 2>nul
if %errorlevel%==0 (
    py "%~dp0uoam_bridge.py" %*
) else (
    python "%~dp0uoam_bridge.py" %*
)
echo.
echo The bridge has stopped.
pause
