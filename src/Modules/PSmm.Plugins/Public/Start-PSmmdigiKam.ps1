#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Starts the digiKam application with project-specific configuration and isolated database.

.DESCRIPTION
    Launches digiKam with project-specific configuration for complete isolation between projects.
    Each project gets its own digiKam instance with:
    - Unique database port allocation (starting from 3310)
    - Project-specific APPDIR for configuration isolation
    - Dedicated digiKam-rc configuration file
    - Separate MariaDB database instance

    The function performs the following operations:
    - Validates the project is not a template
    - Initializes or updates project-specific digiKam configuration
    - Allocates a unique database port for the project
    - Sets up isolated APPDIR environment
    - Launches digiKam with project-specific settings

.PARAMETER Config
    The AppConfiguration object containing all application settings and paths.

.PARAMETER Force
    Forces recreation of project configuration files even if they already exist.

.EXAMPLE
    Start-PSmmdigiKam -Config $appConfig
    Starts digiKam for the current project with project-specific configuration.

.EXAMPLE
    Start-PSmmdigiKam -Config $appConfig -Force
    Forces recreation of project configuration and starts digiKam.

.NOTES
    Author           : Der Mosh
    Version          : 1.0.0
    Created          : 2025-11-05

    Requires         : - digiKam 8.8.0 or higher
                       - MariaDB installation
                       - ExifTool installation

    Dependencies     : - Initialize-digiKam function (from legacy code)
                       - AppConfiguration class

    Related          : Stop-PSmmdigiKam

.LINK
    https://www.digikam.org/
#>

function Start-PSmmdigiKam {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        $Config,

        [Parameter(Mandatory)]
        $FileSystem,

        [Parameter(Mandatory)]
        $PathProvider,

        [Parameter(Mandatory)]
        $Process,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        # Get current project name from Config
        $projectName = if ($null -ne $Config.Projects -and $Config.Projects.ContainsKey('Current') -and
            $Config.Projects.Current.ContainsKey('Name')) {
            $Config.Projects.Current.Name
        } else {
            throw [ConfigurationException]::new('No current project selected', 'ProjectName')
        }

        Write-Verbose "Starting digiKam for project: $projectName"
    }

    process {
        try {
            # Check if this is a template project
            if ($projectName -eq '_Template_') {
                Write-Warning 'digiKam cannot be started for template projects'
                Write-PSmmHost ''
                Read-Host -Prompt 'Press Enter to continue'
                return
            }

            # Confirm the action with ShouldProcess
            if (-not $PSCmdlet.ShouldProcess($projectName, 'Start digiKam')) {
                Write-Verbose 'Start digiKam operation cancelled by user'
                return
            }

            Write-PSmmHost ''
            Write-PSmmLog -Level INFO -Context 'digiKam' -Message 'Starting digiKam...' -Console -File

            # Initialize project-specific digiKam configuration
            Write-Verbose "Initializing project-specific digiKam configuration..."
            $projectConfig = Initialize-PSmmProjectDigiKamConfig -Config $Config -ProjectName $projectName -FileSystem $FileSystem -PathProvider $PathProvider -Force:$Force

            # Get project-specific paths from configuration
            $digiKamRcPath = $projectConfig.DigiKamRcPath
            $appDir = $projectConfig.AppDir
            $databasePort = $projectConfig.DatabasePort

            # Get digiKam executable path
            $digiKamExe = $PathProvider.CombinePath($projectConfig.DigiKamPluginsPath, 'digikam.exe')

            if (-not ($FileSystem.TestPath($digiKamExe))) {
                throw [PluginRequirementException]::new("digiKam executable not found: $digiKamExe", 'digiKam')
            }

            # Verify digiKam RC file exists
            if (-not ($FileSystem.TestPath($digiKamRcPath))) {
                throw [ConfigurationException]::new("digiKam configuration file not found: $digiKamRcPath", 'digiKamRC')
            }

            Write-Verbose "digiKam executable: $digiKamExe"
            Write-Verbose "digiKam config file: $digiKamRcPath"
            Write-Verbose "digiKam APPDIR: $appDir"
            Write-Verbose "Database port: $databasePort"

            # Start digiKam process with project-specific configuration and APPDIR
            Write-PSmmLog -Level INFO -Context 'digiKam' -Message "Launching digiKam for project '$projectName' on port $databasePort" -Console -File

            # Set environment variable for digiKam APPDIR (isolates configuration and data)
            $env:DIGIKAM_APPDIR = $appDir

            $digiKamProcess = $Process.StartProcess($digiKamExe, @('--config', $digiKamRcPath))

            if ($null -eq $digiKamProcess) {
                throw [ProcessException]::new('Failed to start digiKam process', 'digiKam')
            }

            Write-PSmmLog -Level SUCCESS -Context 'digiKam' -Message "digiKam started successfully (PID: $($digiKamProcess.Id)) for project '$projectName'" -Console -File

            # Display project-specific information
            Write-PSmmHost ''
            Write-PSmmHost "digiKam Configuration:" -ForegroundColor Green
            Write-PSmmHost "  Project: $projectName" -ForegroundColor White
            Write-PSmmHost "  Database Port: $databasePort" -ForegroundColor White
            Write-PSmmHost "  APPDIR: $appDir" -ForegroundColor White
            Write-PSmmHost "  Config File: $digiKamRcPath" -ForegroundColor White
            Write-PSmmHost ''
            Write-PSmmHost 'Metadata profile location:' -ForegroundColor Green
            Write-PSmmHost "  $($projectConfig.MetadataProfile)" -ForegroundColor White
            Write-PSmmHost ''

            Write-Verbose "digiKam started with PID: $($digiKamProcess.Id)"
        }
        catch {
            $errorMessage = if ($_.Exception -is [MediaManagerException]) {
                "[$($_.Exception.Context)] $($_.Exception.Message)"
            }
            else {
                "Failed to start digiKam: $_"
            }

            Write-PSmmLog -Level ERROR -Context 'digiKam' -Message $errorMessage -ErrorRecord $_ -Console -File
            throw
        }
    }

    end {
        Write-Verbose 'Start-PSmmdigiKam completed'
    }
}
