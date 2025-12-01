<#
.SYNOPSIS
    Type-safe classes for PSmediaManager application configuration.

.DESCRIPTION
    Provides strongly-typed classes to replace the loosely-typed hashtable approach.
    Implements modern design patterns including:
    - Interface segregation for testability
    - Validation at all levels
    - Immutability where appropriate
    - IntelliSense support
    - Type safety and compile-time checks
    - Proper encapsulation with private fields
    - Comprehensive error handling

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.1.0
#>

using namespace System
using namespace System.IO
using namespace System.Collections.Generic
using namespace System.ComponentModel
using namespace System.Security

#region Base Configuration Classes

<#
.SYNOPSIS
    Represents application paths configuration with validation and path management.

.DESCRIPTION
    Provides structured path management with:
    - Automatic validation
    - Directory creation
    - Path resolution
    - Access control verification
#>
class AppPaths : IPathProvider {
    [ValidateNotNullOrEmpty()]
    [string]$Root

    [ValidateNotNullOrEmpty()]
    [string]$RepositoryRoot

    [ValidateNotNullOrEmpty()]
    [string]$Log

    [ValidateNotNull()]
    [AppSubPaths]$App

    AppPaths() {
        $this.App = [AppSubPaths]::new()
    }

    AppPaths([string]$rootPath) {
        $this.InitializePaths($null, $rootPath)
    }

    AppPaths([string]$repositoryRoot, [string]$runtimeRoot) {
        $this.InitializePaths($repositoryRoot, $runtimeRoot)
    }

    hidden [void] InitializePaths([string]$repositoryRootPath, [string]$runtimeRootPath) {
        if ([string]::IsNullOrWhiteSpace($runtimeRootPath)) {
            throw [ValidationException]::new("Runtime root path cannot be null or empty", "RuntimeRoot", $runtimeRootPath)
        }

        if (-not [Path]::IsPathRooted($runtimeRootPath)) {
            throw [ValidationException]::new("Runtime root path must be absolute", "RuntimeRoot", $runtimeRootPath)
        }

        $resolvedRuntimeRoot = [Path]::GetFullPath($runtimeRootPath)

        if ([string]::IsNullOrWhiteSpace($repositoryRootPath)) {
            $repositoryCandidate = Join-Path -Path $resolvedRuntimeRoot -ChildPath 'PSmediaManager'
            if (Test-Path -Path $repositoryCandidate -PathType Container) {
                $repositoryRootPath = $repositoryCandidate
            }
            else {
                $repositoryRootPath = $resolvedRuntimeRoot
            }
        }

        if (-not [Path]::IsPathRooted($repositoryRootPath)) {
            throw [ValidationException]::new("Repository root path must be absolute", "RepositoryRoot", $repositoryRootPath)
        }

        $resolvedRepositoryRoot = [Path]::GetFullPath($repositoryRootPath)

        if (-not (Test-Path -Path $resolvedRepositoryRoot -PathType Container)) {
            Write-Warning "Repository root not found at: $resolvedRepositoryRoot"
            Write-Warning "Path calculations may be invalid. Verify installation layout."
        }

        # Enforce runtime directories in the drive root, not the repository root
        # Compute the drive root based on the provided runtime root path
        $driveRoot = [Path]::GetPathRoot($resolvedRuntimeRoot)

        $this.Root = $driveRoot
        $this.RepositoryRoot = $resolvedRepositoryRoot

        # Validate that .git exists in repository root when available
        $gitPath = [Path]::Combine($this.RepositoryRoot, '.git')
        $repoExists = Test-Path -Path $this.RepositoryRoot -PathType Container
        if ($repoExists -and -not (Test-Path -Path $gitPath)) {
            Write-Warning "Git directory not found at expected location: $gitPath"
            Write-Warning "Git-based features may not work correctly."
        }

        $this.Log = [Path]::Combine($this.Root, 'PSmm.Log')
        $srcRoot = [Path]::Combine($this.RepositoryRoot, 'src')
        $this.App = [AppSubPaths]::new($srcRoot, $this.Root)
    }

    [void] EnsureDirectoriesExist() {
        $paths = @(
            $this.Root,
            $this.Log,
            $this.App.Root,
            $this.App.Config,
            $this.App.ConfigDigiKam,
            $this.App.Modules,
            $this.App.Plugins.Root,
            $this.App.Plugins.Downloads,
            $this.App.Plugins.Temp,
            $this.App.Vault
        )

        foreach ($path in $paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
            if (-not ([FileSystemService]::new().TestPath($path))) {
                try {
                    $null = ([FileSystemService]::new()).NewItem($path, 'Directory')
                }
                catch {
                    throw [StorageException]::new("Failed to create directory: $path", $path)
                }
            }
        }
    }

