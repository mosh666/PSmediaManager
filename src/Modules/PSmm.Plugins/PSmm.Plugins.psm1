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

$publicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

foreach ($scriptPath in @($publicPath, $privatePath)) {
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        continue
    }

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
