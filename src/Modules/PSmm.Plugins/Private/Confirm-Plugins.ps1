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

if (
    (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) -or
    (-not (Get-Command -Name Test-PSmmPluginsConfigMember -ErrorAction SilentlyContinue))
) {
    $configHelpersPath = Join-Path -Path $PSScriptRoot -ChildPath 'ConfigMemberAccessHelpers.ps1'
    if (Test-Path -Path $configHelpersPath) {
        . $configHelpersPath
    }
}

function Resolve-PluginNameSafe {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$PluginOrConfig
    )

    $cfg = Get-PSmmPluginsConfigMemberValue -Object $PluginOrConfig -Name 'Config'
    if ($null -eq $cfg) {
        $cfg = $PluginOrConfig
    }

    $name = Get-PSmmPluginsConfigMemberValue -Object $cfg -Name 'Name'
    $nameStr = [string]$name
    if ([string]::IsNullOrWhiteSpace($nameStr)) {
        return 'UNKNOWN'
    }

    return $nameStr
}

function Get-ResolvedPluginCommands {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Returns command mapping for multiple plugin commands; plural noun is intentional')]
    [CmdletBinding()]
    [OutputType([hashtable])]
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
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

    if ($PSCmdlet.ShouldProcess($CommandName, "Set resolved plugin command path to $CommandPath")) {
        $commands[$CommandName] = $CommandPath
        Write-Verbose "Resolved $CommandName at: $CommandPath"
        Write-PSmmLog -Level INFO -Context 'Confirm-Plugins' `
            -Message "Resolved $CommandName at $CommandPath" -Console -File
    }
    else {
        Write-Verbose "Skipping set of resolved plugin command for '$CommandName' (WhatIf/Confirm)."
    }
}

function Resolve-PluginCommandPath {
    [CmdletBinding()]
    [OutputType([string])]
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
        [ValidateNotNull()]
        $FileSystem,

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
    $candidates = @($FileSystem.GetChildItem($Paths.Root, $exeFilter, 'File', $true))
    $candidate = $candidates | Select-Object -First 1

    if ($candidate) {
        $resolvedPath = $candidate.FullName
        Set-ResolvedPluginCommandPath -Paths $Paths -CommandName $CommandName -CommandPath $resolvedPath
        return $resolvedPath
    }

    throw [PluginRequirementException]::new("Command '$CommandName' not found in PATH or under $($Paths.Root)", $CommandName)
}

<#
.SYNOPSIS
    Creates PSmm service instances while ensuring core types are available.
.DESCRIPTION
    Executes constructor in global scope where PSmm classes are defined via ScriptsToProcess.
#>
<#
.SYNOPSIS
    Registers plugin executables to PATH based on opt-in metadata.

.DESCRIPTION
    Iterates through all plugins with RegisterToPath=$true and adds their
    executable directories to $env:PATH for the current session. Tracks
    added paths in $Config.AddedPathEntries for later cleanup.

.PARAMETER Config
    Application configuration with Plugins.Resolved and AddedPathEntries.

.PARAMETER Environment
    Environment service for PATH manipulation.

.PARAMETER PathProvider
    Path provider service for path resolution.

.PARAMETER FileSystem
    File system service for path validation.
#>
function Register-PluginsToPATH {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Config,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Environment,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $PathProvider,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem
    )

    try {
        Write-Verbose 'Registering plugin executables to PATH (opt-in only)'
        Write-PSmmLog -Level INFO -Context 'Register-PluginsToPATH' `
            -Message 'Starting plugin PATH registration (opt-in only)' -Console -File

        $pluginRoot = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Paths', 'App', 'Plugins', 'Root')
        $pluginRoot = if ($null -eq $pluginRoot) { '' } else { [string]$pluginRoot }

        $pluginsConfig = Get-PSmmPluginsConfigMemberValue -Object $Config -Name 'Plugins'
        $resolvedPlugins = Get-PSmmPluginsConfigMemberValue -Object $pluginsConfig -Name 'Resolved'

        if ($null -eq $pluginsConfig -or $null -eq $resolvedPlugins) {
            Write-Verbose 'No plugin manifest found in configuration'
            Write-PSmmLog -Level WARNING -Context 'Register-PluginsToPATH' `
                -Message 'No plugin manifest found in configuration' -Console -File
            return
        }

        $pluginGroups = @($resolvedPlugins.GetEnumerator())
        Write-Verbose "Found $($pluginGroups.Count) plugin groups"
        Write-PSmmLog -Level INFO -Context 'Register-PluginsToPATH' `
            -Message "Found $($pluginGroups.Count) plugin groups to process" -Console -File

        $registeredDirs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $pathsToRegister = [System.Collections.Generic.List[string]]::new()
        # Always use Process scope only - Dev mode just skips cleanup at exit
        $persistUserPath = $false

        $existingPathEntries = $Environment.GetPathEntries()
        $pathSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $existingPathEntries) {
            $pathSet.Add($entry) | Out-Null
        }

        foreach ($group in $pluginGroups) {
            try {
                Write-Verbose "Processing plugin group: $($group.Name)"

                $pluginEntries = @($group.Value.GetEnumerator())

                foreach ($pluginEntry in $pluginEntries) {
                    try {
                        $pluginKey = $pluginEntry.Key
                        $resolvedPlugin = $pluginEntry.Value
                        if (-not $resolvedPlugin) { continue }

                        $pluginName = Resolve-PluginNameSafe -PluginOrConfig $resolvedPlugin
                        if ([string]::IsNullOrWhiteSpace($pluginName) -or $pluginName -eq 'UNKNOWN') {
                            Write-Verbose "Plugin at path Plugins[$($group.Name)][$pluginKey] has no name; skipping PATH registration"
                            continue
                        }

                        $isMandatory = [bool](Get-PSmmPluginsConfigMemberValue -Object $resolvedPlugin -Name 'Mandatory')
                        $isEnabled = [bool](Get-PSmmPluginsConfigMemberValue -Object $resolvedPlugin -Name 'Enabled')
                        if (-not ($isMandatory -or $isEnabled)) {
                            Write-Verbose "Plugin $pluginName is not enabled for current scope - skipping PATH registration"
                            continue
                        }

                        $registerToPath = Get-PSmmPluginsConfigMemberValue -Object $resolvedPlugin -Name 'RegisterToPath'
                        if ($registerToPath -ne $true) {
                            Write-Verbose "Plugin $pluginName has RegisterToPath=$registerToPath - skipping"
                            continue
                        }

                        Write-Verbose "Plugin $pluginName is marked for PATH registration"

                        # Skip if plugin doesn't have State (not installed)
                        $state = Get-PSmmPluginsConfigMemberValue -Object $resolvedPlugin -Name 'State'
                        if ($null -eq $state) {
                            Write-Verbose "Plugin $pluginName marked for PATH but not installed (no State) - skipping"
                            continue
                        }

                        # Resolve plugin installation directory
                        if ([string]::IsNullOrWhiteSpace($pluginRoot)) {
                            Write-Verbose "Plugins root path not available; skipping PATH registration for $pluginName"
                            continue
                        }
                        $pluginDirs = $FileSystem.GetChildItem($pluginRoot, $null, 'Directory') | Where-Object { $null -ne $_ -and $_.Name -match $pluginName }

                        if (-not $pluginDirs) {
                            Write-Verbose "Plugin $pluginName directory not found under $pluginRoot - skipping PATH registration"
                            continue
                        }

                        $pluginDir = $pluginDirs | Where-Object { $null -ne $_ } | Select-Object -First 1
                        if ($null -eq $pluginDir) {
                            Write-Verbose "Plugin ${pluginName} directory selection returned null under ${pluginRoot} - skipping PATH registration"
                            continue
                        }
                        $commandPath = Get-PSmmPluginsConfigMemberValue -Object $resolvedPlugin -Name 'CommandPath'
                        $commandPath = if ($commandPath) { [string]$commandPath } else { '' }
                        $executableDir = if ($commandPath) {
                            $PathProvider.CombinePath(@($pluginDir.FullName, $commandPath))
                        } else {
                            $pluginDir.FullName
                        }

                        if ([string]::IsNullOrWhiteSpace($executableDir)) {
                            Write-Verbose "Executable directory resolved empty for ${pluginName} - skipping PATH registration"
                            continue
                        }

                        if (-not $FileSystem.TestPath($executableDir)) {
                            Write-Verbose "Executable directory not found: $executableDir - skipping PATH registration"
                            continue
                        }

                        # Resolve to full path and add to PATH if not already present
                        # Resolve-Path can emit non-terminating errors and return $null; guard to avoid StrictMode failures
                        $resolvedPathInfo = $null
                        try {
                            $resolvedPathInfo = Resolve-Path -LiteralPath $executableDir -ErrorAction Stop | Select-Object -First 1
                        }
                        catch {
                            Write-Verbose "Failed to resolve executable directory for ${pluginName}: $executableDir ($_)"
                            continue
                        }

                        $resolvedDir = if ($null -ne $resolvedPathInfo) { [string]$resolvedPathInfo.Path } else { '' }
                        if ([string]::IsNullOrWhiteSpace($resolvedDir)) {
                            Write-Verbose "Resolved executable directory was empty for ${pluginName}: $executableDir - skipping PATH registration"
                            continue
                        }

                        if ($registeredDirs.Contains($resolvedDir)) {
                            Write-Verbose "Already registered $resolvedDir to PATH in this session - skipping duplicate"
                            continue
                        }

                        # Track for cleanup regardless of whether we add it now (store in config for access during shutdown)
                        # Avoid method calls on values with uncertain runtime types (StrictMode-safe)
                        $existingAdded = Get-PSmmPluginsConfigMemberValue -Object $Config -Name 'AddedPathEntries'

                        $existingList = @()
                        if ($null -ne $existingAdded) {
                            if ($existingAdded -is [System.Collections.IEnumerable] -and -not ($existingAdded -is [string])) {
                                $existingList = @($existingAdded) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                            }
                            else {
                                $existingItem = [string]$existingAdded
                                if (-not [string]::IsNullOrWhiteSpace($existingItem)) {
                                    $existingList = @($existingItem)
                                }
                            }
                        }

                        if ($existingList -notcontains $resolvedDir) {
                            Set-PSmmPluginsConfigMemberValue -Object $Config -Name 'AddedPathEntries' -Value @($existingList + @($resolvedDir))
                        }

                        if ($pathSet.Contains($resolvedDir)) {
                            Write-Verbose "$resolvedDir already in PATH - tracked for cleanup"
                            continue
                        }

                        $pathsToRegister.Add($resolvedDir)
                        $pathSet.Add($resolvedDir) | Out-Null
                        $registeredDirs.Add($resolvedDir) | Out-Null

                        Write-Verbose "Queued $pluginName for PATH registration: $resolvedDir"
                        Write-PSmmLog -Level INFO -Context 'Register-PluginsToPATH' `
                            -Message "Queued $pluginName for PATH registration: $resolvedDir" -Console -File
                    }
                    catch {
                        $pn = [string](Get-PSmmPluginsConfigMemberValue -Object $resolvedPlugin -Name 'Name')
                        $errMessage = if ($null -ne $_.Exception -and -not [string]::IsNullOrWhiteSpace($_.Exception.Message)) { $_.Exception.Message } else { [string]$_ }
                        $where = if ($null -ne $_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber -gt 0) { " ($($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber))" } else { '' }
                        Write-Verbose "Failed to register plugin $pn to PATH: $errMessage$where"
                        Write-PSmmLog -Level WARNING -Context 'Register-PluginsToPATH' `
                            -Message "Failed to register plugin $pn to PATH: $errMessage$where" -ErrorRecord $_ -Console -File
                    }
                }
            }
            catch {
                Write-Verbose "Failed to process plugin group $($group.Name): $_"
                Write-PSmmLog -Level WARNING -Context 'Register-PluginsToPATH' `
                    -Message "Failed to process plugin group $($group.Name): $_" -Console -File
            }
        }

        if ($pathsToRegister.Count -gt 0) {
            $Environment.AddPathEntries($pathsToRegister.ToArray(), $persistUserPath)
            Write-Verbose "Registered $($pathsToRegister.Count) new PATH entries in batch"
        }

        if ($registeredDirs.Count -gt 0) {
            Write-PSmmLog -Level NOTICE -Context 'Register-PluginsToPATH' `
                -Message "Registered $($registeredDirs.Count) plugin(s) to PATH for current session" -Console -File
        } else {
            Write-Verbose 'No plugins opted in for PATH registration'
        }
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Register-PluginsToPATH' `
            -Message "Failed to register plugins to PATH: $_" -ErrorRecord $_ -Console -File
        # Non-fatal - continue execution
    }
}

function New-PSmmServiceInstance {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Temporary global variable is used to execute constructor in global scope where PSmm types are defined')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TypeName
    )

    try {
        Write-Verbose "[New-PSmmServiceInstance] Creating instance of $TypeName via global scope"

        if (-not $PSCmdlet.ShouldProcess($TypeName, 'Instantiate PSmm service instance')) {
            Write-Verbose "Instantiation of $TypeName skipped by ShouldProcess"
            return
        }

        # Use & with script block defined in global scope
        $global:__tempConstructor = [scriptblock]::Create("[$TypeName]::new()")
        $instance = & $global:__tempConstructor
        Remove-Variable -Name __tempConstructor -Scope Global -ErrorAction SilentlyContinue

        if ($null -eq $instance) {
            throw [ProcessException]::new("Constructor returned null for type instantiation")
        }

        return $instance
    }
    catch {
        $psmmInfo = Get-Module -Name 'PSmm'
        $psmmStatus = if ($psmmInfo) { "loaded v$($psmmInfo.Version)" } else { "not loaded" }
        $ex = [ModuleLoadException]::new("Unable to instantiate [$TypeName]. PSmm module is $psmmStatus", $TypeName, $_.Exception)
        throw $ex
    }
}