    # IPathProvider implementation
    [string] GetPath([string]$pathKey) {
        $result = switch ($pathKey) {
            'Root' { $this.Root }
            'Log' { $this.Log }
            'App' { $this.App.Root }
            'Config' { $this.App.Config }
            'Modules' { $this.App.Modules }
            'Plugins' { $this.App.Plugins.Root }
            'Vault' { $this.App.Vault }
            default {
                throw [ValidationException]::new("Unknown path key: $pathKey", "PathKey", $pathKey)
            }
        }
        return $result
    }

    [bool] EnsurePathExists([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $false
        }

        if (-not (Test-Path -Path $path)) {
            try {
                $null = New-Item -Path $path -ItemType Directory -Force -ErrorAction Stop
                return $true
            }
            catch {
                return $false
            }
        }

        return $true
    }

    [string] CombinePath([string[]]$paths) {
        if ($null -eq $paths -or $paths.Count -eq 0) {
            throw [ValidationException]::new("Path array cannot be null or empty", "Paths", $null)
        }

        return [Path]::Combine($paths)
    }

    [bool] Validate() {
        try {
            # Validate root exists and is writable
            if (-not (Test-Path -Path $this.Root)) {
                return $false
            }

            # Test write access
            $testFile = [Path]::Combine($this.Root, ".write_test_$(Get-Random)")
            try {
                $fs = [FileSystemService]::new()
                [void]($fs.NewItem($testFile, 'File'))
                $fs.RemoveItem($testFile)
                return $true
            }
            catch {
                return $false
            }
        }
        catch {
            return $false
        }
    }
}

<#
.SYNOPSIS
    Represents application sub-directory paths.
#>
class AppSubPaths {
    [string]$Root
    [string]$Config
    [string]$ConfigDigiKam
    [string]$Modules
    [PluginsPaths]$Plugins
    [string]$Vault

    AppSubPaths() {
        $this.Plugins = [PluginsPaths]::new()
    }

    AppSubPaths([string]$rootPath) {
        $this.Plugins = [PluginsPaths]::new()
    }

    AppSubPaths([string]$rootPath, [string]$runtimeRoot) {
        # rootPath points to src/ directory containing Modules/ and Config/
        # runtimeRoot points to drive root where runtime folders live (PSmm.Log, PSmm.Plugins, PSmm.Vault)
        $this.Root = $rootPath
        $this.Config = [Path]::Combine($rootPath, 'Config', 'PSmm')
        $this.ConfigDigiKam = [Path]::Combine($rootPath, 'Config', 'digiKam')
        $this.Modules = [Path]::Combine($rootPath, 'Modules')
        $this.Plugins = [PluginsPaths]::new($runtimeRoot)
        $this.Vault = [Path]::Combine($runtimeRoot, 'PSmm.Vault')
    }
}

<#
.SYNOPSIS
    Represents plugins directory paths.
#>
class PluginsPaths {
    [string]$Root
    [string]$Downloads
    [string]$Temp

    PluginsPaths() {}

    PluginsPaths([string]$appRoot) {
        # appRoot is the drive root; place plugins under PSmm.Plugins there
        $this.Root = [Path]::Combine($appRoot, 'PSmm.Plugins')
        $this.Downloads = [Path]::Combine($this.Root, '_Downloads')
        $this.Temp = [Path]::Combine($this.Root, '_Temp')
    }
}

<#
.SYNOPSIS
    Represents application secrets configuration.

.DESCRIPTION
    Manages system secrets using KeePassXC as the exclusive storage mechanism.
    All secrets must be stored in the KeePass database using Initialize-SystemVault
    and Save-SystemSecret functions.
#>
class AppSecrets {
    [SecureString]$GitHubToken
    [string]$VaultPath

    # Service dependencies
    hidden [object]$FileSystem
    hidden [object]$Environment
    hidden [object]$PathProvider
    hidden [object]$Process

    AppSecrets() {}

    AppSecrets([string]$vaultPath) {
        if ($vaultPath) { $this.VaultPath = $vaultPath }
        elseif ($env:PSMM_VAULT_PATH) { $this.VaultPath = $env:PSMM_VAULT_PATH }
        elseif (Get-Command -Name Get-AppConfiguration -ErrorAction SilentlyContinue) {
                try {
                    $this.VaultPath = (Get-AppConfiguration).Paths.App.Vault
                }
                catch {
                    Write-Verbose "Could not retrieve vault path from app configuration: $_"
                }
        }
    }

