<#
.SYNOPSIS
  READ-ONLY snapshot of everything a Vibe Loop test could touch, so before/after runs can be compared.

.DESCRIPTION
  Records (never modifies):
    - HKCU ...\CurrentVersion\Run values (startup entries)
    - HKCU Control Panel\Desktop screensaver and wallpaper values
    - Vibe Loop / Lively Wallpaper data and temp folders (exists, file count, newest change)
    - SHA-256 / size / last-write fingerprints of each app's settings files (Settings.json, layouts, rules, Tokens.dat)
    - a fingerprint of each app's wallpaper library (folder names + LivelyInfo.json hashes)
    - Vibe Loop / Lively Inno Setup uninstall registrations
    - running Vibe Loop / Lively / player processes with their executable paths
    - named pipes and single-instance mutexes of Vibe Loop and Lively
  Works in Windows PowerShell 5.1 and PowerShell 7. Needs no administrator rights.

.EXAMPLE
  .\Get-VibeLoopTestState.ps1 -Label before
  .\Get-VibeLoopTestState.ps1 -Label after
  .\Get-VibeLoopTestState.ps1 -Compare .\state-before.json, .\state-after.json
#>
[CmdletBinding(DefaultParameterSetName = 'Snapshot')]
param(
    [Parameter(ParameterSetName = 'Snapshot')] [string] $Label = 'snapshot',
    [Parameter(ParameterSetName = 'Snapshot')] [string] $OutFile,
    [Parameter(ParameterSetName = 'Compare', Mandatory = $true)] [string[]] $Compare
)

$ErrorActionPreference = 'Continue'

function Get-RegValues([string] $path, [string[]] $names) {
    $result = [ordered]@{}
    try {
        $key = Get-Item -LiteralPath $path -ErrorAction Stop
        $all = if ($names) { $names } else { $key.GetValueNames() }
        foreach ($n in $all) { $result[$n] = $key.GetValue($n, $null) }
    } catch { $result['<error>'] = $_.Exception.Message }
    return $result
}

function Get-FolderState([string] $path) {
    if (-not (Test-Path -LiteralPath $path)) { return [ordered]@{ path = $path; exists = $false } }
    $files = @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue)
    $newest = $files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    $newestUtc = $null; $newestFile = $null
    if ($newest) { $newestUtc = $newest.LastWriteTimeUtc.ToString('o'); $newestFile = $newest.FullName.Substring($path.Length).TrimStart('\') }
    return [ordered]@{ path = $path; exists = $true; fileCount = $files.Count; newestWriteUtc = $newestUtc; newestFile = $newestFile }
}

function Get-FileFingerprint([string] $path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [ordered]@{ exists = $false } }
    $item = Get-Item -LiteralPath $path -Force
    $hash = $null
    try { $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() } catch { $hash = "<unreadable: $($_.Exception.Message)>" }
    return [ordered]@{ exists = $true; size = $item.Length; lastWriteUtc = $item.LastWriteTimeUtc.ToString('o'); sha256 = $hash }
}

function Get-AppDataEvidence([string] $dataRoot) {
    $files = [ordered]@{}
    foreach ($n in 'Settings.json', 'WallpaperLayout.json', 'ScreenSaverLayout.json', 'AppRules.json', 'MusicAppExclusionRules.json', 'WeatherSettings.json', 'Tokens.dat') {
        $files[$n] = Get-FileFingerprint (Join-Path $dataRoot $n)
    }
    # Library location: Settings.json WallpaperDir, else the default <data>\Library.
    $libDir = Join-Path $dataRoot 'Library'
    $settingsPath = Join-Path $dataRoot 'Settings.json'
    if (Test-Path -LiteralPath $settingsPath) {
        try { $cfg = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json; if ($cfg.WallpaperDir) { $libDir = $cfg.WallpaperDir } } catch { }
    }
    $wpDir = Join-Path $libDir 'wallpapers'
    $library = [ordered]@{}
    $library['path'] = $libDir
    $library['exists'] = [bool](Test-Path -LiteralPath $wpDir)
    $library['entries'] = 0
    $library['fingerprint'] = $null
    if ($library['exists']) {
        $lines = @()
        foreach ($d in @(Get-ChildItem -LiteralPath $wpDir -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
            $info = Join-Path $d.FullName 'LivelyInfo.json'
            $h = '-'
            if (Test-Path -LiteralPath $info) { try { $h = (Get-FileHash -LiteralPath $info -Algorithm SHA256).Hash } catch { } }
            $lines += "$($d.Name)|$h"
        }
        $library['entries'] = $lines.Count
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $library['fingerprint'] = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))) | ForEach-Object { $_.ToString('x2') }) } finally { $sha.Dispose() }
    }
    return [ordered]@{ files = $files; library = $library }
}

