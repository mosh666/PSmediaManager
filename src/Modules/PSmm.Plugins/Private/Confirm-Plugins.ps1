<#
 .SYNOPSIS
    Plugin management and validation functions for PSmediaManager.
<#$
.SYNOPSIS
    Checks if a plugin update is available.
<#$
.SYNOPSIS
    Checks if a plugin update is available.

.DESCRIPTION
    Compares the current installed version with the latest available version
    and logs the result.

.PARAMETER Plugin
    Plugin configuration hashtable with State.CurrentVersion and State.LatestVersion.
.SYNOPSIS
    Updates a plugin to the latest version.
<#$
.SYNOPSIS
    Updates a plugin to the latest version.

.DESCRIPTION
    Prompts user for confirmation, removes old version, and installs the
    latest version.

.PARAMETER Plugin
    Plugin configuration hashtable.
function ConvertTo-ModuleSecureString {
    [CmdletBinding()]
    [OutputType([SecureString])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )

    $secure = [System.Security.SecureString]::new()
    foreach ($char in $Value.ToCharArray()) {
        $secure.AppendChar($char)
    }
    $secure.MakeReadOnly()
    return $secure
}

<#
.SYNOPSIS
    Tests whether a plugin-specific helper function exists within the module scope.
#>
function Test-PluginFunction {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    try {
        $cmd = $ExecutionContext.SessionState.InvokeCommand.GetCommand(
            $Name,
            [System.Management.Automation.CommandTypes]::Function
        )
        return $null -ne $cmd
    }
    catch {
        return $false
    }
}

function Get-ResolvedPluginCommands {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Paths
    )

    if (-not $Paths.ContainsKey('Commands') -or $null -eq $Paths.Commands) {
        $Paths.Commands = @{}
    }

    return $Paths.Commands
}

