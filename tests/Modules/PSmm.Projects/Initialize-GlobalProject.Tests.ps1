Set-StrictMode -Version Latest

# Compute repo/test paths; Test support will be dot-sourced inside Describe to ensure availability in Pester scopes
$localRepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path

# Preload PSmm types (AppConfigurationBuilder, etc.)
. (Join-Path -Path $localRepoRoot -ChildPath 'tests/Preload-PSmmTypes.ps1')
$manifestPath = Join-Path -Path $localRepoRoot -ChildPath 'src/Modules/PSmm.Projects/PSmm.Projects.psd1'
$testConfigPath = Join-Path -Path $localRepoRoot -ChildPath 'tests/Support/TestConfig.ps1'

# Logging should be mocked by individual tests or supplied via PSmm.Logging module.

# Ensure logging module is available (provides Write-PSmmLog) before importing projects
$loggingManifest = Join-Path -Path $localRepoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
if (Test-Path -Path $loggingManifest) {
    if (Get-Module -Name 'PSmm.Logging' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm.Logging' -Force }
    Import-Module -Name $loggingManifest -Force -ErrorAction SilentlyContinue
}

if (Get-Module -Name 'PSmm.Projects' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'PSmm.Projects' -Force
}
Import-Module -Name $manifestPath -Force -ErrorAction Stop

Describe 'Initialize-GlobalProject' {
    # Ensure test support helpers are loaded in the Pester run-space for these tests
    . $testConfigPath
    InModuleScope 'PSmm.Projects' {
        BeforeAll {
            # Compute repo/test paths inside the test runspace and load helpers
            $localRepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
            $testConfigPath = Join-Path -Path $localRepoRoot -ChildPath 'tests/Support/TestConfig.ps1'
            . $testConfigPath
        }
        It 'creates _GLOBAL_ and Assets using FileSystem.NewItem and logs' {
            $config = New-TestAppConfiguration -InitializeProjectsPaths
            $config.Projects.Paths.Assets = 'Custom\\Assets'

            $created = New-Object System.Collections.Generic.List[string]
            $fs = [pscustomobject]@{}
            $psmTest = New-Object System.Management.Automation.PSScriptMethod('TestPath', { param([string]$Path) return $false })
            [void]$fs.PSObject.Methods.Add($psmTest)
            $psmNew = New-Object System.Management.Automation.PSScriptMethod('NewItem', { param($Path,$Type) $null = $created.Add($Path); return [pscustomobject]@{ FullName=$Path } })
            [void]$fs.PSObject.Methods.Add($psmNew)

            function Write-PSmmLog { param([string]$Level,[string]$Message,[string]$Body,[object]$ErrorRecord,[string]$Context,[switch]$Console,[switch]$File) }
            Mock -CommandName Write-PSmmLog -ModuleName 'PSmm.Projects' -MockWith {
                param([string]$Level,[string]$Message,[string]$Context)
            }

            $projectsRoot = Join-Path -Path $TestDrive -ChildPath 'Projects'
            Initialize-GlobalProject -ProjectsPath $projectsRoot -Config $config -FileSystem $fs

            $globalPath = Join-Path -Path $projectsRoot -ChildPath '_GLOBAL_'
            $assetsPath = Join-Path -Path $globalPath -ChildPath 'Custom\\Assets'
            $created | Should -Contain $globalPath
            $created | Should -Contain $assetsPath

            Assert-MockCalled -CommandName Write-PSmmLog -ModuleName 'PSmm.Projects' -Times 1 -ParameterFilter {
                $Context -eq 'Initialize-GlobalProject' -and $Message -like '*Created _GLOBAL_ project folder*'
            }
        }

        It 'uses default Assets path when not configured' {
            $config = New-TestAppConfiguration
            # Remove/omit Assets path to trigger default
            $config.Projects.Paths = @{}

            $projectsRoot = Join-Path -Path $TestDrive -ChildPath 'Projects'
            $globalPath = Join-Path -Path $projectsRoot -ChildPath '_GLOBAL_'

            $fs = [pscustomobject]@{}
            $psmTest = New-Object System.Management.Automation.PSScriptMethod('TestPath', {
                param([string]$Path)
                if ($Path -eq $globalPath) { return $true } else { return $false }
            })
            [void]$fs.PSObject.Methods.Add($psmTest)
            $psmNew = New-Object System.Management.Automation.PSScriptMethod('NewItem', { param($Path,$Type) return [pscustomobject]@{ FullName=$Path } })
            [void]$fs.PSObject.Methods.Add($psmNew)

            function Write-PSmmLog { param([string]$Level,[string]$Message,[string]$Body,[object]$ErrorRecord,[string]$Context,[switch]$Console,[switch]$File) }
            { Initialize-GlobalProject -ProjectsPath $projectsRoot -Config $config -FileSystem $fs } | Should -Not -Throw
        }

        It 'does nothing when both _GLOBAL_ and Assets already exist' {
            $config = New-TestAppConfiguration -InitializeProjectsPaths
            $config.Projects.Paths.Assets = 'Lib\\Assets'

            $fs = [pscustomobject]@{}
            $psmTest = New-Object System.Management.Automation.PSScriptMethod('TestPath', {
                param([string]$Path)
                return $true
            })
            [void]$fs.PSObject.Methods.Add($psmTest)

            $newItemCalls = 0
            function Write-PSmmLog { param([string]$Level,[string]$Message,[string]$Body,[object]$ErrorRecord,[string]$Context,[switch]$Console,[switch]$File) }
            Mock -CommandName New-Item -ModuleName 'PSmm.Projects' -MockWith { $script:newItemCalls++ }
            Mock -CommandName Write-PSmmLog -ModuleName 'PSmm.Projects' -MockWith { }

            $projectsRoot = Join-Path -Path $TestDrive -ChildPath 'Projects'
            Initialize-GlobalProject -ProjectsPath $projectsRoot -Config $config -FileSystem $fs

            $newItemCalls | Should -Be 0
        }
    }
}
