<#
.SYNOPSIS
    Implementation of IGitService interface.

.DESCRIPTION
    Provides testable Git operations.
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
    Production implementation of Git service.
#>
class GitService : IGitService {

    <#
    .SYNOPSIS
        Gets the current branch name.
    #>
    [object] GetCurrentBranch([string]$repositoryPath) {
        if ([string]::IsNullOrWhiteSpace($repositoryPath)) {
            $repositoryPath = Get-Location
        }

        if (-not $this.IsRepository($repositoryPath)) {
            throw [InvalidOperationException]::new("Not a git repository: $repositoryPath")
        }

        try {
            Push-Location $repositoryPath
            $branch = git rev-parse --abbrev-ref HEAD 2>&1
            Pop-Location

            if ($LASTEXITCODE -ne 0) {
                throw [InvalidOperationException]::new("Failed to get current branch: $branch")
            }

            return [PSCustomObject]@{
                Name = $branch.Trim()
            }
        }
        catch {
            Pop-Location
            throw [InvalidOperationException]::new("Failed to get current branch: $_", $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        Gets the latest tag.
    #>
    [object] GetLatestTag([string]$repositoryPath) {
        if ([string]::IsNullOrWhiteSpace($repositoryPath)) {
            $repositoryPath = Get-Location
        }

        if (-not $this.IsRepository($repositoryPath)) {
            throw [InvalidOperationException]::new("Not a git repository: $repositoryPath")
        }

        try {
            Push-Location $repositoryPath
            $tag = git describe --tags --abbrev=0 2>&1
            Pop-Location

            if ($LASTEXITCODE -ne 0) {
                return $null
            }

            return [PSCustomObject]@{
                Name = $tag.Trim()
            }
        }
        catch {
            Pop-Location
            return $null
        }
    }

    <#
    .SYNOPSIS
        Gets the current commit hash.
    #>
    [object] GetCommitHash([string]$repositoryPath) {
        if ([string]::IsNullOrWhiteSpace($repositoryPath)) {
            $repositoryPath = Get-Location
        }

        if (-not $this.IsRepository($repositoryPath)) {
            throw [InvalidOperationException]::new("Not a git repository: $repositoryPath")
        }

        try {
            Push-Location $repositoryPath
            $hash = git rev-parse HEAD 2>&1
            $shortHash = git rev-parse --short HEAD 2>&1
            Pop-Location

            if ($LASTEXITCODE -ne 0) {
                throw [InvalidOperationException]::new("Failed to get commit hash: $hash")
            }

            return [PSCustomObject]@{
                Full = $hash.Trim()
                Short = $shortHash.Trim()
            }
        }
        catch {
            Pop-Location
            throw [InvalidOperationException]::new("Failed to get commit hash: $_", $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        Searches for a pattern in tracked files.
    #>
    [object[]] SearchForPattern([string]$pattern, [string]$filePattern) {
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            throw [ArgumentException]::new("Pattern cannot be empty", "pattern")
        }

        try {
            $gitArgs = @('grep', '-l', $pattern)

            if (-not [string]::IsNullOrWhiteSpace($filePattern)) {
                $gitArgs += '--'
                $gitArgs += $filePattern
            }

            $files = & git @gitArgs 2>&1

            if ($LASTEXITCODE -ne 0) {
                return @()
            }

            return @($files)
        }
        catch {
            return @()
        }
    }

    <#
    .SYNOPSIS
        Checks if a path is a Git repository.
    #>
    [bool] IsRepository([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $false
        }

        $gitDir = Join-Path -Path $path -ChildPath '.git'
        return Test-Path -Path $gitDir
    }
}
