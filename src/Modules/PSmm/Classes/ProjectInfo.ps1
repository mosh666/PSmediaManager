<#
.SYNOPSIS
    Type-safe project information class.

.DESCRIPTION
    Represents project data with validation and type safety.
    Replaces PSCustomObject usage for project objects throughout the application.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
#>

using namespace System
using namespace System.Collections.Generic

<#
.SYNOPSIS
    Represents a single project in the media library.

.DESCRIPTION
    Provides strongly-typed project information with validation,
    making it easier to work with project data across the application.
#>
class ProjectInfo {
    [ValidateNotNullOrEmpty()]
    [string]$Name

    [string]$Path

    [string]$Type        # e.g., 'Photo', 'Video', 'Mixed'

    [DateTime]$CreatedDate

    [DateTime]$ModifiedDate

    [int64]$SizeBytes     # Total size in bytes

    [ValidateNotNullOrEmpty()]
    [string]$DriveLetter  # Which drive it's on (e.g., 'D:')

    [string]$DriveLabel   # Human-readable drive label

    [string]$SerialNumber # Drive serial number for tracking

    [ValidateSet('Master', 'Backup')]
    [string]$Location     # Whether on master or backup drive

    [Hashtable]$Metadata  # Additional custom metadata

    ProjectInfo([string]$name, [string]$path) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new("Project name cannot be empty", "name")
        }
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [ArgumentException]::new("Project path cannot be empty", "path")
        }

        $this.Name = $name
        $this.Path = $path
        $this.CreatedDate = [DateTime]::Now
        $this.ModifiedDate = [DateTime]::Now
        $this.SizeBytes = 0
        $this.Metadata = @{}
    }

    ProjectInfo([string]$name, [string]$path, [string]$type) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new("Project name cannot be empty", "name")
        }
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [ArgumentException]::new("Project path cannot be empty", "path")
        }

        $this.Name = $name
        $this.Path = $path
        $this.Type = $type
        $this.CreatedDate = [DateTime]::Now
        $this.ModifiedDate = [DateTime]::Now
        $this.SizeBytes = 0
        $this.Metadata = @{}
    }

    <#
    .SYNOPSIS
        Gets the display size in human-readable format.
    #>
    [string] GetFormattedSize() {
        $size = $this.SizeBytes
        $units = @('B', 'KB', 'MB', 'GB', 'TB')
        $unitIndex = 0

        while ($size -gt 1024 -and $unitIndex -lt $units.Count - 1) {
            $size = $size / 1024
            $unitIndex++
        }

        return "{0:N2} {1}" -f $size, $units[$unitIndex]
    }

    <#
    .SYNOPSIS
        Gets the display name with location info.
    #>
    [string] GetDisplayName() {
        $displayName = $this.Name

        if (-not [string]::IsNullOrWhiteSpace($this.DriveLabel)) {
            $displayName += " @ $($this.DriveLabel)"
        }

        if (-not [string]::IsNullOrWhiteSpace($this.Location)) {
            $displayName += " ($($this.Location))"
        }

        return $displayName
    }

    <#
    .SYNOPSIS
        Validates required fields are set.
    #>
    [bool] Validate() {
        if ([string]::IsNullOrWhiteSpace($this.Name) -or `
            [string]::IsNullOrWhiteSpace($this.Path)) {
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
            Name = $this.Name
            Path = $this.Path
            Type = $this.Type
            CreatedDate = $this.CreatedDate
            ModifiedDate = $this.ModifiedDate
            SizeBytes = $this.SizeBytes
            DriveLetter = $this.DriveLetter
            DriveLabel = $this.DriveLabel
            SerialNumber = $this.SerialNumber
            Location = $this.Location
            Metadata = $this.Metadata
        }
    }
}
