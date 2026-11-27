# Vibe Loop — Phase 1 identity migration summary

Branch `feat/vibe-loop-rebrand`, based on `dev/personal-screensaver` @ `25a0a5f`.
Inventory taken before any change: [IDENTITY_INVENTORY.md](IDENTITY_INVENTORY.md).

## 1. What changed

| Commit | Area | Summary |
|---|---|---|
| `docs: add Phase 1 identity and dependency inventory` | docs | Inventory of identity, IPC, storage, external-service and compatibility dependencies |
| `feat(identity): isolate Vibe Loop runtime identity …` | runtime | Product/storage name, mutex (and the pipe names and DPAPI entropy derived from it), temp/cache folders, default library, NLog paths, CefSharp paths, watchdog scoping |
| `build: rename core executable to VibeLoop.exe …` | build | `AssemblyName=VibeLoop`, screensaver `VibeLoop.Screensaver` + `VibeLoop.scr`, product metadata, `VibeLoop.sln` |
| `installer: give Vibe Loop its own installer and package identity` | packaging | Inno Setup identity, new AppId, AppMutex, Run key, uninstall cleanup; MSIX placeholder identity; screensaver launcher IDs |
| `ui: replace user-visible Lively Wallpaper branding …` | UX | Titles, tray, notifications, message boxes, resources (all locales), About/Help, MSIX display, Light default theme |
| `services: disable upstream-owned update and gallery services` | services | `Constants.Features` flags; updater pointed at the fork; Gallery and Updates pages hidden |
| `ci: add Windows build-validation workflow` | CI | `windows-2022` Release x64 compile, logs, NuGet-warning summary, identity guard |
| `docs: Vibe Loop README, NOTICE, privacy note and migration summary` | docs | This document, README, NOTICE, privacy note, issue template log path |

