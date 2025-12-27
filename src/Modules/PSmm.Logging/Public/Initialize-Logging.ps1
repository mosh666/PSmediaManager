<#
.SYNOPSIS
    Initializes the logging system for the PSmediaManager application.

.DESCRIPTION
    Sets up logging configuration, ensures PSLogs module is available, creates log directory,
    and configures logging defaults. In Dev mode, clears the existing log file.

.PARAMETER Config
    The AppConfiguration object containing logging settings.

.PARAMETER FileSystem
    A FileSystem service instance (service-first DI). This is required; no filesystem shim/fallback is used.

.EXAMPLE
    Initialize-Logging -Config $appConfig -FileSystem $fileSystemService -PathProvider $pathProviderService

    Initializes logging using the AppConfiguration object and injected services.



.NOTES
    Function Name: Initialize-Logging
    Requires: PowerShell 5.1 or higher
    External Dependency: PSLogs module
    This function must be called before using Write-PSmmLog.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function Initialize-Logging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
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
            (-not (Get-Command -Name 'Test-PSmmLoggingConfigMember' -ErrorAction SilentlyContinue)) -or
            (-not (Get-Command -Name 'Get-PSmmLoggingExceptionInstance' -ErrorAction SilentlyContinue))
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
                $pathsCandidate = Get-PSmmLoggingConfigMemberValue -Object $Config -Name 'Paths'
                if ($null -ne $pathsCandidate -and $pathsCandidate -is $iPathProviderType) {
                    $PathProvider = $pathProviderType::new($pathsCandidate)
                }
            }
            catch {
                Write-Verbose "Initialize-Logging: failed to bind PathProvider from Config.Paths: $($_.Exception.Message)"
            }
        }

        if ($null -eq $PathProvider) {
            throw 'PathProvider is required for Initialize-Logging (pass -PathProvider, or ensure Config.Paths provides an IPathProvider).'
        }

        # Logging is service-first: a FileSystem service must be injected.
        $requiredFsMethods = @('TestPath', 'NewItem', 'SetContent')
        foreach ($methodName in $requiredFsMethods) {
            $hasMethod = $null -ne ($FileSystem | Get-Member -Name $methodName -MemberType Method -ErrorAction SilentlyContinue)
            if (-not $hasMethod) {
                throw "FileSystem is missing required method '$methodName'. Initialize-Logging requires an injected FileSystem service implementing: $($requiredFsMethods -join ', ')."
            }
        }

        if ($null -ne $PathProvider -and $null -ne $pathProviderType -and $null -ne $iPathProviderType -and $PathProvider -is $iPathProviderType -and -not ($PathProvider -is $pathProviderType)) {
            $PathProvider = $pathProviderType::new($PathProvider)
        }

        # Basic structure validation supporting both typed classes and hashtable inputs.
        # IMPORTANT: distinguish between "missing member" vs "member present but null".
        $hasParametersMember = $false
        $hasLoggingMember = $false
        try { $hasParametersMember = Test-PSmmLoggingConfigMember -Object $Config -Name 'Parameters' } catch { $hasParametersMember = $false }
        try { $hasLoggingMember = Test-PSmmLoggingConfigMember -Object $Config -Name 'Logging' } catch { $hasLoggingMember = $false }

        if (-not $hasParametersMember -or -not $hasLoggingMember) {
            $available = @(
                $Config |
                    Get-Member -MemberType NoteProperty, Property, ScriptProperty, AliasProperty -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty Name
            )
            $availableText = if ($available) { ($available -join ', ') } else { '<none>' }
            $msg = "Invalid configuration object: missing required members. Expected: Parameters, Logging. Available members: $availableText"
            $ex = Get-PSmmLoggingExceptionInstance -TypeName 'ConfigurationException' -ArgumentList @($msg)
            if ($null -eq $ex) { $ex = [System.InvalidOperationException]::new($msg) }
            throw $ex
        }

        $parametersSource = $null
        $loggingSource = $null
        try { $parametersSource = Get-PSmmLoggingConfigMemberValue -Object $Config -Name 'Parameters' } catch { $parametersSource = $null }
        try { $loggingSource = Get-PSmmLoggingConfigMemberValue -Object $Config -Name 'Logging' } catch { $loggingSource = $null }

        if ($null -eq $parametersSource) {
            # Parameters can be null if a caller passes an incomplete hashtable/PSCustomObject.
            # Logging can still be initialized safely using defaults.
            Write-Verbose "Initialize-Logging: Config.Parameters is null; using fallback runtime parameters defaults."
            $parametersSource = @{
                Debug = $false
                Verbose = $false
                Dev = $false
                Update = $false
                NonInteractive = $false
            }
        }

        $null = if ($parametersSource -is [System.Collections.IDictionary]) {
            try { [bool]$parametersSource['NonInteractive'] } catch { $false }
        }
        else {
            [bool](Get-PSmmLoggingConfigMemberValue -Object $parametersSource -Name 'NonInteractive' -Default $false)
        }

        # Initialize script-level logging context
        $script:Context = @{ Context = $null }

        if ($null -eq $loggingSource) {
            # Logging bag can be null if the caller passed an incomplete config object.
            # Derive safe defaults so bootstrapping can proceed.
            Write-Verbose "Initialize-Logging: Config.Logging is null; deriving default logging configuration."

            $pathsCandidate = $null
            try { $pathsCandidate = Get-PSmmLoggingConfigMemberValue -Object $Config -Name 'Paths' } catch { $pathsCandidate = $null }

            $logDirCandidate = $null
            if ($null -ne $pathsCandidate) {
                try { $logDirCandidate = Get-PSmmLoggingConfigMemberValue -Object $pathsCandidate -Name 'Log' -Default $null } catch { $logDirCandidate = $null }
            }

            $timestamp = Get-Date -Format 'yyyyMMdd'
            $logFileName = "$timestamp-PSmm-$env:USERNAME@$env:COMPUTERNAME.log"

            $derivedLogPath = $null
            try {
                if (-not [string]::IsNullOrWhiteSpace([string]$logDirCandidate) -and $PathProvider) {
                    $derivedLogPath = $PathProvider.CombinePath(@([string]$logDirCandidate, $logFileName))
                }
                elseif (-not [string]::IsNullOrWhiteSpace([string]$logDirCandidate)) {
                    $derivedLogPath = Join-Path -Path ([string]$logDirCandidate) -ChildPath $logFileName
                }
            }
            catch {
                $derivedLogPath = $null
            }

            if ([string]::IsNullOrWhiteSpace([string]$derivedLogPath)) {
                # Last-resort: place log next to the repo (better than failing before any logging works)
                $derivedLogPath = Join-Path -Path (Get-Location) -ChildPath $logFileName
            }

            $loggingSource = @{
                Path = [string]$derivedLogPath
                DefaultLevel = 'INFO'
                Format = '[%{timestamp}] [%{level}] %{message}'
                PrintBody = $true
                Append = $true
                Encoding = 'utf8'
                PrintException = $true
                ShortLevel = $false
                OnlyColorizeLevel = $false
            }
        }

        $loggingSettings = $null

        if ($loggingSource -is [System.Collections.IDictionary]) {
            # Clone dictionary inputs so defaults can be applied without mutating the caller
            $loggingSettings = @{} + $loggingSource
        }
        elseif ($loggingSource -is [string] -or $loggingSource.GetType().IsValueType) {
            $sourceTypeName = $loggingSource.GetType().FullName
            $msg = "Logging configuration is not a hashtable. Type: $sourceTypeName"
            $ex = Get-PSmmLoggingExceptionInstance -TypeName 'ConfigurationException' -ArgumentList @($msg)
            if ($null -eq $ex) { $ex = [System.InvalidOperationException]::new($msg) }
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
            $msg = "Failed to convert logging configuration to hashtable. Source type: $sourceTypeName"
            $ex = Get-PSmmLoggingExceptionInstance -TypeName 'ConfigurationException' -ArgumentList @($msg)
            if ($null -eq $ex) { $ex = [System.InvalidOperationException]::new($msg) }
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
                $msg = "Failed assigning logging settings to script:Logging: $_"
                $ex = Get-PSmmLoggingExceptionInstance -TypeName 'ConfigurationException' -ArgumentList @($msg)
                if ($null -eq $ex) { $ex = [System.InvalidOperationException]::new($msg) }
            throw $ex
        }

            $scriptLoggingType = $script:Logging.GetType().FullName
            Write-Verbose "script:Logging type after assignment: $scriptLoggingType"
            $postAssignKeys = @($script:Logging.Keys)
            $postAssignCount = $postAssignKeys.Count
            Write-Verbose "script:Logging Keys count (post-assign): $postAssignCount"

        # Normalize to a standard Hashtable so downstream code can safely use $script:Logging.Key dot-access
        # (generic dictionaries can be IDictionary but do not reliably support PS property access).
        if ($null -ne $script:Logging -and $script:Logging -is [System.Collections.IDictionary] -and $script:Logging -isnot [hashtable]) {
            $fixed = @{}
            foreach ($kv in $script:Logging.GetEnumerator()) {
                $fixed[[string]$kv.Key] = $kv.Value
            }
            $script:Logging = $fixed
            Write-Verbose "DEBUG: Normalized script:Logging to Hashtable. Keys: $($script:Logging.Keys -join ', ')"
        }

        # Guard: ensure Keys is enumerable and Logging is still sane
        try {
            $null = foreach ($k in $script:Logging.Keys) { $k }  # force enumeration
        }
        catch {
            $msg = "Logging configuration keys could not be enumerated after initialization: $_"
            $ex = Get-PSmmLoggingExceptionInstance -TypeName 'ConfigurationException' -ArgumentList @($msg)
            if ($null -eq $ex) { $ex = [System.InvalidOperationException]::new($msg) }
            throw $ex
        }

        if ($null -eq $script:Logging) {
            $msg = "Logging configuration could not be initialized - settings are null after processing."
            $ex = Get-PSmmLoggingExceptionInstance -TypeName 'ConfigurationException' -ArgumentList @($msg)
            if ($null -eq $ex) { $ex = [System.InvalidOperationException]::new($msg) }
            throw $ex
        }

            if ($script:Logging -isnot [System.Collections.IDictionary]) {
                $scriptLoggingType = $script:Logging.GetType().FullName
                $msg = "Logging configuration is not a hashtable after conversion. Type: $scriptLoggingType"
                $ex = Get-PSmmLoggingExceptionInstance -TypeName 'ConfigurationException' -ArgumentList @($msg)
                if ($null -eq $ex) { $ex = [System.InvalidOperationException]::new($msg) }
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
            $msg = "Logging configuration is missing required 'Path' property. Available keys: $loggingKeys."
            $ex = Get-PSmmLoggingExceptionInstance -TypeName 'ConfigurationException' -ArgumentList @($msg)
            if ($null -eq $ex) { $ex = [System.InvalidOperationException]::new($msg) }
            throw $ex
        }

        if ([string]::IsNullOrWhiteSpace($script:Logging.Path)) {
            $msg = "Logging Path property is empty or whitespace. Value: '$($script:Logging.Path)'"
            $ex = Get-PSmmLoggingExceptionInstance -TypeName 'ConfigurationException' -ArgumentList @($msg)
            if ($null -eq $ex) { $ex = [System.InvalidOperationException]::new($msg) }
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

        # Defaults for properties used by logging targets (avoid StrictMode issues if caller config is minimal)
        if (-not $script:Logging.ContainsKey('PrintBody') -or $null -eq $script:Logging['PrintBody']) {
            $script:Logging['PrintBody'] = $true
        }
        if (-not $script:Logging.ContainsKey('Append') -or $null -eq $script:Logging['Append']) {
            $script:Logging['Append'] = $true
        }
        if (-not $script:Logging.ContainsKey('Encoding') -or [string]::IsNullOrWhiteSpace([string]$script:Logging['Encoding'])) {
            $script:Logging['Encoding'] = 'utf8'
        }
        if (-not $script:Logging.ContainsKey('PrintException') -or $null -eq $script:Logging['PrintException']) {
            $script:Logging['PrintException'] = $true
        }
        if (-not $script:Logging.ContainsKey('ShortLevel') -or $null -eq $script:Logging['ShortLevel']) {
            $script:Logging['ShortLevel'] = $false
        }

        if (-not $SkipPsLogsInit) {
            Write-Verbose 'DEBUG: Validating PSLogs dependency...'
            if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
                throw "PSLogs dependency is missing. Ensure PSLogs is installed and imported before calling Initialize-Logging. (Module loading is owned by PSmm bootstrap.)"
            }
            Write-Verbose 'DEBUG: PSLogs dependency is available'

            # PSLogs uses a private helper named Format-Pattern for target formatting.
            # Some environments/modules do not export it, and PSLogs can attempt to invoke it from a worker scope.
            # Provide a minimal global fallback to prevent runtime logging failures.
            if (-not (Get-Command -Name 'Format-Pattern' -ErrorAction SilentlyContinue)) {
                function global:Format-Pattern {
                    [CmdletBinding()]
                    [OutputType([string])]
                    param(
                        [Parameter(Mandatory)]
                        [ValidateNotNullOrEmpty()]
                        [string]$Pattern,

                        [Parameter()]
                        [AllowNull()]
                        [object]$Source,

                        [Parameter()]
                        [switch]$Wildcard
                    )

                    $src = $Source
                    $useWildcard = [bool]$Wildcard

                    $getValue = {
                        param([string]$key)

                        if ($null -eq $src) { return $null }

                        if ($src -is [System.Collections.IDictionary]) {
                            if ($src.ContainsKey($key)) { return $src[$key] }
                            if ($src.Contains($key)) { return $src[$key] }
                            return $null
                        }

                        try {
                            $p = $src.PSObject.Properties[$key]
                            if ($null -ne $p) { return $p.Value }
                        }
                        catch {
                            return $null
                        }

                        return $null
                    }

                    return ([regex]::Replace(
                        $Pattern,
                        '%\{(?<key>[A-Za-z0-9_]+)(?::(?<fmt>[^}]+))?\}',
                        {
                            param($m)
                            $key = $m.Groups['key'].Value
                            $fmt = $m.Groups['fmt'].Value

                            if ($useWildcard) {
                                return '*'
                            }

                            $val = $getValue.Invoke($key)
                            if ($null -eq $val) { return '' }

                            # Date/time formatting: %{timestamp:+yyyyMMdd HHmmss.fff}
                            if ($val -is [datetime] -and $fmt -and $fmt.StartsWith('+')) {
                                try { return $val.ToString($fmt.Substring(1)) } catch { return $val.ToString() }
                            }

                            # Alignment formatting: %{level:-9}
                            if ($fmt -and ($fmt -match '^-?\d+$')) {
                                try {
                                    $align = [int]$fmt
                                    return ('{0,' + $align + '}' -f ([string]$val))
                                }
                                catch {
                                    return [string]$val
                                }
                            }

                            if ($val -is [System.Collections.IDictionary] -or $val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                                try { return ($val | ConvertTo-Json -Compress -Depth 10) } catch { return [string]$val }
                            }

                            return [string]$val
                        }
                    ))
                }
            }
        }
        else {
            Write-Verbose 'DEBUG: Skipping PSLogs dependency validation per -SkipPsLogsInit flag'
        }

        # Note: Format-Pattern is an internal PSLogs function and not needed in PSLogs 5.5.2+
        # PSLogs handles format string parsing internally via Add-LoggingTarget

        Write-Verbose 'DEBUG: FileSystemService parameter validated'

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
            $logDirExists = $FileSystem.TestPath($logDir)
            if (-not $logDirExists) {
                Write-Verbose "Creating log directory: $logDir"
                try {
                    $FileSystem.NewItem($logDir, 'Directory')
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
            $logFileExists = $FileSystem.TestPath($logFilePath)
            if ($logFileExists) {
                try {
                    $FileSystem.SetContent($logFilePath, '')
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
