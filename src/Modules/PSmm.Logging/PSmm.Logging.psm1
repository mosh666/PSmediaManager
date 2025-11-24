<#
.SYNOPSIS
    PowerShell module for log management.

.DESCRIPTION
    Provides centralized logging functionality for the PSmediaManager application using the PSLogs module.
    Supports file and console logging targets with configurable levels and formats.

    Features:
    - Multiple logging targets (console and file)
    - Configurable logging levels
    - Context-based logging
    - Log rotation support
    - Structured logging with PSLogs
    - Built-in error handling

.NOTES
    Module Name: PSmm.Logging
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
    Last Modified: 2025-10-26
    External Dependency: PSLogs module (https://getps.dev/modules/pslogs/getstarted/)

    Built-in logging levels:
    * NOTSET    ( 0)
    * SQL       ( 5) (Magenta)
    * DEBUG     (10) (Cyan)
    * VERBOSE   (14) (Yellow)
    * INFO      (20) (DarkGray)
    * NOTICE    (24) (Gray)
    * SUCCESS   (26) (Green)
    * WARNING   (30) (Yellow)
    * ERROR     (40) (Red)
    * CRITICAL  (50) (Red)
    * ALERT     (60) (Red)
    * EMERGENCY (70) (Magenta)
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script-level variables for logging state
[hashtable]$script:Context = @{ Context = $null }
[hashtable]$script:Logging = @{}

# Get module paths
$PublicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$PrivatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

# Import all public and private functions
try {
    # Import public functions
    if (Test-Path $PublicPath) {
        $PublicFunctions = @(Get-ChildItem -Path "$PublicPath\*.ps1" -Recurse -ErrorAction SilentlyContinue)

        if ($PublicFunctions.Count -gt 0) {
            foreach ($Function in $PublicFunctions) {
                try {
                    Write-Verbose "Importing public function: $($Function.Name)"
                    . $Function.FullName
                }
                catch {
                    throw "Failed to import public function '$($Function.Name)': $_"
                }
            }
            Write-Verbose "Imported $($PublicFunctions.Count) public function(s)"
        }
        else {
            Write-Warning "No public functions found in: $PublicPath"
        }
    }
    else {
        throw "Public functions path not found: $PublicPath"
    }

    # Import private functions
    if (Test-Path $PrivatePath) {
        $PrivateFunctions = @(Get-ChildItem -Path "$PrivatePath\*.ps1" -Recurse -ErrorAction SilentlyContinue)

        if ($PrivateFunctions.Count -gt 0) {
            foreach ($Function in $PrivateFunctions) {
                try {
                    Write-Verbose "Importing private function: $($Function.Name)"
                    . $Function.FullName
                }
                catch {
                    throw "Failed to import private function '$($Function.Name)': $_"
                }
            }
            Write-Verbose "Imported $($PrivateFunctions.Count) private function(s)"
        }
        else {
            Write-Verbose "No private functions found in: $PrivatePath"
        }
    }
    else {
        Write-Verbose "Creating Private functions directory: $PrivatePath"
        New-Item -Path $PrivatePath -ItemType Directory -Force | Out-Null
    }
}
catch {
    throw "Failed to import module functions: $_"
}

# Export module members (public functions only)
Export-ModuleMember -Function @(
    'Initialize-Logging',
    'Write-PSmmLog',
    'Set-LogContext',
    'Invoke-LogRotation'
)
