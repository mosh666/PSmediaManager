<#
.SYNOPSIS
    Early bootstrap service loader for PSmediaManager.

.DESCRIPTION
    Loads service class definitions from the PSmm module during early startup.
    This script is sourced before module imports to provide minimal service
    implementations needed for module discovery and loading.

    Architecture Decision (Option A):
    - Import service classes from canonical PSmm module location
    - Eliminates duplicate class definitions
    - Maintains single source of truth for service implementations
    - Pre-loads only the minimal classes needed before full module import

.NOTES
    Author: Der Mosh
    Version: 2.0.1 (Fixed PowerShell class scoping issue)
    Last Modified: 2025-12-07
#>

using namespace System
using namespace System.IO

# Define minimal PathProvider first (before imports to avoid scoping issues)
# This is a lightweight helper used only during bootstrap for path joining
class PathProvider {
    [string] GetPath([string]$pathKey) {
        # Minimal implementation – not used in early bootstrap
        return $null
    }

    [bool] EnsurePathExists([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) { return $false }
        if (-not (Test-Path -Path $path)) {
            $null = New-Item -Path $path -ItemType Directory -Force -ErrorAction SilentlyContinue
        }
        return (Test-Path -Path $path)
    }

    [string] CombinePath([string[]]$paths) {
        if ($null -eq $paths) { return '' }
        $pathsArray = @($paths)
        if ($pathsArray.Count -eq 0) { return '' }
        $clean = @($pathsArray | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($clean.Count -eq 0) { return '' }
        $result = $clean[0]
        for ($i = 1; $i -lt $clean.Count; $i++) {
            $result = [System.IO.Path]::Combine($result, $clean[$i])
        }
        return $result
    }
}

# Calculate paths to PSmm module classes
$moduleRoot = Split-Path -Path $PSScriptRoot -Parent
$psmmModulePath = Join-Path -Path $moduleRoot -ChildPath 'Modules\PSmm'
$classesPath = Join-Path -Path $psmmModulePath -ChildPath 'Classes'

# Validate paths exist
if (-not (Test-Path -Path $classesPath)) {
    throw "PSmm module classes path not found: $classesPath"
}

# Import service classes from PSmm module (interfaces first, then implementations)
try {
    Write-Verbose "[Bootstrap] Loading service classes from PSmm module..."

    # 1. Load interfaces (required by all service implementations)
    $interfacesPath = Join-Path -Path $classesPath -ChildPath 'Interfaces.ps1'
    if (Test-Path -Path $interfacesPath) {
        . $interfacesPath
        Write-Verbose "[Bootstrap] Loaded Interfaces.ps1"
    }
    else {
        throw "Required file not found: $interfacesPath"
    }

    # 2. Load service implementations needed for early bootstrap
    $serviceFiles = @(
        'Services\FileSystemService.ps1',
        'Services\EnvironmentService.ps1',
        'Services\ProcessService.ps1'
    )

    foreach ($serviceFile in $serviceFiles) {
        $servicePath = Join-Path -Path $classesPath -ChildPath $serviceFile
        if (Test-Path -Path $servicePath) {
            . $servicePath
            Write-Verbose "[Bootstrap] Loaded $serviceFile"
        }
        else {
            throw "Required service file not found: $servicePath"
        }
    }

    Write-Verbose "[Bootstrap] Successfully loaded early service classes from PSmm module"
}
catch {
    throw "Failed to load bootstrap services from PSmm module: $_"
}
