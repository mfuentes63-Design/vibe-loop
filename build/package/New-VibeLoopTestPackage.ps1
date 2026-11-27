<#
.SYNOPSIS
  Assembles the Vibe Loop Windows x64 TEST package (portable, not an installer, NOT runtime-verified).

.DESCRIPTION
  Run on Windows after the solution was built (Release|x64). The script:
    1. publishes the core (VibeLoop.exe) and the WinUI UI self-contained for win-x64,
    2. lays out the same folder structure the Inno installer ships ({app}\plugins\...),
    3. adds the .NET Framework components (players, watchdog, screensaver launcher) from the build output,
    4. downloads pinned third-party runtimes (build/package/third-party-runtimes.json) and verifies SHA-256,
    5. bundles the MSVC runtime DLLs app-locally (CefSharp/Magick native code),
    6. adds original test fixtures, a read-only state snapshot tool, docs, licenses and third-party notices,
    7. verifies the layout (required files, PE architecture, forbidden files), writes PACKAGE-INFO.json and
       MANIFEST.sha256, and zips it.

  Nothing is installed, registered or executed by this script, and the package contains no installer,
  no auto-start entry and no screensaver registration.

.EXAMPLE
  pwsh build/package/New-VibeLoopTestPackage.ps1 -OutputDirectory artifacts/package
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string] $OutputDirectory = 'artifacts/package',
    [string] $Configuration = 'Release',
    [string] $DownloadCache = 'artifacts/downloads',
    [switch] $SkipPublish,
    [switch] $SkipZip
)

$ErrorActionPreference = 'Stop'
trap {
    $pos = if ($_.InvocationInfo) { $_.InvocationInfo.PositionMessage } else { '' }
    Write-Host "::error title=Test package script failed::$($_.Exception.Message) $($pos -replace '\r?\n', ' ')"
    Write-Host $_.ScriptStackTrace
    exit 1
}
$ProgressPreference = 'SilentlyContinue'

