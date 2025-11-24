#Requires -Version 7.5.4
Set-StrictMode -Version Latest

# Tests should mock `Write-PSmmLog` where necessary; avoid implicit global fallbacks here.

function New-TestRepositoryRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath
    )

    if (-not (Test-Path -Path $RootPath)) {
        $null = New-Item -Path $RootPath -ItemType Directory -Force
    }

    $gitMarker = Join-Path -Path $RootPath -ChildPath '.git'
    if (-not (Test-Path -Path $gitMarker)) {
        $null = New-Item -Path $gitMarker -ItemType Directory -Force
    }

    return (Resolve-Path -Path $RootPath).Path
}

function New-TestAppConfiguration {
    [CmdletBinding()]
    param(
        [string]$RootPath = (Join-Path -Path $TestDrive -ChildPath 'PSmmTestRoot'),
        [switch]$InitializeProjectsPaths
    )

    $rootPath = New-TestRepositoryRoot -RootPath $RootPath

    $builder = [AppConfigurationBuilder]::new()
    $builder.WithRootPath($rootPath) | Out-Null
    $builder.WithParameters([RuntimeParameters]::new()) | Out-Null
    $builder.InitializeDirectories() | Out-Null
    $config = $builder.Build()

    if (-not $config.Projects) {
        $config.Projects = @{}
    }

    if ($InitializeProjectsPaths) {
        if (-not $config.Projects.ContainsKey('Paths')) {
            $config.Projects.Paths = @{}
        }
        $config.Projects.Paths.Assets = 'Libraries\Assets'
    }

    return $config
}

function New-TestStorageDrive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][AllowEmptyString()][string]$DriveLetter,
        [Parameter(Mandatory)][string]$SerialNumber
    )

    $drive = [StorageDriveConfig]::new()
    $drive.Label = $Label
    $drive.DriveLetter = $DriveLetter
    $drive.SerialNumber = $SerialNumber
    $drive.IsAvailable = $true
    return $drive
}

function Add-TestStorageGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AppConfiguration]$Config,
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][StorageDriveConfig]$Master,
        [hashtable]$Backups
    )

    $group = [StorageGroupConfig]::new($GroupId)
    $group.Master = $Master

    if ($null -ne $Backups) {
        foreach ($key in $Backups.Keys) {
            $group.Backups[$key] = $Backups[$key]
        }
    }

    $Config.Storage[$GroupId] = $group
    return $group
}