Where the identity values live now:
- Main constants: `src/Lively/Lively.Common/Constants.cs` (`ApplicationType`, `SingleInstance`, `Features`).
- Duplicated values, each with a "keep in sync" comment:
  - `Lively.Models/SettingsModel.cs` (Models can't reference Common)
  - `Lively.Utility.Screensaver/Program.cs` (has no project references on purpose)
  - `src/installer/Script*.iss`
  - the two `Nlog.config` files

## 2. Old → new identifier map

### Runtime / OS identity

| Identifier | Lively Wallpaper (old) | Vibe Loop (new) | Defined in |
|---|---|---|---|
| Display / product name | `Lively Wallpaper` | `Vibe Loop` | `Constants.ApplicationType.Name` |
| Tagline | — | `Make your screen come alive.` | `Constants.ApplicationType.Tagline` |
| Single-instance mutex | `LIVELY:DESKTOPWALLPAPERSYSTEM` | `VIBELOOP:DESKTOPWALLPAPERSYSTEM` | `Constants.SingleInstance.UniqueAppName`, screensaver launcher, installer `AppMutex` |
| gRPC named pipe | `Grpc_LIVELY:DESKTOPWALLPAPERSYSTEM<user>` | `Grpc_VIBELOOP:DESKTOPWALLPAPERSYSTEM<user>` | derived |
| Legacy v1 pipe | `LIVELY:DESKTOPWALLPAPERSYSTEM<user>` | `VIBELOOP:DESKTOPWALLPAPERSYSTEM<user>` | derived |
| DPAPI entropy (`Tokens.dat`) | `LIVELY:DESKTOPWALLPAPERSYSTEM` | `VIBELOOP:DESKTOPWALLPAPERSYSTEM` | derived |
| App data root | `%LOCALAPPDATA%\Lively Wallpaper` | `%LOCALAPPDATA%\Vibe Loop` | `Constants.CommonPaths.AppDataDir` |
| Settings, layouts, rules, tokens, themes, screenshots, ML models, CEF/WebView2/mpv profiles | under old root | under new root | `Constants.CommonPaths`, `Constants.MachineLearning` |
| Logs (core / UI) | `…\Lively Wallpaper\logs`, `…\Lively Wallpaper\UI` | `…\Vibe Loop\logs`, `…\Vibe Loop\UI` | `Lively/Nlog.config`, `Lively.UI.WinUI/Nlog.config` |
| Temp caches | `%TEMP%\Lively Wallpaper\{themes,CEF,gallery}` | `%TEMP%\Vibe Loop\{themes,CEF,gallery}` | `Constants.CommonPaths`, CefSharp player, UI `DiskCacheService` |
| CEF log file | `%LOCALAPPDATA%\Lively Wallpaper\Cef\logfile.txt` | `%LOCALAPPDATA%\Vibe Loop\Cef\logfile.txt` | `Lively.Player.CefSharp/{Program,Form1}.cs` |
| Default wallpaper library | `%LOCALAPPDATA%\Lively Wallpaper\Library` | `%LOCALAPPDATA%\Vibe Loop\Library` | `SettingsModel.WallpaperDir` |
| MSIX packaged data | `…\Packages\<pfn>\LocalCache\Local\Lively Wallpaper` | `…\Packages\<pfn>\LocalCache\Local\Vibe Loop` | `PackageUtil` (derived) |
| HKCU `…\CurrentVersion\Run` value | `Lively` → `…\Lively.exe` | `VibeLoop` → `…\VibeLoop.exe` | installer `[Registry]`; app derives it from the assembly name in `WindowsStartup` |
| Watchdog UI cleanup | kills every `Lively.UI.WinUI` process | kills only `Lively.UI.WinUI` processes in this install | `Lively.Utility.Watchdog/Program.cs` |
| Default app theme | Dark | Light | `SettingsModel` |

### Executables, solution and assemblies

| Item | Old | New | Notes |
|---|---|---|---|
| Core executable | `Lively.exe` (+ `Lively.dll`, `Lively.deps.json`, `Lively.runtimeconfig.json`, `Lively.resources.dll`) | `VibeLoop.exe` (+ `VibeLoop.*`) | `Lively.csproj` `AssemblyName`; `RootNamespace` pinned to `Lively` so resource names don't change |
| Screensaver launcher | `Lively.Utility.Screensaver.exe` (shipped renamed as `Lively.scr`) | `VibeLoop.Screensaver.exe` + `VibeLoop.scr` (+ `.config`) produced by an after-build target | Windows shows the `.scr` file name as the screensaver name |
| Screensaver → core launch | `<install>\Lively.exe` | `<install>\VibeLoop.exe` | `Lively.Utility.Screensaver/Program.cs` |
| UI executable | `Lively.UI.WinUI.exe` | **unchanged** (product metadata now "Vibe Loop") | see §4 |
| Players, watchdog, CLI | `Lively.Player.*.exe`, `Lively.Watchdog.exe`, `Lively.Utility.Commandline.exe` | **unchanged** | internal plugin files under `plugins\` |
| Solution | `src/Lively/Lively.sln` | `src/Lively/VibeLoop.sln` | project names/GUIDs unchanged |
| Namespaces / project files | `Lively.*` | **unchanged** | see §4 |
| Assembly metadata (Task Manager / file properties) | default (assembly name) | Product/Title "Vibe Loop" for core and UI; "Vibe Loop Screensaver" | |

### Installer and package identity

| Item | Old | New |
|---|---|---|
| Inno `AppId` | `{{E3E43E1B-DEC8-44BF-84A6-243DBA3F2CB1}}` | `{{93A384C2-FB92-4015-BFC7-AEDE5495C2C0}}` |
| Uninstall registry key | `…\Uninstall\{E3E43E1B-…-243DBA3F2CB1}}_is1` | `…\Uninstall\{93A384C2-…-AEDE5495C2C0}}_is1` |
| `AppName` / install dir / Start menu / desktop shortcut | `Lively Wallpaper` / `{autopf}\Lively Wallpaper` | `Vibe Loop` / `{autopf}\Vibe Loop` |
| `AppPublisher` / URLs | `rocksdanister` / `github.com/rocksdanister/lively` | `Vibe Loop (fork of Lively Wallpaper by rocksdanister)` / `github.com/mfuentes63-Design/vibe-loop` |
| `AppMutex` | `LIVELY:DESKTOPWALLPAPERSYSTEM` | `VIBELOOP:DESKTOPWALLPAPERSYSTEM` |
| Installer file | `lively_installer.exe` | `vibeloop_setup_x64_full.exe` (`vibeloop_setup_x86_full.exe` for legacy script) |
| Uninstall "delete data" prompt | `%LOCALAPPDATA%\Lively Wallpaper` | `%LOCALAPPDATA%\Vibe Loop` |
| MSIX `Identity` | `12030rocksdanister.LivelyWallpaper`, `CN=D80CB9E2-21E6-4D9B-8533-660C768F3C5B` | `VibeLoop`, `CN=VibeLoop` (placeholder) |
| MSIX family name (used by screensaver launcher) | `12030rocksdanister.LivelyWallpaper_97hta09mmv6hy` | `VibeLoop_srh4j84q0xahy` |
| MSIX `PhoneIdentity` | upstream Store IDs | removed |
| MSIX display names / StartupTask display | `Lively Wallpaper` | `Vibe Loop` |

The brace format of the AppId is kept as upstream wrote it (`{{GUID}}`, so the Inno value is `{GUID}}`).
The screensaver launcher builds the uninstall key as `"{GUID}" + "}_is1"`. If you "fix" one side
without the other, the launcher stops finding the install.

### Online services

| Service | Old | New |
|---|---|---|
| Update check | `rocksdanister/lively` / `lively-beta` releases, asset `lively_setup_<arch>_full` | **Disabled** (`Constants.Features.IsAppUpdateCheckEnabled=false`). When turned on, it uses `mfuentes63-Design/vibe-loop` releases, asset `vibeloop_setup_<arch>_full` |
| Updates page / tray "update" item | visible | hidden while update check is disabled |
| Online gallery (`api.livelywallpaper.net`, upstream Google/GitHub OAuth apps) | auto-login on start, Gallery tab | **Disabled** (`Constants.Features.IsGalleryEnabled=false`), no network call, Gallery tab hidden |
| About logo / website / source / bug links | livelywallpaper.net, rocksdanister/lively | fork repository (`…/vibe-loop`, `…/vibe-loop/issues`) |
| Licence / privacy links | upstream `core-separation` branch | fork `dev/personal-screensaver` branch |

Feature impact: no in-app updates (update manually from the fork's releases once they exist), no
online gallery browsing/login/subscription/upload/restore. Local import/export of wallpaper `.zip`
files and every wallpaper engine still work. No subscription or paid API is bypassed. The services
are just switched off and the code is kept.

## 3. Unresolved upstream-specific references

### 3a. Legal attribution — keep on purpose

- `LICENSE` (GPL-3.0), `src/installer/License/License.txt`
- About page contributor avatars/links (rocksdanister, roxxel, dabjulmaros, zeealeid, GireeshChandran, everything411) and the "Attribution" link to `livelywallpaper.net/attribution/` (third-party notices)
- About page fork statement and upstream link. README / NOTICE / PRIVACY fork notes. Installer publisher string. Assembly `Description`/`Copyright` "Based on Lively Wallpaper (GPL-3.0)"
- `Lively.Player.CefSharp/Properties/AssemblyInfo.cs` `AssemblyCompany("rocksdanister")` / description: authorship of an unchanged upstream component
- Code comments that link to upstream issues/discussions (`// Ref: https://github.com/rocksdanister/lively/issues/...`)
- `AboutMe.Text` in non-English resource files (upstream author's first-person bio; the key is not used by any view)
- `docs/upstream/LIVELY_README.md` (original README, moved)
- `.github/FUNDING.yml` (upstream author's sponsorship links; whether to keep or remove it is up to the owner)

### 3b. Compatibility contracts — must stay "Lively"

- Wallpaper package files `LivelyInfo.json`, `LivelyProperties.json`, `LivelyProperties.info`, `lively_theme`, `schemas/livelyPropertiesSchema.json`, plus the related model/type names (`LivelyInfoModel`, …)
- Web wallpaper JS API: `livelyPropertyListener`, `livelyAudioListener`, `livelyCurrentTrack`, `livelySystemInformation`, `livelyWallpaperPlaybackChanged`, `lively_default_settings_reload`
- Core↔player stdin protocol (`lively:terminate`), player/watchdog/UI file names inside `plugins\`
- User-facing wording that names the format: "Not a Lively-format wallpaper file", file picker "Wallpaper package (Lively format)"

### 3c. Technical dependencies — still upstream, functional

| Reference | Where | Impact / next step |
|---|---|---|
| ML depth model download `rocksdanister/lively-ml-models` | `DepthEstimateWallpaperViewModel.cs` | Public GitHub asset, only downloaded when the user asks. Mirror it to a fork repository if independence is wanted |
| Documentation links `github.com/rocksdanister/lively/wiki/*` | Help page, settings pages, error dialogs, screensaver setup, `DiagnosticViewModel`, `LivelyExceptionGeneral/MediaPlayback` text | Still accurate for the shared engine. Replace when Vibe Loop has its own docs |
| Community link `rocksdanister/lively/discussions` | Help page | Replace when the fork has a community channel |
| Translation link `rocksdanister.github.io/lively/translation` | Settings › General | Strings are shared with upstream |
| Changelog page `livelywallpaper.net/changelog` | `AppUpdateView.xaml.cs` | Page hidden while updates are off. Repoint before turning updates on |
| Gallery endpoints + upstream OAuth client IDs | `Lively.UI.WinUI/App.xaml.cs` | Disabled. Must not be turned back on with upstream credentials |
| Default URL wallpaper `https://livelywallpaper.net/demo` | `SettingsModel.SavedURL` | Prefilled sample URL in "add URL" |
| Gallery login page privacy link | `GalleryLoginView.xaml` | Page unreachable while gallery is disabled |
| Upstream art assets (app icon, tray icon, splash, `icon-lively-48.png`, `banner-lively-1080.jpg`, Store logos, installer wizard images and icon) | `Assets/`, `Resources/`, `src/installer/{Icons,Theme}` | Visual identity is Phase 2 (redesign). The app still shows Lively's icon |
| `.github/ISSUE_TEMPLATE/bug_report.yml` wiki link | issue template | Log path updated to Vibe Loop. Wiki link kept |
| Internal namespaces/projects `Lively.*`, UI exe `Lively.UI.WinUI.exe`, player exe names | whole solution | See §4 |
| `Lively.Utility.ConsoleDemo` example path comment | demo project | Cosmetic |
| `Resources.Designer.cs` XML doc comments that quote old English strings | core | Regenerated by Visual Studio on next resx edit |
| Inflected product name in some translations (fi `Livelyn`, az `Lively-ni`, hu `Livelynek`, sr `Lively-a`, de `Lively-Einrichtung`, ko particle agreement, …) | `Strings/*/Resources.resw`, `Properties/Resources.*.resx` | Needs native-speaker review. Only the standalone name was replaced automatically |

## 4. Deliberately deferred (and why)

- **C# namespaces, project folders/files, other assembly names (`Lively.*`).** These don't collide
  at runtime once the identifiers in §2 are unique. A rename touches 17 projects plus:
  - WPF/WinUI `x:Class` and `using:` XAML namespaces
  - resx manifest names hard-coded in `*.Designer.cs`
  - gRPC `csharp_namespace` and the generated code
  - SDK-style defaults (`AssemblyName`/`RootNamespace` follow the project file name)
  - the old-style .NET Framework project files

  No Windows compiler was available for this change (see §5). A blind rename would be exactly the
  global search-and-replace the brief rules out. Suggested path: one project per PR, bottom-up
  (`Models` → `Common` → `Common.Services`/`Grpc.*` → players → core → UI), each validated by the CI
  workflow.
- **UI executable name `Lively.UI.WinUI.exe`.** The core launches it by name (`RunnerService`), the
  watchdog looks it up by name, and WinAppSDK MRT resource lookup is tied to the project output.
  Renaming it together with the UI project is best done in Phase 2, which reworks the UI anyway.
  Task Manager already shows "Vibe Loop" through the assembly metadata.
- **Player / watchdog / CLI executable names.** These are internal plugin files and aren't user-visible.
- **Assembly `[Guid]` attributes** in .NET Framework projects. These are COM typelib IDs that are
  never registered (`ComVisible(false)`), so there is no collision.
- **Visual redesign, icons and art.** Phase 2.

## 5. Build results

| Check | Result |
|---|---|
| Compile in this change's environment | **Not run.** The change was prepared in a Linux sandbox with no .NET SDK, no Visual Studio, and no NuGet access. No compile result is claimed |
| Windows CI (`.github/workflows/build-windows.yml`) | Added. **It has not run yet**: it runs on the first push of this branch / when the PR is opened. Check the "Windows build validation" run and its `build-logs` artifact |
| Static checks done | Every edited `.resx`/`.resw` parses as XML. The workflow passes `actionlint`. The identity guard patterns find no upstream runtime identifiers in source. MSIX PublisherId algorithm checked against known values (`8wekyb3d8bbwe`, upstream `97hta09mmv6hy`) before computing `srh4j84q0xahy` |
| Baseline (owner, before this branch) | VS 2022, Release x64: 17 succeeded, 0 failed, 0 skipped |

Compile risks to look at first if CI fails:
- `Lively/Lively.csproj`: the `AssemblyName` change. WPF markup compile generates `/VibeLoop;component/...` URIs automatically; the handwritten `pack://application:,,,/Resources/...` URIs don't depend on the assembly name.
- `Lively.Utility.Screensaver.csproj`: the new `AfterTargets="Build"` copy target.
- `Lively.UI.Shared/ViewModels/MainViewModel.cs`: the `GetPages()` filter (C# 12 collection expression assigned to an array).
- `Lively.Utility.Watchdog/Program.cs`: new P/Invoke helpers (C# 7.3).

### NuGet warnings

Remediated in Phase 1B (Magick.NET 14.17.2, Newtonsoft.Json 13.0.4, plus three transitive security pins).
The audit now covers direct and transitive packages and fails CI on high or critical findings. See
[DEPENDENCY_SECURITY.md](DEPENDENCY_SECURITY.md).

## 6. Requires local Windows runtime testing

Phase 1B replaced this checklist with the detailed VM test plan
[WINDOWS_RUNTIME_TEST_PLAN.md](WINDOWS_RUNTIME_TEST_PLAN.md), which runs against the CI-built test package.
The list below is kept for reference.

Compilation does not show that any of this works. On a Windows test machine (ideally a VM or a
separate user account — **not** the owner's daily Windows profile), with a full runtime layout
(`Plugins\`, optional `Bundle\`):

1. **Side-by-side isolation.** Install or run upstream Lively Wallpaper and Vibe Loop at the same time. Each should start, keep its own tray icon, and not forward its launch to the other app.
2. **Storage.** Vibe Loop creates and uses only `%LOCALAPPDATA%\Vibe Loop` and `%TEMP%\Vibe Loop`. `%LOCALAPPDATA%\Lively Wallpaper` stays untouched (timestamps).
3. **First run.** Fresh settings, Light theme, library at `%LOCALAPPDATA%\Vibe Loop\Library`, bundled wallpapers extracted (if `Bundle\` is present).
4. **IPC.** The UI (`plugins\UI\Lively.UI.WinUI.exe`) connects to the core over `Grpc_VIBELOOP:…` (library loads, settings save). A second `VibeLoop.exe` launch opens the existing UI.
5. **Watchdog.** End `VibeLoop.exe` in Task Manager. Vibe Loop's UI and app-wallpaper processes close, and a running Lively Wallpaper UI is **not** closed.
6. **Startup.** Toggling "Start with Windows" adds/removes HKCU `Run\VibeLoop` and leaves `Run\Lively` alone.
7. **Installer (Inno).** Build with `Script_x64.iss`. Installs to `…\Vibe Loop`, Start menu entry "Vibe Loop", does **not** uninstall an existing Lively install, the uninstaller removes only Vibe Loop and offers to delete only `%LOCALAPPDATA%\Vibe Loop`, and an install/uninstall is blocked while Vibe Loop is running (AppMutex).
8. **Screensaver.** Install `VibeLoop.scr` manually and only on the test machine. Windows Screen Saver Settings should list "VibeLoop". Then check:
   - Preview, Settings, and Show (`/p`, `/c`, `/s`) launch `VibeLoop.exe` from the Vibe Loop install (found through the new AppId uninstall key)
   - nothing starts Lively
   - exclusive mode works when Vibe Loop isn't already running
9. **Wallpaper engines.** Check each engine still renders with hardware acceleration and correct audio/pause behaviour: video (mpv/VLC/WMF), web (WebView2 and CEF, including the CEF cache under `%TEMP%\Vibe Loop\CEF`), GIF, picture, URL/stream, application/Unity/Godot wallpapers, Lively-format `.zip` import/export, multi-monitor layouts, display hot-plug.
10. **Branding.** Window title, title bar, tray tooltip/menu ("Open Vibe Loop"), balloon notifications, About and Help pages, error dialogs, file picker label, Task Manager names — in English and at least one other language.
11. **Disabled services.** No Gallery or Updates tab, no tray update entry, no traffic to `api.livelywallpaper.net` or `api.github.com/repos/rocksdanister/*` at startup (Fiddler / Resource Monitor).
12. **Logs / diagnostics.** Logs written to `%LOCALAPPDATA%\Vibe Loop\logs` and `…\UI`, and the diagnostic report export still works.

Don't change the owner's own Windows screensaver settings or install over existing applications
while testing.
