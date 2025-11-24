#Requires -Version 7.5.4
Set-StrictMode -Version Latest

$script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
$script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'

if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) {
    Remove-Module -Name PSmm -Force
}
Import-Module -Name $script:psmmManifest -Force -ErrorAction Stop

Describe 'Show-StorageInfo' {
    InModuleScope PSmm {
        BeforeAll {
            $script:mockConfig = @{
                DisplayName = 'Test App'
                AppVersion = '1.0.0'
                UI = @{}
                Storage = @{
                    1 = @{
                        Master = @{
                            Label = 'MasterDrive'
                            SerialNumber = 'SN-12345'
                            DriveLetter = 'E'
                            IsAvailable = $true
                            Path = 'E:\'
                            FreeSpaceGB = 100
                            TotalSpaceGB = 500
                        }
                        Backup = @{
                            'BackupDrive1' = @{
                                Label = 'BackupDrive1'
                                SerialNumber = 'SN-67890'
                                DriveLetter = 'F'
                                IsAvailable = $true
                                Path = 'F:\'
                                FreeSpaceGB = 200
                                TotalSpaceGB = 1000
                            }
                        }
                    }
                    2 = @{
                        Master = @{
                            Label = 'MasterDrive2'
                            SerialNumber = 'SN-ABCDE'
                            DriveLetter = 'G'
                            IsAvailable = $false
                            Path = 'G:\'
                        }
                        Backup = @{}
                    }
                }
            }
        }

        It 'displays storage configuration without errors' {
            { Show-StorageInfo -Config $script:mockConfig } | Should -Not -Throw
        }

        It 'handles empty storage configuration' {
            $emptyConfig = @{
                Storage = @{}
            }

            { Show-StorageInfo -Config $emptyConfig } | Should -Not -Throw
        }

        It 'handles storage group with no backup drives' {
            $configWithNoBackups = @{
                Storage = @{
                    1 = @{
                        Master = @{
                            Label = 'OnlyMaster'
                            SerialNumber = 'SN-99999'
                            DriveLetter = 'H'
                            IsAvailable = $true
                        }
                        Backup = @{}
                    }
                }
            }

            { Show-StorageInfo -Config $configWithNoBackups } | Should -Not -Throw
        }

        It 'accepts ShowDetails switch' {
            # Mock Get-StorageDrive to avoid CIM calls in test
            Mock Get-StorageDrive { return @() }

            { Show-StorageInfo -Config $script:mockConfig -ShowDetails } | Should -Not -Throw
            Should -Invoke Get-StorageDrive -Times 1
        }
    }
}

Describe 'Show-StorageDevice' {
    InModuleScope PSmm {
        It 'displays device configuration' {
            $deviceConfig = @{
                Label = 'TestDrive'
                SerialNumber = 'SN-TEST'
                DriveLetter = 'Z'
                IsAvailable = $true
            }

            { Show-StorageDevice -Config $deviceConfig } | Should -Not -Throw
        }

        It 'handles unavailable device' {
            $unavailableConfig = @{
                Label = 'OfflineDrive'
                SerialNumber = 'SN-OFFLINE'
                DriveLetter = ''
                IsAvailable = $false
            }

            { Show-StorageDevice -Config $unavailableConfig } | Should -Not -Throw
        }

        It 'accepts custom indent parameter' {
            $config = @{
                Label = 'IndentTest'
                SerialNumber = 'SN-INDENT'
                DriveLetter = 'Y'
                IsAvailable = $true
            }

            { Show-StorageDevice -Config $config -Indent 8 } | Should -Not -Throw
        }
    }
}
