# Vibe Loop — Phase 1 identity & dependency inventory

Snapshot of `dev/personal-screensaver` @ `25a0a5f` (upstream Lively Wallpaper v2.2.1.x, GPL-3.0),
taken before any rebrand change. Each item is classified as:

- **ID** – runtime/OS identity that must be unique to avoid colliding with an installed Lively Wallpaper
- **UX** – user-visible branding
- **EXT** – upstream-owned external service
- **COMPAT** – wallpaper-format / public-API contract that must *not* be renamed
- **INT** – internal code identifier (namespaces, project names) with no runtime collision risk

## Process model

| Component | Project | Output | Notes |
|---|---|---|---|
| Core (tray, wallpaper engine, gRPC server) | `Lively/Lively.csproj` (WPF, net9.0-windows) | `Lively.exe` | Single-instance via named mutex; hosts gRPC over named pipe |
| UI | `Lively.UI.WinUI` (WinUI 3, unpackaged) | `plugins\UI\Lively.UI.WinUI.exe` | Refuses to start unless core mutex exists; talks to core over gRPC pipe |
| Watchdog | `Lively.Utility.Watchdog` (net472) | shipped as `Plugins\Watchdog\Lively.Watchdog.exe` | Kills wallpaper processes **and every process named `Lively.UI.WinUI`** when core dies |
| Screensaver launcher | `Lively.Utility.Screensaver` (net472) | `Lively.Utility.Screensaver.exe`, distributed renamed as a `.scr` | Hard-codes mutex, Inno AppId, MSIX family name, `Lively.exe` |
| Players | `Lively.Player.{CefSharp,WebView2,Vlc,Wmf}` | `plugins\*\Lively.Player.*.exe` | Spawned by core; stdin protocol (`lively:terminate`) |
| CLI | `Lively.Utility.Commandline` | `Lively.Utility.Commandline.exe` | Checks core mutex |
| Installer | `src/installer/Script_x64.iss` (+ legacy x86 `Script.iss`) | Inno Setup | |

