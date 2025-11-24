#Requires -Version 7.5.4
Set-StrictMode -Version Latest

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

function New-TestAppConfiguration {
    [CmdletBinding()]
    param(
        [string]$StorageGroup = '1',
        [hashtable]$StorageOverrides
    )

    $masterDrive = [PSCustomObject]@{
        Label = 'MASTER-DRIVE'
        DriveLetter = 'D:'
        SerialNumber = 'SERIAL-1234'
        StorageGroup = $StorageGroup
        FreeSpace = 0
        TotalSpace = 0
    }

    $storageGroup = [PSCustomObject]@{
        Master = $masterDrive
        Backup = $null
    }

    if ($StorageOverrides) {
        foreach ($key in $StorageOverrides.Keys) {
            $storageGroup.$key = $StorageOverrides[$key]
        }
    }

    $storageRoot = @{ $StorageGroup = $storageGroup }
    $parameters = [PSCustomObject]@{
        Debug = $false
        Dev = $false
        NonInteractive = $false
    }

    $paths = [PSCustomObject]@{
        App = [PSCustomObject]@{
            Plugins = [PSCustomObject]@{
                Root = Join-Path $env:TEMP 'PSMM-Plugins'
                Downloads = Join-Path $env:TEMP 'PSMM-Plugins\_Downloads'
                Temp = Join-Path $env:TEMP 'PSMM-Plugins\_Temp'
            }
        }
    }

    return [PSCustomObject]@{
        Storage = $storageRoot
        Parameters = $parameters
        Paths = $paths
        Vault = [PSCustomObject]@{}
    }
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
