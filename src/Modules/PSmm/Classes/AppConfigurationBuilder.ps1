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
using namespace System.Collections.Generic

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
            throw [ValidationException]::new("Root path cannot be null or empty", "rootPath")
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
            $testModeReason = ""

            # Signal 1: Check explicit environment variable (most reliable)
            if ($env:MEDIA_MANAGER_TEST_MODE -eq '1') {
                $testModeReason = "MEDIA_MANAGER_TEST_MODE=1"
                $isTestMode = $true
            }

            # Signal 2: Check if called from Pester by examining call stack
            if (-not $isTestMode) {
                try {
                    $callStack = Get-PSCallStack
                    $isPesterContext = $callStack | Where-Object {
                        $_.Command -match 'Invoke-Pester|Should|It|Describe|Context|BeforeAll|AfterAll|Invoke-ScriptBlock' -or
                        $_.ScriptName -match '\.Tests\.ps1$|Invoke-Pester\.ps1$'
                    }
                    if ($isPesterContext) {
                        $testModeReason = "Pester in call stack"
                        $isTestMode = $true
                    }
                } catch {
                    # Ignore errors in call stack inspection
                    Write-Verbose "Unable to inspect call stack: $_"
                }
            }

            # Signal 3: Check for Pester module or preference variable
            if (-not $isTestMode) {
                $pesterLoaded = Get-Module -Name Pester -ErrorAction SilentlyContinue
                $pesterPref = Get-Variable -Name 'PesterPreference' -Scope Global -ErrorAction SilentlyContinue
                if ($pesterLoaded -or $pesterPref) {
                    $testModeReason = "Pester module loaded or PesterPreference exists"
                    $isTestMode = $true
                }
            }

            if ($isTestMode) {
                Write-Verbose "[AppConfigurationBuilder] Test mode DETECTED ($testModeReason)"
            } else {
                Write-Verbose "[AppConfigurationBuilder] Production mode (no test signals detected)"
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
                $testRoot = [System.IO.Path]::Combine($tempPath, 'PSmediaManager', 'Tests')
                Write-Verbose "[AppConfigurationBuilder] Using test runtime root: $testRoot"
                $testRoot
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
                    $fallbackRoot = [System.IO.Path]::Combine($tempPath, 'PSmediaManager', 'Runtime')
                    Write-Verbose "[AppConfigurationBuilder] Using fallback runtime root: $fallbackRoot"
                    $fallbackRoot
                } else {
                    Write-Verbose "[AppConfigurationBuilder] Using production runtime root: $driveRoot"
                    $driveRoot
                }
            }
            $paths = [AppPaths]::new($resolvedPath, $runtimeRoot)
        }
        else {
            # NOT a repository root, but still need to check if we're in test mode
            # to determine where runtime folders should go
            $isTestMode = $false
            $testModeReason = ""

            # Signal 1: Check explicit environment variable (most reliable)
            if ($env:MEDIA_MANAGER_TEST_MODE -eq '1') {
                $testModeReason = "MEDIA_MANAGER_TEST_MODE=1"
                $isTestMode = $true
            }

            # Signal 2: Check if called from Pester by examining call stack
            if (-not $isTestMode) {
                try {
                    $callStack = Get-PSCallStack
                    $isPesterContext = $callStack | Where-Object {
                        $_.Command -match 'Invoke-Pester|Should|It|Describe|Context|BeforeAll|AfterAll|Invoke-ScriptBlock' -or
                        $_.ScriptName -match '\.Tests\.ps1$|Invoke-Pester\.ps1$'
                    }
                    if ($isPesterContext) {
                        $testModeReason = "Pester in call stack"
                        $isTestMode = $true
                    }
                } catch {
                    # Ignore errors in call stack inspection
                    Write-Verbose "Unable to inspect call stack: $_"
                }
            }

            # Signal 3: Check for Pester module or preference variable
            if (-not $isTestMode) {
                $pesterLoaded = Get-Module -Name Pester -ErrorAction SilentlyContinue
                $pesterPref = Get-Variable -Name 'PesterPreference' -Scope Global -ErrorAction SilentlyContinue
                if ($pesterLoaded -or $pesterPref) {
                    $testModeReason = "Pester module loaded or PesterPreference exists"
                    $isTestMode = $true
                }
            }

            if ($isTestMode) {
                Write-Verbose "[AppConfigurationBuilder] Test mode DETECTED in non-repo path ($testModeReason)"
                # For test paths, always use TEMP regardless of the passed path
                $tempPath = [Environment]::GetEnvironmentVariable('TEMP', [EnvironmentVariableTarget]::User)
                if ([string]::IsNullOrWhiteSpace($tempPath)) {
                    $tempPath = [Environment]::GetEnvironmentVariable('TEMP', [EnvironmentVariableTarget]::Process)
                }
                if ([string]::IsNullOrWhiteSpace($tempPath)) {
                    $tempPath = [System.IO.Path]::GetTempPath()
                }
                $testRoot = [System.IO.Path]::Combine($tempPath, 'PSmediaManager', 'Tests')
                Write-Verbose "[AppConfigurationBuilder] Overriding test path to TEMP: $testRoot"
                $paths = [AppPaths]::new($resolvedPath, $testRoot)
            } else {
                Write-Verbose "[AppConfigurationBuilder] Non-repository path, production mode detected"
                $paths = [AppPaths]::new($resolvedPath)
            }
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

        if (-not (Test-Path -Path $configPath -PathType Leaf)) {
            throw [ConfigurationException]::new("Configuration file not found: $configPath", $configPath)
        }

        try {
            $configData = Import-PowerShellDataFile -Path $configPath

            $getMember = {
                param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)

                if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
                    return $null
                }

                if ($Object -is [System.Collections.IDictionary]) {
                    $hasKey = $false
                    try { $hasKey = [bool]$Object.ContainsKey($Name) } catch { $hasKey = $false }
                    if (-not $hasKey) { try { $hasKey = [bool]$Object.Contains($Name) } catch { $hasKey = $false } }
                    if (-not $hasKey) {
                        try {
                            foreach ($k in $Object.Keys) {
                                if ($k -eq $Name) { $hasKey = $true; break }
                            }
                        }
                        catch { $hasKey = $false }
                    }
                    if ($hasKey) { return $Object[$Name] }
                    return $null
                }

                try {
                    $p = $Object.PSObject.Properties[$Name]
                    if ($null -ne $p) { return $p.Value }
                }
                catch { }

                return $null
            }

            # Merge configuration data
            $appData = & $getMember $configData 'App'
            if ($null -ne $appData) {
                $storageRoot = & $getMember $appData 'Storage'
                if ($storageRoot -is [System.Collections.IDictionary]) {
                    foreach ($key in $storageRoot.Keys) {
                        $storageData = $storageRoot[$key]
                        $this._config.Storage[[string]$key] = [StorageGroupConfig]::FromObject([string]$key, $storageData)
                    }
                }

                $uiRoot = & $getMember $appData 'UI'
                if ($null -ne $uiRoot) {
                    $this._config.UI = [UIConfig]::FromObject($uiRoot)
                }

                $loggingRoot = & $getMember $appData 'Logging'
                if ($null -ne $loggingRoot) {
                    $existingLogPath = $null
                    if ($null -ne $this._config.Logging) { $existingLogPath = $this._config.Logging.Path }

                    $this._config.Logging = [LoggingConfiguration]::FromObject($loggingRoot)
                    if ([string]::IsNullOrWhiteSpace($this._config.Logging.Path) -and -not [string]::IsNullOrWhiteSpace($existingLogPath)) {
                        $this._config.Logging.Path = $existingLogPath
                    }
                }
            }

            $projectsRoot = & $getMember $configData 'Projects'
            if ($null -ne $projectsRoot) {
                $this._config.Projects = [ProjectsConfig]::FromObject($projectsRoot)
            }
        }
        catch {
                throw [ConfigurationException]::new("Failed to load configuration file '$configPath': $_", $configPath, $_.Exception)
        }

        return $this
    }

    [AppConfigurationBuilder] LoadRequirementsFile([string]$requirementsPath) {
        $this.EnsureNotBuilt()

        if (-not (Test-Path -Path $requirementsPath)) {
            throw [ConfigurationException]::new("Requirements file not found: $requirementsPath", $requirementsPath)
        }

        try {
                $requirementsContent = Import-PowerShellDataFile -Path $requirementsPath -ErrorAction Stop
        }
        catch {
            throw [ConfigurationException]::new("Failed to load requirements file '$requirementsPath': $_", $requirementsPath, $_.Exception)
        }

            # Store the loaded requirements in the configuration (typed normalization)
            $this._config.Requirements = [RequirementsConfig]::FromObject($requirementsContent)

            return $this
    }

    [AppConfigurationBuilder] LoadPluginsFile([string]$pluginsPath, [string]$scope = 'Global') {
        $this.EnsureNotBuilt()

        if (-not (Test-Path -Path $pluginsPath)) {
            throw [ConfigurationException]::new("Plugins file not found: $pluginsPath", $pluginsPath)
        }

        try {
            $pluginsContent = Import-PowerShellDataFile -Path $pluginsPath -ErrorAction Stop
        }
        catch {
            throw [ConfigurationException]::new("Failed to load plugins file '$pluginsPath': $_", $pluginsPath, $_.Exception)
        }

        $pluginsRoot = $null
        if ($pluginsContent -is [System.Collections.IDictionary]) {
            $hasPluginsKey = $false
            try { $hasPluginsKey = [bool]$pluginsContent.ContainsKey('Plugins') } catch { $hasPluginsKey = $false }
            if (-not $hasPluginsKey) { try { $hasPluginsKey = [bool]$pluginsContent.Contains('Plugins') } catch { $hasPluginsKey = $false } }
            if (-not $hasPluginsKey) {
                try {
                    foreach ($k in $pluginsContent.Keys) {
                        if ($k -eq 'Plugins') { $hasPluginsKey = $true; break }
                    }
                }
                catch {
                    $hasPluginsKey = $false
                }
            }
            if ($hasPluginsKey) { $pluginsRoot = $pluginsContent['Plugins'] }
        }
        elseif ($null -ne $pluginsContent) {
            try {
                $p = $pluginsContent.PSObject.Properties['Plugins']
                if ($null -ne $p) { $pluginsRoot = $p.Value }
            }
            catch { }
        }

        if ($null -eq $pluginsRoot) {
            throw [ConfigurationException]::new("Plugins file is invalid. Expected an IDictionary/hashtable with 'Plugins' root.", $pluginsPath)
        }

        $this._config.Plugins = [PluginsConfig]::FromObject($this._config.Plugins)

        $normalizedScope = if ([string]::IsNullOrWhiteSpace($scope)) { 'Global' } else { $scope }

        switch -Regex ($normalizedScope) {
            '^Project$' {
                $this._config.Plugins.Project = $pluginsRoot
                $this._config.Plugins.Paths.Project = $pluginsPath
            }
            default {
                $this._config.Plugins.Global = $pluginsRoot
                $this._config.Plugins.Paths.Global = $pluginsPath
            }
        }

        # Reset resolved cache to force re-merge on next confirmation
        $this._config.Plugins.Resolved = $null

        return $this
    }

    [AppConfigurationBuilder] LoadStorageFile([string]$storagePath) {
        $this.EnsureNotBuilt()

        if (-not (Test-Path -Path $storagePath)) {
            Write-Verbose "Storage file not found: $storagePath"
            return $this
        }

        try {
            # Storage definitions are PowerShell data files (PSD1), not JSON
            $storageContent = Import-PowerShellDataFile -Path $storagePath -ErrorAction Stop
        }
        catch {
            throw [ConfigurationException]::new("Failed to load storage file '$storagePath': $_", $storagePath, $_.Exception)
        }

        # Expect shape: @{ Storage = @{ '1' = @{ ... }; '2' = @{ ... } } }
        $storageRoot = $null
        if ($storageContent -is [System.Collections.IDictionary]) {
            $hasKey = $false
            try { $hasKey = $storageContent.ContainsKey('Storage') } catch { $hasKey = $false }
            if (-not $hasKey) { try { $hasKey = $storageContent.Contains('Storage') } catch { $hasKey = $false } }
            if (-not $hasKey) {
                try {
                    foreach ($k in $storageContent.Keys) {
                        if ($k -eq 'Storage') { $hasKey = $true; break }
                    }
                }
                catch { }
            }
            if ($hasKey) {
                $storageRoot = $storageContent['Storage']
            }
        }
        else {
            $prop = $storageContent.PSObject.Properties['Storage']
            if ($null -ne $prop) {
                $storageRoot = $prop.Value
            }
        }

        $storageMap = $null
        if ($storageRoot -is [System.Collections.IDictionary]) {
            $storageMap = $storageRoot
        }
        elseif ($null -ne $storageRoot -and $null -ne $storageRoot.PSObject -and $storageRoot.PSObject.Properties.Count -gt 0) {
            $storageMap = @{}
            foreach ($p in $storageRoot.PSObject.Properties) {
                $storageMap[$p.Name] = $p.Value
            }
        }

        if ($null -eq $storageMap) {
            throw [ConfigurationException]::new("Storage file is invalid. Expected a hashtable/object with a 'Storage' root table.", $storagePath)
        }

        foreach ($groupKey in $storageMap.Keys) {
            $groupTable = $storageMap[$groupKey]
            $this._config.Storage[[string]$groupKey] = [StorageGroupConfig]::FromObject([string]$groupKey, $groupTable)
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
            throw [ValidationException]::new("Root path must be set before building", "Paths")
        }

        if ($null -eq $this._config.Parameters) {
            throw [ValidationException]::new("Runtime parameters must be set before building", "Parameters")
        }

        # Ensure initialization is complete
        $this._config.Initialize()

        # Normalize Parameters bag (supports legacy hashtable/PSCustomObject shapes)
        $this._config.Parameters = [RuntimeParameters]::FromObject($this._config.Parameters)

        # Normalize Requirements bag (supports legacy hashtable shapes)
        $this._config.Requirements = [RequirementsConfig]::FromObject($this._config.Requirements)

        # Normalize UI bag (supports legacy hashtable shapes)
        $this._config.UI = [UIConfig]::FromObject($this._config.UI)

        # Normalize InternalErrorMessages to the typed catalog (supports legacy hashtable shapes)
        $this._config.InternalErrorMessages = [UiErrorCatalog]::FromObject($this._config.InternalErrorMessages)

        # Normalize Projects bag (supports missing Projects and legacy Current hashtable)
        $this._config.Projects = [ProjectsConfig]::FromObject($this._config.Projects)

        # Normalize Plugins bag (supports legacy hashtable shape)
        $this._config.Plugins = [PluginsConfig]::FromObject($this._config.Plugins)

        # Normalize Storage groups (supports legacy hashtable/object shapes)
        if ($null -eq $this._config.Storage) {
            $this._config.Storage = [Dictionary[string, StorageGroupConfig]]::new()
        }
        else {
            $normalizedStorage = [Dictionary[string, StorageGroupConfig]]::new()
            if ($this._config.Storage -is [System.Collections.IDictionary]) {
                foreach ($k in $this._config.Storage.Keys) {
                    $key = [string]$k
                    $normalizedStorage[$key] = [StorageGroupConfig]::FromObject($key, $this._config.Storage[$k])
                }
            }
            else {
                foreach ($k in $this._config.Storage.Keys) {
                    $key = [string]$k
                    $normalizedStorage[$key] = [StorageGroupConfig]::FromObject($key, $this._config.Storage[$k])
                }
            }
            $this._config.Storage = $normalizedStorage
        }

        # Fail-fast validation (strict: warnings are fatal)
        $validator = if ($null -ne $this._fileSystem) { [ConfigValidator]::new($this._fileSystem) } else { [ConfigValidator]::new() }
        $issues = $validator.ValidateConfiguration($this._config)
        if ($null -ne $issues -and $issues.Count -gt 0) {
            throw [ConfigValidationException]::new('Configuration validation failed', $issues)
        }

        # Mark as built to prevent further modifications
        $this._built = $true

        return $this._config
    }

    hidden [void] EnsureNotBuilt() {
        if ($this._built) {
            throw [ValidationException]::new("Configuration has already been built and cannot be modified", "_built")
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

            $storageRoot = $null
            if ($storageData -is [System.Collections.IDictionary]) {
                $hasStorage = $false
                try { $hasStorage = [bool]$storageData.ContainsKey('Storage') } catch { $hasStorage = $false }
                if (-not $hasStorage) { try { $hasStorage = [bool]$storageData.Contains('Storage') } catch { $hasStorage = $false } }
                if (-not $hasStorage) {
                    try {
                        foreach ($k in $storageData.Keys) {
                            if ($k -eq 'Storage') { $hasStorage = $true; break }
                        }
                    }
                    catch {
                        $hasStorage = $false
                    }
                }
                if ($hasStorage) { $storageRoot = $storageData['Storage'] }
            }
            elseif ($null -ne $storageData) {
                try {
                    $p = $storageData.PSObject.Properties['Storage']
                    if ($null -ne $p) { $storageRoot = $p.Value }
                }
                catch { }
            }

            if ($null -eq $storageRoot) {
                Write-Warning "Storage file is invalid. Expected an IDictionary/hashtable with 'Storage' root."
                return $null
            }

            if ($storageRoot -is [hashtable]) {
                return $storageRoot
            }

            if ($storageRoot -is [System.Collections.IDictionary]) {
                $fixed = @{}
                foreach ($k in $storageRoot.Keys) {
                    $fixed[[string]$k] = $storageRoot[$k]
                }
                return $fixed
            }

            Write-Warning "Storage file is invalid. Storage root is not a map type. Type: $($storageRoot.GetType().FullName)"
            return $null
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

        $mapHasKey = {
            param([AllowNull()][object]$Map, [Parameter(Mandatory)][string]$Key)

            if ($null -eq $Map -or $Map -isnot [System.Collections.IDictionary]) {
                return $false
            }

            $hasKey = $false
            try { $hasKey = [bool]$Map.ContainsKey($Key) } catch { $hasKey = $false }
            if (-not $hasKey) { try { $hasKey = [bool]$Map.Contains($Key) } catch { $hasKey = $false } }
            if (-not $hasKey) {
                try {
                    foreach ($k in $Map.Keys) {
                        if ($k -eq $Key) { $hasKey = $true; break }
                    }
                }
                catch { $hasKey = $false }
            }

            return $hasKey
        }

        $getMember = {
            param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)

            if ($null -eq $Object) { return $null }

            if ($Object -is [System.Collections.IDictionary]) {
                if (& $mapHasKey $Object $Name) {
                    return $Object[$Name]
                }
                return $null
            }

            try {
                $p = $Object.PSObject.Properties[$Name]
                if ($null -ne $p) { return $p.Value }
            }
            catch { }

            return $null
        }

        if ($storageHashtable.Count -eq 0) {
            $lines += '    }'
        }
        else {
            foreach ($groupId in ($storageHashtable.Keys | Sort-Object {[int]$_})) {
                $group = $storageHashtable[$groupId]
                $displayNameValue = & $getMember $group 'DisplayName'
                $displayName = if ($null -ne $displayNameValue) { [string]$displayNameValue } else { "Storage Group $groupId" }
                # Escape single quotes in display name
                $displayName = $displayName -replace "'", "''"

                $lines += "        '$groupId' = @{"
                $lines += "            DisplayName = '$displayName'"

                $master = & $getMember $group 'Master'
                if ($null -ne $master) {
                    $mLabelValue = & $getMember $master 'Label'
                    $mSerialValue = & $getMember $master 'SerialNumber'
                    $mLabel = if ($null -ne $mLabelValue) { ([string]$mLabelValue) -replace "'", "''" } else { '' }
                    $mSerial = if ($null -ne $mSerialValue) { ([string]$mSerialValue) -replace "'", "''" } else { '' }
                    $lines += "            Master      = @{ Label = '$mLabel'; SerialNumber = '$mSerial' }"
                }

                $backup = & $getMember $group 'Backup'
                $backupMap = $null
                if ($backup -is [System.Collections.IDictionary]) {
                    $backupMap = $backup
                }
                elseif ($null -ne $backup -and $null -ne $backup.PSObject -and $backup.PSObject.Properties.Count -gt 0) {
                    $backupMap = @{}
                    foreach ($p in $backup.PSObject.Properties) {
                        $backupMap[$p.Name] = $p.Value
                    }
                }

                if ($null -ne $backupMap -and $backupMap.Count -gt 0) {
                    $lines += '            Backup      = @{'
                    foreach ($bKey in ($backupMap.Keys | Sort-Object {[int]$_})) {
                        $b = $backupMap[$bKey]
                        $bLabelValue = & $getMember $b 'Label'
                        $bSerialValue = & $getMember $b 'SerialNumber'
                        $bLabel = if ($null -ne $bLabelValue) { ([string]$bLabelValue) -replace "'", "''" } else { '' }
                        $bSerial = if ($null -ne $bSerialValue) { ([string]$bSerialValue) -replace "'", "''" } else { '' }
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
