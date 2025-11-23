#Requires -Version 7.5.4
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BaselinePath = (Join-Path -Path $PSScriptRoot -ChildPath '.coverage-baseline.json'),
    [string]$LatestCoveragePath = (Join-Path -Path $PSScriptRoot -ChildPath '.coverage-latest.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CoverageObject {
    param([string]$Path)
    if (-not (Test-Path -Path $Path)) {
        return $null
    }
    return Get-Content -Path $Path -Raw | ConvertFrom-Json -ErrorAction Stop
}

$latest = Get-CoverageObject -Path $LatestCoveragePath
if ($null -eq $latest) {
    throw "Latest coverage file not found at '$LatestCoveragePath'. Run tests with -CodeCoverage first."
}

$baseline = Get-CoverageObject -Path $BaselinePath
if ($null -eq $baseline) {
    $baseline = [pscustomobject]@{
        metadata = [pscustomobject]@{
            description = 'Line coverage baseline enforced by CI. Update via tests/Update-CoverageBaseline.ps1 after legitimate coverage improvements.'
            lastUpdated = '1970-01-01T00:00:00Z'
        }
        coverage = [pscustomobject]@{
            line = 0.0
        }
    }
}

$latestLine = [math]::Round([double]$latest.line, 2)
$baselineLine = [math]::Round([double]$baseline.coverage.line, 2)

if ($latestLine -lt $baselineLine) {
    throw "Latest coverage (${latestLine}%) is lower than baseline (${baselineLine}%)."
}

if ($latestLine -le $baselineLine) {
    Write-Host "Coverage ${latestLine}% did not exceed the baseline (${baselineLine}%). No update required." -ForegroundColor Yellow
    return
}

if ($PSCmdlet.ShouldProcess($BaselinePath, "Update baseline to ${latestLine}%")) {
    $baseline.coverage.line = $latestLine
    if (-not $baseline.PSObject.Properties.Name.Contains('metadata')) {
        $baseline | Add-Member -MemberType NoteProperty -Name metadata -Value ([pscustomobject]@{})
    }
    $baseline.metadata.description = 'Line coverage baseline enforced by CI. Update via tests/Update-CoverageBaseline.ps1 after legitimate coverage improvements.'
    $baseline.metadata.lastUpdated = (Get-Date).ToString('o')

    $baseline | ConvertTo-Json -Depth 4 | Set-Content -Path $BaselinePath -Encoding UTF8
    Write-Host "Baseline updated to ${latestLine}%" -ForegroundColor Green
}
