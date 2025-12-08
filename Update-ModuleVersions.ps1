<#
.SYNOPSIS
    Updates module manifest versions dynamically from Git.

.DESCRIPTION
    This build script retrieves the current version from Git using GitVersion
    and updates all module manifests (.psd1 files) with the correct version.

    PowerShell module manifests run in restricted language mode and cannot
    execute dynamic code, so we use this build-time script to inject the
    version before deployment or testing.

.PARAMETER UpdateManifests
    Updates all module manifests with the current Git version.

.PARAMETER ShowVersion
    Displays the current version without updating manifests.

.EXAMPLE
    .\Update-ModuleVersions.ps1 -UpdateManifests
    Updates all module manifest files with current Git version.

.EXAMPLE
    .\Update-ModuleVersions.ps1 -ShowVersion
    Displays current version from Git.

.NOTES
    Author: Der Mosh
    Version: 1.0.0
    Last Modified: 2025-12-08
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$UpdateManifests,

    [Parameter()]
    [switch]$ShowVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the version helper
$versionHelperPath = Join-Path -Path $PSScriptRoot -ChildPath 'src\Modules\PSmm\Private\Get-PSmmDynamicVersion.ps1'

if (-not (Test-Path -Path $versionHelperPath)) {
    throw "Version helper not found at: $versionHelperPath"
}

. $versionHelperPath

# Get current version
$moduleVersion = Get-PSmmDynamicVersion -RepositoryRoot $PSScriptRoot
$fullVersion = Get-PSmmFullVersion -RepositoryRoot $PSScriptRoot

Write-Host "Current Version:" -ForegroundColor Cyan
Write-Host "  Module Version (Major.Minor.Patch): $moduleVersion" -ForegroundColor Green
Write-Host "  Full Version (SemVer): $fullVersion" -ForegroundColor Green

if ($ShowVersion) {
    return
}

if (-not $UpdateManifests) {
    Write-Host "`nUse -UpdateManifests to update module manifest files." -ForegroundColor Yellow
    return
}

# Find all module manifests
$manifestPaths = @(
    'src\Modules\PSmm\PSmm.psd1'
    'src\Modules\PSmm.Logging\PSmm.Logging.psd1'
    'src\Modules\PSmm.Plugins\PSmm.Plugins.psd1'
    'src\Modules\PSmm.Projects\PSmm.Projects.psd1'
    'src\Modules\PSmm.UI\PSmm.UI.psd1'
)

Write-Host "`nUpdating module manifests..." -ForegroundColor Cyan

foreach ($relativePath in $manifestPaths) {
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath $relativePath

    if (-not (Test-Path -Path $manifestPath)) {
        Write-Warning "Manifest not found: $manifestPath"
        continue
    }

    try {
        # Read current manifest
        $content = Get-Content -Path $manifestPath -Raw

        # Update ModuleVersion line
        $pattern = "(?m)^\s*ModuleVersion\s*=\s*['""][\d.]+['""]"
        $replacement = "    ModuleVersion = '$moduleVersion'"

        if ($content -match $pattern) {
            $newContent = $content -replace $pattern, $replacement
            Set-Content -Path $manifestPath -Value $newContent -NoNewline -Encoding UTF8

            Write-Host "  ✓ Updated: $relativePath → $moduleVersion" -ForegroundColor Green
        }
        else {
            Write-Warning "  ✗ Could not find ModuleVersion in: $relativePath"
        }
    }
    catch {
        Write-Error "Failed to update $relativePath : $_"
    }
}

Write-Host "`nAll manifests updated successfully!" -ForegroundColor Green
Write-Host "Verify with: Test-ModuleManifest -Path <manifest-path>" -ForegroundColor Yellow