    [void] LoadSecrets() {
        try {
            # Use Get-SystemSecret to load from KeePassXC
            if (Get-Command Get-SystemSecret -ErrorAction SilentlyContinue) {
                Write-Verbose "Loading GitHub credential from KeePassXC vault (optional)"
                # Retrieve token as optional: absence should not raise an ERROR log or throw
                if ($null -ne $this.FileSystem -and $null -ne $this.Environment -and $null -ne $this.PathProvider -and $null -ne $this.Process) {
                    $this.GitHubToken = Get-SystemSecret -SecretType 'GitHub-Token' -VaultPath $this.VaultPath -FileSystem $this.FileSystem -Environment $this.Environment -PathProvider $this.PathProvider -Process $this.Process -Optional -ErrorAction SilentlyContinue
                }
                else {
                    Write-Verbose "Services not injected; skipping secret loading"
                    return
                }
                if ($this.GitHubToken) {
                    Write-Verbose "GitHub credential loaded successfully from KeePassXC"
                }
                else {
                    Write-Verbose "No GitHub credential found; continuing without token (rate-limited operations may occur)."
                }
            }
            else {
                Write-Warning "Get-SystemSecret not available. Ensure PSmm module is properly loaded."
            }
        }
        catch {
            Write-Warning "Failed to load GitHub credential from KeePassXC: $_"
            Write-Warning "Ensure the KeePass database exists and contains the GitHub-Token entry."
            Write-Warning "Use 'Initialize-SystemVault' and 'Save-SystemSecret' to set up secrets."
        }
    }

    [string] GetGitHubToken() {
        if ($null -eq $this.GitHubToken) {
            return $null
        }

        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.GitHubToken)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

<#
.SYNOPSIS
    Represents logging configuration.
#>
class LoggingConfiguration {
    [string]$Path
    [string]$Level = 'INFO'
    [string]$DefaultLevel = 'INFO'
    [string]$Format = '[%{timestamp:+%Y-%m-%d %H:%M:%S}] [%{level}] %{message}'
    [bool]$EnableConsole = $true
    [bool]$EnableFile = $true
    [int]$MaxFileSizeMB = 10
    [int]$MaxLogFiles = 5
    [bool]$PrintBody = $true
    [bool]$Append = $true
    [string]$Encoding = 'utf8'
    [bool]$PrintException = $true
    [bool]$ShortLevel = $false
    [bool]$OnlyColorizeLevel = $false

    LoggingConfiguration() {}

    LoggingConfiguration([string]$logPath) {
        $this.Path = $logPath
    }

    LoggingConfiguration([string]$logPath, [string]$level) {
        $this.Path = $logPath
        $this.Level = $level
        $this.DefaultLevel = $level
    }
}

<#
.SYNOPSIS
    Represents runtime parameters.
#>
class RuntimeParameters {
    [bool]$Debug
    [bool]$Verbose
    [bool]$Dev
    [bool]$Update
    [bool]$NonInteractive

    RuntimeParameters() {}

    RuntimeParameters([hashtable]$boundParameters) {
        $this.Debug = $boundParameters.ContainsKey('Debug')
        $this.Verbose = $boundParameters.ContainsKey('Verbose')
        $this.Dev = $boundParameters.ContainsKey('Dev')
        $this.Update = $boundParameters.ContainsKey('Update')
        $this.NonInteractive = $boundParameters.ContainsKey('NonInteractive')
    }

    [bool] ShouldPause() {
        if ($this.NonInteractive) {
            return $false
        }

        return $this.Debug -or $this.Verbose -or $this.Dev -or $this.Update
    }
}

<#
.SYNOPSIS
    Represents storage drive configuration.
#>
class StorageDriveConfig {
    [string]$Label
    [string]$SerialNumber
    [string]$DriveLetter
    [string]$Path
    [bool]$IsAvailable
    [long]$FreeSpaceGB
    [long]$TotalSpaceGB

    StorageDriveConfig() {}

    StorageDriveConfig([string]$label, [string]$driveLetter) {
        $this.Label = $label
        $this.DriveLetter = $driveLetter
        $this.UpdateStatus()
    }

    [void] UpdateStatus() {
        if ([string]::IsNullOrWhiteSpace($this.DriveLetter)) {
            return
        }

        $inTestMode = [string]::Equals($env:MEDIA_MANAGER_TEST_MODE, '1', [System.StringComparison]::OrdinalIgnoreCase)
        if ($inTestMode) {
            # Skip live drive probing during tests so mocked drives remain available
            $this.IsAvailable = $true
            if ([string]::IsNullOrWhiteSpace($this.Path)) {
                $this.Path = $this.DriveLetter
            }
            return
        }

        $drive = Get-PSDrive -Name $this.DriveLetter.TrimEnd(':') -ErrorAction SilentlyContinue
        if ($drive) {
            $this.IsAvailable = $true
            $this.FreeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
            $this.TotalSpaceGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
            $this.Path = $drive.Root
        }
        else {
            $this.IsAvailable = $false
        }
    }

