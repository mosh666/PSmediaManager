<#
.SYNOPSIS
    Implementation of IFileSystemService interface.

.DESCRIPTION
    Provides testable file system operations by wrapping PowerShell cmdlets.
    This service can be mocked in tests for full testability.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
#>

using namespace System
using namespace System.IO

<#
.SYNOPSIS
    Production implementation of file system service.
#>
class FileSystemService : IFileSystemService {
    
    <#
    .SYNOPSIS
        Tests if a path exists.
    #>
    [bool] TestPath([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $false
        }
        
        return Test-Path -Path $path -ErrorAction SilentlyContinue
    }
    
    <#
    .SYNOPSIS
        Creates a new file system item (file or directory).
    #>
    [void] NewItem([string]$path, [string]$itemType) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [ArgumentException]::new("Path cannot be empty", "path")
        }
        
        if ([string]::IsNullOrWhiteSpace($itemType)) {
            throw [ArgumentException]::new("ItemType cannot be empty", "itemType")
        }
        
        $null = New-Item -Path $path -ItemType $itemType -Force -ErrorAction Stop
    }
    
    <#
    .SYNOPSIS
        Gets the content of a file.
    #>
    [string] GetContent([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [ArgumentException]::new("Path cannot be empty", "path")
        }
        
        if (-not $this.TestPath($path)) {
            throw [FileNotFoundException]::new("File not found: $path")
        }
        
        return Get-Content -Path $path -Raw -ErrorAction Stop
    }
    
    <#
    .SYNOPSIS
        Sets the content of a file.
    #>
    [void] SetContent([string]$path, [string]$content) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [ArgumentException]::new("Path cannot be empty", "path")
        }
        
        # Ensure directory exists
        $directory = Split-Path -Path $path -Parent
        if (-not $this.TestPath($directory)) {
            $this.NewItem($directory, 'Directory')
        }
        
        Set-Content -Path $path -Value $content -Force -ErrorAction Stop
    }
    
    <#
    .SYNOPSIS
        Gets child items from a directory.
    #>
    [object[]] GetChildItem([string]$path, [string]$filter, [string]$itemType) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [ArgumentException]::new("Path cannot be empty", "path")
        }
        
        $params = @{
            Path = $path
            ErrorAction = 'SilentlyContinue'
        }
        
        if (-not [string]::IsNullOrWhiteSpace($filter)) {
            $params['Filter'] = $filter
        }
        
        $items = Get-ChildItem @params
        
        # Filter by item type if specified
        if (-not [string]::IsNullOrWhiteSpace($itemType)) {
            switch ($itemType.ToLower()) {
                'directory' {
                    $items = $items | Where-Object { $_.PSIsContainer }
                }
                'file' {
                    $items = $items | Where-Object { -not $_.PSIsContainer }
                }
            }
        }
        
        return @($items)
    }
    
    <#
    .SYNOPSIS
        Removes a file or directory.
    #>
    [void] RemoveItem([string]$path, [bool]$recurse) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [ArgumentException]::new("Path cannot be empty", "path")
        }
        
        if (-not $this.TestPath($path)) {
            return
        }
        
        $params = @{
            Path = $path
            Force = $true
            ErrorAction = 'Stop'
        }
        
        if ($recurse) {
            $params['Recurse'] = $true
        }
        
        Remove-Item @params
    }
    
    <#
    .SYNOPSIS
        Copies a file or directory.
    #>
    [void] CopyItem([string]$source, [string]$destination) {
        if ([string]::IsNullOrWhiteSpace($source)) {
            throw [ArgumentException]::new("Source cannot be empty", "source")
        }
        
        if ([string]::IsNullOrWhiteSpace($destination)) {
            throw [ArgumentException]::new("Destination cannot be empty", "destination")
        }
        
        if (-not $this.TestPath($source)) {
            throw [FileNotFoundException]::new("Source not found: $source")
        }
        
        Copy-Item -Path $source -Destination $destination -Force -ErrorAction Stop
    }
    
    <#
    .SYNOPSIS
        Moves a file or directory.
    #>
    [void] MoveItem([string]$source, [string]$destination) {
        if ([string]::IsNullOrWhiteSpace($source)) {
            throw [ArgumentException]::new("Source cannot be empty", "source")
        }
        
        if ([string]::IsNullOrWhiteSpace($destination)) {
            throw [ArgumentException]::new("Destination cannot be empty", "destination")
        }
        
        if (-not $this.TestPath($source)) {
            throw [FileNotFoundException]::new("Source not found: $source")
        }
        
        Move-Item -Path $source -Destination $destination -Force -ErrorAction Stop
    }
    
    <#
    .SYNOPSIS
        Gets properties of a file system item.
    #>
    [object] GetItemProperty([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [ArgumentException]::new("Path cannot be empty", "path")
        }
        
        if (-not $this.TestPath($path)) {
            throw [FileNotFoundException]::new("Item not found: $path")
        }
        
        return Get-Item -Path $path -ErrorAction Stop
    }
}