function Set-ResolvedPluginCommandPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Paths,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandPath
    )

    $commands = Get-ResolvedPluginCommands -Paths $Paths

    if ($commands.ContainsKey($CommandName) -and $commands[$CommandName] -eq $CommandPath) {
        return
    }

    $commands[$CommandName] = $CommandPath
    Write-Verbose "Resolved $CommandName at: $CommandPath"
    Write-PSmmLog -Level INFO -Context 'Confirm-Plugins' `
        -Message "Resolved $CommandName at $CommandPath" -Console -File
}

function Resolve-PluginCommandPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Paths,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DefaultCommand,

        [Parameter(Mandatory)]
        $Process
    )

    $commands = Get-ResolvedPluginCommands -Paths $Paths

    if ($commands.ContainsKey($CommandName)) {
        return $commands[$CommandName]
    }

    if ($Process.TestCommand($DefaultCommand)) {
        Set-ResolvedPluginCommandPath -Paths $Paths -CommandName $CommandName -CommandPath $DefaultCommand
        return $DefaultCommand
    }

    $exeFilter = "$CommandName.exe"
    $candidate = Get-ChildItem -LiteralPath $Paths.Root -Recurse -Filter $exeFilter -File -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($candidate) {
        $resolvedPath = $candidate.FullName
        Set-ResolvedPluginCommandPath -Paths $Paths -CommandName $CommandName -CommandPath $resolvedPath
        return $resolvedPath
    }

    throw "Command '$CommandName' not found in PATH or under $($Paths.Root)"
}

<#
.SYNOPSIS
    Creates PSmm service instances while ensuring core types are available.
.DESCRIPTION
    Executes constructor in global scope where PSmm classes are defined via ScriptsToProcess.
#>
function New-PSmmServiceInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TypeName
    )

    try {
        Write-Verbose "[New-PSmmServiceInstance] Creating instance of $TypeName via global scope"
        # Use & with script block defined in global scope
        $global:__tempConstructor = [scriptblock]::Create("[$TypeName]::new()")
        $instance = & $global:__tempConstructor
        Remove-Variable -Name __tempConstructor -Scope Global -ErrorAction SilentlyContinue

        if ($null -eq $instance) {
            throw "Constructor returned null"
        }

        return $instance
    }
    catch {
        $psmmInfo = Get-Module -Name 'PSmm'
        $psmmStatus = if ($psmmInfo) { "loaded v$($psmmInfo.Version)" } else { "not loaded" }
        throw "Unable to instantiate [$TypeName]. PSmm module is $psmmStatus. Error: $_"
    }
}

<#
.SYNOPSIS
    Confirms all required external plugins are installed and up to date.

.DESCRIPTION
    Validates external plugin installations, downloads missing plugins,
    and optionally updates existing plugins to the latest versions.

.PARAMETER Config
    Application configuration object (AppConfiguration).
    Preferred modern approach with strongly-typed configuration.


.PARAMETER Http
    HTTP service for downloading plugins and GitHub API access.

.PARAMETER FileSystem
    File system service for path operations and file management.

.PARAMETER Process
    Process service for executing plugin version checks.

.EXAMPLE
    Confirm-Plugins -Config $appConfig
    Validates plugins using modern AppConfiguration object.


#>
function Confirm-Plugins {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function manages multiple plugins')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Config,

        [Parameter(Mandatory)]
        $Http,

        [Parameter(Mandatory)]
        $Crypto,

        [Parameter(Mandatory)]
        $FileSystem,

        [Parameter(Mandatory)]
        $Process
    )

    # Adapt typed Config into internal hashtable for helper reuse
    $Run = @{
        App = @{
            Paths = @{
                App = @{
                    Plugins = @{
                        Root = $Config.Paths.App.Plugins.Root
                        _Downloads = $Config.Paths.App.Plugins.Downloads
                        _Temp = $Config.Paths.App.Plugins.Temp
                        Commands = @{}
                    }
                    Vault = $Config.Paths.App.Vault
                }
            }
            Parameters = @{
                Update = $Config.Parameters.Update
            }
            Requirements = @{
                Plugins = $Config.Requirements.Plugins
            }
            Secrets = @{
                GitHub = @{}
            }
        }
    }

    try {
        $paths = $Run.App.Paths.App.Plugins
        Get-ResolvedPluginCommands -Paths $paths | Out-Null
        $updateMode = $Run.App.Parameters.Update

        Write-Verbose "Starting plugin confirmation (Update mode: $updateMode)"

        # GitHub token is managed via KeePassXC; no file-path fallback is needed

        # Iterate through plugin groups (a_GitEnv, b_ExifTool, etc.)
        $pluginGroups = $Run.App.Requirements.Plugins.GetEnumerator() | Sort-Object -Property Name

        foreach ($pluginGroup in $pluginGroups) {
            $scopeName = $pluginGroup.Name.Substring(2)  # Remove prefix (e.g., "a_")
            Write-PSmmLog -Level NOTICE -Context "Confirm $scopeName" `
                -Message "Checking for $scopeName plugins" -Console -File

            # Iterate through plugins in this group
            $pluginsInGroup = $pluginGroup.Value.GetEnumerator() | Sort-Object -Property Name

            foreach ($pluginEntry in $pluginsInGroup) {
                $plugin = @{
                    Key = $pluginEntry.Key
                    Config = $pluginEntry.Value
                }

                Invoke-PluginConfirmation -Config $Config -Plugin $plugin -Paths $paths -Run $Run -ScopeName $scopeName -UpdateMode $updateMode -Http $Http -Crypto $Crypto -FileSystem $FileSystem -Process $Process
            }
        }

        # Cleanup temporary files
        #$tempPath = Join-Path -Path $paths._Temp -ChildPath '*'
        #if ($FileSystem.TestPath($tempPath)) {
        #    $FileSystem.RemoveItem($tempPath, $true)
        #    Write-Verbose 'Cleaned up temporary files'
        #}

        Write-PSmmLog -Level NOTICE -Context 'Confirm-Plugins' `
            -Message 'All required plugins are confirmed' -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Confirm-Plugins' `
            -Message 'Failed to confirm plugins' -ErrorRecord $_ -Console -File
        throw
    }
}

