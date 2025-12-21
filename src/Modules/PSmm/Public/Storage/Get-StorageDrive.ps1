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
    [CmdletBinding()] [OutputType([PSCustomObject[]],[object[]])]
    param()

    function Test-MapContainsKey {
        param(
            [Parameter(Mandatory)]
            [AllowNull()]
            $Map,

            [Parameter(Mandatory)]
            [AllowNull()]
            $Key
        )

        if ($null -eq $Map) { return $false }

        if ($Map -is [System.Collections.IDictionary]) {
            try {
                if ([bool]$Map.ContainsKey($Key)) { return $true }
            }
            catch {
                Write-Verbose "Test-MapContainsKey: ContainsKey() failed: $($_.Exception.Message)"
            }
            try {
                if ([bool]$Map.Contains($Key)) { return $true }
            }
            catch {
                Write-Verbose "Test-MapContainsKey: Contains() failed: $($_.Exception.Message)"
            }
            try {
                foreach ($k in $Map.Keys) {
                    if ($k -eq $Key) { return $true }
                }
            }
            catch {
                Write-Verbose "Test-MapContainsKey: failed iterating Keys: $($_.Exception.Message)"
            }
            return $false
        }

        try { return [bool]$Map.ContainsKey($Key) } catch { return $false }
    }

    $forceInlineEnumeration = $false
    if ($env:MEDIA_MANAGER_TEST_FORCE_INLINE_STORAGE -eq '1') {
        $forceInlineEnumeration = $true
        Write-Verbose 'Get-StorageDrive: forcing inline enumeration via MEDIA_MANAGER_TEST_FORCE_INLINE_STORAGE.'
    }

    # Test hook: when forcing inline enumeration and the test data bag is present, use it instead of CIM calls.
    $testData = $null
    $useTestData = $false
    if ($forceInlineEnumeration -and (Get-Variable -Name PSmmTestDriveData -Scope Script -ErrorAction SilentlyContinue)) {
        $testData = $script:PSmmTestDriveData
        if ($testData) { $useTestData = $true }
    }

    # Allow tests (and non-Windows platforms) to short‑circuit via mocked Get-Command.
    if (-not (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)) {
        Write-Verbose 'Get-StorageDrive: CIM APIs unavailable; returning empty result.'
        return @()
    }

    # If the StorageService class is available and tests are not mocking low-level cmdlets, we
    # still prefer the service for consistency. Tests that mock Win32_* cmdlets will exercise
    # the inline implementation below, because mocks apply to the direct calls.
    $useInlineEnumeration = $true
    if (-not $forceInlineEnumeration -and (Get-Command -Name 'Get-CimInstance' -ErrorAction SilentlyContinue)) {
        # Heuristic: if class exists and no Pester mocks are detected for any of the core
        # cmdlets, we can delegate. Pester registers mocks as functions in the current scope;
        # we check for a script block source reference in command metadata.
        $coreCmdlets = 'Get-CimInstance','Get-Disk','Get-CimAssociatedInstance','Get-Volume'
        $mocked = $false
        foreach ($c in $coreCmdlets) {
            $cmdInfo = Get-Command -Name $c -ErrorAction SilentlyContinue
            if ($cmdInfo -and $cmdInfo.Source -eq 'Pester') { $mocked = $true; break }
        }
        if (-not $mocked -and ($null -ne [type]::GetType('StorageService'))) {
            try {
                $service = [StorageService]::new()
                return $service.GetStorageDrives()
            }
            catch {
                Write-Verbose "Get-StorageDrive: StorageService delegation failed, falling back to inline enumeration. Details: $_"
                $useInlineEnumeration = $true
            }
        }
    }

    if ($useInlineEnumeration) {
        $drives = @()
        try {
            $disks = if ($useTestData) { @($testData.Disks) } else { @(Get-CimInstance Win32_Diskdrive -ErrorAction Stop) }
        }
        catch {
            Write-Verbose "Get-StorageDrive: CIM query failed, returning empty result. Details: $_"
            return @()
        }

        foreach ($disk in $disks) {
            try {
                $diskMetadata = if ($useTestData -and $testData.DiskMetadata -and (Test-MapContainsKey -Map $testData.DiskMetadata -Key $disk.Index)) {
                    $testData.DiskMetadata[$disk.Index]
                } else {
                    Get-Disk | Where-Object { $_.Number -eq $disk.Index } | Select-Object -First 1
                }
                if ($null -eq $diskMetadata) { continue }
                $partitions = if ($useTestData -and $testData.Partitions -and (Test-MapContainsKey -Map $testData.Partitions -Key $disk.Index)) {
                    $testData.Partitions[$disk.Index]
                } else {
                    Get-CimAssociatedInstance -ResultClassName Win32_DiskPartition -InputObject $disk
                }
                if ($null -eq $partitions -or $partitions.Count -eq 0) { continue }
                foreach ($partition in $partitions) {
                    $logicalDisks = if ($useTestData -and $testData.LogicalDisks -and (Test-MapContainsKey -Map $testData.LogicalDisks -Key $partition.Index)) {
                        $testData.LogicalDisks[$partition.Index]
                    } else {
                        Get-CimAssociatedInstance -ResultClassName Win32_LogicalDisk -InputObject $partition
                    }
                    if ($null -eq $logicalDisks -or $logicalDisks.Count -eq 0) { continue }
                    foreach ($logicalDisk in $logicalDisks) {
                        try {
                            $totalSpace = [math]::Round($logicalDisk.Size / 1GB, 3)
                            $freeSpace = [math]::Round($logicalDisk.FreeSpace / 1GB, 3)
                            $usedSpace = [math]::Round($totalSpace - $freeSpace, 3)
                            $driveLetter = $logicalDisk.DeviceID.Trim(':')
                            $volume = if ($useTestData -and $testData.Volumes -and (Test-MapContainsKey -Map $testData.Volumes -Key $driveLetter)) {
                                $testData.Volumes[$driveLetter]
                            } else {
                                Get-Volume | Where-Object { $_.DriveLetter -eq $driveLetter } | Select-Object -First 1
                            }
                            if ($null -eq $volume) { continue }
                            $isUsbBus = $null -ne $diskMetadata.BusType -and ([string]$diskMetadata.BusType) -eq 'USB'
                            $isUsbIface = -not [string]::IsNullOrWhiteSpace($disk.InterfaceType) -and $disk.InterfaceType -eq 'USB'
                            $driveTypeVal = $logicalDisk.DriveType
                            $isRemovable = ($driveTypeVal -eq 2) -or $isUsbBus -or $isUsbIface
                            $drives += [PSCustomObject]@{
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
                        }
                        catch {
                            Write-Verbose "Get-StorageDrive: error processing logical disk '$($logicalDisk.DeviceID)': $_"
                            continue
                        }
                    }
                }
            }
            catch {
                Write-Verbose "Get-StorageDrive: error processing disk index '$($disk.Index)': $_"
                continue
            }
        }
        return $drives
    }
}

#endregion ########## PUBLIC ##########
