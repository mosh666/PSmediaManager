#Requires -Version 7.5.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsRoot = $PSScriptRoot

$latest = Join-Path -Path $testsRoot -ChildPath '.coverage-latest.json'
$debug = Join-Path -Path $testsRoot -ChildPath '.coverage-debug.json'

$outText = Join-Path -Path $testsRoot -ChildPath '.coverage-debug.txt'
$outCompare = Join-Path -Path $testsRoot -ChildPath '.coverage-comparison.txt'

if (-not (Test-Path -Path $latest)) {
    'No .coverage-latest.json found; skipping coverage comparison.' | Set-Content -Path $outCompare -Encoding utf8
    'No coverage debug info available.' | Set-Content -Path $outText -Encoding utf8
    return
}

$latestObj = Get-Content -Path $latest -Raw | ConvertFrom-Json

$debugObj = $null
if (Test-Path -Path $debug) {
    $debugObj = Get-Content -Path $debug -Raw | ConvertFrom-Json
}

$summary = @()
$summary += "Latest coverage artifact: $latest"
$summary += "GeneratedAt: $($latestObj.GeneratedAt)"
$summary += "CodeCoverageEnabled: $($latestObj.CodeCoverageEnabled)"

if ($null -ne $debugObj) {
    $summary += "Debug artifact present: $debug"
    if ($debugObj.PSObject.Properties.Match('GeneratedAt').Count -gt 0) {
        $summary += "Debug GeneratedAt: $($debugObj.GeneratedAt)"
    }
}

$summary | Set-Content -Path $outText -Encoding utf8

'Coverage comparison is best-effort; no baseline in repo yet.' | Set-Content -Path $outCompare -Encoding utf8