function Test-MutexExists([string] $name) {
    $m = $null
    try { return [System.Threading.Mutex]::TryOpenExisting($name, [ref] $m) } catch { return $null } finally { if ($m) { $m.Dispose() } }
}

if ($PSCmdlet.ParameterSetName -eq 'Compare') {
    # Also accept "-Compare a.json,b.json" (a single string, e.g. when started with powershell -File).
    if ($Compare.Count -eq 1 -and $Compare[0] -match ',') { $Compare = @($Compare[0] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    if ($Compare.Count -ne 2) { throw 'Pass exactly two snapshot files: -Compare before.json, after.json' }
    $a = Get-Content -Raw $Compare[0] | ConvertFrom-Json
    $b = Get-Content -Raw $Compare[1] | ConvertFrom-Json
    $checks = @(
        @('Startup entries (HKCU Run)', 'startupRun'),
        @('Screensaver settings', 'screensaver'),
        @('Desktop wallpaper settings', 'wallpaper'),
        @('Lively Wallpaper settings files (hash/size/mtime)', 'appData.lively.files'),
        @('Lively Wallpaper library (names + LivelyInfo.json hashes)', 'appData.lively.library'),
        @('Vibe Loop settings files (hash/size/mtime)', 'appData.vibeLoop.files'),
        @('Vibe Loop library (names + LivelyInfo.json hashes)', 'appData.vibeLoop.library'),
        @('Lively Wallpaper data folder', 'folders.livelyData'),
        @('Lively Wallpaper temp folder', 'folders.livelyTemp'),
        @('Vibe Loop data folder', 'folders.vibeLoopData'),
        @('Vibe Loop temp folder', 'folders.vibeLoopTemp'),
        @('Installer registrations', 'uninstall'),
        @('Mutexes', 'mutexes')
    )
    $diff = 0
    foreach ($c in $checks) {
        $pa = $a; $pb = $b
        foreach ($part in $c[1] -split '\.') { $pa = $pa.$part; $pb = $pb.$part }
        $ja = $pa | ConvertTo-Json -Depth 5 -Compress
        $jb = $pb | ConvertTo-Json -Depth 5 -Compress
        if ($ja -ne $jb) { $diff++; Write-Host "CHANGED  $($c[0])" -ForegroundColor Yellow; Write-Host "  before: $ja"; Write-Host "  after:  $jb" }
        else { Write-Host "same     $($c[0])" -ForegroundColor Green }
    }
    Write-Host ''
    Write-Host "Processes before: $(@($a.processes).Count)  after: $(@($b.processes).Count)"
    @($b.processes) | ForEach-Object { Write-Host "  running after: $($_.name) [$($_.id)] $($_.path)" }
    Write-Host "$diff section(s) changed."
    return
}

$local = [Environment]::GetFolderPath('LocalApplicationData')
$temp = [IO.Path]::GetTempPath()
$procNames = 'VibeLoop', 'VibeLoop.UI', 'Lively', 'Lively.UI.WinUI', 'Lively.Watchdog', 'Lively.Utility.Watchdog', 'Lively.Player.CefSharp', 'CefSharp.BrowserSubprocess',
    'Lively.Player.WebView2', 'Lively.PlayerWmf', 'Lively.Player.Wmf', 'Lively.Player.Vlc', 'mpv', 'VibeLoop.Screensaver', 'VibeLoop'

$state = [ordered]@{
    label       = $Label
    takenUtc    = (Get-Date).ToUniversalTime().ToString('o')
    computer    = $env:COMPUTERNAME
    user        = $env:USERNAME
    startupRun  = Get-RegValues 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' $null
    screensaver = Get-RegValues 'HKCU:\Control Panel\Desktop' @('SCRNSAVE.EXE', 'ScreenSaveActive', 'ScreenSaveTimeOut', 'ScreenSaverIsSecure')
    wallpaper   = Get-RegValues 'HKCU:\Control Panel\Desktop' @('Wallpaper', 'WallpaperStyle', 'TileWallpaper')
    folders     = [ordered]@{
        vibeLoopData = Get-FolderState (Join-Path $local 'Vibe Loop')
        vibeLoopTemp = Get-FolderState (Join-Path $temp 'Vibe Loop')
        livelyData   = Get-FolderState (Join-Path $local 'Lively Wallpaper')
        livelyTemp   = Get-FolderState (Join-Path $temp 'Lively Wallpaper')
    }
    appData     = [ordered]@{
        vibeLoop = Get-AppDataEvidence (Join-Path $local 'Vibe Loop')
        lively   = Get-AppDataEvidence (Join-Path $local 'Lively Wallpaper')
    }
    uninstall   = [ordered]@{}
    processes   = @()
    pipes       = @()
    mutexes     = [ordered]@{
        'VIBELOOP:DESKTOPWALLPAPERSYSTEM' = Test-MutexExists 'VIBELOOP:DESKTOPWALLPAPERSYSTEM'
        'LIVELY:DESKTOPWALLPAPERSYSTEM'   = Test-MutexExists 'LIVELY:DESKTOPWALLPAPERSYSTEM'
    }
}

$ids = [ordered]@{ vibeLoop = '{93A384C2-FB92-4015-BFC7-AEDE5495C2C0}}_is1'; lively = '{E3E43E1B-DEC8-44BF-84A6-243DBA3F2CB1}}_is1' }
foreach ($k in $ids.Keys) {
    $found = @()
    foreach ($hive in 'HKCU:', 'HKLM:') {
        foreach ($view in 'Software\Microsoft\Windows\CurrentVersion\Uninstall', 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
            $p = "$hive\$view\$($ids[$k])"
            if (Test-Path -LiteralPath $p) { $found += [ordered]@{ key = $p; installLocation = (Get-ItemProperty -LiteralPath $p -ErrorAction SilentlyContinue).InstallLocation } }
        }
    }
    $state.uninstall[$k] = $found
}

$procList = @()
foreach ($p in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $procNames -contains $_.ProcessName })) {
    $path = $null; $started = $null
    try { $path = $p.Path } catch { }
    try { $started = $p.StartTime.ToUniversalTime().ToString('o') } catch { }
    $procList += [ordered]@{ name = $p.ProcessName; id = $p.Id; path = $path; started = $started }
}
$state.processes = $procList
try {
    $state.pipes = @([IO.Directory]::GetFiles('\\.\pipe\') | ForEach-Object { $_.Substring(9) } | Where-Object { $_ -match 'VIBELOOP|LIVELY|mpvsocket' })
} catch { $state.pipes = @("<error> $($_.Exception.Message)") }

if (-not $OutFile) { $OutFile = Join-Path (Get-Location) ("state-{0}.json" -f $Label) }
$state | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath $OutFile
Write-Host "Snapshot '$Label' written to $OutFile"
Write-Host ("  Run entries: {0}" -f (($state.startupRun.Keys) -join ', '))
Write-Host ("  SCRNSAVE.EXE: {0}" -f $state.screensaver['SCRNSAVE.EXE'])
Write-Host ("  Wallpaper: {0}" -f $state.wallpaper['Wallpaper'])
Write-Host ("  Vibe Loop data exists: {0}; Lively data exists: {1}" -f $state.folders.vibeLoopData.exists, $state.folders.livelyData.exists)
Write-Host ("  Settings.json sha256 - Vibe Loop: {0}; Lively: {1}" -f $state.appData.vibeLoop.files['Settings.json'].sha256, $state.appData.lively.files['Settings.json'].sha256)
Write-Host ("  Library entries - Vibe Loop: {0}; Lively: {1}" -f $state.appData.vibeLoop.library['entries'], $state.appData.lively.library['entries'])
Write-Host ("  Processes: {0}" -f ((@($state.processes) | ForEach-Object { $_.name }) -join ', '))
Write-Host ("  Pipes: {0}" -f ($state.pipes -join ', '))
