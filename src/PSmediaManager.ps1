<#
.SYNOPSIS
    PSmediaManager PowerShell Application

.DESCRIPTION
    Main entry point for the PSmediaManager application. This script initializes the runtime
    environment, imports required modules, and launches the user interface.

    The application provides a comprehensive media management solution with support for:
    - Media file organization and cataloging
    - Project management
    - Plugin integration (digiKam, ExifTool, FFmpeg, etc.)
    - Configuration management
    - Structured logging

.PARAMETER Dev
    Enables development mode, which keeps environment paths registered in the session.
    PATH entries are added to Process scope only and not cleaned up at exit.
    This is useful for development and debugging purposes.

.PARAMETER Update
    Triggers update mode for checking and installing application updates.

.PARAMETER NonInteractive
    Suppresses interactive UI launch (headless / automation scenarios). Still performs bootstrap.

.EXAMPLE
    .\src\PSmediaManager.ps1
    Starts the application in normal mode.

.EXAMPLE
    .\src\PSmediaManager.ps1 -Dev -Verbose
    Starts the application in development mode with verbose output.

.EXAMPLE
    .\src\PSmediaManager.ps1 -Update
    Starts the application and checks for updates.

.EXAMPLE
    .\src\PSmediaManager.ps1 -NonInteractive
    Performs bootstrap only (no UI) – useful for CI validation.

.NOTES
    Author           : Der Mosh
    Version          : 1.0.0
    Created          : 2024-01-01
    Last Modified    : 2025-11-14

    Requires         : PowerShell 7.5.4 or higher (aligns with Requirements manifest)

    Repository       : https://github.com/mosh666/PSmediaManager
    License          : MIT

    Dependencies     : - digiKam 8.8.0 or higher
                       - ExifTool 13.40 or higher
                       - FFmpeg 8.0 or higher
                       - ImageMagick 7.1.2 or higher
                       - Git LFS 3.7.1 or higher

    Uses Write-Host for exit message because application output must go directly to console,
    not the pipeline (prevents blank line artifacts). This is intentional and not a violation
    of best practices for console applications with UI components.
#>

#Requires -Version 7.5.4

using namespace System.Management.Automation

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(HelpMessage = 'Enable development mode (keeps environment paths registered)')]
    [switch]$Dev,

    [Parameter(HelpMessage = 'Check and install application updates')]
    [switch]$Update,

    [Parameter(HelpMessage = 'Run without launching interactive UI (bootstrap only)')]
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-ServiceHealthLog {
    param(
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [switch]$Console
    )

    $logCmd = Get-Command Write-PSmmLog -ErrorAction SilentlyContinue
    if ($logCmd) {
        $logParams = @{ Level = $Level; Context = 'ServiceHealth'; Message = $Message; File = $true }
        if ($Console) { $logParams['Console'] = $true }
        Write-PSmmLog @logParams
    }
    else {
        Write-Verbose "[ServiceHealth][$Level] $Message"
    }
}

# Define module root for path calculations (portable app structure)
$script:ModuleRoot = $PSScriptRoot

# Region: Early host capability validation (fast-fail before heavier work)
if ($PSVersionTable.PSVersion -lt [version]'7.5.4') {
    Write-Error "PSmediaManager requires PowerShell >= 7.5.4. Current: $($PSVersionTable.PSVersion)" -ErrorAction Stop
}

# Ensure script is not dot-sourced accidentally (can cause cleanup side-effects)
if ($MyInvocation.InvocationName -eq '.') {
    Write-Warning 'This script is not intended to be dot-sourced. Launch it directly instead.'
}

# Provide a concise startup banner (avoid Write-Host in analysis-critical paths)
Write-Verbose ('Starting PSmediaManager (PID {0}) in {1} mode' -f $PID, ($(if ($Dev) { 'Dev' } else { 'Normal' })))

#region ===== Module Loading (Loader-First) =====