function Write-Step([string] $m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Fail([string] $m) { if ($env:GITHUB_ACTIONS) { Write-Host "::error title=Test package::$m" }; throw $m }
function Ensure-Dir([string] $p) { New-Item -ItemType Directory -Force -Path $p | Out-Null; (Resolve-Path $p).Path }
function Copy-Tree([string] $from, [string] $to) {
    if (-not (Test-Path $from)) { Fail "Expected build output folder is missing: $from (did the solution build Release|x64?)" }
    Ensure-Dir $to | Out-Null
    Copy-Item -Path (Join-Path $from '*') -Destination $to -Recurse -Force
}
function Get-PEMachine([string] $path) {
    $fs = [IO.File]::OpenRead($path)
    try {
        $br = New-Object IO.BinaryReader($fs)
        $fs.Position = 0x3C; $pe = $br.ReadInt32(); $fs.Position = $pe + 4
        switch ($br.ReadUInt16()) { 0x8664 { 'x64' } 0x014c { 'x86' } 0xAA64 { 'arm64' } default { 'unknown' } }
    } finally { $fs.Dispose() }
}
function Invoke-MSBuild([string[]] $msbuildArgs) {
    & msbuild @msbuildArgs
    if ($LASTEXITCODE -ne 0) { Fail "msbuild failed ($LASTEXITCODE): $($msbuildArgs -join ' ')" }
}

$src = Join-Path $RepoRoot 'src/Lively'
$OutputDirectory = Ensure-Dir (Join-Path $RepoRoot $OutputDirectory)
$DownloadCache = Ensure-Dir (Join-Path $RepoRoot $DownloadCache)
$logDir = Ensure-Dir (Join-Path $RepoRoot 'artifacts/logs')

$commit = (git -C $RepoRoot rev-parse HEAD).Trim()
$short = $commit.Substring(0, 7)
$pkgName = "VibeLoop-TestPackage-x64-$short-NOT-RUNTIME-VERIFIED"
$root = Join-Path $OutputDirectory $pkgName
if (Test-Path $root) { Remove-Item $root -Recurse -Force }
$app = Ensure-Dir (Join-Path $root 'app')
$plugins = Ensure-Dir (Join-Path $app 'plugins')

# ------------------------------------------------------------------ 1. publish core + UI (self-contained)
$publishRoot = Ensure-Dir (Join-Path $RepoRoot 'artifacts/publish')
$corePub = Join-Path $publishRoot 'core'
$uiPub = Join-Path $publishRoot 'ui'
if (-not $SkipPublish) {
    foreach ($p in @(
            @{ name = 'core'; proj = 'Lively/Lively.csproj'; out = $corePub },
            @{ name = 'ui'; proj = 'Lively.UI.WinUI/Lively.UI.WinUI.csproj'; out = $uiPub })) {
        Write-Step "Publishing $($p.name) (self-contained win-x64)"
        if (Test-Path $p.out) { Remove-Item $p.out -Recurse -Force }
        Invoke-MSBuild @((Join-Path $src $p.proj), '-restore', '-t:Publish', '-m', '-nologo', '-v:minimal',
            "-p:Configuration=$Configuration", '-p:Platform=x64', '-p:RuntimeIdentifier=win-x64', '-p:SelfContained=true',
            '-p:PublishReadyToRun=false', '-p:PublishTrimmed=false', "-p:PublishDir=$($p.out)\",
            "-bl:$(Join-Path $logDir "publish-$($p.name).binlog")")
    }
}

Write-Step 'Assembling layout'
Copy-Tree $corePub $app
Copy-Tree $uiPub (Join-Path $plugins 'UI')

# ------------------------------------------------------------------ 2. .NET Framework components from the solution build
$fw = @(
    @{ from = 'Lively.Player.CefSharp/bin/x64/Release'; to = 'cef' },
    @{ from = 'Lively.Player.WebView2/bin/x64/Release'; to = 'webview2' },
    @{ from = 'Lively.Player.Wmf/bin/x64/Release'; to = 'wmf' },
    @{ from = 'Lively.Player.Vlc/bin/Release'; to = 'libvlc' },        # solution maps this project to AnyCPU for Release|x64
    @{ from = 'Lively.Utility.Watchdog/bin/x64/Release'; to = 'Watchdog' }
)
foreach ($c in $fw) { Copy-Tree (Join-Path $src $c.from) (Join-Path $plugins $c.to) }

# Runtime file names expected by the core (Constants.PlayerPartialPaths / WatchdogProcess) differ from the assembly names.
function Rename-Exe([string] $dir, [string] $from, [string] $to) {
    $f = Join-Path $dir $from
    if (-not (Test-Path $f)) { Fail "Missing $f" }
    Move-Item $f (Join-Path $dir $to) -Force
    if (Test-Path "$f.config") { Move-Item "$f.config" (Join-Path $dir "$to.config") -Force }
}
Rename-Exe (Join-Path $plugins 'wmf') 'Lively.Player.Wmf.exe' 'Lively.PlayerWmf.exe'                # Constants.PlayerPartialPaths.WmfPath
Rename-Exe (Join-Path $plugins 'Watchdog') 'Lively.Utility.Watchdog.exe' 'Lively.Watchdog.exe'      # WatchdogProcess: Plugins\Watchdog\Lively.Watchdog

# Screensaver launcher next to VibeLoop.exe (portable lookup), NOT registered with Windows.
$scrOut = Join-Path $src 'Lively.Utility.Screensaver/bin/x64/Release'
foreach ($f in 'VibeLoop.scr', 'VibeLoop.Screensaver.exe', 'VibeLoop.Screensaver.exe.config', 'VibeLoop.scr.config') {
    $p = Join-Path $scrOut $f
    if (Test-Path $p) { Copy-Item $p $app -Force } elseif ($f -notlike '*.config') { Fail "Missing screensaver output $p" }
}

# ------------------------------------------------------------------ 3. pinned third-party runtimes
$manifest = Get-Content (Join-Path $PSScriptRoot 'third-party-runtimes.json') -Raw | ConvertFrom-Json
$thirdParty = @()
$ghHeaders = @{ 'Accept' = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28'; 'User-Agent' = 'vibe-loop-test-package' }
$ghToken = if ($env:GH_TOKEN) { $env:GH_TOKEN } elseif ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $null }
if ($ghToken) { $ghHeaders['Authorization'] = "Bearer $ghToken" }

function Resolve-GitHubAsset($r) {
    $repo = $r.github.repository; $tag = $r.github.tag; $pattern = $r.github.assetPattern
    try {
        $rel = Invoke-RestMethod -Headers $ghHeaders -Uri "https://api.github.com/repos/$repo/releases/tags/$tag"
    } catch {
        $lookupError = $_.Exception.Message
        $hint = ''
        try {
            $recent = Invoke-RestMethod -Headers $ghHeaders -Uri "https://api.github.com/repos/$repo/releases?per_page=5"
            $hint = ($recent | ForEach-Object {
                    $t = $_.tag_name
                    $m = @($_.assets | Where-Object { $_.name -match $pattern } | ForEach-Object { "$($_.name) ($($_.digest))" })
                    "$t -> $($m -join '; ')"
                }) -join ' | '
        } catch { $hint = "could not list releases: $($_.Exception.Message)" }
        Fail "$($r.name): release tag '$tag' not found in $repo ($lookupError). Recent releases and matching assets: $hint"
    }
    $assets = @($rel.assets | Where-Object { $_.name -match $pattern })
    if ($assets.Count -ne 1) {
        Fail "$($r.name): expected exactly one asset matching '$pattern' in $repo@$tag, found $($assets.Count): $((@($rel.assets) | ForEach-Object name) -join ', ')"
    }
    $asset = $assets[0]
    $digest = if ($asset.PSObject.Properties['digest'] -and $asset.digest) { ($asset.digest -replace '^sha256:', '').ToLowerInvariant() } else { $null }
    return [pscustomobject]@{ url = $asset.browser_download_url; name = $asset.name; size = $asset.size; digest = $digest; published = $rel.published_at }
}

foreach ($r in $manifest.runtimes) {
    Write-Step "Third-party runtime: $($r.name) $($r.version)"
    if ($r.PSObject.Properties['github']) {
        $res = Resolve-GitHubAsset $r
    } else {
        $res = [pscustomobject]@{ url = $r.url; name = [IO.Path]::GetFileName(([uri]$r.url).AbsolutePath); size = $null; digest = $null; published = $null }
    }
    $pinned = if ($r.sha256) { $r.sha256.ToLowerInvariant() } else { $null }
    if (-not $pinned -and -not $res.digest) { Fail "$($r.name): no pinned sha256 and no GitHub digest available for $($res.url) - refusing to use an unverified binary." }
    $file = Join-Path $DownloadCache $res.name
    if (-not (Test-Path $file)) { Invoke-WebRequest -Uri $res.url -OutFile $file -UseBasicParsing -Headers @{ 'User-Agent' = 'vibe-loop-test-package' } }
    $hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($res.digest -and $hash -ne $res.digest) {
        Remove-Item $file -Force
        Fail "$($r.name): downloaded file does not match GitHub's digest for $($res.name): expected $($res.digest), got $hash."
    }
    if ($pinned -and $hash -ne $pinned) {
        Remove-Item $file -Force
        Fail "SHA-256 mismatch for $($r.name): pinned $pinned, got $hash ($($res.url)). Update build/package/third-party-runtimes.json only after verifying the new file."
    }
    if (-not $pinned) {
        Write-Host "::warning title=Unpinned third-party runtime::$($r.name) $($res.name) verified against GitHub digest only. Pin it: set ""sha256"": ""$hash"" in build/package/third-party-runtimes.json"
    }
    Write-Host "  $($res.name)  sha256 $hash  (GitHub digest: $(if ($res.digest) { 'match' } else { 'n/a' }); pinned: $(if ($pinned) { 'match' } else { 'NOT PINNED' }))"
    $r | Add-Member -NotePropertyName resolved -NotePropertyValue $res -Force
    $r | Add-Member -NotePropertyName verifiedSha256 -NotePropertyValue $hash -Force
    $dest = Ensure-Dir (Join-Path $app $r.destination)
    switch ($r.archive) {
        '7z' { & 7z x $file "-o$dest" -y | Out-Null; if ($LASTEXITCODE -ne 0) { Fail "7z extraction failed for $file" } }
        'zip' { Expand-Archive $file $dest -Force }
        default { Fail "Unsupported archive type $($r.archive)" }
    }
    # Flatten if the archive wraps everything in a single top-level folder.
    $first = $r.requiredFiles[0]
    if (-not (Test-Path (Join-Path $dest $first))) {
        $children = @(Get-ChildItem $dest)
        if ($children.Count -eq 1 -and $children[0].PSIsContainer -and (Test-Path (Join-Path $children[0].FullName $first))) {
            Get-ChildItem $children[0].FullName | Move-Item -Destination $dest
            Remove-Item $children[0].FullName -Recurse -Force
        }
    }
    foreach ($req in $r.requiredFiles) { if (-not (Test-Path (Join-Path $dest $req))) { Fail "$($r.name): $req not found after extraction" } }
    if ($r.PSObject.Properties['removeAfterExtract']) {
        foreach ($rm in $r.removeAfterExtract) { $t = Join-Path $dest $rm; if (Test-Path $t) { Remove-Item $t -Recurse -Force } }
    }
    $thirdParty += [ordered]@{ name = $r.name; version = $r.version; asset = $r.resolved.name; url = $r.resolved.url; sha256 = $r.verifiedSha256
        githubDigestVerified = [bool]$r.resolved.digest; pinned = [bool]$r.sha256; license = $r.license; source = $r.source }
}

# ------------------------------------------------------------------ 4. MSVC runtime, app-local (redistributable files)
Write-Step 'Bundling MSVC runtime (app-local)'
$crtFiles = @()
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$crtDir = $null
if (Test-Path $vswhere) {
    $vs = & $vswhere -latest -products * -property installationPath
    if ($vs) {
        $crtDir = Get-ChildItem (Join-Path $vs 'VC/Redist/MSVC') -Directory -ErrorAction SilentlyContinue |
            Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
            ForEach-Object { Get-ChildItem (Join-Path $_.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue } |
            Select-Object -First 1
    }
}
if ($crtDir) {
    # Core (Magick.Native), UI (Windows App SDK self-contained) and CEF (CefSharp.Core.Runtime is C++/CLI) load MSVC-built native code.
    foreach ($target in @($app, (Join-Path $plugins 'UI'), (Join-Path $plugins 'cef'))) {
        Get-ChildItem $crtDir.FullName -Filter *.dll | ForEach-Object {
            if (-not (Test-Path (Join-Path $target $_.Name))) { Copy-Item $_.FullName $target }
        }
    }
    $crtFiles = @(Get-ChildItem $crtDir.FullName -Filter *.dll | Select-Object -ExpandProperty Name)
} else {
    Write-Host '::warning title=Test package::MSVC CRT redistributable folder not found; CefSharp may need the VC++ 2015-2022 x64 redistributable on the test VM.'
}

# ------------------------------------------------------------------ 5. fixtures, tools, docs, licenses
Write-Step 'Fixtures, tools, docs, licenses'
$fixtures = Ensure-Dir (Join-Path $root 'test-fixtures')
Get-ChildItem (Join-Path $RepoRoot 'tests/fixtures/runtime') -File | Copy-Item -Destination $fixtures
$tools = Ensure-Dir (Join-Path $root 'tools')
Copy-Item (Join-Path $PSScriptRoot 'Get-VibeLoopTestState.ps1') $tools
$docs = Ensure-Dir (Join-Path $root 'docs')
Copy-Item (Join-Path $RepoRoot 'docs/vibe-loop/WINDOWS_RUNTIME_TEST_PLAN.md') $docs
Copy-Item (Join-Path $RepoRoot 'docs/vibe-loop/IDENTITY_MIGRATION.md') $docs
Copy-Item (Join-Path $PSScriptRoot 'README-TEST-PACKAGE.md') $root

$lic = Ensure-Dir (Join-Path $root 'licenses')
Copy-Item (Join-Path $RepoRoot 'LICENSE') (Join-Path $lic 'LICENSE-GPL-3.0.txt')
Copy-Item (Join-Path $RepoRoot 'NOTICE.md') $lic
Copy-Item (Join-Path $RepoRoot 'PRIVACY.md') $lic

# NuGet package inventory + license files from the package cache (preserves notices shipped inside packages).
$nugetRoot = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { Join-Path $HOME '.nuget/packages' }
$pkgs = @{}
Get-ChildItem $src -Recurse -Filter project.assets.json | Where-Object { $_.FullName -notmatch 'ConsoleDemo' } | ForEach-Object {
    $assets = Get-Content $_.FullName -Raw | ConvertFrom-Json
    foreach ($prop in $assets.libraries.PSObject.Properties) {
        if ($prop.Value.type -eq 'package') { $pkgs[$prop.Name] = $true }
    }
}
$rows = @()
$nugetLic = Ensure-Dir (Join-Path $lic 'nuget')
foreach ($key in ($pkgs.Keys | Sort-Object)) {
    $id, $ver = $key -split '/', 2
    $dir = Join-Path $nugetRoot (Join-Path $id.ToLowerInvariant() $ver.ToLowerInvariant())
    $license = ''; $project = ''
    $nuspec = Get-ChildItem $dir -Filter *.nuspec -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nuspec) {
        [xml]$x = Get-Content $nuspec.FullName -Raw
        $md = $x.package.metadata
        if ($md.license) { $license = if ($md.license -is [string]) { $md.license } else { $md.license.'#text' } }
        elseif ($md.licenseUrl) { $license = $md.licenseUrl }
        if ($md.projectUrl) { $project = $md.projectUrl }
    }
    $licFiles = @(Get-ChildItem $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(LICENSE|LICENCE|NOTICE|COPYING|THIRD.?PARTY|ThirdPartyNotices)' })
    if ($licFiles.Count) {
        $d = Ensure-Dir (Join-Path $nugetLic "$id.$ver")
        $licFiles | Copy-Item -Destination $d
    }
    $rows += "| $id | $ver | $license | $project |"
}

$tp = New-Object System.Text.StringBuilder
[void]$tp.AppendLine('# Third-party notices - Vibe Loop test package')
[void]$tp.AppendLine('')
[void]$tp.AppendLine('Vibe Loop is a GPL-3.0 fork of Lively Wallpaper (https://github.com/rocksdanister/lively); see NOTICE.md and LICENSE-GPL-3.0.txt.')
[void]$tp.AppendLine('License files shipped inside NuGet packages are copied to licenses/nuget/<package>.<version>/. Runtimes copied from build')
[void]$tp.AppendLine('outputs keep any license files they contain in place (for example app/plugins/cef, app/plugins/libvlc, app/plugins/mpv).')
[void]$tp.AppendLine('')
[void]$tp.AppendLine('## Downloaded runtimes (pinned, SHA-256 verified)')
foreach ($t in $thirdParty) {
    [void]$tp.AppendLine("- **$($t.name)** $($t.version) - $($t.license)")
    [void]$tp.AppendLine("  - binary: $($t.url) (sha256 $($t.sha256))")
    foreach ($s in $t.source) { [void]$tp.AppendLine("  - corresponding source: $s") }
}
[void]$tp.AppendLine('')
[void]$tp.AppendLine('## Bundled platform runtimes')
[void]$tp.AppendLine('- .NET 9 runtime and Windows Desktop runtime (self-contained publish of app/ and app/plugins/UI) - MIT, https://github.com/dotnet')
[void]$tp.AppendLine('- Windows App SDK runtime (self-contained in app/plugins/UI) - Microsoft Software License Terms (redistributable), https://github.com/microsoft/WindowsAppSDK')
[void]$tp.AppendLine('- Chromium Embedded Framework via CefSharp (app/plugins/cef) - BSD-style; Chromium third-party credits: https://chromium.googlesource.com/chromium/src/+/main/LICENSE and chrome://credits')
[void]$tp.AppendLine('- libVLC via VideoLAN.LibVLC.Windows (app/plugins/libvlc) - LGPL-2.1-or-later, source https://code.videolan.org/videolan/vlc')
[void]$tp.AppendLine('- Microsoft Edge WebView2 loader (app/plugins/webview2) - BSD-3-Clause (Microsoft.Web.WebView2 package). The WebView2 *runtime* is not bundled; it ships with Windows 11 / current Windows 10.')
if ($crtFiles.Count) { [void]$tp.AppendLine("- Microsoft Visual C++ runtime ($($crtFiles -join ', ')) - Visual Studio redistributable files ('Distributable Code'), copied app-locally from the build machine's VC\Redist folder") }
[void]$tp.AppendLine('')
[void]$tp.AppendLine('## NuGet packages resolved by the solution (all projects except the ConsoleDemo sample)')
[void]$tp.AppendLine('| package | version | license (nuspec) | project |')
[void]$tp.AppendLine('|---|---|---|---|')
$rows | ForEach-Object { [void]$tp.AppendLine($_) }
$tp.ToString() | Set-Content -Encoding utf8 (Join-Path $lic 'THIRD-PARTY-NOTICES.md')

# ------------------------------------------------------------------ 6. verification
Write-Step 'Verifying layout'
$required = @(
    'app/VibeLoop.exe', 'app/VibeLoop.dll', 'app/Nlog.config', 'app/Assets/Plugins/Mpv/LivelyProperties.json',
    'app/VibeLoop.scr', 'app/VibeLoop.Screensaver.exe',
    'app/plugins/UI/Lively.UI.WinUI.exe', 'app/plugins/UI/Nlog.config',
    'app/plugins/cef/Lively.Player.CefSharp.exe', 'app/plugins/cef/CefSharp.BrowserSubprocess.exe', 'app/plugins/cef/libcef.dll',
    'app/plugins/webview2/Lively.Player.WebView2.exe', 'app/plugins/webview2/Microsoft.Web.WebView2.Core.dll',
    'app/plugins/wmf/Lively.PlayerWmf.exe',
    'app/plugins/libvlc/Lively.Player.Vlc.exe',
    'app/plugins/mpv/mpv.exe',
    'app/plugins/Watchdog/Lively.Watchdog.exe',
    'test-fixtures/vibeloop-test-video.mp4', 'test-fixtures/vibeloop-test-web.zip',
    'tools/Get-VibeLoopTestState.ps1', 'docs/WINDOWS_RUNTIME_TEST_PLAN.md', 'README-TEST-PACKAGE.md',
    'licenses/LICENSE-GPL-3.0.txt', 'licenses/NOTICE.md', 'licenses/THIRD-PARTY-NOTICES.md'
)
$problems = New-Object System.Collections.Generic.List[string]
foreach ($r in $required) {
    $p = Join-Path $root $r
    if (-not (Test-Path $p)) { $problems.Add("missing: $r") } elseif ((Get-Item $p).Length -eq 0) { $problems.Add("empty: $r") }
}
# Files that must exist somewhere below a folder.
foreach ($pair in @(@('app/plugins/webview2', 'WebView2Loader.dll'), @('app/plugins/libvlc', 'libvlc.dll'), @('app/plugins/UI', '*.pri'))) {
    if (-not (Get-ChildItem (Join-Path $root $pair[0]) -Recurse -Filter $pair[1] -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        $problems.Add("missing: $($pair[0])/**/$($pair[1])")
    }
}
# Architecture of the native entry points.
foreach ($exe in 'app/VibeLoop.exe', 'app/plugins/UI/Lively.UI.WinUI.exe', 'app/plugins/mpv/mpv.exe', 'app/plugins/cef/CefSharp.BrowserSubprocess.exe') {
    $p = Join-Path $root $exe
    if (Test-Path $p) { $m = Get-PEMachine $p; if ($m -ne 'x64') { $problems.Add("not x64 ($m): $exe") } }
}
# Things that must NOT be in a test package.
foreach ($bad in 'app/Lively.exe', 'app/Lively.dll') { if (Test-Path (Join-Path $root $bad)) { $problems.Add("forbidden (upstream identity): $bad") } }
$forbidden = @(Get-ChildItem $root -Recurse -File | Where-Object { $_.Name -match '^(unins\d*\.exe|setup.*\.exe|vc_redist.*\.exe|windowsdesktop-runtime.*\.exe)$' })
foreach ($f in $forbidden) { $problems.Add("forbidden (installer): $($f.FullName.Substring($root.Length + 1))") }
if ($problems.Count) { $problems | ForEach-Object { Write-Host "::error title=Test package layout::$_" }; Fail "Test package verification failed ($($problems.Count) problem(s))." }

# ------------------------------------------------------------------ 7. info, manifest, zip
function Get-FileVer([string] $rel) { $p = Join-Path $root $rel; if (Test-Path $p) { (Get-Item $p).VersionInfo.FileVersion } else { $null } }
$files = Get-ChildItem $root -Recurse -File
$info = [ordered]@{
    name            = 'Vibe Loop Windows x64 test package'
    status          = 'TEST ONLY - NOT RUNTIME-VERIFIED. Compiled and assembled by CI; not yet started or exercised on Windows.'
    runtimeVerified = $false
    commit          = $commit
    ref             = $env:GITHUB_REF_NAME
    workflowRun     = if ($env:GITHUB_RUN_ID) { "$($env:GITHUB_SERVER_URL)/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)" } else { $null }
    builtUtc        = (Get-Date).ToUniversalTime().ToString('o')
    runner          = $env:ImageOS + ' ' + $env:ImageVersion
    configuration   = "$Configuration|x64; core and UI self-contained win-x64; .NET Framework 4.7.2 components from the solution build"
    components      = [ordered]@{
        core        = Get-FileVer 'app/VibeLoop.exe'
        ui          = Get-FileVer 'app/plugins/UI/Lively.UI.WinUI.exe'
        screensaver = Get-FileVer 'app/VibeLoop.Screensaver.exe'
        cefPlayer   = Get-FileVer 'app/plugins/cef/Lively.Player.CefSharp.exe'
        libcef      = Get-FileVer 'app/plugins/cef/libcef.dll'
        webview2    = Get-FileVer 'app/plugins/webview2/Lively.Player.WebView2.exe'
        magickNative = (Get-ChildItem $app -Recurse -Filter 'Magick.Native-Q8-x64.dll' | Select-Object -First 1 | ForEach-Object { $_.VersionInfo.FileVersion })
    }
    thirdParty      = $thirdParty
    msvcRuntime     = $crtFiles
    fileCount       = $files.Count
    totalBytes      = ($files | Measure-Object Length -Sum).Sum
    safety          = @(
        'Portable: run app\VibeLoop.exe from an unzipped folder; nothing is installed.',
        'No Inno installer, uninstaller, VC++/.NET redistributable installers or MSIX are included.',
        '"Start with Windows" defaults to off; do not enable it on a machine you care about.',
        'VibeLoop.scr is NOT registered as the Windows screensaver; never use Explorer > right-click > Install on the owner''s PC.'
    )
}
$info | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $root 'PACKAGE-INFO.json')

$manifestPath = Join-Path $root 'MANIFEST.sha256'
$lines = Get-ChildItem $root -Recurse -File | Where-Object { $_.FullName -ne $manifestPath } | Sort-Object FullName | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), ($_.FullName.Substring($root.Length + 1) -replace '\\', '/')
}
$lines | Set-Content -Encoding ascii $manifestPath

