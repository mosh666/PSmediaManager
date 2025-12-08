#Requires -Version 7.5.4
<#
.SYNOPSIS
Compares coverage debug information from multiple runs (local vs CI).

.DESCRIPTION
Analyzes .coverage-debug.json files to identify why coverage percentages differ
between runs. Helps debug non-deterministic coverage variations.

.PARAMETER DebugFile
Path to the debug JSON file to analyze. If multiple files exist, compares the latest
two runs.

.PARAMETER OutputPath
Path where comparison report will be saved.
#>
[CmdletBinding()]
param(
    [string]$DebugFile = (Join-Path -Path $PSScriptRoot -ChildPath '.coverage-debug.json'),
    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '.coverage-comparison.txt')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DebugInfo {
    param([string]$Path)
    if (-not (Test-Path -Path $Path)) {
        return $null
    }
    try {
        return Get-Content -Path $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to read debug file '$Path': $($_.Exception.Message)"
        return $null
    }
}

function Format-ComparisonReport {
    param(
        [Parameter(Mandatory)][object]$DebugInfo
    )

    $report = @()
    $report += "=" * 70
    $report += "COVERAGE DEBUG ANALYSIS"
    $report += "=" * 70
    $report += ""

    if ($null -eq $DebugInfo) {
        $report += "No debug information available."
        return $report -join "`n"
    }

    # Environment info
    $report += "ENVIRONMENT:"
    $report += "  Timestamp: $($DebugInfo.timestamp)"
    $report += "  OS: $($DebugInfo.environment.osVersion)"
    $report += "  PowerShell: $($DebugInfo.environment.psVersion)"
    $report += "  CI Context: $($DebugInfo.environment.ciContext)"
    $report += "  GitHub Actions: $($DebugInfo.environment.githubActions)"
    $report += ""

    # Coverage metrics
    $report += "COVERAGE METRICS:"
    $cov = $DebugInfo.coverage
    $report += "  Analyzed Commands: $($cov.analyzed)"
    $report += "  Executed Commands: $($cov.executed)"
    $report += "  Unexecuted Commands: $($cov.delta)"
    $report += "  Precise Coverage: $($cov.precise)%"
    $report += "  Rounded Coverage: $($cov.rounded)%"
    $report += ""

    # Test execution
    $report += "TEST EXECUTION:"
    $test = $DebugInfo.testExecution
    $report += "  Total Tests: $($test.totalTests)"
    $report += "  Passed: $($test.passedTests)"
    $report += "  Failed: $($test.failedTests)"
    $report += "  Skipped: $($test.skippedTests)"
    $report += "  Duration: $($test.duration) seconds"
    $report += ""

    if ($VerbosePreference -eq 'Continue') {
        $report += "RAW DEBUG DATA:"
        $report += ($DebugInfo | ConvertTo-Json -Depth 4)
    }

    return $report -join "`n"
}

