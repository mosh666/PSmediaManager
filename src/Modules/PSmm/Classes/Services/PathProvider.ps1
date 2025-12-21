<#
.SYNOPSIS
    Implementation of IPathProvider interface.

.DESCRIPTION
    Provides path operations via dependency injection.

    This class is designed as a thin wrapper around an inner IPathProvider
    implementation (typically AppPaths). When no inner provider is supplied,
    it falls back to minimal path-join and directory creation behavior.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
#>

using namespace System
using namespace System.IO

<#{
.SYNOPSIS
    Production path provider.
#>
class PathProvider : IPathProvider {

    hidden [IPathProvider] $Inner

    PathProvider() {
        $this.Inner = $null
    }

    PathProvider([IPathProvider]$inner) {
        $this.Inner = $inner
    }

    [string] GetPath([string]$pathKey) {
        if ($null -ne $this.Inner) {
            return $this.Inner.GetPath($pathKey)
        }

        return $null
    }

    [bool] EnsurePathExists([string]$path) {
        if ($null -ne $this.Inner) {
            return $this.Inner.EnsurePathExists($path)
        }

        if ([string]::IsNullOrWhiteSpace($path)) {
            return $false
        }

        if (-not (Test-Path -Path $path)) {
            $null = New-Item -Path $path -ItemType Directory -Force -ErrorAction SilentlyContinue
        }

        return (Test-Path -Path $path)
    }

    [string] CombinePath([string[]]$paths) {
        if ($null -ne $this.Inner) {
            return $this.Inner.CombinePath($paths)
        }

        if ($null -eq $paths) {
            return ''
        }

        $pathsArray = @($paths)
        if ($pathsArray.Count -eq 0) {
            return ''
        }

        $clean = @($pathsArray | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($clean.Count -eq 0) {
            return ''
        }

        $result = $clean[0]
        for ($i = 1; $i -lt $clean.Count; $i++) {
            $result = [System.IO.Path]::Combine($result, $clean[$i])
        }

        return $result
    }
}