<#
.SYNOPSIS
    Ensures GitHub token is available for API access.

.PARAMETER Run
    Runtime configuration hashtable.

.PARAMETER FileSystem
    File system service (injectable for testing).
#>

<#
.SYNOPSIS
    Processes a single plugin (check, install, or update).

.PARAMETER Plugin
    Plugin hashtable with Key and Config properties.

.PARAMETER Paths
    Paths configuration hashtable.

.PARAMETER Run
    Runtime configuration hashtable.

.PARAMETER ScopeName
    Plugin group name for logging.

.PARAMETER UpdateMode
    Whether to check for and apply updates.

.PARAMETER Http
    HTTP service (injectable for testing).

.PARAMETER FileSystem
    File system service (injectable for testing).

.PARAMETER Process
    Process service (injectable for testing).
#>
function Invoke-PluginConfirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Plugin,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Paths,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Run,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScopeName,

        [Parameter(Mandatory)]
        [bool]$UpdateMode,

        [Parameter(Mandatory)]
        $Http,

        [Parameter(Mandatory)]
        $Crypto,

        [Parameter(Mandatory)]
        $FileSystem,

        [Parameter(Mandatory)]
        $Process
    )

    if (-not ($Config | Get-Member -Name 'Paths' -ErrorAction SilentlyContinue)) {
        throw 'Invoke-PluginConfirmation requires a configuration object exposing Paths; received incompatible type.'
    }

    $pluginName = $Plugin.Config.Name
    Write-PSmmLog -Level INFO -Context "Confirm $ScopeName" `
        -Message "Confirming $pluginName" -Console -File

    # Get initial install state
    $state = Get-InstallState -Plugin $Plugin -Paths $Paths -FileSystem $FileSystem -Process $Process
    $Plugin.Config.State = $state

    # Store state in Run configuration
    $scopeKey = $Run.App.Requirements.Plugins.GetEnumerator() |
        Where-Object { $_.Name.Substring(2) -eq $ScopeName } |
        Select-Object -ExpandProperty Name -First 1

    if ($scopeKey) {
        $Run.App.Requirements.Plugins.$scopeKey.$($Plugin.Key).State = $state
    }

    # Handle installation or update
    if ([string]::IsNullOrEmpty($state.CurrentVersion)) {
        Write-PSmmLog -Level WARNING -Context "Check $pluginName" `
            -Message "$pluginName is not installed" -Console -File
        Install-Plugin -Plugin $Plugin -Paths $Paths -Config $Config -Http $Http -Crypto $Crypto -FileSystem $FileSystem -Process $Process
    }
    else {
        Write-PSmmLog -Level SUCCESS -Context "Check $pluginName" `
            -Message "$pluginName is installed: $($state.CurrentVersion)" -Console -File

        if ($UpdateMode) {
            $updateAvailable = Request-PluginUpdate -Plugin $Plugin -Paths $Paths -Config $Config -Http $Http -Crypto $Crypto -FileSystem $FileSystem -Process $Process

            if ($updateAvailable) {
                Write-PSmmLog -Level INFO -Context "Check $pluginName" `
                    -Message "Update requested for $pluginName" -Console -File
                Update-Plugin -Plugin $Plugin -Paths $Paths -Config $Config -Http $Http -Crypto $Crypto -FileSystem $FileSystem -Process $Process
            }
        }
    }

    # Refresh install state after changes
    $state = Get-InstallState -Plugin $Plugin -Paths $Paths -FileSystem $FileSystem -Process $Process
    $Plugin.Config.State = $state

    if ($scopeKey) {
        $Run.App.Requirements.Plugins.$scopeKey.$($Plugin.Key).State = $state
    }
}

<#
.SYNOPSIS
    Determines the installation state of a plugin.

