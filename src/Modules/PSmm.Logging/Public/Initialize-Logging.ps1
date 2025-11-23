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

function Initialize-Logging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter()]
        [object]$FileSystem
    )

    try {

        Write-Verbose 'Initializing logging system...'

        # Basic structure validation to avoid hard dependency on specific class types
        if (-not ($Config | Get-Member -Name 'Parameters' -ErrorAction SilentlyContinue) -or
            -not ($Config | Get-Member -Name 'Logging' -ErrorAction SilentlyContinue)) {
            throw "Invalid configuration object: missing 'Parameters' or 'Logging' members"
        }

        $nonInteractive = [bool]$Config.Parameters.NonInteractive

        # Initialize script-level logging context
        $script:Context = @{ Context = $null }
        # Create logging configuration hashtable for PSLogs using config defaults
        $script:Logging = @{
            Path = $Config.Logging.Path
            DefaultLevel = $Config.Logging.DefaultLevel
            Format = $Config.Logging.Format
            PrintBody = $Config.Logging.PrintBody
            Append = $Config.Logging.Append
            Encoding = $Config.Logging.Encoding
            PrintException = $Config.Logging.PrintException
            ShortLevel = $Config.Logging.ShortLevel
            OnlyColorizeLevel = $Config.Logging.OnlyColorizeLevel
        }

        # Validate that required logging properties exist
        if ($null -eq $script:Logging) {
            throw "Logging configuration is null. Run.App.Logging was not properly initialized."
        }

        if (-not ($script:Logging -is [hashtable])) {
            throw "Logging configuration is not a hashtable. Type: $($script:Logging.GetType().FullName)"
        }

        if (-not $script:Logging.ContainsKey('Path')) {
            $loggingKeys = if ($script:Logging.Keys.Count -gt 0) { $script:Logging.Keys -join ', ' } else { '(no keys)' }
            throw "Logging configuration is missing required 'Path' property. Available keys: $loggingKeys."
        }

        if ([string]::IsNullOrWhiteSpace($script:Logging.Path)) {
            throw "Logging Path property is empty or whitespace. Value: '$($script:Logging.Path)'"
        }

        if (-not $script:Logging.ContainsKey('DefaultLevel') -or [string]::IsNullOrWhiteSpace($script:Logging.DefaultLevel)) {
            Write-Warning "Logging configuration is missing 'DefaultLevel', using 'INFO' as default"
            $script:Logging.DefaultLevel = 'INFO'
        }

        if (-not $script:Logging.ContainsKey('Format') -or [string]::IsNullOrWhiteSpace($script:Logging.Format)) {
            Write-Warning "Logging configuration is missing 'Format', using default format"
            $script:Logging.Format = '[%{timestamp}] [%{level}] %{message}'
        }

        # Ensure PSLogs module is available
        if (-not (Get-Module -ListAvailable -Name PSLogs)) {
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
                    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop
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

        Import-Module -Name PSLogs -Force -ErrorAction Stop
        Write-Verbose 'PSLogs module loaded'

        # Note: Format-Pattern is an internal PSLogs function and not needed in PSLogs 5.5.2+
        # PSLogs handles format string parsing internally via Add-LoggingTarget

        # Instantiate FileSystemService only if available (avoid hard failure on missing type)
        if (-not $PSBoundParameters.ContainsKey('FileSystem') -or $null -eq $FileSystem) {
            try {
                # Attempt to create via type accelerator (class may not yet be loaded in some edge cases)
                $null = [FileSystemService] # access to trigger type resolution
                $FileSystem = [FileSystemService]::new()
            }
            catch {
                Write-Verbose 'FileSystemService type not available - falling back to native cmdlets.'
                $FileSystem = $null
            }
        }

        # Ensure log directory exists (use service if available, else native cmdlets)
        $logDir = Split-Path -Path $script:Logging.Path -Parent
        $logDirExists = if ($FileSystem -and ($FileSystem | Get-Member -Name 'TestPath' -ErrorAction SilentlyContinue)) {
            $FileSystem.TestPath($logDir)
        } else { Test-Path -Path $logDir }
        if (-not $logDirExists) {
            Write-Verbose "Creating log directory: $logDir"
            try {
                if ($FileSystem -and ($FileSystem | Get-Member -Name 'NewItem' -ErrorAction SilentlyContinue)) {
                    $FileSystem.NewItem($logDir, 'Directory')
                }
                else {
                    $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop
                }
            }
            catch {
                throw "Failed to create log directory '$logDir': $_"
            }
        }

        # Configure PSLogs module settings
        Set-LoggingCallerScope 2
        Set-LoggingDefaultLevel -Level $script:Logging.DefaultLevel
        Set-LoggingDefaultFormat -Format $script:Logging.Format
        Write-Verbose "Logging configured with default level: $($script:Logging.DefaultLevel)"

        # Clear log file in Dev mode
        if ($Config.Parameters.Dev) {
            Write-Verbose 'Dev mode: Clearing log file'
            $logFilePath = $script:Logging.Path
            $logFileExists = if ($FileSystem -and ($FileSystem | Get-Member -Name 'TestPath' -ErrorAction SilentlyContinue)) {
                $FileSystem.TestPath($logFilePath)
            } else { Test-Path -Path $logFilePath }
            if ($logFileExists) {
                try {
                    if ($FileSystem -and ($FileSystem | Get-Member -Name 'SetContent' -ErrorAction SilentlyContinue)) {
                        $FileSystem.SetContent($logFilePath, '')
                    }
                    else {
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

        Write-Verbose 'Logging initialization complete'
    }
    catch {
        # At this early stage Write-PSmmLog might not be functional; use Write-Error/Warn directly
        Write-Error "Failed to initialize logging: $_"
        throw
    }
}

#endregion ########## PUBLIC ##########
