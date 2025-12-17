#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Lists all allocated digiKam database ports for projects.

.DESCRIPTION
    Displays a comprehensive list of all projects and their allocated database ports,
    including status information about whether the ports are currently in use.
    Useful for troubleshooting port conflicts and managing multiple digiKam instances.

    Note: This function uses a plural noun (ProjectPorts) to accurately represent that
    it returns multiple port allocations, which is more semantically correct than
    Get-PSmmProjectPort in this context.

.PARAMETER Config
    The AppConfiguration object containing all application settings and paths.

.PARAMETER IncludeUsage
    Include port usage status (whether port is currently listening).

.EXAMPLE
    Get-PSmmProjectPorts -Config $appConfig
    # Lists all allocated ports

.EXAMPLE
    Get-PSmmProjectPorts -Config $appConfig -IncludeUsage
    # Lists ports with usage status

.OUTPUTS
    Array of PSCustomObject containing project port allocation information.

.NOTES
    Author           : Der Mosh
    Version          : 1.1.0
    Created          : 2025-11-05
    Modified         : 2025-11-06

    Related          : Get-PSmmAvailablePort, Start-PSmmdigiKam

.LINK
    https://www.digikam.org/
#>

function Get-PSmmProjectPorts {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Function returns multiple ports; plural form is semantically correct')]
    [CmdletBinding()]
    [OutputType([PSCustomObject[]],[object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        $Config,

        [Parameter()]
        [switch]$IncludeUsage,

        [Parameter(Mandatory)]
        $Process
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        function Get-ConfigMemberValue {
            param(
                [Parameter(Mandatory = $true)]
                [AllowNull()]
                [object]$Object,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$Name
            )

            if ($null -eq $Object) { return $null }

            try {
                if ($Object -is [System.Collections.IDictionary]) {
                    $hasKey = $false
                    try { $hasKey = $Object.ContainsKey($Name) } catch { $hasKey = $false }
                    if (-not $hasKey) { try { $hasKey = $Object.Contains($Name) } catch { $hasKey = $false } }

                    if (-not $hasKey) {
                        try {
                            foreach ($k in $Object.Keys) {
                                if ($k -eq $Name) { $hasKey = $true; break }
                            }
                        }
                        catch { $hasKey = $false }
                    }

                    if ($hasKey) { return $Object[$Name] }
                }
            }
            catch { }

            try {
                $prop = $Object.PSObject.Properties[$Name]
                if ($null -ne $prop) { return $prop.Value }
            }
            catch { }

            return $null
        }

        function Set-ConfigMemberValue {
            param(
                [Parameter(Mandatory = $true)]
                [AllowNull()]
                [object]$Object,

                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$Name,

                [Parameter(Mandatory = $false)]
                [AllowNull()]
                [object]$Value
            )

            if ($null -eq $Object) { return }

            try {
                if ($Object -is [System.Collections.IDictionary]) {
                    $Object[$Name] = $Value
                    return
                }
            }
            catch { }

            try {
                $prop = $Object.PSObject.Properties[$Name]
                if ($null -ne $prop) {
                    $prop.Value = $Value
                    return
                }
            }
            catch { }

            try {
                $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
            }
            catch { }
        }

        Write-Verbose "Retrieving project port allocations"
    }

    process {
        try {
            $results = @()

            $projects = Get-ConfigMemberValue -Object $Config -Name 'Projects'
            $projectsPortRegistry = Get-ConfigMemberValue -Object $projects -Name 'PortRegistry'

            $portRegistry = if ($null -ne $projects -and $null -ne $projectsPortRegistry) {
                [ProjectsPortRegistry]::FromObject($projectsPortRegistry)
            }
            else {
                [ProjectsPortRegistry]::new()
            }

            if ($null -ne $projects) {
                Set-ConfigMemberValue -Object $projects -Name 'PortRegistry' -Value $portRegistry
            }

            # Check if PortRegistry exists
            if ($portRegistry.GetCount() -eq 0) {
                Write-Warning 'No port allocations found. Projects may not have been initialized with digiKam yet.'
                return $results
            }

            # Get all allocated ports
            foreach ($projectName in $portRegistry.GetKeys() | Sort-Object) {
                $port = $portRegistry.GetPort($projectName)

                $result = [PSCustomObject]@{
                    ProjectName = $projectName
                    Port = $port
                    Type = 'digiKam Database'
                }

                # Add usage information if requested
                if ($IncludeUsage.IsPresent) {
                    try {
                        $connection = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($connection) {
                            $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
                            if ($process) {
                                $result | Add-Member -MemberType NoteProperty -Name 'InUse' -Value $true
                                $result | Add-Member -MemberType NoteProperty -Name 'ProcessName' -Value $process.ProcessName
                                $result | Add-Member -MemberType NoteProperty -Name 'ProcessId' -Value $process.Id
                            }
                            else {
                                $result | Add-Member -MemberType NoteProperty -Name 'InUse' -Value $false
                                $result | Add-Member -MemberType NoteProperty -Name 'ProcessName' -Value ''
                                $result | Add-Member -MemberType NoteProperty -Name 'ProcessId' -Value 0
                            }
                        }
                        else {
                            $result | Add-Member -MemberType NoteProperty -Name 'InUse' -Value $false
                            $result | Add-Member -MemberType NoteProperty -Name 'ProcessName' -Value ''
                            $result | Add-Member -MemberType NoteProperty -Name 'ProcessId' -Value 0
                        }
                    }
                    catch {
                        $result | Add-Member -MemberType NoteProperty -Name 'InUse' -Value 'Unknown'
                        $result | Add-Member -MemberType NoteProperty -Name 'ProcessName' -Value 'Error'
                        $result | Add-Member -MemberType NoteProperty -Name 'ProcessId' -Value 0
                        Write-Verbose "Could not determine usage for port $port`: $_"
                    }
                }

                $results += $result
            }

            # Display summary
            $totalPorts = @($results).Count
            Write-Verbose "Found $totalPorts allocated port(s)"

            if ($IncludeUsage.IsPresent) {
                $inUse = @($results | Where-Object { $_.InUse -eq $true }).Count
                Write-PSmmLog -Level INFO -Context 'Get-PSmmProjectPorts' `
                    -Message "Port allocation summary: $totalPorts allocated, $inUse in use" -Console -File
            }
            else {
                Write-PSmmLog -Level INFO -Context 'Get-PSmmProjectPorts' `
                    -Message "Found $totalPorts allocated port(s)" -Console -File
            }

            return $results
        }
        catch {
            $errorMessage = if ($_.Exception -is [MediaManagerException]) {
                "[$($_.Exception.Context)] $($_.Exception.Message)"
            }
            else {
                "Failed to retrieve project ports: $_"
            }

            Write-PSmmLog -Level ERROR -Context 'Get-PSmmProjectPorts' `
                -Message $errorMessage -ErrorRecord $_ -Console -File
            throw
        }
    }

    end {
        Write-Verbose 'Get-PSmmProjectPorts completed'
    }
}
