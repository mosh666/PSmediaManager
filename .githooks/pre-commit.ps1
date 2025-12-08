<#!
Pre-commit hook to keep module versions in sync with Git.
Enable via:
  git config core.hooksPath .githooks
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Note {
    param([string]$Message)
    Write-Host "[pre-commit] $Message" -ForegroundColor Cyan
}

try {
    $repoRoot = git rev-parse --show-toplevel 2>$null
    if (-not $repoRoot) { throw 'Unable to locate repository root.' }
    Set-Location $repoRoot

    $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Update-ModuleVersions.ps1'
    if (-not (Test-Path -Path $scriptPath)) {
        Write-Note 'Update-ModuleVersions.ps1 not found; skipping version sync.'
        exit 0
    }

    Write-Note 'Updating module manifests from Git version...'
    pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -UpdateManifests

    Write-Note 'Staging updated manifests...'
    git add src/Modules/**/*.psd1

    Write-Note 'Version sync complete.'
    exit 0
}
catch {
    Write-Host "[pre-commit] ERROR: $_" -ForegroundColor Red
    exit 1
}
