#Requires -Version 7.5.4
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.5' }

Describe 'Clear-PSmmProjectRegistry' {
    BeforeAll {
        $ErrorActionPreference = 'Stop'
        $RootPath = Split-Path $PSScriptRoot -Parent | Split-Path -Parent | Split-Path -Parent

        # Load all test helpers including stubs
        $importAllHelpersScript = Join-Path -Path $RootPath -ChildPath 'tests/Support/Import-AllTestHelpers.ps1'
        if (Test-Path -Path $importAllHelpersScript) { . $importAllHelpersScript -RepositoryRoot $RootPath }

        # Remove modules to ensure clean state for this test
        if (Get-Module -Name 'PSmm.Projects' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm.Projects' -Force }
        if (Get-Module -Name 'PSmm' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm' -Force }

        # Import PSmm module first for dependencies
        $PSmm = Join-Path $RootPath 'src\Modules\PSmm\PSmm.psd1'
        Import-Module $PSmm -Force

        # Import the module
        $ModulePath = Join-Path $RootPath 'src\Modules\PSmm.Projects\PSmm.Projects.psd1'
        Import-Module $ModulePath -Force
    }

    AfterAll {
        # Clean up modules after test to avoid state pollution for next test file
        if (Get-Module -Name 'PSmm.Projects' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm.Projects' -Force }
        if (Get-Module -Name 'PSmm' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm' -Force }
    }
    Context 'Registry clearing' {
        It 'Should clear existing project registry' {
            $Config = @{
                Projects = @{
                    Registry = @{
                        Master = @{ 'Project1' = 'Path1' }
                        Backup = @{ 'Project2' = 'Path2' }
                        LastScanned = Get-Date
                        ProjectDirs = @{ 'Dir1' = 'Path1' }
                    }
                }
            }

            Clear-PSmmProjectRegistry -Config $Config

            $Config.Projects.Registry.Master.Count | Should -Be 0
            $Config.Projects.Registry.Backup.Count | Should -Be 0
            $Config.Projects.Registry.LastScanned | Should -Be ([datetime]::MinValue)
            $Config.Projects.Registry.ProjectDirs.Count | Should -Be 0
        }

        It 'Should handle Config without Registry' {
            $Config = @{
                Projects = @{}
            }

            { Clear-PSmmProjectRegistry -Config $Config } | Should -Not -Throw
        }

        It 'Should output verbose message when registry does not exist' {
            $Config = @{
                Projects = @{}
            }

            $verboseOutput = Clear-PSmmProjectRegistry -Config $Config -Verbose 4>&1

            $verboseOutput | Where-Object { $_ -match 'No project registry to clear' } | Should -Not -BeNullOrEmpty
        }

        It 'Should output verbose messages' {
            $Config = @{
                Projects = @{
                    Registry = @{
                        Master = @{}
                        Backup = @{}
                        LastScanned = Get-Date
                        ProjectDirs = @{}
                    }
                }
            }

            $verboseOutput = Clear-PSmmProjectRegistry -Config $Config -Verbose 4>&1

            $verboseOutput | Should -Not -BeNullOrEmpty
            $verboseOutput | Where-Object { $_ -match 'Clearing project registry cache' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {
        It 'Should accept AppConfiguration parameter' {
            $Config = @{
                Projects = @{
                    Registry = @{
                        Master = @{}
                        Backup = @{}
                        LastScanned = Get-Date
                        ProjectDirs = @{}
                    }
                }
            }

            { Clear-PSmmProjectRegistry -Config $Config } | Should -Not -Throw
        }

        It 'Should not accept null Config' {
            { Clear-PSmmProjectRegistry -Config $null } | Should -Throw
        }
    }

    Context 'Registry structure' {
        It 'Should initialize all registry components' {
            $Config = @{
                Projects = @{
                    Registry = @{
                        Master = @{ 'Existing' = 'Data' }
                        Backup = @{ 'Existing' = 'Data' }
                        LastScanned = Get-Date
                        ProjectDirs = @{ 'Existing' = 'Data' }
                    }
                }
            }

            Clear-PSmmProjectRegistry -Config $Config

            $Config.Projects.Registry.ContainsKey('Master') | Should -BeTrue
            $Config.Projects.Registry.ContainsKey('Backup') | Should -BeTrue
            $Config.Projects.Registry.ContainsKey('LastScanned') | Should -BeTrue
            $Config.Projects.Registry.ContainsKey('ProjectDirs') | Should -BeTrue
        }
    }
}
