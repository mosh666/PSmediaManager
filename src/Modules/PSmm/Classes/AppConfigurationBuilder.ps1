<#
.SYNOPSIS
    Builder pattern for constructing AppConfiguration instances.

.DESCRIPTION
    Provides a fluent interface for building and configuring the PSmediaManager
    application. This pattern improves code readability and maintainability.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0

    IMPORTANT: This file depends on types defined in AppConfiguration.ps1
    The module loader (PSmm.psm1) ensures AppConfiguration.ps1
    is loaded BEFORE this file, so all type references are valid at runtime.

    The PowerShell language server may show "Unable to find type" errors
    because it analyzes files individually. These are FALSE POSITIVES and
    can be safely ignored. The code works correctly at runtime.
#>

using namespace System
using namespace System.IO

#Requires -Version 7.5.4

# Suppress TypeNotFound warnings - these types are loaded at runtime from AppConfiguration.ps1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('TypeNotFound', '', Justification = 'Types are loaded from AppConfiguration.ps1 before this file by the module loader')]
param()

<#
.SYNOPSIS
    Builder for creating AppConfiguration instances.

.DESCRIPTION
    Requires types from AppConfiguration.ps1 to be loaded first.
#>
class AppConfigurationBuilder {
    hidden [AppConfiguration]$_config
    hidden [bool]$_built = $false

    AppConfigurationBuilder() {
        $this.InitializeConfig()
    }

    AppConfigurationBuilder([string]$rootPath) {
        $this.InitializeConfig()
        $this.ConfigurePathsFromHint($rootPath)
    }

    hidden [void] InitializeConfig() {
        $this._config = [AppConfiguration]::new()
        if ([string]::IsNullOrWhiteSpace($this._config.InternalName)) {
            $this._config.InternalName = 'PSmm'
        }
        if ([string]::IsNullOrWhiteSpace($this._config.DisplayName)) {
            $this._config.DisplayName = 'PSmediaManager'
        }
        $this._config.Parameters = $null
    }

    hidden [void] ConfigurePathsFromHint([string]$pathHint) {
        $this.EnsureNotBuilt()

        if ([string]::IsNullOrWhiteSpace($pathHint)) {
            throw "Root path cannot be null or empty"
        }

        $resolvedPath = [System.IO.Path]::GetFullPath($pathHint)
        $srcCandidate = [System.IO.Path]::Combine($resolvedPath, 'src')
        $looksLikeRepoRoot = Test-Path -Path $srcCandidate -PathType Container

        $paths = $null
        if ($looksLikeRepoRoot) {
            $runtimeRoot = [System.IO.Path]::GetPathRoot($resolvedPath)
            if ([string]::IsNullOrWhiteSpace($runtimeRoot)) {
                $runtimeRoot = $resolvedPath
            }
            $paths = [AppPaths]::new($resolvedPath, $runtimeRoot)
        }
        else {
            $paths = [AppPaths]::new($resolvedPath)
        }

        $this.ApplyPaths($paths)
    }

    hidden [void] ApplyPaths([AppPaths]$paths) {
        $this._config.Paths = $paths
        $this._config.Secrets = [AppSecrets]::new($paths.App.Vault)

        # Initialize logging with date-based filename anchored to runtime root
        $timestamp = Get-Date -Format 'yyyyMMdd'
        $logFileName = "$timestamp-$($this._config.InternalName)-$env:USERNAME@$env:COMPUTERNAME.log"
        $logPath = [System.IO.Path]::Combine($paths.Log, $logFileName)
        $this._config.Logging = [LoggingConfiguration]::new($logPath)
    }

    [AppConfigurationBuilder] WithRootPath([string]$rootPath) {
        $this.ConfigurePathsFromHint($rootPath)
        return $this
    }

    [AppConfigurationBuilder] WithParameters([RuntimeParameters]$parameters) {
        $this.EnsureNotBuilt()
        $this._config.Parameters = $parameters

        # Ensure logging is initialized
        if ($null -eq $this._config.Logging) {
            $this._config.Logging = [LoggingConfiguration]::new()
        }

        # Adjust logging level based on parameters
        if ($parameters.Debug) {
            $this._config.Logging.Level = 'DEBUG'
            $this._config.Logging.DefaultLevel = 'DEBUG'
        }
        elseif ($parameters.Verbose) {
            $this._config.Logging.Level = 'VERBOSE'
            $this._config.Logging.DefaultLevel = 'VERBOSE'
        }

        return $this
    }

