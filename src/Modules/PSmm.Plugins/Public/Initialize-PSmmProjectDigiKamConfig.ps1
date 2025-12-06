#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Initializes project-specific digiKam configuration files and directories.

.DESCRIPTION
    Creates and configures all necessary files and directories for a project-specific
    digiKam instance, including:
    - Project-specific digiKam-rc configuration file
    - Database directory with unique port allocation
    - APPDIR configuration for digiKam data isolation
    - MariaDB instance configuration

.PARAMETER Config
    The AppConfiguration object containing all application settings and paths.

.PARAMETER ProjectName
    The name of the project to initialize digiKam configuration for.

.PARAMETER Force
    Forces recreation of configuration files even if they already exist.

.EXAMPLE
    Initialize-PSmmProjectDigiKamConfig -Config $appConfig -ProjectName "MyProject"
    # Initializes digiKam configuration for "MyProject"

.EXAMPLE
    Initialize-PSmmProjectDigiKamConfig -Config $appConfig -ProjectName "MyProject" -Force
    # Forces recreation of configuration files

.OUTPUTS
    Hashtable containing configuration details including allocated port and paths.

.NOTES
    Author           : Der Mosh
    Version          : 1.0.0
    Created          : 2025-11-05

    Creates          : - ProjectPath\Config\digiKam-rc
                      - ProjectPath\Config\digiKam\ (APPDIR)
                      - ProjectPath\Databases\digiKam\

    Related          : Start-PSmmdigiKam, Get-PSmmAvailablePort

.LINK
    https://www.digikam.org/
#>

