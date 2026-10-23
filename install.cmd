@echo off
setlocal EnableDelayedExpansion
rem Copies couch-mode.star into Steam's Millennium plugins folder.
rem Double-click it with Steam closed. It looks for the .star file next to this
rem script first, then in dist\ (after "npm run build").

set "PLUGIN=couch-mode.star"
set "SOURCE=%~dp0%PLUGIN%"
if not exist "%SOURCE%" set "SOURCE=%~dp0dist\%PLUGIN%"
if not exist "%SOURCE%" (
    echo Could not find %PLUGIN% next to this script or in dist\.
    goto :fail
)

rem Steam writes its install folder to the registry.
set "STEAM="
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul ^| find "SteamPath"') do set "STEAM=%%B"
if not defined STEAM (
    echo Steam does not seem to be installed.
    goto :fail
)
set "STEAM=%STEAM:/=\%"
set "TARGET=%STEAM%\millennium\plugins"
if not exist "%TARGET%" (
    echo Millennium is not installed: !TARGET! does not exist.
    echo Install Millennium from https://steambrew.app first.
    goto :fail
)

tasklist /fi "imagename eq steam.exe" 2>nul | find /i "steam.exe" >nul
if not errorlevel 1 (
    echo Steam is running. Close Steam completely, then run this again.
    goto :fail
)

copy /y "%SOURCE%" "%TARGET%\%PLUGIN%" >nul
if errorlevel 1 (
    echo Copy failed. Try running this as administrator.
    goto :fail
)

echo Installed to %TARGET%\%PLUGIN%

rem Before 3.0 the plugin was called Big Picture Controller Battery. Two copies
rem would both read the controller, so the old file goes. Couch Mode copies
rem its settings over on first start.
set "OLD=%TARGET%\big-picture-controller-battery.star"
if exist "%OLD%" (
    del /f /q "%OLD%" >nul 2>&1
    if exist "!OLD!" (
        echo Could not remove the old big-picture-controller-battery.star. Delete it yourself.
    ) else (
        echo Removed the old big-picture-controller-battery.star.
    )
)
echo.
echo Start Steam. If this is the first install, open Millennium ^> Plugins in
echo desktop Steam, turn on Couch Mode and press Save Changes.
echo.
pause
exit /b 0

:fail
echo.
pause
exit /b 1
