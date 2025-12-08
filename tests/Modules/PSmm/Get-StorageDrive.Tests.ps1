#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Get-StorageDrive' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        $script:loggingManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        $script:testConfigPath = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/TestConfig.ps1'

        . $script:testConfigPath

        $importClassesScript = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
        & $importClassesScript -RepositoryRoot $script:repoRoot

        foreach ($module in 'PSmm', 'PSmm.Logging') {
            if (Get-Module -Name $module -ErrorAction SilentlyContinue) {
                Remove-Module -Name $module -Force
            }
        }

        Import-Module -Name $script:loggingManifest -Force -ErrorAction Stop
        Import-Module -Name $script:psmmManifest -Force -ErrorAction Stop

        Mock Write-PSmmLog {} -ModuleName PSmm

        $env:MEDIA_MANAGER_TEST_FORCE_INLINE_STORAGE = '1'
    }

    AfterAll {
        Get-Module -Name PSmm, PSmm.Logging -ErrorAction SilentlyContinue | Remove-Module -Force
        if (Test-Path env:MEDIA_MANAGER_TEST_FORCE_INLINE_STORAGE) {
            Remove-Item env:MEDIA_MANAGER_TEST_FORCE_INLINE_STORAGE
        }
    }

    AfterEach {
        InModuleScope PSmm {
            if (Get-Variable -Name PSmmTestDriveData -Scope Script -ErrorAction SilentlyContinue) {
                Remove-Variable -Name PSmmTestDriveData -Scope Script -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Parameter Validation' {
        It 'accepts no parameters' {
            { Get-StorageDrive } | Should -Not -Throw

            $result = Get-StorageDrive
            ($result -is [PSCustomObject]) -or ($result -is [object[]]) -or ($null -eq $result) | Should -BeTrue
        }
    }

    Context 'CIM API Availability' {
        It 'returns empty array when Get-CimInstance is unavailable' {
            InModuleScope PSmm {
                Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-CimInstance' } -ModuleName PSmm

                $result = Get-StorageDrive

                $result | Should -BeNullOrEmpty
            }
        }

        It 'returns empty array when CIM operations fail' {
            InModuleScope PSmm {
                Mock Get-CimInstance { throw 'CIM unavailable' } -ModuleName PSmm

                $result = Get-StorageDrive

                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Drive Enumeration' {
        It 'returns drives with expected properties' {
            InModuleScope PSmm {
                $fakeDisk = [pscustomobject]@{
                    Index = 0
                    Caption = 'PhysicalDrive0'
                    SerialNumber = 'TEST-SERIAL-123'
                    Model = 'TestDrive 1TB'
                    Manufacturer = 'TestMfg'
                    InterfaceType = 'SATA'
                }
                $fakePartition = [pscustomobject]@{ Index = 0 }
                $fakeLogicalDisk = [pscustomobject]@{
                    DeviceID = 'C:'
                    DriveType = 3
                    Size = 1099511627776
                    FreeSpace = 549755813888
                }
                $fakeDiskMetadata = [pscustomobject]@{
                    Number = 0
                    BusType = 'SATA'
                    SerialNumber = 'TEST-SERIAL-123'
                    Model = 'TestDrive 1TB'
                    Manufacturer = 'TestMfg'
                    PartitionStyle = 'GPT'
                }
                $fakeVolume = [pscustomobject]@{
                    DriveLetter = 'C'
                    FileSystemLabel = 'TestVolume'
                    FileSystem = 'NTFS'
                    HealthStatus = 'Healthy'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($fakeDisk)
                    DiskMetadata = @{ 0 = $fakeDiskMetadata }
                    Partitions   = @{ 0 = @($fakePartition) }
                    LogicalDisks = @{ 0 = @($fakeLogicalDisk) }
                    Volumes      = @{ 'C' = $fakeVolume }
                }

                $result = Get-StorageDrive

                $result | Should -Not -BeNullOrEmpty
                $result[0].Label | Should -Be 'TestVolume'
                $result[0].DriveLetter | Should -Be 'C:'
                $result[0].SerialNumber | Should -Be 'TEST-SERIAL-123'
                $result[0].FileSystem | Should -Be 'NTFS'
                $result[0].IsRemovable | Should -Be $false
                $result[0].TotalSpace | Should -Be 1024
                $result[0].FreeSpace | Should -Be 512
                $result[0].UsedSpace | Should -Be 512
            }
        }

        It 'calculates used space correctly' {
            InModuleScope PSmm {
                $fakeDisk = [pscustomobject]@{
                    Index = 0
                    Caption = 'PhysicalDrive0'
                    SerialNumber = 'TEST-123'
                    Model = 'Test'
                    Manufacturer = 'Test'
                    InterfaceType = 'SATA'
                }
                $fakePartition = [pscustomobject]@{ Index = 0 }
                $fakeLogicalDisk = [pscustomobject]@{
                    DeviceID = 'D:'
                    DriveType = 3
                    Size = 2199023255552
                    FreeSpace = 1099511627776
                }
                $fakeDiskMetadata = [pscustomobject]@{
                    Number = 0
                    BusType = 'SATA'
                    SerialNumber = 'TEST-123'
                    Model = 'Test'
                    Manufacturer = 'Test'
                    PartitionStyle = 'MBR'
                }
                $fakeVolume = [pscustomobject]@{
                    DriveLetter = 'D'
                    FileSystemLabel = 'Data'
                    FileSystem = 'NTFS'
                    HealthStatus = 'Healthy'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($fakeDisk)
                    DiskMetadata = @{ 0 = $fakeDiskMetadata }
                    Partitions   = @{ 0 = @($fakePartition) }
                    LogicalDisks = @{ 0 = @($fakeLogicalDisk) }
                    Volumes      = @{ 'D' = $fakeVolume }
                }

                $result = Get-StorageDrive

                $result[0].TotalSpace | Should -Be 2048
                $result[0].FreeSpace | Should -Be 1024
                $result[0].UsedSpace | Should -Be 1024
            }
        }
    }

    Context 'USB/Removable Drive Detection' {
        It 'marks USB drives as removable via BusType' {
            InModuleScope PSmm {
                $fakeDisk = [pscustomobject]@{
                    Index = 1
                    Caption = 'PhysicalDrive1'
                    SerialNumber = 'USB-123'
                    Model = 'USB Drive'
                    Manufacturer = 'Generic'
                    InterfaceType = 'SATA'
                }
                $fakePartition = [pscustomobject]@{ Index = 0 }
                $fakeLogicalDisk = [pscustomobject]@{
                    DeviceID = 'E:'
                    DriveType = 2
                    Size = 16106127360
                    FreeSpace = 16106127360
                }
                $fakeDiskMetadata = [pscustomobject]@{
                    Number = 1
                    BusType = 'USB'
                    SerialNumber = 'USB-123'
                    Model = 'USB Drive'
                    Manufacturer = 'Generic'
                    PartitionStyle = 'MBR'
                }
                $fakeVolume = [pscustomobject]@{
                    DriveLetter = 'E'
                    FileSystemLabel = 'USBDrive'
                    FileSystem = 'FAT32'
                    HealthStatus = 'Healthy'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($fakeDisk)
                    DiskMetadata = @{ 1 = $fakeDiskMetadata }
                    Partitions   = @{ 1 = @($fakePartition) }
                    LogicalDisks = @{ 0 = @($fakeLogicalDisk) }
                    Volumes      = @{ 'E' = $fakeVolume }
                }

                $result = Get-StorageDrive

                $result[0].IsRemovable | Should -Be $true
                $result[0].BusType | Should -Be 'USB'
            }
        }

        It 'marks USB drives as removable via InterfaceType' {
            InModuleScope PSmm {
                $fakeDisk = [pscustomobject]@{
                    Index = 2
                    Caption = 'PhysicalDrive2'
                    SerialNumber = 'USB-456'
                    Model = 'USB Device'
                    Manufacturer = 'TestMfg'
                    InterfaceType = 'USB'
                }
                $fakePartition = [pscustomobject]@{ Index = 0 }
                $fakeLogicalDisk = [pscustomobject]@{
                    DeviceID = 'F:'
                    DriveType = 3
                    Size = 8589934592
                    FreeSpace = 4294967296
                }
                $fakeDiskMetadata = [pscustomobject]@{
                    Number = 2
                    BusType = 'SATA'
                    SerialNumber = 'USB-456'
                    Model = 'USB Device'
                    Manufacturer = 'TestMfg'
                    PartitionStyle = 'MBR'
                }
                $fakeVolume = [pscustomobject]@{
                    DriveLetter = 'F'
                    FileSystemLabel = 'USB'
                    FileSystem = 'exFAT'
                    HealthStatus = 'Healthy'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($fakeDisk)
                    DiskMetadata = @{ 2 = $fakeDiskMetadata }
                    Partitions   = @{ 2 = @($fakePartition) }
                    LogicalDisks = @{ 0 = @($fakeLogicalDisk) }
                    Volumes      = @{ 'F' = $fakeVolume }
                }

                $result = Get-StorageDrive

                $result[0].IsRemovable | Should -Be $true
                $result[0].InterfaceType | Should -Be 'USB'
            }
        }

        It 'marks removable drive type as removable' {
            InModuleScope PSmm {
                $fakeDisk = [pscustomobject]@{
                    Index = 3
                    Caption = 'PhysicalDrive3'
                    SerialNumber = 'REM-789'
                    Model = 'Removable'
                    Manufacturer = 'Test'
                    InterfaceType = 'SATA'
                }
                $fakePartition = [pscustomobject]@{ Index = 0 }
                $fakeLogicalDisk = [pscustomobject]@{
                    DeviceID = 'G:'
                    DriveType = 2
                    Size = 1073741824
                    FreeSpace = 536870912
                }
                $fakeDiskMetadata = [pscustomobject]@{
                    Number = 3
                    BusType = 'SATA'
                    SerialNumber = 'REM-789'
                    Model = 'Removable'
                    Manufacturer = 'Test'
                    PartitionStyle = 'MBR'
                }
                $fakeVolume = [pscustomobject]@{
                    DriveLetter = 'G'
                    FileSystemLabel = 'RemovableDrive'
                    FileSystem = 'FAT32'
                    HealthStatus = 'Healthy'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($fakeDisk)
                    DiskMetadata = @{ 3 = $fakeDiskMetadata }
                    Partitions   = @{ 3 = @($fakePartition) }
                    LogicalDisks = @{ 0 = @($fakeLogicalDisk) }
                    Volumes      = @{ 'G' = $fakeVolume }
                }

                $result = Get-StorageDrive

                $result[0].IsRemovable | Should -Be $true
                $result[0].DriveType | Should -Be 2
            }
        }
    }

    Context 'Error Handling' {
        It 'skips disks with missing disk metadata' {
            InModuleScope PSmm {
                $fakeDisk = [pscustomobject]@{
                    Index = 5
                    Caption = 'PhysicalDrive5'
                    SerialNumber = 'MISSING-META'
                    Model = 'Test'
                    Manufacturer = 'Test'
                    InterfaceType = 'SATA'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($fakeDisk)
                    DiskMetadata = @{}
                    Partitions   = @{}
                    LogicalDisks = @{}
                    Volumes      = @{}
                }

                $result = Get-StorageDrive

                $result | Should -BeNullOrEmpty
            }
        }

        It 'skips disks with no partitions' {
            InModuleScope PSmm {
                $fakeDisk = [pscustomobject]@{
                    Index = 6
                    Caption = 'PhysicalDrive6'
                    SerialNumber = 'NO-PART'
                    Model = 'Test'
                    Manufacturer = 'Test'
                    InterfaceType = 'SATA'
                }
                $fakeDiskMetadata = [pscustomobject]@{
                    Number = 6
                    BusType = 'SATA'
                    SerialNumber = 'NO-PART'
                    Model = 'Test'
                    Manufacturer = 'Test'
                    PartitionStyle = 'GPT'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($fakeDisk)
                    DiskMetadata = @{ 6 = $fakeDiskMetadata }
                    Partitions   = @{ 6 = @() }
                    LogicalDisks = @{}
                    Volumes      = @{}
                }

                $result = Get-StorageDrive

                $result | Should -BeNullOrEmpty
            }
        }

        It 'skips partitions with no logical disks' {
            InModuleScope PSmm {
                $fakeDisk = [pscustomobject]@{
                    Index = 7
                    Caption = 'PhysicalDrive7'
                    SerialNumber = 'NO-LOGICAL'
                    Model = 'Test'
                    Manufacturer = 'Test'
                    InterfaceType = 'SATA'
                }
                $fakePartition = [pscustomobject]@{ Index = 0 }
                $fakeDiskMetadata = [pscustomobject]@{
                    Number = 7
                    BusType = 'SATA'
                    SerialNumber = 'NO-LOGICAL'
                    Model = 'Test'
                    Manufacturer = 'Test'
                    PartitionStyle = 'GPT'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($fakeDisk)
                    DiskMetadata = @{ 7 = $fakeDiskMetadata }
                    Partitions   = @{ 7 = @($fakePartition) }
                    LogicalDisks = @{ 0 = @() }
                    Volumes      = @{}
                }

                $result = Get-StorageDrive

                $result | Should -BeNullOrEmpty
            }
        }

        It 'skips logical disks with no matching volume' {
            InModuleScope PSmm {
                $fakeDisk = [pscustomobject]@{
                    Index = 8
                    Caption = 'PhysicalDrive8'
                    SerialNumber = 'NO-VOL'
                    Model = 'Test'
                    Manufacturer = 'Test'
                    InterfaceType = 'SATA'
                }
                $fakePartition = [pscustomobject]@{ Index = 0 }
                $fakeLogicalDisk = [pscustomobject]@{
                    DeviceID = 'H:'
                    DriveType = 3
                    Size = 1099511627776
                    FreeSpace = 549755813888
                }
                $fakeDiskMetadata = [pscustomobject]@{
                    Number = 8
                    BusType = 'SATA'
                    SerialNumber = 'NO-VOL'
                    Model = 'Test'
                    Manufacturer = 'Test'
                    PartitionStyle = 'GPT'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($fakeDisk)
                    DiskMetadata = @{ 8 = $fakeDiskMetadata }
                    Partitions   = @{ 8 = @($fakePartition) }
                    LogicalDisks = @{ 0 = @($fakeLogicalDisk) }
                    Volumes      = @{}
                }

                $result = Get-StorageDrive

                $result | Should -BeNullOrEmpty
            }
        }

        It 'continues on error processing individual disk' {
            InModuleScope PSmm {
                $goodDisk = [pscustomobject]@{
                    Index = 0
                    Caption = 'PhysicalDrive0'
                    SerialNumber = 'GOOD'
                    Model = 'Good'
                    Manufacturer = 'Test'
                    InterfaceType = 'SATA'
                }
                $badDisk = [pscustomobject]@{
                    Index = 1
                    Caption = 'PhysicalDrive1'
                    SerialNumber = 'BAD'
                    Model = 'Bad'
                    Manufacturer = 'Test'
                    InterfaceType = 'SATA'
                }
                $goodPartition = [pscustomobject]@{ Index = 0 }
                $goodLogicalDisk = [pscustomobject]@{
                    DeviceID = 'C:'
                    DriveType = 3
                    Size = 1099511627776
                    FreeSpace = 549755813888
                }
                $goodDiskMetadata = [pscustomobject]@{
                    Number = 0
                    BusType = 'SATA'
                    SerialNumber = 'GOOD'
                    Model = 'Good'
                    Manufacturer = 'Test'
                    PartitionStyle = 'GPT'
                }
                $goodVolume = [pscustomobject]@{
                    DriveLetter = 'C'
                    FileSystemLabel = 'System'
                    FileSystem = 'NTFS'
                    HealthStatus = 'Healthy'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($goodDisk, $badDisk)
                    DiskMetadata = @{ 0 = $goodDiskMetadata }
                    Partitions   = @{ 0 = @($goodPartition); 1 = @() }
                    LogicalDisks = @{ 0 = @($goodLogicalDisk); 1 = @() }
                    Volumes      = @{ 'C' = $goodVolume }
                }

                $result = Get-StorageDrive

                $result | Should -Not -BeNullOrEmpty
                $result.Count | Should -BeGreaterThan 0
            }
        }
    }

    Context 'Multiple Drives' {
        It 'enumerates multiple drives correctly' {
            InModuleScope PSmm {
                $disk1 = [pscustomobject]@{
                    Index = 0
                    Caption = 'PhysicalDrive0'
                    SerialNumber = 'SN-001'
                    Model = 'SSD1'
                    Manufacturer = 'Brand1'
                    InterfaceType = 'SATA'
                }
                $disk2 = [pscustomobject]@{
                    Index = 1
                    Caption = 'PhysicalDrive1'
                    SerialNumber = 'SN-002'
                    Model = 'HDD1'
                    Manufacturer = 'Brand2'
                    InterfaceType = 'SATA'
                }
                $partition1 = [pscustomobject]@{ Index = 0 }
                $partition2 = [pscustomobject]@{ Index = 1 }
                $logical1 = [pscustomobject]@{
                    DeviceID = 'C:'
                    DriveType = 3
                    Size = 549755813888
                    FreeSpace = 274877906944
                }
                $logical2 = [pscustomobject]@{
                    DeviceID = 'D:'
                    DriveType = 3
                    Size = 2199023255552
                    FreeSpace = 1099511627776
                }
                $meta1 = [pscustomobject]@{
                    Number = 0
                    BusType = 'SATA'
                    SerialNumber = 'SN-001'
                    Model = 'SSD1'
                    Manufacturer = 'Brand1'
                    PartitionStyle = 'GPT'
                }
                $meta2 = [pscustomobject]@{
                    Number = 1
                    BusType = 'SATA'
                    SerialNumber = 'SN-002'
                    Model = 'HDD1'
                    Manufacturer = 'Brand2'
                    PartitionStyle = 'MBR'
                }
                $volume1 = [pscustomobject]@{
                    DriveLetter = 'C'
                    FileSystemLabel = 'System'
                    FileSystem = 'NTFS'
                    HealthStatus = 'Healthy'
                }
                $volume2 = [pscustomobject]@{
                    DriveLetter = 'D'
                    FileSystemLabel = 'Storage'
                    FileSystem = 'NTFS'
                    HealthStatus = 'Healthy'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($disk1, $disk2)
                    DiskMetadata = @{ 0 = $meta1; 1 = $meta2 }
                    Partitions   = @{ 0 = @($partition1); 1 = @($partition2) }
                    LogicalDisks = @{ 0 = @($logical1); 1 = @($logical2) }
                    Volumes      = @{ 'C' = $volume1; 'D' = $volume2 }
                }

                $result = Get-StorageDrive

                $result | Should -HaveCount 2
                $result[0].SerialNumber | Should -Be 'SN-001'
                $result[0].Label | Should -Be 'System'
                $result[1].SerialNumber | Should -Be 'SN-002'
                $result[1].Label | Should -Be 'Storage'
            }
        }
    }

    Context 'Serial Number Handling' {
        It 'trims whitespace from serial numbers' {
            InModuleScope PSmm {
                $fakeDisk = [pscustomobject]@{
                    Index = 0
                    Caption = 'PhysicalDrive0'
                    SerialNumber = '  TEST-SERIAL-WITH-SPACES  '
                    Model = 'Test'
                    Manufacturer = 'Test'
                    InterfaceType = 'SATA'
                }
                $fakePartition = [pscustomobject]@{ Index = 0 }
                $fakeLogicalDisk = [pscustomobject]@{
                    DeviceID = 'C:'
                    DriveType = 3
                    Size = 1099511627776
                    FreeSpace = 549755813888
                }
                $fakeDiskMetadata = [pscustomobject]@{
                    Number = 0
                    BusType = 'SATA'
                    SerialNumber = '  TEST-SERIAL-WITH-SPACES  '
                    Model = 'Test'
                    Manufacturer = 'Test'
                    PartitionStyle = 'GPT'
                }
                $fakeVolume = [pscustomobject]@{
                    DriveLetter = 'C'
                    FileSystemLabel = 'TestVol'
                    FileSystem = 'NTFS'
                    HealthStatus = 'Healthy'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($fakeDisk)
                    DiskMetadata = @{ 0 = $fakeDiskMetadata }
                    Partitions   = @{ 0 = @($fakePartition) }
                    LogicalDisks = @{ 0 = @($fakeLogicalDisk) }
                    Volumes      = @{ 'C' = $fakeVolume }
                }

                $result = Get-StorageDrive

                $result[0].SerialNumber | Should -Be 'TEST-SERIAL-WITH-SPACES'
            }
        }

        It 'handles empty serial numbers' {
            InModuleScope PSmm {
                $fakeDisk = [pscustomobject]@{
                    Index = 0
                    Caption = 'PhysicalDrive0'
                    SerialNumber = $null
                    Model = 'Test'
                    Manufacturer = 'Test'
                    InterfaceType = 'SATA'
                }
                $fakePartition = [pscustomobject]@{ Index = 0 }
                $fakeLogicalDisk = [pscustomobject]@{
                    DeviceID = 'C:'
                    DriveType = 3
                    Size = 1099511627776
                    FreeSpace = 549755813888
                }
                $fakeDiskMetadata = [pscustomobject]@{
                    Number = 0
                    BusType = 'SATA'
                    SerialNumber = $null
                    Model = 'Test'
                    Manufacturer = 'Test'
                    PartitionStyle = 'GPT'
                }
                $fakeVolume = [pscustomobject]@{
                    DriveLetter = 'C'
                    FileSystemLabel = 'NoSerial'
                    FileSystem = 'NTFS'
                    HealthStatus = 'Healthy'
                }

                $script:PSmmTestDriveData = @{
                    Disks        = @($fakeDisk)
                    DiskMetadata = @{ 0 = $fakeDiskMetadata }
                    Partitions   = @{ 0 = @($fakePartition) }
                    LogicalDisks = @{ 0 = @($fakeLogicalDisk) }
                    Volumes      = @{ 'C' = $fakeVolume }
                }

                $result = Get-StorageDrive

                $result[0].SerialNumber | Should -Be ''
            }
        }
    }
}