function Compare-DebugInfos {
    param(
        [Parameter(Mandatory)][object]$Current,
        [Parameter(Mandatory)][object]$Previous
    )

    $report = @()
    $report += "=" * 70
    $report += "COVERAGE COMPARISON ANALYSIS"
    $report += "=" * 70
    $report += ""

    if ($null -eq $Current -or $null -eq $Previous) {
        $report += "Insufficient debug data for comparison."
        return $report -join "`n"
    }

    # Current run
    $report += "CURRENT RUN:"
    $report += "  Timestamp: $($Current.timestamp)"
    $report += "  Environment: $($Current.environment.osVersion) | PS $($Current.environment.psVersion)"
    $report += "  Analyzed: $($Current.coverage.analyzed) | Executed: $($Current.coverage.executed)"
    $report += "  Coverage: $($Current.coverage.rounded)%"
    $report += ""

    # Previous run
    $report += "PREVIOUS RUN:"
    $report += "  Timestamp: $($Previous.timestamp)"
    $report += "  Environment: $($Previous.environment.osVersion) | PS $($Previous.environment.psVersion)"
    $report += "  Analyzed: $($Previous.coverage.analyzed) | Executed: $($Previous.coverage.executed)"
    $report += "  Coverage: $($Previous.coverage.rounded)%"
    $report += ""

    # Differences
    $report += "DIFFERENCES:"
    $analyzedDiff = [int]$Current.coverage.analyzed - [int]$Previous.coverage.analyzed
    $executedDiff = [int]$Current.coverage.executed - [int]$Previous.coverage.executed
    $deltaDiff = [int]$Current.coverage.delta - [int]$Previous.coverage.delta
    $coverageDiff = [math]::Round($Current.coverage.rounded - $Previous.coverage.rounded, 2)

    $sign = if ($analyzedDiff -ge 0) { '+' } else { '' }
    $report += "  Analyzed Commands: $sign$analyzedDiff ($([int]$Current.coverage.analyzed) vs $([int]$Previous.coverage.analyzed))"
    
    $sign = if ($executedDiff -ge 0) { '+' } else { '' }
    $report += "  Executed Commands: $sign$executedDiff ($([int]$Current.coverage.executed) vs $([int]$Previous.coverage.executed))"
    
    $sign = if ($deltaDiff -ge 0) { '+' } else { '' }
    $report += "  Unexecuted Commands: $sign$deltaDiff ($([int]$Current.coverage.delta) vs $([int]$Previous.coverage.delta))"
    
    $sign = if ($coverageDiff -ge 0) { '+' } else { '' }
    $report += "  Coverage %: $sign$coverageDiff ($($Current.coverage.rounded)% vs $($Previous.coverage.rounded)%)"
    $report += ""

    # Test execution comparison
    $report += "TEST EXECUTION COMPARISON:"
    $curTest = $Current.testExecution
    $prevTest = $Previous.testExecution
    
    $sign = if (($curTest.totalTests - $prevTest.totalTests) -ge 0) { '+' } else { '' }
    $report += "  Total Tests: $($curTest.totalTests) vs $($prevTest.totalTests) (diff: $sign$($curTest.totalTests - $prevTest.totalTests))"
    
    $sign = if (($curTest.passedTests - $prevTest.passedTests) -ge 0) { '+' } else { '' }
    $report += "  Passed: $($curTest.passedTests) vs $($prevTest.passedTests) (diff: $sign$($curTest.passedTests - $prevTest.passedTests))"
    
    $sign = if (($curTest.failedTests - $prevTest.failedTests) -ge 0) { '+' } else { '' }
    $report += "  Failed: $($curTest.failedTests) vs $($prevTest.failedTests) (diff: $sign$($curTest.failedTests - $prevTest.failedTests))"
    
    $sign = if (($curTest.skippedTests - $prevTest.skippedTests) -ge 0) { '+' } else { '' }
    $report += "  Skipped: $($curTest.skippedTests) vs $($prevTest.skippedTests) (diff: $sign$($curTest.skippedTests - $prevTest.skippedTests))"
    $report += ""

    # Analysis
    $report += "ANALYSIS:"
    if ([math]::Abs($coverageDiff) -lt 0.01) {
        $report += "  ✓ Coverage is stable (< 0.01% variance)"
    }
    elseif ($analyzedDiff -ne 0) {
        $report += "  ! Analyzed commands count changed - check if coverage config differs"
    }

    if ($executedDiff -ne 0) {
        $report += "  ! Executed commands changed - some code paths may not be exercised consistently"
        $report += "    Root causes could be:"
        $report += "      - Test execution order (Pester randomizes by default)"
        $report += "      - Conditional test skipping"
        $report += "      - Non-deterministic test behavior"
        $report += "      - State-dependent code paths"
    }

    if ($curTest.totalTests -ne $prevTest.totalTests) {
        $report += "  ! Test count differs - some tests may be skipped inconsistently"
    }

    if ($curTest.failedTests -gt $prevTest.failedTests) {
        $report += "  ! More failed tests - coverage may be affected by test failures"
    }

    return $report -join "`n"
}

# Main logic
$current = Get-DebugInfo -Path $DebugFile

if ($null -eq $current) {
    Write-Warning "No debug information found at '$DebugFile'"
    Write-Host "Run tests with -CodeCoverage first: tests/Invoke-Pester.ps1 -CodeCoverage"
    exit 1
}

# Single file analysis
$report = Format-ComparisonReport -DebugInfo $current

# Try to find a previous run for comparison
$debugDir = Split-Path -Parent $DebugFile
$debugFiles = @(Get-ChildItem -Path $debugDir -Filter '.coverage-debug*.json' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 2)

if ($debugFiles.Count -ge 2) {
    $report += "`n`n"
    $previous = Get-DebugInfo -Path $debugFiles[1].FullName
    $comparisonReport = Compare-DebugInfos -Current $current -Previous $previous
    $report += $comparisonReport
}

# Output
$report | Write-Host
if ($OutputPath) {
    $report | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "`nReport saved to: $OutputPath" -ForegroundColor Cyan
}
