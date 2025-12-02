param(
    [Parameter(Mandatory)][string]$RepositoryRoot
)

# Centralized test helper script: dot-source this file with the repository root parameter
# to load common test helpers into the caller scope. Example:
#   . (Join-Path -Path $repoRoot -ChildPath 'tests/Support/Import-AllTestHelpers.ps1') -RepositoryRoot $repoRoot

# Import typed classes for tests
$importClassesScript = Join-Path -Path $RepositoryRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
if (Test-Path -Path $importClassesScript) { . $importClassesScript -RepositoryRoot $RepositoryRoot }

# Test filesystem service helper (provides [TestFileSystemService] type)
$tfs = Join-Path -Path $RepositoryRoot -ChildPath 'tests/Support/TestFileSystemService.ps1'
if (Test-Path -Path $tfs) { . $tfs }

# Test config helpers (New-TestAppConfiguration etc.)
$tc = Join-Path -Path $RepositoryRoot -ChildPath 'tests/Support/TestConfig.ps1'
if (Test-Path -Path $tc) { . $tc }

# Stub Write-PSmmLog helper
$stub = Join-Path -Path $RepositoryRoot -ChildPath 'tests/Support/Stub-WritePSmmLog.ps1'
if (Test-Path -Path $stub) { . $stub; Import-TestWritePSmmLogStub -RepositoryRoot $RepositoryRoot }

# Global filesystem guards to prevent writes to C:\ during tests
$guards = Join-Path -Path $RepositoryRoot -ChildPath 'tests/Support/GlobalFilesystemGuards.ps1'
if (Test-Path -Path $guards) { . $guards; Register-GlobalFilesystemGuards | Out-Null }

# Ensure PSmm.Logging module is available for tests that use InModuleScope
$psmmLoggingManifest = Join-Path -Path $RepositoryRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
$psmmLoggingRootModule = Join-Path -Path $RepositoryRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psm1'
try {
    if (-not (Get-Module -Name PSmm.Logging)) {
        if (Test-Path -Path $psmmLoggingManifest) { Import-Module $psmmLoggingManifest -Force -ErrorAction Stop }
        elseif (Test-Path -Path $psmmLoggingRootModule) { Import-Module $psmmLoggingRootModule -Force -ErrorAction Stop }
    }
}
catch {
    Write-Verbose ("[Import-AllTestHelpers] Failed to import PSmm.Logging module: " + $_.Exception.Message)
}

# Ensure PSmm module is available for tests (functions and private helpers)
$psmmManifest = Join-Path -Path $RepositoryRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
$psmmRootModule = Join-Path -Path $RepositoryRoot -ChildPath 'src/Modules/PSmm/PSmm.psm1'
try {
    if (Test-Path -Path $psmmManifest) { Import-Module $psmmManifest -Force -ErrorAction Stop }
    elseif (Test-Path -Path $psmmRootModule) { Import-Module $psmmRootModule -Force -ErrorAction Stop }
}
catch {
    Write-Verbose ("[Import-AllTestHelpers] Failed to import PSmm module: " + $_.Exception.Message)
}

return $true
