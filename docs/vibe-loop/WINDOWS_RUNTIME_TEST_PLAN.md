# Vibe Loop — Windows runtime test plan (Phase 1B)

This plan checks that the CI-built **test package** (`VibeLoop-TestPackage-x64-<sha>-NOT-RUNTIME-VERIFIED.zip`, about 500 MB, an artifact of the *Windows build, audit & test package* workflow; GitHub keeps it for 14 days, so rerun the workflow for a fresh one) actually runs. It also checks that Vibe Loop stays isolated from an installed Lively Wallpaper. Until every **[GATE]** test passes, the package and the rebrand PR count as *not runtime-verified*.

## 0. Ground rules (protect the owner's computer)

- **Run everything in a disposable Windows environment.** Use a Hyper-V / VirtualBox / VMware VM with a snapshot, a cloud Windows VM, or a spare PC. **Don't** run the package on the owner's laptop. Turning on Windows Sandbox or Hyper-V on that laptop is itself a system change, and that's the owner's decision.
- Take a **VM snapshot** before T0. Roll back to it instead of cleaning up by hand.
- Don't turn on "Start with Windows" except in T10. Don't register the screensaver except in the optional VM-only test T9.
- Every test writes before/after snapshots with the read-only `tools\Get-VibeLoopTestState.ps1`. Compare them with `-Compare`.

Recommended VM: **Windows 11 x64 23H2 or 24H2**, 4 vCPU, 8 GB RAM, 3D/GPU acceleration on if the hypervisor offers it, one display (T6 needs two). Windows 10 22H2 x64 is a secondary target.

Already present on these Windows versions: .NET Framework 4.8, the WebView2 runtime, and Media Foundation (missing on "N" editions; install the Media Feature Pack *in the VM only*). Bundled in the package: the .NET 9 and Windows App SDK runtimes (self-contained) and the MSVC runtime DLLs (app-local). Don't install VC++ or .NET in the VM unless a test fails. If you do, record it.

## 1. Result template

Copy this per run into the PR or an issue:

```
VM: Windows <edition> <version> build <n>, GPU accel: yes/no, displays: <n>
Package: <zip name>  sha256: <hash>  PACKAGE-INFO.commit: <sha>
| ID  | Result (PASS/FAIL/BLOCKED/SKIP) | Notes / evidence files |
|-----|----------------------------------|------------------------|
| T0  | | |
...
```

Evidence for a failure:
- the snapshots (`state-*.json`)
- the logs from `%LOCALAPPDATA%\Vibe Loop\logs` and `%LOCALAPPDATA%\Vibe Loop\UI`
- a screenshot
- for crashes, the *Windows Logs > Application* event in Event Viewer

## 2. Tests

