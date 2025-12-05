<#
.SYNOPSIS
    Core bootstrap service and interface definitions loaded before module imports.

.DESCRIPTION
    Provides minimal interface and service implementations required early in startup
    (prior to importing the PSmm module) so that dependency injection can be used
    for module discovery and loading. These classes are intentionally light-weight
    and do not depend on PSmm module types.

    Extracted from PSmm module (Option B refactor) to allow early service usage
    in `PSmediaManager.ps1` for path and file operations.

.NOTES
    Author: Der Mosh (refactor by automation)
    Version: 1.0.0
    Loads before any module imports.
#>

using namespace System
using namespace System.IO
using namespace System.Diagnostics

#region Interfaces (subset required for early bootstrap)
class IPathProvider {
    [string] GetPath([string]$pathKey) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
    [bool] EnsurePathExists([string]$path) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
    [string] CombinePath([string[]]$paths) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
}

class IFileSystemService {
    [bool] TestPath([string]$path) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
    [void] NewItem([string]$path, [string]$itemType) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
    [string] GetContent([string]$path) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
    [void] SetContent([string]$path, [string]$content) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
}

class IEnvironmentService {
    [string] GetVariable([string]$name) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
    [void] SetVariable([string]$name, [string]$value, [string]$scope) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
    [string[]] GetPathEntries() { throw [NotImplementedException]::new('Method must be implemented by derived class') }
    [void] AddPathEntry([string]$path) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
    [void] RemovePathEntry([string]$path) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
}

class IProcessService {
    [object] StartProcess([string]$filePath, [string[]]$argumentList) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
    [object] GetProcess([string]$name) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
    [bool] TestCommand([string]$command) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
    [object] InvokeCommand([string]$command, [string[]]$arguments) { throw [NotImplementedException]::new('Method must be implemented by derived class') }
}
#endregion Interfaces

#region Implementations
class PathProvider : IPathProvider {
    [string] GetPath([string]$pathKey) {
        # Minimal implementation – not used in early bootstrap beyond CombinePath
        return $null
    }
    [bool] EnsurePathExists([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) { return $false }
        if (-not (Test-Path -Path $path)) {
            $null = New-Item -Path $path -ItemType Directory -Force -ErrorAction SilentlyContinue
        }
        return (Test-Path -Path $path)
    }
    [string] CombinePath([string[]]$paths) {
        if ($null -eq $paths) { return '' }
        $pathsArray = @($paths)
        if ($pathsArray.Count -eq 0) { return '' }
        $clean = @($pathsArray | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($clean.Count -eq 0) { return '' }
        $result = $clean[0]
        for ($i = 1; $i -lt $clean.Count; $i++) { $result = [System.IO.Path]::Combine($result, $clean[$i]) }
        return $result
    }
}

class FileSystemService : IFileSystemService {
    [bool] TestPath([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) { return $false }
        return Test-Path -Path $path -ErrorAction SilentlyContinue
    }
    [void] NewItem([string]$path, [string]$itemType) {
        if ([string]::IsNullOrWhiteSpace($path)) { throw [ArgumentException]::new('Path cannot be empty','path') }
        if ([string]::IsNullOrWhiteSpace($itemType)) { throw [ArgumentException]::new('ItemType cannot be empty','itemType') }
        $null = New-Item -Path $path -ItemType $itemType -Force -ErrorAction Stop
    }
    [string] GetContent([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) { throw [ArgumentException]::new('Path cannot be empty','path') }
        if (-not $this.TestPath($path)) { throw [IO.FileNotFoundException]::new("File not found: $path") }
        return Get-Content -Path $path -Raw -ErrorAction Stop
    }
    [void] SetContent([string]$path, [string]$content) {
        if ([string]::IsNullOrWhiteSpace($path)) { throw [ArgumentException]::new('Path cannot be empty','path') }
        $dir = Split-Path -Path $path -Parent
        if (-not $this.TestPath($dir)) { $this.NewItem($dir,'Directory') }
        Set-Content -Path $path -Value $content -Force -ErrorAction Stop
    }
}

class EnvironmentService : IEnvironmentService {
    [string] GetVariable([string]$name) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw [ArgumentException]::new('Variable name cannot be empty','name') }
        return [Environment]::GetEnvironmentVariable($name)
    }
    [void] SetVariable([string]$name, [string]$value, [string]$scope) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw [ArgumentException]::new('Variable name cannot be empty','name') }
        $valid = @('Process','User','Machine')
        if ($scope -notin $valid) { throw [ArgumentException]::new("Scope must be one of: $($valid -join ', ')",'scope') }
        [Environment]::SetEnvironmentVariable($name,$value,$scope)
    }
    [string[]] GetPathEntries() {
        $path = $this.GetVariable('PATH'); if ([string]::IsNullOrWhiteSpace($path)) { return @() }
        return @($path -split [IO.Path]::PathSeparator | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    [void] AddPathEntry([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) { throw [ArgumentException]::new('Path cannot be empty','path') }
        $current = $this.GetPathEntries(); if ($current | Where-Object { $_ -ieq $path }) { return }
        $newPath = (@($path) + $current) -join [IO.Path]::PathSeparator
        $this.SetVariable('PATH',$newPath,'User')
        $this.SetVariable('PATH',$newPath,'Process')
    }
    [void] RemovePathEntry([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) { throw [ArgumentException]::new('Path cannot be empty','path') }
        $current = $this.GetPathEntries(); $filtered = @($current | Where-Object { $_ -ine $path })
        if ($filtered.Count -eq $current.Count) { return }
        $newPath = $filtered -join [IO.Path]::PathSeparator
        $this.SetVariable('PATH',$newPath,'User')
        $this.SetVariable('PATH',$newPath,'Process')
    }
}

class ProcessService : IProcessService {
    [object] StartProcess([string]$filePath, [string[]]$argumentList) {
        if ([string]::IsNullOrWhiteSpace($filePath)) { throw [ArgumentException]::new('File path cannot be empty','filePath') }
        $psi = [ProcessStartInfo]::new(); $psi.FileName = $filePath; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        if ($argumentList) { foreach ($a in $argumentList) { $psi.ArgumentList.Add($a) } }
        try {
            $p = [Process]::Start($psi); $stdout = $p.StandardOutput.ReadToEnd(); $stderr = $p.StandardError.ReadToEnd(); $p.WaitForExit()
            return [pscustomobject]@{ ExitCode = $p.ExitCode; StdOut = $stdout; StdErr = $stderr; Success = $p.ExitCode -eq 0 }
        }
        catch { throw [InvalidOperationException]::new("Failed to start process $filePath : $_", $_.Exception) }
    }
    [object] GetProcess([string]$name) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw [ArgumentException]::new('Process name cannot be empty','name') }
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue; if ($procs) { return $procs[0] }; return $null
    }
    [bool] TestCommand([string]$command) { if ([string]::IsNullOrWhiteSpace($command)) { return $false }; return $null -ne (Get-Command -Name $command -ErrorAction SilentlyContinue) }
    [object] InvokeCommand([string]$command, [string[]]$arguments) {
        if ([string]::IsNullOrWhiteSpace($command)) { throw [ArgumentException]::new('Command cannot be empty','command') }
        if (-not $this.TestCommand($command)) { throw [InvalidOperationException]::new("Command not found: $command") }
        try { $output = & $command @arguments 2>&1; $exit = $LASTEXITCODE; return [pscustomobject]@{ ExitCode = $exit; Output = $output; Success = $exit -eq 0 } }
        catch { throw [InvalidOperationException]::new("Failed to invoke command $command : $_", $_.Exception) }
    }
}
#endregion Implementations
