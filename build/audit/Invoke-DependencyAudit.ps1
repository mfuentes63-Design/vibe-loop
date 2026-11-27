<#
.SYNOPSIS
  Vibe Loop explicit NuGet dependency audit (CI and local).

.DESCRIPTION
  Collects dependency findings from two independent sources and writes a JSON + Markdown report:
    1. NuGet restore audit warnings from the MSBuild log (NU1901-NU1904 advisories, NU1605 downgrades,
       NU1608 out-of-range dependencies). Covers SDK-style and legacy .NET Framework projects.
    2. `dotnet list <project> package --vulnerable --include-transitive --format json` for every
       SDK-style project (the shared .shproj and legacy projects are skipped - covered by source 1).

  Policy (nothing is suppressed; the audit fails CLOSED when it cannot see everything):
    - FAIL  : any advisory at or above -FailOnSeverity (default: high), any NU1605 downgrade,
              any `dotnet list` tool error or an SDK-style project that was not audited (unless -AllowToolErrors),
              a restore log that contains no restore output.
    - WARN  : advisories below the threshold, NU1608.
  "PASS" is policy-specific: it means no finding at or above the threshold, NOT "no vulnerabilities".

.PARAMETER RestoreLog
  MSBuild text log that contains the restore output (e.g. artifacts/logs/build.log).

.EXAMPLE
  pwsh build/audit/Invoke-DependencyAudit.ps1 -RestoreLog artifacts/logs/build.log -OutDir artifacts/audit
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RestoreLog,
    [string] $SourceRoot = (Join-Path $PSScriptRoot '../../src/Lively'),
    [string] $OutDir = 'artifacts/audit',
    [ValidateSet('low', 'moderate', 'high', 'critical')] [string] $FailOnSeverity = 'high',
    [switch] $SkipDotnetList,
    [switch] $AllowToolErrors
)

