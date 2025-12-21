#Requires -Version 7.5.4

param(
    [Parameter()][ValidateNotNullOrEmpty()][string]$TargetPath = './src'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$targetFullPath = Resolve-Path -Path $TargetPath -ErrorAction Stop

$testsRoot = $PSScriptRoot
$repoRoot = Split-Path -Path $testsRoot -Parent
$versionsPath = Join-Path -Path $repoRoot -ChildPath 'build/versions.psd1'
if (-not (Test-Path -Path $versionsPath)) {
    throw "Missing versions manifest: $versionsPath"
}

$versions = Import-PowerShellDataFile -Path $versionsPath
$analyzerVersion = $versions.Modules.PSScriptAnalyzer
if ([string]::IsNullOrWhiteSpace($analyzerVersion)) {
    throw 'PSScriptAnalyzer version is not defined in build/versions.psd1'
}

Import-Module -Name PSScriptAnalyzer -RequiredVersion $analyzerVersion -ErrorAction Stop

Write-Verbose "Running PSScriptAnalyzer on: $targetFullPath"

$results = Invoke-ScriptAnalyzer -Path $targetFullPath -Recurse -Severity @('Error','Warning')

$resultsList = @(
    $results | Where-Object {
        $_.Severity -in @('Error', 'Warning')
    }
)

$informationalResultsCount = @(
    $results | Where-Object {
        $_.Severity -notin @('Error', 'Warning')
    }
).Count

if ($informationalResultsCount -gt 0) {
    Write-Verbose "Ignoring $informationalResultsCount informational PSScriptAnalyzer result(s) (for example: TypeNotFound)."
}

if ($resultsList.Count -gt 0) {
    $resultsList |
        Sort-Object -Property RuleName, ScriptName, Line |
        Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message |
        Out-String |
        Write-Output

    throw "PSScriptAnalyzer reported $($resultsList.Count) issue(s)"
}

Write-Verbose 'PSScriptAnalyzer passed (no issues)'
