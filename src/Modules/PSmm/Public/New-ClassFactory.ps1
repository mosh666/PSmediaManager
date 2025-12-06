<#
.SYNOPSIS
    Factory functions for type-safe class instantiation.

.DESCRIPTION
    Provides public factory methods to create ProjectInfo and PortInfo instances.
    Works around PowerShell module scoping limitations for user-defined classes
    by providing accessible entry points for class instantiation.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
#>

<#
.SYNOPSIS
    Creates a new ProjectInfo instance.

.DESCRIPTION
    Factory function for creating strongly-typed project information objects.
    Provides an accessible way to instantiate ProjectInfo classes despite
    PowerShell module scoping limitations.

.PARAMETER Name
    The project name. Cannot be empty.

.PARAMETER Path
    The project path on the file system.

.PARAMETER Type
    Project type (e.g., 'Photo', 'Video', 'Mixed').

.PARAMETER DriveLetter
    Drive letter where the project is located.

.PARAMETER DriveLabel
    Human-readable label for the drive.

.PARAMETER SerialNumber
    Drive serial number for tracking purposes.

.PARAMETER Location
    Location indicator: 'Master' or 'Backup'.

.PARAMETER CreatedDate
    Date the project was created.

.PARAMETER ModifiedDate
    Date the project was last modified.

.PARAMETER SizeBytes
    Total size of project in bytes.

.PARAMETER Metadata
    Optional hashtable of additional metadata.

.EXAMPLE
    $project = New-ProjectInfo -Name 'VacationPhotos' -Path 'D:\Projects\Vacation' -Type 'Photo'

.OUTPUTS
    [ProjectInfo] A new ProjectInfo instance with validated properties.
#>
function New-ProjectInfo {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Factory function creates objects but does not modify system state')]
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Path,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Type,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$DriveLetter,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DriveLabel,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$SerialNumber,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('Master', 'Backup')]
        [string]$Location,

        [Parameter(ValueFromPipelineByPropertyName)]
        [DateTime]$CreatedDate = (Get-Date),

        [Parameter(ValueFromPipelineByPropertyName)]
        [DateTime]$ModifiedDate = (Get-Date),

        [Parameter(ValueFromPipelineByPropertyName)]
        [int64]$SizeBytes = 0,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Hashtable]$Metadata
    )

    process {
        try {
            # Create PSCustomObject that mirrors ProjectInfo class structure
            # Uses PSTypeName to indicate type while remaining accessible from outside module
            $project = [PSCustomObject]@{
                PSTypeName = 'ProjectInfo'
                Name = $Name
                Path = $Path
                Type = $Type
                CreatedDate = $CreatedDate
                ModifiedDate = $ModifiedDate
                SizeBytes = $SizeBytes
                DriveLetter = $DriveLetter
                DriveLabel = $DriveLabel
                SerialNumber = $SerialNumber
                Location = $Location
                Metadata = $Metadata ?? @{}
            }

            # Add ScriptMethod to provide GetDisplayName() functionality
            $project | Add-Member -MemberType ScriptMethod -Name GetDisplayName -Value {
                return "$($this.Name) [$($this.Type)]"
            }

            return $project
        }
        catch {
            throw [System.Management.Automation.RuntimeException]::new("Failed to create ProjectInfo: $_")
        }
    }
}

<#
.SYNOPSIS
    Creates a new PortInfo instance.

.DESCRIPTION
    Factory function for creating strongly-typed port allocation objects.
    Provides an accessible way to instantiate PortInfo classes despite
    PowerShell module scoping limitations.

.PARAMETER ProjectName
    The project name this port is allocated for.

.PARAMETER Port
    The port number (1-65535).

.PARAMETER Protocol
    Protocol type: 'TCP', 'UDP', or 'Both'. Defaults to 'TCP'.

.PARAMETER ServiceName
    Name of the service using this port.

.PARAMETER Description
    Optional description of the port allocation.

.PARAMETER AllocatedDate
    Date the port was allocated.

.PARAMETER IsActive
    Whether the port allocation is currently active.

.PARAMETER Metadata
    Optional hashtable of additional metadata.

