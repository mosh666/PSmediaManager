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

            $gitVersionOutput = & $gitVersionExe $RepositoryRoot /output json /nofetch 2>$null

            if ($LASTEXITCODE -eq 0 -and $gitVersionOutput) {
                try {
                    $gitVersionJson = ($gitVersionOutput | Out-String)
                    $gitVersionData = $gitVersionJson | ConvertFrom-Json -ErrorAction Stop

                    if ($IncludePrerelease) {
                        # Return full semantic version
                        if ($gitVersionData.PSObject.Properties['InformationalVersion']) {
                            return $gitVersionData.InformationalVersion
                        }
                        elseif ($gitVersionData.PSObject.Properties['FullSemVer']) {
                            return $gitVersionData.FullSemVer
                        }
                        elseif ($gitVersionData.PSObject.Properties['SemVer']) {
                            return $gitVersionData.SemVer
                        }
                    }
                    else {
                        # Return only Major.Minor.Patch for module manifests
                        if ($gitVersionData.PSObject.Properties['MajorMinorPatch']) {
                            return $gitVersionData.MajorMinorPatch
                        }
                        elseif ($gitVersionData.PSObject.Properties['SemVer']) {
                            # Extract Major.Minor.Patch from SemVer
                            $semVer = $gitVersionData.SemVer
                            if ($semVer -match '^(\d+\.\d+\.\d+)') {
                                return $matches[1]
                            }
                        }
                    }

                    Write-Verbose "Retrieved version from GitVersion: $($gitVersionData | ConvertTo-Json -Compress)"
                }
                catch {
                    Write-Warning "Failed to parse GitVersion JSON output: $_"
                }
            }
            else {
                Write-Warning "GitVersion did not return valid output (exit code: $LASTEXITCODE)"
            }
        }

        # Fallback: Try native git commands
        $gitExe = Get-Command git.exe -ErrorAction SilentlyContinue
        if ($gitExe) {
            Write-Verbose "Falling back to native git commands"

            # Try to get the latest tag
            $latestTag = & git.exe -C $RepositoryRoot describe --tags --abbrev=0 2>$null
            if ($latestTag) {
                $latestTag = $latestTag.Trim() -replace '^v', ''

                if ($IncludePrerelease) {
                    # Get commits since tag and short SHA
                    $commitsSinceTag = & git.exe -C $RepositoryRoot rev-list "$latestTag..HEAD" --count 2>$null
                    $shortSha = & git.exe -C $RepositoryRoot rev-parse --short HEAD 2>$null

                    if ($commitsSinceTag -and $shortSha) {
                        $commitsSinceTag = $commitsSinceTag.Trim()
                        $shortSha = $shortSha.Trim()

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
            $isRepo = & git.exe -C $RepositoryRoot rev-parse --git-dir 2>$null
            if ($isRepo) {
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
