#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Confirm-Storage and Test-StorageDevice' -Tag 'unit' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $psmmManifest = Join-Path $repoRoot 'src/Modules/PSmm/PSmm.psd1'
        $psmmLoggingManifest = Join-Path $repoRoot 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        . (Join-Path $repoRoot 'tests/Support/Stub-WritePSmmLog.ps1')
        Enable-TestWritePSmmLogStub
        if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) { Remove-Module -Name PSmm -Force }
        if (Get-Module -Name PSmm.Logging -ErrorAction SilentlyContinue) { Remove-Module -Name PSmm.Logging -Force }
        Import-Module $psmmManifest -Force -ErrorAction Stop
        Import-Module $psmmLoggingManifest -Force -ErrorAction Stop

        # Ensure module-scoped logging calls resolve during tests by mocking inside PSmm module
        Mock Write-PSmmLog { param($Level, $Context, $Message) } -ModuleName PSmm

        # Load classes used by AppConfigurationBuilder
        . (Join-Path $repoRoot 'tests/Preload-PSmmTypes.ps1')
        # Load test helpers for creating configurations
        . (Join-Path $repoRoot 'tests/Support/TestConfig.ps1')
    }

    It 'handles empty backups without error' {
        $cfg = New-TestAppConfiguration
        # Create minimal storage group with empty backups using helpers to respect typed dictionary
        $master = New-TestStorageDrive -Label 'L1' -DriveLetter '' -SerialNumber 'S1'
        $null = Add-TestStorageGroup -Config $cfg -GroupId '1' -Master $master -Backups @{}

        Mock Get-StorageDrive { @() }

        { Confirm-Storage -Config $cfg -Verbose:$false } | Should -Not -Throw
    }

    It 'marks unavailable master as not available and clears letter' {
        $cfg = New-TestAppConfiguration
        $master = New-TestStorageDrive -Label 'L2' -DriveLetter '' -SerialNumber 'S2'
        $group = Add-TestStorageGroup -Config $cfg -GroupId '2' -Master $master -Backups @{}
        # Pre-mark as available with a drive letter to validate clearing behavior
        $group.Master.DriveLetter = 'X:'
        $group.Master.IsAvailable = $true

        Mock Get-StorageDrive { @() }
        Confirm-Storage -Config $cfg -Verbose:$false
        $cfg.Storage['2'].Master.DriveLetter | Should -Be ''
    }
}

