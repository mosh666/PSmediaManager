<#
.SYNOPSIS
    PowerShell module for PSmediaManager project management.

.DESCRIPTION
    Provides functions for creating, selecting, and managing media projects including
    directory structure setup, database initialization, and project configuration.

    Features:
    - Project creation and initialization
    - Project selection and switching
    - Directory structure management
    - Project configuration management
    - Database integration support
    - Project validation

.NOTES
    Module Name: PSmm.Projects
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
    Last Modified: 2025-10-26
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure the PSmm module is loaded (for IFileSystemService and other shared classes)
$CoreModulePath = Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath 'PSmm\PSmm.psd1'
if (Test-Path $CoreModulePath) {
    if (-not (Get-Module -Name 'PSmm')) {
        Import-Module $CoreModulePath -Force -Global -ErrorAction Stop
    }

    # Also dot-source the required class files to ensure types are available
    $ClassesPath = Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath 'PSmm\Classes'
    . (Join-Path $ClassesPath 'Interfaces.ps1')
    . (Join-Path $ClassesPath 'Exceptions.ps1')
    . (Join-Path $ClassesPath 'Services\FileSystemService.ps1')
    . (Join-Path $ClassesPath 'AppConfiguration.ps1')
}
else {
    Write-Warning "Core module not found at: $CoreModulePath"
}

# Ensure the PSmm.Logging module is loaded for Write-PSmmLog and logging helpers
$LoggingModulePath = Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath 'PSmm.Logging\PSmm.Logging.psd1'
if (Test-Path $LoggingModulePath) {
    if (-not (Get-Module -Name 'PSmm.Logging')) {
        Import-Module $LoggingModulePath -Force -Global -ErrorAction Stop
    }
}
else {
    Write-Verbose "Logging module not found at: $LoggingModulePath"
}

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
    'Clear-PSmmProjectRegistry',
    'Get-PSmmProjects',
    'New-PSmmProject',
    'Select-PSmmProject'
)
