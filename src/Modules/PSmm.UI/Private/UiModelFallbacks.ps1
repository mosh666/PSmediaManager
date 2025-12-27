#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function ConvertTo-PSmmUiErrorCatalog {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Object
    )

    $uiErrorCatalogType = 'UiErrorCatalog' -as [type]
    if ($uiErrorCatalogType -and ($Object -is $uiErrorCatalogType)) {
        return $Object
    }

    $catalog = [pscustomobject]@{
        Storage = [System.Collections.Generic.Dictionary[string, string]]::new()
    }
    $catalog.PSObject.TypeNames.Insert(0, 'UiErrorCatalog')

    if ($null -eq $Object) {
        $catalog | Add-Member -MemberType ScriptMethod -Name FilterStorageGroup -Force -Value {
            param([string]$storageGroupFilter)
            $null = $storageGroupFilter
            return $this
        }
        $catalog | Add-Member -MemberType ScriptMethod -Name GetAllMessages -Force -Value {
            $messages = [System.Collections.Generic.List[string]]::new()
            foreach ($kvp in $this.Storage.GetEnumerator()) {
                if (-not [string]::IsNullOrWhiteSpace($kvp.Value)) {
                    $messages.Add($kvp.Value)
                }
            }
            return $messages.ToArray()
        }
        return $catalog
    }

    if ($Object -is [hashtable] -and $Object.ContainsKey('Storage')) {
        $storageObj = $Object['Storage']
        if ($storageObj -is [hashtable]) {
            foreach ($k in $storageObj.Keys) {
                $v = $storageObj[$k]
                if ($v -is [string] -and -not [string]::IsNullOrWhiteSpace($v)) {
                    $catalog.Storage[[string]$k] = [string]$v
                }
            }
        }
    }
    elseif ($Object -is [hashtable]) {
        foreach ($k in $Object.Keys) {
            $v = $Object[$k]
            if ($v -is [string] -and -not [string]::IsNullOrWhiteSpace($v)) {
                $catalog.Storage[[string]$k] = [string]$v
            }
        }
    }

    $catalog | Add-Member -MemberType ScriptMethod -Name FilterStorageGroup -Force -Value {
        param([string]$storageGroupFilter)

        if ([string]::IsNullOrWhiteSpace($storageGroupFilter)) {
            return $this
        }

        $filtered = [pscustomobject]@{
            Storage = [System.Collections.Generic.Dictionary[string, string]]::new()
        }
        $filtered.PSObject.TypeNames.Insert(0, 'UiErrorCatalog')

        $prefix = [regex]::Escape($storageGroupFilter) + '\.'
        foreach ($kvp in $this.Storage.GetEnumerator()) {
            if ($kvp.Key -match ('^' + $prefix)) {
                $filtered.Storage[$kvp.Key] = $kvp.Value
            }
        }

        $filtered | Add-Member -MemberType ScriptMethod -Name FilterStorageGroup -Force -Value $this.PSObject.Methods['FilterStorageGroup'].Value
        $filtered | Add-Member -MemberType ScriptMethod -Name GetAllMessages -Force -Value $this.PSObject.Methods['GetAllMessages'].Value

        return $filtered
    }

    $catalog | Add-Member -MemberType ScriptMethod -Name GetAllMessages -Force -Value {
        $messages = [System.Collections.Generic.List[string]]::new()
        foreach ($kvp in $this.Storage.GetEnumerator()) {
            if (-not [string]::IsNullOrWhiteSpace($kvp.Value)) {
                $messages.Add($kvp.Value)
            }
        }
        return $messages.ToArray()
    }

    return $catalog
}

function ConvertTo-PSmmUiProjectsIndex {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Object
    )

    $uiProjectsIndexType = 'UiProjectsIndex' -as [type]
    if ($uiProjectsIndexType -and ($Object -is $uiProjectsIndexType)) {
        return $Object
    }

    $idx = [pscustomobject]@{
        Master = @{}
        Backup = @{}
    }
    $idx.PSObject.TypeNames.Insert(0, 'UiProjectsIndex')

    if ($null -eq $Object) {
        return $idx
    }

    $masterObj = $null
    $backupObj = $null

    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey('Master')) { $masterObj = $Object['Master'] }
        if ($Object.ContainsKey('Backup')) { $backupObj = $Object['Backup'] }
    }
    else {
        try { $masterObj = $Object.Master } catch { $masterObj = $null }
        try { $backupObj = $Object.Backup } catch { $backupObj = $null }
    }

    if ($masterObj -is [System.Collections.IDictionary]) {
        foreach ($k in $masterObj.Keys) {
            $v = $masterObj[$k]
            $idx.Master[[string]$k] = if ($null -eq $v) { [object[]]@() } else { [object[]]@($v) }
        }
    }

    if ($backupObj -is [System.Collections.IDictionary]) {
        foreach ($k in $backupObj.Keys) {
            $v = $backupObj[$k]
            $idx.Backup[[string]$k] = if ($null -eq $v) { [object[]]@() } else { [object[]]@($v) }
        }
    }

    return $idx
}

function ConvertTo-PSmmUiProjectCurrentConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Object
    )

    if ($null -eq $Object) {
        return $null
    }

    $name = Get-PSmmUiConfigMemberValue -Object $Object -Name 'Name'
    $databases = Get-PSmmUiConfigMemberValue -Object $Object -Name 'Databases'
    $configPath = Get-PSmmUiConfigMemberValue -Object $Object -Name 'Config'
    $storageDriveSource = Get-PSmmUiConfigMemberValue -Object $Object -Name 'StorageDrive'

    $storageDrive = $null
    if ($null -ne $storageDriveSource) {
        $storageDrive = [pscustomobject]@{
            Label       = Get-PSmmUiConfigMemberValue -Object $storageDriveSource -Name 'Label'
            DriveLetter = Get-PSmmUiConfigMemberValue -Object $storageDriveSource -Name 'DriveLetter'
        }
        $storageDrive.PSObject.TypeNames.Insert(0, 'StorageDrive')
    }

    $current = [pscustomobject]@{
        Name        = $name
        Databases   = $databases
        Config      = $configPath
        StorageDrive = $storageDrive
    }
    $current.PSObject.TypeNames.Insert(0, 'ProjectCurrentConfig')

    return $current
}

function New-PSmmUiDriveProjectsInfo {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Factory function creates an in-memory UI model object and does not modify system state')]
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter()]
        [AllowNull()]
        [object[]]$Projects = @(),

        [Parameter()]
        [string]$DriveType = '',

        [Parameter()]
        [string]$Prefix = '',

        [Parameter()]
        [AllowNull()]
        [Nullable[int]]$BackupNumber = $null,

        [Parameter()]
        [bool]$IsFallback = $false
    )

    $info = [pscustomobject]@{
        Projects     = if ($null -eq $Projects) { @() } else { $Projects }
        DriveType    = $DriveType
        Prefix       = $Prefix
        BackupNumber = $BackupNumber
        IsFallback   = $IsFallback
    }

    $info.PSObject.TypeNames.Insert(0, 'UiDriveProjectsInfo')

    return $info
}