Describe 'Get-StorageDrive (inline fallback)' -Tag 'unit' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $psmmManifest = Join-Path $repoRoot 'src/Modules/PSmm/PSmm.psd1'
        if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) { Remove-Module -Name PSmm -Force }
        Import-Module $psmmManifest -Force -ErrorAction Stop
    }

    It 'returns empty when CIM APIs are unavailable' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-CimInstance' } -ModuleName PSmm
        @(Get-StorageDrive).Count | Should -Be 0
    }
}
#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Confirm-Storage' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        $script:psmmLoggingManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        $script:importClassesScript = Join-Path -Path $repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
        $script:testConfigPath = Join-Path -Path $repoRoot -ChildPath 'tests/Support/TestConfig.ps1'

        . $testConfigPath
        $helperFunctions = @(
            'New-TestRepositoryRoot',
            'New-TestAppConfiguration',
            'New-TestStorageDrive',
            'Add-TestStorageGroup'
        )
        foreach ($helper in $helperFunctions) {
            $command = Get-Command -Name $helper -CommandType Function -ErrorAction Stop
            Set-Item -Path "function:\global:$helper" -Value $command.ScriptBlock -Force
        }
        & $importClassesScript -RepositoryRoot $repoRoot

        if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) {
            Remove-Module -Name PSmm -Force
        }
        if (Get-Module -Name PSmm.Logging -ErrorAction SilentlyContinue) {
            Remove-Module -Name PSmm.Logging -Force
        }

        Import-Module -Name $psmmManifest -Force -ErrorAction Stop
        Import-Module -Name $psmmLoggingManifest -Force -ErrorAction Stop
    }

    Context 'Confirm-Storage function' {
        It 'logs a warning when no storage groups are configured' {
            InModuleScope PSmm {
                $config = New-TestAppConfiguration
                $config.Storage.Clear()

                Mock Write-PSmmLog { param($Level, $Context, $Message) } -ModuleName PSmm
                Mock Get-StorageDrive { @() } -ModuleName PSmm

                Confirm-Storage -Config $config

                Should -Invoke Write-PSmmLog -ModuleName PSmm -ParameterFilter {
                    $Level -eq 'WARNING' -and $Message -like 'No storage groups configured*'
                } -Times 1
            }
        }
    }

    Context 'Test-StorageDevice' {
        It 'updates master storage config when the drive is found' {
            $result = InModuleScope PSmm {
                $config = New-TestAppConfiguration
                $masterDrive = New-TestStorageDrive -Label 'Master-One' -DriveLetter '' -SerialNumber 'MASTER-001'
                $group = Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive

                $availableDrives = @(
                    [pscustomobject]@{
                        SerialNumber = 'MASTER-001'
                        DriveLetter = 'Z:'
                        Label = 'Master-One'
                    }
                )

                $errorTracker = @{}

                Mock Write-PSmmLog { param($Level, $Context, $Message) } -ModuleName PSmm

                Test-StorageDevice -StorageConfig $group.Master -AvailableDrives $availableDrives -StorageType 'Master' -StorageGroup '1' -ErrorTracker $errorTracker -Config $config

                Should -Invoke Write-PSmmLog -ModuleName PSmm -ParameterFilter {
                    $Level -eq 'INFO' -and $Message -like '*found at Z:*'
                } -Times 1

                [pscustomobject]@{
                    DriveLetter = $group.Master.DriveLetter
                    IsAvailable = $group.Master.IsAvailable
                }
            }

            $result.DriveLetter | Should -Be 'Z:'
            $result.IsAvailable | Should -BeTrue
        }

        It 'records an error when a required drive is missing' {
            $result = InModuleScope PSmm {
                $config = New-TestAppConfiguration
                $masterDrive = New-TestStorageDrive -Label 'Master-Two' -DriveLetter '' -SerialNumber 'MASTER-002'
                $group = Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive

                $errorTracker = @{}

                Mock Write-PSmmLog { param($Level, $Context, $Message) } -ModuleName PSmm

                Test-StorageDevice -StorageConfig $group.Master -AvailableDrives @() -StorageType 'Master' -StorageGroup '1' -ErrorTracker $errorTracker -Config $config

                [pscustomobject]@{
                    DriveLetter = $group.Master.DriveLetter
                    IsAvailable = $group.Master.IsAvailable
                    ErrorTracker = $errorTracker
                }
            }

            $result.ErrorTracker.ContainsKey('1.Master') | Should -BeTrue
            $result.ErrorTracker['1.Master'] | Should -Match 'Master Disk: Master-Two.*not found'
            $result.DriveLetter | Should -Be ''
            $result.IsAvailable | Should -BeFalse
        }

        It 'treats optional drives as informational when missing' {
            $result = InModuleScope PSmm {
                $storageConfig = @{
                    Label = 'Backup-Optional'
                    SerialNumber = 'BACKUP-999'
                    Optional = $true
                    DriveLetter = ''
                    IsAvailable = $false
                }

                $errorTracker = @{}

                Mock Write-PSmmLog { param($Level, $Context, $Message) } -ModuleName PSmm

                Test-StorageDevice -StorageConfig $storageConfig -AvailableDrives @() -StorageType 'Backup' -StorageGroup '1' -BackupId '1' -ErrorTracker $errorTracker

                Should -Invoke Write-PSmmLog -ModuleName PSmm -ParameterFilter {
                    $Level -eq 'INFO' -and $Message -like '*Optional*'
                } -Times 1

                [pscustomobject]@{
                    ErrorTrackerCount = $errorTracker.Count
                    DriveLetter = $storageConfig.DriveLetter
                    IsAvailable = $storageConfig.IsAvailable
                }
            }

            $result.ErrorTrackerCount | Should -Be 0
            $result.DriveLetter | Should -Be ''
            $result.IsAvailable | Should -BeFalse
        }

        It 'logs warning and skips when SerialNumber is empty' {
            $result = InModuleScope PSmm {
                $storageConfig = @{
                    Label = 'NoSerial'
                    SerialNumber = ''
                    DriveLetter = ''
                    IsAvailable = $false
                }

                $errorTracker = @{}

                Mock Write-PSmmLog { param($Level, $Context, $Message) } -ModuleName PSmm

                Test-StorageDevice -StorageConfig $storageConfig -AvailableDrives @() -StorageType 'Master' -StorageGroup '1' -ErrorTracker $errorTracker

                Should -Invoke Write-PSmmLog -ModuleName PSmm -ParameterFilter {
                    $Level -eq 'WARNING' -and $Message -like '*has no serial number configured*'
                } -Times 1

                [pscustomobject]@{
                    ErrorTrackerCount = $errorTracker.Count
                    DriveLetter = $storageConfig.DriveLetter
                    IsAvailable = $storageConfig.IsAvailable
                }
            }

            $result.ErrorTrackerCount | Should -Be 0
            $result.DriveLetter | Should -Be ''
            $result.IsAvailable | Should -BeFalse
        }

        It 'updates backup storage config when the drive is found' {
            $result = InModuleScope PSmm {
                $config = New-TestAppConfiguration
            $dummyMaster = New-TestStorageDrive -Label 'Master-Temp' -DriveLetter '' -SerialNumber 'MASTER-TMP'
                $backupDrive = New-TestStorageDrive -Label 'Backup-Two' -DriveLetter '' -SerialNumber 'BACK-002'
            $group = Add-TestStorageGroup -Config $config -GroupId '3' -Master $dummyMaster -Backups @{ '2' = $backupDrive }

                $availableDrives = @(
                    [pscustomobject]@{
                        SerialNumber = 'BACK-002'
                        DriveLetter = 'Y:'
                        Label = 'Backup-Two'
                    }
                )

                $errorTracker = @{}

                Mock Write-PSmmLog { param($Level, $Context, $Message) } -ModuleName PSmm

                Test-StorageDevice -StorageConfig $group.Backups['2'] -AvailableDrives $availableDrives -StorageType 'Backup' -StorageGroup '3' -BackupId '2' -ErrorTracker $errorTracker -Config $config

                Should -Invoke Write-PSmmLog -ModuleName PSmm -ParameterFilter {
                    $Level -eq 'INFO' -and $Message -like '*Backup*found at Y:*'
                } -Times 1

                [pscustomobject]@{
                    DriveLetter = $group.Backups['2'].DriveLetter
                    IsAvailable = $group.Backups['2'].IsAvailable
                }
            }

            $result.DriveLetter | Should -Be 'Y:'
            $result.IsAvailable | Should -BeTrue
        }
    }
}
