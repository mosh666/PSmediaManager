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

# Service-aware path helpers (optional - check variable existence first to avoid StrictMode errors)
$servicesVar = Get-Variable -Name 'Services' -Scope Script -ErrorAction SilentlyContinue
$hasServices = ($null -ne $servicesVar) -and ($null -ne $servicesVar.Value)
$pathProvider = if ($hasServices -and $servicesVar.Value.PathProvider) { $servicesVar.Value.PathProvider } else { $null }
$fileSystem   = if ($hasServices -and $servicesVar.Value.FileSystem) { $servicesVar.Value.FileSystem } else { $null }
$parentRoot = Split-Path -Parent $PSScriptRoot

# Import required classes from PSmm module
$psmmModulePath = if ($pathProvider) { $pathProvider.CombinePath(@($parentRoot,'PSmm')) } else { Join-Path -Path $parentRoot -ChildPath 'PSmm' }
$exceptionsPath = if ($pathProvider) { $pathProvider.CombinePath(@($psmmModulePath,'Classes','Exceptions.ps1')) } else { Join-Path -Path $psmmModulePath -ChildPath 'Classes/Exceptions.ps1' }
if ((($fileSystem) -and $fileSystem.TestPath($exceptionsPath)) -or (-not $fileSystem -and (Test-Path -LiteralPath $exceptionsPath))) {
    . $exceptionsPath
}

$publicPath  = if ($pathProvider) { $pathProvider.CombinePath(@($PSScriptRoot,'Public')) } else { Join-Path -Path $PSScriptRoot -ChildPath 'Public' }
$privatePath = if ($pathProvider) { $pathProvider.CombinePath(@($PSScriptRoot,'Private')) } else { Join-Path -Path $PSScriptRoot -ChildPath 'Private' }

foreach ($scriptPath in @($publicPath, $privatePath)) {
    if (-not ((($fileSystem) -and $fileSystem.TestPath($scriptPath)) -or (-not $fileSystem -and (Test-Path -LiteralPath $scriptPath)))) {
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