function Initialize-PSmmProjectDigiKamConfig {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        $Config,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        $FileSystem,

        [Parameter(Mandatory)]
        $PathProvider,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        Write-Verbose "Initializing digiKam configuration for project: $ProjectName"
    }

    process {
        try {
            # Confirm the action with ShouldProcess
            if (-not $PSCmdlet.ShouldProcess($ProjectName, 'Initialize digiKam configuration')) {
                Write-Verbose 'Initialize digiKam configuration operation cancelled by user'
                return @{}
            }

            # Get project path - check if this is the current project
            $projectPath = $null
            if ($Config.Projects.ContainsKey('Current') -and
                $Config.Projects.Current.ContainsKey('Name') -and
                $Config.Projects.Current.Name -eq $ProjectName -and
                $Config.Projects.Current.ContainsKey('Path')) {
                $projectPath = $Config.Projects.Current.Path
            }
            else {
                # Project is not currently selected, need to find it
                # For now, we'll require the project to be selected first
                throw [ConfigurationException]::new("Project '$ProjectName' is not currently selected. Please select the project first using Select-PSmmProject.", 'ProjectNotSelected')
            }

            if (-not $projectPath -or -not ($FileSystem.TestPath($projectPath))) {
                throw [ConfigurationException]::new("Project path not found for project: $ProjectName", 'ProjectPath')
            }

            # Define project-specific paths
            $projectConfigPath = $PathProvider.CombinePath($projectPath,'Config')
            $projectDatabasePath = $PathProvider.CombinePath($projectPath,'Databases','digiKam')
            $projectDigiKamAppDir = $PathProvider.CombinePath($projectConfigPath,'digiKam')
            $digiKamRcPath = $PathProvider.CombinePath($projectConfigPath,'digiKam-rc')

            # Create necessary directories
            $directories = @($projectConfigPath, $projectDatabasePath, $projectDigiKamAppDir)
            foreach ($dir in $directories) {
                if (-not ($FileSystem.TestPath($dir))) {
                    Write-Verbose "Creating directory: $dir"
                    $null = $FileSystem.NewDirectory($dir)
                }
            }

            # Get available port for this project
            $databasePort = Get-PSmmAvailablePort -Config $Config -ProjectName $ProjectName -Force:$Force

            # Get plugin paths
            $digiKamInstallations = $FileSystem.GetChildItem($Config.Paths.App.Plugins.Root, 'digiKam-*', 'Directory')
            if (-not $digiKamInstallations) {
                throw [PluginRequirementException]::new('digiKam installation not found in Plugins directory', 'digiKam')
            }
            $digiKamPluginsPath = $digiKamInstallations[0].FullName

            $mariaDbInstallations = $FileSystem.GetChildItem($Config.Paths.App.Plugins.Root, 'mariadb-*', 'Directory')
            if (-not $mariaDbInstallations) {
                throw [PluginRequirementException]::new('MariaDB installation not found in Plugins directory', 'MariaDB')
            }
            $mariaDbPath = $mariaDbInstallations[0].FullName

            # Check if digiKam-rc already exists
            if (($FileSystem.TestPath($digiKamRcPath)) -and -not $Force.IsPresent) {
                Write-Verbose "DigiKam configuration already exists for project $ProjectName, using existing configuration"
                Write-PSmmLog -Level INFO -Context 'Initialize-PSmmProjectDigiKamConfig' `
                    -Message "Using existing digiKam configuration for project $ProjectName" -Console -File
            }
            else {
                # Load template and replace variables
                $templatePath = $PathProvider.CombinePath(@($Config.Paths.App.ConfigDigiKam, 'digiKam-rc-template'))
                if (-not ($FileSystem.TestPath($templatePath))) {
                    throw [ConfigurationException]::new("DigiKam template file not found: $templatePath", 'TemplateFile')
                }

                Write-Verbose "Reading digiKam template from: $templatePath"
                $templateContent = $FileSystem.GetContent($templatePath)

                # Replace template variables
                $configContent = $templateContent -replace '%%ProjectName%%', $ProjectName
                $configContent = $configContent -replace '%%ProjectPath%%', ($projectPath -replace '\\', '/')
                $configContent = $configContent -replace '%%DatabasePort%%', $databasePort
                $configContent = $configContent -replace '%%DatabasePath%%', ($projectDatabasePath -replace '\\', '/')
                $configContent = $configContent -replace '%%DigiKamPluginsPath%%', ($digiKamPluginsPath -replace '\\', '/')
                $configContent = $configContent -replace '%%MariaDBPath%%', ($mariaDbPath -replace '\\', '/')

                # Write project-specific configuration
                Write-Verbose "Writing digiKam configuration to: $digiKamRcPath"
                $FileSystem.SetContent($digiKamRcPath, $configContent)

                Write-PSmmLog -Level SUCCESS -Context 'Initialize-PSmmProjectDigiKamConfig' `
                    -Message "Created digiKam configuration for project $ProjectName on port $databasePort" -Console -File
            }

            # Copy metadata profile if it doesn't exist
            $sourceProfilePath = $PathProvider.CombinePath($Config.Paths.App.ConfigDigiKam,'digiKam-metadataProfile.dkamp')
            $targetProfilePath = $PathProvider.CombinePath($projectDigiKamAppDir,'digiKam-metadataProfile.dkamp')

            if (($FileSystem.TestPath($sourceProfilePath)) -and (-not ($FileSystem.TestPath($targetProfilePath)) -or $Force.IsPresent)) {
                Write-Verbose "Copying metadata profile to project APPDIR"
                $FileSystem.CopyItem($sourceProfilePath,$targetProfilePath,$true)
            }

            # Create configuration result
            $configResult = @{
                ProjectName = $ProjectName
                ProjectPath = $projectPath
                ConfigPath = $projectConfigPath
                DatabasePath = $projectDatabasePath
                AppDir = $projectDigiKamAppDir
                DigiKamRcPath = $digiKamRcPath
                DatabasePort = $databasePort
                DigiKamPluginsPath = $digiKamPluginsPath
                MariaDbPath = $mariaDbPath
                MetadataProfile = $targetProfilePath
            }

            Write-Verbose "DigiKam configuration initialized successfully for project $ProjectName"
            return $configResult
        }
        catch {
            $errorMessage = if ($null -ne $_.Exception.PSObject.Properties['Context']) {
                "[$($_.Exception.Context)] $($_.Exception.Message)"
            }
            else {
                "Failed to initialize digiKam configuration for project $ProjectName`: $_"
            }

            Write-PSmmLog -Level ERROR -Context 'Initialize-PSmmProjectDigiKamConfig' `
                -Message $errorMessage -ErrorRecord $_ -Console -File
            throw
        }
    }

    end {
        Write-Verbose 'Initialize-PSmmProjectDigiKamConfig completed'
    }
}