    [string] ToString() {
        if ($this.IsAvailable) {
            return "$($this.Label) ($($this.DriveLetter)) - $($this.FreeSpaceGB)GB free of $($this.TotalSpaceGB)GB"
        }
        return "$($this.Label) (Not Available)"
    }
}

<#
.SYNOPSIS
    Represents storage group configuration.
#>
class StorageGroupConfig {
    [string]$GroupId
    [string]$DisplayName
    [StorageDriveConfig]$Master
    [Dictionary[string, StorageDriveConfig]]$Backups
    [Dictionary[string, string]]$Paths

    StorageGroupConfig() {
        $this.Backups = [Dictionary[string, StorageDriveConfig]]::new()
        $this.Paths = [Dictionary[string, string]]::new()
    }

    StorageGroupConfig([string]$groupId) {
        $this.GroupId = $groupId
        $this.Backups = [Dictionary[string, StorageDriveConfig]]::new()
        $this.Paths = [Dictionary[string, string]]::new()
    }

    [bool] IsValid() {
        return $null -ne $this.Master -and $this.Master.IsAvailable
    }

    [void] UpdateStatus() {
        if ($null -ne $this.Master) {
            $this.Master.UpdateStatus()
        }
        if ($null -ne $this.Backups) {
            foreach ($backupKey in $this.Backups.Keys) {
                $this.Backups[$backupKey].UpdateStatus()
            }
        }
    }
}

<#
.SYNOPSIS
    Main application configuration class.
#>
class AppConfiguration {
    # Internal identity used in code, modules and paths (short name)
    [string]$InternalName = 'PSmm'
    # User-facing application name shown in UI and messages
    [string]$DisplayName = 'PSmediaManager'
    [version]$Version = '1.0.0'
    [string]$AppVersion  # String to support semantic versioning (e.g., "2.2.0-alpha.262-27f773b")
    [RuntimeParameters]$Parameters
    [AppPaths]$Paths
    [AppSecrets]$Secrets
    [LoggingConfiguration]$Logging
    [Dictionary[string, StorageGroupConfig]]$Storage
    [hashtable]$Requirements
    [hashtable]$UI
    [hashtable]$Projects
    # Internal, structured error tracking persisted with configuration
    [hashtable]$InternalErrorMessages

    # Service dependencies for DI
    hidden [object]$FileSystem
    hidden [object]$Environment
    hidden [object]$PathProvider
    hidden [object]$Process

    AppConfiguration() {
        $this.Parameters = [RuntimeParameters]::new()
        $this.Logging = [LoggingConfiguration]::new()
        $this.Storage = [Dictionary[string, StorageGroupConfig]]::new()
        $this.InternalErrorMessages = @{
            Storage = @{}
        }
    }

    AppConfiguration([string]$rootPath, [RuntimeParameters]$parameters) {
        if ([string]::IsNullOrWhiteSpace($this.InternalName)) {
            $this.InternalName = 'PSmm'
        }
        if ([string]::IsNullOrWhiteSpace($this.DisplayName)) {
            $this.DisplayName = 'PSmediaManager'
        }
        $this.Parameters = $parameters
        $this.Paths = [AppPaths]::new($rootPath)
        $this.Secrets = [AppSecrets]::new($this.Paths.App.Vault)

        # Initialize logging with date-based filename
        $timestamp = Get-Date -Format 'yyyyMMdd'
        $logFileName = "$timestamp-$($this.InternalName)-$env:USERNAME@$env:COMPUTERNAME.log"
        $logPath = [Path]::Combine($this.Paths.Log, $logFileName)
        $this.Logging = [LoggingConfiguration]::new($logPath)

        $this.Storage = [Dictionary[string, StorageGroupConfig]]::new()
        $this.InternalErrorMessages = @{
            Storage = @{}
        }
    }

    [void] Initialize() {
        # Ensure all directories exist
        $this.Paths.EnsureDirectoriesExist()

        # Note: Secrets are loaded separately after logging is initialized
        # to avoid trying to write log messages before the logging system is ready
    }

    [string] GetConfigPath([string]$configName) {
        # Config path already includes 'PSmm' folder from AppSubPaths constructor
        return [Path]::Combine(
            $this.Paths.App.Config,
            "$($this.InternalName).$configName.psd1"
        )
    }

    [string] ToString() {
        return "$($this.DisplayName) v$($this.Version) (App: v$($this.AppVersion))"
    }
}

#endregion Base Configuration Classes
