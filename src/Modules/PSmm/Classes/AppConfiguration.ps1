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

function _PSmm_DictionaryHasKey {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Dictionary,
        [Parameter(Mandatory)][object]$Key
    )

    $hasKey = $false
    try { $hasKey = $Dictionary.ContainsKey($Key) } catch { $hasKey = $false }
    if (-not $hasKey) {
        try { $hasKey = $Dictionary.Contains($Key) } catch { $hasKey = $false }
    }

    if (-not $hasKey) {
        try {
            foreach ($k in $Dictionary.Keys) {
                if ($k -eq $Key) {
                    return $true
                }
            }
        }
        catch {
            Write-Verbose "Dictionary key enumeration failed; treating key '$Key' as missing. $($_.Exception.Message)"
        }
    }
    return $hasKey
}

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

        # CRITICAL: Determine where to place runtime folders based on context
        # - During TESTS: Use TEMP environment (TestDrive) to avoid polluting any drive
        # - During PRODUCTION: Use drive root where PSmediaManager is located (e.g., D:\ for D:\PSmediaManager)

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
                Write-Verbose "Unable to inspect call stack: $_"
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

        if ($isTestMode) {
            # Test mode: Use TEMP environment to avoid creating folders on any real drive
            $tempPath = [Environment]::GetEnvironmentVariable('TEMP', [EnvironmentVariableTarget]::User)
            if ([string]::IsNullOrWhiteSpace($tempPath)) {
                $tempPath = [Environment]::GetEnvironmentVariable('TEMP', [EnvironmentVariableTarget]::Process)
            }
            if ([string]::IsNullOrWhiteSpace($tempPath)) {
                $tempPath = [Path]::GetTempPath()
            }
            # If resolvedRuntimeRoot looks like a TestDrive path, use it directly; otherwise use temp
            if ($resolvedRuntimeRoot -match 'TestDrive') {
                $runtimeStorageRoot = $resolvedRuntimeRoot
            } else {
                $runtimeStorageRoot = [Path]::Combine($tempPath, 'PSmediaManager', 'Tests')
            }
        } else {
            # Production mode: Use drive root where PSmediaManager repository is located
            # e.g., if repo is at D:\PSmediaManager, use D:\ for runtime folders
            # CRITICAL: NEVER use C:\ as runtime root - always fallback to TEMP if that happens
            $driveRoot = [Path]::GetPathRoot($resolvedRuntimeRoot)
            if ([string]::IsNullOrWhiteSpace($driveRoot) -or $driveRoot -ieq 'C:\') {
                # Fallback to TEMP for safety (prevents polluting C:\ system drive)
                $tempPath = [Environment]::GetEnvironmentVariable('TEMP', [EnvironmentVariableTarget]::User)
                if ([string]::IsNullOrWhiteSpace($tempPath)) {
                    $tempPath = [Environment]::GetEnvironmentVariable('TEMP', [EnvironmentVariableTarget]::Process)
                }
                if ([string]::IsNullOrWhiteSpace($tempPath)) {
                    $tempPath = [Path]::GetTempPath()
                }
                $runtimeStorageRoot = [Path]::Combine($tempPath, 'PSmediaManager', 'Runtime')
            } else {
                $runtimeStorageRoot = $driveRoot
            }
        }

        $this.Root = $runtimeStorageRoot
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

    static [LoggingConfiguration] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [LoggingConfiguration]::new()
        }

        if ($obj -is [LoggingConfiguration]) {
            return $obj
        }

        $cfg = [LoggingConfiguration]::new()

        $getValue = {
            param(
                [Parameter(Mandatory)]
                [object]$source,
                [Parameter(Mandatory)]
                [string]$name
            )

            if ($null -eq $source) { return $null }

            if ($source -is [System.Collections.IDictionary]) {
                $hasKey = $false
                try { $hasKey = $source.ContainsKey($name) } catch { $hasKey = $false }
                if (-not $hasKey) { try { $hasKey = $source.Contains($name) } catch { $hasKey = $false } }
                if (-not $hasKey) {
                    try {
                        foreach ($k in $source.Keys) {
                            if ($k -eq $name) {
                                return $source[$k]
                            }
                        }
                    }
                    catch {
                        Write-Verbose "Dictionary key enumeration failed for '$name'. $($_.Exception.Message)"
                    }
                }
                if ($hasKey) { return $source[$name] }
                return $null
            }

            $p = $source.PSObject.Properties[$name]
            if ($null -ne $p) { return $p.Value }

            return $null
        }

        $v = & $getValue $obj 'Path'
        if ($null -ne $v) { $cfg.Path = [string]$v }

        $v = & $getValue $obj 'Level'
        if ($null -ne $v) { $cfg.Level = [string]$v }

        $v = & $getValue $obj 'DefaultLevel'
        if ($null -ne $v) { $cfg.DefaultLevel = [string]$v }

        $v = & $getValue $obj 'Format'
        if ($null -ne $v) { $cfg.Format = [string]$v }

        $v = & $getValue $obj 'EnableConsole'
        if ($null -ne $v) { $cfg.EnableConsole = [bool]$v }

        $v = & $getValue $obj 'EnableFile'
        if ($null -ne $v) { $cfg.EnableFile = [bool]$v }

        $v = & $getValue $obj 'MaxFileSizeMB'
        if ($null -ne $v) { $cfg.MaxFileSizeMB = [int]$v }

        $v = & $getValue $obj 'MaxLogFiles'
        if ($null -ne $v) { $cfg.MaxLogFiles = [int]$v }

        $v = & $getValue $obj 'PrintBody'
        if ($null -ne $v) { $cfg.PrintBody = [bool]$v }

        $v = & $getValue $obj 'Append'
        if ($null -ne $v) { $cfg.Append = [bool]$v }

        $v = & $getValue $obj 'Encoding'
        if ($null -ne $v) { $cfg.Encoding = [string]$v }

        $v = & $getValue $obj 'PrintException'
        if ($null -ne $v) { $cfg.PrintException = [bool]$v }

        $v = & $getValue $obj 'ShortLevel'
        if ($null -ne $v) { $cfg.ShortLevel = [bool]$v }

        $v = & $getValue $obj 'OnlyColorizeLevel'
        if ($null -ne $v) { $cfg.OnlyColorizeLevel = [bool]$v }

        return $cfg
    }

    [hashtable] ToHashtable() {
        return @{
            Path = $this.Path
            Level = $this.Level
            DefaultLevel = $this.DefaultLevel
            Format = $this.Format
            EnableConsole = $this.EnableConsole
            EnableFile = $this.EnableFile
            MaxFileSizeMB = $this.MaxFileSizeMB
            MaxLogFiles = $this.MaxLogFiles
            PrintBody = $this.PrintBody
            Append = $this.Append
            Encoding = $this.Encoding
            PrintException = $this.PrintException
            ShortLevel = $this.ShortLevel
            OnlyColorizeLevel = $this.OnlyColorizeLevel
        }
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
        $this.Debug = ($boundParameters.ContainsKey('Debug') -and [bool]$boundParameters['Debug'])
        $this.Verbose = ($boundParameters.ContainsKey('Verbose') -and [bool]$boundParameters['Verbose'])
        $this.Dev = ($boundParameters.ContainsKey('Dev') -and [bool]$boundParameters['Dev'])
        $this.Update = ($boundParameters.ContainsKey('Update') -and [bool]$boundParameters['Update'])
        $this.NonInteractive = ($boundParameters.ContainsKey('NonInteractive') -and [bool]$boundParameters['NonInteractive'])
    }

    static [RuntimeParameters] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [RuntimeParameters]::new()
        }

        if ($obj -is [RuntimeParameters]) {
            return $obj
        }

        $cfg = [RuntimeParameters]::new()

        $getValue = {
            param(
                [Parameter(Mandatory)]
                [object]$source,
                [Parameter(Mandatory)]
                [string]$name
            )

            if ($null -eq $source) { return $null }

            if ($source -is [System.Collections.IDictionary]) {
                $hasKey = $false
                try { $hasKey = $source.ContainsKey($name) } catch { $hasKey = $false }
                if (-not $hasKey) { try { $hasKey = $source.Contains($name) } catch { $hasKey = $false } }
                if (-not $hasKey) {
                    try {
                        foreach ($k in $source.Keys) {
                            if ($k -eq $name) {
                                return $source[$k]
                            }
                        }
                    }
                    catch {
                        Write-Verbose "Dictionary key enumeration failed for '$name'. $($_.Exception.Message)"
                    }
                }
                if ($hasKey) { return $source[$name] }
                return $null
            }

            $p = $source.PSObject.Properties[$name]
            if ($null -ne $p) { return $p.Value }

            return $null
        }

        $v = & $getValue $obj 'Debug'
        if ($null -ne $v) { $cfg.Debug = [bool]$v }

        $v = & $getValue $obj 'Verbose'
        if ($null -ne $v) { $cfg.Verbose = [bool]$v }

        $v = & $getValue $obj 'Dev'
        if ($null -ne $v) { $cfg.Dev = [bool]$v }

        $v = & $getValue $obj 'Update'
        if ($null -ne $v) { $cfg.Update = [bool]$v }

        $v = & $getValue $obj 'NonInteractive'
        if ($null -ne $v) { $cfg.NonInteractive = [bool]$v }

        return $cfg
    }

    [hashtable] ToHashtable() {
        return @{
            Debug = $this.Debug
            Verbose = $this.Verbose
            Dev = $this.Dev
            Update = $this.Update
            NonInteractive = $this.NonInteractive
        }
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

    static [StorageDriveConfig] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [StorageDriveConfig]::new()
        }

        if ($obj -is [StorageDriveConfig]) {
            return $obj
        }

        $cfg = [StorageDriveConfig]::new()

        $labelObj = $null
        $serialObj = $null
        $driveLetterObj = $null
        $pathObj = $null

        if ($obj -is [System.Collections.IDictionary]) {
            $labelObj = $obj['Label']
            $serialObj = $obj['SerialNumber']
            $driveLetterObj = $obj['DriveLetter']
            $pathObj = $obj['Path']
        }
        else {
            $p = $obj.PSObject.Properties['Label']
            if ($null -ne $p) { $labelObj = $p.Value }

            $p = $obj.PSObject.Properties['SerialNumber']
            if ($null -ne $p) { $serialObj = $p.Value }

            $p = $obj.PSObject.Properties['DriveLetter']
            if ($null -ne $p) { $driveLetterObj = $p.Value }

            $p = $obj.PSObject.Properties['Path']
            if ($null -ne $p) { $pathObj = $p.Value }
        }

        if ($null -ne $labelObj) { $cfg.Label = [string]$labelObj }
        if ($null -ne $serialObj) { $cfg.SerialNumber = [string]$serialObj }
        if ($null -ne $driveLetterObj) { $cfg.DriveLetter = [string]$driveLetterObj }
        if ($null -ne $pathObj) { $cfg.Path = [string]$pathObj }

        return $cfg
    }

    [hashtable] ToHashtable() {
        return @{
            Label = $this.Label
            SerialNumber = $this.SerialNumber
        }
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

    static [StorageGroupConfig] FromObject([string]$groupId, [object]$obj) {
        $gid = if ([string]::IsNullOrWhiteSpace($groupId)) { '' } else { [string]$groupId }

        if ($null -eq $obj) {
            return [StorageGroupConfig]::new($gid)
        }

        if ($obj -is [StorageGroupConfig]) {
            if ([string]::IsNullOrWhiteSpace($obj.GroupId) -and -not [string]::IsNullOrWhiteSpace($gid)) {
                $obj.GroupId = $gid
            }
            if ($null -eq $obj.Backups) { $obj.Backups = [Dictionary[string, StorageDriveConfig]]::new() }
            if ($null -eq $obj.Paths) { $obj.Paths = [Dictionary[string, string]]::new() }
            return $obj
        }

        $cfg = [StorageGroupConfig]::new($gid)

        $displayNameObj = $null
        $masterObj = $null
        $backupObj = $null
        $backupsObj = $null
        $pathsObj = $null

        if ($obj -is [System.Collections.IDictionary]) {
            $displayNameObj = $obj['DisplayName']
            $masterObj = $obj['Master']
            $backupObj = $obj['Backup']
            $backupsObj = $obj['Backups']
            $pathsObj = $obj['Paths']
        }
        else {
            $p = $obj.PSObject.Properties['DisplayName']
            if ($null -ne $p) { $displayNameObj = $p.Value }

            $p = $obj.PSObject.Properties['Master']
            if ($null -ne $p) { $masterObj = $p.Value }

            $p = $obj.PSObject.Properties['Backup']
            if ($null -ne $p) { $backupObj = $p.Value }

            $p = $obj.PSObject.Properties['Backups']
            if ($null -ne $p) { $backupsObj = $p.Value }

            $p = $obj.PSObject.Properties['Paths']
            if ($null -ne $p) { $pathsObj = $p.Value }
        }

        if ($null -ne $displayNameObj) {
            $cfg.DisplayName = [string]$displayNameObj
        }

        # Support both legacy and safe-export shapes:
        # - Master = @{ Label; SerialNumber }
        # - Master = @{ Drive = @{ Label; SerialNumber }; Backups = @{...} }
        if ($null -ne $masterObj) {
            $masterDriveObj = $null
            if ($masterObj -is [System.Collections.IDictionary] -and (_PSmm_DictionaryHasKey -Dictionary $masterObj -Key 'Drive')) {
                $masterDriveObj = $masterObj['Drive']
            }
            elseif ($null -ne $masterObj.PSObject.Properties['Drive']) {
                $masterDriveObj = $masterObj.Drive
            }

            $cfg.Master = if ($null -ne $masterDriveObj) {
                [StorageDriveConfig]::FromObject($masterDriveObj)
            }
            else {
                [StorageDriveConfig]::FromObject($masterObj)
            }

            # If backups were nested under Master.Backups, prefer them when Backup/Backups not provided
            if (($null -eq $backupObj) -and ($null -eq $backupsObj)) {
                if ($masterObj -is [System.Collections.IDictionary] -and (_PSmm_DictionaryHasKey -Dictionary $masterObj -Key 'Backups')) {
                    $backupsObj = $masterObj['Backups']
                }
                elseif ($null -ne $masterObj.PSObject.Properties['Backups']) {
                    $backupsObj = $masterObj.Backups
                }
            }
        }

        # Backups can be stored as Backup={ '1'={...} } or Backups={ '1'={...} }
        $srcBackups = if ($null -ne $backupObj) { $backupObj } else { $backupsObj }
        if ($null -ne $srcBackups) {
            if ($srcBackups -is [System.Collections.IDictionary]) {
                foreach ($bk in $srcBackups.Keys) {
                    $key = [string]$bk
                    $cfg.Backups[$key] = [StorageDriveConfig]::FromObject($srcBackups[$bk])
                }
            }
            else {
                foreach ($p in $srcBackups.PSObject.Properties) {
                    $key = [string]$p.Name
                    $cfg.Backups[$key] = [StorageDriveConfig]::FromObject($p.Value)
                }
            }
        }

        if ($null -ne $pathsObj) {
            if ($pathsObj -is [System.Collections.IDictionary]) {
                foreach ($pk in $pathsObj.Keys) {
                    $cfg.Paths[[string]$pk] = [string]$pathsObj[$pk]
                }
            }
            else {
                foreach ($p in $pathsObj.PSObject.Properties) {
                    $cfg.Paths[[string]$p.Name] = [string]$p.Value
                }
            }
        }

        if ($null -eq $cfg.Backups) { $cfg.Backups = [Dictionary[string, StorageDriveConfig]]::new() }
        if ($null -eq $cfg.Paths) { $cfg.Paths = [Dictionary[string, string]]::new() }

        return $cfg
    }

    [hashtable] ToHashtable() {
        $backupTable = @{}
        if ($null -ne $this.Backups) {
            foreach ($bk in $this.Backups.Keys) {
                $backupTable[[string]$bk] = if ($null -ne $this.Backups[$bk]) { $this.Backups[$bk].ToHashtable() } else { $null }
            }
        }

        $pathsTable = @{}
        if ($null -ne $this.Paths) {
            foreach ($pk in $this.Paths.Keys) {
                $pathsTable[[string]$pk] = $this.Paths[$pk]
            }
        }

        return @{
            DisplayName = $this.DisplayName
            Master = if ($null -ne $this.Master) { $this.Master.ToHashtable() } else { $null }
            Backup = $backupTable
            Paths = $pathsTable
        }
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
    # Full semantic version from Git (e.g., "0.1.0-alpha.5+Branch.dev.Sha.abc1234")
    # This is the primary version property - derived from GitVersion during bootstrap
    [string]$AppVersion
    [RuntimeParameters]$Parameters
    [AppPaths]$Paths
    [AppSecrets]$Secrets
    [LoggingConfiguration]$Logging
    [Dictionary[string, StorageGroupConfig]]$Storage
    [RequirementsConfig]$Requirements
    [PluginsConfig]$Plugins
    [UIConfig]$UI
    [ProjectsConfig]$Projects
    # Internal, structured error tracking persisted with configuration
    [UiErrorCatalog]$InternalErrorMessages
    # Tracks PATH directories added during runtime for cleanup (unless -Dev mode)
    [string[]]$AddedPathEntries = @()

    # Service dependencies for DI
    hidden [object]$FileSystem
    hidden [object]$Environment
    hidden [object]$PathProvider
    hidden [object]$Process

    AppConfiguration() {
        $this.Parameters = [RuntimeParameters]::new()
        $this.Logging = [LoggingConfiguration]::new()
        $this.Storage = [Dictionary[string, StorageGroupConfig]]::new()
        $this.Requirements = [RequirementsConfig]::new()
        $this.Plugins = [PluginsConfig]::new()
        $this.UI = [UIConfig]::new()
        $this.Projects = [ProjectsConfig]::new()
        $this.InternalErrorMessages = [UiErrorCatalog]::new()
        $this.AddedPathEntries = @()
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
        $this.Requirements = [RequirementsConfig]::new()
        $this.Plugins = [PluginsConfig]::new()
        $this.UI = [UIConfig]::new()
        $this.Projects = [ProjectsConfig]::new()
        $this.InternalErrorMessages = [UiErrorCatalog]::new()
        $this.AddedPathEntries = @()
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
        return "$($this.DisplayName) v$($this.AppVersion)"
    }

    hidden static [object] _GetMemberValue([object]$obj, [string]$name) {
        if ($null -eq $obj -or [string]::IsNullOrWhiteSpace($name)) {
            return $null
        }

        if ($obj -is [System.Collections.IDictionary]) {
            try { if ($obj.ContainsKey($name)) { return $obj[$name] } }
            catch {
                Write-Verbose "Dictionary ContainsKey failed for '$name'. $($_.Exception.Message)"
            }

            try { if ($obj.Contains($name)) { return $obj[$name] } }
            catch {
                Write-Verbose "Dictionary Contains failed for '$name'. $($_.Exception.Message)"
            }

            try {
                foreach ($k in $obj.Keys) {
                    if ($k -eq $name) {
                        return $obj[$k]
                    }
                }
            }
            catch {
                Write-Verbose "Dictionary key enumeration failed for '$name'. $($_.Exception.Message)"
            }
            return $null
        }

        $p = $obj.PSObject.Properties[$name]
        if ($null -ne $p) {
            return $p.Value
        }

        return $null
    }

    hidden static [void] _SetMemberValue([object]$obj, [string]$name, [object]$value) {
        if ($null -eq $obj -or [string]::IsNullOrWhiteSpace($name)) {
            return
        }

        if ($obj -is [System.Collections.IDictionary]) {
            $obj[$name] = $value
            return
        }

        try { $obj.$name = $value }
        catch {
            $typeName = $obj.GetType().FullName
            Write-Verbose "Failed to set member '$name' on object type '$typeName'. $($_.Exception.Message)"
        }
    }

    hidden static [string] _ToStringOrNull([object]$value) {
        if ($null -eq $value) { return $null }
        try {
            $s = [string]$value
            if ([string]::IsNullOrWhiteSpace($s)) { return $null }
            return $s
        }
        catch {
            return $null
        }
    }

    static [AppConfiguration] FromObject([object]$obj) {
        if ($null -eq $obj) {
            throw [ArgumentNullException]::new('obj')
        }

        if ($obj -is [AppConfiguration]) {
            return $obj
        }

        $cfg = [AppConfiguration]::new()

        $internalNameValue = [AppConfiguration]::_ToStringOrNull([AppConfiguration]::_GetMemberValue($obj, 'InternalName'))
        if (-not [string]::IsNullOrWhiteSpace($internalNameValue)) {
            $cfg.InternalName = $internalNameValue
        }

        $displayNameValue = [AppConfiguration]::_ToStringOrNull([AppConfiguration]::_GetMemberValue($obj, 'DisplayName'))
        if (-not [string]::IsNullOrWhiteSpace($displayNameValue)) {
            $cfg.DisplayName = $displayNameValue
        }

        $cfg.AppVersion = [AppConfiguration]::_ToStringOrNull([AppConfiguration]::_GetMemberValue($obj, 'AppVersion'))

        $parametersSource = [AppConfiguration]::_GetMemberValue($obj, 'Parameters')
        $cfg.Parameters = [RuntimeParameters]::FromObject($parametersSource)

        $pathsSource = [AppConfiguration]::_GetMemberValue($obj, 'Paths')
        $runtimeRoot = [AppConfiguration]::_ToStringOrNull([AppConfiguration]::_GetMemberValue($pathsSource, 'Root'))
        $repoRoot = [AppConfiguration]::_ToStringOrNull([AppConfiguration]::_GetMemberValue($pathsSource, 'RepositoryRoot'))
        if ([string]::IsNullOrWhiteSpace($runtimeRoot)) {
            $runtimeRoot = $repoRoot
        }

        if (-not [string]::IsNullOrWhiteSpace($runtimeRoot)) {
            $cfg.Paths = if (-not [string]::IsNullOrWhiteSpace($repoRoot)) {
                [AppPaths]::new($repoRoot, $runtimeRoot)
            }
            else {
                [AppPaths]::new($runtimeRoot)
            }

            $cfg.Secrets = [AppSecrets]::new($cfg.Paths.App.Vault)
        }

        $loggingSource = [AppConfiguration]::_GetMemberValue($obj, 'Logging')
        if ($null -ne $loggingSource) {
            $cfg.Logging = [LoggingConfiguration]::FromObject($loggingSource)
        }

        $requirementsSource = [AppConfiguration]::_GetMemberValue($obj, 'Requirements')
        if ($null -ne $requirementsSource) {
            $cfg.Requirements = [RequirementsConfig]::FromObject($requirementsSource)
        }

        $pluginsSource = [AppConfiguration]::_GetMemberValue($obj, 'Plugins')
        if ($null -ne $pluginsSource) {
            $cfg.Plugins = [PluginsConfig]::FromObject($pluginsSource)
        }

        $uiSource = [AppConfiguration]::_GetMemberValue($obj, 'UI')
        if ($null -ne $uiSource) {
            $cfg.UI = [UIConfig]::FromObject($uiSource)
        }

        $projectsSource = [AppConfiguration]::_GetMemberValue($obj, 'Projects')
        if ($null -ne $projectsSource) {
            $cfg.Projects = [ProjectsConfig]::FromObject($projectsSource)
        }

        $errorsSource = [AppConfiguration]::_GetMemberValue($obj, 'InternalErrorMessages')
        if ($null -ne $errorsSource) {
            $cfg.InternalErrorMessages = [UiErrorCatalog]::FromObject($errorsSource)
        }

        $addedPathEntriesValue = [AppConfiguration]::_GetMemberValue($obj, 'AddedPathEntries')
        if ($addedPathEntriesValue -is [string[]]) {
            $cfg.AddedPathEntries = $addedPathEntriesValue
        }
        elseif ($addedPathEntriesValue -is [System.Collections.IEnumerable] -and -not ($addedPathEntriesValue -is [string])) {
            try {
                $cfg.AddedPathEntries = @($addedPathEntriesValue | ForEach-Object { [string]$_ })
            }
            catch {
                Write-Verbose "Failed to normalize AddedPathEntries from enumerable. $($_.Exception.Message)"
            }
        }

        $storageSource = [AppConfiguration]::_GetMemberValue($obj, 'Storage')
        if ($null -eq $storageSource) {
            $cfg.Storage = [Dictionary[string, StorageGroupConfig]]::new()
        }
        else {
            $normalizedStorage = [Dictionary[string, StorageGroupConfig]]::new()
            if ($storageSource -is [System.Collections.IDictionary]) {
                foreach ($k in $storageSource.Keys) {
                    $key = [string]$k
                    $normalizedStorage[$key] = [StorageGroupConfig]::FromObject($key, $storageSource[$k])
                }
            }
            else {
                foreach ($p in $storageSource.PSObject.Properties) {
                    $key = [string]$p.Name
                    $normalizedStorage[$key] = [StorageGroupConfig]::FromObject($key, $p.Value)
                }
            }
            $cfg.Storage = $normalizedStorage
        }

        return $cfg
    }
}

#endregion Base Configuration Classes
