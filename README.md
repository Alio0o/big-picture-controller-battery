# Big Picture Controller Battery

A [Millennium](https://steambrew.app) plugin for Steam on Windows.

- Shows your Bluetooth controller's battery level next to the clock in Steam Big Picture and in the in-game overlay.
- Hold the Menu button in a game to open the Steam overlay. This is on by default and can be turned off.

## Why the overlay shortcut

If you leave the Xbox button to Windows Game Bar, Steam's overlay has no controller button anymore. Steam Input can map one per game, but there is no global setting. This plugin adds one: hold Menu (or View) for a moment in any game, and the overlay opens. Hold it again to close it.

A short press still goes to the game as normal. Turn it off in the plugin settings if you don't want it.

## Requirements

- Windows 10 or 11
- Steam with [Millennium](https://steambrew.app) installed
- Battery: a controller connected over Bluetooth that reports its battery to Windows. Tested with the Xbox Wireless Controller.
- Shortcut: an Xbox-style (XInput) controller, connected in any way

## Install

1. Download `big-picture-controller-battery.star` and `install.cmd` from the [latest release](../../releases/latest) into the same folder.
2. Close Steam.
3. Double-click `install.cmd`. It finds Steam's Millennium plugins folder and copies the plugin there. It stops if Steam is still running.
   - Or copy the `.star` file yourself into Steam's Millennium plugins folder, usually `C:\Program Files (x86)\Steam\millennium\plugins\`.
4. Start Steam. In desktop mode, open Millennium > Plugins, turn on **Big Picture Controller Battery**, and press Save Changes.

When building from source, `install.cmd` in the repository installs `dist\big-picture-controller-battery.star`.

To remove it, turn it off in the same list and delete the file. The plugin leaves nothing else behind; its settings are stored by Millennium.

## Xbox mode (optional extra step)

If you start Steam through Windows' Xbox mode (full screen experience), the overlay shortcut does nothing until the desktop has been shown once. The battery badge is not affected.

Why: in Xbox mode, Windows gives controller input to programs in the background only if they are on its allow list (`HKLM\SOFTWARE\Microsoft\GameInput`, value `BackgroundInput`). Steam is on it. The plugin runs inside Millennium's plugin host, `millennium.luavm64.exe`, which is not. Everyone else gets a blank controller.

Fix: download `xbox-mode-access.cmd` from the [latest release](../../releases/latest) and double-click it once (or right-click > Run as administrator). It needs administrator rights and asks for them itself, then adds `millennium.luavm64.exe` to that list and keeps the other entries. Then start Xbox mode again.

To undo it, run `xbox-mode-access.cmd remove` from a terminal.

## Settings

Desktop Steam > Millennium > Plugins > Big Picture Controller Battery.

| Setting | Default | |
|---|---|---|
| Hold to open Steam overlay | On | Turns the shortcut on or off |
| Hold time | 600 ms | 200 to 2000 ms |
| Button | Menu | Menu or View |
| Overlay keys | Shift+Tab | Must match Steam > Settings > In Game > Overlay shortcut keys |

Changes apply right away.

## What it does on your PC

Everything runs inside the plugin itself, through Millennium's Lua backend. There is no extra program, background service, script, or startup entry, and no network access. The only exception is the optional `xbox-mode-access.cmd` above, which you run yourself.

- **Battery:** reads the battery level that Windows already keeps for paired Bluetooth devices (the number Windows Settings shows), using the Windows Configuration Manager API (`cfgmgr32.dll`). It reads devices whose name contains "Controller" or "Gamepad". Nothing is sent to the controller.
- **Controller buttons:** reads the controller through XInput (`xinput1_4.dll`) about 25 times a second, only while a game is running and a controller is connected.
- **Overlay shortcut:** when the button has been held long enough, it sends the overlay key combination with `SendInput`, as if typed on a keyboard. It does nothing when Steam itself is in front.

All Windows calls are declared in [`backend/win32.lua`](backend/win32.lua).

## Known limits

- Battery only for Bluetooth controllers that report it to Windows. Controllers on the Xbox Wireless Adapter or a cable show no badge.
- No charging indicator; Windows does not report charging for these devices.
- The game also receives the Menu press, so its pause menu may open behind the overlay.
- Windows blocks simulated keys to games running as administrator, and some anti-cheat games ignore them.
- Only tested on one PC so far (Windows 11, Steam Beta, Millennium 3.5.0, Xbox Wireless Controller over Bluetooth). Reports from other setups are welcome.

## Build from source

Requires [Node.js](https://nodejs.org) 18 or newer.

```
npm install
npm run build
```

The plugin is written to `dist/big-picture-controller-battery.star`. `npm run typecheck` checks the frontend. With [LuaJIT](https://luajit.org) on Windows, `luajit tools/check-backend.lua` runs the backend checks against your real controller.

## License

[MIT](LICENSE)
