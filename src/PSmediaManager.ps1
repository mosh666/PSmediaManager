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
    Enables development mode, which keeps environment paths registered after exit.
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

#region ===== Early Service Initialization =====

<#
    Load core service/interface definitions before module imports so we can use
    dependency-injected services for path and file operations during module loading.
    (Option B refactor)
#>
try {
    $coreServicesPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Core/BootstrapServices.ps1'
    if (-not (Test-Path -Path $coreServicesPath)) {
        throw "Core services file not found: $coreServicesPath"
    }
    . $coreServicesPath
    Write-Verbose "Loaded core bootstrap services definitions"
}
catch {
    Write-Error "Failed to load core bootstrap services: $_" -ErrorAction Stop
}

try {
    Write-Verbose "Instantiating early services for module loading..."
    $script:Services = @{
        FileSystem   = [FileSystemService]::new()
        Environment  = [EnvironmentService]::new()
        PathProvider = [PathProvider]::new()
        Process      = [ProcessService]::new()
    }
    Write-Verbose "Early services instantiated"
}
catch {
    Write-Error "Failed to instantiate early services: $_" -ErrorAction Stop
}

#endregion ===== Early Service Initialization =====

#region ===== Module Imports =====

<#
    Import all PSmediaManager modules from the Modules directory.
    Modules are imported in dependency order to ensure proper loading.
    The core PSmm module must be imported FIRST as it contains the classes
    needed for configuration and other modules.
#>
try {
    # Calculate modules path using PathProvider
    $modulesPath = $script:Services.PathProvider.CombinePath(@($script:ModuleRoot, 'Modules'))
    Write-Verbose "Importing modules from: $modulesPath"

    # Define module load order (dependencies first)
    $moduleLoadOrder = @(
        'PSmm',              # Core module (contains classes and base functions)
        'PSmm.Logging',      # Logging functionality
        'PSmm.Plugins',      # External plugin orchestration and digiKam helpers
        'PSmm.Projects',     # Project management
        'PSmm.UI'            # User interface (depends on all others)
    )

    $loadedModules = 0
    foreach ($moduleName in $moduleLoadOrder) {
        $moduleFolder = $script:Services.PathProvider.CombinePath(@($modulesPath, $moduleName))
        $manifestPath = $script:Services.PathProvider.CombinePath(@($moduleFolder, "$moduleName.psd1"))

        if ($script:Services.FileSystem.TestPath($manifestPath)) {
            try {
                Write-Verbose "Importing module: $moduleName"
                # Removed -Global flag for proper module scoping
                Import-Module -Name $manifestPath -Force -ErrorAction Stop -Verbose:($VerbosePreference -eq 'Continue')
                $loadedModules++
            }
            catch {
                # Wrap the original error to preserve inner exception details without relying on module-defined types
                $innerEx = if ($_.Exception) { $_.Exception } else { $_ }
                throw [System.Exception]::new("Failed to import module '$moduleName'", $innerEx)
            }
        }
        else {
            Write-Warning "Module manifest not found: $manifestPath"
        }
    }

    if ($loadedModules -eq 0) {
        throw "No modules were loaded from: $modulesPath"
    }

    Write-Verbose "Successfully imported $loadedModules module(s)"
}
catch {
    $innerMsg = if ($_.Exception -and $_.Exception.InnerException) { $_.Exception.InnerException.Message } elseif ($_.Exception) { $_.Exception.Message } else { $null }
    if ($innerMsg) {
        Write-Error "Failed to import modules: $($_.Exception.Message) | Inner: $innerMsg"
    }
    else {
        Write-Error "Failed to import modules: $_"
    }
    exit 1
}

#endregion ===== Module Imports =====


#region ===== Service Instantiation (Full Set) =====

<#
    Instantiate service implementations for dependency injection.
    These services provide testable abstractions over system operations.