# Inventory for CI logs.
function Get-InventoryGroup([string] $full) {
    $seg = $full.Substring($root.Length + 1) -split '[\\/]'
    if ($seg.Count -ge 4 -and $seg[0] -eq 'app' -and $seg[1] -eq 'plugins') { return ($seg[0..2] -join '/') }
    if ($seg.Count -ge 3) { return ($seg[0..1] -join '/') }
    if ($seg.Count -eq 2) { return $seg[0] }
    return '.'
}
$inv = Get-ChildItem $root -Recurse -File | Group-Object { Get-InventoryGroup $_.FullName } |
    Sort-Object Name | ForEach-Object { '{0,-40} {1,6} files {2,10:N1} MB' -f $_.Name, $_.Count, (($_.Group | Measure-Object Length -Sum).Sum / 1MB) }
$inv | Set-Content -Encoding utf8 (Join-Path $logDir 'test-package-inventory.txt')
$inv | ForEach-Object { Write-Host $_ }

if (-not $SkipZip) {
    Write-Step 'Zipping'
    $zip = Join-Path $OutputDirectory "$pkgName.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Push-Location $OutputDirectory
    try { & 7z a -tzip -mx=5 $zip $pkgName | Out-Null; if ($LASTEXITCODE -ne 0) { Fail '7z zip failed' } } finally { Pop-Location }
    $zipHash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$zipHash  $pkgName.zip" | Set-Content -Encoding ascii "$zip.sha256"
    Write-Host "Package: $zip ($([Math]::Round((Get-Item $zip).Length / 1MB, 1)) MB) sha256 $zipHash"
    if ($env:GITHUB_OUTPUT) { "zip=$zip" | Out-File -Append -Encoding utf8 $env:GITHUB_OUTPUT; "name=$pkgName" | Out-File -Append -Encoding utf8 $env:GITHUB_OUTPUT }
}
if ($env:GITHUB_STEP_SUMMARY) {
    @('## Test package (NOT runtime-verified)', '', "``$pkgName``  -  $($files.Count) files, $([Math]::Round($info.totalBytes / 1MB, 1)) MB unpacked", '', '```', $inv, '```') |
        Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY
}