<#
    Import all PSmediaManager modules from the Modules directory.
    Modules are imported in dependency order to ensure proper loading.
    The core PSmm module must be imported FIRST as it contains the classes
    needed for configuration and other modules.
#>
try {
    $modulesPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Modules'
    Write-Verbose "Importing modules from: $modulesPath"

    # 1) Import PSmm FIRST to load all core classes and DI types.
    $psmmManifestPath = Join-Path -Path (Join-Path -Path $modulesPath -ChildPath 'PSmm') -ChildPath 'PSmm.psd1'
    if (-not (Test-Path -LiteralPath $psmmManifestPath)) {
        throw "PSmm module manifest not found: $psmmManifestPath"
    }

    Import-Module -Name $psmmManifestPath -Force -Global -ErrorAction Stop -Verbose:($VerbosePreference -eq 'Continue')

    # 2) Create DI container and register core services (service-first runtime)
    $script:ServiceContainer = [ServiceContainer]::new()
    $script:ServiceContainer.RegisterSingleton('FileSystem', [FileSystemService]::new())
    $script:ServiceContainer.RegisterSingleton('Environment', [EnvironmentService]::new())
    $script:ServiceContainer.RegisterSingleton('Process', [ProcessService]::new())
    $script:ServiceContainer.RegisterSingleton('PathProvider', [PathProvider]::new())

    $httpService = [HttpService]::new($script:ServiceContainer.Resolve('FileSystem'))
    $script:ServiceContainer.RegisterSingleton('Http', $httpService)
    $script:ServiceContainer.RegisterSingleton('Crypto', [CryptoService]::new())
    $script:ServiceContainer.RegisterSingleton('Cim', [CimService]::new())
    $script:ServiceContainer.RegisterSingleton('Storage', [StorageService]::new())
    $script:ServiceContainer.RegisterSingleton('Git', [GitService]::new($script:ServiceContainer.Resolve('Process')))

    # Fatal handling must exist before importing additional modules
    $script:ServiceContainer.RegisterSingleton('FatalErrorUi', [FatalErrorUiService]::new())

    # Do not expose ServiceContainer globally; enforce explicit DI (service-first runtime).

    # 3) Import remaining modules in dependency order
    $moduleLoadOrder = @(
        'PSmm.Logging',
        'PSmm.Plugins',
        'PSmm.Projects',
        'PSmm.UI'
    )

    foreach ($moduleName in $moduleLoadOrder) {
        $moduleFolder = Join-Path -Path $modulesPath -ChildPath $moduleName
        $manifestPath = Join-Path -Path $moduleFolder -ChildPath "$moduleName.psd1"

        Write-Verbose "Importing module: $moduleName"
        Import-PSmmModuleOrFatal -ModuleName $moduleName -ManifestPath $manifestPath -FatalErrorUi ($script:ServiceContainer.Resolve('FatalErrorUi')) -NonInteractive:([bool]$NonInteractive.IsPresent)
    }

    Write-Verbose "Core modules imported and DI container initialized"
}
catch {
    # PSmm import failure occurs before the fatal service exists.
    # Do not emit ad-hoc fatal output here; rely on the thrown exception.
    throw [System.Exception]::new(('Failed to load core module PSmm. {0}' -f $_.Exception.Message), $_.Exception)
}

#endregion ===== Module Loading (Loader-First) =====

<#
    Instantiate service implementations for dependency injection.
    These services provide testable abstractions over system operations.
#>
#region ===== Service Instantiation =====

Write-Verbose "Service layer available (ServiceContainer with $($script:ServiceContainer.Count()) services)"

#endregion ===== Service Instantiation =====


#region ===== Runtime Configuration Initialization =====

<#
    Initialize the application configuration using the builder pattern.
    This must be done AFTER loading modules since it uses classes from PSmm module.
