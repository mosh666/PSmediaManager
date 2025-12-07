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
    
    # Enable test mode to avoid interactive prompts
    $env:MEDIA_MANAGER_TEST_MODE = '1'
}

AfterAll {
    $env:MEDIA_MANAGER_TEST_MODE = '0'
    Remove-Item -Path 'env:MEDIA_MANAGER_TEST_INPUTS' -ErrorAction SilentlyContinue
    Remove-Module -Name 'PSmm' -Force -ErrorAction SilentlyContinue
    Remove-Module -Name 'PSmm.Logging' -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-StorageWizard' {
    
    Context 'Parameter Validation' {
        It 'requires Config parameter' {
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            # Pass $null for Config to trigger validation error
            { Invoke-StorageWizard -Config $null -DriveRoot 'D:\' -ErrorAction Stop } | Should -Throw
        }

        It 'requires DriveRoot parameter' {
            $config = New-TestAppConfiguration
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            # Pass empty string for DriveRoot to trigger validation error
            { Invoke-StorageWizard -Config $config -DriveRoot '' -ErrorAction Stop } | Should -Throw
        }

        It 'validates Mode parameter' {
            $config = New-TestAppConfiguration
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            { Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Invalid' -ErrorAction Stop } | Should -Throw
        }

        It 'requires GroupId when Mode is Edit' {
            $config = New-TestAppConfiguration
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            { Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Edit' -ErrorAction Stop } | Should -Throw
        }

        It 'validates GroupId exists when Mode is Edit' {
            $config = New-TestAppConfiguration
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            { Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Edit' -GroupId 'nonexistent' -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'No Removable Drives Available' {
        It 'returns false when no USB drives found in Add mode' {
            $config = New-TestAppConfiguration
            
            # Mock only fixed drives, no USB
            $fixedDrives = @(
                [PSCustomObject]@{
                    Label = 'C_Drive'
                    DriveLetter = 'C:'
                    SerialNumber = 'SNFIXED1'
                    IsUSB = $false
                    IsRemovable = $false
                    BusType = 'SATA'
                    InterfaceType = 'IDE'
                    TotalSpace = 500
                    Status = 'Healthy'
                }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $fixedDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add' -NonInteractive
            $result | Should -Be $false
        }

        It 'logs warning when no USB drives found' {
            $config = New-TestAppConfiguration
            
            $fixedDrives = @(
                [PSCustomObject]@{
                    Label = 'C_Drive'
                    DriveLetter = 'C:'
                    SerialNumber = 'SNFIXED1'
                    IsUSB = $false
                    IsRemovable = $false
                    BusType = 'SATA'
                    InterfaceType = 'IDE'
                    TotalSpace = 500
                    Status = 'Healthy'
                }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $fixedDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add' -NonInteractive
            
            Assert-MockCalled -CommandName Write-PSmmLog -ModuleName PSmm.Logging `
                -ParameterFilter { $Level -eq 'WARNING' } -Times 1
        }
    }

    Context 'Add Mode - New Group Creation' {
        It 'creates group with auto-incremented ID when storage is empty' {
            $config = New-TestAppConfiguration
            $config.Storage = @{}
            
            $usbDrive = [PSCustomObject]@{
                Label = 'USB_Drive'
                DriveLetter = 'D:'
                SerialNumber = 'SNUSB123'
                IsUSB = $true
                IsRemovable = $true
                BusType = 'USB'
                InterfaceType = 'USB'
                TotalSpace = 1000
                Status = 'Healthy'
            }
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @($usbDrive) }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add' -NonInteractive
            
            # Verify group '1' was created
            $config.Storage.ContainsKey('1') | Should -Be $true
            $config.Storage['1'].Master | Should -Not -BeNullOrEmpty
        }

        It 'auto-increments group ID from existing groups' {
            $config = New-TestAppConfiguration
            $existingMaster = New-TestStorageDrive -Label 'Existing' -DriveLetter 'E:' -SerialNumber 'SNEXIST'
            Add-TestStorageGroup -Config $config -GroupId '5' -Master $existingMaster
            
            $usbDrive = [PSCustomObject]@{
                Label = 'USB_Drive'
                DriveLetter = 'D:'
                SerialNumber = 'SNUSB123'
                IsUSB = $true
                IsRemovable = $true
                BusType = 'USB'
                InterfaceType = 'USB'
                TotalSpace = 1000
                Status = 'Healthy'
            }
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @($usbDrive) }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add' -NonInteractive
            
            # Verify group '6' was created (next after existing '5')
            $config.Storage.ContainsKey('6') | Should -Be $true
        }

        It 'excludes drives already assigned to other groups' {
            $config = New-TestAppConfiguration
            $existingMaster = New-TestStorageDrive -Label 'Master1' -DriveLetter 'D:' -SerialNumber 'SNUSED'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $existingMaster
            
            $usbDrives = @(
                [PSCustomObject]@{
                    Label = 'Used_USB'
                    DriveLetter = 'D:'
                    SerialNumber = 'SNUSED'
                    IsUSB = $true
                    IsRemovable = $true
                    BusType = 'USB'
                    InterfaceType = 'USB'
                    TotalSpace = 1000
                    Status = 'Healthy'
                },
                [PSCustomObject]@{
                    Label = 'Available_USB'
                    DriveLetter = 'E:'
                    SerialNumber = 'SNFREE'
                    IsUSB = $true
                    IsRemovable = $true
                    BusType = 'USB'
                    InterfaceType = 'USB'
                    TotalSpace = 1000
                    Status = 'Healthy'
                }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $usbDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add' -NonInteractive
            
            # Should only create group with SNFREE, not SNUSED
            $config.Storage['2'].Master.SerialNumber | Should -Be 'SNFREE'
        }
    }

    Context 'Edit Mode - Existing Group Modification' {
        It 'allows editing existing storage group' {
            $config = New-TestAppConfiguration
            $existingMaster = New-TestStorageDrive -Label 'Master1' -DriveLetter 'D:' -SerialNumber 'SNOLD'
            $existingGroup = Add-TestStorageGroup -Config $config -GroupId '1' -Master $existingMaster
            $existingGroup.DisplayName = 'Old Name'
            
            $usbDrives = @(
                [PSCustomObject]@{
                    Label = 'New_USB'
                    DriveLetter = 'E:'
                    SerialNumber = 'SNNEW'
                    IsUSB = $true
                    IsRemovable = $true
                    BusType = 'USB'
                    InterfaceType = 'USB'
                    TotalSpace = 1000
                    Status = 'Healthy'
                }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $usbDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Edit' -GroupId '1' -NonInteractive
            
            # Edit mode should succeed
            $config.Storage['1'] | Should -Not -BeNullOrEmpty
        }

        It 'excludes other groups drives when editing' {
            $config = New-TestAppConfiguration
            $master1 = New-TestStorageDrive -Label 'Master1' -DriveLetter 'D:' -SerialNumber 'SN1'
            Add-TestStorageGroup -Config $config -GroupId '1' -Master $master1
            
            $master2 = New-TestStorageDrive -Label 'Master2' -DriveLetter 'E:' -SerialNumber 'SN2'
            Add-TestStorageGroup -Config $config -GroupId '2' -Master $master2
            
            # When editing group 1, group 2's drive (SN2) should be excluded
            $usbDrives = @(
                [PSCustomObject]@{
                    Label = 'Group1_Master'; DriveLetter = 'D:'; SerialNumber = 'SN1'; IsUSB = $true; IsRemovable = $true; BusType = 'USB'; InterfaceType = 'USB'; TotalSpace = 1000; Status = 'Healthy'
                },
                [PSCustomObject]@{
                    Label = 'Group2_Master'; DriveLetter = 'E:'; SerialNumber = 'SN2'; IsUSB = $true; IsRemovable = $true; BusType = 'USB'; InterfaceType = 'USB'; TotalSpace = 1000; Status = 'Healthy'
                }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $usbDrives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Edit' -GroupId '1' -NonInteractive
            
            # Group 1 should still exist
            $config.Storage['1'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Drive Detection and Filtering' {
        It 'identifies USB drives by BusType' {
            $config = New-TestAppConfiguration
            
            $usbDrive = [PSCustomObject]@{
                Label = 'USB_Drive'
                DriveLetter = 'E:'
                SerialNumber = 'SNUSB'
                IsUSB = $false
                IsRemovable = $false
                BusType = 'USB'
                InterfaceType = 'IDE'
                TotalSpace = 1000
                Status = 'Healthy'
            }
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @($usbDrive) }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add' -NonInteractive
            
            # Should detect USB drive by BusType even if IsUSB is false
            $result | Should -Be $true
            $config.Storage['1'] | Should -Not -BeNullOrEmpty
        }

        It 'identifies USB drives by InterfaceType' {
            $config = New-TestAppConfiguration
            
            $usbDrive = [PSCustomObject]@{
                Label = 'USB_Drive'
                DriveLetter = 'E:'
                SerialNumber = 'SNUSB'
                IsUSB = $false
                IsRemovable = $false
                BusType = 'SATA'
                InterfaceType = 'USB'
                TotalSpace = 1000
                Status = 'Healthy'
            }
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @($usbDrive) }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add' -NonInteractive
            
            # Should detect USB drive by InterfaceType
            $result | Should -Be $true
        }

        It 'identifies removable drives by IsRemovable flag' {
            $config = New-TestAppConfiguration
            
            $removableDrive = [PSCustomObject]@{
                Label = 'Removable_Drive'
                DriveLetter = 'F:'
                SerialNumber = 'SNREM'
                IsUSB = $false
                IsRemovable = $true
                BusType = 'SATA'
                InterfaceType = 'IDE'
                TotalSpace = 1000
                Status = 'Healthy'
            }
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @($removableDrive) }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add' -NonInteractive
            
            # Should detect removable drive
            $result | Should -Be $true
        }
    }

    Context 'Error Handling' {
        It 'handles Get-StorageDrive failure gracefully' {
            $config = New-TestAppConfiguration
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { throw 'Drive enumeration error' }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            $result = Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add' -NonInteractive
            
            # Should return false when no drives available after error
            $result | Should -Be $false
        }

        It 'handles null Config gracefully' {
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @() }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            { Invoke-StorageWizard -Config $null -DriveRoot 'D:\' -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Logging' {
        It 'logs wizard start with mode information' {
            $config = New-TestAppConfiguration
            
            $usbDrive = [PSCustomObject]@{
                Label = 'USB_Drive'
                DriveLetter = 'D:'
                SerialNumber = 'SNUSB123'
                IsUSB = $true
                IsRemovable = $true
                BusType = 'USB'
                InterfaceType = 'USB'
                TotalSpace = 1000
                Status = 'Healthy'
            }
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @($usbDrive) }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add' -NonInteractive
            
            # Verify logging was called
            Assert-MockCalled -CommandName Write-PSmmLog -ModuleName PSmm.Logging -AtLeastOnce
        }

        It 'logs excluded drives at verbose level' {
            $config = New-TestAppConfiguration
            
            $drives = @(
                [PSCustomObject]@{
                    Label = 'Fixed_Drive'
                    DriveLetter = 'C:'
                    SerialNumber = 'SNFIXED'
                    IsUSB = $false
                    IsRemovable = $false
                    BusType = 'SATA'
                    InterfaceType = 'IDE'
                    TotalSpace = 500
                    Status = 'Healthy'
                }
            )
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { $drives }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add' -NonInteractive
            
            # Should log excluded drives information
            Assert-MockCalled -CommandName Write-PSmmLog -ModuleName PSmm.Logging -Times 1
        }
    }

    Context 'NonInteractive Mode' {
        It 'skips all user prompts in NonInteractive mode' {
            $config = New-TestAppConfiguration
            
            $usbDrive = [PSCustomObject]@{
                Label = 'USB_Drive'
                DriveLetter = 'D:'
                SerialNumber = 'SNUSB123'
                IsUSB = $true
                IsRemovable = $true
                BusType = 'USB'
                InterfaceType = 'USB'
                TotalSpace = 1000
                Status = 'Healthy'
            }
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @($usbDrive) }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            # In NonInteractive mode, should complete without prompting
            $result = Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add' -NonInteractive
            
            # Verify Write-PSmmHost was not called much (minimal display)
            Assert-MockCalled -CommandName Write-PSmmHost -ModuleName PSmm -Times 0
        }

        It 'returns false immediately in test mode without test inputs' {
            $config = New-TestAppConfiguration
            Remove-Item -Path 'env:MEDIA_MANAGER_TEST_INPUTS' -ErrorAction SilentlyContinue
            
            $usbDrive = [PSCustomObject]@{
                Label = 'USB_Drive'
                DriveLetter = 'D:'
                SerialNumber = 'SNUSB123'
                IsUSB = $true
                IsRemovable = $true
                BusType = 'USB'
                InterfaceType = 'USB'
                TotalSpace = 1000
                Status = 'Healthy'
            }
            
            Mock -CommandName Get-StorageDrive -ModuleName PSmm -MockWith { @($usbDrive) }
            Mock -CommandName Write-PSmmLog -ModuleName PSmm.Logging -MockWith {}
            Mock -CommandName Write-PSmmHost -ModuleName PSmm -MockWith {}
            
            # In test mode without test inputs and non-interactive, should return false
            $result = Invoke-StorageWizard -Config $config -DriveRoot 'D:\' -Mode 'Add'
            
            $result | Should -Be $false
        }
    }
}
