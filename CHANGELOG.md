# Changelog

## 2.0.1

- Fixed: pressing Menu on the Big Picture home screen (no game running) could show Steam's "An error occurred while rendering this content" screen (React error #130). The plugin's settings page and icon now check that each Steam UI component exists before using it, and any remaining rendering error is caught inside the plugin instead of reaching Steam's UI.

## 2.0.0

- First public release: battery badge for Bluetooth controllers in Big Picture and the game overlay, hold Menu in a game to open the Steam overlay, settings page in Millennium's plugin list.
