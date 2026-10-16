@echo off
setlocal
rem Optional, for Windows Xbox mode (full screen experience) only.
rem Does the same as the "Xbox mode controller access" button on the plugin's
rem settings page: lets Millennium's plugin host read the controller while a
rem game is in front, so the overlay shortcut works in Xbox mode.
rem
rem   xbox-mode-access.cmd           turn it on
rem   xbox-mode-access.cmd remove    turn it off
rem
rem Needs administrator rights (the setting is in HKLM) and asks for them.

set "KEY=HKLM\SOFTWARE\Microsoft\GameInputRedist\Exe\millennium.luavm64.exe"

fltmc >nul 2>&1
if errorlevel 1 (
    echo Asking Windows for administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
    exit /b
)

if /i "%~1"=="remove" (
    reg delete "%KEY%" /f >nul 2>&1
    echo Xbox mode controller access is off.
) else (
    reg add "%KEY%" /v BackgroundInput /t REG_DWORD /d 1 /f >nul || (echo Could not change the setting. & goto :done)
    echo Xbox mode controller access is on. Start Xbox mode again if it is running.
)

:done
echo.
pause
