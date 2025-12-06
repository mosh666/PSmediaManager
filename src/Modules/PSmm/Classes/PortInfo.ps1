<#
.SYNOPSIS
    Type-safe port allocation information class.

.DESCRIPTION
    Represents port allocation data for containerized projects and services.
    Replaces PSCustomObject usage for port objects throughout the application.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
#>

using namespace System
using namespace System.Collections.Generic

<#
.SYNOPSIS
    Represents a port allocation for a project service.

.DESCRIPTION
    Provides strongly-typed port information with validation,
    making it easier to work with port allocations across the application.
#>
class PortInfo {
    [ValidateNotNullOrEmpty()]
    [string]$ProjectName

    [ValidateRange(1, 65535)]
    [int]$Port

    [ValidateSet('TCP', 'UDP', 'Both')]
    [string]$Protocol = 'TCP'

    [string]$ServiceName

    [string]$Description

    [DateTime]$AllocatedDate

    [bool]$IsActive = $true

    [Hashtable]$Metadata

    PortInfo([string]$projectName, [int]$port) {
        if ([string]::IsNullOrWhiteSpace($projectName)) {
            throw [ArgumentException]::new("Project name cannot be empty", "projectName")
        }
        if ($port -lt 1 -or $port -gt 65535) {
            throw [ArgumentException]::new("Port must be between 1 and 65535", "port")
        }

        $this.ProjectName = $projectName
        $this.Port = $port
        $this.AllocatedDate = [DateTime]::Now
        $this.Metadata = @{}
    }

    PortInfo([string]$projectName, [int]$port, [string]$protocol) {
        if ([string]::IsNullOrWhiteSpace($projectName)) {
            throw [ArgumentException]::new("Project name cannot be empty", "projectName")
        }
        if ($port -lt 1 -or $port -gt 65535) {
            throw [ArgumentException]::new("Port must be between 1 and 65535", "port")
        }
        if ($protocol -notin @('TCP', 'UDP', 'Both')) {
            throw [ArgumentException]::new("Protocol must be TCP, UDP, or Both", "protocol")
        }

        $this.ProjectName = $projectName
        $this.Port = $port
        $this.Protocol = $protocol
        $this.AllocatedDate = [DateTime]::Now
        $this.Metadata = @{}
    }

    PortInfo([string]$projectName, [int]$port, [string]$protocol, [string]$serviceName) {
        if ([string]::IsNullOrWhiteSpace($projectName)) {
            throw [ArgumentException]::new("Project name cannot be empty", "projectName")
        }
        if ($port -lt 1 -or $port -gt 65535) {
            throw [ArgumentException]::new("Port must be between 1 and 65535", "port")
        }
        if ($protocol -notin @('TCP', 'UDP', 'Both')) {
            throw [ArgumentException]::new("Protocol must be TCP, UDP, or Both", "protocol")
        }

        $this.ProjectName = $projectName
        $this.Port = $port
        $this.Protocol = $protocol
        $this.ServiceName = $serviceName
        $this.AllocatedDate = [DateTime]::Now
        $this.Metadata = @{}
    }

    <#
    .SYNOPSIS
        Gets the display name with protocol info.
    #>
    [string] GetDisplayName() {
        $displayName = "$($this.ProjectName):$($this.Port)/$($this.Protocol)"

        if (-not [string]::IsNullOrWhiteSpace($this.ServiceName)) {
            $displayName += " ($($this.ServiceName))"
        }

        return $displayName
    }

    <#
    .SYNOPSIS
        Validates port number is within valid range.
    #>
    [bool] Validate() {
        if ([string]::IsNullOrWhiteSpace($this.ProjectName) -or `
            $this.Port -lt 1 -or $this.Port -gt 65535) {
            return $false
        }
        return $true
    }

    <#
    .SYNOPSIS
        Converts to PSCustomObject for compatibility.
    #>
    [PSCustomObject] ToPSObject() {
        return [PSCustomObject]@{
            ProjectName = $this.ProjectName
            Port = $this.Port
            Protocol = $this.Protocol
            ServiceName = $this.ServiceName
            Description = $this.Description
            AllocatedDate = $this.AllocatedDate
            IsActive = $this.IsActive
            Metadata = $this.Metadata
        }
    }
}
