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
            function _TryGetConfigValue {
                [CmdletBinding()]
                param(
                    [Parameter()][AllowNull()]$Object,
                    [Parameter()][string]$Name
                )

                if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
                    return $null
                }

                if ($Object -is [System.Collections.IDictionary]) {
                    try {
                        if ($Object.ContainsKey($Name)) { return $Object[$Name] }
                    }
                    catch {
                        Write-Verbose "_TryGetConfigValue: ContainsKey('$Name') failed: $($_.Exception.Message)"
                    }
                    try {
                        if ($Object.Contains($Name)) { return $Object[$Name] }
                    }
                    catch {
                        Write-Verbose "_TryGetConfigValue: Contains('$Name') failed: $($_.Exception.Message)"
                    }

                    try {
                        foreach ($k in $Object.Keys) {
                            if ($k -eq $Name) { return $Object[$k] }
                        }
                    }
                    catch {
                        Write-Verbose "_TryGetConfigValue: Enumerating dictionary keys for '$Name' failed: $($_.Exception.Message)"
                    }
                    return $null
                }

                $p = $Object.PSObject.Properties[$Name]
                if ($null -ne $p) {
                    return $p.Value
                }

                return $null
            }

            function _TryGetNestedValue {
                [CmdletBinding()]
                param(
                    [Parameter()][AllowNull()]$Root,
                    [Parameter(Mandatory)][string[]]$PathParts
                )

                $cur = $Root
                foreach ($part in $PathParts) {
                    if ($null -eq $cur) { return $null }
                    $cur = _TryGetConfigValue -Object $cur -Name $part
                }
                return $cur
            }

            # Confirm the action with ShouldProcess
            if (-not $PSCmdlet.ShouldProcess($ProjectName, 'Initialize digiKam configuration')) {
                Write-Verbose 'Initialize digiKam configuration operation cancelled by user'
                return @{}
            }

            # Get project path - check if this is the current project
            $projectPath = $null
            $projectsCurrent = $null
            $projectsCurrent = _TryGetNestedValue -Root $Config -PathParts @('Projects','Current')

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
            $pluginsRoot = _TryGetNestedValue -Root $Config -PathParts @('Paths','App','Plugins','Root')
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
                $configDigiKamPath = _TryGetNestedValue -Root $Config -PathParts @('Paths','App','ConfigDigiKam')
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
                $configDigiKamPath = _TryGetNestedValue -Root $Config -PathParts @('Paths','App','ConfigDigiKam')
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
