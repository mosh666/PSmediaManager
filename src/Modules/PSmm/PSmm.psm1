<#
.SYNOPSIS
    PowerShell module for bootstrapping PSmediaManager.

.DESCRIPTION
    Core module that imports all public and private functions for the PSmediaManager application.
    This module serves as the entry point for all core functionality including:
    - Application bootstrapping
    - Directory structure creation
    - Environment path management
    - Custom filename generation
    - Storage management

.NOTES
    Module Name: PSmm
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
    Last Modified: 2025-11-03
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Get module paths
$ClassesPath = Join-Path -Path $PSScriptRoot -ChildPath 'Classes'
$PublicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$PrivatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

# Import all classes, public and private functions
try {
    # Import classes first (order matters for dependencies)
    if (Test-Path $ClassesPath) {
        # Load classes in dependency order
        # 1. Interfaces and base classes (no dependencies)
        # 2. Exception classes (inherit from base)
        # 3. Service implementations (implement interfaces)
        # 4. Configuration classes (use exceptions and interfaces)
        # 5. Builder classes (use configuration)
        # 6. DI container (uses all above)
        $ClassFiles = @(
            'Interfaces.ps1', # Interface definitions (no dependencies)
            'Exceptions.ps1', # Exception classes (no dependencies)
            'Services\FileSystemService.ps1', # File system service (implements IFileSystemService)
            'Services\EnvironmentService.ps1', # Environment service (implements IEnvironmentService)
            'Services\HttpService.ps1', # HTTP service (implements IHttpService)
            'Services\ProcessService.ps1', # Process service (implements IProcessService)
            'Services\CimService.ps1', # CIM service (implements ICimService)
            'Services\GitService.ps1', # Git service (implements IGitService)
            'Services\CryptoService.ps1', # Crypto service (implements ICryptoService)
            'AppConfiguration.ps1', # Configuration classes (uses exceptions and interfaces)
            'AppConfigurationBuilder.ps1' # Builder (uses configuration and exceptions)
        )

        $importDiagnostics = [System.Collections.Generic.List[object]]::new()
        foreach ($ClassFile in $ClassFiles) {
            $ClassPath = Join-Path -Path $ClassesPath -ChildPath $ClassFile
            if (Test-Path $ClassPath) {
                Write-Verbose "[ClassImport] BEGIN $ClassFile"
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    . $ClassPath
                    $sw.Stop()
                    $importDiagnostics.Add([pscustomobject]@{ Type = 'Class'; Name = $ClassFile; Status = 'OK'; Milliseconds = $sw.ElapsedMilliseconds })
                    $ms = $sw.ElapsedMilliseconds
                    Write-Verbose "[ClassImport] OK $ClassFile ($ms ms)"
                }
                catch {
                    $sw.Stop()
                    $errMsg = $_.Exception.Message
                    $ms = $sw.ElapsedMilliseconds
                    $importDiagnostics.Add([pscustomobject]@{ Type = 'Class'; Name = $ClassFile; Status = 'FAIL'; Milliseconds = $ms; Error = $errMsg })
                    Write-Error "[ClassImport] FAIL $ClassFile ($ms ms): $errMsg"
                    throw "Failed to import class '$ClassFile': $errMsg"
                }
            }
            else {
                Write-Warning "Class file not found: $ClassPath"
                $importDiagnostics.Add([pscustomobject]@{ Type = 'Class'; Name = $ClassFile; Status = 'MISSING'; Milliseconds = 0 })
            }
        }
        Write-Verbose "Imported class files summary:"
        foreach ($d in $importDiagnostics) {
            $hasErrorProp = ($d.PSObject.Properties.Match('Error').Count -gt 0)
            $suffix = if ($hasErrorProp -and $null -ne $d.Error) { " => $($d.Error)" } else { '' }
            Write-Verbose ("  - {0}:{1} ({2} ms){3}" -f $d.Type, $d.Name, $d.Milliseconds, $suffix)
        }
        $failures = $importDiagnostics | Where-Object { ($_ -ne $null) -and ($_.PSObject.Properties.Match('Status').Count -gt 0) -and ($_.Status -eq 'FAIL') }
        $failureCount = @($failures).Count
        Write-Verbose "Imported $($ClassFiles.Count) class file(s) (Failures: $failureCount)"
    }
    else {
        Write-Verbose "Classes path not found: $ClassesPath"
    }

    # Import public functions
    if (Test-Path $PublicPath) {
        $PublicFunctions = @(Get-ChildItem -Path "$PublicPath\*.ps1" -Recurse -ErrorAction SilentlyContinue)

        if ($PublicFunctions.Count -gt 0) {
            foreach ($Function in $PublicFunctions) {
                try {
                    Write-Verbose "Importing public function: $($Function.Name)"
                    . $Function.FullName
                }
                catch {
                    throw "Failed to import public function '$($Function.Name)': $_"
                }
            }
            Write-Verbose "Imported $($PublicFunctions.Count) public function(s)"
        }
        else {
            Write-Warning "No public functions found in: $PublicPath"
        }
    }
    else {
        throw "Public functions path not found: $PublicPath"
    }

    # Import private functions
    if (Test-Path $PrivatePath) {
        $PrivateFunctions = @(Get-ChildItem -Path "$PrivatePath\*.ps1" -Recurse -ErrorAction SilentlyContinue)

        if ($PrivateFunctions.Count -gt 0) {
            foreach ($Function in $PrivateFunctions) {
                try {
                    Write-Verbose "Importing private function: $($Function.Name)"
                    . $Function.FullName
                }
                catch {
                    throw "Failed to import private function '$($Function.Name)': $_"
                }
            }
            Write-Verbose "Imported $($PrivateFunctions.Count) private function(s)"
        }
        else {
            Write-Verbose "No private functions found in: $PrivatePath"
        }
    }
    else {
        Write-Verbose "Creating Private functions directory: $PrivatePath"
        New-Item -Path $PrivatePath -ItemType Directory -Force | Out-Null
    }
}
catch {
    throw "Failed to import module functions: $_"
}

# Export module members (public API only)
Export-ModuleMember -Function @(
    'Invoke-PSmm',
    'New-CustomFileName',
    'New-DirectoriesFromHashtable',
    'Confirm-Storage',
    'Get-StorageDrive',
    'Show-StorageInfo',
    'Export-SafeConfiguration',
    # KeePassXC Secret Management Functions
    'Get-SystemSecret',
    'Get-SystemSecretMetadata',
    'Initialize-SystemVault',
    'Save-SystemSecret',
    # Drive Root Launcher
    'New-DriveRootLauncher'
)
