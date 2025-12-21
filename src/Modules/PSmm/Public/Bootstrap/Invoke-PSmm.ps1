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
        [object]$Config
    )

    begin {
        # Main bootstrap flow
        Write-Verbose "Starting PSmediaManager bootstrap process..."
    }

    process {
        try {
            # Normalize legacy config shapes to typed AppConfiguration before using typed members
            if (-not ($Config -is [AppConfiguration])) {
                $Config = [AppConfiguration]::FromObject($Config)
            }

            function Get-ConfigMemberValue([object]$Object, [string]$Name, $Default = $null) {
                if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
                    return $Default
                }

                if ($Object -is [System.Collections.IDictionary]) {
                    try { if ($Object.ContainsKey($Name)) { return $Object[$Name] } } catch { Write-Verbose "Get-ConfigMemberValue: ContainsKey('$Name') failed: $($_.Exception.Message)" }
                    try { if ($Object.Contains($Name)) { return $Object[$Name] } } catch { Write-Verbose "Get-ConfigMemberValue: Contains('$Name') failed: $($_.Exception.Message)" }
                    try {
                        foreach ($k in $Object.Keys) {
                            if ($k -eq $Name) { return $Object[$k] }
                        }
                    }
                    catch { Write-Verbose "Get-ConfigMemberValue: Enumerating dictionary keys for '$Name' failed: $($_.Exception.Message)" }
                    return $Default
                }

                $p = $Object.PSObject.Properties[$Name]
                if ($null -ne $p) {
                    return $p.Value
                }

                return $Default
            }

            if ($null -eq $Config.Paths) {
                throw 'Configuration is missing Paths; unable to bootstrap.'
            }

            $vaultPath = $null
            try { $vaultPath = [string]$Config.Paths.App.Vault } catch { $vaultPath = $null }
            if ([string]::IsNullOrWhiteSpace($vaultPath)) {
                throw 'Configuration is missing Paths.App.Vault; unable to bootstrap.'
            }

            $repositoryRoot = $null
            try { $repositoryRoot = [string]$Config.Paths.RepositoryRoot } catch { $repositoryRoot = $null }
            if ([string]::IsNullOrWhiteSpace($repositoryRoot)) {
                throw 'Configuration is missing Paths.RepositoryRoot; unable to bootstrap.'
            }

            #region ----- Setup Folders
            Write-Verbose 'Creating directory structure...'
            if ($null -eq $Config.Paths) {
                throw 'Configuration is missing Paths; unable to bootstrap.'
            }

            try {
                $ensureMethod = $Config.Paths.PSObject.Methods['EnsureDirectoriesExist']
                if ($null -eq $ensureMethod) {
                    throw 'Configuration Paths object does not implement EnsureDirectoriesExist().'
                }
                $Config.Paths.EnsureDirectoriesExist()
            }
            catch {
                throw "Failed to ensure directories exist from Config.Paths: $_"
            }
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
            $dbPath = $pathProviderService.CombinePath(@($vaultPath,'PSmm_System.kdbx'))

            $nonInteractive = $false
            if ($Config -and $Config.Parameters) {
                try { $nonInteractive = [bool]$Config.Parameters.NonInteractive } catch { $nonInteractive = $false }
            }

            if (-not ($fileSystemService.TestPath($dbPath))) {
                Write-PSmmLog -Level NOTICE -Context 'First-Run Setup' -Message 'KeePass vault not found - starting first-run setup' -Console -File

                if (Get-Command Invoke-FirstRunSetup -ErrorAction SilentlyContinue) {
                    $setupSuccess = Invoke-FirstRunSetup -Config $Config -NonInteractive:$nonInteractive -FileSystem $fileSystemService -Environment $environmentService -PathProvider $pathProviderService -Process $processService

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
                if ($null -eq $Config.Secrets) {
                    throw 'Configuration is missing Secrets; unable to load secrets.'
                }
                try {
                    $loadMethod = $Config.Secrets.PSObject.Methods['LoadSecrets']
                    if ($null -eq $loadMethod) {
                        throw 'Configuration Secrets object does not implement LoadSecrets().'
                    }
                    $Config.Secrets.LoadSecrets()
                }
                catch {
                    throw "Failed to load secrets from Config.Secrets: $_"
                }
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

            # Create temporary ServiceContainer for plugin confirmation with available services
            $pluginServiceContainer = [ServiceContainer]::new()
            $pluginServiceContainer.RegisterSingleton('Http', $httpService)
            $pluginServiceContainer.RegisterSingleton('Crypto', $cryptoService)
            $pluginServiceContainer.RegisterSingleton('FileSystem', $fileSystemService)
            $pluginServiceContainer.RegisterSingleton('Environment', $environmentService)
            $pluginServiceContainer.RegisterSingleton('PathProvider', $pathProviderService)
            $pluginServiceContainer.RegisterSingleton('Process', $processService)

            Confirm-Plugins -Config $Config -ServiceContainer $pluginServiceContainer
            Write-Verbose "Required plugins verified"
            #endregion ----- Verify Required Plugins

            #region ----- Complete Pending Setup
            if ($setupPending) {
                Write-PSmmLog -Level NOTICE -Context 'First-Run Setup' -Message 'KeePassXC now available - completing vault setup' -Console -File

                $dbPath = $pathProviderService.CombinePath(@($vaultPath,'PSmm_System.kdbx'))

                # Check if vault was created during plugin installation
                if (-not ($fileSystemService.TestPath($dbPath))) {
                    if (Get-Command Invoke-FirstRunSetup -ErrorAction SilentlyContinue) {
                        $setupSuccess = Invoke-FirstRunSetup -Config $Config -NonInteractive:$nonInteractive -FileSystem $fileSystemService -Environment $environmentService -PathProvider $pathProviderService -Process $processService

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
                if ($null -eq $Config.Secrets) {
                    throw 'Configuration is missing Secrets; unable to reload secrets.'
                }
                try {
                    $loadMethod = $Config.Secrets.PSObject.Methods['LoadSecrets']
                    if ($null -eq $loadMethod) {
                        throw 'Configuration Secrets object does not implement LoadSecrets().'
                    }
                    $Config.Secrets.LoadSecrets()
                }
                catch {
                    throw "Failed to reload secrets from Config.Secrets: $_"
                }
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
            $GitPath = Join-Path -Path $repositoryRoot -ChildPath '.git'
            $gitVersionExecutable = $null

            $pluginsConfig = Get-ConfigMemberValue -Object $Config -Name 'Plugins'
            $resolvedPlugins = Get-ConfigMemberValue -Object $pluginsConfig -Name 'Resolved'
            $gitEnvGroup = Get-ConfigMemberValue -Object $resolvedPlugins -Name 'b_GitEnv'
            $gitVersionPlugin = Get-ConfigMemberValue -Object $gitEnvGroup -Name 'GitVersion'
            $gitVersionMandatory = [bool](Get-ConfigMemberValue -Object $gitVersionPlugin -Name 'Mandatory' -Default $false)
            $gitVersionEnabled = [bool](Get-ConfigMemberValue -Object $gitVersionPlugin -Name 'Enabled' -Default $false)

            if ($null -ne $gitVersionPlugin -and ($gitVersionMandatory -or $gitVersionEnabled)) {
                # Try to resolve plugins path for GitVersion lookup
                $pluginsPath = $null
                try {
                    $pluginsPath = [string]$Config.Paths.App.Plugins.Root
                }
                catch {
                    Write-Verbose "Could not resolve plugins path from Config.Paths: $_"
                }

                $gitVersionExecutable = Get-LocalPluginExecutablePath -PluginConfig $gitVersionPlugin -PluginsRootPath $pluginsPath
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
            if ($Config.Parameters) {
                $isNonInteractive = $false
                try { $isNonInteractive = [bool]$Config.Parameters.NonInteractive } catch { $isNonInteractive = $false }

                if (-not $isNonInteractive) {
                    try {
                        $pauseMethod = $Config.Parameters.PSObject.Methods['ShouldPause']
                        if ($null -eq $pauseMethod) {
                            throw 'Config.Parameters.ShouldPause() method not found.'
                        }
                        $shouldPause = [bool]$Config.Parameters.ShouldPause()
                    }
                    catch {
                        throw "Failed to evaluate Config.Parameters.ShouldPause(): $($_.Exception.Message)"
                    }
                }
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
            $stack = $_.ScriptStackTrace
            $invocation = $null
            if ($_.InvocationInfo) {
                $invocation = $_.InvocationInfo.PositionMessage
            }

            $ErrorMessage = "Bootstrap failed: $_"
            if ($stack) {
                $ErrorMessage += "`nStack:`n$stack"
            }
            if ($invocation) {
                $ErrorMessage += "`nPosition:`n$invocation"
            }

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

                    if ($verSemVer) {
                        Write-Verbose "Retrieved version from GitVersion: $verSemVer"
                        return $verSemVer
                    }
                    else {
                        Write-Warning 'GitVersion JSON missing SemVer field'
                    }
                }
                catch {
                    Write-Warning "Failed to parse GitVersion JSON output: $_"
                }
            }
            else {
                Write-Verbose 'GitVersion did not return version information; attempting git describe fallback'
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

            if ($gitSemVer) {
                Write-Verbose "Retrieved version from git describe fallback: $gitSemVer"
                return $gitSemVer
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
        [hashtable]$PluginConfig,

        [Parameter()]
        [string]$PluginsRootPath
    )

    if ($null -eq $PluginConfig) {
        return $null
    }

    # Try to get InstallPath from config; if not present, compute it from plugin name
    $installPath = $PluginConfig.InstallPath

    # If InstallPath not in config but we have PluginsRootPath and plugin Name, try to find it
    if ([string]::IsNullOrWhiteSpace($installPath) -and -not [string]::IsNullOrWhiteSpace($PluginsRootPath) -and $PluginConfig.Name) {
        # Search for installed plugin directory matching the name pattern
        try {
            $pluginDir = Get-ChildItem -Path $PluginsRootPath -Directory -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -like "$($PluginConfig.Name)*" } |
                         Select-Object -First 1
            if ($pluginDir) {
                $installPath = $pluginDir.FullName
            }
        }
        catch {
            Write-Verbose "Error searching for plugin directory at $PluginsRootPath : $_"
        }
    }

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
