# Couch Mode

A [Millennium](https://steambrew.app) plugin for Steam on Windows that makes Big Picture feel more like a console.

- **Controller battery:** shows your Bluetooth controller's battery level next to the clock in Steam Big Picture and in the in-game overlay.
- **Hold for overlay:** hold the Menu button in a game to open the Steam overlay.
- **Game mute:** the game goes quiet while the Steam overlay is open, and its sound comes back when the overlay closes.
- **Music:** your own music plays everywhere in Big Picture, menus included. It fades out on the store, while a trailer or video plays, while a game runs, and when another program is in front. It can also play in the game overlay while the game is muted.

Each one can be turned on or off in the plugin settings. Music is off until you turn it on.

Couch Mode was called Big Picture Controller Battery before version 3.0.

## Why the overlay shortcut

If you leave the Xbox button to Windows Game Bar, Steam's overlay has no controller button anymore. Steam Input can map one per game, but there is no global setting. This plugin adds one: hold Menu (or View) for a moment in any game, and the overlay opens. Hold it again to close it.

A short press still goes to the game as normal. Turn it off in the plugin settings if you don't want it.

## Requirements

- Windows 10 or 11
- Steam with [Millennium](https://steambrew.app) installed
- Battery: a controller connected over Bluetooth that reports its battery to Windows. Tested with the Xbox Wireless Controller.
- Shortcut: an Xbox-style (XInput) controller, connected in any way

## Install

1. Download `couch-mode.star` and `install.cmd` from the [latest release](../../releases/latest) into the same folder.
2. Close Steam.
3. Double-click `install.cmd`. It finds Steam's Millennium plugins folder and copies the plugin there. It stops if Steam is still running.
   - Or copy the `.star` file yourself into Steam's Millennium plugins folder, usually `C:\Program Files (x86)\Steam\millennium\plugins\`.
4. Start Steam. In desktop mode, open Millennium > Plugins, turn on **Couch Mode**, and press Save Changes.

Coming from Big Picture Controller Battery: `install.cmd` removes the old `big-picture-controller-battery.star`, and Couch Mode copies its settings on first start. If you copy the file yourself, delete the old one. Turn on Couch Mode in the plugin list once, as it is a new entry there.

When building from source, `install.cmd` in the repository installs `dist\couch-mode.star`.

To remove it, first press **Remove** next to "Xbox mode controller access" if you turned it on, then turn the plugin off in the same list and delete the file. The plugin leaves nothing else behind; its settings are stored by Millennium.

## Xbox mode

If you start Steam through Windows' Xbox mode (full screen experience), Windows hides the controller from programs in the background unless they are allowed to read it. Steam is allowed; the plugin, which runs inside Millennium's plugin host `millennium.luavm64.exe`, is not. Without that permission the overlay shortcut does nothing in Xbox mode. The battery badge is not affected.

Fix: in the plugin's settings, press **Turn on** next to "Xbox mode controller access". Windows asks for administrator rights once. This sets `BackgroundInput = 1` under `HKLM\SOFTWARE\Microsoft\GameInputRedist\Exe\millennium.luavm64.exe`, the same per-program setting Windows already has for `steam.exe`. It stays in place after restarts. **Remove** in the same place takes it out again.

[`xbox-mode-access.cmd`](xbox-mode-access.cmd) in the repository does the same from outside Steam (`xbox-mode-access.cmd remove` to undo).

## Settings

Desktop Steam > Millennium > Plugins > Couch Mode.

| Setting | Default | |
|---|---|---|
| Battery next to the clock | On | Shows or hides the battery badge |
| Hold to open Steam overlay | On | Turns the shortcut on or off |
| Hold time | 600 ms | 200 to 2000 ms |
| Button | Menu | Menu or View |
| Overlay keys | Shift+Tab | Must match Steam > Settings > In Game > Overlay shortcut keys |
| Xbox mode controller access | Off | See [Xbox mode](#xbox-mode). Needs administrator rights once |
| Mute the game while the overlay is open | On | |
| Music in Big Picture | Off | |
| Music in the game overlay | Off | Plays the music while the overlay is open over a game. Needs game mute on |
| Music file or folder | Default folder | Choose a file or a folder with **Browse...** (Windows' own picker opens on the desktop), or type a path. A folder's files play in name order. The default is a `Couch Mode` folder in your Music folder (wherever Windows keeps it, also for OneDrive), created when you turn the music on |
| Music volume | 40% | |

Music plays mp3, ogg, opus, m4a, aac, wav, flac and webm files of up to 64 MB each. No music comes with the plugin.

Changes apply right away.

## What it does on your PC

Everything runs inside the plugin itself, through Millennium's Lua backend. There is no extra program, background service, script, or startup entry, and no network access.

- **Battery:** reads the battery level that Windows already keeps for paired Bluetooth devices (the number Windows Settings shows), using the Windows Configuration Manager API (`cfgmgr32.dll`). It reads devices whose name contains "Controller" or "Gamepad". Nothing is sent to the controller.
- **Controller buttons:** reads the controller through XInput (`xinput1_4.dll`) about 25 times a second, only while a game is running and a controller is connected.
- **Xbox mode controller access:** reads one registry value. Only when you press the button does it start `reg.exe` through Windows' administrator prompt to set or remove it.
- **Overlay shortcut:** when the button has been held long enough, it sends the overlay key combination with `SendInput`, as if typed on a keyboard. It does nothing when Steam itself is in front.
- **Game mute:** when Steam reports that the overlay opened, it turns on the mute switch of the game's audio sessions (the same switch as in the Windows Volume mixer), for the game and the programs it started, through the Windows audio API (`ole32.dll`, Core Audio). It turns off only the switches it turned on, so a game you muted yourself stays muted. Steam's own sounds keep playing.
- **Music:** reads only the music file or folder you set, and plays it inside Steam.

All Windows calls are declared in [`backend/win32.lua`](backend/win32.lua).

## Known limits

- Battery only for Bluetooth controllers that report it to Windows. Controllers on the Xbox Wireless Adapter or a cable show no badge.
- No charging indicator; Windows does not report charging for these devices.
- The game also receives the Menu press, so its pause menu may open behind the overlay.
- Windows blocks simulated keys to games running as administrator, and some anti-cheat games ignore them.
- Game mute needs Steam to report the overlay opening (`SteamClient.Overlay.RegisterForOverlayActivated`). If a Steam update removes that, the game is simply not muted.
- Music tells the store apart by Big Picture's own navigation. If Steam changes that, the music pauses on the store only for its videos.
- Only tested on one PC so far (Windows 11, Steam Beta, Millennium 3.5.0, Xbox Wireless Controller over Bluetooth). Reports from other setups are welcome.

## Build from source

Requires [Node.js](https://nodejs.org) 18 or newer.

```
npm install
npm run build
```

The plugin is written to `dist/couch-mode.star`. `npm run typecheck` checks the frontend. With [LuaJIT](https://luajit.org) on Windows, `luajit tools/check-backend.lua` runs the backend checks against your real controller. Set `COUCH_TEST_PID` to the process id of a program that plays sound (something silent) to also check muting it.

## License

[MIT](LICENSE)
