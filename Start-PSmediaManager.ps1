<#
.SYNOPSIS
    Starter script for PSmediaManager.

.DESCRIPTION
    Convenience wrapper to launch PSmediaManager from the repository root.
    This script forwards all parameters to the main application entry point
    in the src directory.

.PARAMETER Dev
    Enables development mode, which keeps environment paths registered in the session.
    PATH entries are added to Process scope only and not cleaned up at exit.
    Useful for development and debugging purposes.

.PARAMETER Update
    Triggers update mode for checking and installing application updates.

.PARAMETER NonInteractive
    Suppresses interactive UI launch (headless / automation scenarios).
    Still performs bootstrap and initialization.

.EXAMPLE
    .\Start-PSmediaManager.ps1
    Starts the application in normal mode.

.EXAMPLE
    .\Start-PSmediaManager.ps1 -Dev -Verbose
    Starts the application in development mode with verbose output.

.EXAMPLE
    .\Start-PSmediaManager.ps1 -Update
    Starts the application and checks for updates.

.EXAMPLE
    .\Start-PSmediaManager.ps1 -NonInteractive
    Performs bootstrap only (no UI) – useful for CI validation.

.NOTES
    Author           : Der Mosh
    Version          : 1.0.0
    Created          : 2025-11-19

    Requires         : PowerShell 7.5.4 or higher

    Repository       : https://github.com/mosh666/PSmediaManager
    License          : MIT
#>

#Requires -Version 7.5.4

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(HelpMessage = 'Enable development mode (keeps environment paths registered)')]
    [switch]$Dev,

    [Parameter(HelpMessage = 'Check and install application updates')]
    [switch]$Update,

    [Parameter(HelpMessage = 'Run without launching interactive UI (bootstrap only)')]
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Validate that this script is running from the repository root
# Expected structure: Start-PSmediaManager.ps1 at root, with src/ subdirectory
$ExpectedMarkers = @(
    (Join-Path -Path $PSScriptRoot -ChildPath 'src'),
    (Join-Path -Path $PSScriptRoot -ChildPath 'README.md'),
    (Join-Path -Path $PSScriptRoot -ChildPath '.git')
)

$MissingMarkers = @($ExpectedMarkers | Where-Object { -not (Test-Path $_) })
if ($MissingMarkers.Count -gt 0) {
    Write-Error @"
Start-PSmediaManager.ps1 is not in a valid repository structure.

Script location:  $PSScriptRoot

Expected to find:
  - src/
  - README.md
  - .git/

Please ensure the repository is properly cloned or extracted.
"@ -ErrorAction Stop
}

# Validate that the current working directory is the repository root
$CurrentLocation = (Get-Location).Path
$RepoRoot = $PSScriptRoot

if ($CurrentLocation -ne $RepoRoot) {
    Write-Error @"
This script must be run from the repository root directory.

Current location: $CurrentLocation
Repository root:  $RepoRoot

Please navigate to the repository root first:
    cd '$RepoRoot'
    .\Start-PSmediaManager.ps1

Alternatively, use the full path:
    & '$RepoRoot\Start-PSmediaManager.ps1'
"@ -ErrorAction Stop
}

# Determine the path to the main application script
$MainScript = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'src') -ChildPath 'PSmediaManager.ps1'

# Import core module first so PSmm functions (and any supporting script-module setup) are available.
$psmmManifestPath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'src') -ChildPath 'Modules\PSmm\PSmm.psd1'
if (-not (Test-Path -LiteralPath $psmmManifestPath)) {
    throw "PSmm module manifest not found: $psmmManifestPath"
}

Import-Module -Name $psmmManifestPath -Force -Global -ErrorAction Stop -Verbose:($VerbosePreference -eq 'Continue')

# Verify the main script exists
if (-not (Test-Path $MainScript -PathType Leaf)) {
    Write-Error "Main application script not found at: $MainScript" -ErrorAction Stop
}

# Forward parameters and launch the main application
$SplatParams = @{}
if ($Dev) { $SplatParams['Dev'] = $true }
if ($Update) { $SplatParams['Update'] = $true }
if ($NonInteractive) { $SplatParams['NonInteractive'] = $true }
$boundParameters = $PSCmdlet.MyInvocation.BoundParameters
if ($boundParameters.ContainsKey('Verbose') -and $boundParameters['Verbose']) { $SplatParams['Verbose'] = $true }
if ($boundParameters.ContainsKey('Debug') -and $boundParameters['Debug']) { $SplatParams['Debug'] = $true }

Push-Location -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'src')
try {
    # Invoke the entrypoint directly (no '&', no dot-sourcing)
    .\PSmediaManager.ps1 @SplatParams
}
finally {
    Pop-Location
}

# Propagate exit code
$exitCode = 0
$lastExitVar = Get-Variable -Name 'LASTEXITCODE' -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $lastExitVar) {
    try { $exitCode = [int]$lastExitVar.Value } catch { $exitCode = 0 }
}

exit $exitCode
