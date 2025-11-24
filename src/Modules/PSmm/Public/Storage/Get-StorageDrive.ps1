<#
.SYNOPSIS
    Gets information about physical storage drives.

.DESCRIPTION
    Retrieves detailed information about all physical disk drives in the system,
    including drive letter, label, serial number, manufacturer, model, and space information.
    This function is used to identify and validate storage drives by their serial numbers.

.EXAMPLE
    Get-StorageDrive
    Returns an array of PSCustomObjects containing drive information.

.EXAMPLE
    Get-StorageDrive | Where-Object { $_.SerialNumber -eq 'ABC123' }
    Finds a specific drive by serial number.

.OUTPUTS
    Array of PSCustomObjects with the following properties:
    - Label: Volume label
    - DriveLetter: Drive letter (e.g., 'C:')
    - Number: Disk number
    - Manufacturer: Disk manufacturer
    - Model: Disk model
    - SerialNumber: Disk serial number
    - Name: Disk caption
    - FileSystem: File system type
    - PartitionKind: Partition style (GPT, MBR)
    - TotalSpace: Total space in GB
    - FreeSpace: Free space in GB
    - UsedSpace: Used space in GB
    - HealthStatus: Volume health status
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function Get-StorageDrive {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    # Cross-platform guard: On non-Windows platforms (or when CIM cmdlets are unavailable),
    # return an empty result instead of throwing. This keeps callers resilient in WSL/Linux.
    try {
        if (-not $IsWindows -or -not (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)) {
            Write-Verbose "Get-StorageDrive: Windows CIM APIs are unavailable on this platform; returning empty result."
            return @()
        }
    }
    catch {
        # In case environment probing fails unexpectedly, fail safe
        Write-Verbose "Get-StorageDrive: Environment probe failed; returning empty result. Details: $_"
        return @()
    }

    try {
        $drives = @()

        foreach ($disk in Get-CimInstance Win32_Diskdrive) {
            try {
                $diskMetadata = Get-Disk | Where-Object { $_.Number -eq $disk.Index } | Select-Object -First 1

                if ($null -eq $diskMetadata) {
                    Write-Verbose "No metadata found for disk $($disk.Index), skipping..."
                    continue
                }

                $partitions = Get-CimAssociatedInstance -ResultClassName Win32_DiskPartition -InputObject $disk

                if ($null -eq $partitions) {
                    Write-Verbose "No partitions found for disk $($disk.Index), skipping..."
                    continue
                }

                foreach ($partition in $partitions) {
                    $logicalDisks = Get-CimAssociatedInstance -ResultClassName Win32_LogicalDisk -InputObject $partition

                    if ($null -eq $logicalDisks) {
                        continue
                    }

                    foreach ($logicalDisk in $logicalDisks) {
                        try {
                            $totalSpace = [math]::Round($logicalDisk.Size / 1GB, 3)
                            $freeSpace = [math]::Round($logicalDisk.FreeSpace / 1GB, 3)
                            $usedSpace = [math]::Round($totalSpace - $freeSpace, 3)

                            $volume = Get-Volume |
                                Where-Object { $_.DriveLetter -eq $logicalDisk.DeviceID.Trim(":") } |
                                Select-Object -First 1

                            if ($null -eq $volume) {
                                Write-Verbose "No volume found for drive $($logicalDisk.DeviceID), skipping..."
                                continue
                            }

                            $driveInfo = [PSCustomObject]@{
                                Label = $volume.FileSystemLabel
                                DriveLetter = $logicalDisk.DeviceID
                                Number = $disk.Index
                                Manufacturer = $diskMetadata.Manufacturer
                                Model = $diskMetadata.Model
                                SerialNumber = if ($diskMetadata.SerialNumber) { $diskMetadata.SerialNumber.Trim() } else { '' }
                                Name = $disk.Caption
                                FileSystem = $volume.FileSystem
                                PartitionKind = $diskMetadata.PartitionStyle
                                TotalSpace = $totalSpace
                                FreeSpace = $freeSpace
                                UsedSpace = $usedSpace
                                HealthStatus = $volume.HealthStatus
                            }

                            $drives += $driveInfo
                        }
                        catch {
                            Write-Verbose "Error processing logical disk: $_"
                            continue
                        }
                    }
                }
            }
            catch {
                Write-Verbose "Error processing disk $($disk.Index): $_"
                continue
            }
        }

        return $drives
    }
    catch {
        Write-Error "Failed to retrieve storage drive information: $_"
        throw
    }
}

#endregion ########## PUBLIC ##########