.DESCRIPTION
    Checks if a plugin is installed, locates its installation path, and detects
    the current version. Supports custom version detection functions.

.PARAMETER Plugin
    Plugin configuration hashtable containing Config with Name property.

.PARAMETER Paths
    Paths configuration hashtable with Root and _Downloads properties.

.PARAMETER FileSystem
    File system service (injectable for testing).

.PARAMETER Process
    Process service (injectable for testing).

.OUTPUTS
    Hashtable with CurrentVersion and CurrentInstaller properties.

.NOTES
    - Supports custom version detection via Get-CurrentVersion-{PluginName} functions
    - Falls back to directory name for version if no custom function exists
#>
function Get-InstallState {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Plugin,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Paths,

        [Parameter()]
        $FileSystem,

        [Parameter()]
        $Process
    )

    # Lazy instantiation to avoid parse-time type resolution

    $state = @{
        CurrentVersion = ''
        CurrentInstaller = ''
    }

    try {
        $pluginName = $Plugin.Config.Name
        Write-Verbose "Getting install state for: $pluginName"

        # Check if plugin is installed
        $installPath = $FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory') |
            Select-Object -First 1

        if ($installPath) {
            Write-Verbose "Found installation at: $($installPath.FullName)"
            $Plugin.Config.InstallPath = $installPath.FullName
            # Temporary PATH registration removed: callers should reference install paths directly.
        }

        # Check for downloaded installer
        $currentInstaller = $FileSystem.GetChildItem($Paths._Downloads, "$pluginName*", 'File') |
            Select-Object -First 1

        if ($currentInstaller) {
            $state.CurrentInstaller = $currentInstaller.Name
            Write-Verbose "Found installer: $($state.CurrentInstaller)"
        }

        # Detect current version
        $versionFunctionName = "Get-CurrentVersion-$pluginName"

        if (Test-PluginFunction -Name $versionFunctionName) {
            Write-Verbose "Using custom version detection function: $versionFunctionName"
            $state.CurrentVersion = & $versionFunctionName -Plugin $Plugin -Paths $Paths
        }
        elseif ($installPath) {
            # Fall back to directory name as version
            $state.CurrentVersion = $installPath.BaseName
            Write-Verbose "Using directory name as version: $($state.CurrentVersion)"
        }

        return $state
    }
    catch {
        Write-Warning "Failed to get install state for $($Plugin.Config.Name): $_"
        return $state
    }
}

<#
.SYNOPSIS
    Retrieves the download URL for the latest plugin version.

.DESCRIPTION
    Queries the plugin's source (GitHub or custom URL) to obtain the download URL
    for the latest version. Supports custom URL retrieval functions.

.PARAMETER Plugin
    Plugin configuration hashtable with Config.Source property ('GitHub' or 'Url').

.PARAMETER Paths
    Paths configuration hashtable.

.PARAMETER TokenPath
    Path to the GitHub token file (for GitHub sources).

.PARAMETER FileSystem
    File system service (injectable for testing).

.PARAMETER Process
    Process service (injectable for testing).

.OUTPUTS
    String - Download URL for the latest version, or $null if not found.

.NOTES
    - Requires GitHub token for GitHub sources
    - Supports custom URL functions via Get-LatestUrlFromUrl-{PluginName}
