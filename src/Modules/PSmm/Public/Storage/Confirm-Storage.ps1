#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function Confirm-Storage {
    <#
    .SYNOPSIS
        Confirms and validates storage configuration.

    .DESCRIPTION
        Validates the Master and Backup storage drives defined in the application configuration.
        Checks drive availability by serial number and updates drive letter information.
        Logs errors for any missing storage devices.

    .PARAMETER Config
        Application configuration object (AppConfiguration).
        Preferred modern approach with strongly-typed configuration.


    .EXAMPLE
        Confirm-Storage -Config $appConfig

        Validates storage using modern AppConfiguration object.



    .NOTES
        This function validates storage using the hierarchical structure:
        - Storage.1.Master (Primary Master)
        - Storage.1.Backup.1 (First backup)
        - Storage.1.Backup.2 (Second backup)
        - Storage.2.Master (Secondary Master)
        - Storage.2.Backup (Additional backups)
    #>
    [CmdletBinding()]
    param(
        # Modern strongly-typed configuration object
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AppConfiguration]$Config
    )

    try {
        Write-Verbose 'Validating storage configuration...'

        # Initialize error tracking
        $errorTracker = @{}

        # Determine storage root from AppConfiguration
        $storageRoot = $Config.Storage
        $availableDrives = Get-StorageDrive

        if ($null -eq $storageRoot -or $storageRoot.Count -eq 0) {
            Write-PSmmLog -Level WARNING -Context 'Confirm-Storage' -Message 'No storage groups configured' -Console -File
            return
        }

        foreach ($storageGroup in $storageRoot.Keys | Sort-Object) {
            Write-Verbose "Processing Storage Group: $storageGroup"

            # Validate Master storage
            if ($storageRoot[$storageGroup].Master) {
                $testParams = @{
                    StorageConfig = $storageRoot[$storageGroup].Master
                    AvailableDrives = $availableDrives
                    StorageType = 'Master'
                    StorageGroup = $storageGroup
                    ErrorTracker = $errorTracker
                    Verbose = $VerbosePreference
                }
                $testParams['Config'] = $Config

                Test-StorageDevice @testParams
            }

            # Validate Backup storage(s)
            if ($storageRoot[$storageGroup].Backups) {
                $backupStorage = $storageRoot[$storageGroup].Backups

                # Check if Backup is empty (like Storage.2.Backup)
                if ($backupStorage.Count -eq 0) {
                    Write-Verbose "Storage Group $storageGroup has no backup drives configured"
                }
                else {
                    # Process each numbered backup
                    foreach ($backupId in $backupStorage.Keys | Sort-Object) {
                        Write-Verbose "Processing Backup $backupId for Storage Group $storageGroup"

                        $testParams = @{
                            StorageConfig = $backupStorage.$backupId
                            AvailableDrives = $availableDrives
                            StorageType = 'Backup'
                            StorageGroup = $storageGroup
                            BackupId = $backupId
                            ErrorTracker = $errorTracker
                            Verbose = $VerbosePreference
                        }
                        $testParams['Config'] = $Config

                        Test-StorageDevice @testParams
                    }
                }
            }
        }

        # Log summary
        $errorCount = ($errorTracker.Values | Measure-Object).Count
        if ($errorCount -eq 0) {
            Write-PSmmLog -Level INFO -Context 'Confirm-Storage' `
                -Message 'All configured storage devices validated successfully' -Console -File
        }
        else {
            Write-PSmmLog -Level WARNING -Context 'Confirm-Storage' `
                -Message "Storage validation completed with $errorCount error(s)" -Console -File

            # Log each error
            foreach ($errorKey in $errorTracker.Keys) {
                Write-PSmmLog -Level ERROR -Context 'Confirm-Storage' `
                    -Message $errorTracker[$errorKey] -Console -File
            }
        }
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Confirm-Storage' `
            -Message "Storage validation failed: $_" -Console -File
        throw
    }
}

<#
.SYNOPSIS
    Tests a single storage device configuration.

.DESCRIPTION
    Validates a single storage device by checking if it's available via serial number.
    Updates the drive letter if found, or logs an error if not found.
#>
function Test-StorageDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$StorageConfig,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$AvailableDrives,

        [Parameter(Mandatory)]
        [string]$StorageType,

        [Parameter(Mandatory)]
        [string]$StorageGroup,

        [Parameter()]
        [string]$BackupId = '',

        [Parameter(Mandatory)]
        [hashtable]$ErrorTracker,

        [Parameter()]
        [AppConfiguration]$Config = $null
    )

    # Extract storage configuration values
    $serialNumber = $null
    $label = $null
    $isOptional = $false
    try { $serialNumber = $StorageConfig.SerialNumber }
    catch {
        Write-Verbose "Storage configuration is missing SerialNumber: $_"
    }
    try { $label = $StorageConfig.Label }
    catch {
        Write-Verbose "Storage configuration is missing Label: $_"
    }
    try { $isOptional = [bool]$StorageConfig.Optional }
    catch {
        Write-Verbose "Storage configuration is missing Optional flag: $_"
    }

    # Build identifier for logging
    $identifier = if ($BackupId) {
        "$StorageType $BackupId"
    }
    else {
        $StorageType
    }

    # Validate serial number is not empty
    if ([string]::IsNullOrWhiteSpace($serialNumber)) {
        Write-Verbose "Storage.$StorageGroup.$identifier : $label has empty serial number, skipping validation"
        Write-PSmmLog -Level WARNING -Context 'Confirm-Storage' `
            -Message "Storage.$StorageGroup.$identifier : $label has no serial number configured" -Console
        return
    }

    # Find the drive by serial number (exclude drives with empty serial numbers)
    $drive = $AvailableDrives | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.SerialNumber) -and
        $_.SerialNumber.Trim() -eq $serialNumber.Trim()
    } | Select-Object -First 1

    if ($drive) {
        # Update drive letter
        try { $StorageConfig.DriveLetter = $drive.DriveLetter }
        catch {
            Write-Verbose "Unable to assign DriveLetter on storage config: $_"
        }
        try { $StorageConfig.IsAvailable = $true }
        catch {
            Write-Verbose "Unable to mark storage config as available: $_"
        }

        # Also update the original Config object if provided
        if ($null -ne $Config -and $Config.Storage.ContainsKey($StorageGroup)) {
            $configGroup = $Config.Storage[$StorageGroup]

            if ($StorageType -eq 'Master' -and $null -ne $configGroup.Master) {
                Write-Verbose "Updating Master DriveLetter in Config object: $($drive.DriveLetter)"
                $configGroup.Master.DriveLetter = $drive.DriveLetter
                $configGroup.Master.UpdateStatus()
            }
            elseif ($StorageType -eq 'Backup' -and $BackupId -and $null -ne $configGroup.Backups -and $configGroup.Backups.ContainsKey($BackupId)) {
                Write-Verbose "Updating Backup.$BackupId DriveLetter in Config object: $($drive.DriveLetter)"
                $configGroup.Backups[$BackupId].DriveLetter = $drive.DriveLetter
                $configGroup.Backups[$BackupId].UpdateStatus()
            }
        }

        Write-Verbose "Storage.$StorageGroup.$identifier : $label ($serialNumber) -> $($drive.DriveLetter)"
        Write-PSmmLog -Level INFO -Context 'Confirm-Storage' `
            -Message "Storage.$StorageGroup.$identifier : $label found at $($drive.DriveLetter)" -Console
    }
    else {
        # Build error key
        $errorKey = if ($BackupId) {
            "$StorageGroup.$StorageType.$BackupId"
        }
        else {
            "$StorageGroup.$StorageType"
        }

        $errorMessage = "$StorageType Disk: $label (SN: $serialNumber) not found."

        # Store error only if not optional
        if (-not $isOptional) {
            if (-not $ErrorTracker.ContainsKey($errorKey)) {
                $ErrorTracker[$errorKey] = $errorMessage
            }

            Write-Verbose "Storage.$StorageGroup ERROR: $errorMessage"
        }
        else {
            Write-Verbose "Storage.$StorageGroup INFO: $errorMessage (Optional - not an error)"
            Write-PSmmLog -Level INFO -Context 'Confirm-Storage' `
                -Message "Storage.$StorageGroup.$identifier : $label not found (Optional)" -Console
        }

        # Clear drive letter and mark as unavailable
        try { $StorageConfig.DriveLetter = '' }
        catch {
            Write-Verbose "Unable to clear DriveLetter on storage config: $_"
        }
        try { $StorageConfig.IsAvailable = $false }
        catch {
            Write-Verbose "Unable to clear availability flag on storage config: $_"
        }

        # Also update Config object if provided
        if ($null -ne $Config -and $Config.Storage.ContainsKey($StorageGroup)) {
            $configGroup = $Config.Storage[$StorageGroup]

            if ($StorageType -eq 'Master' -and $null -ne $configGroup.Master) {
                $configGroup.Master.DriveLetter = ''
                $configGroup.Master.IsAvailable = $false
            }
            elseif ($StorageType -eq 'Backup' -and $BackupId -and $null -ne $configGroup.Backups -and $configGroup.Backups.ContainsKey($BackupId)) {
                $configGroup.Backups[$BackupId].DriveLetter = ''
                $configGroup.Backups[$BackupId].IsAvailable = $false
            }
        }
    }
}

#endregion ########## PUBLIC ##########
