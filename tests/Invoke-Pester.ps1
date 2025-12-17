#Requires -Version 7.5.4

param(
    [Parameter()][switch]$CodeCoverage,
    [Parameter()][switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Tell tools/test runners we are in CI mode without forcing Invoke-Pester into the 'Simple' parameter set.
$env:CI = 'true'

$testsRoot = $PSScriptRoot
$repoRoot = Split-Path -Path $testsRoot -Parent

$versionsPath = Join-Path -Path $repoRoot -ChildPath 'build/versions.psd1'
if (-not (Test-Path -Path $versionsPath)) {
    throw "Missing versions manifest: $versionsPath"
}

$versions = Import-PowerShellDataFile -Path $versionsPath
$pesterVersion = $versions.Modules.Pester

if ([string]::IsNullOrWhiteSpace($pesterVersion)) {
    throw 'Pester version is not defined in build/versions.psd1'
}

try {
    Import-Module -Name Pester -RequiredVersion $pesterVersion -ErrorAction Stop
}
catch {
    Write-Verbose "Pester $pesterVersion not found locally; attempting install..."
    try {
        Install-Module -Name Pester -RequiredVersion $pesterVersion -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Import-Module -Name Pester -RequiredVersion $pesterVersion -ErrorAction Stop
    }
    catch {
        throw "Failed to import or install Pester $pesterVersion. Install it manually with: Install-Module Pester -RequiredVersion $pesterVersion -Scope CurrentUser"
    }
}

$testResultPath = Join-Path -Path $testsRoot -ChildPath 'TestResults.xml'

$config = New-PesterConfiguration

$config.Run.Path = @($testsRoot)
$config.Run.PassThru = $true

$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = $testResultPath

if ($Quiet) {
    $config.Output.Verbosity = 'None'
}

if ($CodeCoverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = @(
        Join-Path -Path $repoRoot -ChildPath 'src'
    )
    $config.CodeCoverage.OutputPath = (Join-Path -Path $testsRoot -ChildPath 'coverage.xml')
}

Write-Verbose "Running Pester in: $testsRoot"
$result = Invoke-Pester -Configuration $config

# Emit lightweight coverage artifacts for CI upload (best-effort)
try {
    $coveragePath = Join-Path -Path $testsRoot -ChildPath '.coverage-latest.json'
    $coverageDebugPath = Join-Path -Path $testsRoot -ChildPath '.coverage-debug.json'

    $coverageObj = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('o')
        CodeCoverageEnabled = [bool]$CodeCoverage
        CodeCoverage = $result.CodeCoverage
    }

    $coverageObj | ConvertTo-Json -Depth 20 | Set-Content -Path $coveragePath -Encoding utf8
    $coverageObj | ConvertTo-Json -Depth 20 | Set-Content -Path $coverageDebugPath -Encoding utf8
}
catch {
    Write-Verbose "Failed to write coverage artifacts: $_"
}

if (-not $result -or -not $result.Passed) {
    throw 'Pester tests failed'
}