function Resolve-PluginsConfig {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Config
    )

    $pluginsSource = Get-PSmmPluginsConfigMemberValue -Object $Config -Name 'Plugins'
    if (-not $pluginsSource) {
        throw [ConfigurationException]::new('Plugin manifest not loaded in configuration', 'Plugins')
    }

    $pluginsConfigType = 'PluginsConfig' -as [type]
    if (-not $pluginsConfigType) {
        $psmmManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\PSmm\PSmm.psd1'
        if (Test-Path -LiteralPath $psmmManifestPath) {
            try {
                Import-Module -Name $psmmManifestPath -Force -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Verbose "Resolve-PluginsConfig: failed importing PSmm module '$psmmManifestPath': $($_.Exception.Message)"
                # ignore - handled below
            }
        }
        $pluginsConfigType = 'PluginsConfig' -as [type]
    }

    if (-not $pluginsConfigType) {
        throw [ConfigurationException]::new('Unable to resolve PluginsConfig type (PSmm module not loaded)', 'Plugins')
    }

    $pluginsBag = $pluginsConfigType::FromObject($pluginsSource)
    Set-PSmmPluginsConfigMemberValue -Object $Config -Name 'Plugins' -Value $pluginsBag

    function _UnwrapPluginsManifest {
        param([Parameter()][AllowNull()]$Manifest)

        if ($null -eq $Manifest) { return $null }
        if ($Manifest -is [System.Collections.IDictionary]) {
            try {
                if ($Manifest.Contains('Plugins')) { return $Manifest['Plugins'] }
            }
            catch {
                Write-Verbose "_UnwrapPluginsManifest: failed Contains('Plugins'): $($_.Exception.Message)"
                # ignore
            }
            try {
                if ($Manifest.ContainsKey('Plugins')) { return $Manifest['Plugins'] }
            }
            catch {
                Write-Verbose "_UnwrapPluginsManifest: failed ContainsKey('Plugins'): $($_.Exception.Message)"
                # ignore
            }

            try {
                foreach ($k in $Manifest.Keys) {
                    if ($k -eq 'Plugins') {
                        return $Manifest[$k]
                    }
                }
            }
            catch {
                Write-Verbose "_UnwrapPluginsManifest: failed iterating Keys: $($_.Exception.Message)"
                # ignore
            }
        }

        if (Get-Command -Name Test-PSmmPluginsConfigMember -ErrorAction SilentlyContinue) {
            if (Test-PSmmPluginsConfigMember -Object $Manifest -Name 'Plugins') {
                try { return Get-PSmmPluginsConfigMemberValue -Object $Manifest -Name 'Plugins' }
                catch {
                    Write-Verbose "_UnwrapPluginsManifest: failed reading 'Plugins' member: $($_.Exception.Message)"
                }
            }
        }
        return $Manifest
    }

    $globalPath = $null
    $projectPath = $null
    try { if ($pluginsBag.Paths) { $globalPath = $pluginsBag.Paths.Global } } catch { Write-Debug "Failed to retrieve global plugin path: $_" }
    try { if ($pluginsBag.Paths) { $projectPath = $pluginsBag.Paths.Project } } catch { Write-Debug "Failed to retrieve project plugin path: $_" }

    $globalManifest = _UnwrapPluginsManifest -Manifest $pluginsBag.Global

    if (-not $globalManifest) {
        throw [ConfigurationException]::new('Global plugin manifest is missing or invalid', $globalPath)
    }

    $projectManifest = $null

    # Use already-loaded project manifest when present
    if ($pluginsBag.Project) {
        $projectManifest = _UnwrapPluginsManifest -Manifest $pluginsBag.Project
    }
    else {
        # Attempt to auto-load project plugins manifest if a project is selected
        $candidateProjectPath = $null
        try {
            $currentPathObj = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Projects', 'Current', 'Path')
            $currentPath = if ($null -ne $currentPathObj) { [string]$currentPathObj } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($currentPath)) {
                $candidateProjectPath = Join-Path -Path $currentPath -ChildPath 'Config/PSmm/PSmm.Plugins.psd1'
            }
        } catch { Write-Debug "Failed to construct project plugin path: $_" }

        if ($candidateProjectPath -and (Test-Path -Path $candidateProjectPath)) {
            $projectPath = $candidateProjectPath
            $projectManifestRaw = Import-PowerShellDataFile -Path $candidateProjectPath -ErrorAction Stop
            $projectManifest = _UnwrapPluginsManifest -Manifest $projectManifestRaw
            $pluginsBag.Project = $projectManifest
        }
        elseif ($candidateProjectPath) {
            $projectPath = $candidateProjectPath
        }
    }

    $previousResolved = $pluginsBag.Resolved
    $resolved = @{}

    foreach ($groupName in ($globalManifest.Keys | Sort-Object)) {
        $resolved[$groupName] = @{}
        foreach ($pluginKey in ($globalManifest[$groupName].Keys | Sort-Object)) {
            $source = $globalManifest[$groupName][$pluginKey]
            $clone = @{}
            foreach ($prop in $source.Keys) {
                $clone[$prop] = $source[$prop]
            }

            if (-not $clone.ContainsKey('Mandatory')) { $clone.Mandatory = $false }
            $clone.Mandatory = [bool]$clone.Mandatory

            if (-not $clone.ContainsKey('Enabled')) { $clone.Enabled = $clone.Mandatory }
            else { $clone.Enabled = [bool]$clone.Enabled -or $clone.Mandatory }

            $prevGroup = $null
            if ($previousResolved) {
                $prevGroup = Get-PSmmPluginsConfigMemberValue -Object $previousResolved -Name $groupName
            }

            if ($null -ne $prevGroup) {
                $prevPlugin = Get-PSmmPluginsConfigMemberValue -Object $prevGroup -Name $pluginKey
                $prevState = Get-PSmmPluginsConfigMemberValue -Object $prevPlugin -Name 'State'
                if ($null -ne $prevState) {
                    $clone.State = $prevState
                }
            }

            $resolved[$groupName][$pluginKey] = $clone
        }
    }

    if ($projectManifest) {
        foreach ($groupName in ($projectManifest.Keys | Sort-Object)) {
            foreach ($pluginKey in ($projectManifest[$groupName].Keys | Sort-Object)) {
                if (-not $resolved.ContainsKey($groupName) -or -not $resolved[$groupName].ContainsKey($pluginKey)) {
                    $msg = "Plugin '$pluginKey' in group '$groupName' is not defined in global manifest. (Global: $globalPath; Project: $projectPath)"
                    throw [ConfigurationException]::new($msg, $projectPath)
                }

                $target = $resolved[$groupName][$pluginKey]
                $projectEntry = $projectManifest[$groupName][$pluginKey]

                $conflicts = @()
                $projectEntryKeys = @()
                if ($projectEntry -is [System.Collections.IDictionary]) {
                    $projectEntryKeys = @($projectEntry.Keys)
                }
                else {
                    try {
                        $projectEntryKeys = @(
                            Get-Member -InputObject $projectEntry -MemberType NoteProperty,Property -ErrorAction SilentlyContinue |
                                Select-Object -ExpandProperty Name
                        )
                    }
                    catch {
                        $projectEntryKeys = @()
                    }
                }

                foreach ($prop in $projectEntryKeys) {
                    if ($prop -eq 'Enabled') { continue }

                    if ($prop -eq 'Mandatory') {
                        $projectMandatory = Get-PSmmPluginsConfigMemberValue -Object $projectEntry -Name 'Mandatory'
                        if ([bool]$target.Mandatory -ne [bool]$projectMandatory) {
                            $conflicts += $prop
                        }
                        continue
                    }

                    $targetValue = Get-PSmmPluginsConfigMemberValue -Object $target -Name $prop
                    if ($null -eq $targetValue) {
                        $conflicts += $prop
                        continue
                    }

                    $projectValue = Get-PSmmPluginsConfigMemberValue -Object $projectEntry -Name $prop
                    if ($targetValue -ne $projectValue) {
                        $conflicts += $prop
                    }
                }

                if ($conflicts.Count -gt 0) {
                    $fields = ($conflicts -join ', ')
                    $msg = "Plugin '$pluginKey' has conflicting definitions for field(s): $fields. Global: $globalPath; Project: $projectPath"
                    throw [ConfigurationException]::new($msg, $projectPath)
                }

                $projectEnabled = $true
                $projectEnabledValue = Get-PSmmPluginsConfigMemberValue -Object $projectEntry -Name 'Enabled'
                if ($null -ne $projectEnabledValue) {
                    $projectEnabled = [bool]$projectEnabledValue
                }

                if ($target.Mandatory -and -not $projectEnabled) {
                    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $target -Name 'Name')
                    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = $pluginKey }
                    $msg = "Project manifest cannot disable mandatory plugin '$pluginName'. Global: $globalPath; Project: $projectPath"
                    throw [ConfigurationException]::new($msg, $projectPath)
                }

                $projectState = Get-PSmmPluginsConfigMemberValue -Object $projectEntry -Name 'State'
                if ($null -ne $projectState -and -not $target.State) {
                    $target.State = $projectState
                }

                if ($projectEnabled) {
                    $target.Enabled = $true
                }
            }
        }
    }

    if ($null -eq $pluginsBag.Paths) {
        $pluginsBag.Paths = [PluginsPathsConfig]::new()
    }

    if ([string]::IsNullOrWhiteSpace($pluginsBag.Paths.Global)) { $pluginsBag.Paths.Global = $globalPath }
    if ($projectPath) { $pluginsBag.Paths.Project = $projectPath }

    $pluginsBag.Resolved = $resolved
    Set-PSmmPluginsConfigMemberValue -Object $Config -Name 'Plugins' -Value $pluginsBag
    return $resolved
}

