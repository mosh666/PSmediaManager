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
        [ValidateNotNull()]
        $FileSystem,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $PathProvider,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        if (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) {
            throw "Get-PSmmPluginsConfigMemberValue is not available. Ensure PSmm.Plugins is imported before calling Initialize-PSmmProjectDigiKamConfig."
        }

        if (-not (Get-Command -Name Test-PSmmPluginsConfigMember -ErrorAction SilentlyContinue)) {
            throw "Test-PSmmPluginsConfigMember is not available. Ensure PSmm.Plugins is imported before calling Initialize-PSmmProjectDigiKamConfig."
        }

        # Break-fast: PathProvider must be explicitly provided by DI.
        $pathProviderType = 'PathProvider' -as [type]
        $iPathProviderType = 'IPathProvider' -as [type]
        if ($null -eq $PathProvider) {
            throw 'PathProvider is required for Initialize-PSmmProjectDigiKamConfig (pass DI service).'
        }
        if ($null -ne $pathProviderType -and $null -ne $iPathProviderType -and $PathProvider -is $iPathProviderType -and -not ($PathProvider -is $pathProviderType)) {
            $PathProvider = $pathProviderType::new([IPathProvider]$PathProvider)
        }

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
            $projectsCurrent = $null
            $projectsCurrent = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Projects', 'Current')

            if ($null -ne $projectsCurrent) {
                $currentProject = [ProjectCurrentConfig]::FromObject($projectsCurrent)
                if ($currentProject.Name -eq $ProjectName -and -not [string]::IsNullOrWhiteSpace($currentProject.Path)) {
                    $projectPath = $currentProject.Path
                }
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
            $pluginsRoot = $null
            $pluginsRoot = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Paths', 'App', 'Plugins', 'Root')
            $pluginsRoot = if ($null -eq $pluginsRoot) { '' } else { [string]$pluginsRoot }
            if ([string]::IsNullOrWhiteSpace($pluginsRoot)) {
                throw [ConfigurationException]::new('Plugins root path not found in configuration (Paths.App.Plugins.Root)', 'PluginsRoot')
            }

            $digiKamInstallations = $FileSystem.GetChildItem($pluginsRoot, 'digiKam-*', 'Directory')
            if (-not $digiKamInstallations) {
                throw [PluginRequirementException]::new('digiKam installation not found in Plugins directory', 'digiKam')
            }
            $digiKamPluginsPath = $digiKamInstallations[0].FullName

            $mariaDbInstallations = $FileSystem.GetChildItem($pluginsRoot, 'mariadb-*', 'Directory')
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
                $configDigiKamPath = $null
                $configDigiKamPath = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Paths', 'App', 'ConfigDigiKam')
                $configDigiKamPath = if ($null -eq $configDigiKamPath) { '' } else { [string]$configDigiKamPath }
                if ([string]::IsNullOrWhiteSpace($configDigiKamPath)) {
                    throw [ConfigurationException]::new('digiKam config path not found in configuration (Paths.App.ConfigDigiKam)', 'ConfigDigiKam')
                }

                $templatePath = $PathProvider.CombinePath(@($configDigiKamPath, 'digiKam-rc-template'))
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
            if (-not $configDigiKamPath) {
                $configDigiKamPath = $null
                $configDigiKamPath = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Paths', 'App', 'ConfigDigiKam')
                $configDigiKamPath = if ($null -eq $configDigiKamPath) { '' } else { [string]$configDigiKamPath }
            }

            $sourceProfilePath = $PathProvider.CombinePath($configDigiKamPath,'digiKam-metadataProfile.dkamp')
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
            $hasContext = $false
            try {
                if (Get-Command -Name Test-PSmmPluginsConfigMember -ErrorAction SilentlyContinue) {
                    $hasContext = Test-PSmmPluginsConfigMember -Object $_.Exception -Name 'Context'
                }
            }
            catch {
                $hasContext = $false
            }

            if ($hasContext) {
                $contextValue = $null
                try { $contextValue = Get-PSmmPluginsConfigMemberValue -Object $_.Exception -Name 'Context' } catch { $contextValue = $null }
                $errorMessage = "[$contextValue] $($_.Exception.Message)"
            }
            else {
                $errorMessage = "Failed to initialize digiKam configuration for project $ProjectName`: $_"
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
