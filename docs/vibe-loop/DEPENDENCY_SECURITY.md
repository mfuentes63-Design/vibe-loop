# Vibe Loop — dependency security status (Phase 1B)

Policy: NuGet audit covers every project, direct and transitive packages, at every severity
(`src/Lively/Directory.Build.props`). Nothing is suppressed. CI (`build/audit/Invoke-DependencyAudit.ps1`)
**fails** on any high or critical advisory and on any package downgrade (NU1605), and **reports**
moderate and low advisories as warnings. Every run uploads its report as the `dependency-audit` artifact.

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
| `Magick.NET-Q8-AnyCPU` 14.9.1 → **14.17.2** in `Lively.csproj` and `Lively.ML.csproj` | Newest release of the same 14.x major line (2026-09-27, ImageMagick 7.1.2-32), with no vulnerability listed on nuget.org. Upstream release notes for 14.10–14.17.2 list security fixes and no breaking change for the APIs used here: `MagickImage`, `MagickImageCollection`, `MagickGeometry`, `Resize`/`Thumbnail`, `MagickColor.FromRgb`. **15.x was not chosen**: it drops `net8.0` (`Lively.ML` targets it) and removes or renames public APIs. |
| `Newtonsoft.Json` 13.0.3 → **13.0.4** in `Lively.Player.Wmf.csproj` | Matches every other project. Same 13.0 line; the assembly version stays 13.0.0.0, so binding redirects don't change. |

No other package was upgraded.

## Result after Phase 1B

See section "CI verification" in the Phase 1B pull request for the run link. Summary of the audit on the
Phase 1B branch: **0 critical, 0 high, 0 moderate, 0 low advisories and 0 downgrades** (NuGet audit, direct and
transitive, all projects; the `dotnet list --vulnerable` cross-check found the same).

Runtime impact still to verify on Windows: Magick.NET is used for thumbnails, GIF screen capture, image
import/conversion, the taskbar accent color and the depth-estimation wallpaper. See the risk table in
[WINDOWS_RUNTIME_TEST_PLAN.md](WINDOWS_RUNTIME_TEST_PLAN.md).

## Third-party binaries outside NuGet

| Runtime | Pin | Verification |
|---|---|---|
| mpv (shinchiro/mpv-winbuild-cmake, baseline x86-64 build) | release tag + asset pattern + SHA-256 in `build/package/third-party-runtimes.json` | Download must match GitHub's server-side asset digest and the pinned SHA-256 |

These binaries are not covered by NuGet audit. Track mpv/FFmpeg security releases manually, and bump the
pinned tag and hash in a dedicated PR.
