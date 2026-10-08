@echo off
setlocal EnableDelayedExpansion
rem Optional, for Windows Xbox mode (full screen experience) only.
rem In Xbox mode, Windows gives controller input to background programs only
rem when they are on its GameInput "BackgroundInput" list. Steam is on it;
rem Millennium's plugin host (millennium.luavm64.exe) is not, so the overlay
rem shortcut never sees the button. This adds it to that list.
rem
rem   xbox-mode-access.cmd           add the entry
rem   xbox-mode-access.cmd remove    take it out again
rem
rem Needs administrator rights once (the list is in HKLM). Other entries on
rem the list are kept as they are.

set "KEY=HKLM\SOFTWARE\Microsoft\GameInput"
set "NAME=BackgroundInput"
set "EXE=millennium.luavm64.exe"

fltmc >nul 2>&1
if errorlevel 1 (
    echo Asking Windows for administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
    exit /b
)

set "VALUE="
for /f "tokens=2,*" %%A in ('reg query "%KEY%" /v %NAME% 2^>nul ^| findstr /c:"REG_MULTI_SZ"') do set "VALUE=%%B"
set "WRAPPED=\0!VALUE!\0"
set "PRESENT=0"
if /i not "!WRAPPED:\0%EXE%\0=!"=="!WRAPPED!" set "PRESENT=1"

if /i "%~1"=="remove" (
    if "!PRESENT!"=="0" (
        echo %EXE% is not on the list. Nothing to do.
        goto :done
    )
    set "NEW=!WRAPPED:\0%EXE%\0=\0!"
    if "!NEW!"=="\0" (set "NEW=") else set "NEW=!NEW:~2,-2!"
    reg add "%KEY%" /v %NAME% /t REG_MULTI_SZ /d "!NEW!" /f >nul || goto :fail
    echo Removed %EXE% from the list.
    goto :done
)

if "!PRESENT!"=="1" (
    echo %EXE% is already on the list. Nothing to do.
    goto :done
)
if defined VALUE (set "NEW=!VALUE!\0%EXE%") else set "NEW=%EXE%"
reg add "%KEY%" /v %NAME% /t REG_MULTI_SZ /d "!NEW!" /f >nul || goto :fail
echo Added %EXE%. The overlay shortcut now works in Xbox mode.
echo Start Xbox mode again (or restart Steam) if it is already running.
goto :done

:fail
echo Could not change %KEY%.
:done
echo.
echo List now:
reg query "%KEY%" /v %NAME% 2>nul | findstr /c:"REG_MULTI_SZ"
pause
