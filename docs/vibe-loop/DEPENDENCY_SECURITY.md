# Vibe Loop — dependency security status (Phase 1B)

Policy: NuGet audit covers every project, direct and transitive packages, at every severity
(`src/Lively/Directory.Build.props`). Nothing is suppressed. CI (`build/audit/Invoke-DependencyAudit.ps1`)
**fails** on:
- any high or critical advisory
- any package downgrade (NU1605)
- any `dotnet list --vulnerable` tool error, or an SDK-style project it couldn't audit
- a restore log that contains no restore output

The last two make the audit fail closed when it can't see everything. Moderate and low advisories are
**reported** as warnings. Every run prints
`Dependency audit <PASS|FAIL>: … toolErrors=N sdkProjectsAudited=X/Y restoreOutputSeen=…` and uploads the
`dependency-audit` artifact.

**"PASS" is policy-specific:** it means no finding at or above the threshold, not "no vulnerabilities".
Open advisories below the threshold are residual risks and are listed below.

## Findings before Phase 1B

Source: restore warnings of the Windows CI run for `feat/vibe-loop-rebrand` @ `ac062b1`
([run 46046678309](https://github.com/mfuentes63-Design/vibe-loop/actions/runs/46046678309)).

| Package | Version | Where | Finding |
|---|---|---|---|
| `Magick.NET-Q8-AnyCPU` | 14.9.1 | `Lively` (core), `Lively.ML` (→ UI) | **151 distinct GitHub advisories**: 20 high (NU1903), 97 moderate (NU1902), 34 low (NU1901) |
| `Newtonsoft.Json` | 13.0.3 | `Lively.Player.Wmf` | NU1605 downgrade: `Lively.Common`/`Lively.Models` need ≥ 13.0.4 |

No other package was flagged.

High-severity advisories against Magick.NET 14.9.1:
GHSA-36wm-hprc-mcf5, GHSA-3mwp-xqp2-q6ph, GHSA-6hjr-v6g4-3fm8, GHSA-72hf-fj62-w6j4, GHSA-7355-pwx2-pm84,
GHSA-7gg8-qqx7-92g5, GHSA-8jvj-p28h-9gm7, GHSA-8pj9-6897-74xc, GHSA-932h-jw47-73jm, GHSA-96pc-27rx-pr36,
GHSA-fwvm-ggf6-2p4x, GHSA-g22q-f7gc-5jhr, GHSA-hffp-q43q-qq76, GHSA-pqgj-2p96-rx85, GHSA-q62c-h75r-2xhc,
GHSA-rqq8-jh93-f4vg, GHSA-v7g2-m8c5-mf84, GHSA-vhqj-f5cj-9x8h, GHSA-wj8w-pjxf-9g4f, GHSA-x9h5-r9v2-vcww.

## Changes

| Change | Why this version |
|---|---|
| `Magick.NET-Q8-AnyCPU` 14.9.1 → **14.17.2** in `Lively.csproj` and `Lively.ML.csproj` | Newest release of the same 14.x major line (ImageMagick 7.1.2-32). Upstream release notes for 14.10–14.17.2 list security fixes and no breaking change for the APIs used here: `MagickImage`, `MagickImageCollection`, `MagickGeometry`, `Resize`/`Thumbnail`, `MagickColor.FromRgb`. **15.x was not chosen**: it drops `net8.0` (`Lively.ML` targets it) and removes or renames public APIs. CI shows no advisory for 14.17.2. |
| `Newtonsoft.Json` 13.0.3 → **13.0.4** in `Lively.Player.Wmf.csproj` | Matches every other project. Same 13.0 line; the assembly version stays 13.0.0.0, so binding redirects don't change. |
| Transitive pin `System.Private.Uri` **4.3.2** in `Lively.Models.csproj` | 4.3.0 (GHSA-xhfc-gr8f-ffwc, GHSA-5f2m-466j-3848 high; GHSA-x5qj-9vmx-7g6g moderate) comes in through `System.Drawing.Primitives` 4.3.0's netstandard1.x graph. Every affected project references `Lively.Models`. |
| Transitive pin `System.Text.RegularExpressions` **4.3.1** in `Lively.Common.csproj` | 4.3.0 (GHSA-cmhx-cq75-c4mj high, ReDoS) comes in through the netstandard1.x graph. Every affected project references `Lively.Common`. |
| Transitive pin `System.Text.Json` **8.0.5** in `Lively.Gallery.Client.csproj` | 7.0.2 (GHSA-hh2w-p6rv-4g7w high) was resolved for `Lively.Gallery.Client` and, through it, `Lively.UI.WinUI`. |

The three transitive findings were **pre-existing**. Phase 1 didn't see them because the default audit
only covered direct packages. Turning on `NuGetAuditMode=all` in Phase 1B exposed them (CI run
[46050921257](https://github.com/mfuentes63-Design/vibe-loop/actions/runs/46050921257)). On .NET 8/9 the
shared framework normally supersedes these assemblies at runtime; the pins remove them from the graph
anyway. No other package was upgraded.

## Result after Phase 1B

CI run [46052995949](https://github.com/mfuentes63-Design/vibe-loop/actions/runs/46052995949) (`a5752be`),
full NuGet audit (direct and transitive, every project) plus the `dotnet list --vulnerable` cross-check
on all SDK-style projects:

**PASS: critical 0, high 0, moderate 1, low 0, downgrades 0.**

### Remaining advisory (reported, not blocking)

| Package | Version | Advisory | Severity | Where | Disposition |
|---|---|---|---|---|---|
| `CefSharp.Common` (via `CefSharp.WinForms`) | 141.0.110 | [GHSA-85jm-cwp2-mvpv](https://github.com/advisories/GHSA-85jm-cwp2-mvpv) | moderate | `Lively.Player.CefSharp` (optional CEF web player; WebView2 is the default) | Fixing it means a CefSharp/Chromium major upgrade, which changes the bundled Chromium runtime and needs its own compatibility testing (T4 CEF). Track it in a dedicated dependency PR. Until then, keep WebView2 as the web player. |

Runtime impact still to verify on Windows:
- Magick.NET is used for thumbnails, GIF screen capture, image import/conversion, the taskbar accent color and the depth-estimation wallpaper.
- The transitive pins touch the core, the UI and the .NET Framework players through `Lively.Common`/`Lively.Models`.

See the risk table in [WINDOWS_RUNTIME_TEST_PLAN.md](WINDOWS_RUNTIME_TEST_PLAN.md).

## Third-party binaries outside NuGet

| Runtime | Pin | Verification |
|---|---|---|
| mpv (shinchiro/mpv-winbuild-cmake `20261111`, `mpv-x86_64-20261111-git-bcde6b93cc.7z`, baseline x86-64) | release tag + asset pattern + SHA-256 `f259b5fd4b5c395617c948a4fadcdf55bba1c5282fb7c13e88626b3f71072baf` in `build/package/third-party-runtimes.json` | Download must match GitHub's server-side asset digest **and** the pinned SHA-256 (both matched in run 46052995949) |
| MSVC runtime DLLs (app-local) | copied from the runner's Visual Studio `VC\Redist\MSVC\<latest>\x64\Microsoft.VC*.CRT` | Recorded in `PACKAGE-INFO.json` (`msvcRuntime`) |

These binaries are not covered by NuGet audit. Track mpv/FFmpeg security releases manually, and bump the
pinned tag and hash in a dedicated PR.
