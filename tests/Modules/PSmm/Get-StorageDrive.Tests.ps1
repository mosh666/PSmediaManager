#Requires -Version 7.5.4
Set-StrictMode -Version Latest

$script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
$script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'

if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) {
    Remove-Module -Name PSmm -Force
}
Import-Module -Name $script:psmmManifest -Force -ErrorAction Stop

Describe 'Get-StorageDrive' {
    InModuleScope PSmm {
        It 'returns empty result when CIM is unavailable' {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-CimInstance' }

            $res = Get-StorageDrive -Verbose
            $res | Should -BeNullOrEmpty
        }

        It 'handles disks without partitions gracefully and returns empty' {
            # Disk enumeration returns one disk
            Mock Get-CimInstance { @(New-CimInstance -ClassName 'Win32_Diskdrive' -ClientOnly -Property @{ Index = 0; Caption = 'Disk 0' }) } -ParameterFilter { $ClassName -eq 'Win32_Diskdrive' }
            # Disk metadata available
            Mock Get-Disk { @([pscustomobject]@{ Number = 0; Manufacturer = 'ACME'; Model = 'Turbo'; SerialNumber = 'SN001'; PartitionStyle = 'GPT' }) }
            # No partitions associated
            Mock Get-CimAssociatedInstance { @() }
            
            $res = Get-StorageDrive -Verbose
            $res | Should -BeNullOrEmpty
        }

        It 'continues when Get-Volume fails for a logical disk' {
            # One disk with one partition and one logical disk
            Mock Get-CimInstance { @(New-CimInstance -ClassName 'Win32_Diskdrive' -ClientOnly -Property @{ Index = 1; Caption = 'Disk 1' }) } -ParameterFilter { $ClassName -eq 'Win32_Diskdrive' }
            Mock Get-Disk { @([pscustomobject]@{ Number = 1; Manufacturer = 'ACME'; Model = 'Turbo'; SerialNumber = 'SN002'; PartitionStyle = 'GPT' }) }
            Mock Get-CimAssociatedInstance {
                if ($ResultClassName -eq 'Win32_DiskPartition') {
                    @([pscustomobject]@{ Index = 1 })
                }
                elseif ($ResultClassName -eq 'Win32_LogicalDisk') {
                    @([pscustomobject]@{ DeviceID = 'E:'; Size = 100GB; FreeSpace = 60GB })
                }
            }
            Mock Get-Volume { throw 'Simulated failure' }

            $res = Get-StorageDrive -Verbose
            $res | Should -BeNullOrEmpty
        }
    }
}

Describe 'Show-StorageInfo' {
    InModuleScope PSmm {
        It 'prints storage info without details' {
            $config = @{ Storage = @{ '1' = @{ Master = @{ DriveLetter = 'E:'; SerialNumber = 'SN001'; Label = 'DATA' }; Backup = @{} } } }
            { Show-StorageInfo -Config $config } | Should -Not -Throw
        }

        It 'prints storage info with details using mocked drive data' {
            Mock Get-StorageDrive { @([pscustomobject]@{ SerialNumber = 'SN001'; Manufacturer = 'ACME'; Model = 'Turbo'; FileSystem = 'NTFS'; PartitionKind = 'GPT'; TotalSpace = 100; FreeSpace = 25; UsedSpace = 75; HealthStatus = 'Healthy'; Number = 0; DriveLetter = 'E:'; Label = 'DATA' }) }
            $config = @{ Storage = @{ '1' = @{ Master = @{ DriveLetter = 'E:'; SerialNumber = 'SN001'; Label = 'DATA' }; Backup = @{} } } }
            { Show-StorageInfo -Config $config -ShowDetails } | Should -Not -Throw
        }
    }
}
