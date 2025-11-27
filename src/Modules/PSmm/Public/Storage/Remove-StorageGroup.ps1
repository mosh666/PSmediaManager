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
        [AppConfiguration]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DriveRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$GroupIds
    )

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
        if ($storageHashtable.ContainsKey($gid)) {
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
    $Config.Storage.Clear()

    if ($storageHashtable.Count -gt 0) {
        # Re-read from file to get renumbered groups
        $reloaded = [AppConfigurationBuilder]::ReadStorageFile($storagePath)

        if ($null -ne $reloaded) {
            foreach ($groupKey in $reloaded.Keys) {
                $groupTable = $reloaded[$groupKey]
                $group = [StorageGroupConfig]::new([string]$groupKey)
                if ($groupTable.ContainsKey('DisplayName')) { $group.DisplayName = $groupTable.DisplayName }

                if ($groupTable.ContainsKey('Master') -and $groupTable.Master) {
                    $mLabel = if ($groupTable.Master.ContainsKey('Label')) { $groupTable.Master.Label } else { '' }
                    $mSerial = if ($groupTable.Master.ContainsKey('SerialNumber')) { $groupTable.Master.SerialNumber } else { '' }
                    $group.Master = [StorageDriveConfig]::new($mLabel, '')
                    $group.Master.SerialNumber = $mSerial
                }

                if ($groupTable.ContainsKey('Backup') -and $groupTable.Backup -is [hashtable]) {
                    foreach ($bk in ($groupTable.Backup.Keys | Where-Object { $_ -match '^[0-9]+' } | Sort-Object {[int]$_})) {
                        $b = $groupTable.Backup[$bk]
                        if ($null -eq $b) { continue }
                        $bLabel = if ($b.ContainsKey('Label')) { $b.Label } else { '' }
                        $bSerial = if ($b.ContainsKey('SerialNumber')) { $b.SerialNumber } else { '' }
                        $cfg = [StorageDriveConfig]::new($bLabel, '')
                        $cfg.SerialNumber = $bSerial
                        $group.Backups[[string]$bk] = $cfg
                    }
                }

                $Config.Storage[[string]$groupKey] = $group
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

    foreach ($groupKey in $Config.Storage.Keys) {
        $group = $Config.Storage[$groupKey]

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