<#
.SYNOPSIS
    Confirms all required external plugins are installed and up to date.

.DESCRIPTION
    Validates external plugin installations, downloads missing plugins,
    and optionally updates existing plugins to the latest versions.

.OUTPUTS
    System.Collections.Hashtable

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
        $ServiceContainer
    )

    $resolvedPlugins = Resolve-PluginsConfig -Config $Config

    $pluginRoot = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Paths', 'App', 'Plugins', 'Root')
    $pluginDownloads = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Paths', 'App', 'Plugins', 'Downloads')
    $pluginTemp = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Paths', 'App', 'Plugins', 'Temp')
    $vaultPath = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Paths', 'App', 'Vault')
    $updateMode = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Parameters', 'Update')

    if ([string]::IsNullOrWhiteSpace([string]$pluginRoot)) {
        throw [ValidationException]::new('Config.Paths.App.Plugins.Root is required for plugin confirmation', 'Paths.App.Plugins.Root')
    }
    if ([string]::IsNullOrWhiteSpace([string]$pluginDownloads)) {
        throw [ValidationException]::new('Config.Paths.App.Plugins.Downloads is required for plugin confirmation', 'Paths.App.Plugins.Downloads')
    }
    if ([string]::IsNullOrWhiteSpace([string]$pluginTemp)) {
        throw [ValidationException]::new('Config.Paths.App.Plugins.Temp is required for plugin confirmation', 'Paths.App.Plugins.Temp')
    }
    if ([string]::IsNullOrWhiteSpace([string]$vaultPath)) {
        throw [ValidationException]::new('Config.Paths.App.Vault is required for plugin confirmation', 'Paths.App.Vault')
    }

    # Adapt typed Config into internal hashtable for helper reuse
    $Run = @{
        App = @{
            Paths = @{
                App = @{
                    Plugins = @{
                        Root = [string]$pluginRoot
                        _Downloads = [string]$pluginDownloads
                        _Temp = [string]$pluginTemp
                        Commands = @{}
                    }
                    Vault = [string]$vaultPath
                }
            }
            Parameters = @{
                Update = [bool]$updateMode
            }
            Plugins = @{
                Manifest = $resolvedPlugins
            }
            Secrets = @{
                GitHub = @{}
            }
        }
    }

    # Resolve services needed across confirmation flow
    $FileSystem = $null
    $Environment = $null
    $PathProvider = $null
    if ($null -ne $ServiceContainer) {
        try { $FileSystem = $ServiceContainer.Resolve('FileSystem') } catch { Write-Verbose "Failed to resolve FileSystem from ServiceContainer: $_" }
        try { $Environment = $ServiceContainer.Resolve('Environment') } catch { Write-Verbose "Failed to resolve Environment from ServiceContainer: $_" }
        try { $PathProvider = $ServiceContainer.Resolve('PathProvider') } catch { Write-Verbose "Failed to resolve PathProvider from ServiceContainer: $_" }
    }

    if ($null -eq $PathProvider) {
        # Prefer the canonical AppPaths behavior when available on Config.Paths
        try {
            $pathsCandidate = Get-PSmmPluginsConfigMemberValue -Object $Config -Name 'Paths'
            if ($null -ne $pathsCandidate -and ($pathsCandidate -is [IPathProvider])) {
                $PathProvider = [PathProvider]::new([IPathProvider]$pathsCandidate)
            }
        }
        catch {
            Write-Verbose "Failed to bind PathProvider from Config.Paths: $($_.Exception.Message)"
        }
    }

    if ($null -eq $PathProvider) {
        # Fallback to global service container when available (host app bootstrap)
        try {
            $globalServiceContainer = Get-Variable -Name 'PSmmServiceContainer' -Scope Global -ValueOnly -ErrorAction Stop
            $PathProvider = $globalServiceContainer.Resolve('PathProvider')
        }
        catch {
            Write-Verbose "Failed to resolve PathProvider from global ServiceContainer: $($_.Exception.Message)"
        }
    }

    if ($null -eq $PathProvider) {
        # Minimal fallback for standalone/test scenarios
        $PathProvider = [PathProvider]::new()
    }

    try {
        $paths = $Run.App.Paths.App.Plugins
        Get-ResolvedPluginCommands -Paths $paths | Out-Null
        $updateMode = $Run.App.Parameters.Update

        Write-Verbose "Starting plugin confirmation (Update mode: $updateMode)"

        # GitHub token is managed via KeePassXC; no file-path fallback is needed

        # Iterate through plugin groups (a_GitEnv, b_ExifTool, etc.)
        $pluginGroups = $Run.App.Plugins.Manifest.GetEnumerator() | Sort-Object -Property Name

        # Capture baseline plugin versions once before processing (for later health diff)
        if (-not (Get-Variable -Name PSmm_PluginBaseline -Scope Script -ErrorAction SilentlyContinue)) {
            $script:PSmm_PluginBaseline = @()
            foreach ($baselineGroup in $pluginGroups) {
                foreach ($baselinePlugin in $baselineGroup.Value.GetEnumerator()) {
                    $state = Get-PSmmPluginsConfigMemberValue -Object $baselinePlugin.Value -Name 'State'
                    $currentVersion = Get-PSmmPluginsConfigMemberValue -Object $state -Name 'CurrentVersion'
                    $isInstalled = -not [string]::IsNullOrWhiteSpace([string]$currentVersion)
                    $isMandatory = [bool](Get-PSmmPluginsConfigMemberValue -Object $baselinePlugin.Value -Name 'Mandatory')
                    $isEnabled = [bool](Get-PSmmPluginsConfigMemberValue -Object $baselinePlugin.Value -Name 'Enabled')
                    if (-not ($isMandatory -or $isEnabled -or $isInstalled)) { continue }

                    $script:PSmm_PluginBaseline += [pscustomobject]@{
                        Name = [string](Get-PSmmPluginsConfigMemberValue -Object $baselinePlugin.Value -Name 'Name')
                        Scope = $baselineGroup.Name
                        InstalledVersion = if ($state) { $state.CurrentVersion } else { $null }
                    }
                }
            }
            Write-Verbose "Captured plugin baseline for health summary ($($script:PSmm_PluginBaseline.Count) plugins)"
        }

        foreach ($pluginGroup in $pluginGroups) {
            $scopeName = $pluginGroup.Name.Substring(2)  # Remove prefix (e.g., "a_")
            Write-PSmmLog -Level NOTICE -Context "Confirm $scopeName" `
                -Message "Checking for $scopeName plugins" -Console -File

            # Iterate through plugins in this group
            $pluginsInGroup = $pluginGroup.Value.GetEnumerator() | Sort-Object -Property @{ Expression = { -not ($_.Value.Mandatory) } }, Name

            foreach ($pluginEntry in $pluginsInGroup) {
                $plugin = @{
                    Key = $pluginEntry.Key
                    Config = $pluginEntry.Value
                }
                $pluginName = Resolve-PluginNameSafe -PluginOrConfig $plugin
                $isMandatory = [bool](Get-PSmmPluginsConfigMemberValue -Object $plugin.Config -Name 'Mandatory')
                $isEnabled = [bool](Get-PSmmPluginsConfigMemberValue -Object $plugin.Config -Name 'Enabled')
                $state = Get-PSmmPluginsConfigMemberValue -Object $plugin.Config -Name 'State'
                $currentVersion = Get-PSmmPluginsConfigMemberValue -Object $state -Name 'CurrentVersion'
                $hasInstalledState = -not [string]::IsNullOrWhiteSpace([string]$currentVersion)
                $shouldProcess = $isMandatory -or $isEnabled -or ($updateMode -and $hasInstalledState)

                if (-not $shouldProcess) {
                    Write-Verbose "Skipping plugin $pluginName (not enabled for current scope)"
                    continue
                }

                Invoke-PluginConfirmation -Config $Config -Plugin $plugin -Paths $paths -Run $Run -ScopeName $scopeName -UpdateMode $updateMode `
                    -ServiceContainer $ServiceContainer
            }
        }

        # Register plugin executables to PATH (opt-in via RegisterToPath metadata)
        if ($Environment -and $PathProvider -and $FileSystem) {
            Register-PluginsToPATH -Config $Config -Environment $Environment -PathProvider $PathProvider -FileSystem $FileSystem
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
        $ServiceContainer
    )

    $hasPaths = $false
    if ($Config -is [System.Collections.IDictionary]) {
        try { $hasPaths = $Config.ContainsKey('Paths') } catch { $hasPaths = $false }
        if (-not $hasPaths) {
            try { $hasPaths = $Config.Contains('Paths') } catch { $hasPaths = $false }
        }
        if (-not $hasPaths) {
            try {
                foreach ($k in $Config.Keys) {
                    if ($k -eq 'Paths') { $hasPaths = $true; break }
                }
            }
            catch { $hasPaths = $false }
        }
    }
    else {
        $hasPaths = $false
        if (Get-Command -Name Test-PSmmPluginsConfigMember -ErrorAction SilentlyContinue) {
            $hasPaths = Test-PSmmPluginsConfigMember -Object $Config -Name 'Paths'
        }
    }

    if (-not $hasPaths) {
        throw [ValidationException]::new('Invoke-PluginConfirmation requires a configuration object exposing Paths', 'Config')
    }

    # Resolve services from ServiceContainer
    $FileSystem = $null
    $Process = $null

    if ($null -ne $ServiceContainer) {
        try {
            $FileSystem = $ServiceContainer.Resolve('FileSystem')
            $Process = $ServiceContainer.Resolve('Process')
        }
        catch {
            Write-Verbose "Failed to resolve services from ServiceContainer: $_"
        }
    }

    $pluginName = Resolve-PluginNameSafe -PluginOrConfig $Plugin
    Write-PSmmLog -Level INFO -Context "Confirm $ScopeName" `
        -Message "Confirming $pluginName" -Console -File

    # Get initial install state
    $state = Get-InstallState -Plugin $Plugin -Paths $Paths -FileSystem $FileSystem -Process $Process
    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    Set-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state

    # Store state in Run configuration
    $scopeKey = $Run.App.Plugins.Manifest.GetEnumerator() |
        Where-Object { $_.Name.Substring(2) -eq $ScopeName } |
        Select-Object -ExpandProperty Name -First 1

    if ($scopeKey) {
        $Run.App.Plugins.Manifest.$scopeKey.$($Plugin.Key).State = $state
    }

    # Handle installation or update
    if ([string]::IsNullOrEmpty($state.CurrentVersion)) {
        Write-PSmmLog -Level NOTICE -Context "Check $pluginName" `
            -Message "$pluginName is not installed (installing now)" -Console -File
        Install-Plugin -Plugin $Plugin -Paths $Paths -Config $Config -ServiceContainer $ServiceContainer
    }
    else {
        Write-PSmmLog -Level SUCCESS -Context "Check $pluginName" `
            -Message "$pluginName is installed: $($state.CurrentVersion)" -Console -File

        if ($UpdateMode) {
            $updateAvailable = Request-PluginUpdate -Plugin $Plugin -Paths $Paths -Config $Config -Http $Http -Crypto $Crypto `
                -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process

            if ($updateAvailable) {
                Write-PSmmLog -Level INFO -Context "Check $pluginName" `
                    -Message "Update requested for $pluginName" -Console -File
                Update-Plugin -Plugin $Plugin -Paths $Paths -Config $Config -Http $Http -Crypto $Crypto -FileSystem $FileSystem -Process $Process
            }
        }
    }

    # Refresh install state after changes
    $state = Get-InstallState -Plugin $Plugin -Paths $Paths -FileSystem $FileSystem -Process $Process
    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    Set-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state

    if ($scopeKey) {
        $Run.App.Plugins.Manifest.$scopeKey.$($Plugin.Key).State = $state
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
        $pluginName = Resolve-PluginNameSafe -PluginOrConfig $Plugin
        # Mark injected but unused parameter as intentionally unused for static analysis
        $null = $Process
        Write-Verbose "Getting install state for: $pluginName"

        # Check if plugin is installed
        $installPath = $FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory') |
            Select-Object -First 1

        if ($installPath) {
            Write-Verbose "Found installation at: $($installPath.FullName)"
            $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
            Set-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'InstallPath' -Value $installPath.FullName
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
            $state.CurrentVersion = & $versionFunctionName -Plugin $Plugin -Paths $Paths -FileSystem $FileSystem
        }
        elseif ($installPath) {
            # Fall back to directory name as version
            $state.CurrentVersion = $installPath.BaseName
            Write-Verbose "Using directory name as version: $($state.CurrentVersion)"
        }

        return $state
    }
    catch {
        $pn = Resolve-PluginNameSafe -PluginOrConfig $Plugin
        Write-Warning "Failed to get install state for ${pn}: $_"
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
        $ServiceContainer
    )

    try {
        # Resolve services from ServiceContainer
        $Http = $null
        $Crypto = $null
        $FileSystem = $null
        $Environment = $null
        $PathProvider = $null
        $Process = $null

        if ($null -ne $ServiceContainer) {
            try {
                $Http = $ServiceContainer.Resolve('Http')
                $Crypto = $ServiceContainer.Resolve('Crypto')
                $FileSystem = $ServiceContainer.Resolve('FileSystem')
                $Environment = $ServiceContainer.Resolve('Environment')
                $PathProvider = $ServiceContainer.Resolve('PathProvider')
                $Process = $ServiceContainer.Resolve('Process')
            }
            catch {
                Write-Verbose "Failed to resolve services from ServiceContainer: $_"
            }
        }

        if ($null -eq $PathProvider) {
            try {
                $pathsCandidate = Get-PSmmPluginsConfigMemberValue -Object $Config -Name 'Paths'
                if ($null -ne $pathsCandidate -and ($pathsCandidate -is [IPathProvider])) {
                    $PathProvider = [PathProvider]::new([IPathProvider]$pathsCandidate)
                }
            }
            catch {
                Write-Verbose "Failed to bind PathProvider from Config.Paths: $($_.Exception.Message)"
            }
        }

        if ($null -eq $PathProvider) {
            try {
                $globalServiceContainer = Get-Variable -Name 'PSmmServiceContainer' -Scope Global -ValueOnly -ErrorAction Stop
                $PathProvider = $globalServiceContainer.Resolve('PathProvider')
            }
            catch {
                Write-Verbose "Failed to resolve PathProvider from global ServiceContainer: $($_.Exception.Message)"
            }
        }

        if ($null -eq $PathProvider) {
            $PathProvider = [PathProvider]::new()
        }

        # Ensure Config bucket exists before accessing nested members
        $hasConfig = $false
        try {
            if ($Plugin -is [System.Collections.IDictionary]) {
                try { $hasConfig = $Plugin.ContainsKey('Config') } catch { $hasConfig = $false }
                if (-not $hasConfig) {
                    try { $hasConfig = $Plugin.Contains('Config') } catch { $hasConfig = $false }
                }
                if (-not $hasConfig) {
                    try {
                        foreach ($k in $Plugin.Keys) {
                            if ($k -eq 'Config') { $hasConfig = $true; break }
                        }
                    }
                    catch { $hasConfig = $false }
                }
            }
            else {
                $hasConfig = $false
                if (Get-Command -Name Test-PSmmPluginsConfigMember -ErrorAction SilentlyContinue) {
                    $hasConfig = Test-PSmmPluginsConfigMember -Object $Plugin -Name 'Config'
                }
            }
        }
        catch {
            $hasConfig = $false
        }

        if (-not $hasConfig) {
            throw [PluginRequirementException]::new("Plugin missing required 'Config' member", "Plugin")
        }

        $pluginConfig = $Plugin['Config']
        $pluginName = $null
        $source = $null
        try {
            if ($pluginConfig -is [System.Collections.IDictionary]) {
                $hasName = $false
                try { $hasName = $pluginConfig.ContainsKey('Name') } catch { $hasName = $false }
                if (-not $hasName) {
                    try { $hasName = $pluginConfig.Contains('Name') } catch { $hasName = $false }
                }
                if (-not $hasName) {
                    try {
                        foreach ($k in $pluginConfig.Keys) {
                            if ($k -eq 'Name') { $hasName = $true; break }
                        }
                    }
                    catch { $hasName = $false }
                }
                if ($hasName) { $pluginName = [string]$pluginConfig['Name'] }

                $hasSource = $false
                try { $hasSource = $pluginConfig.ContainsKey('Source') } catch { $hasSource = $false }
                if (-not $hasSource) {
                    try { $hasSource = $pluginConfig.Contains('Source') } catch { $hasSource = $false }
                }
                if (-not $hasSource) {
                    try {
                        foreach ($k in $pluginConfig.Keys) {
                            if ($k -eq 'Source') { $hasSource = $true; break }
                        }
                    }
                    catch { $hasSource = $false }
                }
                if ($hasSource) { $source = [string]$pluginConfig['Source'] }
            }
            else {
                if (Get-Command -Name Test-PSmmPluginsConfigMember -ErrorAction SilentlyContinue) {
                    if (Test-PSmmPluginsConfigMember -Object $pluginConfig -Name 'Name') {
                        $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
                    }
                    if (Test-PSmmPluginsConfigMember -Object $pluginConfig -Name 'Source') {
                        $source = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Source')
                    }
                }
                else {
                    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
                    $source = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Source')
                }
            }
        }
        catch {
            Write-Verbose "Confirm-Plugins: failed reading plugin config Name/Source: $($_.Exception.Message)"
            # Leave as null; validation below will handle
        }

        # Ensure State bucket exists to store version metadata

        $hasState = $false
        try {
            if ($pluginConfig -is [System.Collections.IDictionary]) {
                try { $hasState = $pluginConfig.ContainsKey('State') } catch { $hasState = $false }
                if (-not $hasState) {
                    try { $hasState = $pluginConfig.Contains('State') } catch { $hasState = $false }
                }
                if (-not $hasState) {
                    try {
                        foreach ($k in $pluginConfig.Keys) {
                            if ($k -eq 'State') { $hasState = $true; break }
                        }
                    }
                    catch { $hasState = $false }
                }
            }
            else {
                $hasState = $false
                if (Get-Command -Name Test-PSmmPluginsConfigMember -ErrorAction SilentlyContinue) {
                    $hasState = Test-PSmmPluginsConfigMember -Object $pluginConfig -Name 'State'
                }
            }
        }
        catch {
            $hasState = $false
        }

        if (-not $hasState -or $null -eq $pluginConfig.State) {
            $pluginConfig.State = @{}
        }

        Write-PSmmLog -Level INFO -Context "Check $pluginName" -Message "Getting latest download URL for $pluginName from source: $source" -Console -File

        switch ($source) {
            'GitHub' {
                # Token is optional; if not provided, fall back to unauthenticated
                if ($null -eq $Token) {
                    Write-Verbose 'GitHub token not provided; proceeding unauthenticated'
                }
                $url = Get-LatestUrlFromGitHub -Plugin $Plugin -Token $Token -Http $Http -Crypto $Crypto `
                    -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process
            }
            'Url' {
                $urlFunctionName = "Get-LatestUrlFromUrl-$pluginName"

                if (Test-PluginFunction -Name $urlFunctionName) {
                    Write-PSmmLog -Level INFO -Context "Check $pluginName" -Message "Using custom URL function: $urlFunctionName" -Console -File
                    $url = & $urlFunctionName -Plugin $Plugin -Paths $Paths -ServiceContainer $ServiceContainer
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
        $pn = Resolve-PluginNameSafe -PluginOrConfig $Plugin
        Write-Warning "Failed to get latest download URL for ${pn}: $_"
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
        $pluginName = Resolve-PluginNameSafe -PluginOrConfig $Plugin
        # Mark injected but unused parameter as intentionally unused for static analysis
        $null = $Process
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
        $pn = Resolve-PluginNameSafe -PluginOrConfig $Plugin
        Write-PSmmLog -Level ERROR -Context "Download $pn" `
            -Message "Failed to download $pn" -ErrorRecord $_ -Console -File
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
        $pluginName = Resolve-PluginNameSafe -PluginOrConfig $Plugin
        $extension = [System.IO.Path]::GetExtension($InstallerPath).ToLower()

        Write-Verbose "Installing $pluginName from: $InstallerPath (Type: $extension)"

        switch ($extension) {
            '.msi' {
                Write-Verbose 'Launching MSI installer...'
                $result = $Process.StartProcess('msiexec.exe', @('/i', "`"$InstallerPath`""))
                if (-not $result.Success) {
                    $ex = [ProcessException]::new("MSI installer failed", "msiexec.exe")
                    $ex.SetExitCode($result.ExitCode)
                    throw $ex
                }
            }
            '.exe' {
                Write-Verbose 'Launching EXE installer...'
                $result = $Process.StartProcess($InstallerPath, @())
                if (-not $result.Success) {
                    $ex = [ProcessException]::new("EXE installer failed", [System.IO.Path]::GetFileNameWithoutExtension($InstallerPath))
                    $ex.SetExitCode($result.ExitCode)
                    throw $ex
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
                    $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -FileSystem $FileSystem -Process $Process
                }
                catch {
                    throw [PluginRequirementException]::new("7z is required to extract .7z archives: $($_)", "7z", $_.Exception)
                }

                # First, test archive integrity for clearer diagnostics (let PowerShell handle quoting)
                $testResult = $Process.InvokeCommand($sevenZipCmd, @('t', $InstallerPath))
                if (-not $testResult.Success) {
                    $ex = [ProcessException]::new("7z archive test failed", "7z", $_.Exception)
                    $ex.SetExitCode($testResult.ExitCode)
                    throw $ex
                }

                # Extract archive
                $result = $Process.InvokeCommand($sevenZipCmd, @('x', $InstallerPath, "-o$extractPath", '-y'))
                if (-not $result.Success) {
                    $ex = [ProcessException]::new("7z extraction failed", "7z", $_.Exception)
                    $ex.SetExitCode($result.ExitCode)
                    throw $ex
                }
            }
            default {
                throw [PluginRequirementException]::new("Unsupported installer type: $extension", "Installer")
            }
        }

        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" `
            -Message "Installation complete for $InstallerPath" -Console -File
    }
    catch {
        $pn = Resolve-PluginNameSafe -PluginOrConfig $Plugin
        Write-PSmmLog -Level ERROR -Context "Install $pn" `
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
        $ServiceContainer
    )

    try {
        $pluginName = Resolve-PluginNameSafe -PluginOrConfig $Plugin
        Write-Verbose "Starting installation process for: $pluginName"

        # Resolve services from ServiceContainer
        $Http = $null
        $FileSystem = $null
        $Environment = $null
        $PathProvider = $null
        $Process = $null

        if ($null -ne $ServiceContainer) {
            try {
                $Http = $ServiceContainer.Resolve('Http')
                $null = $ServiceContainer.Resolve('Crypto')
                $FileSystem = $ServiceContainer.Resolve('FileSystem')
                $Environment = $ServiceContainer.Resolve('Environment')
                $PathProvider = $ServiceContainer.Resolve('PathProvider')
                $Process = $ServiceContainer.Resolve('Process')
            }
            catch {
                Write-Verbose "Failed to resolve services from ServiceContainer: $_"
            }
        }

        if ($null -eq $PathProvider) {
            try {
                $pathsCandidate = Get-PSmmPluginsConfigMemberValue -Object $Config -Name 'Paths'
                if ($null -ne $pathsCandidate -and ($pathsCandidate -is [IPathProvider])) {
                    $PathProvider = [PathProvider]::new([IPathProvider]$pathsCandidate)
                }
            }
            catch {
                Write-Verbose "Failed to bind PathProvider from Config.Paths: $($_.Exception.Message)"
            }
        }

        if ($null -eq $PathProvider) {
            try {
                $globalServiceContainer = Get-Variable -Name 'PSmmServiceContainer' -Scope Global -ValueOnly -ErrorAction Stop
                $PathProvider = $globalServiceContainer.Resolve('PathProvider')
            }
            catch {
                Write-Verbose "Failed to resolve PathProvider from global ServiceContainer: $($_.Exception.Message)"
            }
        }

        if ($null -eq $PathProvider) {
            $PathProvider = [PathProvider]::new()
        }

        # Prefer an already-secure token if available; otherwise build SecureString safely
        $token = $null

        $secrets = $null
        if ($null -ne $Config) {
            $secrets = Get-PSmmPluginsConfigMemberValue -Object $Config -Name 'Secrets'
        }

        if ($null -ne $secrets) {
            if ($secrets -is [System.Collections.IDictionary]) {
                $hasGitHubToken = $false
                try { $hasGitHubToken = $secrets.ContainsKey('GitHubToken') } catch { $hasGitHubToken = $false }
                if (-not $hasGitHubToken) {
                    try { $hasGitHubToken = $secrets.Contains('GitHubToken') } catch { $hasGitHubToken = $false }
                }
                if (-not $hasGitHubToken) {
                    try {
                        foreach ($k in $secrets.Keys) {
                            if ($k -eq 'GitHubToken') { $hasGitHubToken = $true; break }
                        }
                    }
                    catch { $hasGitHubToken = $false }
                }

                if ($hasGitHubToken -and $secrets['GitHubToken'] -is [System.Security.SecureString]) {
                    $token = $secrets['GitHubToken']
                }
            }
            else {
                # If the secrets object exposes a SecureString property, use it directly
                if (Get-Command -Name Test-PSmmPluginsConfigMember -ErrorAction SilentlyContinue) {
                    if (Test-PSmmPluginsConfigMember -Object $secrets -Name 'GitHubToken') {
                        $secretsToken = Get-PSmmPluginsConfigMemberValue -Object $secrets -Name 'GitHubToken'
                        if ($secretsToken -is [System.Security.SecureString]) {
                            $token = $secretsToken
                        }
                    }
                }
            }
        }

        # If token not available from config, fallback to system vault
        if ($null -eq $token -and (Get-Command -Name Get-SystemSecret -ErrorAction SilentlyContinue)) {
            try {
                $token = Get-SystemSecret -SecretType 'GitHub-Token' `
                    -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process -Optional
            }
            catch {
                Write-Verbose "Could not retrieve GitHub token from system vault: $_"
            }
        }

        # Get latest download URL
        $url = Get-LatestDownloadUrl -Plugin $Plugin -Paths $Paths -Token $token -ServiceContainer $ServiceContainer

        if (-not $url) {
            Write-Warning "Could not determine download URL for: $pluginName"
            return
        }

        # Download installer (custom or default)
        $installerFunctionName = "Get-Installer-$pluginName"

        if (Test-PluginFunction -Name $installerFunctionName) {
            Write-Verbose "Using custom installer download function: $installerFunctionName"
            $installerPath = & $installerFunctionName -Url $url -Plugin $Plugin -Paths $Paths -ServiceContainer $ServiceContainer
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
            & $installFunctionName -Plugin $Plugin -Paths $Paths -InstallerPath $installerPath -ServiceContainer $ServiceContainer
        }
        else {
            Invoke-Installer -Plugin $Plugin -Paths $Paths -InstallerPath $installerPath -Process $Process -FileSystem $FileSystem
        }
    }
    catch {
        $pn = Resolve-PluginNameSafe -PluginOrConfig $Plugin
        Write-PSmmLog -Level ERROR -Context 'Install Plugin' `
            -Message "Failed to install $pn" -ErrorRecord $_ -Console -File
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
        $Environment,

        [Parameter(Mandatory)]
        $PathProvider,

        [Parameter(Mandatory)]
        $Process
    )

    try {
        $pluginName = Resolve-PluginNameSafe -PluginOrConfig $Plugin

        # Prefer an already-secure token if available; otherwise build SecureString safely
        $token = $null

        $secrets = $null
        if ($null -ne $Config) {
            $secrets = Get-PSmmPluginsConfigMemberValue -Object $Config -Name 'Secrets'
        }

        if ($null -ne $secrets) {
            if ($secrets -is [System.Collections.IDictionary]) {
                $hasGitHubToken = $false
                try { $hasGitHubToken = $secrets.ContainsKey('GitHubToken') } catch { $hasGitHubToken = $false }
                if (-not $hasGitHubToken) {
                    try { $hasGitHubToken = $secrets.Contains('GitHubToken') } catch { $hasGitHubToken = $false }
                }
                if (-not $hasGitHubToken) {
                    try {
                        foreach ($k in $secrets.Keys) {
                            if ($k -eq 'GitHubToken') { $hasGitHubToken = $true; break }
                        }
                    }
                    catch { $hasGitHubToken = $false }
                }

                if ($hasGitHubToken -and $secrets['GitHubToken'] -is [System.Security.SecureString]) {
                    $token = $secrets['GitHubToken']
                }
            }
            else {
                # If the secrets object exposes a SecureString property, use it directly
                if (Get-Command -Name Test-PSmmPluginsConfigMember -ErrorAction SilentlyContinue) {
                    if (Test-PSmmPluginsConfigMember -Object $secrets -Name 'GitHubToken') {
                        $secretsToken = Get-PSmmPluginsConfigMemberValue -Object $secrets -Name 'GitHubToken'
                        if ($secretsToken -is [System.Security.SecureString]) {
                            $token = $secretsToken
                        }
                    }
                }
            }
        }

        # If token not available from config, fallback to system vault
        if ($null -eq $token -and (Get-Command -Name Get-SystemSecret -ErrorAction SilentlyContinue)) {
            try {
                $token = Get-SystemSecret -SecretType 'GitHub-Token' `
                    -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process -Optional
            }
            catch {
                Write-Verbose "Could not retrieve GitHub token from system vault: $_"
            }
        }

        # Get latest version information
        Get-LatestDownloadUrl -Plugin $Plugin -Paths $Paths -Token $token -Http $Http -Crypto $Crypto `
            -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process | Out-Null

        $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
        $state = Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State'

        $currentVersion = Get-PSmmPluginsConfigMemberValue -Object $state -Name 'CurrentVersion'
        $latestVersion = Get-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestVersion'

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
        $pn = Resolve-PluginNameSafe -PluginOrConfig $Plugin
        Write-Warning "Failed to check for updates for ${pn}: $_"
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
        $pluginName = Resolve-PluginNameSafe -PluginOrConfig $Plugin
        $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
        $state = Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State'

        $currentVersion = Get-PSmmPluginsConfigMemberValue -Object $state -Name 'CurrentVersion'
        $latestVersion = Get-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestVersion'

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
            Install-Plugin -Plugin $Plugin -Paths $Paths -Config $Config -Http $Http -Crypto $Crypto `
                -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process
        }
        else {
            Write-PSmmLog -Level INFO -Context "Update $pluginName" `
                -Message "Skipped update for $pluginName" -Console -File
        }
    }
    catch {
        $pn = Resolve-PluginNameSafe -PluginOrConfig $Plugin
        Write-PSmmLog -Level ERROR -Context 'Update Plugin' `
            -Message "Failed to update $pn" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
