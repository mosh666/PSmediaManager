<#
.SYNOPSIS
    Removes one or more storage groups from configuration.

.DESCRIPTION
    Deletes specified storage groups from the in-memory configuration and
    the on-drive PSmm.Storage.psd1 file. Remaining groups are renumbered
    sequentially (1, 2, 3...) and the storage status is refreshed.

.PARAMETER Config
    The AppConfiguration object containing application state.

.PARAMETER DriveRoot
    The root path of the drive where PSmm.Storage.psd1 is stored.

.PARAMETER GroupIds
    Array of group IDs (as strings) to remove.

.EXAMPLE
    Remove-StorageGroup -Config $config -DriveRoot 'D:\' -GroupIds @('2', '3')

.NOTES
    After removal, the system reloads the storage file and updates drive status.
    If all groups are removed, the configuration will contain an empty Storage hashtable.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Remove-StorageGroup {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DriveRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$GroupIds
    )

    function Get-ConfigMemberValue {
        param(
            [Parameter(Mandatory)]
            [AllowNull()]
            $Object,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,

            [Parameter()]
            $Default = $null
        )

        if ($null -eq $Object) { return $Default }

        if ($Object -is [System.Collections.IDictionary]) {
            try {
                if ($Object.ContainsKey($Name)) { return $Object[$Name] }
            }
            catch {
                # fall through
            }

            try {
                if ($Object.Contains($Name)) { return $Object[$Name] }
            }
            catch {
                # fall through
            }

            try {
                foreach ($k in $Object.Keys) {
                    if ($k -eq $Name) { return $Object[$k] }
                }
            }
            catch {
                # fall through
            }
        }

        $prop = $Object.PSObject.Properties[$Name]
        if ($null -ne $prop) { return $prop.Value }

        return $Default
    }

    function Set-ConfigMemberValue {
        param(
            [Parameter(Mandatory)]
            [AllowNull()]
            $Object,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,

            [Parameter()]
            $Value
        )

        if ($null -eq $Object) { return }

        if ($Object -is [System.Collections.IDictionary]) {
            $Object[$Name] = $Value
            return
        }

        if ($Object.PSObject.Properties[$Name]) {
            $Object.$Name = $Value
            return
        }

        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }

    $storageMap = Get-ConfigMemberValue -Object $Config -Name 'Storage' -Default $null
    if ($null -eq $storageMap -and $Config -is [System.Collections.IDictionary]) {
        # Allow passing a Storage-map directly in legacy/test scenarios
        $storageMap = $Config
    }
    if ($null -eq $storageMap) {
        $storageMap = @{}
        Set-ConfigMemberValue -Object $Config -Name 'Storage' -Value $storageMap
    }

    $logAvail = Get-Command Write-PSmmLog -ErrorAction SilentlyContinue
    function Write-RemoveLog([string]$level, [string]$msg) {
        if ($logAvail) { Write-PSmmLog -Level $level -Context 'RemoveStorageGroup' -Message $msg -Console -File }
        else { Write-Verbose $msg }
    }

    # Build storage path
    $storagePath = Join-Path -Path $DriveRoot -ChildPath 'PSmm.Config\PSmm.Storage.psd1'

    # Load current storage from file
    $storageHashtable = [AppConfigurationBuilder]::ReadStorageFile($storagePath)
    if ($null -eq $storageHashtable) {
        Write-RemoveLog 'WARNING' "Storage file not found or invalid: $storagePath"
        $storageHashtable = @{}
    }

    # Remove specified groups
    $removedCount = 0
    foreach ($gid in $GroupIds) {
        $hasGroup = $false
        if ($storageHashtable -is [System.Collections.IDictionary]) {
            try { $hasGroup = $storageHashtable.Contains($gid) } catch { $hasGroup = $false }
            if (-not $hasGroup) { try { $hasGroup = $storageHashtable.ContainsKey($gid) } catch { $hasGroup = $false } }
        }
        if ($hasGroup) {
            if ($PSCmdlet.ShouldProcess("Storage Group $gid", "Remove")) {
                $storageHashtable.Remove($gid)
                $removedCount++
                Write-RemoveLog 'NOTICE' "Removed storage group $gid from configuration"
            }
        }
        else {
            Write-RemoveLog 'WARNING' "Group $gid not found in storage configuration"
        }
    }

    if ($removedCount -eq 0) {
        Write-RemoveLog 'WARNING' 'No groups were removed'
        return
    }

    # Write updated storage (with renumbering)
    if ($PSCmdlet.ShouldProcess($storagePath, "Update storage file")) {
        try {
            [AppConfigurationBuilder]::WriteStorageFile($storagePath, $storageHashtable)
            Write-RemoveLog 'NOTICE' "Updated storage file: $storagePath (removed $removedCount group(s), renumbered remaining)"
        }
        catch {
            Write-RemoveLog 'ERROR' "Failed to write storage file: $_"
            throw
        }
    }

    # Reload storage into Config (clear existing and reload from file)
    $storageMap.Clear()

    if ($storageHashtable.Count -gt 0) {
        # Re-read from file to get renumbered groups
        $reloaded = [AppConfigurationBuilder]::ReadStorageFile($storagePath)

        if ($null -ne $reloaded) {
            foreach ($groupKey in $reloaded.Keys) {
                $groupTable = $reloaded[$groupKey]
                $group = [StorageGroupConfig]::new([string]$groupKey)
                $displayNameValue = Get-ConfigMemberValue -Object $groupTable -Name 'DisplayName' -Default $null
                if (-not [string]::IsNullOrWhiteSpace([string]$displayNameValue)) { $group.DisplayName = [string]$displayNameValue }

                $mTable = Get-ConfigMemberValue -Object $groupTable -Name 'Master' -Default $null
                if ($null -ne $mTable) {
                    $mLabel = [string](Get-ConfigMemberValue -Object $mTable -Name 'Label' -Default '')
                    $mSerial = [string](Get-ConfigMemberValue -Object $mTable -Name 'SerialNumber' -Default '')
                    $group.Master = [StorageDriveConfig]::new($mLabel, '')
                    $group.Master.SerialNumber = $mSerial
                }

                $bTable = Get-ConfigMemberValue -Object $groupTable -Name 'Backup' -Default $null
                if ($bTable -is [System.Collections.IDictionary] -and $bTable.Count -gt 0) {
                    foreach ($bk in ($bTable.Keys | Where-Object { $_ -match '^[0-9]+' } | Sort-Object { [int]$_ })) {
                        $b = $bTable[$bk]
                        if ($null -eq $b) { continue }
                        $bLabel = [string](Get-ConfigMemberValue -Object $b -Name 'Label' -Default '')
                        $bSerial = [string](Get-ConfigMemberValue -Object $b -Name 'SerialNumber' -Default '')
                        $cfg = [StorageDriveConfig]::new($bLabel, '')
                        $cfg.SerialNumber = $bSerial
                        $group.Backups[[string]$bk] = $cfg
                    }
                }

                $storageMap[[string]$groupKey] = $group
            }
        }
    }

    # Update storage status (match drives by serial, refresh availability)
    $availableDrives = @()
    try {
        if (Get-Command Get-StorageDrive -ErrorAction SilentlyContinue) {
            $availableDrives = Get-StorageDrive
        }
    }
    catch {
        Write-RemoveLog 'WARNING' "Failed to get storage drives: $_"
    }

    foreach ($groupKey in $storageMap.Keys) {
        $group = $storageMap[$groupKey]

        # Match Master drive
        if ($null -ne $group.Master -and -not [string]::IsNullOrWhiteSpace($group.Master.SerialNumber)) {
            $matchedDrive = $availableDrives | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.SerialNumber) -and
                $_.SerialNumber.Trim() -eq $group.Master.SerialNumber.Trim()
            } | Select-Object -First 1

            if ($matchedDrive) {
                $group.Master.DriveLetter = $matchedDrive.DriveLetter
            }
        }

        # Match Backup drives
        if ($null -ne $group.Backups -and $group.Backups.Count -gt 0) {
            foreach ($backupKey in $group.Backups.Keys) {
                $backup = $group.Backups[$backupKey]
                if (-not [string]::IsNullOrWhiteSpace($backup.SerialNumber)) {
                    $matchedDrive = $availableDrives | Where-Object {
                        -not [string]::IsNullOrWhiteSpace($_.SerialNumber) -and
                        $_.SerialNumber.Trim() -eq $backup.SerialNumber.Trim()
                    } | Select-Object -First 1

                    if ($matchedDrive) {
                        $backup.DriveLetter = $matchedDrive.DriveLetter
                    }
                }
            }
        }

        $group.UpdateStatus()
    }

    # Run Confirm-Storage to validate and log status
    try {
        Confirm-Storage -Config $Config
    }
    catch {
        Write-RemoveLog 'WARNING' "Storage validation after removal encountered issues: $_"
    }

    Write-RemoveLog 'NOTICE' "Storage groups removed and configuration reloaded successfully"
}
