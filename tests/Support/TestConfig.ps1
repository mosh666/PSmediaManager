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

function New-TestAppLogsRecorder {
    [CmdletBinding()]
    param()

    $entries = [System.Collections.ArrayList]::new()
    $recorder = [PSCustomObject]@{
        Entries = $entries
    }

    $recorder | Add-Member -MemberType ScriptMethod -Name Clear -Value { $this.Entries.Clear() }
    $recorder | Add-Member -MemberType ScriptMethod -Name Record -Value {
        param(
            $Level,
            $Message,
            $Context
        )
        $this.Entries.Add([PSCustomObject]@{ Level = $Level; Message = $Message; Context = $Context }) | Out-Null
    }

    $recorder | Add-Member -MemberType ScriptMethod -Name Assert-LogLevel -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Level,

            [Parameter(Mandatory)]
            [string]$Message,

            [int]$Count = 1
        )

        $matches = @($this.Entries | Where-Object { $_.Level -eq $Level -and $_.Message -like "*$Message*" })
        if ($matches.Count -lt $Count) {
            throw "Expected at least $Count entries with Level='$Level' and Message containing '$Message', found $($matches.Count)"
        }
    }

    $recorder | Add-Member -MemberType ScriptMethod -Name Assert-Info -Value { param($Message,$Count=1) $this.'Assert-LogLevel'('INFO',$Message,$Count) }
    $recorder | Add-Member -MemberType ScriptMethod -Name Assert-Warning -Value { param($Message,$Count=1) $this.'Assert-LogLevel'('WARNING',$Message,$Count) }
    $recorder | Add-Member -MemberType ScriptMethod -Name Assert-Error -Value { param($Message,$Count=1) $this.'Assert-LogLevel'('ERROR',$Message,$Count) }

    return $recorder
}

function Register-TestWritePSmmLogMock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Recorder,
        [string[]]$ModuleName
    )

    $mockWith = {
        param(
            [string]$Level,
            [string]$Message,
            [string]$Context,
            [switch]$Console,
            [switch]$File,
            $Body,
            $ErrorRecord,
            $ExceptionInfo
        )
        $Recorder.Record($Level, $Message, $Context)
    }

    if ($ModuleName) {
        foreach ($module in $ModuleName) {
            Mock -ModuleName $module -CommandName 'Write-PSmmLog' -MockWith $mockWith
        }
    }
    else {
        Mock -CommandName 'Write-PSmmLog' -MockWith $mockWith
    }
}

function New-MockObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Properties
    )

    $obj = [PSCustomObject]@{}

    foreach ($key in $Properties.Keys) {
        $value = $Properties[$key]
        
        if ($value -is [scriptblock]) {
            # Add script block as a method
            $obj | Add-Member -MemberType ScriptMethod -Name $key -Value $value
        }
        else {
            # Add as property
            $obj | Add-Member -MemberType NoteProperty -Name $key -Value $value
        }
    }

    return $obj
}
