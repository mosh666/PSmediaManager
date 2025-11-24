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

return $true
