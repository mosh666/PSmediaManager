#Requires -Version 7.5.4
Set-StrictMode -Version Latest

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

    # Validate Config is AppConfiguration type
    if ($Config.GetType().Name -ne 'AppConfiguration') {
        throw [ArgumentException]::new("Config parameter must be of type [AppConfiguration]", 'Config')
    }

    # Build internal runtime projection for helpers
    $Run = @{
        Projects = @{
            Current = @{}
            Paths = $Config.Projects.Paths
            Registry = $Config.Projects.Registry
        }
    }

    try {
        Write-Verbose "Selecting project: $pName"
        if (-not [string]::IsNullOrWhiteSpace($SerialNumber)) {
            Write-Verbose "Targeting specific disk with SerialNumber: $SerialNumber"
        }

        # Find the project across all storage groups and drives
        $AllProjects = Get-PSmmProjects -Config $Config -FileSystem $FileSystem
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

        # Initialize Current project structure if it doesn't exist
        if (-not $Run.Projects.ContainsKey('Current')) {
            $Run.Projects.Current = @{}
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
        $Run.Projects.Current.StorageDrive = @{
            Label = $storageDrive.Label
            DriveLetter = $storageDrive.DriveLetter
            SerialNumber = $storageDrive.SerialNumber
            DriveLabel = $StorageDriveLabel
        }

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

        # Sync Current project back to Config if using AppConfiguration
        $Config.Projects.Current = $Run.Projects.Current

        # Load project-specific plugin manifest and install enabled optional plugins
        if (-not $Config.Plugins) {
            $Config.Plugins = @{ Global = $null; Project = $null; Resolved = $null; Paths = @{ Global = $null; Project = $null } }
        }

        $projectPluginsPath = $PathProvider.CombinePath(@($Run.Projects.Current.Config,'PSmm','PSmm.Plugins.psd1'))
        $Config.Plugins.Paths.Project = $projectPluginsPath

        if ($FileSystem.TestPath($projectPluginsPath)) {
            $projectPlugins = Import-PowerShellDataFile -Path $projectPluginsPath -ErrorAction Stop
            $Config.Plugins.Project = if ($projectPlugins.ContainsKey('Plugins')) { $projectPlugins.Plugins } else { $projectPlugins }
        }
        else {
            $Config.Plugins.Project = $null
        }

        try {
            # Use pre-instantiated services from global context when available,
            # otherwise instantiate new ones (for standalone/test usage)
            if ($global:PSmmServices) {
                $httpService = $global:PSmmServices.Http
                $cryptoService = $global:PSmmServices.Crypto
                $environmentService = $global:PSmmServices.Environment
                $processService = $global:PSmmServices.Process
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
