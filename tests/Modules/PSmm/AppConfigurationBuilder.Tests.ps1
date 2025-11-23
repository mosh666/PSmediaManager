#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'AppConfigurationBuilder' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $importClassesScript = Join-Path -Path $repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
        $psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        . (Join-Path -Path $repoRoot -ChildPath 'tests/Support/TestConfig.ps1')

        & $importClassesScript -RepositoryRoot $repoRoot

        if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) {
            Remove-Module -Name PSmm -Force
        }

        Import-Module -Name $psmmManifest -Force -ErrorAction Stop
    }

    It 'promotes logging level when Debug parameter is set' {
        $rootPath = New-TestRepositoryRoot -RootPath (Join-Path -Path $TestDrive -ChildPath 'builder-debug')

        $parameters = [RuntimeParameters]::new()
        $parameters.Debug = $true

        $builder = [AppConfigurationBuilder]::new()
        $builder.WithRootPath($rootPath) | Out-Null
        $builder.WithParameters($parameters) | Out-Null
        $builder.InitializeDirectories() | Out-Null

        $config = $builder.Build()
        $config.Logging.Level | Should -Be 'DEBUG'
        $config.Logging.DefaultLevel | Should -Be 'DEBUG'
    }

    It 'throws when runtime parameters are missing' {
        $builder = [AppConfigurationBuilder]::new()
        $rootPath = New-TestRepositoryRoot -RootPath (Join-Path -Path $TestDrive -ChildPath 'builder-missing-parameters')
        $builder.WithRootPath($rootPath) | Out-Null

        Should -ActualValue { $builder.Build() } -Throw -ExpectedMessage '*Runtime parameters must be set*'
    }

    It 'loads storage definitions from configuration file' {
        $rootPath = New-TestRepositoryRoot -RootPath (Join-Path -Path $TestDrive -ChildPath 'builder-config')

        $configData = @"
@{
    App = @{
        Storage = @{
            '1' = @{
                Master = @{
                    Label = 'Master-One'
                    DriveLetter = 'X:\'
                    SerialNumber = 'MASTER-001'
                }
                Backup = @{
                    '1' = @{
                        Label = 'Backup-One'
                        DriveLetter = 'Y:\'
                        SerialNumber = 'BACKUP-001'
                    }
                }
            }
        }
    }
}
"@
        $configPath = Join-Path -Path $rootPath -ChildPath 'PSmm.App.psd1'
        Set-Content -Path $configPath -Value $configData -Encoding UTF8

        $builder = [AppConfigurationBuilder]::new()
        $builder.WithRootPath($rootPath) | Out-Null
        $builder.WithParameters([RuntimeParameters]::new()) | Out-Null
        $builder.LoadConfigurationFile($configPath) | Out-Null
        $builder.InitializeDirectories() | Out-Null

        $config = $builder.Build()

        $config.Storage.ContainsKey('1') | Should -BeTrue
        $config.Storage['1'].Master.Label | Should -Be 'Master-One'
        $config.Storage['1'].Master.SerialNumber | Should -Be 'MASTER-001'
        $config.Storage['1'].Backups.ContainsKey('1') | Should -BeTrue
        $config.Storage['1'].Backups['1'].Label | Should -Be 'Backup-One'
    }
}
