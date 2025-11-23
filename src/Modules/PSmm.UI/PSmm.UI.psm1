<#
.SYNOPSIS
    PowerShell module for PSmediaManager UI components.

.DESCRIPTION
    Provides user interface functions for the PSmediaManager application including
    menu display, formatting, and interactive prompts.
    
    Features:
    - Interactive menu system
    - Multi-option prompts
    - ANSI-colored output formatting
    - User input validation
    - Context-aware UI components
    - Error message handling

.NOTES
    Module Name: PSmm.UI
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
    Last Modified: 2025-10-26
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    'Invoke-PSmmUI',
    'Invoke-MultiOptionPrompt'
)
