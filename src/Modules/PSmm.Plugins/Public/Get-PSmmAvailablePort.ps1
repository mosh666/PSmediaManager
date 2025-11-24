#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Gets an available port for digiKam project database instances.

.DESCRIPTION
    Allocates unique ports for each project's digiKam database instance to avoid conflicts.
    Starts from port 3310 and increments for each project. Maintains a registry of
    allocated ports to ensure consistency across application restarts.

.PARAMETER Config
    The AppConfiguration object containing all application settings and paths.

.PARAMETER ProjectName
    The name of the project to get a port for.

.PARAMETER Force
    Forces a new port allocation even if one already exists for the project.

.EXAMPLE
    $port = Get-PSmmAvailablePort -Config $appConfig -ProjectName "MyProject"
    # Returns: 3310 (or next available port)

.EXAMPLE
    $port = Get-PSmmAvailablePort -Config $appConfig -ProjectName "MyProject" -Force
    # Forces a new port allocation

.OUTPUTS
    Int32 - The allocated port number for the project.

.NOTES
    Author           : Der Mosh
    Version          : 1.0.0
    Created          : 2025-11-05

    Port Range       : 3310-3399 (90 projects maximum)
    Base Port        : 3310
    Reserved Ports   : 3306 (MySQL default), 3307 (current digiKam default)

    Related          : Start-PSmmdigiKam, Stop-PSmmdigiKam

.LINK
    https://www.digikam.org/
#>

function Get-PSmmAvailablePort {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        $Config,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectName,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        # Port allocation settings
        $BasePort = 3310
        $MaxPort = 3399
        $ReservedPorts = @(3306, 3307)  # MySQL default and current digiKam default

        Write-Verbose "Getting available port for project: $ProjectName"
    }

    process {
        try {
            # Initialize PortRegistry in Config if not exists
            if (-not $Config.Projects.ContainsKey('PortRegistry') -or $null -eq $Config.Projects.PortRegistry) {
                $Config.Projects.PortRegistry = @{}
                Write-Verbose 'Initialized Projects PortRegistry'
            }

            # Return existing port if available and not forced
            if (-not $Force.IsPresent -and $Config.Projects.PortRegistry.ContainsKey($ProjectName)) {
                $existingPort = $Config.Projects.PortRegistry[$ProjectName]
                Write-Verbose "Using existing port $existingPort for project $ProjectName"
                Write-PSmmLog -Level DEBUG -Context 'Get-PSmmAvailablePort' `
                    -Message "Using existing port $existingPort for project $ProjectName" -File
                return $existingPort
            }

            # Get all currently allocated ports
            $allocatedPorts = @($Config.Projects.PortRegistry.Values) + $ReservedPorts

            # Find the next available port
            $availablePort = $BasePort
            while ($availablePort -le $MaxPort) {
                if ($availablePort -notin $allocatedPorts) {
                    # Check if port is actually free on the system
                    $portInUse = Get-NetTCPConnection -LocalPort $availablePort -ErrorAction SilentlyContinue
                    if (-not $portInUse) {
                        break
                    }
                }
                $availablePort++
            }

            # Validate we found an available port
            if ($availablePort -gt $MaxPort) {
                throw [ConfigurationException]::new("No available ports in range $BasePort-$MaxPort", 'PortAllocation')
            }

            # Allocate the port to the project
            $Config.Projects.PortRegistry[$ProjectName] = $availablePort

            Write-Verbose "Allocated port $availablePort to project $ProjectName"
            Write-PSmmLog -Level INFO -Context 'Get-PSmmAvailablePort' `
                -Message "Allocated port $availablePort to project $ProjectName" -Console -File

            return $availablePort
        }
        catch {
            $errorMessage = if ($_.Exception -is [MediaManagerException]) {
                "[$($_.Exception.Context)] $($_.Exception.Message)"
            }
            else {
                "Failed to get available port for project $ProjectName`: $_"
            }

            Write-PSmmLog -Level ERROR -Context 'Get-PSmmAvailablePort' `
                -Message $errorMessage -ErrorRecord $_ -Console -File
            throw
        }
    }

    end {
        Write-Verbose 'Get-PSmmAvailablePort completed'
    }
}
