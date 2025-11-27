#Requires -Version 7.5.4
Set-StrictMode -Version Latest

$script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
$script:psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
$script:psmmLoggingManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
$script:importClassesScript = Join-Path -Path $repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
$script:testConfigPath = Join-Path -Path $repoRoot -ChildPath 'tests/Support/TestConfig.ps1'

. $testConfigPath
. $importClassesScript -RepositoryRoot $repoRoot

Describe 'Remove-StorageGroup' {
    BeforeAll {

        . $importClassesScript -RepositoryRoot $repoRoot
        Get-Module -Name PSmm, PSmm.Logging -ErrorAction SilentlyContinue | ForEach-Object { Remove-Module -Name $_.Name -Force }
        Import-Module -Name $psmmManifest -Force -ErrorAction Stop
        Import-Module -Name $psmmLoggingManifest -Force -ErrorAction Stop
    }

    It 'removes specified group, writes updated file, and refreshes config' {
        InModuleScope PSmm {
            $driveRoot = Join-Path -Path $TestDrive -ChildPath 'missing-root'
            $storageDir = Join-Path -Path $driveRoot -ChildPath 'PSmm.Config'
            $storagePath = Join-Path -Path $storageDir -ChildPath 'PSmm.Storage.psd1'

            $null = New-Item -Path $storageDir -ItemType Directory -Force

            # Build initial storage hashtable with groups '1' and '2'
            $initial = @{
                '1' = @{ DisplayName = 'G1'; Master = @{ Label = 'M1'; SerialNumber = 'SER-M1' }; Backup = @{} }
                '2' = @{ DisplayName = 'G2'; Master = @{ Label = 'M2'; SerialNumber = 'SER-M2' }; Backup = @{} }
            }
            [AppConfigurationBuilder]::WriteStorageFile($storagePath, $initial)

            $config = [AppConfigurationBuilder]::new()
            $config = $config.WithRootPath($TestDrive)
            $config = $config.WithParameters([RuntimeParameters]::new())
            $config = $config.InitializeDirectories()
            $config = $config.GetConfig()

            Mock Write-PSmmLog {}
            Mock Get-StorageDrive { @([pscustomobject]@{ SerialNumber='SER-M1'; DriveLetter='Z:' }) }
            Mock Confirm-Storage {}

            { Remove-StorageGroup -Config $config -DriveRoot $driveRoot -GroupIds @('2') -Confirm:$false } | Should -Not -Throw

            # Config updated
            $config.Storage.Keys.Count | Should -Be 1
            $config.Storage['1'].Master.Label | Should -Be 'M1'
            $config.Storage['1'].Master.DriveLetter | Should -Be 'Z:'

            # File updated and contains only group '1'
            (Test-Path -Path $storagePath) | Should -BeTrue
            $loaded = [AppConfigurationBuilder]::ReadStorageFile($storagePath)
            $loaded.Keys.Count | Should -Be 1
            $loaded.ContainsKey('1') | Should -BeTrue
            $loaded.ContainsKey('2') | Should -BeFalse

            Should -Invoke Confirm-Storage -Times 1
        }
    }

    It 'skips confirmation when no valid groups are provided' {
        InModuleScope PSmm {
            $driveRoot = Join-Path $TestDrive ''

            $config = [AppConfigurationBuilder]::new()
            $config = $config.WithRootPath($TestDrive)
            $config = $config.WithParameters([RuntimeParameters]::new())
            $config = $config.InitializeDirectories()
            $config = $config.GetConfig()

            Mock Confirm-Storage {}
            Mock Get-StorageDrive { @() }

            { Remove-StorageGroup -Config $config -DriveRoot $driveRoot -GroupIds @('99') -Confirm:$false } | Should -Not -Throw

            Should -Invoke Confirm-Storage -Times 0
            Should -Invoke Get-StorageDrive -Times 0
        }
    }
}
