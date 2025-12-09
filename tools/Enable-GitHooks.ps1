#Requires -Version 7.5.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Note {
    param([string]$Message)
    Write-Information "[Enable-GitHooks] $Message" -InformationAction Continue
}

try {
    Get-Command git -ErrorAction Stop | Out-Null
}
catch {
    Write-Error "[Enable-GitHooks] git is not available on PATH."
    exit 1
}

$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    Write-Error "[Enable-GitHooks] Not inside a Git repository."
    exit 1
}

$hooksPath = Join-Path -Path $repoRoot -ChildPath '.githooks'
if (-not (Test-Path -Path $hooksPath)) {
    Write-Error "[Enable-GitHooks] .githooks directory not found at $repoRoot."
    exit 1
}

Write-Note "Setting core.hooksPath to .githooks..."
git -C $repoRoot config --local core.hooksPath .githooks | Out-Null

$current = git -C $repoRoot config --local --get core.hooksPath
if ($current -ne '.githooks') {
    Write-Error "[Enable-GitHooks] Failed to set core.hooksPath (found: $current)."
    exit 1
}

Write-Note "Hook path enabled: $hooksPath"
Write-Note "Pre-commit hook will update module manifests before commits."
exit 0
