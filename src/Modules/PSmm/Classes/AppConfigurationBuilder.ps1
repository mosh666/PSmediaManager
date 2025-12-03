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

    # Service dependencies
    hidden [object]$_fileSystem
    hidden [object]$_environment
    hidden [object]$_pathProvider
    hidden [object]$_process

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
            # CRITICAL: Determine where to place runtime folders based on context
            # - During TESTS: Use TEMP environment to avoid polluting any drive
            # - During PRODUCTION: Use drive root where PSmediaManager is located
            
            # NOTE: PowerShell classes are compiled at module load time. After modifying this
            # file, you MUST restart PowerShell/VS Code to pick up changes. The test runner
            # caches class definitions and won't see updates until the session is restarted.
            
            # Detect test mode via multiple signals to ensure robustness
            $isTestMode = $false
            
            # Check explicit environment variable
            if ($env:MEDIA_MANAGER_TEST_MODE -eq '1') {
                $isTestMode = $true
            }
            
            # Check if called from Pester by examining call stack
            if (-not $isTestMode) {
                try {
                    $callStack = Get-PSCallStack
                    $isPesterContext = $callStack | Where-Object {
                        $_.Command -match 'Invoke-Pester|Should|It|Describe|Context|BeforeAll|AfterAll' -or
                        $_.ScriptName -match '\.Tests\.ps1$'
                    }
                    if ($isPesterContext) {
                        $isTestMode = $true
                    }
                } catch {
                    # Ignore errors in call stack inspection
                }
            }
            
            # Check for Pester module or preference variable
            if (-not $isTestMode) {
                $pesterLoaded = Get-Module -Name Pester -ErrorAction SilentlyContinue
                $pesterPref = Get-Variable -Name 'PesterPreference' -Scope Global -ErrorAction SilentlyContinue
                if ($pesterLoaded -or $pesterPref) {
                    $isTestMode = $true
                }
            }
            
            $runtimeRoot = if ($isTestMode) {
                # Test mode: Use TEMP environment to avoid creating folders on any real drive
                $tempPath = [Environment]::GetEnvironmentVariable('TEMP', [EnvironmentVariableTarget]::User)
                if ([string]::IsNullOrWhiteSpace($tempPath)) {
                    $tempPath = [Environment]::GetEnvironmentVariable('TEMP', [EnvironmentVariableTarget]::Process)
                }
                if ([string]::IsNullOrWhiteSpace($tempPath)) {
                    $tempPath = [System.IO.Path]::GetTempPath()
                }
                [System.IO.Path]::Combine($tempPath, 'PSmediaManager', 'Tests')
            } else {
                # Production mode: Use drive root where PSmediaManager repository is located
                # e.g., if repo is at D:\PSmediaManager, folders go to D:\PSmm.Log, D:\PSmm.Plugins, etc.
                # CRITICAL: NEVER use C:\ as runtime root - always fallback to TEMP if that happens
                $driveRoot = [System.IO.Path]::GetPathRoot($resolvedPath)
                if ([string]::IsNullOrWhiteSpace($driveRoot) -or $driveRoot -ieq 'C:\' -or $driveRoot -ieq 'C:') {
                    # Fallback to TEMP for safety (prevents polluting C:\ system drive)
                    Write-Warning "[AppConfigurationBuilder] Detected C:\ as runtime root - redirecting to TEMP"
                    $tempPath = [Environment]::GetEnvironmentVariable('TEMP', [EnvironmentVariableTarget]::User)
                    if ([string]::IsNullOrWhiteSpace($tempPath)) {
                        $tempPath = [Environment]::GetEnvironmentVariable('TEMP', [EnvironmentVariableTarget]::Process)
                    }
                    if ([string]::IsNullOrWhiteSpace($tempPath)) {
                        $tempPath = [System.IO.Path]::GetTempPath()
                    }
                    [System.IO.Path]::Combine($tempPath, 'PSmediaManager', 'Runtime')
                } else {
                    $driveRoot
                }
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

        # Inject services into Secrets if available
        if ($null -ne $this._fileSystem) {
            $this._config.Secrets.FileSystem = $this._fileSystem
            $this._config.Secrets.Environment = $this._environment
            $this._config.Secrets.PathProvider = $this._pathProvider
            $this._config.Secrets.Process = $this._process
        }

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

    [AppConfigurationBuilder] WithServices([object]$fileSystem, [object]$environment, [object]$pathProvider, [object]$process) {
        $this.EnsureNotBuilt()
        $this._fileSystem = $fileSystem
        $this._environment = $environment
        $this._pathProvider = $pathProvider
        $this._process = $process

        # Inject services into config
        $this._config.FileSystem = $fileSystem
        $this._config.Environment = $environment
        $this._config.PathProvider = $pathProvider
        $this._config.Process = $process

        # Inject services into Secrets if it exists
        if ($null -ne $this._config.Secrets) {
            $this._config.Secrets.FileSystem = $fileSystem
            $this._config.Secrets.Environment = $environment
            $this._config.Secrets.PathProvider = $pathProvider
            $this._config.Secrets.Process = $process
        }

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
                            $masterDrive = ''
                            $masterSerial = if ($storageData.Master.ContainsKey('SerialNumber')) { $storageData.Master.SerialNumber } else { '' }

                            Write-Verbose "Loading Master for Storage.$key : Label=$masterLabel, Serial=$masterSerial"
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
                                    $backupDriveLetter = ''
                                    $backupSerial = if ($backup.ContainsKey('SerialNumber')) { $backup.SerialNumber } else { '' }

                                    Write-Verbose "Loading Backup.$backupKey for Storage.$key : Label=$backupLabel, Serial=$backupSerial"

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

    [AppConfigurationBuilder] LoadStorageFile([string]$storagePath) {
        $this.EnsureNotBuilt()

        if (-not (Test-Path -Path $storagePath)) {
            Write-Verbose "Storage file not found: $storagePath"
            return $this
        }

        try {
            $storageData = Import-PowerShellDataFile -Path $storagePath
        }
        catch {
            throw "Failed to load storage file '$storagePath': $_"
        }

        if (-not ($storageData -is [hashtable]) -or -not $storageData.ContainsKey('Storage')) {
            throw "Storage file is invalid. Expected a hashtable with 'Storage' root."
        }

        foreach ($groupKey in $storageData.Storage.Keys) {
            $groupTable = $storageData.Storage[$groupKey]
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

            $this._config.Storage[[string]$groupKey] = $group
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

        # Ensure services are injected before loading secrets
        if ($null -ne $this._fileSystem) {
            $this._config.Secrets.FileSystem = $this._fileSystem
            $this._config.Secrets.Environment = $this._environment
            $this._config.Secrets.PathProvider = $this._pathProvider
            $this._config.Secrets.Process = $this._process
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

    <#
    .SYNOPSIS
        Reads storage configuration from a PSmm.Storage.psd1 file.

    .DESCRIPTION
        Loads the storage hashtable from the specified .psd1 file.
        Returns $null if the file doesn't exist or is invalid.
    #>
    static [hashtable] ReadStorageFile([string]$storagePath) {
        if (-not (Test-Path -Path $storagePath -PathType Leaf)) {
            return $null
        }

        try {
            $storageData = Import-PowerShellDataFile -Path $storagePath
            if (-not ($storageData -is [hashtable]) -or -not $storageData.ContainsKey('Storage')) {
                Write-Warning "Storage file is invalid. Expected a hashtable with 'Storage' root."
                return $null
            }
            return $storageData.Storage
        }
        catch {
            Write-Warning "Failed to read storage file '$storagePath': $_"
            return $null
        }
    }

    <#
    .SYNOPSIS
        Writes storage configuration to a PSmm.Storage.psd1 file with renumbering.

    .DESCRIPTION
        Renumbers all storage groups sequentially (1, 2, 3...) and writes
        the configuration to the specified path in .psd1 format.
    #>
    static [void] WriteStorageFile([string]$storagePath, [hashtable]$storageHashtable) {
        # Renumber groups sequentially
        $renumbered = @{}
        $numericKeys = @()
        foreach ($k in $storageHashtable.Keys) {
            if ($k -match '^[0-9]+$') {
                $numericKeys += [int]$k
            }
        }
        $sorted = $numericKeys | Sort-Object
        $newId = 1
        foreach ($oldId in $sorted) {
            $renumbered[[string]$newId] = $storageHashtable[[string]$oldId]
            $newId++
        }

        # Convert to .psd1 format
        $psd1Content = [AppConfigurationBuilder]::ConvertStorageToPsd1($renumbered)

        # Ensure directory exists via FileSystem service
        $configRoot = Split-Path -Path $storagePath -Parent
        $fs = [FileSystemService]::new()
        if (-not $fs.TestPath($configRoot)) {
            $null = $fs.NewItem($configRoot, 'Directory')
        }

        # Write to file via FileSystem service
        $fs.SetContent($storagePath, $psd1Content)
    }

    <#
    .SYNOPSIS
        Converts a storage hashtable to .psd1 format string.

    .DESCRIPTION
        Serializes the storage groups hashtable to PowerShell Data File format
        with proper indentation and escaping.
    #>
    static [string] ConvertStorageToPsd1([hashtable]$storageHashtable) {
        $lines = @()
        $lines += '@{'
        $lines += '    Storage = @{'

        if ($storageHashtable.Count -eq 0) {
            $lines += '    }'
        }
        else {
            foreach ($groupId in ($storageHashtable.Keys | Sort-Object {[int]$_})) {
                $group = $storageHashtable[$groupId]
                $displayName = if ($group.ContainsKey('DisplayName')) { $group.DisplayName } else { "Storage Group $groupId" }
                # Escape single quotes in display name
                $displayName = $displayName -replace "'", "''"

                $lines += "        '$groupId' = @{"
                $lines += "            DisplayName = '$displayName'"

                if ($group.ContainsKey('Master') -and $group.Master) {
                    $mLabel = if ($group.Master.ContainsKey('Label')) { $group.Master.Label -replace "'", "''" } else { '' }
                    $mSerial = if ($group.Master.ContainsKey('SerialNumber')) { $group.Master.SerialNumber -replace "'", "''" } else { '' }
                    $lines += "            Master      = @{ Label = '$mLabel'; SerialNumber = '$mSerial' }"
                }

                if ($group.ContainsKey('Backup') -and $group.Backup -and $group.Backup.Count -gt 0) {
                    $lines += '            Backup      = @{'
                    foreach ($bKey in ($group.Backup.Keys | Sort-Object {[int]$_})) {
                        $b = $group.Backup[$bKey]
                        $bLabel = if ($b.ContainsKey('Label')) { $b.Label -replace "'", "''" } else { '' }
                        $bSerial = if ($b.ContainsKey('SerialNumber')) { $b.SerialNumber -replace "'", "''" } else { '' }
                        $lines += "                '$bKey' = @{ Label = '$bLabel'; SerialNumber = '$bSerial' }"
                    }
                    $lines += '            }'
                }
                else {
                    $lines += '            Backup      = @{}'
                }

                $lines += '        }'
            }
            $lines += '    }'
        }

        $lines += '}'
        return ($lines -join [Environment]::NewLine)
    }
}

#endregion Builder Classes
