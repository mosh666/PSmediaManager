#Requires -Version 7.5.4
Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmConfigMemberValue -ErrorAction SilentlyContinue)) {
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $helperPath = Join-Path -Path $moduleRoot -ChildPath 'Private\\Get-PSmmConfigMemberValue.ps1'
    if (Test-Path $helperPath) {
        . $helperPath
    }
}

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
        # Accept both strongly-typed AppConfiguration and legacy IDictionary configs
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config
    )

    try {
        Write-Verbose 'Validating storage configuration...'

        # Initialize error tracking
        $errorTracker = @{}

        # Determine storage root from config
        $storageRoot = Get-PSmmConfigMemberValue -Object $Config -Name 'Storage' -Default $null
        $availableDrives = Get-StorageDrive
        if ($null -eq $availableDrives) {
            $availableDrives = @()
        }

        if ($null -eq $storageRoot -or $storageRoot.Count -eq 0) {
            Write-PSmmLog -Level WARNING -Context 'Confirm-Storage' -Message 'No storage groups configured' -Console -File
            return
        }

        foreach ($storageGroup in $storageRoot.Keys | Sort-Object) {
            Write-Verbose "Processing Storage Group: $storageGroup"

            $group = Get-PSmmConfigMemberValue -Object $storageRoot -Name ([string]$storageGroup) -Default $null
            if ($null -eq $group) {
                continue
            }

            # Validate Master storage
            $masterCfg = Get-PSmmConfigMemberValue -Object $group -Name 'Master' -Default $null
            if ($null -ne $masterCfg) {
                $testParams = @{
                    StorageConfig = $masterCfg
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
            $backupStorage = Get-PSmmConfigMemberValue -Object $group -Name 'Backups' -Default $null
            if ($null -eq $backupStorage) {
                $backupStorage = Get-PSmmConfigMemberValue -Object $group -Name 'Backup' -Default $null
            }

            if ($null -ne $backupStorage) {

                # Check if Backup is empty (like Storage.2.Backup)
                if ($backupStorage.Count -eq 0) {
                    Write-Verbose "Storage Group $storageGroup has no backup drives configured"
                }
                else {
                    # Process each numbered backup
                    foreach ($backupId in $backupStorage.Keys | Sort-Object) {
                        Write-Verbose "Processing Backup $backupId for Storage Group $storageGroup"

                        $backupCfg = Get-PSmmConfigMemberValue -Object $backupStorage -Name ([string]$backupId) -Default $null
                        if ($null -eq $backupCfg) {
                            continue
                        }

                        $testParams = @{
                            StorageConfig = $backupCfg
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
        [object]$Config = $null
    )

    # Extract storage configuration values
    $serialNumber = [string](Get-PSmmConfigMemberValue -Object $StorageConfig -Name 'SerialNumber' -Default '')
    $label = [string](Get-PSmmConfigMemberValue -Object $StorageConfig -Name 'Label' -Default '')
    $isOptional = [bool](Get-PSmmConfigMemberValue -Object $StorageConfig -Name 'Optional' -Default $false)

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
        if ($StorageConfig -is [System.Collections.IDictionary]) {
            try { $StorageConfig['DriveLetter'] = $drive.DriveLetter } catch { Write-Verbose "Unable to assign DriveLetter on storage config dictionary: $_" }
            try { $StorageConfig['IsAvailable'] = $true } catch { Write-Verbose "Unable to mark storage config dictionary as available: $_" }
        }
        else {
            try { $StorageConfig.DriveLetter = $drive.DriveLetter }
            catch {
                Write-Verbose "Unable to assign DriveLetter on storage config: $_"
            }
            try { $StorageConfig.IsAvailable = $true }
            catch {
                Write-Verbose "Unable to mark storage config as available: $_"
            }
        }

        # Also update the original Config object if provided
        if ($null -ne $Config) {
            $configStorage = Get-PSmmConfigMemberValue -Object $Config -Name 'Storage' -Default $null

            if ($null -ne $configStorage) {
                $configGroup = $null
                try { $configGroup = $configStorage[[string]$StorageGroup] } catch { $configGroup = $null }
                if ($null -eq $configGroup) {
                    $configGroup = Get-PSmmConfigMemberValue -Object $configStorage -Name ([string]$StorageGroup) -Default $null
                }

                if ($null -ne $configGroup) {
                    if ($StorageType -eq 'Master') {
                        $master = $null
                        try { $master = if ($configGroup -is [System.Collections.IDictionary]) { $configGroup['Master'] } else { $configGroup.Master } } catch { $master = $null }
                        if ($null -ne $master) {
                            Write-Verbose "Updating Master DriveLetter in Config object: $($drive.DriveLetter)"
                            try { $master.DriveLetter = $drive.DriveLetter }
                            catch { Write-Verbose "Unable to update Master DriveLetter in Config object: $_" }
                            try { $master.UpdateStatus() }
                            catch { Write-Verbose "Unable to update Master status in Config object: $_" }
                        }
                    }
                    elseif ($StorageType -eq 'Backup' -and $BackupId) {
                        $backups = $null
                        try {
                            if ($configGroup -is [System.Collections.IDictionary]) {
                                $backups = Get-PSmmConfigMemberValue -Object $configGroup -Name 'Backups' -Default $null
                                if ($null -eq $backups) {
                                    $backups = Get-PSmmConfigMemberValue -Object $configGroup -Name 'Backup' -Default $null
                                }
                            }
                            else {
                                $backups = if ($null -ne $configGroup.Backups) { $configGroup.Backups } elseif ($null -ne $configGroup.Backup) { $configGroup.Backup } else { $null }
                            }
                        }
                        catch {
                            $backups = $null
                        }

                        if ($null -ne $backups) {
                            $backupTarget = $null
                            try { $backupTarget = $backups[[string]$BackupId] } catch { $backupTarget = $null }
                            if ($null -ne $backupTarget) {
                                Write-Verbose "Updating Backup.$BackupId DriveLetter in Config object: $($drive.DriveLetter)"
                                try { $backupTarget.DriveLetter = $drive.DriveLetter }
                                catch { Write-Verbose "Unable to update Backup.$BackupId DriveLetter in Config object: $_" }
                                try { $backupTarget.UpdateStatus() }
                                catch { Write-Verbose "Unable to update Backup.$BackupId status in Config object: $_" }
                            }
                        }
                    }
                }
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
        if ($StorageConfig -is [System.Collections.IDictionary]) {
            try { $StorageConfig['DriveLetter'] = '' } catch { Write-Verbose "Unable to clear DriveLetter on storage config dictionary: $_" }
            try { $StorageConfig['IsAvailable'] = $false } catch { Write-Verbose "Unable to clear availability flag on storage config dictionary: $_" }
        }
        else {
            try { $StorageConfig.DriveLetter = '' }
            catch {
                Write-Verbose "Unable to clear DriveLetter on storage config: $_"
            }
            try { $StorageConfig.IsAvailable = $false }
            catch {
                Write-Verbose "Unable to clear availability flag on storage config: $_"
            }
        }

        # Also update Config object if provided
        if ($null -ne $Config) {
            $storageRoot = Get-PSmmConfigMemberValue -Object $Config -Name 'Storage' -Default $null
            if ($null -eq $storageRoot) {
                return
            }

            $configGroup = $null
            try { $configGroup = $storageRoot[[string]$StorageGroup] } catch { $configGroup = $null }
            if ($null -eq $configGroup) {
                $configGroup = Get-PSmmConfigMemberValue -Object $storageRoot -Name ([string]$StorageGroup) -Default $null
            }
            if ($null -eq $configGroup) {
                return
            }

            if ($StorageType -eq 'Master') {
                $masterCfg = Get-PSmmStorageConfigMemberValue -Object $configGroup -Name 'Master'
                if ($null -ne $masterCfg) {
                    try { $masterCfg.DriveLetter = '' }
                    catch {
                        Write-Verbose "Unable to clear Master DriveLetter on Config object: $_"
                        try { if ($masterCfg -is [System.Collections.IDictionary]) { $masterCfg['DriveLetter'] = '' } }
                        catch { Write-Verbose "Unable to clear Master DriveLetter on Config dictionary: $_" }
                    }
                    try { $masterCfg.IsAvailable = $false }
                    catch {
                        Write-Verbose "Unable to clear Master availability flag on Config object: $_"
                        try { if ($masterCfg -is [System.Collections.IDictionary]) { $masterCfg['IsAvailable'] = $false } }
                        catch { Write-Verbose "Unable to clear Master availability flag on Config dictionary: $_" }
                    }
                }
            }
            elseif ($StorageType -eq 'Backup' -and $BackupId) {
                $backupsCfg = Get-PSmmConfigMemberValue -Object $configGroup -Name 'Backups' -Default $null
                if ($null -eq $backupsCfg) { $backupsCfg = Get-PSmmConfigMemberValue -Object $configGroup -Name 'Backup' -Default $null }

                $backupCfg = $null
                if ($null -ne $backupsCfg) {
                    try { $backupCfg = $backupsCfg[[string]$BackupId] } catch { $backupCfg = $null }
                    if ($null -eq $backupCfg) {
                        $backupCfg = Get-PSmmConfigMemberValue -Object $backupsCfg -Name ([string]$BackupId) -Default $null
                    }
                }
                if ($null -ne $backupCfg) {
                    try { $backupCfg.DriveLetter = '' }
                    catch {
                        Write-Verbose "Unable to clear Backup.$BackupId DriveLetter on Config object: $_"
                        try { if ($backupCfg -is [System.Collections.IDictionary]) { $backupCfg['DriveLetter'] = '' } }
                        catch { Write-Verbose "Unable to clear Backup.$BackupId DriveLetter on Config dictionary: $_" }
                    }
                    try { $backupCfg.IsAvailable = $false }
                    catch {
                        Write-Verbose "Unable to clear Backup.$BackupId availability flag on Config object: $_"
                        try { if ($backupCfg -is [System.Collections.IDictionary]) { $backupCfg['IsAvailable'] = $false } }
                        catch { Write-Verbose "Unable to clear Backup.$BackupId availability flag on Config dictionary: $_" }
                    }
                }
            }
        }
    }
}

#endregion ########## PUBLIC ##########
