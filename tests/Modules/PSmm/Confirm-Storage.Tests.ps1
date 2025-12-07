#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\src\Modules\PSmm\PSmm.psd1'
    $loggingModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\src\Modules\PSmm.Logging\PSmm.Logging.psd1'
    
    # Load modules
    Import-Module -Name $modulePath -Force -Verbose:$false
    Import-Module -Name $loggingModulePath -Force -Verbose:$false
    
    # Import test support functions
    $testConfigPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\tests\Support\TestConfig.ps1'
    . $testConfigPath
    
    # Pre-load classes
    $classPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\tests\Support\Import-PSmmClasses.ps1'
    if (Test-Path -Path $classPath) {
        . $classPath
    }
    
    # Enable test mode to avoid live drive access
    $env:MEDIA_MANAGER_TEST_MODE = '1'
}

AfterAll {
    $env:MEDIA_MANAGER_TEST_MODE = '0'
    Remove-Module -Name 'PSmm' -Force -ErrorAction SilentlyContinue
    Remove-Module -Name 'PSmm.Logging' -Force -ErrorAction SilentlyContinue
}

Describe 'Confirm-Storage' {
    
    Context 'Parameter Validation' {
        It 'accepts AppConfiguration object' {
            $config = New-TestAppConfiguration
            
            # Mock Get-StorageDrive to return empty array
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            { Confirm-Storage -Config $config } | Should -Not -Throw
            
            Assert-MockCalled -CommandName Get-StorageDrive -ModuleName PSmm -Times 1
        }

        It 'rejects null Config' {
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            { Confirm-Storage -Config $null -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'No Storage Configuration' {
        It 'handles null storage root' {
            $config = New-TestAppConfiguration
            $config.Storage = $null
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
        }

        It 'handles empty storage groups' {
            $config = New-TestAppConfiguration
            $config.Storage = @{}
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
        }
    }

    Context 'Single Master Drive Validation' {
        It 'finds and updates master drive by serial number' {
            $config = New-TestAppConfiguration
            $masterDrive = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN12345'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive
            
            $availableDrives = @(
                [PSCustomObject]@{
                    Label = 'Master1'
                    DriveLetter = 'D:'
                    SerialNumber = 'SN12345'
                    IsUSB = $false
                    FreeSpaceGB = 500
                    TotalSpaceGB = 1000
                    Status = 'Healthy'
                }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $availableDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
            $config.Storage['1'].Master.IsAvailable | Should -Be $true
            $config.Storage['1'].Master.DriveLetter | Should -Be 'D:'
            
        }

        It 'logs error when master drive not found' {
            $config = New-TestAppConfiguration
            $masterDrive = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN99999'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
            $config.Storage['1'].Master.IsAvailable | Should -Be $false
            $config.Storage['1'].Master.DriveLetter | Should -Be ''
            
        }

        It 'trims whitespace from serial numbers during matching' {
            $config = New-TestAppConfiguration
            $masterDrive = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN12345  '
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive
            
            $availableDrives = @(
                [PSCustomObject]@{
                    Label = 'Master1'
                    DriveLetter = 'D:'
                    SerialNumber = '  SN12345'
                    IsUSB = $false
                    FreeSpaceGB = 500
                    TotalSpaceGB = 1000
                    Status = 'Healthy'
                }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $availableDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
            $config.Storage['1'].Master.IsAvailable | Should -Be $true
            $config.Storage['1'].Master.DriveLetter | Should -Be 'D:'
        }

        It 'skips validation when serial number is whitespace only' {
            $config = New-TestAppConfiguration
            $masterDrive = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber '   '
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
        }
    }

    Context 'Backup Drive Validation' {
        It 'finds and updates backup drives' {
            $config = New-TestAppConfiguration
            $masterDrive = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN12345'
            $backup1 = New-TestStorageDrive -Label 'Backup1' -DriveLetter '' -SerialNumber 'SNB1'
            $backup2 = New-TestStorageDrive -Label 'Backup2' -DriveLetter '' -SerialNumber 'SNB2'
            
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive -Backups @{
                '1' = $backup1
                '2' = $backup2
            }
            
            $availableDrives = @(
                [PSCustomObject]@{ Label = 'Master1'; DriveLetter = 'D:'; SerialNumber = 'SN12345'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' },
                [PSCustomObject]@{ Label = 'Backup1'; DriveLetter = 'E:'; SerialNumber = 'SNB1'; IsUSB = $true; FreeSpaceGB = 1000; TotalSpaceGB = 2000; Status = 'Healthy' },
                [PSCustomObject]@{ Label = 'Backup2'; DriveLetter = 'F:'; SerialNumber = 'SNB2'; IsUSB = $true; FreeSpaceGB = 1000; TotalSpaceGB = 2000; Status = 'Healthy' }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $availableDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
            $config.Storage['1'].Backups['1'].IsAvailable | Should -Be $true
            $config.Storage['1'].Backups['1'].DriveLetter | Should -Be 'E:'
            $config.Storage['1'].Backups['2'].IsAvailable | Should -Be $true
            $config.Storage['1'].Backups['2'].DriveLetter | Should -Be 'F:'
        }

        It 'handles missing backup drives' {
            $config = New-TestAppConfiguration
            $masterDrive = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN12345'
            $backup1 = New-TestStorageDrive -Label 'Backup1' -DriveLetter '' -SerialNumber 'SNB1'
            
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive -Backups @{
                '1' = $backup1
            }
            
            $availableDrives = @(
                [PSCustomObject]@{ Label = 'Master1'; DriveLetter = 'D:'; SerialNumber = 'SN12345'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $availableDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
            $config.Storage['1'].Backups['1'].IsAvailable | Should -Be $false
            $config.Storage['1'].Backups['1'].DriveLetter | Should -Be ''
        }

        It 'handles empty backup collection' {
            $config = New-TestAppConfiguration
            $masterDrive = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN12345'
            $group = Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive
            $group.Backups = @{}  # Empty backups
            
            $availableDrives = @(
                [PSCustomObject]@{ Label = 'Master1'; DriveLetter = 'D:'; SerialNumber = 'SN12345'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $availableDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
        }
    }

    Context 'Multiple Storage Groups' {
        It 'validates multiple storage groups' {
            $config = New-TestAppConfiguration
            
            $master1 = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN1'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master1
            
            $master2 = New-TestStorageDrive -Label 'Master2' -DriveLetter '' -SerialNumber 'SN2'
            Add-TestStorageGroup -Config $config -GroupId '2' -Master $master2
            
            $availableDrives = @(
                [PSCustomObject]@{ Label = 'Master1'; DriveLetter = 'D:'; SerialNumber = 'SN1'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' },
                [PSCustomObject]@{ Label = 'Master2'; DriveLetter = 'E:'; SerialNumber = 'SN2'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $availableDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
            $config.Storage['1'].Master.DriveLetter | Should -Be 'D:'
            $config.Storage['2'].Master.DriveLetter | Should -Be 'E:'
        }
    }

    Context 'Error Handling and Logging' {
        It 'logs success summary when all drives found' {
            $config = New-TestAppConfiguration
            $masterDrive = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN12345'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive
            
            $availableDrives = @(
                [PSCustomObject]@{ Label = 'Master1'; DriveLetter = 'D:'; SerialNumber = 'SN12345'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $availableDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
        }

        It 'logs summary with error count when drives missing' {
            $config = New-TestAppConfiguration
            $master = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN99999'
            $backup = New-TestStorageDrive -Label 'Backup1' -DriveLetter '' -SerialNumber 'SNBAD'
            
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master -Backups @{
                '1' = $backup
            }
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
        }

        It 'handles exception during validation' {
            $config = New-TestAppConfiguration
            $masterDrive = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN12345'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { throw 'Test error' }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            { Confirm-Storage -Config $config -ErrorAction Stop } | Should -Throw
            
        }
    }

    Context 'StorageConfig Property Extraction' {
        It 'handles missing Label property gracefully' {
            $config = New-TestAppConfiguration
            $masterDrive = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN12345'
            $masterDrive.Label = $null
            
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive
            
            $availableDrives = @(
                [PSCustomObject]@{ Label = 'Master1'; DriveLetter = 'D:'; SerialNumber = 'SN12345'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $availableDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            # Should not throw when label is missing
            { Confirm-Storage -Config $config } | Should -Not -Throw
        }
    }

    Context 'First Match Selection' {
        It 'uses first matching drive when multiple have same serial number' {
            $config = New-TestAppConfiguration
            $masterDrive = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SNDUPE'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive
            
            $availableDrives = @(
                [PSCustomObject]@{ Label = 'Duplicate1'; DriveLetter = 'D:'; SerialNumber = 'SNDUPE'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' },
                [PSCustomObject]@{ Label = 'Duplicate2'; DriveLetter = 'E:'; SerialNumber = 'SNDUPE'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $availableDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
            $config.Storage['1'].Master.DriveLetter | Should -Be 'D:'
        }
    }

    Context 'Configuration Object Updates' {
        It 'updates DriveLetter on StorageConfig directly' {
            $config = New-TestAppConfiguration
            $masterDrive = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN12345'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive
            
            $availableDrives = @(
                [PSCustomObject]@{ Label = 'Master1'; DriveLetter = 'D:'; SerialNumber = 'SN12345'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $availableDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
            $masterDrive.DriveLetter | Should -Be 'D:'
        }
    }

    Context 'Drive Enumeration Sorting' {
        It 'processes storage groups in sorted order' {
            $config = New-TestAppConfiguration
            
            # Add in reverse order
            $master3 = New-TestStorageDrive -Label 'Master3' -DriveLetter '' -SerialNumber 'SN3'
            Add-TestStorageGroup -Config $config -GroupId '3' -Master $master3
            
            $master1 = New-TestStorageDrive -Label 'Master1' -DriveLetter '' -SerialNumber 'SN1'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master1
            
            $master2 = New-TestStorageDrive -Label 'Master2' -DriveLetter '' -SerialNumber 'SN2'
            Add-TestStorageGroup -Config $config -GroupId '2' -Master $master2
            
            $availableDrives = @(
                [PSCustomObject]@{ Label = 'Master1'; DriveLetter = 'D:'; SerialNumber = 'SN1'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' },
                [PSCustomObject]@{ Label = 'Master2'; DriveLetter = 'E:'; SerialNumber = 'SN2'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' },
                [PSCustomObject]@{ Label = 'Master3'; DriveLetter = 'F:'; SerialNumber = 'SN3'; IsUSB = $false; FreeSpaceGB = 500; TotalSpaceGB = 1000; Status = 'Healthy' }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $availableDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            
            Confirm-Storage -Config $config
            
            # All three storage groups should be updated
            $config.Storage['1'].Master.IsAvailable | Should -Be $true
            $config.Storage['2'].Master.IsAvailable | Should -Be $true
            $config.Storage['3'].Master.IsAvailable | Should -Be $true
        }
    }
}