#>
try {
    Write-Verbose "Extending early services with remaining implementations..."
    $script:Services.Http    = [HttpService]::new()
    $script:Services.Crypto  = [CryptoService]::new()
    $script:Services.Cim     = [CimService]::new()
    $script:Services.Storage = [StorageService]::new()
    $script:Services.Git     = [GitService]::new()
    Write-Verbose "Full service layer available"
}
catch {
    Write-Error "Failed to extend service layer: $_"
    exit 1
}

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
    WithParameters($runtimeParams).
    WithVersion([version]'1.0.0').
    WithServices($script:Services.FileSystem, $script:Services.Environment, $script:Services.PathProvider, $script:Services.Process).
    InitializeDirectories()

    Write-Verbose "Runtime configuration initialized successfully"
}
catch {
    Write-Error "Failed to initialize runtime configuration: $_"
    exit 1
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
    $repositoryRoot = $tempConfig.Paths.RepositoryRoot

    if ($repositoryRoot) {
        $launcherCmd = Get-Command -Name 'New-DriveRootLauncher' -ErrorAction SilentlyContinue
        if ($launcherCmd) {
            New-DriveRootLauncher -RepositoryRoot $repositoryRoot -FileSystem $script:Services.FileSystem -PathProvider $script:Services.PathProvider
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

    # Load configuration files using the builder (before Build() is called)
    if ($script:Services.FileSystem.TestPath($defaultConfigPath)) {
        $null = $configBuilder.LoadConfigurationFile($defaultConfigPath)
        Write-Verbose "Loaded configuration: $defaultConfigPath"
    }
    else {
        Write-Warning "Default configuration file not found: $defaultConfigPath"
    }

    if ($script:Services.FileSystem.TestPath($requirementsPath)) {
        $null = $configBuilder.LoadRequirementsFile($requirementsPath)
        Write-Verbose "Loaded requirements: $requirementsPath"
    }
    else {
        Write-Warning "Requirements file not found: $requirementsPath"
    }

    # Load on-drive storage config scoped to the current running drive
    # NOTE: Storage configuration is now handled in first-run setup (Invoke-FirstRunSetup)
    # to provide a unified setup experience
    $driveRoot = [System.IO.Path]::GetPathRoot($script:ModuleRoot)
    if (-not [string]::IsNullOrWhiteSpace($driveRoot)) {
        $storagePath = $script:Services.PathProvider.CombinePath(@($driveRoot, 'PSmm.Config', 'PSmm.Storage.psd1'))

        if ($script:Services.FileSystem.TestPath($storagePath)) {
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
    Write-Verbose "Configuration built successfully"

    # Bootstrap using modern AppConfiguration approach
    # All bootstrap functions now support AppConfiguration natively
    Invoke-PSmm -Config $appConfig
    Write-Verbose 'Bootstrap completed successfully'
}
catch {
    $errorMessage = if ($_.Exception -is [MediaManagerException]) {
        "[$($_.Exception.Context)] $($_.Exception.Message)"
    }
    else {
        "Failed to bootstrap application: $_"
    }

    Write-Error $errorMessage

    # Attempt to log the error if logging is initialized
    if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
        Write-PSmmLog -Level ERROR -Context 'Bootstrap' -Message $errorMessage -Console -File
    }

    exit 1
}

#endregion ===== Application Bootstrap =====


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
            $uiWidth = if ($null -ne $appConfig.UI -and $appConfig.UI.ContainsKey('Width')) { $appConfig.UI.Width } else { 'N/A' }
            $ansiFgCount = if ($null -ne $appConfig.UI -and $appConfig.UI.ContainsKey('ANSI') -and $appConfig.UI.ANSI.ContainsKey('FG')) { ($appConfig.UI.ANSI.FG.Keys | Measure-Object).Count } else { 0 }
            Write-PSmmHost "[UI] Launching $($appConfig.DisplayName) UI (ConfigType=$cfgType, UI=$uiExists, Width=$uiWidth, FGColors=$ansiFgCount)" -ForegroundColor Cyan
        }
        catch { Write-PSmmHost "[UI] Launching $($appConfig.DisplayName) UI (ConfigType=UNKNOWN, error collecting UI details: $($_.Exception.Message))" -ForegroundColor Cyan }
        Invoke-PSmmUI -Config $appConfig -Process $script:Services.Process -FileSystem $script:Services.FileSystem -PathProvider $script:Services.PathProvider
        Write-Verbose 'UI session completed'
    }
    #endregion User Interface Launch
}
catch {
    $exitCode = 1

    $errorMessage = if ($_.Exception -is [MediaManagerException]) {
        "[$($_.Exception.Context)] $($_.Exception.Message)"
    }
    else {
        "UI error: $_"
    }

    Write-Error $errorMessage

    # Log the error
    if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
        try {
            Write-PSmmLog -Level ERROR -Context 'UI' -Message $errorMessage -Console -File
        }
        catch {
            Write-Warning "Failed to log UI error: $_"
        }
    }
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
            Export-SafeConfiguration -Configuration $appConfig -Path $runConfigPath -FileSystem $script:Services.FileSystem -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to save configuration: $_"
            # Fallback: minimal PSD1 export bypassing Export-SafeConfiguration internals
            try {
                $mini = @{
                    App = @{ Name = $appConfig.DisplayName; Version = $appConfig.AppVersion }
                    Paths = @{ Root = $appConfig.Paths.Root; Log = $appConfig.Paths.Log }
                    Timestamp = (Get-Date).ToString('o')
                }
                $miniContent = "@{`n    App = @{ Name = '$($mini.App.Name)'; Version = '$($mini.App.Version)' }`n    Paths = @{ Root = '$($mini.Paths.Root)'; Log = '$($mini.Paths.Log)' }`n    Timestamp = '$($mini.Timestamp)'`n}"
                $script:Services.FileSystem.SetContent($runConfigPath, $miniContent)
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
                        $summaryLine = "Health: PS=$($health.PowerShell.Current) (Req $($health.PowerShell.Required), OK=$($health.PowerShell.VersionOk)); Modules=$(@($health.Modules).Count); Plugins=$(@($health.Plugins).Count); Changed=$pluginChanges; Upgraded=$upgrades; Storage=$(@($health.Storage).Count); GitHubToken=$($health.Vault.GitHubTokenPresent)"
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
            $script:Services.Environment.RemovePathEntries($appConfig.AddedPathEntries, $false)
            Write-Verbose "Removed PATH entries: $($appConfig.AddedPathEntries -join ', ')"
            Write-PSmmLog -Level NOTICE -Context 'PATH Cleanup' `
                -Message "Removed $($appConfig.AddedPathEntries.Count) plugin PATH entries" -File
        }
        catch {
            Write-Warning "Failed to clean up PATH entries: $_"
        }
    }
    elseif ($Dev) {
        Write-Verbose 'Development mode (-Dev) - keeping plugin PATH entries registered'
        Write-PSmmLog -Level INFO -Context 'PATH Cleanup' `
            -Message "Development mode: preserved $($appConfig.AddedPathEntries.Count) PATH entries" -File
    }
    else {
        Write-Verbose 'No PATH entries to clean up'
    }

    # Display exit message while module helpers are still available
    Write-PSmmHost ''
    if ($exitCode -eq 0) {
        Write-PSmmHost "$($appConfig.DisplayName) exited successfully.`n" -ForegroundColor Green
    }
    else {
        Write-PSmmHost "$($appConfig.DisplayName) exited with errors. Check the log for details.`n" -ForegroundColor Yellow
    }

    # Remove imported modules (clean up PowerShell session)
    Write-Verbose 'Removing imported modules...'
    try {
        Get-Module -Name 'PSmm*' | Remove-Module -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Failed to remove modules: $_"
    }

    # Exit with appropriate code
    Write-Verbose "Exiting with code: $exitCode"
    exit $exitCode
    #endregion Application Cleanup
}

#endregion ===== Application Execution =====
