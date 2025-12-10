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

# Get module paths (service-aware - check ServiceContainer variable existence first to avoid StrictMode errors)
$serviceContainer = Get-Variable -Name 'PSmmServiceContainer' -Scope Global -ErrorAction SilentlyContinue
$hasServiceContainer = ($null -ne $serviceContainer) -and ($null -ne $serviceContainer.Value)
$pathProvider = $null
$fileSystem   = $null

if ($hasServiceContainer) {
    try {
        $pathProvider = $serviceContainer.Value.Resolve('PathProvider')
        $fileSystem   = $serviceContainer.Value.Resolve('FileSystem')
    }
    catch {
        Write-Verbose "Failed to resolve services from ServiceContainer: $_"
    }
}

if ($pathProvider) {
    $PublicPath  = $pathProvider.CombinePath(@($PSScriptRoot,'Public'))
    $PrivatePath = $pathProvider.CombinePath(@($PSScriptRoot,'Private'))
} else {
    $PublicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
    $PrivatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
}

# Import all public and private functions
try {
    # Import public functions
    if ((($fileSystem) -and $fileSystem.TestPath($PublicPath)) -or (-not $fileSystem -and (Test-Path $PublicPath))) {
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
    if ((($fileSystem) -and $fileSystem.TestPath($PrivatePath)) -or (-not $fileSystem -and (Test-Path $PrivatePath))) {
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
        if ($fileSystem -and ($fileSystem | Get-Member -Name 'NewItem' -ErrorAction SilentlyContinue)) {
            $null = $fileSystem.NewItem($PrivatePath, 'Directory')
        }
        else {
            throw "FileSystem service is required to create Private functions directory: $PrivatePath"
        }
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
