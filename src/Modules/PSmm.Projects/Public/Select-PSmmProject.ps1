#Requires -Version 7.5.4
Set-StrictMode -Version Latest

if (-not (Get-Command -Name 'Get-PSmmProjectsConfigMemberValue' -ErrorAction SilentlyContinue)) {
    $helpersPath = Join-Path -Path $PSScriptRoot -ChildPath '..\\Private\\ConfigMemberAccessHelpers.ps1'
    if (Test-Path -Path $helpersPath) {
        . $helpersPath
    }
}

if (-not (Get-Command -Name 'Set-PSmmProjectsConfigMemberValue' -ErrorAction SilentlyContinue)) {
    $helpersPath = Join-Path -Path $PSScriptRoot -ChildPath '..\\Private\\ConfigMemberAccessHelpers.ps1'
    if (Test-Path -Path $helpersPath) {
        . $helpersPath
    }
}

function Select-PSmmProject {
    <#
    .SYNOPSIS
        Selects and activates a specific PSmediaManager project.

    .DESCRIPTION
        Sets the current active project by updating the configuration with
        project-specific paths for config, logs, backup, databases, documents,
        libraries, and vault. Creates KeePass database if it doesn't exist.

    .PARAMETER Config
        Application configuration object (AppConfiguration).
        Preferred modern approach with strongly-typed configuration.


    .PARAMETER pName
        The name of the project to select and activate.

    .PARAMETER SerialNumber
        Optional. The serial number of the specific disk to select the project from.
        If not specified, searches Master drives first, then Backup drives.

    .PARAMETER FileSystem
        File system service for testing. Defaults to FileSystemService instance.

    .EXAMPLE
        Select-PSmmProject -Config $appConfig -pName "MyVideoProject"

    .EXAMPLE
        Select-PSmmProject -Config $appConfig -pName "MyVideoProject" -SerialNumber "ABC123"

    .NOTES
        This function modifies the Projects.Current configuration.
        Requires KeePass functions to be available for vault initialization.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,  # Uses [object] instead of [AppConfiguration] to avoid type resolution issues when module is loaded

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$pName,

        [Parameter()]
        [string]$SerialNumber = $null,

        [Parameter(Mandatory)]
        $FileSystem,

        [Parameter(Mandatory)]
        $PathProvider
    )

    # Prefer a strongly-typed config when the class is available, but keep legacy/fallback behavior
    # to avoid breaking callers when PSmm classes aren't loaded yet.
    $appConfigType = 'AppConfiguration' -as [type]
    if ($null -ne $appConfigType -and -not ($Config -is $appConfigType)) {
        try {
            $Config = $appConfigType::FromObject($Config)
        }
        catch {
            Write-Verbose "[Select-PSmmProject] AppConfiguration::FromObject() failed; falling back to legacy config handling: $($_.Exception.Message)"
        }
    }

    # Ensure PathProvider is available, preferring DI/global instance, otherwise wrap Config.Paths when possible.
    $pathProviderType = 'PathProvider' -as [type]
    $iPathProviderType = 'IPathProvider' -as [type]
    if ($null -eq $PathProvider) {
        $resolved = $null

        try {
            $globalServiceContainer = Get-Variable -Name 'PSmmServiceContainer' -Scope Global -ValueOnly -ErrorAction Stop
            if ($null -ne $globalServiceContainer) {
                try {
                    $resolved = $globalServiceContainer.Resolve('PathProvider')
                }
                catch {
                    $resolved = $null
                }
            }
        }
        catch {
            $resolved = $null
        }

        if ($null -ne $resolved) {
            $PathProvider = $resolved
        }
        elseif ($null -ne $pathProviderType -and $null -ne $iPathProviderType) {
            $configPaths = Get-PSmmProjectsConfigMemberValue -Object $Config -Name 'Paths'
            if ($null -ne $configPaths -and $configPaths -is $iPathProviderType) {
                $PathProvider = $pathProviderType::new([IPathProvider]$configPaths)
            }
        }

        if ($null -eq $PathProvider -and $null -ne $pathProviderType) {
            $PathProvider = $pathProviderType::new()
        }
    }
    elseif ($null -ne $pathProviderType -and $null -ne $iPathProviderType -and $PathProvider -is $iPathProviderType -and -not ($PathProvider -is $pathProviderType)) {
        $PathProvider = $pathProviderType::new([IPathProvider]$PathProvider)
    }

    # Support legacy dictionary-shaped configs by normalizing key members into typed models
    # and using a PSCustomObject view for property access.
    $configMap = $null
    if ($Config -is [System.Collections.IDictionary]) {
        $configMap = $Config

        $hasProjects = $false
        try { $hasProjects = $configMap.ContainsKey('Projects') } catch { $hasProjects = $false }
        if (-not $hasProjects) {
            try { $hasProjects = $configMap.Contains('Projects') } catch { $hasProjects = $false }
        }
        if (-not $hasProjects) {
            try {
                foreach ($k in $configMap.Keys) {
                    if ($k -eq 'Projects') { $hasProjects = $true; break }
                }
            }
            catch { $hasProjects = $false }
        }

        if (-not $hasProjects -or $null -eq $configMap['Projects']) {
            $configMap['Projects'] = [ProjectsConfig]::FromObject($null)
        }
        else {
            $configMap['Projects'] = [ProjectsConfig]::FromObject($configMap['Projects'])
        }

        $hasPlugins = $false
        try { $hasPlugins = $configMap.ContainsKey('Plugins') } catch { $hasPlugins = $false }
        if (-not $hasPlugins) {
            try { $hasPlugins = $configMap.Contains('Plugins') } catch { $hasPlugins = $false }
        }
        if (-not $hasPlugins) {
            try {
                foreach ($k in $configMap.Keys) {
                    if ($k -eq 'Plugins') { $hasPlugins = $true; break }
                }
            }
            catch { $hasPlugins = $false }
        }

        if (-not $hasPlugins -or $null -eq $configMap['Plugins']) {
            $configMap['Plugins'] = [PluginsConfig]::FromObject($null)
        }
        else {
            $configMap['Plugins'] = [PluginsConfig]::FromObject($configMap['Plugins'])
        }

        $hasStorage = $false
        try { $hasStorage = $configMap.ContainsKey('Storage') } catch { $hasStorage = $false }
        if (-not $hasStorage) {
            try { $hasStorage = $configMap.Contains('Storage') } catch { $hasStorage = $false }
        }
        if (-not $hasStorage) {
            try {
                foreach ($k in $configMap.Keys) {
                    if ($k -eq 'Storage') { $hasStorage = $true; break }
                }
            }
            catch { $hasStorage = $false }
        }

        if (-not $hasStorage -or $null -eq $configMap['Storage']) {
            $configMap['Storage'] = @{}
        }

        $Config = [pscustomobject]$configMap
    }

    # Ensure Projects and Plugins are typed models (or have compatible shapes) before any dot access
    $projectsConfig = Get-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects'
    if ($null -eq $projectsConfig) {
        $projectsConfig = [ProjectsConfig]::FromObject($null)
        Set-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig
    }
    elseif ($projectsConfig -isnot [ProjectsConfig]) {
        $projectsConfig = [ProjectsConfig]::FromObject($projectsConfig)
        Set-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig
    }

    $projectsRegistry = Get-PSmmProjectsConfigMemberValue -Object $projectsConfig -Name 'Registry'
    if ($null -eq $projectsRegistry) {
        $projectsRegistry = [ProjectsRegistryCache]::new()
        Set-PSmmProjectsConfigMemberValue -Object $projectsConfig -Name 'Registry' -Value $projectsRegistry
        Set-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig
    }
    else {
        $projectsRegistry = [ProjectsRegistryCache]::FromObject($projectsRegistry)
        Set-PSmmProjectsConfigMemberValue -Object $projectsConfig -Name 'Registry' -Value $projectsRegistry
        Set-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig
    }

    $pluginsConfig = Get-PSmmProjectsConfigMemberValue -Object $Config -Name 'Plugins'
    $pluginsConfig = [PluginsConfig]::FromObject($pluginsConfig)
    if ($null -eq $pluginsConfig.Paths) {
        $pluginsConfig.Paths = [PluginsPathsConfig]::new()
    }
    Set-PSmmProjectsConfigMemberValue -Object $Config -Name 'Plugins' -Value $pluginsConfig

    # Build internal runtime projection for helpers
    $pathsSource = Get-PSmmProjectsConfigMemberValue -Object $projectsConfig -Name 'Paths'
    $projectPaths = if ($null -ne $pathsSource) {
        [ProjectsPathsConfig]::FromObject($pathsSource).ToHashtable()
    }
    else {
        @{}
    }
    $Run = [ProjectSelectionContext]::new($projectPaths, $projectsRegistry)

    try {
        Write-Verbose "Selecting project: $pName"
        if (-not [string]::IsNullOrWhiteSpace($SerialNumber)) {
            Write-Verbose "Targeting specific disk with SerialNumber: $SerialNumber"
        }

        # Find the project across all storage groups and drives
        $projectsServiceContainer = [ServiceContainer]::new()
        $projectsServiceContainer.RegisterSingleton('FileSystem', $FileSystem)
        $AllProjects = Get-PSmmProjects -Config $Config -ServiceContainer $projectsServiceContainer
        $FoundProject = $null
        $StorageDriveLabel = $null

        # If SerialNumber is specified, search only on that specific disk
        if (-not [string]::IsNullOrWhiteSpace($SerialNumber)) {
            # Search in Master drives
            foreach ($driveLabel in $AllProjects.Master.Keys) {
                $projectsOnDrive = $AllProjects.Master[$driveLabel]
                foreach ($proj in $projectsOnDrive) {
                    if ($proj.Name -eq $pName -and $proj.SerialNumber -eq $SerialNumber) {
                        $FoundProject = $proj
                        $StorageDriveLabel = $driveLabel
                        break
                    }
                }
                if ($FoundProject) { break }
            }

            # If not found in Master, search in Backup drives
            if (-not $FoundProject) {
                foreach ($driveLabel in $AllProjects.Backup.Keys) {
                    $projectsOnDrive = $AllProjects.Backup[$driveLabel]
                    foreach ($proj in $projectsOnDrive) {
                        if ($proj.Name -eq $pName -and $proj.SerialNumber -eq $SerialNumber) {
                            $FoundProject = $proj
                            $StorageDriveLabel = $driveLabel
                            break
                        }
                    }
                    if ($FoundProject) { break }
                }
            }
        }
        else {
            # No SerialNumber specified, use original search logic (Master first, then Backup)
            # Search in Master drives
            foreach ($driveLabel in $AllProjects.Master.Keys) {
                $projectsOnDrive = $AllProjects.Master[$driveLabel]
                foreach ($proj in $projectsOnDrive) {
                    if ($proj.Name -eq $pName) {
                        $FoundProject = $proj
                        $StorageDriveLabel = $driveLabel
                        break
                    }
                }
                if ($FoundProject) { break }
            }

            # If not found in Master, search in Backup drives
            if (-not $FoundProject) {
                foreach ($driveLabel in $AllProjects.Backup.Keys) {
                    $projectsOnDrive = $AllProjects.Backup[$driveLabel]
                    foreach ($proj in $projectsOnDrive) {
                        if ($proj.Name -eq $pName) {
                            $FoundProject = $proj
                            $StorageDriveLabel = $driveLabel
                            break
                        }
                    }
                    if ($FoundProject) { break }
                }
            }
        }

        if (-not $FoundProject) {
            $serialMsg = if (-not [string]::IsNullOrWhiteSpace($SerialNumber)) { " on disk with SerialNumber '$SerialNumber'" } else { "" }
            throw [ProjectException]::new("Project '$pName' not found in any storage location$serialMsg", "Project lookup failure")
        }

        # Get the actual storage drive information
        $storageDrive = Get-StorageDrive | Where-Object { $_.SerialNumber -eq $FoundProject.SerialNumber } | Select-Object -First 1
        if (-not $storageDrive) {
            throw [StorageException]::new("Storage drive for project '$pName' not found or not mounted", $FoundProject.SerialNumber)
        }

        $projectBasePath = $FoundProject.Path

        # Verify project exists
        if (-not $FileSystem.TestPath($projectBasePath)) {
            throw [ProjectException]::new("Project '$pName' does not exist at: $projectBasePath", $projectBasePath)
        }

        # Set project name
        $Run.Projects.Current.Name = $pName

        # Update all project-specific paths
        $Run.Projects.Current.Path = $projectBasePath
        $Run.Projects.Current.Config = $PathProvider.CombinePath(@($projectBasePath,'Config'))
        $Run.Projects.Current.Backup = $PathProvider.CombinePath(@($projectBasePath,'Backup'))
        $Run.Projects.Current.Databases = $PathProvider.CombinePath(@($projectBasePath,'Databases'))
        $Run.Projects.Current.Documents = $PathProvider.CombinePath(@($projectBasePath,'Documents'))
        $Run.Projects.Current.Libraries = $PathProvider.CombinePath(@($projectBasePath,'Libraries'))
        $Run.Projects.Current.Vault = $PathProvider.CombinePath(@($projectBasePath,'Vault'))
        $Run.Projects.Current.Log = $PathProvider.CombinePath(@($projectBasePath,'Log'))

        # Store storage drive information
        $Run.Projects.Current.StorageDrive = [ProjectStorageDriveInfo]::new(
            $storageDrive.Label,
            $storageDrive.DriveLetter,
            $storageDrive.SerialNumber,
            $StorageDriveLabel
        )

        # Ensure vault exists
        $vaultPath = $Run.Projects.Current.Vault
        if (-not $FileSystem.TestPath($vaultPath)) {
            Write-Verbose "Vault not found, creating KeePass database for project: $pName"
            try {
                New-KeePassDatabase -vaultPath $vaultPath -dbName $pName
                Write-Verbose "KeePass database created successfully"
            }
            catch {
                Write-Warning "Failed to create KeePass database: $_"
            }
        }
        else {
            Write-Verbose "Project vault exists at: $vaultPath"
        }

        # Sync Current project back to Config as a typed model (supports legacy consumers via FromObject/ToHashtable)
        Set-PSmmProjectsConfigMemberValue -Object $projectsConfig -Name 'Current' -Value ([ProjectCurrentConfig]::FromObject($Run.Projects.Current.ToHashtable()))
        Set-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig

        # Load project-specific plugin manifest and install enabled optional plugins
        $pluginsConfig = [PluginsConfig]::FromObject($pluginsConfig)
        if ($null -eq $pluginsConfig.Paths) {
            $pluginsConfig.Paths = [PluginsPathsConfig]::new()
        }

        $projectPluginsPath = $PathProvider.CombinePath(@($Run.Projects.Current.Config,'PSmm','PSmm.Plugins.psd1'))
        $pluginsConfig.Paths.Project = $projectPluginsPath

        if ($FileSystem.TestPath($projectPluginsPath)) {
            $projectPlugins = Import-PowerShellDataFile -Path $projectPluginsPath -ErrorAction Stop
            if ($projectPlugins -is [System.Collections.IDictionary]) {
                $hasProjectPluginsKey = $false
                try { $hasProjectPluginsKey = $projectPlugins.ContainsKey('Plugins') } catch { $hasProjectPluginsKey = $false }
                if (-not $hasProjectPluginsKey) {
                    try { $hasProjectPluginsKey = $projectPlugins.Contains('Plugins') } catch { $hasProjectPluginsKey = $false }
                }
                if (-not $hasProjectPluginsKey) {
                    try {
                        foreach ($k in $projectPlugins.Keys) {
                            if ($k -eq 'Plugins') { $hasProjectPluginsKey = $true; break }
                        }
                    }
                    catch { $hasProjectPluginsKey = $false }
                }
                $pluginsConfig.Project = if ($hasProjectPluginsKey) { $projectPlugins['Plugins'] } else { $projectPlugins }
            }
            else {
                if (Test-PSmmProjectsConfigMember -Object $projectPlugins -Name 'Plugins') {
                    $pluginsConfig.Project = Get-PSmmProjectsConfigMemberValue -Object $projectPlugins -Name 'Plugins'
                }
                else {
                    $pluginsConfig.Project = $projectPlugins
                }
            }
        }
        else {
            $pluginsConfig.Project = $null
        }

        # Reset resolved cache to force re-merge on next confirmation
        $pluginsConfig.Resolved = $null
        Set-PSmmProjectsConfigMemberValue -Object $Config -Name 'Plugins' -Value $pluginsConfig

        try {
            # Use pre-instantiated services from global context when available,
            # otherwise instantiate new ones (for standalone/test usage)
            $globalServiceContainer = $null
            try {
                $globalServiceContainer = Get-Variable -Name 'PSmmServiceContainer' -Scope Global -ValueOnly -ErrorAction Stop
            }
            catch {
                Write-Verbose "[Select-PSmmProject] Global ServiceContainer not available: $($_.Exception.Message)"
                $globalServiceContainer = $null
            }

            if ($null -ne $globalServiceContainer) {
                $httpService = $globalServiceContainer.Resolve('Http')
                $cryptoService = $globalServiceContainer.Resolve('Crypto')
                $environmentService = $globalServiceContainer.Resolve('Environment')
                $processService = $globalServiceContainer.Resolve('Process')
            }
            else {
                $httpService = [HttpService]::new()
                $cryptoService = [CryptoService]::new()
                $environmentService = [EnvironmentService]::new()
                $processService = [ProcessService]::new()
            }

            # Create ServiceContainer for plugin confirmation
            $pluginServiceContainer = [ServiceContainer]::new()
            $pluginServiceContainer.RegisterSingleton('Http', $httpService)
            $pluginServiceContainer.RegisterSingleton('Crypto', $cryptoService)
            $pluginServiceContainer.RegisterSingleton('FileSystem', $FileSystem)
            $pluginServiceContainer.RegisterSingleton('Environment', $environmentService)
            $pluginServiceContainer.RegisterSingleton('PathProvider', $PathProvider)
            $pluginServiceContainer.RegisterSingleton('Process', $processService)

            Confirm-Plugins -Config $Config -ServiceContainer $pluginServiceContainer
        }
        catch {
            Write-Warning "Failed to confirm project plugins for '$pName': $_"
            throw
        }

        Write-Verbose "Project '$pName' selected successfully"
    }
    catch {
        Write-Error "Failed to select project '$pName': $_"
        throw
    }
}