#>
function Get-LatestDownloadUrl {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Plugin,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Paths,

        [Parameter()]
        [SecureString]$Token,

        [Parameter(Mandatory)]
        $Http,

        [Parameter(Mandatory)]
        $Crypto,

        [Parameter(Mandatory)]
        $FileSystem,

        [Parameter(Mandatory)]
        $Process
    )

    try {
        $pluginName = $Plugin.Config.Name
        $source = $Plugin.Config.Source

        # Ensure State bucket exists to store version metadata
        if (-not $Plugin.ContainsKey('Config')) { throw "Plugin hashtable missing 'Config' key" }
        if (-not $Plugin.Config.ContainsKey('State') -or $null -eq $Plugin.Config.State) {
            $Plugin.Config.State = @{}
        }

        Write-PSmmLog -Level INFO -Context "Check $pluginName" -Message "Getting latest download URL for $pluginName from source: $source" -Console -File

        switch ($source) {
            'GitHub' {
                # Token is optional; if not provided, fall back to unauthenticated
                if ($null -eq $Token) {
                    Write-Verbose 'GitHub token not provided; proceeding unauthenticated'
                }
                $url = Get-LatestUrlFromGitHub -Plugin $Plugin -Token $Token -Http $Http -Crypto $Crypto
            }
            'Url' {
                $urlFunctionName = "Get-LatestUrlFromUrl-$pluginName"

                if (Test-PluginFunction -Name $urlFunctionName) {
                    Write-PSmmLog -Level INFO -Context "Check $pluginName" -Message "Using custom URL function: $urlFunctionName" -Console -File
                    $url = & $urlFunctionName -Plugin $Plugin -Paths $Paths
                }
                else {
                    Write-Warning "No custom URL function found: $urlFunctionName"
                    $url = $null
                }
            }
            default {
                Write-Warning "Unknown plugin source: $source"
                $url = $null
            }
        }

        if ($url) {
            Write-PSmmLog -Level INFO -Context "Check $pluginName" -Message "Retrieved download URL: $url" -Console -File
        }

        return $url
    }
    catch {
        Write-Warning "Failed to get latest download URL for $($Plugin.Config.Name): $_"
        return $null
    }
}

<#
.SYNOPSIS
    Downloads a plugin installer from a URL.

.DESCRIPTION
    Downloads the plugin installer file to the downloads directory with
    progress logging.

.PARAMETER Url
    The URL to download from.

.PARAMETER Plugin
    Plugin configuration hashtable.

.PARAMETER Paths
    Paths configuration with _Downloads property.

.PARAMETER Http
    HTTP service (injectable for testing).

.PARAMETER FileSystem
    File system service (injectable for testing).

.OUTPUTS
    String - Path to the downloaded file, or $null if download failed.
#>
function Get-Installer {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Plugin,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Paths,

        [Parameter()]
        $Http,

        [Parameter()]
        $FileSystem,

        [Parameter()]
        $Process
    )

    try {
        $pluginName = $Plugin.Config.Name
        $fileName = Split-Path -Path $Url -Leaf
        $downloadPath = Join-Path -Path $Paths._Downloads -ChildPath $fileName

        if ($FileSystem -and -not $FileSystem.TestPath($Paths._Downloads)) {
            $FileSystem.NewItem($Paths._Downloads, 'Directory')
        }

        Write-PSmmLog -Level INFO -Context "Download $pluginName" `
            -Message "Downloading $pluginName from $Url ..." -Console -File

        $Http.DownloadFile($Url, $downloadPath)

        Write-PSmmLog -Level SUCCESS -Context "Download $pluginName" `
            -Message "$pluginName downloaded successfully to $downloadPath" -Console -File

        return $downloadPath
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Download $($Plugin.Config.Name)" `
            -Message "Failed to download $($Plugin.Config.Name)" -ErrorRecord $_ -Console -File
        return $null
    }
}

<#
.SYNOPSIS
    Executes a plugin installer.

.DESCRIPTION
    Installs a plugin based on the installer file type. Supports MSI, EXE, ZIP,
    and 7Z formats. Automatically extracts archives to the plugins directory.

.PARAMETER Plugin
    Plugin configuration hashtable.

.PARAMETER Paths
    Paths configuration with Root property for extraction.

.PARAMETER InstallerPath
    Path to the installer file.

.PARAMETER Process
    Process service (injectable for testing).

.PARAMETER FileSystem
    File system service (injectable for testing).

.NOTES
    - MSI: Launches msiexec with interactive installer
    - EXE: Launches executable with wait
    - ZIP: Extracts using PowerShell Expand-Archive
    - 7Z: Extracts using 7z.exe (must be in PATH)
