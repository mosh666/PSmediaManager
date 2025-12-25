<#!
.SYNOPSIS
    PSmediaManager external plugin orchestration module.

.DESCRIPTION
    Provides plugin orchestration features such as external plugin acquisition
    and digiKam/MariaDB coordination while relying on explicit plugin paths
    (temporary PATH registration helpers were removed).
    Depends on PSmm for core types/services and PSmm.Logging for telemetry.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module paths (loader-first: do not depend on DI or globals during import)
$publicPath  = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

if (-not (Test-Path -LiteralPath $publicPath)) {
    throw "Public functions path not found: $publicPath"
}

if (-not (Test-Path -LiteralPath $privatePath)) {
    throw "Private functions path not found: $privatePath"
}

# Load required helpers first (break fast)
$configHelpers = Join-Path -Path $privatePath -ChildPath 'ConfigMemberAccessHelpers.ps1'
if (-not (Test-Path -LiteralPath $configHelpers)) {
    throw "Required helper not found: $configHelpers"
}

try {
    . $configHelpers
}
catch {
    throw "Failed to import required helper '$configHelpers': $_"
}

foreach ($scriptPath in @($publicPath, $privatePath)) {
    Get-ChildItem -LiteralPath $scriptPath -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $item = $_
        $itemType = if ($null -ne $item) { $item.GetType().FullName } else { '<null>' }

        $hasFullName = $item -and ($item.PSObject.Properties.Match('FullName').Count -gt 0)
        if (-not $hasFullName) {
            Write-Verbose "Skipping unexpected module artifact ($itemType) without FullName from $scriptPath"
            continue
        }

        try {
            . $item.FullName
        }
        catch {
            throw "Failed to import script '$($item.FullName)': $_"
        }
    }
}

Export-ModuleMember -Function @(
    'Confirm-Plugins'
    'Install-KeePassXC'
    'Get-PSmmAvailablePort'
    'Get-PSmmProjectPorts'
    'Initialize-PSmmProjectDigiKamConfig'
    'Start-PSmmdigiKam'
    'Stop-PSmmdigiKam'
)
