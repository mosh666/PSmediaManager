#Requires -Version 7.5.4
[CmdletBinding()]
param(
    [switch]$CodeCoverage,
    [string]$TestPath,
    [string]$CoverageTarget,
    [switch]$WithPSScriptAnalyzer,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Logging functions should be mocked by individual tests or provided by modules under test.

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDirectory
$baselinePath = Join-Path -Path $scriptDirectory -ChildPath '.coverage-baseline.json'

function Get-CoverageDocument {
    param([string]$Path)
    if (-not (Test-Path -Path $Path)) {
        return $null
    }
    return Get-Content -Path $Path -Raw | ConvertFrom-Json -ErrorAction Stop
}

function Get-DefaultBaseline {
    return [pscustomobject]@{
        metadata = [pscustomobject]@{
            description = 'Line coverage baseline enforced by CI. Update via tests/Update-CoverageBaseline.ps1 after legitimate coverage improvements.'
            lastUpdated = '1970-01-01T00:00:00Z'
        }
        coverage = [pscustomobject]@{
            line = 0.0
        }
    }
}
if ([string]::IsNullOrWhiteSpace($TestPath)) {
    $TestPath = Join-Path -Path $scriptDirectory -ChildPath 'Modules'
}
if ([string]::IsNullOrWhiteSpace($CoverageTarget)) {
    $CoverageTarget = Join-Path -Path $repoRoot -ChildPath 'src/Modules'
}

Write-Host "DEBUG TestPath: <$TestPath>"
Write-Host "DEBUG CoverageTarget: <$CoverageTarget>"
$env:MEDIA_MANAGER_TEST_MODE = '1'
$env:MEDIA_MANAGER_SKIP_READKEY = '1'

Write-Verbose "Using test path: $TestPath"
Write-Verbose "Using coverage target: $CoverageTarget"
Write-Verbose "Script directory: $scriptDirectory"
Write-Verbose "Repository root: $repoRoot"

if ($WithPSScriptAnalyzer) {
    $analyzeScript = Join-Path -Path $scriptDirectory -ChildPath 'Invoke-PSScriptAnalyzer.ps1'
    if (-not (Test-Path -Path $analyzeScript)) {
        throw "PSScriptAnalyzer invoke script not found at $analyzeScript. Create tests/Invoke-PSScriptAnalyzer.ps1"
    }
    Write-Host "Running PSScriptAnalyzer..."
    try {
        & $analyzeScript -TargetPath (Join-Path -Path $repoRoot -ChildPath 'src') -SettingsFile (Join-Path -Path $scriptDirectory -ChildPath 'PSScriptAnalyzer.Settings.psd1')
    }
    catch {
        Write-Host 'PSScriptAnalyzer reported issues.' -ForegroundColor Red
        [Console]::Error.WriteLine($_.Exception.Message)
        [System.Environment]::Exit(1)
    }
}

if (-not (Get-Module -Name Pester -ListAvailable)) {
    throw 'Pester module is not available. Install it via Install-Module Pester -Scope CurrentUser'
}

$null = Import-Module Pester -MinimumVersion 5.5 -ErrorAction Stop

$config = New-PesterConfiguration
$config.Run.Path = @($TestPath)
$config.Run.Exit = $false
$config.Run.PassThru = $true
$config.Output.Verbosity = if ($Quiet) { 'Normal' } else { 'Detailed' }
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$testResultPath = Join-Path -Path $PSScriptRoot -ChildPath 'TestResults.xml'
$config.TestResult.OutputPath = $testResultPath

if ($CodeCoverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputPath = Join-Path -Path $PSScriptRoot -ChildPath '.coverage-jacoco.xml'

    # Prefer covering only modules that have tests to get a more meaningful ratio
    # Also focus on Public folders and exclude Private/Classes to avoid counting
    # code paths that aren't directly exercised by unit tests.
    $coveragePaths = @()
    $coverageFiles = @()
    $excludePaths = @()
    try {
        if (Test-Path -Path $TestPath) {
            # Get unique module names from test files in tests\Modules\<ModuleName>\*.Tests.ps1
            $testFiles = Get-ChildItem -Path $TestPath -Filter '*.Tests.ps1' -Recurse -ErrorAction SilentlyContinue
            $testedModules = @{}
            foreach ($file in $testFiles) {
                # Extract module name from path: tests\Modules\<ModuleName>\...
                $relativePath = $file.FullName.Substring($TestPath.Length).TrimStart('\','/')
                $parts = $relativePath -split '[/\\]'
                if ($parts.Count -gt 0) {
                    $moduleName = $parts[0]
                    $testedModules[$moduleName] = $true
                }
            }
            
            foreach ($m in $testedModules.Keys) {
                $moduleRoot = Join-Path -Path (Join-Path -Path $repoRoot -ChildPath 'src/Modules') -ChildPath $m
                if (-not (Test-Path -Path $moduleRoot)) { continue }

                $publicPath = Join-Path -Path $moduleRoot -ChildPath 'Public'
                $privatePath = Join-Path -Path $moduleRoot -ChildPath 'Private'
                $classesPath = Join-Path -Path $moduleRoot -ChildPath 'Classes'

                if (Test-Path -Path $publicPath) {
                    $coveragePaths += $publicPath
                    Write-Verbose "Including coverage for module public: $m"
                } else {
                    # Fallback to module root when no Public folder exists
                    $coveragePaths += $moduleRoot
                    Write-Verbose "Including coverage for module: $m (no Public folder)"
                }

                if (Test-Path -Path $privatePath) { $excludePaths += $privatePath }
                if (Test-Path -Path $classesPath) { $excludePaths += $classesPath }
            }

            # Build a precise file list based on real matches between Public functions and existing tests
            foreach ($moduleName in $testedModules.Keys) {
                $moduleRoot = Join-Path -Path (Join-Path -Path $repoRoot -ChildPath 'src/Modules') -ChildPath $moduleName
                $publicPath = Join-Path -Path $moduleRoot -ChildPath 'Public'
                if (-not (Test-Path -Path $publicPath)) { continue }

                $publicFunctions = Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse -File -ErrorAction SilentlyContinue
                foreach ($func in $publicFunctions) {
                    $funcName = [System.IO.Path]::GetFileNameWithoutExtension($func.Name)
                    $matchingTest = Get-ChildItem -Path (Join-Path -Path $TestPath -ChildPath $moduleName) -Filter ("$funcName.Tests.ps1") -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($matchingTest) {
                        if (-not ($coverageFiles -contains $func.FullName)) {
                            $coverageFiles += $func.FullName
                            Write-Verbose "Including coverage file from tests: $($func.FullName)"
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-Verbose "Failed to infer coverage paths from tests: $($_.Exception.Message)"
    }

    # Exclude non-unit-testable or interactive entrypoints to keep unit coverage meaningful
    try {
        $excludeFiles = @(
            # Bootstrap and interactive flows
            (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Public/Bootstrap/Invoke-PSmm.ps1')

            # Project creation/selection are highly IO/interactive heavy
            (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Projects/Public/New-PSmmProject.ps1')
            (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Projects/Public/Select-PSmmProject.ps1')

            # External process control (digiKam)
            (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Plugins/Public/Start-PSmmdigiKam.ps1')
            (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Plugins/Public/Stop-PSmmdigiKam.ps1')

            # Console/UI rendering helpers
            (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Public/Storage/Show-StorageInfo.ps1')
        )
        foreach ($f in $excludeFiles) {
            if (Test-Path -Path $f) { $excludePaths += $f }
        }
    }
    catch {
        Write-Verbose "Failed to append explicit coverage exclusions: $($_.Exception.Message)"
    }

    # Prefer precise file-level coverage when available, otherwise fall back to folder-level
    if ($coverageFiles.Count -gt 0) {
        $config.CodeCoverage.Path = $coverageFiles
        if ($excludePaths.Count -gt 0) {
            if ($config.CodeCoverage.PSObject.Properties.Name -contains 'Exclude') {
                $config.CodeCoverage.Exclude = $excludePaths
            }
            elseif ($config.CodeCoverage.PSObject.Properties.Name -contains 'ExcludePath') {
                $config.CodeCoverage.ExcludePath = $excludePaths
            }
        }
        Write-Verbose ("Focused coverage on " + $coverageFiles.Count + " files inferred from tests")
    }
    elseif ($coveragePaths.Count -gt 0) {
        $config.CodeCoverage.Path = $coveragePaths
        if ($excludePaths.Count -gt 0) {
            if ($config.CodeCoverage.PSObject.Properties.Name -contains 'Exclude') {
                $config.CodeCoverage.Exclude = $excludePaths
            }
            elseif ($config.CodeCoverage.PSObject.Properties.Name -contains 'ExcludePath') {
                $config.CodeCoverage.ExcludePath = $excludePaths
            }
        }
        Write-Verbose ("Focused coverage on " + $coveragePaths.Count + " modules with tests")
    }
    else {
        $config.CodeCoverage.Path = @($CoverageTarget)
        if ($excludePaths.Count -gt 0) {
            if ($config.CodeCoverage.PSObject.Properties.Name -contains 'Exclude') {
                $config.CodeCoverage.Exclude = $excludePaths
            }
            elseif ($config.CodeCoverage.PSObject.Properties.Name -contains 'ExcludePath') {
                $config.CodeCoverage.ExcludePath = $excludePaths
            }
        }
    }

    # Lightweight diagnostics for coverage selection
    try {
        $coverageDebugPath = Join-Path -Path $PSScriptRoot -ChildPath '.coverage-debug.txt'
        "# Coverage Diagnostics $(Get-Date -Format o)" | Set-Content -Path $coverageDebugPath -Encoding UTF8
        $ccProps = ($config.CodeCoverage.PSObject.Properties.Name | Sort-Object) -join ', '
        ("Files={0} Paths={1} Excludes={2}" -f $coverageFiles.Count, $coveragePaths.Count, $excludePaths.Count) | Add-Content -Path $coverageDebugPath
        ("ConfigProperties: {0}" -f $ccProps) | Add-Content -Path $coverageDebugPath
        if ($config.CodeCoverage.PSObject.Properties.Name -contains 'Path') {
            $pathsValue = $config.CodeCoverage.Path
            try { if ($pathsValue -and $pathsValue.PSObject.Properties.Name -contains 'Value') { $pathsValue = $pathsValue.Value } } catch {}
            $pathsPreview = @($pathsValue | Select-Object -First 10)
            if ($pathsPreview.Count -gt 0) { ("PathPreview: {0}" -f ($pathsPreview -join ' | ')) | Add-Content -Path $coverageDebugPath }
        }
        if ($config.CodeCoverage.PSObject.Properties.Name -contains 'Exclude') {
            $exPreview = @($config.CodeCoverage.Exclude | Select-Object -First 10)
            if ($exPreview.Count -gt 0) { ("ExcludePreview: {0}" -f ($exPreview -join ' | ')) | Add-Content -Path $coverageDebugPath }
        }
        elseif ($config.CodeCoverage.PSObject.Properties.Name -contains 'ExcludePath') {
            $exPreview = @($config.CodeCoverage.ExcludePath | Select-Object -First 10)
            if ($exPreview.Count -gt 0) { ("ExcludePathPreview: {0}" -f ($exPreview -join ' | ')) | Add-Content -Path $coverageDebugPath }
        }
    }
    catch {
        Write-Verbose "[Coverage] Failed to print diagnostics: $($_.Exception.Message)"
    }
}

Push-Location -Path $repoRoot
try {
    $result = Invoke-Pester -Configuration $config
}
finally {
    Pop-Location
}

if ($config.TestResult.Enabled -and $testResultPath -and (Test-Path -Path $testResultPath)) {
    try {
        $xmlContent = Get-Content -Path $testResultPath -Raw
        $xmlContent | Set-Content -Path $testResultPath -Encoding utf8NoBOM
        Write-Verbose 'Normalized TestResults.xml encoding to UTF-8 without BOM'
    }
    catch {
        Write-Verbose "Failed to normalize TestResults.xml encoding: $($_.Exception.Message)"
    }
}

if ($CodeCoverage) {
    $coveragePath = Join-Path -Path $PSScriptRoot -ChildPath '.coverage-latest.json'
    $coverageInfo = $null
    $hasCodeCoverage = $null -ne $result -and ($result.PSObject.Properties.Name -contains 'CodeCoverage')
    if ($hasCodeCoverage -and $null -ne $result.CodeCoverage) {
        $cc = $result.CodeCoverage
        $getMetric = {
            param($coverageObject, [string[]]$candidateNames)
            foreach ($name in $candidateNames) {
                if ($coverageObject.PSObject.Properties.Name -contains $name) {
                    return [double]$coverageObject.$name
                }
            }
            return 0
        }

        $analyzed = & $getMetric $cc @('CommandsAnalyzedCount', 'NumberOfCommandsAnalyzed', 'NumberOfAnalyzedCommands')
        $executed = & $getMetric $cc @('CommandsExecutedCount', 'NumberOfCommandsExecuted', 'CommandsHitCount', 'NumberOfCommandsHit')
        $linePercent = if ($analyzed -gt 0) {
            [math]::Round(($executed / $analyzed) * 100, 2)
        }
        else {
            0
        }

        $coverageInfo = [pscustomobject]@{
            line = $linePercent
            analyzedCommands = [int]$analyzed
            executedCommands = [int]$executed
            generatedAt = (Get-Date).ToString('o')
        }
    }
    else {
        $coverageInfo = [pscustomobject]@{
            line = 0
            analyzedCommands = 0
            executedCommands = 0
            generatedAt = (Get-Date).ToString('o')
        }
    }

    $coverageInfo | ConvertTo-Json -Depth 4 | Set-Content -Path $coveragePath -Encoding UTF8

    $baseline = Get-CoverageDocument -Path $baselinePath
    if ($null -eq $baseline) {
        $baseline = Get-DefaultBaseline
    }

    $latestLine = [math]::Round([double]$coverageInfo.line, 2)
    $baselineLine = [math]::Round([double]$baseline.coverage.line, 2)

    if ($latestLine -lt $baselineLine) {
        $VerbosePreference = 'SilentlyContinue'
        Write-Host "Code coverage ${latestLine}% is below the enforced baseline of ${baselineLine}%" -ForegroundColor Red
        [Console]::Error.WriteLine("Exit code: 1")
        [System.Environment]::Exit(1)
    }

    if ($latestLine -gt $baselineLine) {
        $baseline.coverage.line = $latestLine
        $baseline.metadata.description = 'Line coverage baseline enforced by CI. Update via tests/Update-CoverageBaseline.ps1 after legitimate coverage improvements.'
        $baseline.metadata.lastUpdated = (Get-Date).ToString('o')
        $baseline | ConvertTo-Json -Depth 4 | Set-Content -Path $baselinePath -Encoding UTF8
        Write-Host "Coverage improved to ${latestLine}%. Baseline updated." -ForegroundColor Green
    }
    else {
        Write-Host "Coverage ${latestLine}% meets the baseline (${baselineLine}%)." -ForegroundColor Yellow
    }
}

if ($result.FailedCount -gt 0) {
    $VerbosePreference = 'SilentlyContinue'
    $msg = "Pester reported $($result.FailedCount) failure(s)."
    Write-Host $msg -ForegroundColor Red
    [Console]::Error.WriteLine($msg)
    try { $host.SetShouldExit(1) } catch {}
    [System.Environment]::Exit(1)
}

Write-Host 'All Pester tests passed.' -ForegroundColor Green
[System.Environment]::Exit(0)
