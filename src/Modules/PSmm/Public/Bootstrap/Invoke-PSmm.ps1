<#
.SYNOPSIS
    Bootstraps the PSmediaManager application.

.DESCRIPTION
    Initializes the PSmediaManager application by setting up folders, loading configuration,
    initializing logging, confirming PowerShell requirements, verifying plugins, getting app version,
    confirming storage structure, and loading UI configuration.

    This is the main initialization function that prepares the entire runtime environment
    and ensures all prerequisites are met before launching the user interface.

.PARAMETER Config
    The AppConfiguration object containing application settings and paths.
    This object provides type-safe access to:
    - Application metadata (name, version, parameters)
    - Path configurations (root, modules, plugins)
    - Configuration file paths
    - Logging settings
    - Storage configuration


.EXAMPLE
    Invoke-PSmm -Config $appConfig

    Bootstraps the application using the provided configuration object.


.NOTES
    This function is called during application startup to prepare the runtime environment.
    It performs critical initialization steps in a specific order to ensure dependencies
    are properly handled.

    Function Name: Invoke-PSmm
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function Invoke-PSmm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AppConfiguration]$Config
    )

    begin {
        # Main bootstrap flow
        Write-Verbose "Starting PSmediaManager bootstrap process..."
    }

    process {
        try {
            #region ----- Setup Folders
            Write-Verbose 'Creating directory structure...'
            $Config.Paths.EnsureDirectoriesExist()
            #endregion ----- Setup Folders

            #region ----- Initialize Shared Services (Early)
            # Create core services needed for configuration and logging
            $fileSystemService = [FileSystemService]::new()
            $pathProviderService = [PathProvider]::new()
            $environmentService = [EnvironmentService]::new()
            $processService = [ProcessService]::new()
            $httpService = [HttpService]::new()
            $cryptoService = [CryptoService]::new()
            #endregion ----- Initialize Shared Services (Early)

            #region ----- Load Configuration
            Write-Verbose 'Verifying configuration...'

            # Configuration and requirements already loaded by AppConfigurationBuilder in main script
            # Just verify they exist
            if ($null -eq $Config.Requirements) {
                throw "Configuration requirements not loaded"
            }
            Write-Verbose "Configuration already loaded by AppConfigurationBuilder"

            Write-Verbose "Configuration verification complete"
            #endregion ----- Load Configuration

            #region ----- Initialize Logging
            Write-Verbose 'Initializing logging system...'
            Write-Verbose 'SENTINEL: About to call Initialize-Logging'
            Write-Output ''
            try {
                Initialize-Logging -Config $Config -FileSystem $fileSystemService -PathProvider $pathProviderService -SkipPsLogsInit
                Write-Verbose 'SENTINEL: Returned from Initialize-Logging'
            }
            catch {
                Write-Error "EXCEPTION DETAILS: $($_.Exception.Message)"
                Write-Verbose "InvocationInfo: $($_.InvocationInfo | Out-String)"
                Write-Verbose "ScriptStackTrace: $($_.ScriptStackTrace)"
                Write-Verbose "TargetObject: $($_.TargetObject)"
                throw
            }
            Start-Sleep -Milliseconds 500
            #endregion ----- Initialize Logging

            Write-PSmmLog -Level NOTICE -Context 'Start PSmediaManager' -Message '########## Bootstrapping PSmediaManager' -Console -File

            #region ----- First-Run Setup
            $setupPending = $false
            $vaultPath = $Config.Paths.App.Vault
            $dbPath = $pathProviderService.CombinePath(@($vaultPath,'PSmm_System.kdbx'))

            if (-not ($fileSystemService.TestPath($dbPath))) {
                Write-PSmmLog -Level NOTICE -Context 'First-Run Setup' -Message 'KeePass vault not found - starting first-run setup' -Console -File

                if (Get-Command Invoke-FirstRunSetup -ErrorAction SilentlyContinue) {
                    $setupSuccess = Invoke-FirstRunSetup -Config $Config -NonInteractive:$Config.Parameters.NonInteractive -FileSystem $fileSystemService -Environment $environmentService -PathProvider $pathProviderService -Process $processService

                    if ($setupSuccess -eq 'PendingKeePassXC') {
                        Write-PSmmLog -Level NOTICE -Context 'First-Run Setup' `
                            -Message 'Setup pending KeePassXC installation - will complete after plugins are confirmed' -Console -File
                        $setupPending = $true
                    }
                    elseif ($setupSuccess -eq $false) {
                        Write-PSmmLog -Level ERROR -Context 'First-Run Setup' `
                            -Message 'First-run setup was cancelled. Application cannot continue without vault setup.' -Console -File
                        Write-Output ''
                        Write-Error 'Application terminated.'
                        Write-Output ''
                        if ($env:MEDIA_MANAGER_TEST_MODE -eq '1') {
                            throw 'First-run setup cancelled. (Test Mode: throwing instead of exit)'
                        }
                        else {
                            exit 1
                        }
                    }
                }
                else {
                    Write-PSmmLog -Level ERROR -Context 'First-Run Setup' `
                        -Message 'Invoke-FirstRunSetup function not available. Vault setup required.' -Console -File
                    Write-Error "Invoke-FirstRunSetup function not available. Vault setup required."
                    Write-Error "Use 'Initialize-SystemVault' and 'Save-SystemSecret' to set up secrets."
                    if ($env:MEDIA_MANAGER_TEST_MODE -eq '1') {
                        throw 'Invoke-FirstRunSetup not available. (Test Mode: throwing instead of exit)'
                    }
                    else {
                        exit 1
                    }
                }
            }
            #endregion ----- First-Run Setup

            #region ----- Load Secrets (Skip if setup is pending)
            if (-not $setupPending) {
                Write-Verbose 'Ensuring KeePassXC CLI is available before loading secrets...'
                $null = Get-KeePassCli -Config $Config -Http $httpService -Crypto $cryptoService `
                    -FileSystem $fileSystemService -Environment $environmentService -PathProvider $pathProviderService -Process $processService

                Write-Verbose 'Loading secrets from KeePassXC vault...'
                # Load secrets after logging is initialized so warnings can be properly logged
                $Config.Secrets.LoadSecrets()
            }
            else {
                Write-Verbose 'Skipping secret loading - setup is pending KeePassXC installation'
            }
            #endregion ----- Load Secrets (Skip if setup is pending)

            #region ----- Verify PowerShell Requirements
            Write-PSmmLog -Level NOTICE -Context 'Confirm-PowerShell' -Message 'Checking required PowerShell version and modules' -Console -File
            Confirm-PowerShell -Config $Config -Scope PSVersion
            Confirm-PowerShell -Config $Config -Scope PSModules
            Write-Verbose "PowerShell requirements verified"
            #endregion ----- Verify PowerShell Requirements

            #region ----- Verify Required Plugins
            Write-PSmmLog -Level NOTICE -Context 'Confirm-Plugins' -Message 'Checking required plugins' -Console -File
            Confirm-Plugins -Config $Config -Http $httpService -Crypto $cryptoService `
                -FileSystem $fileSystemService -Environment $environmentService -PathProvider $pathProviderService -Process $processService
            Write-Verbose "Required plugins verified"
            #endregion ----- Verify Required Plugins

            #region ----- Complete Pending Setup
            if ($setupPending) {
                Write-PSmmLog -Level NOTICE -Context 'First-Run Setup' -Message 'KeePassXC now available - completing vault setup' -Console -File

                $vaultPath = $Config.Paths.App.Vault
                $dbPath = $pathProviderService.CombinePath(@($vaultPath,'PSmm_System.kdbx'))

                # Check if vault was created during plugin installation
                if (-not ($fileSystemService.TestPath($dbPath))) {
                    if (Get-Command Invoke-FirstRunSetup -ErrorAction SilentlyContinue) {
                        $setupSuccess = Invoke-FirstRunSetup -Config $Config -NonInteractive:$Config.Parameters.NonInteractive -FileSystem $fileSystemService -Environment $environmentService -PathProvider $pathProviderService -Process $processService

                        # Re-check DB existence in case function succeeded but returned non-boolean
                        $dbNowExists = $fileSystemService.TestPath($dbPath)
                        $pending = ($setupSuccess -is [string] -and $setupSuccess -eq 'PendingKeePassXC')
                        $ok = ($setupSuccess -is [bool] -and $setupSuccess) -or ($setupSuccess -is [string] -and $setupSuccess -eq 'True') -or $dbNowExists

                        if (-not $ok -or $pending) {
                            Write-PSmmLog -Level ERROR -Context 'First-Run Setup' `
                                -Message 'Failed to complete vault setup after KeePassXC installation' -Console -File
                            Write-Output ''
                            Write-Error 'Failed to complete setup. Application terminated.'
                            Write-Output ''
                            if ($env:MEDIA_MANAGER_TEST_MODE -eq '1') {
                                throw 'Failed to complete vault setup. (Test Mode: throwing instead of exit)'
                            }
                            else {
                                exit 1
                            }
                        }
                    }
                }

                # Reload secrets now that vault is set up
                $Config.Secrets.LoadSecrets()
            }
            #endregion ----- Complete Pending Setup

            #region ----- Security Validation
            Write-PSmmLog -Level NOTICE -Context 'Security Check' -Message 'Validating secrets security' -Console -File
            $securityCheckPassed = Test-SecretsSecurity -Config $Config
            if (-not $securityCheckPassed) {
                Write-Warning 'Security validation identified issues - please review'
            }
            Write-Verbose "Security validation completed"
            #endregion ----- Security Validation

            #region ----- Get Application Version
            Write-PSmmLog -Level NOTICE -Context 'Get-AppVersion' -Message 'Getting PSmediaManager version from Git' -Console -File
            $GitPath = Join-Path -Path $Config.Paths.RepositoryRoot -ChildPath '.git'
            $gitVersionExecutable = $null
            if ($Config.Requirements -and $Config.Requirements.Plugins -and $Config.Requirements.Plugins.b_GitEnv -and $Config.Requirements.Plugins.b_GitEnv.GitVersion) {
                $gitVersionExecutable = Get-LocalPluginExecutablePath -PluginConfig $Config.Requirements.Plugins.b_GitEnv.GitVersion
            }
            $Config.AppVersion = Get-ApplicationVersion -GitPath $GitPath -GitVersionExecutablePath $gitVersionExecutable
            Write-PSmmLog -Level NOTICE -Context 'Get-AppVersion' -Message "Current PSmediaManager version: $($Config.AppVersion)" -Console -File
            #endregion ----- Get Application Version

            #region ----- Confirm Storage Structure
            Write-PSmmLog -Level NOTICE -Context 'Confirm-Storage' -Message 'Checking Master and Backup Storage' -Console -File
            Confirm-Storage -Config $Config
            Write-Verbose "Storage structure confirmed"
            #endregion ----- Confirm Storage Structure

            #region ----- Load UI/Projects Configuration
            Write-Verbose 'UI and Projects configuration loaded via AppConfiguration'
            #endregion ----- Load UI/Projects Configuration

            # Pause if running in debug/verbose/dev/update mode for user review
            $shouldPause = $false
            if ($Config.Parameters -and -not $Config.Parameters.NonInteractive) {
                $shouldPause = $Config.Parameters.ShouldPause()
            }

            if ($shouldPause) {
                Write-Information "`nPress any key to continue..." -InformationAction Continue
                if ($env:MEDIA_MANAGER_SKIP_READKEY -ne '1') {
                    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
                    catch { Write-Verbose 'ReadKey skipped due to host limitations.' }
                }
                else {
                    Write-Verbose 'Interactive pause bypassed (MEDIA_MANAGER_SKIP_READKEY=1).'
                }
            }

            Write-Verbose "Bootstrap completed successfully"
        }
        catch {
            $ErrorMessage = "Bootstrap failed: $_"

            # Only log if Write-PSmmLog is available (logging may not be initialized yet)
            if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                Write-PSmmLog -Level ERROR -Context 'Invoke-PSmm' -Message $ErrorMessage -Console -File
            }
            else {
                Write-Warning $ErrorMessage
            }

            throw $ErrorMessage
        }
    }
}