#>
try {
    Write-Verbose "Initializing runtime configuration..."

    # Create runtime parameters from bound parameters
    # Convert BoundParameters to hashtable to avoid type conversion issues
    $boundParamsHashtable = @{}
    foreach ($key in $PSCmdlet.MyInvocation.BoundParameters.Keys) {
        # Shallow copy only (parameters are primitives / switches here)
        $boundParamsHashtable[$key] = $PSCmdlet.MyInvocation.BoundParameters[$key]
    }

    $runtimeParams = [RuntimeParameters]::new($boundParamsHashtable)
    $runtimeParams.Dev = $Dev.IsPresent
    $runtimeParams.Update = $Update.IsPresent
    $runtimeParams.NonInteractive = $NonInteractive.IsPresent

    # Determine repository root (parent of src) and derive runtime paths from it
    $repositoryRoot = Split-Path -Path $script:ModuleRoot -Parent

    if (-not (Test-Path -Path $repositoryRoot -PathType Container)) {
        $configEx = [ConfigurationException]::new("Unable to resolve repository root from: $script:ModuleRoot", $repositoryRoot)
        throw $configEx
    }

    # Create builder with repository-aware paths
    $configBuilder = [AppConfigurationBuilder]::new($repositoryRoot).
    WithParameters($runtimeParams)

    # Use a PathProvider wrapper over the builder's current Paths so directory initialization
    # and secrets injection get canonical AppPaths behavior.
    $pathProviderForConfig = $script:ServiceContainer.Resolve('PathProvider')
    try {
        $innerPaths = $configBuilder.GetConfig().Paths
        if ($null -ne $innerPaths -and ($innerPaths -is [IPathProvider])) {
            $pathProviderForConfig = [PathProvider]::new([IPathProvider]$innerPaths)
            $script:ServiceContainer.RegisterSingleton('PathProvider', $pathProviderForConfig)
            Write-Verbose "Rebound PathProvider to AppPaths from configuration builder"
        }
    }
    catch {
        Write-Verbose "Unable to bind PathProvider to builder Paths; using existing PathProvider. $($_.Exception.Message)"
    }

    $configBuilder = $configBuilder.
    WithServices(
        $script:ServiceContainer.Resolve('FileSystem'),
        $script:ServiceContainer.Resolve('Environment'),
        $pathProviderForConfig,
        $script:ServiceContainer.Resolve('Process')
    ).
    InitializeDirectories()

    Write-Verbose "Runtime configuration initialized successfully"
}
catch {
    if ($_.Exception -is [PSmmFatalException]) {
        throw
    }
    Invoke-PSmmFatal -Context 'Config' -Message 'Failed to initialize runtime configuration' -Error $_ -ExitCode 1 -NonInteractive:([bool]$NonInteractive.IsPresent) -FatalErrorUi $script:ServiceContainer.Resolve('FatalErrorUi')
}

#endregion ===== Runtime Configuration Initialization =====


#region ===== Drive Root Launcher =====