`Plugins\` (mpv, CEF, WebView2 player, watchdog, UI) and `Bundle\` (starter wallpapers) are **not in the repo**;
they are assembled into the core output folder before packaging.

## Identity-bearing items

| # | Item | Where | Class |
|---|---|---|---|
| 1 | Product name `Lively Wallpaper` (`Constants.ApplicationType.Name`) | `Lively.Common/Constants.cs` | ID+UX — also drives `%LOCALAPPDATA%\Lively Wallpaper` |
| 2 | Single-instance mutex `LIVELY:DESKTOPWALLPAPERSYSTEM` | `Constants.SingleInstance.UniqueAppName`, `Lively.Utility.Screensaver/Program.cs`, installer `AppMutex` | ID |
| 3 | gRPC pipe `Grpc_LIVELY:DESKTOPWALLPAPERSYSTEM<user>` (derived from #2) | `Constants.SingleInstance.GrpcPipeServerName` | ID |
| 4 | Legacy v1 pipe name (derived from #2) | `Constants.SingleInstance.PipeServerName` | ID |
| 5 | DPAPI entropy for `Tokens.dat` (derived from #2) | `Lively.Common/Helpers/EncryptUtil.cs` | ID |
| 6 | App data root `%LOCALAPPDATA%\Lively Wallpaper` (settings, layouts, logs, CEF/WebView2 profiles, ML models, themes) | `Constants.CommonPaths` | ID |
| 7 | Temp roots `%TEMP%\Lively Wallpaper\{themes,CEF,gallery}` | `Constants.cs`, `Lively.Player.CefSharp/{Program,Form1}.cs`, `Lively.UI.WinUI/App.xaml.cs` | ID |
| 8 | Default wallpaper library `%LOCALAPPDATA%\Lively Wallpaper\Library` | `Lively.Models/SettingsModel.cs` (can't see `Constants`) | ID |
| 9 | NLog file targets `…/Lively Wallpaper/logs`, `…/Lively Wallpaper/UI` | `Lively/Nlog.config`, `Lively.UI.WinUI/Nlog.config` | ID |
| 10 | Startup registration: HKCU `…\Run` value = core **assembly name** (`Lively`) | `Lively/Helpers/WindowsStartup.cs`; installer `[Registry]` | ID |
| 11 | Inno Setup `AppId {E3E43E1B-DEC8-44BF-84A6-243DBA3F2CB1}` (also used to auto-uninstall "previous version") | `Script*.iss`, screensaver launcher | ID — **reusing it would uninstall Lively** |
| 12 | Install dir `{autopf}\Lively Wallpaper`, Start menu/desktop shortcut names, uninstall data-folder prompt | `Script*.iss` | ID+UX |
| 13 | MSIX identity `12030rocksdanister.LivelyWallpaper` / `CN=D80CB9E2-…`, PhoneIdentity, family `…_97hta09mmv6hy`, StartupTask | `Lively.UI.WinUI/Package.appxmanifest`, screensaver launcher | ID (upstream Store identity) |
| 14 | Executable name `Lively.exe` | `Lively.csproj` (default), installer, screensaver launcher, appxmanifest, UI error text | ID+UX |
| 15 | Screensaver display name (= `.scr` file name) | not produced by the build; upstream ships `Lively.scr` | UX |
| 16 | Watchdog kills **all** `Lively.UI.WinUI` processes system-wide | `Lively.Utility.Watchdog/Program.cs` | ID — cross-app interference |
| 17 | Solution `Lively.sln` | `src/Lively` | INT |
| 18 | Namespaces / assemblies `Lively.*` (17 projects, WPF/WinUI `x:Class`, resx manifest names, proto `csharp_namespace`) | everywhere | INT — no runtime collision once #1–#16 are unique |

## User-visible branding (UX)

- WinUI main window `Title`, title-bar text, `TitleAppName` resource (`Lively.UI.WinUI/Strings/*/Resources.resw`)
- Core tray tooltip, balloon notifications, message boxes (`Lively/Services/Systray.cs`, `Lively/App.xaml.cs`, `DiagnosticViewModel.cs`)
- Core localized resources (`Lively/Properties/Resources*.resx`) – tray menu "Open Lively", update notification, errors
- WPF diagnostic windows "Lively Debugger", "Lively Diagnostics"
- About page (logo link, licence/privacy links), Help page (website/source/bug links), `AboutMe.Text` (written in upstream author's first person)
- File-picker filter label "Lively Wallpaper (.zip)"
- Installer `MyAppName`, publisher, URLs, output file name; MSIX `DisplayName`
- Assembly metadata (Product/Title/Company) shown in Task Manager & file properties

## Upstream external services (EXT)

| Service | Where | Risk if left on |
|---|---|---|
| GitHub release updater → `rocksdanister/lively` (+ `lively-beta`), asset `lively_setup_x64_full*` | `Lively.Common.Services/GithubUpdaterService.cs` | Would prompt Vibe Loop users to download & run the **upstream Lively installer** |
| Lively Gallery API `api.livelywallpaper.net` with upstream Google & GitHub OAuth client IDs (login, subscribe, share, restore) | `Lively.UI.WinUI/App.xaml.cs`, `Lively.Gallery.Client`, Gallery nav tab | Fork would authenticate against upstream's backend under upstream's OAuth apps |
| Changelog page `livelywallpaper.net/changelog` | `AppUpdateView.xaml.cs` | Shows upstream changelog |
| ML model download `rocksdanister/lively-ml-models` (GitHub release asset) | `DepthEstimateWallpaperViewModel.cs` | Public, free asset – functional dependency |
| Wiki/docs links `github.com/rocksdanister/lively/wiki/*` | many XAML views | Technical docs still accurate for the shared engine |
| Demo URL `livelywallpaper.net/demo` (default "URL" wallpaper field) | `SettingsModel.cs` | Cosmetic |
| OpenWeatherMap key | `Constants.Weather` | Empty upstream – nothing to change |

No telemetry/analytics SDK is present.

## Compatibility contracts (COMPAT — keep as-is)

- Wallpaper package files `LivelyInfo.json`, `LivelyProperties.json`, `LivelyProperties.info`, `lively_theme`
- Web wallpaper JS callbacks `livelyPropertyListener`, `livelyAudioListener`, `livelyCurrentTrack`, `livelySystemInformation`, `livelyWallpaperPlaybackChanged`, button `lively_default_settings_reload`
- `schemas/livelyPropertiesSchema.json`
- Core↔player stdin messages (`lively:terminate`), player exe names under `plugins\`
- CLI verbs/options

Renaming any of these would break every existing Lively-format wallpaper.

## NuGet warnings to record (do not fix in Phase 1)

- `Magick.NET-Q8-AnyCPU` **14.9.1** in `Lively/Lively.csproj` and `Lively.ML/Lively.ML.csproj` — reported by the owner's local build as having known vulnerabilities (NU190x)
- `Newtonsoft.Json` **13.0.3** pinned in `Lively.Player.Wmf/Lively.Player.Wmf.csproj` while `Lively.Common`/`Lively.Models` require **13.0.4** → package-downgrade warning (NU1605)
