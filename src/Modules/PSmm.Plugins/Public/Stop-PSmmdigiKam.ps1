#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Stops the digiKam application and related processes for a specific project.

.DESCRIPTION
    Terminates project-specific digiKam and associated MariaDB database processes.
    The function identifies processes by their configuration paths and database ports
    to ensure only the correct project's processes are stopped.

    The function performs the following operations:
    - Finds and stops digiKam processes using the project-specific APPDIR
    - Finds and stops MariaDB processes on the project's allocated port
    - Cleans up child processes spawned by digiKam
    - Preserves other project instances running on different ports

.PARAMETER Config
    The AppConfiguration object containing all application settings and paths.

.EXAMPLE
    Stop-PSmmdigiKam -Config $appConfig
    Stops all digiKam and related processes for the current project.

.NOTES
    Author           : Der Mosh
    Version          : 1.0.0
    Created          : 2025-11-05

    Requires         : - AppConfiguration class

    Related          : Start-PSmmdigiKam

.LINK
    https://www.digikam.org/
#>

function Stop-PSmmdigiKam {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        $Config
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        # Get current project name from Config
        $projectName = if ($null -ne $Config.Projects -and $Config.Projects.ContainsKey('Current') -and
            $Config.Projects.Current.ContainsKey('Name')) {
            $Config.Projects.Current.Name
        } else {
            'Unknown'
        }

        Write-Verbose "Stopping digiKam for project: $projectName"
    }

    process {
        try {
            # Confirm the action with ShouldProcess
            if (-not $PSCmdlet.ShouldProcess($projectName, 'Stop digiKam and related processes')) {
                Write-Verbose 'Stop digiKam operation cancelled by user'
                return
            }

            Write-Host ''
            Write-PSmmLog -Level INFO -Context 'digiKam' -Message 'Stopping digiKam...' -Console -File

            # Get project-specific paths - check if this is the current project
            $projectPath = $null
            if ($Config.Projects.ContainsKey('Current') -and
                $Config.Projects.Current.ContainsKey('Name') -and
                $Config.Projects.Current.Name -eq $projectName -and
                $Config.Projects.Current.ContainsKey('Path')) {
                $projectPath = $Config.Projects.Current.Path
            }
            else {
                Write-Warning "Project '$projectName' is not currently selected. Cannot determine project paths for stopping digiKam."
                return
            }

            $configPath = Join-Path -Path $projectPath -ChildPath 'Config'
            $appDir = Join-Path -Path $configPath -ChildPath 'digiKam'

            # Get project's allocated database port
            $databasePort = $null
            if ($Config.Projects.ContainsKey('PortRegistry') -and
                $Config.Projects.PortRegistry.ContainsKey($projectName)) {
                $databasePort = $Config.Projects.PortRegistry[$projectName]
                Write-Verbose "Found allocated port $databasePort for project $projectName"
            }

            $processesKilled = 0

            # Stop digiKam processes using the project-specific APPDIR
            Write-Verbose "Looking for digiKam processes with APPDIR: $appDir"

            # Get all digiKam processes and check their environment variables
            $digiKamProcesses = Get-Process -Name 'digikam' -ErrorAction SilentlyContinue
            $projectDigiKamProcesses = @()

            foreach ($proc in $digiKamProcesses) {
                try {
                    # Check if process command line contains our config file
                    $digiKamRcPath = Join-Path -Path $configPath -ChildPath 'digiKam-rc'
                    if ($proc.CommandLine -like "*$digiKamRcPath*") {
                        $projectDigiKamProcesses += $proc
                    }
                }
                catch {
                    # If we can't access CommandLine, skip this process
                    Write-Verbose "Cannot access CommandLine for process PID: $($proc.Id)"
                }
            }

            if ($projectDigiKamProcesses) {
                foreach ($proc in $projectDigiKamProcesses) {
                    try {
                        Write-Verbose "Stopping digiKam process (PID: $($proc.Id)) for project $projectName"
                        $proc.Kill()
                        $processesKilled++
                    }
                    catch {
                        Write-Warning "Failed to stop digiKam process (PID: $($proc.Id)): $_"
                    }
                }
            }
            else {
                Write-Verbose "No digiKam processes found for project $projectName"
            }

            # Stop MariaDB processes associated with project database port
            if ($databasePort) {
                Write-Verbose "Looking for MariaDB processes on port: $databasePort"

                # Find MariaDB processes listening on the project's port
                $portConnections = Get-NetTCPConnection -LocalPort $databasePort -ErrorAction SilentlyContinue
                $mariaDbProcesses = @()

                foreach ($connection in $portConnections) {
                    try {
                        $proc = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
                        if ($proc -and ($proc.ProcessName -eq 'mariadbd' -or $proc.ProcessName -eq 'mysqld')) {
                            $mariaDbProcesses += $proc
                        }
                    }
                    catch {
                        Write-Verbose "Cannot access process for PID: $($connection.OwningProcess)"
                    }
                }

                if ($mariaDbProcesses) {
                    foreach ($proc in $mariaDbProcesses) {
                        try {
                            Write-Verbose "Stopping MariaDB process (PID: $($proc.Id)) on port $databasePort for project $projectName"
                            $proc.Kill()
                            $processesKilled++
                        }
                        catch {
                            Write-Warning "Failed to stop MariaDB process (PID: $($proc.Id)): $_"
                        }
                    }
                }
                else {
                    Write-Verbose "No MariaDB processes found on port $databasePort for project $projectName"
                }
            }
            else {
                Write-Verbose "No database port allocated for project $projectName"
            }

            if ($processesKilled -gt 0) {
                Write-PSmmLog -Level SUCCESS -Context 'digiKam' -Message "Stopped $processesKilled process(es)" -Console -File
            }
            else {
                Write-PSmmLog -Level INFO -Context 'digiKam' -Message 'No running digiKam or MariaDB processes found for this project' -Console -File
            }

            Write-Host ''
        }
        catch {
            $errorMessage = if ($_.Exception -is [MediaManagerException]) {
                "[$($_.Exception.Context)] $($_.Exception.Message)"
            }
            else {
                "Failed to stop digiKam: $_"
            }

            Write-PSmmLog -Level ERROR -Context 'digiKam' -Message $errorMessage -ErrorRecord $_ -Console -File
            throw
        }
    }

    end {
        Write-Verbose 'Stop-PSmmdigiKam completed'
    }
}
