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

# Module-level vault master password cache shared by Initialize-SystemVault and Get-SystemSecret
# Preserve existing cache value across module re-imports within the same session
if (-not (Get-Variable -Name _VaultMasterPasswordCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:_VaultMasterPasswordCache = $null
}

# Get module paths (service-aware - check variable existence first to avoid StrictMode errors)
$servicesVar = Get-Variable -Name 'Services' -Scope Script -ErrorAction SilentlyContinue
$hasServices = ($null -ne $servicesVar) -and ($null -ne $servicesVar.Value)
$pathProvider = if ($hasServices -and $servicesVar.Value.PathProvider) { $servicesVar.Value.PathProvider } else { $null }
$fileSystem   = if ($hasServices -and $servicesVar.Value.FileSystem) { $servicesVar.Value.FileSystem } else { $null }

if ($pathProvider) {
    $ClassesPath = $pathProvider.CombinePath(@($PSScriptRoot,'Classes'))
    $PublicPath  = $pathProvider.CombinePath(@($PSScriptRoot,'Public'))
    $PrivatePath = $pathProvider.CombinePath(@($PSScriptRoot,'Private'))
}
else {
    $ClassesPath = Join-Path -Path $PSScriptRoot -ChildPath 'Classes'
    $PublicPath  = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
    $PrivatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
}

# Import all classes, public and private functions
try {
    # Import classes first (order matters for dependencies)
    if ((($fileSystem) -and $fileSystem.TestPath($ClassesPath)) -or (-not $fileSystem -and (Test-Path $ClassesPath))) {
        # Load classes in dependency order
        # 1. Interfaces and base classes (no dependencies)
        # 2. Exception classes (inherit from base)
        # 3. Service implementations (implement interfaces)
        # 4. Configuration classes (use exceptions and interfaces)
        # 5. Builder classes (use configuration)
        # 6. DI container (uses all above)
        $ClassFiles = @(
            # Interfaces (required before implementations and exception classes that may inherit from them)
            'Interfaces.ps1',              # Interface contracts (no dependencies)
            'Exceptions.ps1',              # Exception classes (no dependencies)
            # Service implementations (in dependency order)
            'Services\FileSystemService.ps1', # File system service (implements IFileSystemService)
            'Services\EnvironmentService.ps1', # Environment service (implements IEnvironmentService)
            'Services\ProcessService.ps1',  # Process service (implements IProcessService)
            'Services\HttpService.ps1',    # HTTP service (implements IHttpService)
            'Services\CimService.ps1',     # CIM service (implements ICimService)
            'Services\GitService.ps1',     # Git service (implements IGitService)
            'Services\CryptoService.ps1',  # Crypto service (implements ICryptoService)
            'Services\StorageService.ps1', # Storage service (implements IStorageService)
            # Configuration classes (use services and interfaces)
            'AppConfiguration.ps1',        # Configuration classes (uses exceptions and interfaces)
            'ConfigValidator.ps1',         # Configuration validator (Phase 10)
            'AppConfigurationBuilder.ps1', # Builder (uses configuration and exceptions)
            # Domain model classes
            'ProjectInfo.ps1',             # Project information (type-safe project data)
            'PortInfo.ps1'                 # Port allocation information (type-safe port data)
        )

        $importDiagnostics = [System.Collections.Generic.List[object]]::new()
        foreach ($ClassFile in $ClassFiles) {
            $ClassPath = if ($pathProvider) { $pathProvider.CombinePath(@($ClassesPath,$ClassFile)) } else { Join-Path -Path $ClassesPath -ChildPath $ClassFile }
            if ((($fileSystem) -and $fileSystem.TestPath($ClassPath)) -or (-not $fileSystem -and (Test-Path $ClassPath))) {
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
    if ((($fileSystem) -and $fileSystem.TestPath($PublicPath)) -or (-not $fileSystem -and (Test-Path $PublicPath))) {
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
    if ((($fileSystem) -and $fileSystem.TestPath($PrivatePath)) -or (-not $fileSystem -and (Test-Path $PrivatePath))) {
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
        if ($fileSystem -and ($fileSystem | Get-Member -Name 'NewItem' -ErrorAction SilentlyContinue)) {
            $null = $fileSystem.NewItem($PrivatePath, 'Directory')
        }
        else {
            throw "FileSystem service is required to create Private functions directory: $PrivatePath"
        }
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
    'Invoke-StorageWizard',
    'Invoke-ManageStorage',
    'Remove-StorageGroup',
    'Test-DuplicateSerial',
    'Show-StorageInfo',
    'Export-SafeConfiguration',
    'Get-PSmmHealth',
    # KeePassXC Secret Management Functions
    'Get-KeePassCli',
    'Get-SystemSecret',
    'Get-SystemSecretMetadata',
    'Initialize-SystemVault',
    'Save-SystemSecret',
    # Drive Root Launcher
    'New-DriveRootLauncher',
    # Type-safe class factory functions
    'New-ProjectInfo',
    'New-PortInfo',
    'Get-ProjectInfoFromPath'
)

# Ensure host output helper is exported so scripts (outside the module)
# can call it after importing PSmm. This centralizes host I/O.
Export-ModuleMember -Function 'Write-PSmmHost'
