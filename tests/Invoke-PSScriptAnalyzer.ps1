#!/usr/bin/env pwsh
# Invoke-PSScriptAnalyzer.ps1
# Runs PSScriptAnalyzer against the repository root (default) using optional settings,
# excluding the `tests` folder and other noisy directories. Writes results to
# `tests/PSScriptAnalyzerResults.json`.

#Requires -Version 7.5.4
[CmdletBinding()]
param(
    [string]$TargetPath,
    [string]$SettingsFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDirectory

# Ensure custom PSmm classes/interfaces are loaded so PSScriptAnalyzer can resolve
# types like AppConfiguration or IPathProvider during parse-time validation.
$preloadScript = Join-Path -Path $scriptDirectory -ChildPath 'Preload-PSmmTypes.ps1'
if (Test-Path -Path $preloadScript) {
    try {
        Write-Verbose "Preloading PSmm types via $preloadScript"
        . $preloadScript
    }
    catch {
        Write-Warning "Failed to preload PSmm types: $($_.Exception.Message)."
    }
}
else {
    Write-Verbose "Preload script not found at $preloadScript"
}

if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    $TargetPath = Join-Path -Path $repoRoot -ChildPath ''
}

if ([string]::IsNullOrWhiteSpace($SettingsFile)) {
    $SettingsFile = Join-Path -Path $scriptDirectory -ChildPath 'PSScriptAnalyzer.Settings.psd1'
}

Write-Verbose "PSScriptAnalyzer target: $TargetPath"
Write-Verbose "PSScriptAnalyzer settings: $SettingsFile"

if (-not (Get-Module -Name PSScriptAnalyzer -ListAvailable)) {
    throw 'PSScriptAnalyzer module is not available. Install it via: Install-Module PSScriptAnalyzer -Scope CurrentUser'
}

Import-Module PSScriptAnalyzer -ErrorAction Stop | Out-Null

if (-not (Test-Path -Path $TargetPath)) {
    throw "Target path for analysis does not exist: $TargetPath"
}

$settingsArg = $null
$settings = $null
if (Test-Path -Path $SettingsFile) {
    try {
        $settings = Import-PowerShellDataFile -Path $SettingsFile -ErrorAction Stop
        $settingsArg = $settings
    }
    catch {
        Write-Warning "Failed to load settings file $SettingsFile - $($_.Exception.Message). Continuing without settings."
        $settingsArg = $null
    }
}

# Build exclude paths (full paths) for known noisy folders
$excludePaths = @()
$possibleExcludes = @('tests','.git')
foreach ($p in $possibleExcludes) {
    $full = Join-Path -Path $repoRoot -ChildPath $p
    if (Test-Path -Path $full) { $excludePaths += $full }
}

Write-Host "Running PSScriptAnalyzer against: $TargetPath"

try {
    if ($excludePaths.Count -gt 0) {
        # Build explicit file list excluding noisy folders because this PSScriptAnalyzer version
        # may not support -ExcludePath as a parameter. We analyze script files only.
        $scriptFiles = Get-ChildItem -Path $TargetPath -Recurse -File -Include '*.ps1','*.psm1','*.psd1' -ErrorAction SilentlyContinue
        $filesToAnalyze = @()
        foreach ($f in $scriptFiles) {
            $full = $f.FullName
            $skip = $false
            foreach ($ex in $excludePaths) {
                if ($full.StartsWith($ex, [System.StringComparison]::InvariantCultureIgnoreCase)) { $skip = $true; break }
            }
            if (-not $skip) { $filesToAnalyze += $full }
        }

        if ($filesToAnalyze.Count -eq 0) {
            Write-Host 'No script files found to analyze after applying exclusions.' -ForegroundColor Yellow
            $results = @()
        }
        else {
            $allResults = @()
            foreach ($p in $filesToAnalyze) {
                if ($settingsArg) { $r = Invoke-ScriptAnalyzer -Path $p -Settings $settingsArg -ErrorAction Stop }
                else { $r = Invoke-ScriptAnalyzer -Path $p -ErrorAction Stop }
                if ($r) { $allResults += $r }
            }
            $results = $allResults
        }
    }
    else {
        if ($settingsArg) {
            $results = Invoke-ScriptAnalyzer -Path $TargetPath -Recurse -Settings $settingsArg -ErrorAction Stop
        }
        else {
            $results = Invoke-ScriptAnalyzer -Path $TargetPath -Recurse -ErrorAction Stop
        }
    }
}
catch {
    throw "PSScriptAnalyzer execution failed: $($_.Exception.Message)"
}

$outPath = Join-Path -Path $scriptDirectory -ChildPath 'PSScriptAnalyzerResults.json'

# Normalize results to an array so `.Count` checks are safe (handles single object or $null)
$results = @($results)

# Filter out noisy parse-time type errors (TypeNotFound) that are intentionally resolved at runtime
$results = @($results | Where-Object { $_.RuleName -ne 'TypeNotFound' })

if ($results -and $results.Count -gt 0) {
    Write-Host "PSScriptAnalyzer found $($results.Count) issue(s):" -ForegroundColor Yellow
    $results | Select-Object @{Name='FilePath';Expression={$_.ScriptName}}, RuleName, Severity, Line, Message | Format-Table -AutoSize

    $results | Select-Object @{Name='FilePath';Expression={$_.ScriptName}}, RuleName, Severity, Line, Message | ConvertTo-Json -Depth 6 | Set-Content -Path $outPath -Encoding UTF8
    Write-Host "Results saved to $outPath"

    $errors = $results | Where-Object { $_.Severity -eq 'Error' }
    # Normalize errors to an array so `.Count` checks are safe when a single object is returned
    $errors = @($errors)
    if ($errors.Count -gt 0) {
        throw "PSScriptAnalyzer found $($errors.Count) error(s). Treating as failure."
    }
    else {
        Write-Host "No errors found (warnings/info only)." -ForegroundColor Green
    }
}
else {
    # No results -> clean
    @() | ConvertTo-Json | Set-Content -Path $outPath -Encoding UTF8
    Write-Host 'No PSScriptAnalyzer issues found.' -ForegroundColor Green
}

return 0
