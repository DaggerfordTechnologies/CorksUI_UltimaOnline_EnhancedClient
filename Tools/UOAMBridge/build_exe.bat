@echo off
rem Builds CorksUOAMBridge.exe (the bridge with Python built in) into this folder.
rem Needs Python 3.8+; PyInstaller is installed into a temporary folder, not your Python.
setlocal
set "HERE=%~dp0"
set "WORK=%TEMP%\CorksUOAMBridgeBuild"
where py >nul 2>nul && (set "PY=py -3") || (set "PY=python")

if not exist "%WORK%\venv\Scripts\python.exe" (
    echo Setting up PyInstaller in %WORK% ...
    %PY% -m venv "%WORK%\venv" || goto failed
    "%WORK%\venv\Scripts\python.exe" -m pip install --disable-pip-version-check -q pyinstaller || goto failed
)

"%WORK%\venv\Scripts\python.exe" -m PyInstaller --onefile --console --name CorksUOAMBridge ^
    --distpath "%HERE%." --workpath "%WORK%\work" --specpath "%WORK%" --paths "%HERE%." ^
    --noconfirm --log-level WARN "%HERE%uoam_bridge.py" || goto failed
if exist "%HERE%__pycache__" rmdir /s /q "%HERE%__pycache__"
echo.
echo Built %HERE%CorksUOAMBridge.exe
pause
exit /b 0

:failed
echo.
echo The build failed.
pause
exit /b 1