$ErrorActionPreference = 'Stop'
trap {
    $pos = if ($_.InvocationInfo) { $_.InvocationInfo.PositionMessage } else { '' }
    Write-Host "::error title=Dependency audit script failed (audit result unknown)::$($_.Exception.Message) $($pos -replace '\r?\n', ' ')"
    Write-Host $_.ScriptStackTrace
    exit 1
}
$rank = @{ low = 1; moderate = 2; high = 3; critical = 4 }
$codeSeverity = @{ NU1901 = 'low'; NU1902 = 'moderate'; NU1903 = 'high'; NU1904 = 'critical' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$SourceRoot = (Resolve-Path $SourceRoot).Path

function Get-ProjectName([string] $path) { [IO.Path]::GetFileNameWithoutExtension(($path -replace '\\', '/')) }

# ---------------------------------------------------------------- 1. restore log
$advisories = @{}   # key: package|version|advisory -> object
$downgrades = @{}
$outOfRange = @{}
if (-not (Test-Path $RestoreLog)) { throw "Restore log not found: $RestoreLog" }

$advRegex = [regex] '(?<proj>[^\s:]+\.csproj)\s*:\s*warning (?<code>NU190[1-4]): Package ''(?<pkg>[^'']+)'' (?<ver>\S+) has a known (?<sev>low|moderate|high|critical) severity vulnerability, (?<url>https://\S+)'
$downRegex = [regex] '(?<proj>[^\s:]+\.csproj)\s*:\s*(?:warning|error) NU1605: Detected package downgrade: (?<pkg>\S+) from (?<from>\S+) to (?<to>\S+)'
$rangeRegex = [regex] '(?<proj>[^\s:]+\.csproj)\s*:\s*warning NU1608: (?<msg>.+?)(?:\s+\[|$)'

$logLines = [IO.File]::ReadAllLines((Resolve-Path $RestoreLog).Path)
$restoreSeen = $false
foreach ($l in $logLines) { if ($l -match 'Determining projects to restore|Restored .+\.csproj|All projects are up-to-date for restore') { $restoreSeen = $true; break } }
for ($i = 0; $i -lt $logLines.Length; $i++) {
    $line = [string]$logLines[$i]
    $ma = $advRegex.Match($line)
    $md = $downRegex.Match($line)
    $mr = $rangeRegex.Match($line)
    if ($ma.Success) {
        $url = $ma.Groups['url'].Value.TrimEnd([char[]]@('.', ']'))
        $key = "$($ma.Groups['pkg'].Value)|$($ma.Groups['ver'].Value)|$url"
        if (-not $advisories.ContainsKey($key)) {
            $advisories[$key] = @{
                package = $ma.Groups['pkg'].Value; version = $ma.Groups['ver'].Value
                severity = $ma.Groups['sev'].Value; advisory = $url; code = $ma.Groups['code'].Value
                projects = @{}; sources = @{}
            }
        }
        $advisories[$key].projects[(Get-ProjectName $ma.Groups['proj'].Value)] = $true
        $advisories[$key].sources['restore'] = $true
    }
    elseif ($md.Success) {
        $proj = Get-ProjectName $md.Groups['proj'].Value
        $downgrades["$proj|$($md.Groups['pkg'].Value)"] = @{ project = $proj; package = $md.Groups['pkg'].Value; from = $md.Groups['from'].Value; to = $md.Groups['to'].Value.TrimEnd([char[]]@('.')) }
    }
    elseif ($mr.Success) {
        $proj = Get-ProjectName $mr.Groups['proj'].Value
        $outOfRange["$proj|$($mr.Groups['msg'].Value)"] = @{ project = $proj; message = $mr.Groups['msg'].Value.Trim() }
    }
}

# ---------------------------------------------------------------- 2. dotnet list (SDK-style projects)
$toolErrors = New-Object System.Collections.Generic.List[object]
$listedProjects = New-Object System.Collections.Generic.List[string]
$sdkProjectCount = 0
if (-not $SkipDotnetList) {
    $projects = Get-ChildItem -Path $SourceRoot -Recurse -Filter *.csproj | Where-Object {
        $_.FullName -notmatch '[\\/](bin|obj)[\\/]' -and (Get-Content $_.FullName -TotalCount 3 | Select-String -SimpleMatch '<Project Sdk=' -Quiet)
    }
    $projects = @($projects)
    $sdkProjectCount = $projects.Count
    foreach ($p in $projects) {
        $name = $p.BaseName
        $raw = & dotnet list $p.FullName package --vulnerable --include-transitive --format json 2>&1
        $text = ($raw | Out-String)
        $jsonStart = $text.IndexOf('{')
        if ($LASTEXITCODE -ne 0 -or $jsonStart -lt 0) {
            $toolErrors.Add([ordered]@{ project = $name; error = ($text.Trim() -split "`n" | Select-Object -Last 3) -join ' ' })
            continue
        }
        $listedProjects.Add($name)
        $json = $text.Substring($jsonStart) | ConvertFrom-Json
        foreach ($proj in @($json.projects)) {
            foreach ($fw in @($proj.frameworks)) {
                foreach ($pkg in @($fw.topLevelPackages) + @($fw.transitivePackages)) {
                    if (-not $pkg -or -not $pkg.vulnerabilities) { continue }
                    foreach ($v in @($pkg.vulnerabilities)) {
                        $sev = "$($v.severity)".ToLowerInvariant()
                        $url = "$($v.advisoryurl)"
                        $key = "$($pkg.id)|$($pkg.resolvedVersion)|$url"
                        if (-not $advisories.ContainsKey($key)) {
                            $code = $null
                            foreach ($c in $codeSeverity.Keys) { if ($codeSeverity[$c] -eq $sev) { $code = $c } }
                            $advisories[$key] = @{
                                package = "$($pkg.id)"; version = "$($pkg.resolvedVersion)"; severity = $sev; advisory = $url
                                code = $code; projects = @{}; sources = @{}
                            }
                        }
                        $advisories[$key].projects[$name] = $true
                        $advisories[$key].sources['dotnet-list'] = $true
                    }
                }
            }
        }
    }
}

# ---------------------------------------------------------------- evaluate + report
$threshold = $rank[$FailOnSeverity]
$adv = @(foreach ($a in $advisories.Values) {
        [pscustomobject]@{
            severity = $a.severity; package = $a.package; version = $a.version; advisory = $a.advisory; code = $a.code
            projects = @($a.projects.Keys | Sort-Object); sources = @($a.sources.Keys | Sort-Object)
            rank = [int]$rank[$a.severity]
        }
    })
$adv = @($adv | Sort-Object -Property @{ Expression = 'rank'; Descending = $true }, package, advisory)
$blocking = @($adv | Where-Object { $rank[$_.severity] -ge $threshold })
$nonBlocking = @($adv | Where-Object { $rank[$_.severity] -lt $threshold })
$down = @($downgrades.Values | ForEach-Object { [pscustomobject]$_ })
$range = @($outOfRange.Values | ForEach-Object { [pscustomobject]$_ })
$coverageGap = (-not $SkipDotnetList) -and ($listedProjects.Count -lt $sdkProjectCount)
$toolFailure = (($toolErrors.Count -gt 0) -or $coverageGap) -and (-not $AllowToolErrors)
$failed = ($blocking.Count -gt 0) -or ($down.Count -gt 0) -or $toolFailure -or (-not $restoreSeen)

$resultText = 'PASS'
if ($failed) { $resultText = 'FAIL' }
$bySeverity = [ordered]@{}
foreach ($s in 'critical', 'high', 'moderate', 'low') { $bySeverity[$s] = @($adv | Where-Object severity -eq $s).Count }

$report = [ordered]@{}
$report['generatedUtc'] = (Get-Date).ToUniversalTime().ToString('o')
$toolNote = ''
if ($AllowToolErrors) { $toolNote = ' (tool errors allowed by -AllowToolErrors)' }
$report['policy'] = "fail on severity >= $FailOnSeverity, NU1605 downgrades, audit tool errors / unaudited SDK projects$toolNote and missing restore output; nothing suppressed; PASS is policy-specific, not 'no vulnerabilities'"
$report['result'] = $resultText
$report['advisoryCounts'] = $bySeverity
$report['advisories'] = $adv
$report['downgrades'] = $down
$report['outOfRange'] = $range
$report['dotnetListProjects'] = $listedProjects.ToArray()
$report['toolErrors'] = $toolErrors.ToArray()
$report['coverage'] = [ordered]@{}
$report['coverage']['restoreOutputSeen'] = [bool]$restoreSeen
$report['coverage']['sdkProjectsFound'] = $sdkProjectCount
$report['coverage']['sdkProjectsAudited'] = $listedProjects.Count
$report['coverage']['toolErrors'] = $toolErrors.Count
$report['coverage']['dotnetListSkipped'] = [bool]$SkipDotnetList
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $OutDir 'dependency-audit.json')

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("## Dependency audit: **$($report.result)**")
[void]$md.AppendLine('')
[void]$md.AppendLine("Policy: $($report.policy).")
[void]$md.AppendLine('')
[void]$md.AppendLine("| critical | high | moderate | low | downgrades (NU1605) | out-of-range (NU1608) |")
[void]$md.AppendLine("|---|---|---|---|---|---|")
[void]$md.AppendLine("| $($bySeverity.critical) | $($bySeverity.high) | $($bySeverity.moderate) | $($bySeverity.low) | $($down.Count) | $($range.Count) |")
[void]$md.AppendLine('')
if ($adv.Count) {
    [void]$md.AppendLine('### Advisories')
    [void]$md.AppendLine('| severity | package | version | advisory | projects | source |')
    [void]$md.AppendLine('|---|---|---|---|---|---|')
    foreach ($a in $adv) { [void]$md.AppendLine("| $($a.severity) | $($a.package) | $($a.version) | $($a.advisory) | $($a.projects -join ', ') | $($a.sources -join ', ') |") }
    [void]$md.AppendLine('')
}
if ($down.Count) {
    [void]$md.AppendLine('### Package downgrades')
    foreach ($d in $down) { [void]$md.AppendLine("- $($d.project): $($d.package) $($d.from) -> $($d.to)") }
    [void]$md.AppendLine('')
}
if ($range.Count) {
    [void]$md.AppendLine('### Out-of-range dependencies (NU1608)')
    foreach ($r in $range) { [void]$md.AppendLine("- $($r.project): $($r.message)") }
    [void]$md.AppendLine('')
}
[void]$md.AppendLine("Coverage: restore output seen = $restoreSeen; dotnet list audited $($listedProjects.Count) of $sdkProjectCount SDK-style projects; tool errors: $($toolErrors.Count).")
[void]$md.AppendLine('')
[void]$md.AppendLine('> PASS is policy-specific: no finding at or above the threshold. Advisories below it are listed above and remain open.')
foreach ($t in $toolErrors) { [void]$md.AppendLine("- $($t.project): $($t.error)") }
$md.ToString() | Set-Content -Encoding utf8 (Join-Path $OutDir 'dependency-audit.md')
if ($env:GITHUB_STEP_SUMMARY) { $md.ToString() | Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY }

