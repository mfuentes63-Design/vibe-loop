# Vibe Loop — Windows x64 TEST package

> **TEST ONLY — NOT RUNTIME-VERIFIED.**
> CI compiled and assembled this package. Nobody has started or exercised it on Windows yet.
> Use it **only in a disposable Windows VM** (or a spare test PC), never on your everyday computer.

## What this is

- A portable copy of Vibe Loop laid out like an installed copy:
  - `app\` holds `VibeLoop.exe` and the folders it expects under `app\plugins\`: the UI, the CEF and WebView2 web players, the mpv, libVLC and WMF video players, and the watchdog.
  - `app\VibeLoop.scr` is the screensaver launcher.
- The core and the UI are self-contained. No .NET runtime, Windows App SDK or VC++ runtime has to be installed first.
- `test-fixtures\` holds original synthetic test media (video with tone, GIF, picture, Lively-format web wallpaper `.zip`).
- `tools\Get-VibeLoopTestState.ps1` takes a **read-only** snapshot of startup entries, screensaver and wallpaper settings, app-data folders, processes, pipes and mutexes, so you can compare before and after a test.
- `docs\WINDOWS_RUNTIME_TEST_PLAN.md` is the step-by-step test plan. Start there.
- `PACKAGE-INFO.json` records the commit, the CI run, component versions and the pinned third-party runtimes.
- `MANIFEST.sha256` lists a hash for every file. Licences and third-party notices are in `licenses\`.

## What this is not

- **Not an installer.** It contains no Inno Setup installer or uninstaller, no redistributable installers and no MSIX.
- It does **not** register a startup entry. "Start with Windows" is off by default; don't turn it on outside the VM.
- It does **not** register the screensaver. `VibeLoop.scr` only runs when you start it yourself (`VibeLoop.scr /s`).
  **Never** right-click it and choose **Install** on a computer whose screensaver you care about. That replaces the Windows screensaver setting.
- It does not change your desktop wallpaper unless you turn on "set desktop wallpaper" type options or choose the WinAPI picture player. On exit, the app asks Windows to redraw the current wallpaper.

## Quick start (inside the VM)

```powershell
# 1. Verify the download (compare with the .sha256 file published next to the zip)
Get-FileHash .\VibeLoop-TestPackage-x64-*.zip -Algorithm SHA256

# 2. Unzip anywhere, e.g. C:\VibeLoopTest, then take a baseline snapshot
cd C:\VibeLoopTest\VibeLoop-TestPackage-x64-*\tools
powershell -ExecutionPolicy Bypass -File .\Get-VibeLoopTestState.ps1 -Label before

# 3. Start Vibe Loop
..\app\VibeLoop.exe
```

Then follow `docs\WINDOWS_RUNTIME_TEST_PLAN.md`. When reporting a problem, attach:
- the test ID
- the `state-*.json` snapshots
- `%LOCALAPPDATA%\Vibe Loop\logs\*` and `%LOCALAPPDATA%\Vibe Loop\UI\*`

## Removing it

Exit Vibe Loop from the tray icon (**Exit**). Then delete the unzipped folder, `%LOCALAPPDATA%\Vibe Loop` and `%TEMP%\Vibe Loop`. Nothing else is created unless you turned on "Start with Windows". If you did, turn it off in Settings before exiting.

Vibe Loop is a GPL-3.0 fork of Lively Wallpaper. See `licenses\NOTICE.md`.
