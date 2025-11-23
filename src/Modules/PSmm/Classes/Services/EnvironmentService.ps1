<#
.SYNOPSIS
    Implementation of IEnvironmentService interface.

.DESCRIPTION
    Provides testable environment variable operations.
    This service can be mocked in tests for full testability.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
#>

using namespace System

<#
.SYNOPSIS
    Production implementation of environment variable service.
#>
class EnvironmentService : IEnvironmentService {
    
    <#
    .SYNOPSIS
        Gets an environment variable value.
    #>
    [string] GetVariable([string]$name) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new("Variable name cannot be empty", "name")
        }
        
        return [Environment]::GetEnvironmentVariable($name)
    }
    
    <#
    .SYNOPSIS
        Sets an environment variable value.
    #>
    [void] SetVariable([string]$name, [string]$value, [string]$scope) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new("Variable name cannot be empty", "name")
        }
        
        $validScopes = @('Process', 'User', 'Machine')
        if ($scope -notin $validScopes) {
            throw [ArgumentException]::new("Scope must be one of: $($validScopes -join ', ')", "scope")
        }
        
        [Environment]::SetEnvironmentVariable($name, $value, $scope)
    }
    
    <#
    .SYNOPSIS
        Gets the PATH environment variable as an array of entries.
    #>
    [string[]] GetPathEntries() {
        $path = $this.GetVariable('PATH')
        if ([string]::IsNullOrWhiteSpace($path)) {
            return @()
        }
        
        return $path -split [IO.Path]::PathSeparator | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
    
    <#
    .SYNOPSIS
        Adds an entry to the PATH environment variable.
    #>
    [void] AddPathEntry([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [ArgumentException]::new("Path cannot be empty", "path")
        }
        
        $currentPaths = $this.GetPathEntries()
        
        # Check if already exists (case-insensitive)
        if ($currentPaths -contains $path) {
            return
        }
        
        $newPath = ($currentPaths + $path) -join [IO.Path]::PathSeparator
        $this.SetVariable('PATH', $newPath, 'Process')
    }
    
    <#
    .SYNOPSIS
        Removes an entry from the PATH environment variable.
    #>
    [void] RemovePathEntry([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [ArgumentException]::new("Path cannot be empty", "path")
        }
        
        $currentPaths = $this.GetPathEntries()
        
        # Filter out the path (case-insensitive)
        $filteredPaths = $currentPaths | Where-Object { $_ -ne $path }
        
        if ($filteredPaths.Count -eq $currentPaths.Count) {
            # Path was not in the list
            return
        }
        
        $newPath = $filteredPaths -join [IO.Path]::PathSeparator
        $this.SetVariable('PATH', $newPath, 'Process')
    }
    
    <#
    .SYNOPSIS
        Gets the current working directory.
    #>
    [string] GetCurrentDirectory() {
        return [Environment]::CurrentDirectory
    }
    
    <#
    .SYNOPSIS
        Gets the current user name.
    #>
    [string] GetUserName() {
        return [Environment]::UserName
    }
    
    <#
    .SYNOPSIS
        Gets the computer name.
    #>
    [string] GetComputerName() {
        return [Environment]::MachineName
    }
}