<#
.SYNOPSIS
    Gets the application version from Git.

.DESCRIPTION
    Retrieves the semantic version and short SHA from Git using GitVersion.
    Returns 'Unknown-Version' if Git or GitVersion is unavailable.

.PARAMETER GitPath
    Path to either the repository root or the .git directory.

.OUTPUTS
    String containing the semantic version and short SHA (e.g., "1.0.0-abc123"),
    or 'Unknown-Version' if Git information is unavailable.

.EXAMPLE
    $version = Get-ApplicationVersion -GitPath "D:\MyApp\.git"

-.NOTES
    Requires GitVersion to be installed locally (preferably under App.Paths.App.Plugins) or available in PATH.
#>
function Get-ApplicationVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$GitPath,

        [Parameter()]
        [string]$GitVersionExecutablePath
    )

    try {
        if (-not (Test-Path -Path $GitPath)) {
            Write-Warning "Git directory not found: $GitPath"
            return 'Unknown-Version'
        }

        $resolvedGitPath = Resolve-Path -Path $GitPath -ErrorAction Stop
        $repositoryPath = $resolvedGitPath.Path

        if ((Split-Path -Path $repositoryPath -Leaf) -eq '.git') {
            $repositoryPath = Split-Path -Path $repositoryPath -Parent
        }

        if (-not (Test-Path -Path $repositoryPath)) {
            Write-Warning "Repository path not found: $repositoryPath"
            return 'Unknown-Version'
        }

        # GitVersion fails when invoked with a bare drive root (e.g. "D:\") so force a concrete directory token
        $repositoryFullPath = [System.IO.Path]::GetFullPath($repositoryPath)
        $gitVersionTargetPath = if ($repositoryFullPath -eq [System.IO.Path]::GetPathRoot($repositoryFullPath)) {
            Join-Path -Path $repositoryFullPath -ChildPath '.'
        }
        else {
            $repositoryFullPath
        }

        # Prefer the configured GitVersion executable (usually under App.Plugins) before falling back to PATH
        $gitVersionExecutable = $null

        if (-not [string]::IsNullOrWhiteSpace($GitVersionExecutablePath)) {
            if (Test-Path -Path $GitVersionExecutablePath) {
                $gitVersionExecutable = $GitVersionExecutablePath
            }
            else {
                Write-Warning "GitVersion executable not found at configured path: $GitVersionExecutablePath"
            }
        }

        if (-not $gitVersionExecutable) {
            $gitVersionCommand = Get-Command gitversion.exe -ErrorAction SilentlyContinue
            if ($gitVersionCommand) {
                $gitVersionExecutable = $gitVersionCommand.Source
            }
            else {
                Write-Warning 'GitVersion not found in PATH'
            }
        }

        if ($gitVersionExecutable) {
            Write-Verbose "Using GitVersion executable at: $gitVersionExecutable"
            $gitVersionOutput = & $gitVersionExecutable $gitVersionTargetPath /output json /nofetch 2>$null

            if ($LASTEXITCODE -eq 0 -and $gitVersionOutput) {
                try {
                    $gitVersionJson = ($gitVersionOutput | Out-String)
                    $gitVersionData = $gitVersionJson | ConvertFrom-Json -ErrorAction Stop
                    $verSemVer = $gitVersionData.SemVer
                    $verShortSha = $gitVersionData.ShortSha

                    if ($verSemVer -and $verShortSha) {
                        $version = "$verSemVer-$verShortSha"
                        Write-Verbose "Retrieved version from GitVersion: $version"
                        return $version
                    }
                    else {
                        Write-Warning 'GitVersion JSON missing SemVer or ShortSha fields'
                    }
                }
                catch {
                    Write-Warning "Failed to parse GitVersion JSON output: $_"
                }
            }
            else {
                Write-Warning 'GitVersion did not return version information'
            }
        }

        # Fallback: use native git commands if GitVersion output was unavailable
        $gitExe = Get-Command git.exe -ErrorAction SilentlyContinue
        if ($gitExe) {
            $gitSemVer = & git.exe -C $repositoryPath describe --tags --exact-match 2>$null
            if (-not $gitSemVer) {
                $gitSemVer = & git.exe -C $repositoryPath describe --tags --long 2>$null
            }

            $gitSemVer = $gitSemVer.Trim()
            $gitSha = (& git.exe -C $repositoryPath rev-parse --short HEAD 2>$null).Trim()

            if ($gitSemVer -and $gitSha) {
                $fallbackVersion = "$gitSemVer-$gitSha"
                Write-Verbose "Retrieved version from git describe fallback: $fallbackVersion"
                return $fallbackVersion
            }
        }

        Write-Warning 'Unable to determine application version from Git'
        return 'Unknown-Version'
    }
    catch {
        Write-Verbose "Failed to get version from Git: $_"
        return 'Unknown-Version'
    }
}

# Helper builds the executable path for a confirmed plugin under App.Plugins.
function Get-LocalPluginExecutablePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$PluginConfig
    )

    if ($null -eq $PluginConfig) {
        return $null
    }

    $installPath = $PluginConfig.InstallPath
    if ([string]::IsNullOrWhiteSpace($installPath)) {
        return $null
    }

    $segments = @($installPath)
    if (-not [string]::IsNullOrWhiteSpace($PluginConfig.CommandPath)) {
        $segments += $PluginConfig.CommandPath
    }
    if (-not [string]::IsNullOrWhiteSpace($PluginConfig.Command)) {
        $segments += $PluginConfig.Command
    }

    $segments = $segments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($segments.Count -eq 0) {
        return $null
    }

    $executablePath = $segments[0]
    for ($i = 1; $i -lt $segments.Count; $i++) {
        $executablePath = Join-Path -Path $executablePath -ChildPath $segments[$i]
    }

    return $executablePath
}

#endregion ########## PUBLIC ##########