    [AppConfigurationBuilder] WithVersion([version]$version) {
        $this.EnsureNotBuilt()
        $this._config.Version = $version
        return $this
    }

    [AppConfigurationBuilder] WithLogging([LoggingConfiguration]$logging) {
        $this.EnsureNotBuilt()
        $this._config.Logging = $logging
        return $this
    }

    [AppConfigurationBuilder] WithStorageGroup([string]$groupId, [StorageGroupConfig]$storageGroup) {
        $this.EnsureNotBuilt()
        $this._config.Storage[$groupId] = $storageGroup
        return $this
    }

    [AppConfigurationBuilder] LoadConfigurationFile([string]$configPath) {
        $this.EnsureNotBuilt()

        if (-not (Test-Path -Path $configPath)) {
            throw "Configuration file not found: $configPath"
        }

        try {
            $configData = Import-PowerShellDataFile -Path $configPath

            # Merge configuration data
            if ($configData.ContainsKey('App')) {
                if ($configData.App.ContainsKey('Storage')) {
                    foreach ($key in $configData.App.Storage.Keys) {
                        $storageData = $configData.App.Storage[$key]
                        $group = [StorageGroupConfig]::new($key)

                        if ($storageData.ContainsKey('Master') -and $storageData.Master) {
                            $masterLabel = if ($storageData.Master.ContainsKey('Label')) { $storageData.Master.Label } else { '' }
                            $masterDrive = if ($storageData.Master.ContainsKey('DriveLetter')) { $storageData.Master.DriveLetter } else { '' }
                            $masterSerial = if ($storageData.Master.ContainsKey('SerialNumber')) { $storageData.Master.SerialNumber } else { '' }
                            Write-Verbose "Loading Master for Storage.$key : Label=$masterLabel, Drive=$masterDrive, Serial=$masterSerial"
                            $group.Master = [StorageDriveConfig]::new($masterLabel, $masterDrive)
                            $group.Master.SerialNumber = $masterSerial
                            Write-Verbose "Set Master.SerialNumber to: $($group.Master.SerialNumber)"
                        }

                        # Handle Backup storage - config file has numbered backups (1, 2, etc.)
                        if ($storageData.ContainsKey('Backup') -and $storageData.Backup -and $storageData.Backup -is [hashtable]) {
                            # Load all numbered backup entries
                            $backupKeys = $storageData.Backup.Keys | Where-Object { $_ -match '^\d+$' } | Sort-Object { [int]$_ }

                            if ($backupKeys) {
                                foreach ($backupKey in $backupKeys) {
                                    $backup = $storageData.Backup[$backupKey]
                                    $backupLabel = if ($backup.ContainsKey('Label')) { $backup.Label } else { '' }
                                    $backupDriveLetter = if ($backup.ContainsKey('DriveLetter')) { $backup.DriveLetter } else { '' }
                                    $backupSerial = if ($backup.ContainsKey('SerialNumber')) { $backup.SerialNumber } else { '' }
                                    Write-Verbose "Loading Backup.$backupKey for Storage.$key : Label=$backupLabel, Drive=$backupDriveLetter, Serial=$backupSerial"

                                    $backupDriveConfig = [StorageDriveConfig]::new($backupLabel, $backupDriveLetter)
                                    $backupDriveConfig.SerialNumber = $backupSerial
                                    $group.Backups[$backupKey] = $backupDriveConfig
                                    Write-Verbose "Set Backup.$backupKey SerialNumber to: $($backupDriveConfig.SerialNumber)"
                                }
                            }
                            else {
                                Write-Verbose "Storage.$key has Backup hashtable but no numbered entries found"
                            }
                        }

                        if ($storageData.ContainsKey('Paths') -and $storageData.Paths) {
                            foreach ($pathKey in $storageData.Paths.Keys) {
                                $group.Paths[$pathKey] = $storageData.Paths[$pathKey]
                            }
                        }

                        $this._config.Storage[$key] = $group
                    }
                }

                if ($configData.App.ContainsKey('UI')) {
                    $this._config.UI = $configData.App.UI
                }

                if ($configData.App.ContainsKey('Logging')) {
                    $loggingTable = $configData.App.Logging
                    $loggingType = $this._config.Logging.GetType()
                    foreach ($key in $loggingTable.Keys) {
                        $prop = $loggingType.GetProperty($key)
                        if ($null -eq $prop) {
                            Write-Verbose "Skipping unsupported logging configuration key: $key"
                            continue
                        }

                        try {
                            $prop.SetValue($this._config.Logging, $loggingTable[$key])
                        }
                        catch {
                            Write-Warning "Failed to assign logging configuration key '$key': $_"
                        }
                    }
                }
            }

            if ($configData.ContainsKey('Projects')) {
                $this._config.Projects = $configData.Projects
            }
        }
        catch {
            throw "Failed to load configuration file '$configPath': $_"
        }

        return $this
    }

