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

    [IProcessService] $Process

    GitService() {
        throw [InvalidOperationException]::new('GitService requires an injected Process service. Construct via DI (GitService(Process)).')
    }

    GitService([IProcessService]$Process) {
        if ($null -eq $Process) {
            throw [InvalidOperationException]::new('GitService requires an injected Process service (Process is null).')
        }
        $this.Process = $Process
    }

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
            if (-not $this.Process.TestCommand('git')) {
                throw [InvalidOperationException]::new('Git command not found: git')
            }

            $result = $this.Process.InvokeCommand('git', @(
                    '-C',
                    $repositoryPath,
                    'rev-parse',
                    '--abbrev-ref',
                    'HEAD'
                ))

            if (-not $result.Success) {
                throw [InvalidOperationException]::new("Failed to get current branch: $($result.Output | Out-String)")
            }

            $branch = ($result.Output | Out-String).Trim()
            return [PSCustomObject]@{ Name = $branch }
        }
        catch {
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
            if (-not $this.Process.TestCommand('git')) {
                return $null
            }

            $result = $this.Process.InvokeCommand('git', @(
                    '-C',
                    $repositoryPath,
                    'describe',
                    '--tags',
                    '--abbrev=0'
                ))

            if (-not $result.Success) {
                return $null
            }

            $tag = ($result.Output | Out-String).Trim()
            if ([string]::IsNullOrWhiteSpace($tag)) {
                return $null
            }

            return [PSCustomObject]@{ Name = $tag }
        }
        catch {
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
            if (-not $this.Process.TestCommand('git')) {
                throw [InvalidOperationException]::new('Git command not found: git')
            }

            $fullResult = $this.Process.InvokeCommand('git', @(
                    '-C',
                    $repositoryPath,
                    'rev-parse',
                    'HEAD'
                ))

            if (-not $fullResult.Success) {
                throw [InvalidOperationException]::new("Failed to get commit hash: $($fullResult.Output | Out-String)")
            }

            $shortResult = $this.Process.InvokeCommand('git', @(
                    '-C',
                    $repositoryPath,
                    'rev-parse',
                    '--short',
                    'HEAD'
                ))

            if (-not $shortResult.Success) {
                throw [InvalidOperationException]::new("Failed to get short commit hash: $($shortResult.Output | Out-String)")
            }

            $hash = ($fullResult.Output | Out-String).Trim()
            $shortHash = ($shortResult.Output | Out-String).Trim()

            return [PSCustomObject]@{
                Full = $hash
                Short = $shortHash
            }
        }
        catch {
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

            if (-not $this.Process.TestCommand('git')) {
                return @()
            }

            $result = $this.Process.InvokeCommand('git', $gitArgs)
            if (-not $result.Success) {
                return @()
            }

            return @($result.Output)
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
