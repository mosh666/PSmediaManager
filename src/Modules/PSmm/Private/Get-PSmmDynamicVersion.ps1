<#
.SYNOPSIS
    Dynamic version helper for PSmediaManager and all modules.

.DESCRIPTION
    Provides a centralized function to retrieve the application version from Git
    using GitVersion. This ensures all modules and the application derive their
    version from a single, consistent source.

.NOTES
    Author: Der Mosh
    Version: 1.0.0
    Last Modified: 2025-12-08

    This helper is designed to be dot-sourced or imported before module manifests
    are processed, allowing dynamic version injection at import time.
#>

using namespace System.IO

$__psmmDynVerRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($__psmmDynVerRoot)) {
    try {
        $__psmmDynVerRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    catch {
        $__psmmDynVerRoot = $null
    }
}

if (-not [string]::IsNullOrWhiteSpace($__psmmDynVerRoot)) {
    $nativeCapture = Join-Path -Path $__psmmDynVerRoot -ChildPath 'Invoke-PSmmNativeProcessCapture.ps1'
    if (Test-Path -LiteralPath $nativeCapture) {
        . $nativeCapture
    }
}

if (-not (Get-Command -Name Invoke-PSmmNativeProcessCapture -ErrorAction SilentlyContinue)) {
    throw "Invoke-PSmmNativeProcessCapture helper not available. Expected to dot-source 'Invoke-PSmmNativeProcessCapture.ps1'."
}

<#
.SYNOPSIS
    Gets the dynamic version from Git using GitVersion.

.DESCRIPTION
    Retrieves the semantic version from Git using GitVersion or falls back to
    git native commands. Returns a version string suitable for PowerShell module
    manifests (Major.Minor.Patch format).

.PARAMETER RepositoryRoot
    Path to the repository root. If not specified, attempts to discover from script location.

.PARAMETER IncludePrerelease
    If specified, returns the full semantic version including prerelease tags.
    Otherwise, returns only Major.Minor.Patch for module manifest compatibility.

.OUTPUTS
    String - Version in format "Major.Minor.Patch" or full SemVer if -IncludePrerelease

.EXAMPLE
    $version = Get-PSmmDynamicVersion
    # Returns: "0.1.0"

.EXAMPLE
    $fullVersion = Get-PSmmDynamicVersion -IncludePrerelease
    # Returns: "0.1.0-alpha.5+Branch.dev.Sha.abc1234"
#>
function Get-PSmmDynamicVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$RepositoryRoot,

        [Parameter()]
        [switch]$IncludePrerelease
    )

    try {
        # Discover repository root if not provided
        if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
            $scriptPath = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($scriptPath)) {
                $scriptPath = $PWD.Path
            }

            # Walk up to find .git directory
            $current = $scriptPath
            $maxDepth = 10
            $depth = 0

            while ($depth -lt $maxDepth) {
                $gitPath = Join-Path -Path $current -ChildPath '.git'
                if (Test-Path -Path $gitPath) {
                    $RepositoryRoot = $current
                    break
                }

                $parent = Split-Path -Path $current -Parent
                if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
                    break
                }

                $current = $parent
                $depth++
            }

            if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
                Write-Warning "Could not locate Git repository root from: $scriptPath"
                return '0.0.1'
            }
        }

        if (-not (Test-Path -Path $RepositoryRoot)) {
            Write-Warning "Repository root not found: $RepositoryRoot"
            return '0.0.1'
        }

        # Try to find GitVersion executable
        $gitVersionExe = $null

        # 1. Check in repository's plugin directory structure
        $possiblePluginPaths = @(
            (Join-Path -Path $RepositoryRoot -ChildPath '..\PSmm.Plugins'),
            (Join-Path -Path (Split-Path -Path $RepositoryRoot -Parent) -ChildPath 'PSmm.Plugins')
        )

        foreach ($pluginPath in $possiblePluginPaths) {
            if (Test-Path -Path $pluginPath) {
                $gitVersionDir = Get-ChildItem -Path $pluginPath -Directory -ErrorAction SilentlyContinue |
                                 Where-Object { $_.Name -like 'gitversion*' } |
                                 Select-Object -First 1

                if ($gitVersionDir) {
                    $gitVersionCandidate = Join-Path -Path $gitVersionDir.FullName -ChildPath 'gitversion.exe'
                    if (Test-Path -Path $gitVersionCandidate) {
                        $gitVersionExe = $gitVersionCandidate
                        break
                    }
                }
            }
        }

        # 2. Fall back to PATH
        if (-not $gitVersionExe) {
            $gitVersionCmd = Get-Command gitversion.exe -ErrorAction SilentlyContinue
            if ($gitVersionCmd) {
                $gitVersionExe = $gitVersionCmd.Source
            }
        }

        # Execute GitVersion if available
        if ($gitVersionExe) {
            Write-Verbose "Using GitVersion: $gitVersionExe"

            $gitVersionResult = Invoke-PSmmNativeProcessCapture -FilePath $gitVersionExe -ArgumentList @(
                $RepositoryRoot,
                '/output',
                'json',
                '/nofetch'
            )

            if ($gitVersionResult.Success -and -not [string]::IsNullOrWhiteSpace($gitVersionResult.StdOut)) {
                try {
                    $gitVersionJson = [string]$gitVersionResult.StdOut
                    $gitVersionData = $gitVersionJson | ConvertFrom-Json -ErrorAction Stop

                    if ($IncludePrerelease) {
                        # Return full semantic version
                        try { $v = $gitVersionData.InformationalVersion } catch { $v = $null }
                        if ($null -ne $v) { return $v }

                        try { $v = $gitVersionData.FullSemVer } catch { $v = $null }
                        if ($null -ne $v) { return $v }

                        try { $v = $gitVersionData.SemVer } catch { $v = $null }
                        if ($null -ne $v) { return $v }
                    }
                    else {
                        # Return only Major.Minor.Patch for module manifests
                        try { $v = $gitVersionData.MajorMinorPatch } catch { $v = $null }
                        if ($null -ne $v) { return $v }

                        # Extract Major.Minor.Patch from SemVer
                        try { $semVer = $gitVersionData.SemVer } catch { $semVer = $null }
                        if ($semVer -and $semVer -match '^(\d+\.\d+\.\d+)') {
                            return $matches[1]
                        }
                    }

                    Write-Verbose "Retrieved version from GitVersion: $($gitVersionData | ConvertTo-Json -Compress)"
                }
                catch {
                    Write-Warning "Failed to parse GitVersion JSON output: $_"
                }
            }
            else {
                $exitCode = [int]$gitVersionResult.ExitCode
                Write-Warning "GitVersion did not return valid output (exit code: $exitCode)"
            }
        }

        # Fallback: Try native git commands
        $gitExe = Get-Command git.exe -ErrorAction SilentlyContinue
        if ($gitExe) {
            Write-Verbose "Falling back to native git commands"

            # Try to get the latest tag
            $latestTagResult = Invoke-PSmmNativeProcessCapture -FilePath 'git.exe' -ArgumentList @(
                '-C',
                $RepositoryRoot,
                'describe',
                '--tags',
                '--abbrev=0'
            )

            $latestTag = $null
            if ($latestTagResult.Success -and -not [string]::IsNullOrWhiteSpace($latestTagResult.StdOut)) {
                $latestTag = $latestTagResult.StdOut.Trim() -replace '^v', ''
            }

            if ($latestTag) {

                if ($IncludePrerelease) {
                    # Get commits since tag and short SHA
                    $commitsResult = Invoke-PSmmNativeProcessCapture -FilePath 'git.exe' -ArgumentList @(
                        '-C',
                        $RepositoryRoot,
                        'rev-list',
                        "$latestTag..HEAD",
                        '--count'
                    )

                    $shaResult = Invoke-PSmmNativeProcessCapture -FilePath 'git.exe' -ArgumentList @(
                        '-C',
                        $RepositoryRoot,
                        'rev-parse',
                        '--short',
                        'HEAD'
                    )

                    if ($commitsResult.Success -and $shaResult.Success -and $commitsResult.StdOut -and $shaResult.StdOut) {
                        $commitsSinceTag = $commitsResult.StdOut.Trim()
                        $shortSha = $shaResult.StdOut.Trim()

                        if ($commitsSinceTag -eq '0') {
                            return "$latestTag-$shortSha"
                        }
                        else {
                            return "$latestTag-alpha.$commitsSinceTag+$shortSha"
                        }
                    }
                }

                # Extract Major.Minor.Patch
                if ($latestTag -match '^(\d+\.\d+\.\d+)') {
                    return $matches[1]
                }
            }

            # No tags yet - check if we're in a repo at all
            $repoResult = Invoke-PSmmNativeProcessCapture -FilePath 'git.exe' -ArgumentList @(
                '-C',
                $RepositoryRoot,
                'rev-parse',
                '--git-dir'
            )
            if ($repoResult.Success) {
                Write-Verbose "No tags found in repository - using initial version 0.0.1"
                return '0.0.1'
            }
        }

        # Ultimate fallback
        Write-Warning "Unable to determine version from Git - using fallback 0.0.1"
        return '0.0.1'
    }
    catch {
        Write-Warning "Error retrieving dynamic version: $_"
        return '0.0.1'
    }
}

<#
.SYNOPSIS
    Gets the full semantic version including prerelease and metadata.

.DESCRIPTION
    Convenience wrapper for Get-PSmmDynamicVersion -IncludePrerelease.
    Returns the full semantic version string suitable for AppVersion property.

.PARAMETER RepositoryRoot
    Path to the repository root.

.OUTPUTS
    String - Full semantic version (e.g., "0.1.0-alpha.5+Branch.dev.Sha.abc1234")

.EXAMPLE
    $appVersion = Get-PSmmFullVersion
    # Returns: "0.1.0-alpha.5+Branch.dev.Sha.abc1234"
#>
function Get-PSmmFullVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$RepositoryRoot
    )

    Get-PSmmDynamicVersion -RepositoryRoot $RepositoryRoot -IncludePrerelease
}

# Note: When dot-sourced (not imported as module), functions are automatically available
# No Export-ModuleMember needed in this context
