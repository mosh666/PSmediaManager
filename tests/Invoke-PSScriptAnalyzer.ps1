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

if ($null -ne $results -and $results.Count -gt 0) {
    $results |
        Sort-Object -Property RuleName, ScriptName, Line |
        Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message |
        Out-String |
        Write-Host

    throw "PSScriptAnalyzer reported $($results.Count) issue(s)"
}

Write-Verbose 'PSScriptAnalyzer passed (no issues)'