    [AppConfigurationBuilder] LoadRequirementsFile([string]$requirementsPath) {
        $this.EnsureNotBuilt()

        if (-not (Test-Path -Path $requirementsPath)) {
            throw "Requirements file not found: $requirementsPath"
        }

        try {
            $this._config.Requirements = Import-PowerShellDataFile -Path $requirementsPath
        }
        catch {
            throw "Failed to load requirements file '$requirementsPath': $_"
        }

        return $this
    }

    [AppConfigurationBuilder] InitializeDirectories() {
        $this.EnsureNotBuilt()
        $this._config.Paths.EnsureDirectoriesExist()
        return $this
    }

    [AppConfigurationBuilder] LoadSecrets() {
        $this.EnsureNotBuilt()

        if ($null -eq $this._config.Secrets) {
            $this._config.Secrets = [AppSecrets]::new($this._config.Paths.App.Vault)
        }

        $this._config.Secrets.LoadSecrets()
        return $this
    }

    [AppConfigurationBuilder] UpdateStorageStatus() {
        $this.EnsureNotBuilt()

        # Get all available drives using Get-StorageDrive
        $availableDrives = @()
        try {
            if (Get-Command Get-StorageDrive -ErrorAction SilentlyContinue) {
                $availableDrives = Get-StorageDrive
            }
        }
        catch {
            Write-Warning "Failed to get storage drives: $_"
        }

        # Match each storage device by serial number and update drive letters
        foreach ($groupKey in $this._config.Storage.Keys) {
            $group = $this._config.Storage[$groupKey]

            # Match Master drive
            if ($null -ne $group.Master -and -not [string]::IsNullOrWhiteSpace($group.Master.SerialNumber)) {
                $matchedDrive = $availableDrives | Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_.SerialNumber) -and
                    $_.SerialNumber.Trim() -eq $group.Master.SerialNumber.Trim()
                } | Select-Object -First 1

                if ($matchedDrive) {
                    $group.Master.DriveLetter = $matchedDrive.DriveLetter
                    Write-Verbose "Matched Master for Group $groupKey : $($group.Master.Label) -> $($matchedDrive.DriveLetter)"
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
                            Write-Verbose "Matched Backup.$backupKey for Group $groupKey : $($backup.Label) -> $($matchedDrive.DriveLetter)"
                        }
                    }
                }
            }

            # Now update status for this group (which will populate size/availability info)
            $group.UpdateStatus()
        }

        return $this
    }

    [AppConfiguration] Build() {
        $this.EnsureNotBuilt()

        # Validate required properties
        if ($null -eq $this._config.Paths) {
            throw "Root path must be set before building"
        }

        if ($null -eq $this._config.Parameters) {
            throw "Runtime parameters must be set before building"
        }

        # Ensure initialization is complete
        $this._config.Initialize()

        # Mark as built to prevent further modifications
        $this._built = $true

        return $this._config
    }

    hidden [void] EnsureNotBuilt() {
        if ($this._built) {
            throw "Configuration has already been built and cannot be modified"
        }
    }

    [AppConfiguration] GetConfig() {
        return $this._config
    }
}

#endregion Builder Classes
