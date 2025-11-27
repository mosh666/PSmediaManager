<#
.SYNOPSIS
    Implementation of IStorageService interface.

.DESCRIPTION
    Provides testable storage drive operations by wrapping Windows CIM APIs.
    This service can be mocked in tests for full testability.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
#>

using namespace System
using namespace System.Collections.Generic

<#
.SYNOPSIS
    Production implementation of storage service.
#>
class StorageService : IStorageService {

    <#
    .SYNOPSIS
        Gets information about physical storage drives.

    .DESCRIPTION
        Retrieves detailed information about all physical disk drives in the system,
        including drive letter, label, serial number, manufacturer, model, and space information.
        This function is used to identify and validate storage drives by their serial numbers.

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
        - BusType: Disk bus type (e.g., USB, SATA)
        - InterfaceType: Interface type from Win32_DiskDrive (e.g., USB)
        - DriveType: Logical drive type (2=Removable, 3=LocalDisk, etc.)
        - IsRemovable: True when removable/USB
    #>
    [object[]] GetStorageDrives() {
        # Cross-platform guard: On non-Windows platforms (or when CIM cmdlets are unavailable),
        # return an empty result instead of throwing. This keeps callers resilient in WSL/Linux.
        try {
            $isWindowsPlatform = if (Test-Path Variable:\IsWindows) { $script:IsWindows } else { $true }
            if (-not $isWindowsPlatform -or -not (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)) {
                Write-Verbose "StorageService: Windows CIM APIs are unavailable on this platform; returning empty result."
                return @()
            }
        }
        catch {
            # In case environment probing fails unexpectedly, fail safe
            Write-Verbose "StorageService: Environment probe failed; returning empty result. Details: $_"
            return @()
        }

        try {
            $drives = [List[object]]::new()

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

                                $isUsbBus = $null -ne $diskMetadata.BusType -and ([string]$diskMetadata.BusType) -eq 'USB'
                                $isUsbIface = -not [string]::IsNullOrWhiteSpace($disk.InterfaceType) -and $disk.InterfaceType -eq 'USB'
                                $driveTypeVal = $logicalDisk.DriveType
                                $isRemovable = ($driveTypeVal -eq 2) -or $isUsbBus -or $isUsbIface

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
                                    BusType = $diskMetadata.BusType
                                    InterfaceType = $disk.InterfaceType
                                    DriveType = $driveTypeVal
                                    IsRemovable = [bool]$isRemovable
                                }

                                $drives.Add($driveInfo)
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

            return $drives.ToArray()
        }
        catch {
            throw [InvalidOperationException]::new("Failed to retrieve storage drive information: $_", $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        Finds a storage drive by serial number.
    #>
    [object] FindDriveBySerial([string]$serialNumber) {
        if ([string]::IsNullOrWhiteSpace($serialNumber)) {
            throw [ArgumentException]::new("Serial number cannot be empty", "serialNumber")
        }

        $drives = $this.GetStorageDrives()
        $matchingDrive = $drives | Where-Object { $_.SerialNumber -eq $serialNumber } | Select-Object -First 1

        return $matchingDrive
    }

    <#
    .SYNOPSIS
        Finds a storage drive by label.
    #>
    [object] FindDriveByLabel([string]$label) {
        if ([string]::IsNullOrWhiteSpace($label)) {
            throw [ArgumentException]::new("Label cannot be empty", "label")
        }

        $drives = $this.GetStorageDrives()
        $matchingDrive = $drives | Where-Object { $_.Label -eq $label } | Select-Object -First 1

        return $matchingDrive
    }

    <#
    .SYNOPSIS
        Gets removable/USB drives only.
    #>
    [object[]] GetRemovableDrives() {
        $drives = $this.GetStorageDrives()
        return @($drives | Where-Object { $_.IsRemovable })
    }
}
