#Requires -Version 7.5.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Note {
    param([string]$Message)
    Write-Host "[Enable-GitHooks] $Message" -ForegroundColor Cyan
}

try {
    Get-Command git -ErrorAction Stop | Out-Null
}
catch {
    Write-Host "[Enable-GitHooks] git is not available on PATH." -ForegroundColor Red
    exit 1
}

$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    Write-Host "[Enable-GitHooks] Not inside a Git repository." -ForegroundColor Red
    exit 1
}

$hooksPath = Join-Path -Path $repoRoot -ChildPath '.githooks'
if (-not (Test-Path -Path $hooksPath)) {
    Write-Host "[Enable-GitHooks] .githooks directory not found at $repoRoot." -ForegroundColor Red
    exit 1
}

Write-Note "Setting core.hooksPath to .githooks..."
git -C $repoRoot config --local core.hooksPath .githooks | Out-Null

$current = git -C $repoRoot config --local --get core.hooksPath
if ($current -ne '.githooks') {
    Write-Host "[Enable-GitHooks] Failed to set core.hooksPath (found: $current)." -ForegroundColor Red
    exit 1
}

Write-Note "Hook path enabled: $hooksPath"
Write-Note "Pre-commit hook will update module manifests before commits."
exit 0
