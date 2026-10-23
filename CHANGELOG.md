# Changelog

## Unreleased

- **Music pause:** a music note next to the battery badge in Big Picture's top bar (and in the game overlay) pauses and resumes the music; a slash shows it is paused. It stays paused after a restart and is also on the settings page. Shown only while music is on. It works with the mouse, touch and keyboard; the controller's D-pad does not reach it.

## 3.0.0 (2026-10-23)

Big Picture Controller Battery is now **Couch Mode**: extras that make Steam Big Picture feel more like a console.

### New

- **Game mute:** the game goes quiet while the Steam overlay is open and its sound comes back when the overlay closes. Couch Mode mutes the game's sessions in the Windows volume mixer, for the game, the programs it started, and every other program Steam started that is not part of Steam, so games started through a launcher are covered too. It only unmutes what it muted itself.
- **Music:** your own music plays everywhere in Big Picture, menus included. It fades out on the store (also when opened from the overlay), while a trailer or video plays, while a game runs, and when another program is in front, and fades back in where it stopped. Optionally it also plays in the overlay over a muted game. The music comes from a `Couch Mode` folder in your Music folder, which Couch Mode creates; **Browse...** picks the file with Windows' own file picker. Off by default, volume 30%.
- The battery badge can be turned off.
- Settings page with a section per feature, in Steam's card style.

### Upgrading from Big Picture Controller Battery 2.x

- The plugin id, name and file are now `couch-mode`, Couch Mode and `couch-mode.star`. Turn on Couch Mode once in Millennium > Plugins.
- `install.cmd` removes the old `big-picture-controller-battery.star`.
- Your settings (hold time, button, overlay keys, shortcut on or off) are copied over once on first start.

## 2.1.0 (2026-10-16)

- Xbox mode controller access can be turned on and off from the settings page.

## 2.0.0 (2026-10-08)

- Hold Menu (or View) in a game to open the Steam overlay.
- Battery badge next to the clock in Big Picture and in the game overlay.
- `install.cmd` for a one-click install, and `xbox-mode-access.cmd` for the overlay shortcut in Windows' Xbox mode.