.EXAMPLE
    $port = New-PortInfo -ProjectName 'MyProject' -Port 8080 -Protocol 'TCP' -ServiceName 'WebServer'

.OUTPUTS
    [PortInfo] A new PortInfo instance with validated port number.
#>
function New-PortInfo {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Factory function creates objects but does not modify system state')]
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectName,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('TCP', 'UDP', 'Both')]
        [string]$Protocol = 'TCP',

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ServiceName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Description,

        [Parameter(ValueFromPipelineByPropertyName)]
        [DateTime]$AllocatedDate = (Get-Date),

        [Parameter(ValueFromPipelineByPropertyName)]
        [bool]$IsActive = $true,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Hashtable]$Metadata
    )

    process {
        try {
            # Create PSCustomObject that mirrors PortInfo class structure
            # Uses PSTypeName to indicate type while remaining accessible from outside module
            $portInfo = [PSCustomObject]@{
                PSTypeName = 'PortInfo'
                ProjectName = $ProjectName
                Port = $Port
                Protocol = $Protocol
                ServiceName = $ServiceName
                Description = $Description
                AllocatedDate = $AllocatedDate
                IsActive = $IsActive
                Metadata = $Metadata ?? @{}
            }

            # Add ScriptMethod to provide GetDisplayName() functionality
            $portInfo | Add-Member -MemberType ScriptMethod -Name GetDisplayName -Value {
                return "$($this.ProjectName):$($this.Port)/$($this.Protocol)"
            }

            return $portInfo
        }
        catch {
            throw [System.Management.Automation.RuntimeException]::new("Failed to create PortInfo: $_")
        }
    }
}

<#
.SYNOPSIS
    Gets project information from a directory.

.DESCRIPTION
    Creates a ProjectInfo object from an existing project directory,
    populating all metadata from the file system.

.PARAMETER Path
    Path to the project directory.

.PARAMETER DriveLetter
    The drive letter where the project resides.

.PARAMETER DriveLabel
    Human-readable label for the drive.

.PARAMETER SerialNumber
    Serial number of the drive.

.PARAMETER Location
    Location indicator: 'Master' or 'Backup'.

.PARAMETER FileSystem
    File system service for retrieving directory information.

.EXAMPLE
    $project = Get-ProjectInfoFromPath -Path 'D:\Projects\Photos' -DriveLetter 'D:' -FileSystem $fileSystemService

.OUTPUTS
    [ProjectInfo] Project information populated from directory metadata.
#>
function Get-ProjectInfoFromPath {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DriveLetter,

        [Parameter()]
        [string]$DriveLabel,

        [Parameter()]
        [string]$SerialNumber,

        [Parameter()]
        [ValidateSet('Master', 'Backup')]
        [string]$Location = 'Master',

        [Parameter()]
        $FileSystem
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            throw [System.IO.DirectoryNotFoundException]::new("Project directory not found: $Path")
        }

        $item = Get-Item -Path $Path
        $projectName = $item.Name

        # Calculate directory size
        $sizeBytes = 0
        if ($FileSystem) {
            try {
                $childItems = @($FileSystem.GetChildItem($Path, $null, $null, $true))
                if ($childItems.Count -gt 0) {
                    $sizeBytes = ($childItems | Measure-Object -Property Length -Sum).Sum
                }
            }
            catch {
                Write-Warning "Could not calculate project size: $_"
            }
        }
        else {
            $files = @(Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue)
            if ($files.Count -gt 0) {
                $sizeBytes = ($files | Measure-Object -Property Length -Sum).Sum
            }
        }

        # Create PSCustomObject that mirrors ProjectInfo class structure
        $project = [PSCustomObject]@{
            PSTypeName = 'ProjectInfo'
            Name = $projectName
            Path = $Path
            Type = 'Mixed'
            CreatedDate = $item.CreationTime
            ModifiedDate = $item.LastWriteTime
            SizeBytes = [int64]($sizeBytes ?? 0)
            DriveLetter = $DriveLetter
            DriveLabel = $DriveLabel
            SerialNumber = $SerialNumber
            Location = $Location
            Metadata = @{}
        }

        return $project
    }
    catch {
        throw [System.Management.Automation.RuntimeException]::new("Failed to create ProjectInfo from path: $_")
    }
}
