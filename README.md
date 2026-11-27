# Vibe Loop

**Make your screen come alive.**

Vibe Loop is a personal Windows app for animated and interactive desktop wallpapers and screensavers:
video, web, GIF, shader and application wallpapers, multi-monitor layouts, and a screensaver mode.
The planned look is fun, colorful, cinematic, futuristic, bright and playful.

> **Fork notice.** Vibe Loop is a fork of [Lively Wallpaper](https://github.com/rocksdanister/lively)
> by Dani John ([rocksdanister](https://github.com/rocksdanister)) and the Lively contributors.
> Almost all of the code is theirs. It is distributed under the same
> [GNU General Public License v3.0](LICENSE). Vibe Loop is not affiliated with or endorsed by the
> Lively Wallpaper project. See [NOTICE.md](NOTICE.md).

## Status

Work in progress. Phase 1 (application identity and isolation) changes the name, executable and
Windows identifiers so Vibe Loop can be installed next to Lively Wallpaper without sharing settings,
wallpaper library, mutexes, IPC pipes, installer registration or startup entries.
The visual redesign comes in a later phase.

- Identity inventory: [docs/vibe-loop/IDENTITY_INVENTORY.md](docs/vibe-loop/IDENTITY_INVENTORY.md)
- Migration summary and old→new identifier map: [docs/vibe-loop/IDENTITY_MIGRATION.md](docs/vibe-loop/IDENTITY_MIGRATION.md)

## Building

Requirements: Windows 10 1903 or later, Visual Studio 2022 with the .NET desktop and WinUI
(Windows App SDK) workloads, and the .NET 9 SDK.

1. Open `src/Lively/VibeLoop.sln`.
2. Select **Release | x64** and build the solution.
3. The core executable is `VibeLoop.exe`. The screensaver launcher is built as
   `VibeLoop.Screensaver.exe` and copied to `VibeLoop.scr`.

A successful build is not a runnable app on its own. The runtime layout also needs the `Plugins\`
folder (mpv, web/video players, watchdog, UI) and the optional `Bundle\` starter wallpapers, and
those are not part of this repository. The GitHub Actions workflow
[`build-windows.yml`](.github/workflows/build-windows.yml) only checks compilation.

## Compatibility

Vibe Loop keeps the Lively wallpaper package format (`LivelyInfo.json`, `LivelyProperties.json`)
and the web wallpaper JavaScript API (`livelyPropertyListener`, …), so existing Lively-format
wallpapers keep working. Engine documentation is still upstream:
[Lively wiki](https://github.com/rocksdanister/lively/wiki).

## License

[GPL-3.0](LICENSE). The original Lively Wallpaper README is kept at
[docs/upstream/LIVELY_README.md](docs/upstream/LIVELY_README.md).
