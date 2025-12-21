<#
.SYNOPSIS
    Initializes the logging system for the PSmediaManager application.

.DESCRIPTION
    Sets up logging configuration, ensures PSLogs module is available, creates log directory,
    and configures logging defaults. In Dev mode, clears the existing log file.

.PARAMETER Config
    The AppConfiguration object containing logging settings.

.EXAMPLE
    Initialize-Logging -Config $appConfig

    Initializes logging using the AppConfiguration object.



.NOTES
    Function Name: Initialize-Logging
    Requires: PowerShell 5.1 or higher
    External Dependency: PSLogs module
    This function must be called before using Write-PSmmLog.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function Set-PSmmRepositoryInstallationPolicy {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$InstallationPolicy
    )

    # Thin wrapper to make Set-PSRepository easy to mock in tests
    if ($PSCmdlet.ShouldProcess("Repository '$Name'", "Set InstallationPolicy to '$InstallationPolicy'")) {
        Set-PSRepository -Name $Name -InstallationPolicy $InstallationPolicy -ErrorAction Stop
    }
}

function Initialize-Logging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter()]
        [object]$FileSystem,

        [Parameter()]
        [object]$PathProvider,

        [Parameter()]
        [switch]$SkipPsLogsInit
    )

    try {
        Write-Verbose 'ENTER Initialize-Logging'
        Write-Verbose 'Initializing logging system...'

        if (
            (-not (Get-Command -Name 'Get-PSmmLoggingConfigMemberValue' -ErrorAction SilentlyContinue)) -or
            (-not (Get-Command -Name 'Test-PSmmLoggingConfigMember' -ErrorAction SilentlyContinue))
        ) {
            try {
                $helpersPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Private\ConfigMemberAccessHelpers.ps1'
                if (Test-Path -Path $helpersPath) {
                    . $helpersPath
                }
            }
            catch {
                Write-Verbose "Initialize-Logging: failed to load ConfigMemberAccess helpers: $($_.Exception.Message)"
            }
        }

        $pathProviderType = 'PathProvider' -as [type]
        $iPathProviderType = 'IPathProvider' -as [type]

        if ($null -eq $PathProvider -and $null -ne $pathProviderType -and $null -ne $iPathProviderType) {
            try {
                $pathsCandidate = [ConfigMemberAccess]::GetMemberValue($Config, 'Paths')
                if ($null -ne $pathsCandidate -and $pathsCandidate -is $iPathProviderType) {
                    $PathProvider = $pathProviderType::new($pathsCandidate)
                }
            }
            catch {
                Write-Verbose "Initialize-Logging: failed to bind PathProvider from Config.Paths: $($_.Exception.Message)"
            }
        }

        if ($null -eq $PathProvider) {
            try {
                $globalServiceContainer = Get-Variable -Name 'PSmmServiceContainer' -Scope Global -ValueOnly -ErrorAction Stop
                $resolved = $globalServiceContainer.Resolve('PathProvider')
                if ($null -ne $resolved) {
                    $PathProvider = $resolved
                }
            }
            catch {
                Write-Verbose "Initialize-Logging: failed to resolve PathProvider from global ServiceContainer: $($_.Exception.Message)"
            }
        }

        if ($null -ne $PathProvider -and $null -ne $pathProviderType -and $null -ne $iPathProviderType -and $PathProvider -is $iPathProviderType -and -not ($PathProvider -is $pathProviderType)) {
            $PathProvider = $pathProviderType::new($PathProvider)
        }

        # Basic structure validation supporting both typed classes and hashtable inputs.
        # IMPORTANT: Do not rely on Get-Command visibility of private helper functions;
        # use ConfigMemberAccess directly so AppConfiguration works reliably.
        $parametersSource = $null
        $loggingSource = $null
        $hasParameters = $false
        $hasLogging = $false
        try { $hasParameters = [ConfigMemberAccess]::TryGetMemberValue($Config, 'Parameters', [ref]$parametersSource) } catch { $hasParameters = $false }
        try { $hasLogging = [ConfigMemberAccess]::TryGetMemberValue($Config, 'Logging', [ref]$loggingSource) } catch { $hasLogging = $false }

        if (-not $hasParameters -or -not $hasLogging) {
            $available = @(
                $Config |
                    Get-Member -MemberType NoteProperty, Property, ScriptProperty, AliasProperty -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty Name
            )
            $availableText = if ($available) { ($available -join ', ') } else { '<none>' }
            $ex = [ConfigurationException]::new("Invalid configuration object: missing 'Parameters' or 'Logging' members. Available members: $availableText")
            throw $ex
        }

        if ($null -eq $parametersSource) {
            $ex = [ConfigurationException]::new("Invalid configuration object: 'Parameters' is null")
            throw $ex
        }

        $nonInteractive = $false
        if ($parametersSource -is [System.Collections.IDictionary]) {
            try { $nonInteractive = [bool]$parametersSource['NonInteractive'] } catch { $nonInteractive = $false }
        }
        else {
            $nonInteractive = [bool]([ConfigMemberAccess]::GetMemberValue($parametersSource, 'NonInteractive'))
        }

        # Initialize script-level logging context
        $script:Context = @{ Context = $null }

        if ($null -eq $loggingSource) {
            $ex = [ConfigurationException]::new("Logging configuration is null. Run.App.Logging was not properly initialized.")
            throw $ex
        }

        $loggingSettings = $null

        if ($loggingSource -is [System.Collections.IDictionary]) {
            # Clone dictionary inputs so defaults can be applied without mutating the caller
            $loggingSettings = @{} + $loggingSource
        }
        elseif ($loggingSource -is [string] -or $loggingSource.GetType().IsValueType) {
            $sourceTypeName = $loggingSource.GetType().FullName
            $ex = [ConfigurationException]::new("Logging configuration is not a hashtable. Type: $sourceTypeName")
            throw $ex
        }
        else {
            # Convert objects (PSCustomObject or typed) to hashtable for easier merging
            # Prefer ToHashtable() when available (stable schema for typed config)
            try {
                $loggingSettings = $loggingSource.ToHashtable()
                if ($loggingSettings -is [System.Collections.IDictionary]) {
                    $keyCount = @($loggingSettings.Keys).Count
                    $convertedKeys = $loggingSettings.Keys -join ', '
                    Write-Verbose "Converted LoggingConfiguration via ToHashtable() with $keyCount keys: $convertedKeys"
                }
                else {
                    $loggingSettings = $null
                }
            }
            catch {
                Write-Verbose "[Initialize-Logging] ToHashtable() failed; falling back to Get-Member: $($_.Exception.Message)"
                $loggingSettings = $null
            }

            if ($null -eq $loggingSettings) {
                $convertedLogging = @{}
                $memberNames = @(
                    $loggingSource |
                        Get-Member -MemberType NoteProperty, Property -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty Name
                )
                foreach ($memberName in $memberNames) {
                    if ([string]::IsNullOrWhiteSpace([string]$memberName)) {
                        continue
                    }
                    $memberValue = Get-PSmmLoggingConfigMemberValue -Object $loggingSource -Name ([string]$memberName)
                    $convertedLogging[[string]$memberName] = $memberValue
                }
                # Use Keys count to avoid relying on .Count property availability across types
                $keyCount = @($convertedLogging.Keys).Count
                $convertedKeys = $convertedLogging.Keys -join ', '
                Write-Verbose "Converted LoggingConfiguration to hashtable with $keyCount keys: $convertedKeys"
                $loggingSettings = $convertedLogging
            }
        }

        if ($null -eq $loggingSettings) {
            $sourceTypeName = $loggingSource.GetType().FullName
            $ex = [ConfigurationException]::new("Failed to convert logging configuration to hashtable. Source type: $sourceTypeName")
            throw $ex
        }

            $loggingSettingsType = $loggingSettings.GetType().FullName
            Write-Verbose "loggingSettings type after conversion: $loggingSettingsType"
            $preAssignKeys = @($loggingSettings.Keys)
            $preAssignCount = $preAssignKeys.Count
            Write-Verbose "loggingSettings Keys count (pre-assign): $preAssignCount"

        try {
            Write-Verbose 'DEBUG: Assigning logging settings to script:Logging'
            $script:Logging = $loggingSettings
            Write-Verbose 'DEBUG: Assigned logging settings to script:Logging'
        }
        catch {
                $ex = [ConfigurationException]::new("Failed assigning logging settings to script:Logging: $_")
            throw $ex
        }

            $scriptLoggingType = $script:Logging.GetType().FullName
            Write-Verbose "script:Logging type after assignment: $scriptLoggingType"
            $postAssignKeys = @($script:Logging.Keys)
            $postAssignCount = $postAssignKeys.Count
            Write-Verbose "script:Logging Keys count (post-assign): $postAssignCount"

        # Guard: ensure Keys is enumerable and Logging is a standard Hashtable
        try {
            $null = foreach ($k in $script:Logging.Keys) { $k }  # force enumeration
        }
        catch {
            Write-Verbose "DEBUG: Logging.Keys enumeration failed: $_. Converting to standard Hashtable."
            $fixed = @{}
            foreach ($kv in $loggingSettings.GetEnumerator()) {
                $fixed[$kv.Key] = $kv.Value
            }
            $script:Logging = $fixed
            Write-Verbose "DEBUG: Replaced script:Logging with standard Hashtable. Keys: $($script:Logging.Keys -join ', ')"
        }

        if ($null -eq $script:Logging) {
            $ex = [ConfigurationException]::new("Logging configuration could not be initialized - settings are null after processing.")
            throw $ex
        }

            if ($script:Logging -isnot [System.Collections.IDictionary]) {
                $scriptLoggingType = $script:Logging.GetType().FullName
                $ex = [ConfigurationException]::new("Logging configuration is not a hashtable after conversion. Type: $scriptLoggingType")
                throw $ex
            }

        $containsPath = $false
        try { $containsPath = [bool]$script:Logging.ContainsKey('Path') } catch { $containsPath = $false }
        if (-not $containsPath) {
            try { $containsPath = [bool]$script:Logging.Contains('Path') } catch { $containsPath = $false }
        }
        if (-not $containsPath) {
            try {
                foreach ($k in $script:Logging.Keys) {
                    if ($k -eq 'Path') { $containsPath = $true; break }
                }
            }
            catch {
                $containsPath = $false
            }
        }
        if (-not $containsPath) {
            $keysCount = @($script:Logging.Keys).Count
            $loggingKeys = if ($script:Logging.Keys -and $keysCount -gt 0) { $script:Logging.Keys -join ', ' } else { '(no keys)' }
            $ex = [ConfigurationException]::new("Logging configuration is missing required 'Path' property. Available keys: $loggingKeys.")
            throw $ex
        }

        if ([string]::IsNullOrWhiteSpace($script:Logging.Path)) {
            $ex = [ConfigurationException]::new("Logging Path property is empty or whitespace. Value: '$($script:Logging.Path)'")
            throw $ex
        }

        $hasDefaultLevel = $false
        try { $hasDefaultLevel = [bool]$script:Logging.ContainsKey('DefaultLevel') } catch { $hasDefaultLevel = $false }
        if (-not $hasDefaultLevel) {
            try { $hasDefaultLevel = [bool]$script:Logging.Contains('DefaultLevel') } catch { $hasDefaultLevel = $false }
        }
        if (-not $hasDefaultLevel) {
            try {
                foreach ($k in $script:Logging.Keys) {
                    if ($k -eq 'DefaultLevel') { $hasDefaultLevel = $true; break }
                }
            }
            catch {
                $hasDefaultLevel = $false
            }
        }
        if (-not $hasDefaultLevel -or [string]::IsNullOrWhiteSpace($script:Logging.DefaultLevel)) {
            Write-Warning "Logging configuration is missing 'DefaultLevel', using 'INFO' as default"
            $script:Logging.DefaultLevel = 'INFO'
        }

        $hasFormat = $false
        try { $hasFormat = [bool]$script:Logging.ContainsKey('Format') } catch { $hasFormat = $false }
        if (-not $hasFormat) {
            try { $hasFormat = [bool]$script:Logging.Contains('Format') } catch { $hasFormat = $false }
        }
        if (-not $hasFormat) {
            try {
                foreach ($k in $script:Logging.Keys) {
                    if ($k -eq 'Format') { $hasFormat = $true; break }
                }
            }
            catch {
                $hasFormat = $false
            }
        }
        if (-not $hasFormat -or [string]::IsNullOrWhiteSpace($script:Logging.Format)) {
            Write-Warning "Logging configuration is missing 'Format', using default format"
            $script:Logging.Format = '[%{timestamp}] [%{level}] %{message}'
        }

        # Ensure PSLogs module is available
        if (-not $SkipPsLogsInit -and -not (Get-Module -ListAvailable -Name PSLogs)) {
            Write-Verbose 'PSLogs module not found, installing...'
            try {
                $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
                if (-not $nugetProvider) {
                    Write-Verbose 'NuGet provider not found, installing...'
                    Install-PackageProvider -Name NuGet -Scope CurrentUser -Force -ErrorAction Stop
                }
            }
            catch {
                $nugetMessage = "Failed to install NuGet provider required for PSLogs: $_"
                if ($nonInteractive) {
                    throw $nugetMessage
                }
                Write-Warning $nugetMessage
            }

            try {
                $psGallery = Get-PSRepository -Name 'PSGallery' -ErrorAction Stop
                if ($psGallery.InstallationPolicy -ne 'Trusted') {
                    Write-Verbose 'PSGallery repository not trusted - marking as Trusted'
                    Set-PSmmRepositoryInstallationPolicy -Name 'PSGallery' -InstallationPolicy 'Trusted'
                }
            }
            catch {
                $repoMessage = "Failed to configure PSGallery repository for PSLogs installation: $_"
                if ($nonInteractive) {
                    throw $repoMessage
                }
                Write-Warning $repoMessage
            }

            try {
                Install-Module -Name PSLogs -Force -Scope CurrentUser -ErrorAction Stop -Confirm:$false
            }
            catch {
                $installMessage = "Failed to install PSLogs module automatically. Install it manually with 'Install-Module -Name PSLogs -Scope CurrentUser'. Details: $_"
                throw $installMessage
            }
        }

        if (-not $SkipPsLogsInit) {
            try {
                Write-Verbose 'DEBUG: Importing PSLogs module...'
                Import-Module -Name PSLogs -Force -ErrorAction Stop
                Write-Verbose 'PSLogs module loaded'
            }
            catch {
                throw "Failed to import PSLogs module: $_"
            }
        }
        else {
            Write-Verbose 'DEBUG: Skipping PSLogs import per -SkipPsLogsInit flag'
        }

        # Note: Format-Pattern is an internal PSLogs function and not needed in PSLogs 5.5.2+
        # PSLogs handles format string parsing internally via Add-LoggingTarget

        # Instantiate FileSystemService only if available (avoid hard failure on missing type)
            Write-Verbose 'DEBUG: Checking FileSystemService parameter...'
        if (-not $PSBoundParameters.ContainsKey('FileSystem') -or $null -eq $FileSystem) {
            try {
                $FileSystem = New-FileSystemService
            }
            catch {
                Write-Verbose 'FileSystemService type not available - falling back to native cmdlets.'
                $FileSystem = $null
            }
        }
            Write-Verbose 'DEBUG: FileSystemService check complete'

        # Ensure log directory exists (using PathProvider and FileSystem services)
    $scriptLoggingType = $script:Logging.GetType().FullName
    $scriptLoggingKeysCount = @($script:Logging.Keys).Count
    $scriptLoggingKeysJoined = $script:Logging.Keys -join ', '
    Write-Verbose "DEBUG: About to check log directory. script:Logging type: $scriptLoggingType, KeysCount: $scriptLoggingKeysCount, Keys: $scriptLoggingKeysJoined"
        # Derive parent directory
        $parent = Split-Path -Path $script:Logging.Path -Parent
        if ($PathProvider) {
            $logDir = $PathProvider.CombinePath(@($parent))
        } else {
            $logDir = $parent
        }
        try {
            Write-Verbose "DEBUG: Checking log directory exists: $logDir"
            # Use FileSystem service if available, otherwise use native cmdlet
            if ($FileSystem) {
                $logDirExists = $FileSystem.TestPath($logDir)
            } else {
                $logDirExists = Test-Path -Path $logDir
            }
            if (-not $logDirExists) {
                Write-Verbose "Creating log directory: $logDir"
                try {
                    if ($FileSystem) {
                        $FileSystem.NewItem($logDir, 'Directory')
                    }
                    else {
                        # Fallback only during early bootstrap when services may not be loaded
                        Write-Verbose 'FileSystem service not available during bootstrap, using native New-Item cmdlet'
                        $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop
                    }
                }
                catch {
                    $ex = [LoggingException]::new("Failed to create log directory '$logDir'", $logDir, $_.Exception)
                    throw $ex
                }
            }
        }
        catch {
              $ex = [LoggingException]::new("Log directory check failed: $_", $logDir, $_.Exception)
            throw $ex
        }
            Write-Verbose 'DEBUG: Log directory check complete'

        # Configure PSLogs module settings with detailed instrumentation
        if (-not $SkipPsLogsInit) {
            Write-Verbose 'DEBUG: About to configure PSLogs defaults...'
            try {
                Write-Verbose 'DEBUG: Set-LoggingCallerScope(2)'
                Set-LoggingCallerScope 2
                Write-Verbose 'DEBUG: Set-LoggingCallerScope OK'
            }
            catch {
                $ex = [LoggingException]::new("PSLogs default setup failed at Set-LoggingCallerScope: $_", $_.Exception)
                throw $ex
            }

            try {
                Write-Verbose "DEBUG: Set-LoggingDefaultLevel(Level=$($script:Logging.DefaultLevel))"
                Set-LoggingDefaultLevel -Level $script:Logging.DefaultLevel
                Write-Verbose 'DEBUG: Set-LoggingDefaultLevel OK'
            }
            catch {
                    $ex = [LoggingException]::new("PSLogs default setup failed at Set-LoggingDefaultLevel: $_", $loggingPath, $_.Exception)
                throw $ex
            }

            try {
                Write-Verbose "DEBUG: Set-LoggingDefaultFormat(Format=$($script:Logging.Format))"
                Set-LoggingDefaultFormat -Format $script:Logging.Format
                Write-Verbose 'DEBUG: Set-LoggingDefaultFormat OK'
            }
            catch {
                    $ex = [LoggingException]::new("PSLogs default setup failed at Set-LoggingDefaultFormat: $_", $loggingPath, $_.Exception)
                throw $ex
            }

            Write-Verbose 'DEBUG: PSLogs defaults configured'
            Write-Verbose "Logging configured with default level: $($script:Logging.DefaultLevel)"
        }
        else {
            Write-Verbose 'DEBUG: Skipping PSLogs defaults configuration per -SkipPsLogsInit flag'
        }

        # Clear log file in Dev mode
        $devMode = [bool](Get-PSmmLoggingConfigMemberValue -Object $parametersSource -Name 'Dev')
        if ($devMode) {
            Write-Verbose 'Dev mode: Clearing log file'
            $logFilePath = $script:Logging.Path
            $logFileExists = if ($FileSystem) {
                $FileSystem.TestPath($logFilePath)
            } else {
                Test-Path -Path $logFilePath
            }
            if ($logFileExists) {
                try {
                    if ($FileSystem) {
                        $FileSystem.SetContent($logFilePath, '')
                    }
                    else {
                        # Fallback during early bootstrap
                        Set-Content -Path $logFilePath -Value '' -Force -ErrorAction Stop
                    }
                }
                catch {
                    Write-Warning "Failed to clear log file '$logFilePath': $_"
                }
            }
            Write-Verbose "Dev mode: Log file cleared: $logFilePath"
            Write-PSmmLog -Level 'INFO' -Message 'Log file cleared' -Context '-Dev: Clear logfile' -Console -File
        }

        Write-Verbose 'EXIT Initialize-Logging (success)'
        Write-Verbose 'Logging initialization complete'
    }
    catch {
        # At this early stage Write-PSmmLog might not be functional; use Write-Error/Warn directly
        Write-Verbose 'EXIT Initialize-Logging (failure)'
        Write-Verbose "EXCEPTION AT: $($_.InvocationInfo.ScriptLineNumber):$($_.InvocationInfo.OffsetInLine) in $($_.InvocationInfo.ScriptName)"
        Write-Verbose "EXCEPTION: $($_.Exception.Message)"
        Write-Error "Failed to initialize logging: $_"
        throw
    }
}

#endregion ########## PUBLIC ##########