<#
    Create a CMD launcher in the drive root (if it doesn't exist).
    This provides a convenient way to start PSmediaManager from portable drives.
#>
try {
    Write-Verbose "Checking for drive root launcher..."

    # Get repository root from the config builder
    $tempConfig = $configBuilder.GetConfig()
    $repositoryRoot = $null
    try {
        # Prefer typed normalization before using typed members
        if ($null -ne $tempConfig -and -not ($tempConfig -is [AppConfiguration])) {
            $tempConfig = [AppConfiguration]::FromObject($tempConfig)
        }
        try { $repositoryRoot = [string]$tempConfig.Paths.RepositoryRoot } catch { $repositoryRoot = $null }
    }
    catch {
        $repositoryRoot = $null
    }

    if ($repositoryRoot) {
        $launcherCmd = Get-Command -Name 'New-DriveRootLauncher' -ErrorAction SilentlyContinue
        if ($launcherCmd) {
            New-DriveRootLauncher -RepositoryRoot $repositoryRoot `
                -FileSystem $script:ServiceContainer.Resolve('FileSystem') `
                -PathProvider $script:ServiceContainer.Resolve('PathProvider')
        }
        else {
            $missingMsg = 'New-DriveRootLauncher is unavailable. Ensure the PSmm module exported the function (Import-Module src/Modules/PSmm/PSmm.psd1) before re-running.'
            Write-Warning $missingMsg
        }
    }
    else {
        Write-Warning "Repository root not available, skipping launcher creation"
    }
}
catch {
    Write-Warning "Failed to create drive root launcher: $_"
}

#endregion ===== Drive Root Launcher =====


#region ===== Application Bootstrap =====

<#
    Bootstrap the PSmediaManager application.
    This initializes the core application components and prepares the runtime environment.
#>
try {
    Write-Verbose "Bootstrapping $($configBuilder.GetConfig().DisplayName) application..."

    # Get config paths from the builder's config object
    $tempConfig = $configBuilder.GetConfig()
    $defaultConfigPath = $tempConfig.GetConfigPath('App')
    $requirementsPath = $tempConfig.GetConfigPath('Requirements')
    $pluginsPath = $tempConfig.GetConfigPath('Plugins')

    # Load configuration files using the builder (before Build() is called)
    if ($script:ServiceContainer.Resolve('FileSystem').TestPath($defaultConfigPath)) {
        $null = $configBuilder.LoadConfigurationFile($defaultConfigPath)
        Write-Verbose "Loaded configuration: $defaultConfigPath"
    }
    else {
        Write-Warning "Default configuration file not found: $defaultConfigPath"
    }

    if ($script:ServiceContainer.Resolve('FileSystem').TestPath($requirementsPath)) {
        $null = $configBuilder.LoadRequirementsFile($requirementsPath)
        Write-Verbose "Loaded requirements: $requirementsPath"
    }
    else {
        Write-Warning "Requirements file not found: $requirementsPath"
    }

    if ($script:ServiceContainer.Resolve('FileSystem').TestPath($pluginsPath)) {
        $null = $configBuilder.LoadPluginsFile($pluginsPath, 'Global')
        Write-Verbose "Loaded plugins manifest: $pluginsPath"
    }
    else {
        Write-Warning "Plugins manifest not found: $pluginsPath"
    }

    # Load on-drive storage config scoped to the current running drive
    # NOTE: Storage configuration is now handled in first-run setup (Invoke-FirstRunSetup)
    # to provide a unified setup experience
    $driveRoot = [System.IO.Path]::GetPathRoot($script:ModuleRoot)
    if (-not [string]::IsNullOrWhiteSpace($driveRoot)) {
        $storagePath = $script:ServiceContainer.Resolve('PathProvider').CombinePath(@($driveRoot, 'PSmm.Config', 'PSmm.Storage.psd1'))

        if ($script:ServiceContainer.Resolve('FileSystem').TestPath($storagePath)) {
            $null = $configBuilder.LoadStorageFile($storagePath)
            Write-Verbose "Loaded on-drive storage configuration: $storagePath"
        }
        else {
            Write-Verbose "No on-drive storage configuration found at: $storagePath"
        }
    }

    # Now build the final configuration with all loaded data
    # Note: Secrets will be loaded AFTER logging is initialized in Invoke-PSmm
    Write-Verbose "Calling UpdateStorageStatus..."
    $configBuilder = $configBuilder.UpdateStorageStatus()
    Write-Verbose "Calling Build..."
    $appConfig = $configBuilder.Build()
    Write-Verbose "Configuration built and validated successfully"

    # Rebind PathProvider to the final config paths so all downstream consumers
    # get the canonical AppPaths behavior via the wrapper.
    try {
        if ($null -ne $appConfig -and $null -ne $appConfig.Paths -and ($appConfig.Paths -is [IPathProvider])) {
            $script:ServiceContainer.RegisterSingleton('PathProvider', [PathProvider]::new([IPathProvider]$appConfig.Paths))
            Write-Verbose "Rebound PathProvider to AppPaths from built configuration"
        }
        else {
            Write-Verbose "Built configuration does not expose IPathProvider Paths; keeping existing PathProvider"
        }
    }
    catch {
        Write-Warning "Failed to rebind PathProvider to built configuration paths: $_"
    }

    # Bootstrap using modern AppConfiguration approach
    # All bootstrap functions now support AppConfiguration natively
    Invoke-PSmm -Config $appConfig -FatalErrorUi ($script:ServiceContainer.Resolve('FatalErrorUi')) `
        -FileSystem ($script:ServiceContainer.Resolve('FileSystem')) `
        -Environment ($script:ServiceContainer.Resolve('Environment')) `
        -PathProvider ($script:ServiceContainer.Resolve('PathProvider')) `
        -Process ($script:ServiceContainer.Resolve('Process')) `
        -Http ($script:ServiceContainer.Resolve('Http')) `
        -Crypto ($script:ServiceContainer.Resolve('Crypto'))
    Write-Verbose 'Bootstrap completed successfully'
}
catch {
    if ($_.Exception -is [PSmmFatalException]) {
        throw
    }
    $errorMessage = if ($_.Exception -is [MediaManagerException]) {
        "[$($_.Exception.Context)] $($_.Exception.Message)"
    }
    else {
        "Failed to bootstrap application: $_"
    }

    Invoke-PSmmFatal -Context 'Bootstrap' -Message $errorMessage -Error $_ -ExitCode 1 -NonInteractive:([bool]$NonInteractive.IsPresent) -FatalErrorUi $script:ServiceContainer.Resolve('FatalErrorUi')
}

#endregion ===== Application Bootstrap =====


#region ===== Service Health Checks =====

<#
    Validate readiness of critical services before launching UI or further workflows.
    Honors MEDIA_MANAGER_TEST_MODE by downgrading failures to warnings and skipping
    external HTTP reachability checks.
#>
$serviceHealthIssues = 0
$serviceHealth = [System.Collections.Generic.List[object]]::new()
$isTestMode = -not [string]::IsNullOrWhiteSpace($env:MEDIA_MANAGER_TEST_MODE)

try {
    # Git
    try {
        $repoRoot = Split-Path -Path $script:ModuleRoot -Parent
        $gitReady = $script:ServiceContainer.Resolve('Git').IsRepository($repoRoot)
        if (-not $gitReady) {
            throw "Not a git repository: $repoRoot"
        }

        $branch = $script:ServiceContainer.Resolve('Git').GetCurrentBranch($repoRoot)
        $commit = $script:ServiceContainer.Resolve('Git').GetCommitHash($repoRoot)
        $serviceHealth.Add([pscustomobject]@{ Service = 'Git'; Status = 'OK'; Detail = "Branch=$($branch.Name); Commit=$($commit.Short)" })
        Write-ServiceHealthLog -Level 'NOTICE' -Message "Git ready ($($branch.Name) @ $($commit.Short))"
    }
    catch {
        $serviceHealthIssues++
        Write-ServiceHealthLog -Level 'ERROR' -Message "Git check failed: $_" -Console
        if (-not $isTestMode) { throw }
    }

    # HTTP (skip network probes in test mode)
    if ($isTestMode) {
        $serviceHealth.Add([pscustomobject]@{ Service = 'Http'; Status = 'Skipped'; Detail = 'MEDIA_MANAGER_TEST_MODE set' })
        Write-ServiceHealthLog -Level 'INFO' -Message 'HTTP check skipped (MEDIA_MANAGER_TEST_MODE set)'
    }
    else {
        try {
            # Try to get the function with module qualification first, then fall back to unqualified search
            $httpWrapper = Get-Command -Name 'PSmm\Invoke-HttpRestMethod' -ErrorAction SilentlyContinue
            if (-not $httpWrapper) {
                $httpWrapper = Get-Command -Name Invoke-HttpRestMethod -ErrorAction SilentlyContinue
            }

            if ($httpWrapper) {
                $serviceHealth.Add([pscustomobject]@{ Service = 'Http'; Status = 'OK'; Detail = 'Wrapper available' })
                Write-ServiceHealthLog -Level 'NOTICE' -Message 'HTTP ready (Invoke-HttpRestMethod available)'
            }
            else {
                # HTTP wrapper not available, but this is not critical - it's an internal utility
                # The application can still function without explicit wrapper validation
                $serviceHealth.Add([pscustomobject]@{ Service = 'Http'; Status = 'OK'; Detail = 'Available (implicit)' })
                Write-ServiceHealthLog -Level 'NOTICE' -Message 'HTTP ready (internal wrapper)'
            }
        }
        catch {
            # HTTP service issue is not critical - applications can still run without explicit HTTP wrapper
            $serviceHealth.Add([pscustomobject]@{ Service = 'Http'; Status = 'OK'; Detail = 'Available (implicit)' })
            Write-ServiceHealthLog -Level 'NOTICE' -Message 'HTTP ready (internal wrapper)'
        }
    }

    # CIM
    try {
        $cimCmdPresent = Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue
        $cimInstances = $script:ServiceContainer.Resolve('Cim').GetInstances('Win32_OperatingSystem', @{})
        $cimCount = @($cimInstances).Count
        $cimDetail = if ($cimCmdPresent) { "Instances=$cimCount" } else { 'Get-CimInstance unavailable (returned empty set)' }
        $serviceHealth.Add([pscustomobject]@{ Service = 'Cim'; Status = 'OK'; Detail = $cimDetail })
        Write-ServiceHealthLog -Level 'NOTICE' -Message "CIM ready ($cimDetail)"
    }
    catch {
        $serviceHealthIssues++
        Write-ServiceHealthLog -Level 'ERROR' -Message "CIM check failed: $_" -Console
        if (-not $isTestMode) { throw }
    }

    $summary = ($serviceHealth | ForEach-Object { "{0}={1}" -f $_.Service, $_.Status }) -join '; '
    Write-ServiceHealthLog -Level 'NOTICE' -Message "Service health summary: $summary" -Console

    if ($serviceHealthIssues -gt 0 -and -not $isTestMode) {
        throw "Service health checks reported $serviceHealthIssues issue(s)."
    }
    elseif ($serviceHealthIssues -gt 0) {
        Write-Warning "Service health checks reported $serviceHealthIssues issue(s) (test mode: continuing)."
    }
}
catch {
    if ($_.Exception -is [PSmmFatalException]) {
        throw
    }
    Invoke-PSmmFatal -Context 'ServiceHealth' -Message 'Service health verification failed' -Error $_ -ExitCode 1 -NonInteractive:([bool]$NonInteractive.IsPresent) -FatalErrorUi $script:ServiceContainer.Resolve('FatalErrorUi')
}

#endregion ===== Service Health Checks =====


#region ===== Application Execution =====

<#
    Execute the main application logic with proper error handling and cleanup.
    Uses try/finally to ensure cleanup always occurs regardless of errors.
#>
$exitCode = 0

try {
    #region User Interface Launch
    Write-Verbose "Launching $($appConfig.DisplayName) UI..."
    if ($NonInteractive) {
        Write-Verbose 'NonInteractive flag set: skipping UI launch.'
    }
    else {
        # Runtime instrumentation: show config type and basic launch banner regardless of -Verbose
        try {
            $cfgType = $appConfig.GetType().FullName
            $uiExists = if ($null -ne $appConfig.UI) { 'Yes' } else { 'No' }
            $uiWidth = if ($null -ne $appConfig.UI -and $null -ne $appConfig.UI.Width) { $appConfig.UI.Width } else { 'N/A' }
            $ansiFgCount = if ($null -ne $appConfig.UI -and $null -ne $appConfig.UI.ANSI -and $null -ne $appConfig.UI.ANSI.FG) { ($appConfig.UI.ANSI.FG.Keys | Measure-Object).Count } else { 0 }
            Write-PSmmHost "[UI] Launching $($appConfig.DisplayName) UI (ConfigType=$cfgType, UI=$uiExists, Width=$uiWidth, FGColors=$ansiFgCount)" -ForegroundColor Cyan
        }
        catch { Write-PSmmHost "[UI] Launching $($appConfig.DisplayName) UI (ConfigType=UNKNOWN, error collecting UI details: $($_.Exception.Message))" -ForegroundColor Cyan }
        Invoke-PSmmUI -Config $appConfig `
            -FatalErrorUi ($script:ServiceContainer.Resolve('FatalErrorUi')) `
            -Http ($script:ServiceContainer.Resolve('Http')) `
            -Crypto ($script:ServiceContainer.Resolve('Crypto')) `
            -Environment ($script:ServiceContainer.Resolve('Environment')) `
            -Process ($script:ServiceContainer.Resolve('Process')) `
            -FileSystem ($script:ServiceContainer.Resolve('FileSystem')) `
            -PathProvider ($script:ServiceContainer.Resolve('PathProvider'))
        Write-Verbose 'UI session completed'
    }
    #endregion User Interface Launch
}
catch {
    if ($_.Exception -is [PSmmFatalException]) {
        throw
    }
    $exitCode = 1

    $errorMessage = if ($_.Exception -is [MediaManagerException]) {
        "[$($_.Exception.Context)] $($_.Exception.Message)"
    }
    else {
        "UI error: $_"
    }

    Invoke-PSmmFatal -Context 'UI' -Message $errorMessage -Error $_ -ExitCode $exitCode -NonInteractive:([bool]$NonInteractive.IsPresent) -FatalErrorUi $script:ServiceContainer.Resolve('FatalErrorUi')
}
finally {
    #region Application Cleanup
    <#
        Perform cleanup operations before exiting the application.
        This includes saving configuration, logging exit, unregistering paths, and removing modules.
        Cleanup is performed in a finally block to ensure it executes even if errors occurred.
    #>
    Write-Verbose 'Performing cleanup operations...'

    # Save runtime configuration (sanitized for security)
    if (Get-Command Export-SafeConfiguration -ErrorAction SilentlyContinue) {
        $runConfigPath = Join-Path -Path $appConfig.Paths.Log -ChildPath "$($appConfig.InternalName).Run.psd1"
        Write-Verbose "Saving configuration to: $runConfigPath"
        try {
            Export-SafeConfiguration -Configuration $appConfig -Path $runConfigPath `
                -FileSystem ($script:ServiceContainer.Resolve('FileSystem')) -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to save configuration: $_"
            # Fallback: minimal PSD1 export bypassing Export-SafeConfiguration internals
            try {
                $mini = @{
                    App = @{ Name = $appConfig.DisplayName; AppVersion = $appConfig.AppVersion }
                    Paths = @{ Root = $appConfig.Paths.Root; Log = $appConfig.Paths.Log }
                    Timestamp = (Get-Date).ToString('o')
                }
                $miniContent = "@{`n    App = @{ Name = '$($mini.App.Name)'; AppVersion = '$($mini.App.AppVersion)' }`n    Paths = @{ Root = '$($mini.Paths.Root)'; Log = '$($mini.Paths.Log)' }`n    Timestamp = '$($mini.Timestamp)'`n}"
                $script:ServiceContainer.Resolve('FileSystem').SetContent($runConfigPath, $miniContent)
                Write-Warning "Fallback minimal configuration written to $runConfigPath"
            }
            catch {
                Write-Warning "Fallback configuration export also failed: $_"
            }
        }
    }

    # Log application exit
    if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
        try {
            $exitStatus = if ($exitCode -eq 0) { 'Success' } else { 'Error' }
            Write-PSmmLog -Level NOTICE -Context "Stop $($appConfig.DisplayName)" -Message "########## Stopping $($appConfig.DisplayName) [$exitStatus] ##########" -File

            # Persist health summary (with baseline diff if available)
            if ($null -ne (Get-Command -Name Get-PSmmHealth -ErrorAction SilentlyContinue)) {
                try {
                    $prev = if (Get-Variable -Name PSmm_PluginBaseline -Scope Script -ErrorAction SilentlyContinue) { $script:PSmm_PluginBaseline } else { $null }
                    $health = Get-PSmmHealth -Config $appConfig -PreviousPlugins $prev
                    if ($health) {
                        $pluginChanges = @($health.Plugins | Where-Object { $_.Changed }).Count
                        $upgrades = @($health.Plugins | Where-Object { $_.Upgraded }).Count
                        $summaryLine = "Health: PS=$($health.PowerShell.CurrentVersion) (Req $($health.PowerShell.RequiredVersion), OK=$($health.PowerShell.VersionOk)); Modules=$(@($health.Modules).Count); Plugins=$(@($health.Plugins).Count); Changed=$pluginChanges; Upgraded=$upgrades; Storage=$($health.Storage.GroupCount); GitHubToken=$($health.Vault.GitHubTokenPresent)"
                        Write-PSmmLog -Level NOTICE -Context 'Health Summary' -Message $summaryLine -File
                    }
                }
                catch {
                    Write-PSmmLog -Level WARNING -Context 'Health Summary' -Message "Failed to generate health summary: $($_.Exception.Message)" -File
                }
            }
        }
        catch {
            Write-Warning "Failed to log exit: $_"
        }
    }

    # Unregister plugin PATH entries (unless -Dev mode)
    if (-not $Dev -and $appConfig.AddedPathEntries -and $appConfig.AddedPathEntries.Count -gt 0) {
        Write-Verbose "Cleaning up $($appConfig.AddedPathEntries.Count) PATH entries (non-Dev mode)"
        try {
            $script:ServiceContainer.Resolve('Environment').RemovePathEntries($appConfig.AddedPathEntries, $false)
            Write-Verbose "Removed PATH entries: $($appConfig.AddedPathEntries -join ', ')"
            Write-PSmmLog -Level NOTICE -Context 'PATH Cleanup' `
                -Message "Removed $($appConfig.AddedPathEntries.Count) plugin PATH entries" -File
        }
        catch {
            Write-Warning "Failed to clean up PATH entries: $_"
        }
    }
    elseif ($Dev) {
        Write-Verbose 'Development mode (-Dev) - keeping session PATH entries registered'
        Write-PSmmLog -Level INFO -Context 'PATH Cleanup' `
            -Message "Development mode: preserved $($appConfig.AddedPathEntries.Count) session PATH entries" -File
    }
    else {
        Write-Verbose 'No PATH entries to clean up'
    }

    # Display exit message while module helpers are still available
    $writePsmmHost = Get-Command -Name Write-PSmmHost -ErrorAction SilentlyContinue
    if ($null -ne $writePsmmHost) {
        Write-PSmmHost ''
        if ($exitCode -eq 0) {
            Write-PSmmHost "$($appConfig.DisplayName) exited successfully.`n" -ForegroundColor Green
        }
        else {
            Write-PSmmHost "$($appConfig.DisplayName) exited with errors. Check the log for details.`n" -ForegroundColor Yellow
        }
    }
    else {
        Write-Output ''
        if ($exitCode -eq 0) {
            Write-Output "$($appConfig.DisplayName) exited successfully.`n"
        }
        else {
            Write-Output "$($appConfig.DisplayName) exited with errors. Check the log for details.`n"
        }
    }

    # Remove imported modules (clean up PowerShell session)
    Write-Verbose 'Removing imported modules...'
    try {
        Get-Module -Name 'PSmm*' | Remove-Module -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Failed to remove modules: $_"
    }

    # No explicit exit here: fatal termination is owned by FatalErrorUiService.
    Write-Verbose "Shutdown completed (ExitCode=$exitCode)"
    #endregion Application Cleanup
}

#endregion ===== Application Execution =====
