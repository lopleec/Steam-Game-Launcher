# Steam Game Launcher

English · [简体中文](README.zh-CN.md)

A native macOS launcher for your Steam games and local apps, built with SwiftUI.

[Download](https://github.com/lopleec/Steam-Game-Launcher/releases/latest) · [Report an issue](https://github.com/lopleec/Steam-Game-Launcher/issues) · [MIT License](LICENSE)

## Features

- Scan Steam libraries on your Mac, including external drives, and identify installed games.
- Launch games and open their Steam store, library, community, achievements, guides and workshop pages.
- Search, sort, favorite and organize games into collections, with Windows and Linux filters for synced libraries.
- Add Steam App IDs, local `.app` bundles, scripts, `.command` files, `.jar` files and other launchable files. Removed shortcuts can be restored.
- Hide games from the main library, with optional password protection.
- Display a fullscreen animated poster wall with horizontal, vertical and diagonal motion, idle activation and a clock.
- Configure the app on first launch and restore default settings at any time.

## Install

Requires **macOS 14 or later**. The DMG supports **Apple Silicon and Intel Macs**. Install the Steam client to use Steam links and launch Steam games.

Download the DMG from [Releases](https://github.com/lopleec/Steam-Game-Launcher/releases/latest), open it, and drag **Steam Game Launcher** into **Applications**.

Current releases are ad-hoc signed and are not Apple-notarized. macOS may require approval in **System Settings → Privacy & Security** on first launch.

## Steam library sync

Optional **Steam login** opens Steam's official page inside the app. The app can sync your owned games, save the library locally and match it against local installations. No developer API key or separate server is required. Steam handles downloads and social features.

Account sync is **experimental**: it depends on Steam's web session interfaces. Local scanning works without signing in.

App data is stored in `~/Library/Application Support/SteamGameLauncher/`. The Steam web session stays in the app's local WebKit storage; passwords and login tokens are not written to the library file. Artwork is loaded from Steam's local cache, with optional online artwork and metadata requests.

## Build

Requires Xcode command line tools with **Swift 5.10 or later**, plus Python 3 for bundle packaging.

```sh
./script/build_and_run.sh --verify  # Debug build and launch
swift test                        # Unit tests
./script/package_dmg.sh            # Universal release DMG in dist/
```

Bundle identity and release version are defined in [`script/app_config.sh`](script/app_config.sh). The bundle identifier is `com.lopleec.SteamGameLauncher`.

## License

[MIT](LICENSE). Steam and game artwork belong to their respective owners. This project is not affiliated with Valve.
