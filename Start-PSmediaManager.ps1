<#
.SYNOPSIS
    Starter script for PSmediaManager.

.DESCRIPTION
    Convenience wrapper to launch PSmediaManager from the repository root.
    This script forwards all parameters to the main application entry point
    in the src directory.

.PARAMETER Dev
    Enables development mode, which keeps environment paths registered after exit.
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

# Determine the path to the main application script
$MainScript = Join-Path $PSScriptRoot 'src' 'PSmediaManager.ps1'

# Verify the main script exists
if (-not (Test-Path $MainScript -PathType Leaf)) {
    Write-Error "Main application script not found at: $MainScript" -ErrorAction Stop
}

# Forward parameters and launch the main application
$SplatParams = @{}
if ($Dev) { $SplatParams['Dev'] = $true }
if ($Update) { $SplatParams['Update'] = $true }
if ($NonInteractive) { $SplatParams['NonInteractive'] = $true }
if ($PSCmdlet.MyInvocation.BoundParameters['Verbose']) { $SplatParams['Verbose'] = $true }
if ($PSCmdlet.MyInvocation.BoundParameters['Debug']) { $SplatParams['Debug'] = $true }

# Invoke the main script directly (not in a subprocess)
# This allows proper module resolution and $PSScriptRoot handling
& $MainScript @SplatParams

# Propagate exit code
exit $LASTEXITCODE
