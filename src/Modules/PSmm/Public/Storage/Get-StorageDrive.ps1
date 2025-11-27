<#
.SYNOPSIS
    Gets information about physical storage drives.

.DESCRIPTION
    Retrieves detailed information about all physical disk drives in the system,
    including drive letter, label, serial number, manufacturer, model, and space information.
    This function is used to identify and validate storage drives by their serial numbers.

    This function serves as a public wrapper around the StorageService class, maintaining
    backward compatibility while delegating to the testable service implementation.

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
    - BusType: Disk bus type (e.g., USB, SATA)
    - InterfaceType: Interface type from Win32_DiskDrive (e.g., USB)
    - DriveType: Logical drive type (2=Removable, 3=LocalDisk, etc.)
    - IsRemovable: True when removable/USB

.NOTES
    This function wraps the StorageService class for backward compatibility.
    For new code, consider using StorageService directly for better testability.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function Get-StorageDrive {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]],[object[]])]
    param()

    try {
        $storageService = [StorageService]::new()
        return $storageService.GetStorageDrives()
    }
    catch {
        Write-Error "Failed to retrieve storage drive information: $_"
        throw
    }
}

#endregion ########## PUBLIC ##########
