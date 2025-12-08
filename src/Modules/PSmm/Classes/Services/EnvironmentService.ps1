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
        return $this.GetPathEntriesForTarget([EnvironmentVariableTarget]::Process)
    }

    <#
    .SYNOPSIS
        Adds an entry to the PATH environment variable.
    #>
    [void] AddPathEntry([string]$path, [bool]$persistUser = $false) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [ArgumentException]::new("Path cannot be empty", "path")
        }

        $this.AddPathEntries(@($path), $persistUser)
    }

    <#
    .SYNOPSIS
        Adds multiple entries to the PATH environment variable in one pass.
    #>
    [void] AddPathEntries([string[]]$paths, [bool]$persistUser = $false) {
        $pathArray = @($paths)
        if (-not $pathArray -or $pathArray.Count -eq 0) {
            return
        }

        $validPaths = @($pathArray | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if (-not $validPaths -or $validPaths.Count -eq 0) {
            return
        }

        $currentPaths = $this.GetPathEntries()
        $pathSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($existing in $currentPaths) {
            $pathSet.Add($existing) | Out-Null
        }

        $orderedPaths = [System.Collections.Generic.List[string]]::new()
        $added = $false

        foreach ($candidate in $validPaths) {
            if ($pathSet.Add($candidate)) {
                $orderedPaths.Add($candidate)
                $added = $true
            }
        }

        if (-not $added) {
            if ($persistUser) {
                $this.SyncUserPath($currentPaths)
            }
            return
        }

        foreach ($existing in $currentPaths) {
            $orderedPaths.Add($existing)
        }

        $this.UpdatePathVariables($orderedPaths, $persistUser)
    }

    <#
    .SYNOPSIS
        Removes an entry from the PATH environment variable.
    #>
    [void] RemovePathEntry([string]$path, [bool]$persistUser = $false) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw [ArgumentException]::new("Path cannot be empty", "path")
        }

        $this.RemovePathEntries(@($path), $persistUser)
    }

    <#
    .SYNOPSIS
        Removes multiple entries from the PATH in one pass.
    #>
    [void] RemovePathEntries([string[]]$paths, [bool]$persistUser = $false) {
        $pathArray = @($paths)
        if (-not $pathArray -or $pathArray.Count -eq 0) {
            return
        }

        $validPaths = @($pathArray | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if (-not $validPaths -or $validPaths.Count -eq 0) {
            return
        }

        $currentPaths = $this.GetPathEntries()
        if (-not $currentPaths -or $currentPaths.Count -eq 0) {
            if ($persistUser) {
                $this.RemoveFromUserPath($validPaths)
            }
            return
        }

        $pathSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($existing in $currentPaths) {
            $pathSet.Add($existing) | Out-Null
        }

        $removed = $false
        foreach ($candidate in $validPaths) {
            if ($pathSet.Remove($candidate)) {
                $removed = $true
            }
        }

        if (-not $removed) {
            if ($persistUser) {
                $this.RemoveFromUserPath($validPaths)
            }
            return
        }

        $orderedPaths = [System.Collections.Generic.List[string]]::new()
        foreach ($existing in $currentPaths) {
            if ($pathSet.Contains($existing)) {
                $orderedPaths.Add($existing)
            }
        }

        if ($persistUser) {
            $this.RemoveFromUserPath($validPaths)
        }

        $this.UpdatePathVariables($orderedPaths, $persistUser)
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

    hidden [string[]] GetPathEntriesForTarget([EnvironmentVariableTarget]$target) {
        $path = [Environment]::GetEnvironmentVariable('PATH', $target)
        if ([string]::IsNullOrWhiteSpace($path)) {
            return @()
        }

        return $path -split [IO.Path]::PathSeparator | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    hidden [void] UpdatePathVariables([System.Collections.Generic.List[string]]$paths, [bool]$persistUser) {
        $newPath = $paths.ToArray() -join [IO.Path]::PathSeparator
        $this.SetVariable('PATH', $newPath, 'Process')

        if ($persistUser) {
            $this.SyncUserPath($paths)
        }
    }

    hidden [void] SyncUserPath([System.Collections.Generic.IEnumerable[string]]$orderedProcessPaths) {
        $userEntries = $this.GetPathEntriesForTarget([EnvironmentVariableTarget]::User)
        $pathSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

        $orderedUserPaths = [System.Collections.Generic.List[string]]::new()
        foreach ($path in $orderedProcessPaths) {
            if ($pathSet.Add($path)) {
                $orderedUserPaths.Add($path)
            }
        }

        foreach ($entry in $userEntries) {
            if ($pathSet.Add($entry)) {
                $orderedUserPaths.Add($entry)
            }
        }

        $userPath = $orderedUserPaths.ToArray() -join [IO.Path]::PathSeparator
        $this.SetVariable('PATH', $userPath, 'User')
    }

    hidden [void] RemoveFromUserPath([string[]]$paths) {
        $userEntries = $this.GetPathEntriesForTarget([EnvironmentVariableTarget]::User)
        if (-not $userEntries -or $userEntries.Count -eq 0) {
            return
        }

        $pathSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $userEntries) {
            $pathSet.Add($entry) | Out-Null
        }

        $removed = $false
        foreach ($candidate in $paths) {
            if ($pathSet.Remove($candidate)) {
                $removed = $true
            }
        }

        if (-not $removed) {
            return
        }

        $newUserPath = $pathSet.ToArray() -join [IO.Path]::PathSeparator
        $this.SetVariable('PATH', $newUserPath, 'User')
    }
}