### T0 — Package integrity and baseline [GATE]
1. Check the zip's SHA-256 against the `.sha256` file from the CI artifact.
2. Unzip to `C:\VibeLoopTest\` and check every file against the manifest:
   ```powershell
   cd C:\VibeLoopTest\VibeLoop-TestPackage-x64-*
   Get-Content .\MANIFEST.sha256 | ForEach-Object { $h,$f = $_ -split '  ',2; if ((Get-FileHash $f -Algorithm SHA256).Hash.ToLower() -ne $h) { "MISMATCH $f" } }
   ```
3. `cd tools; powershell -ExecutionPolicy Bypass -File .\Get-VibeLoopTestState.ps1 -Label t0-baseline`

**Expected:**
- no hash mismatch
- `PACKAGE-INFO.json` shows `"runtimeVerified": false` and the commit under test
- the baseline lists no `VibeLoop` Run entry and no Vibe Loop folders

### T1 — First start and clean exit [GATE]
1. Start `app\VibeLoop.exe`.
2. Expected:
   - a splash, then the tray icon (tooltip **Vibe Loop**)
   - the main window opens because this is the first run: title **Vibe Loop**, Light theme
   - no Gallery or Updates tab
3. Close the window. The first-run tray hint appears and the app keeps running in the tray.
4. Tray icon → **Exit**.
5. Snapshot `-Label t1-after`, then `-Compare state-t0-baseline.json, state-t1-after.json`.

**Expected:**
- In the snapshot comparison, only the *Vibe Loop* data and temp folders changed: `%LOCALAPPDATA%\Vibe Loop` (Settings.json, logs) and `%TEMP%\Vibe Loop`.
- These are **unchanged**:
  - Run entries (**no `VibeLoop` value**)
  - screensaver settings
  - wallpaper settings
  - Lively folders
  - installer registrations
- No Vibe Loop or player process is left running.
- The log's first lines read `Vibe Loop v2.2.1.5 x64 desktop-native …`.

### T2 — Single instance and core↔UI IPC [GATE]
1. Start `app\VibeLoop.exe`, then start it a second time. **Expected:** no second tray icon; the existing UI comes to the front.
2. While it runs, take a snapshot. **Expected:** mutex `VIBELOOP:DESKTOPWALLPAPERSYSTEM` = true, and a pipe named `Grpc_VIBELOOP:DESKTOPWALLPAPERSYSTEM<username>` exists.
3. In Settings, change a few options: theme, *Wallpaper > Video player*, *System > Tray icon* (turn it back on afterwards). Close the UI window and reopen it from the tray. **Expected:** the values persist and `Settings.json` reflects them.
4. Kill `Lively.UI.WinUI.exe` in Task Manager, then double-click the tray icon. **Expected:** the UI reopens and talks to the core (the library loads).
5. Run `app\plugins\UI\Lively.UI.WinUI.exe` while the core is **not** running. **Expected:** the message box "Wallpaper core is not running, run VibeLoop.exe first…" titled *Vibe Loop*.

### T3 — Video wallpaper (mpv, default) [GATE]
1. **Add wallpaper** → pick `test-fixtures\vibeloop-test-video.mp4` → set it as the wallpaper.
2. Expected:
   - the test pattern plays behind the desktop icons and loops
   - `mpv.exe` runs from `app\plugins\mpv`
   - with GPU acceleration, Task Manager › GPU shows *Video Decode* activity
3. Open a maximized app (e.g. Notepad maximized, or full screen). **Expected:** playback pauses according to *Performance* settings, then resumes.
4. Control panel / customise: change the volume. **Expected:** the 440 Hz tone is audible and the volume changes.
5. In *Settings > Wallpaper*, switch the video player to **libVLC** (`Lively.Player.Vlc`) and then to **WMF** (`Lively.PlayerWmf`), re-applying the wallpaper each time. **Expected:** each one plays, and nothing gets stuck in "loading".
   - Record the result for each player separately. libVLC and WMF were renamed or repackaged for the test layout.

### T4 — Web wallpaper (WebView2, default; CEF) [GATE for WebView2]
1. **Add wallpaper** → `test-fixtures\vibeloop-test-web.zip`. **Expected:**
   - it is imported as "Vibe Loop test - web" with its thumbnail
   - there is no "Not a Lively-format wallpaper file" error
2. Set it as the wallpaper. **Expected:**
   - an animated gradient with a running clock
   - `Lively.Player.WebView2.exe` is running
3. Customise: move *Animation period*, change *Accent color*, toggle *Show clock*. **Expected:**
   - the panel text shows `property speed = …` and so on
   - the visuals update right away
4. *Settings > Wallpaper > Web browser* → **CEF**, then re-apply. CefSharp 141.0.110 has one open **moderate** advisory (see DEPENDENCY_SECURITY.md), so load only the local test fixture with CEF, not arbitrary websites. **Expected:**
   - `Lively.Player.CefSharp.exe` and `CefSharp.BrowserSubprocess.exe` run
   - the wallpaper renders
   - the CEF cache appears under `%TEMP%\Vibe Loop\CEF\…`; nothing is created under `%TEMP%\Lively Wallpaper`
   - If CEF fails to start, note the error. Retry once after installing the *VC++ 2015–2022 x64 redistributable* **in the VM** to tell a missing app-local runtime apart from other failures.

### T5 — GIF and picture
Import `vibeloop-test-animation.gif` and `vibeloop-test-picture.jpg`. **Expected:** both display through mpv, and the Windows wallpaper setting (snapshot) stays the same.

### T6 — Multi-monitor and display changes (if the VM supports 2 displays)
Use per-display wallpapers, then *Span* and *Duplicate*. Disconnect and reconnect the second display. **Expected:** the wallpapers re-layout without leftover windows or a crash.

### T7 — Watchdog scope [GATE]
1. Set the video wallpaper (T3) and open the UI.
2. End `VibeLoop.exe` in Task Manager (*End task*).
3. **Expected:** within a few seconds, `mpv.exe` and `Lively.UI.WinUI.exe` from this package exit, and the desktop shows the normal Windows wallpaper again.
4. The cross-app part of this test is in T11 step 5.

### T8 — Screensaver, manual (no registration) [GATE]
Run these from a terminal in `app\`. The `.scr` finds `VibeLoop.exe` next to itself because no Vibe Loop installation is registered.
1. Vibe Loop running, a wallpaper set: `.\VibeLoop.scr /s`.
   - **Expected:** the screensaver view appears on every display, and moving the mouse or pressing a key ends it.
   - With *Settings > Screensaver > lock on resume* on, the session locks (VM only).
2. `.\VibeLoop.scr /c` → **Expected:** the screensaver settings or layout UI opens.
3. Exit Vibe Loop, then `.\VibeLoop.scr /s` → **Expected:** Vibe Loop starts in *exclusive screensaver mode*, shows the screensaver, and exits when it is dismissed. No tray icon stays behind.
4. Exit Vibe Loop, then run `.\VibeLoop.scr /c` and `.\VibeLoop.scr /p 0` → **Expected:** nothing happens. By design, the launcher only forwards configure and preview to a running instance.
5. Snapshot compare against T0 → **Expected:** screensaver values (`SCRNSAVE.EXE`, `ScreenSaveActive`, timeout) are **unchanged**.

### T9 — Screensaver registered with Windows (optional, VM ONLY)
1. Snapshot `t9-before`.
2. In Explorer, right-click `app\VibeLoop.scr` → **Install**. This sets it as the Windows screensaver.
3. In *Screen Saver Settings*:
   - **Expected:** the list shows **VibeLoop**
   - the small preview works while Vibe Loop runs (`/p`)
   - *Settings…* works (`/c`)
   - *Preview* works (`/s`)
4. Set a 1-minute wait and stay idle. **Expected:** Vibe Loop's screensaver starts.
5. Set the screensaver back to the value recorded in `t9-before`, then snapshot and compare. **Expected:** screensaver values match the baseline again.

### T10 — Startup registration (opt-in)
1. Settings › General › *Start with Windows* → **on**. **Expected:** the snapshot shows Run value **`VibeLoop`** = `"…\app\VibeLoop.exe"`, and a `Lively` value (if any) is unchanged.
2. Exit and start the app again. **Expected:** it stays on, no duplicate value appears, and the path is the same.
3. Turn it **off**. **Expected:** the `VibeLoop` Run value is gone, and Run entries equal the baseline.

### T11 — Coexistence with upstream Lively Wallpaper [GATE]
1. **In the VM only:** install the official Lively Wallpaper from https://github.com/rocksdanister/lively/releases. Start it and set any wallpaper. Snapshot `t11-lively`.
2. Start Vibe Loop. **Expected:**
   - two tray icons (Lively and Vibe Loop)
   - Vibe Loop does **not** forward its launch to Lively
   - Lively does not forward to Vibe Loop
   - the snapshot shows both mutexes and both gRPC pipes
3. Change a setting in each app. **Expected:** `%LOCALAPPDATA%\Lively Wallpaper\Settings.json` and `%LOCALAPPDATA%\Vibe Loop\Settings.json` change independently.
4. Close each app's UI and reopen it from its own tray icon. **Expected:** each UI connects to its own core. The Vibe Loop UI shows only Vibe Loop's library.
5. With **both UIs open**, end `VibeLoop.exe` in Task Manager. **Expected:**
   - Vibe Loop's UI and players exit
   - **Lively's UI (also `Lively.UI.WinUI.exe`, but from Lively's install folder) keeps running**
   - this is the watchdog installation filter
6. Do the reverse: end Lively's core. **Expected:** Vibe Loop's UI keeps running. Lively's own (upstream) watchdog may close every `Lively.UI.WinUI` process, so if Vibe Loop's UI closes here, record it as an upstream limitation, not a Vibe Loop fault.
7. Exit both apps and uninstall Lively. **Expected:**
   - Lively's uninstaller removes only Lively
   - Vibe Loop's folders, its settings and the package folder are untouched (snapshot)

### T12 — Upstream services disabled
1. Run `ipconfig /flushdns` **in the VM**, start Vibe Loop, open every tab, wait 2 minutes.
2. Then:
   ```powershell
   Get-DnsClientCache | Where-Object Entry -match 'livelywallpaper|api\.github\.com' | Format-Table Entry, Data
   Get-NetTCPConnection -State Established | Where-Object { (Get-Process -Id $_.OwningProcess -EA 0).ProcessName -in 'VibeLoop','Lively.UI.WinUI' }
   ```
**Expected:**
- no `api.livelywallpaper.net` or `livelywallpaper.net` lookup, and no update check against `api.github.com`
- no Gallery or Updates tab, and no tray "update" item
- (The WebView2/CEF players and web wallpapers may contact sites the wallpaper itself loads; the test fixture loads none.)

### T13 — Removal (portable) [GATE]
1. Exit Vibe Loop.
2. Delete `C:\VibeLoopTest`, `%LOCALAPPDATA%\Vibe Loop` and `%TEMP%\Vibe Loop`.
3. Snapshot, then compare with `t0-baseline`.

**Expected:** identical, apart from timestamps of unrelated folders. No Run entry, screensaver or wallpaper change, and no installer registration.

### T14 — Not covered by this package (track separately)
- **Inno installer / uninstaller** (`src/installer/Script_x64.iss`). The test package deliberately ships no installer. Before the first installer build, test in a VM:
  - install to `…\Vibe Loop`
  - side by side with Lively, without uninstalling it
  - AppMutex blocks setup while Vibe Loop runs
  - the uninstaller removes `Run\VibeLoop` and offers to delete only `%LOCALAPPDATA%\Vibe Loop`
- **Framework-dependent layout.** The installer ships the core framework-dependent and installs the .NET Desktop Runtime. The test package is self-contained. Re-check T1–T4 once with the installer build.
- Application, Unity, Godot and video-stream (yt-dlp) wallpapers, the depth-estimation (ML) wallpaper, and the taskbar theming plugin.
- Non-English UI text (translations need native review).

## 3. Known risks to watch

| Area | Why | Test |
|---|---|---|
| WMF and watchdog executables are renamed by the package script (`Lively.Player.Wmf.exe` → `Lively.PlayerWmf.exe`, `Lively.Utility.Watchdog.exe` → `Lively.Watchdog.exe`) to match the paths the core expects | Upstream release layout, not reproducible from the repo before Phase 1B | T3, T7 |
| App-local MSVC runtime for CEF, Magick and WinAppSDK | Replaces the VC++ redistributable the installer would install | T1, T4 (CEF) |
| Self-contained core and UI | The installer layout is framework-dependent | T1–T4; T14 |
| mpv baseline x86-64 build `20261111-git-bcde6b93cc` | Third-party binary, pinned by release tag and SHA-256, and checked against GitHub's asset digest | T3, T5 |
| Transitive security pins (`System.Private.Uri` 4.3.2, `System.Text.RegularExpressions` 4.3.1, `System.Text.Json` 8.0.5) | New assemblies in the core, UI and .NET Framework players' graphs | T1–T4 (each player starts) |
| Magick.NET 14.17.2 (security update) | Native ImageMagick changed; used for thumbnails, GIF capture and the taskbar accent | T3–T5 (thumbnails), T4 import |
| Watchdog installation filter | New code (Phase 1) | T7, T11 |
| `VibeLoop.scr` side-by-side lookup | New code (Phase 1B) | T8, T9 |