#>
function Invoke-Installer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Plugin,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Paths,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$InstallerPath,

        [Parameter()]
        $Process,

        [Parameter()]
        $FileSystem
    )

    # Lazy instantiation to avoid parse-time type resolution

    try {
        $pluginName = $Plugin.Config.Name
        $extension = [System.IO.Path]::GetExtension($InstallerPath).ToLower()

        Write-Verbose "Installing $pluginName from: $InstallerPath (Type: $extension)"

        switch ($extension) {
            '.msi' {
                Write-Verbose 'Launching MSI installer...'
                $result = $Process.StartProcess('msiexec.exe', @('/i', "`"$InstallerPath`""))
                if (-not $result.Success) {
                    throw "MSI installer failed with exit code: $($result.ExitCode)"
                }
            }
            '.exe' {
                Write-Verbose 'Launching EXE installer...'
                $result = $Process.StartProcess($InstallerPath, @())
                if (-not $result.Success) {
                    throw "EXE installer failed with exit code: $($result.ExitCode)"
                }
            }
            '.zip' {
                $extractPath = Join-Path -Path $Paths.Root -ChildPath (Split-Path $InstallerPath -LeafBase)
                Write-Verbose "Extracting ZIP to: $extractPath"

                # Ensure extraction directory exists
                if (-not $FileSystem.TestPath($extractPath)) {
                    $FileSystem.NewItem($extractPath, 'Directory')
                }

                # Use Expand-Archive via PowerShell process
                # PowerShell 7+ includes compression APIs; no explicit Add-Type required
                [System.IO.Compression.ZipFile]::ExtractToDirectory($InstallerPath, $extractPath, $true)
            }
            '.7z' {
                $extractPath = Join-Path -Path $Paths.Root -ChildPath (Split-Path $InstallerPath -LeafBase)
                Write-Verbose "Extracting 7Z to: $extractPath"

                # Ensure extraction directory exists
                if (-not $FileSystem.TestPath($extractPath)) {
                    $FileSystem.NewItem($extractPath, 'Directory')
                }

                try {
                    $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -Process $Process
                }
                catch {
                    throw "7z is required to extract .7z archives: $($_)"
                }

                # First, test archive integrity for clearer diagnostics (let PowerShell handle quoting)
                $testResult = $Process.InvokeCommand($sevenZipCmd, @('t', $InstallerPath))
                if (-not $testResult.Success) {
                    $details = if ($null -ne $testResult.Output) { ($testResult.Output | Out-String).Trim() } else { '' }
                    throw "7z archive test failed (exit $($testResult.ExitCode)). $details"
                }

                # Extract archive
                $result = $Process.InvokeCommand($sevenZipCmd, @('x', $InstallerPath, "-o$extractPath", '-y'))
                if (-not $result.Success) {
                    $details = if ($null -ne $result.Output) { ($result.Output | Out-String).Trim() } else { '' }
                    throw "7z extraction failed with exit code: $($result.ExitCode). $details"
                }
            }
            default {
                throw "Unsupported installer type: $extension"
            }
        }

        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" `
            -Message "Installation complete for $InstallerPath" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" `
            -Message "Installation failed for $InstallerPath" -ErrorRecord $_ -Console -File
        throw
    }
}

<#
.SYNOPSIS
    Installs a plugin from its source.

.DESCRIPTION
    Orchestrates the complete installation process: downloads the latest version,
    optionally uses custom installer/download functions, and performs installation.

.PARAMETER Plugin
    Plugin configuration hashtable.

.PARAMETER Paths
    Paths configuration hashtable.

.PARAMETER Http
    HTTP service (injectable for testing).

.PARAMETER FileSystem
    File system service (injectable for testing).

.PARAMETER Process
    Process service (injectable for testing).

.NOTES
    - Supports custom download functions: Get-Installer-{PluginName}
    - Supports custom install functions: Invoke-Installer-{PluginName}
#>
function Install-Plugin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Plugin,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Paths,

        [Parameter()]
        $Config,

        [Parameter(Mandatory)]
        $Http,

        [Parameter(Mandatory)]
        $Crypto,

        [Parameter(Mandatory)]
        $FileSystem,

        [Parameter(Mandatory)]
        $Process
    )

    try {
        $pluginName = $Plugin.Config.Name
        Write-Verbose "Starting installation process for: $pluginName"

        # Prefer an already-secure token if available; otherwise build SecureString safely
        $token = $null
        if ($Config -and $Config.Secrets) {
            # If the secrets object exposes a SecureString property, use it directly
            if ($Config.Secrets.PSObject.Properties.Match('GitHubToken') -and
                $Config.Secrets.GitHubToken -is [System.Security.SecureString]) {
                $token = $Config.Secrets.GitHubToken
            }
            else {
                $tokenString = $Config.Secrets.GetGitHubToken()
                if ($tokenString) {
                    $secure = New-Object System.Security.SecureString
                    foreach ($ch in $tokenString.ToCharArray()) { $secure.AppendChar($ch) }
                    $secure.MakeReadOnly()
                    $token = $secure
                }
            }
        }

        # Get latest download URL
        $url = Get-LatestDownloadUrl -Plugin $Plugin -Paths $Paths -Token $token -Http $Http -Crypto $Crypto -FileSystem $FileSystem -Process $Process

        if (-not $url) {
            Write-Warning "Could not determine download URL for: $pluginName"
            return
        }

        # Download installer (custom or default)
        $installerFunctionName = "Get-Installer-$pluginName"

        if (Test-PluginFunction -Name $installerFunctionName) {
            Write-Verbose "Using custom installer download function: $installerFunctionName"
            $installerPath = & $installerFunctionName -Url $url -Plugin $Plugin -Paths $Paths -Http $Http -FileSystem $FileSystem
        }
        else {
            $installerPath = Get-Installer -Url $url -Plugin $Plugin -Paths $Paths -Http $Http -FileSystem $FileSystem
        }

        if (-not $installerPath) {
            Write-Warning "Failed to download installer for: $pluginName"
            return
        }

        # Run installer (custom or default)
        $installFunctionName = "Invoke-Installer-$pluginName"

        if (Test-PluginFunction -Name $installFunctionName) {
            Write-Verbose "Using custom installation function: $installFunctionName"
            & $installFunctionName -Plugin $Plugin -Paths $Paths -InstallerPath $installerPath -Process $Process -FileSystem $FileSystem
        }
        else {
            Invoke-Installer -Plugin $Plugin -Paths $Paths -InstallerPath $installerPath -Process $Process -FileSystem $FileSystem
        }
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Install Plugin' `
            -Message "Failed to install $($Plugin.Config.Name)" -ErrorRecord $_ -Console -File
    }
}

<#
.SYNOPSIS
    Checks if a plugin update is available.

.DESCRIPTION
    Compares the current installed version with the latest available version
    and logs the result.

.PARAMETER Plugin
    Plugin configuration hashtable with State.CurrentVersion and State.LatestVersion.

.PARAMETER Paths
    Paths configuration hashtable.

.PARAMETER FileSystem
    File system service (injectable for testing).

.PARAMETER Process
    Process service (injectable for testing).

.OUTPUTS
    Boolean - $true if update available, $false if up to date.
#>
function Request-PluginUpdate {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Plugin,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Paths,

        [Parameter()]
        $Config,

        [Parameter(Mandatory)]
        $Http,

        [Parameter(Mandatory)]
        $Crypto,

        [Parameter(Mandatory)]
        $FileSystem,

        [Parameter(Mandatory)]
        $Process
    )

    try {
        $pluginName = $Plugin.Config.Name

        # Prefer an already-secure token if available; otherwise build SecureString safely
        $token = $null
        if ($Config -and $Config.Secrets) {
            # If the secrets object exposes a SecureString property, use it directly
            if ($Config.Secrets.PSObject.Properties.Match('GitHubToken') -and
                $Config.Secrets.GitHubToken -is [System.Security.SecureString]) {
                $token = $Config.Secrets.GitHubToken
            }
            else {
                $tokenString = $Config.Secrets.GetGitHubToken()
                if ($tokenString) {
                    $secure = New-Object System.Security.SecureString
                    foreach ($ch in $tokenString.ToCharArray()) { $secure.AppendChar($ch) }
                    $secure.MakeReadOnly()
                    $token = $secure
                }
            }
        }

        # Get latest version information
        Get-LatestDownloadUrl -Plugin $Plugin -Paths $Paths -Token $token -Http $Http -Crypto $Crypto -FileSystem $FileSystem -Process $Process | Out-Null

        $currentVersion = $Plugin.Config.State.CurrentVersion
        $latestVersion = $Plugin.Config.State.LatestVersion

        if (-not $latestVersion) {
            Write-Warning "Could not determine latest version for: $pluginName"
            return $false
        }

        # Compare versions
        if ($currentVersion -ge $latestVersion) {
            Write-PSmmLog -Level INFO -Context "Update $pluginName" `
                -Message "$pluginName is up to date: $currentVersion" -Console -File
            return $false
        }
        else {
            Write-PSmmLog -Level WARNING -Context "Update $pluginName" `
                -Message "Update available for $pluginName from $currentVersion to $latestVersion" -Console -File
            return $true
        }
    }
    catch {
        Write-Warning "Failed to check for updates for $($Plugin.Config.Name): $_"
        return $false
    }
}

