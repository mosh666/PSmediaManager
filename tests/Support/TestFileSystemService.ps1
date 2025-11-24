#Requires -Version 7.5.4
Set-StrictMode -Version Latest

class TestFileSystemService {
    [hashtable]$Entries

    TestFileSystemService([string[]]$InitialDirectories) {
        $this.Entries = @{}
        if ($null -ne $InitialDirectories) {
            foreach ($dir in $InitialDirectories) {
                if ([string]::IsNullOrWhiteSpace($dir)) { continue }
                $this.AddDirectory($dir, [datetime]::UtcNow)
            }
        }
    }

    [void] AddDirectory([string]$Path, [datetime]$LastWriteTime) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        $key = $this.NormalizeKey($Path)
        $normalizedPath = $this.NormalizePath($Path)
        $leaf = $this.GetLeafName($normalizedPath)
        if (-not $this.Entries.ContainsKey($key)) {
            $this.Entries[$key] = [pscustomobject]@{
                Name = $leaf
                FullName = $normalizedPath
                LastWriteTime = $LastWriteTime
            }
        }
        else {
            $this.Entries[$key].LastWriteTime = $LastWriteTime
            $this.Entries[$key].FullName = $normalizedPath
            $this.Entries[$key].Name = $leaf
        }
    }

    [void] SetLastWriteTime([string]$Path, [datetime]$LastWriteTime) {
        $key = $this.NormalizeKey($Path)
        if ($this.Entries.ContainsKey($key)) {
            $this.Entries[$key].LastWriteTime = $LastWriteTime
        }
    }

    [bool] TestPath([string]$Path) {
        $key = $this.NormalizeKey($Path)
        return $this.Entries.ContainsKey($key)
    }

    [pscustomobject] GetItemProperty([string]$Path) {
        $key = $this.NormalizeKey($Path)
        if (-not $this.Entries.ContainsKey($key)) {
            throw "Path '$Path' was not seeded in TestFileSystemService"
        }
        return $this.Entries[$key]
    }

    [object[]] GetChildItem([string]$Path, $Filter, [string]$ItemType) {
        $parentKey = $this.NormalizeKey($Path)
        $children = @()
        foreach ($entryKey in $this.Entries.Keys) {
            $entry = $this.Entries[$entryKey]
            $entryParentKey = $this.GetParentKey($entry.FullName)
            if ($entryParentKey -eq $parentKey) {
                $children += [pscustomobject]@{
                    Name = $entry.Name
                    FullName = $entry.FullName
                }
            }
        }
        return $children
    }

    [pscustomobject] NewItem([string]$Path, [string]$ItemType) {
        $now = [datetime]::UtcNow
        $this.AddDirectory($Path, $now)
        return $this.GetItemProperty($Path)
    }

    [string] NormalizeKey([string]$Path) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
        $normalized = $this.NormalizePath($Path).Replace('/', '\\')
        if ($normalized -match '^[A-Za-z]:\\$') {
            return $normalized.ToUpperInvariant()
        }
        return $normalized.TrimEnd('\\').ToUpperInvariant()
    }

    [string] NormalizePath([string]$Path) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
        try {
            return [System.IO.Path]::GetFullPath($Path)
        }
        catch {
            return $Path
        }
    }

    [string] GetLeafName([string]$Path) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
        $leaf = Split-Path -Path $Path -Leaf
        if ([string]::IsNullOrWhiteSpace($leaf)) {
            return $Path.TrimEnd('\')
        }
        return $leaf
    }

    [string] GetParentKey([string]$Path) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
        $parent = Split-Path -Path $Path -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            return ''
        }
        return $this.NormalizeKey($parent)
    }
}

function New-TestFileSystemService {
    [CmdletBinding()]
    param(
        [string[]]$Directories,
        [hashtable]$LastWriteTimes
    )

    $service = [TestFileSystemService]::new($Directories)
    if ($null -ne $LastWriteTimes) {
        foreach ($path in $LastWriteTimes.Keys) {
            $service.SetLastWriteTime($path, $LastWriteTimes[$path])
        }
    }
    return $service
}