# Annotations
$inGha = [bool]$env:GITHUB_ACTIONS
foreach ($a in $blocking) { if ($inGha) { Write-Host "::error title=Vulnerable dependency ($($a.severity))::$($a.package) $($a.version) - $($a.advisory) [$($a.projects -join ', ')]" } }
foreach ($d in $down) { if ($inGha) { Write-Host "::error title=Package downgrade (NU1605)::$($d.project): $($d.package) $($d.from) -> $($d.to)" } }
$nonBlocking | Group-Object package, version | ForEach-Object {
    if ($inGha) { Write-Host "::warning title=Dependency advisories below threshold::$($_.Name): $($_.Count) advisory(ies) ($((($_.Group.severity) | Sort-Object -Unique) -join ', '))" }
}
foreach ($t in $toolErrors) { if ($inGha) { Write-Host "::error title=dotnet list failed (audit fails closed)::$($t.project): $($t.error)" } }
if ($coverageGap -and $inGha) { Write-Host "::error title=Audit coverage gap::dotnet list audited $($listedProjects.Count) of $sdkProjectCount SDK-style projects" }
if (-not $restoreSeen -and $inGha) { Write-Host "::error title=Audit input invalid::$RestoreLog contains no NuGet restore output" }

Write-Host ("Dependency audit {0}: critical={1} high={2} moderate={3} low={4} downgrades={5} toolErrors={6} sdkProjectsAudited={7}/{8} restoreOutputSeen={9}" -f $report.result, $bySeverity.critical, $bySeverity.high, $bySeverity.moderate, $bySeverity.low, $down.Count, $toolErrors.Count, $listedProjects.Count, $sdkProjectCount, $restoreSeen)
if ($failed) { exit 1 }
exit 0