<#
.SYNOPSIS
    Updates a plugin to the latest version.

.DESCRIPTION
    Prompts user for confirmation, removes old version, and installs the
    latest version.

.PARAMETER Plugin
    Plugin configuration hashtable.

.PARAMETER Paths
    Paths configuration hashtable.

.PARAMETER Http
    HTTP service (injectable for testing).

.PARAMETER FileSystem
    File system service (injectable for testing).

.PARAMETER Process
    Process service (injectable for testing).
#>
function Update-Plugin {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Plugin,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Paths,

        [Parameter()]
        $Config,

        [Parameter()]
        $Http,

        [Parameter()]
        $Crypto,

        [Parameter()]
        $FileSystem,

        [Parameter()]
        $Process
    )

    try {
        $pluginName = $Plugin.Config.Name
        $currentVersion = $Plugin.Config.State.CurrentVersion
        $latestVersion = $Plugin.Config.State.LatestVersion

        # Update with ShouldProcess support
        if ($PSCmdlet.ShouldProcess("$pluginName", "Update from $currentVersion to $latestVersion")) {
            Write-Verbose "Updating: $pluginName"

            # Remove old installation
            $oldInstallPath = Join-Path -Path $Paths.Root -ChildPath "$pluginName*"
            if ($FileSystem.TestPath($oldInstallPath)) {
                $FileSystem.RemoveItem($oldInstallPath, $true)
                Write-Verbose "Removed old installation: $oldInstallPath"
            }

            # Remove old installer
            $oldInstallerPath = Join-Path -Path $Paths._Downloads -ChildPath "$pluginName*"
            if ($FileSystem.TestPath($oldInstallerPath)) {
                $FileSystem.RemoveItem($oldInstallerPath, $false)
                Write-Verbose "Removed old installer: $oldInstallerPath"
            }

            # Install new version
            Install-Plugin -Plugin $Plugin -Paths $Paths -Config $Config -Http $Http -Crypto $Crypto -FileSystem $FileSystem -Process $Process
        }
        else {
            Write-PSmmLog -Level INFO -Context "Update $pluginName" `
                -Message "Skipped update for $pluginName" -Console -File
        }
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Update Plugin' `
            -Message "Failed to update $($Plugin.Config.Name)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
