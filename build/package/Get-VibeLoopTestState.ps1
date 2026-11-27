<#
.SYNOPSIS
  READ-ONLY snapshot of everything a Vibe Loop test could touch, so before/after runs can be compared.

.DESCRIPTION
  Records (never modifies):
    - HKCU ...\CurrentVersion\Run values (startup entries)
    - HKCU Control Panel\Desktop screensaver and wallpaper values
    - Vibe Loop / Lively Wallpaper data and temp folders (exists, file count, newest change)
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
    return [ordered]@{
        path = $path; exists = $true; fileCount = $files.Count
        newestWriteUtc = if ($newest) { $newest.LastWriteTimeUtc.ToString('o') } else { $null }
        newestFile = if ($newest) { $newest.FullName.Substring($path.Length).TrimStart('\') } else { $null }
    }
}

function Test-MutexExists([string] $name) {
    $m = $null
    try { return [System.Threading.Mutex]::TryOpenExisting($name, [ref] $m) } catch { return $null } finally { if ($m) { $m.Dispose() } }
}

if ($PSCmdlet.ParameterSetName -eq 'Compare') {
    if ($Compare.Count -ne 2) { throw 'Pass exactly two snapshot files: -Compare before.json, after.json' }
    $a = Get-Content -Raw $Compare[0] | ConvertFrom-Json
    $b = Get-Content -Raw $Compare[1] | ConvertFrom-Json
    $checks = @(
        @('Startup entries (HKCU Run)', 'startupRun'),
        @('Screensaver settings', 'screensaver'),
        @('Desktop wallpaper settings', 'wallpaper'),
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
$procNames = 'VibeLoop', 'Lively', 'Lively.UI.WinUI', 'Lively.Watchdog', 'Lively.Utility.Watchdog', 'Lively.Player.CefSharp', 'CefSharp.BrowserSubprocess',
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

$state.processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $procNames -contains $_.ProcessName } | ForEach-Object {
        $path = $null; try { $path = $_.Path } catch { }
        [ordered]@{ name = $_.ProcessName; id = $_.Id; path = $path; started = $(try { $_.StartTime.ToUniversalTime().ToString('o') } catch { $null }) }
    })
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
Write-Host ("  Processes: {0}" -f ((@($state.processes) | ForEach-Object { $_.name }) -join ', '))
Write-Host ("  Pipes: {0}" -f ($state.pipes -join ', '))
