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

# Module paths (loader-first: do not depend on DI or globals during import)
$fileSystem   = $null

# Ensure the PSmm module is loaded (for IFileSystemService and other shared classes)
# NOTE: Module dependencies are handled by PSmediaManager.ps1 bootstrap - no need to force re-import here
# $CoreModulePath = if ($pathProvider) { $pathProvider.CombinePath(@($parentRoot,'PSmm','PSmm.psd1')) } else { Join-Path -Path $parentRoot -ChildPath 'PSmm\PSmm.psd1' }
# if ((($fileSystem) -and $fileSystem.TestPath($CoreModulePath)) -or (-not $fileSystem -and (Test-Path $CoreModulePath))) {
#     if (-not (Get-Module -Name 'PSmm')) {
#         Import-Module $CoreModulePath -Force -Global -ErrorAction Stop
#     }

#     # Also dot-source the required class files to ensure types are available
#     $ClassesPath = if ($pathProvider) { $pathProvider.CombinePath(@($parentRoot,'PSmm','Classes')) } else { Join-Path -Path $parentRoot -ChildPath 'PSmm\Classes' }
#     . (if ($pathProvider) { $pathProvider.CombinePath(@($ClassesPath,'Interfaces.ps1')) } else { Join-Path $ClassesPath 'Interfaces.ps1' })
#     . (if ($pathProvider) { $pathProvider.CombinePath(@($ClassesPath,'Exceptions.ps1')) } else { Join-Path $ClassesPath 'Exceptions.ps1' })
#     . (if ($pathProvider) { $pathProvider.CombinePath(@($ClassesPath,'Services','FileSystemService.ps1')) } else { Join-Path $ClassesPath 'Services\FileSystemService.ps1' })
#     . (if ($pathProvider) { $pathProvider.CombinePath(@($ClassesPath,'AppConfiguration.ps1')) } else { Join-Path $ClassesPath 'AppConfiguration.ps1' })
# }
# else {
#     Write-Warning "Core module not found at: $CoreModulePath"
# }

# Ensure the PSmm.Logging module is loaded for Write-PSmmLog and logging helpers
# NOTE: Module dependencies are handled by PSmediaManager.ps1 bootstrap - no need to force re-import here
# $LoggingModulePath = if ($pathProvider) { $pathProvider.CombinePath(@($parentRoot,'PSmm.Logging','PSmm.Logging.psd1')) } else { Join-Path -Path $parentRoot -ChildPath 'PSmm.Logging\PSmm.Logging.psd1' }
# if ((($fileSystem) -and $fileSystem.TestPath($LoggingModulePath)) -or (-not $fileSystem -and (Test-Path $LoggingModulePath))) {
#     if (-not (Get-Module -Name 'PSmm.Logging')) {
#         Import-Module $LoggingModulePath -Force -Global -ErrorAction Stop
#     }
# }

# Get module paths
$ClassesPath = Join-Path -Path $PSScriptRoot -ChildPath 'Classes'
$PublicPath  = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$PrivatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

# Import all public and private functions
try {
    # Import class/type definitions first (so public functions can reference them)
    if (Test-Path -Path $ClassesPath) {
        $ClassFiles = @(Get-ChildItem -Path "$ClassesPath\*.ps1" -Recurse -ErrorAction SilentlyContinue)
        foreach ($File in $ClassFiles) {
            try {
                Write-Verbose "Importing class file: $($File.Name)"
                . $File.FullName
            }
            catch {
                throw "Failed to import class file '$($File.Name)': $_"
            }
        }
    }

    # Import public functions
    if (Test-Path -Path $PublicPath) {
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
    if (Test-Path -Path $PrivatePath) {
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
        # Private directory doesn't exist - create it if FileSystem service is available
        # During early bootstrap, service may not be available yet - that's okay, directory can be created later if needed
        if ($fileSystem -and ($fileSystem | Get-Member -Name 'NewItem' -ErrorAction SilentlyContinue)) {
            Write-Verbose "Creating Private functions directory: $PrivatePath"
            $null = $fileSystem.NewItem($PrivatePath, 'Directory')
        }
        else {
            Write-Verbose "Private functions directory does not exist (will be created when needed): $PrivatePath"
        }
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
