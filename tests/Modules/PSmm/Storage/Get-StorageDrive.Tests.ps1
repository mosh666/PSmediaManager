#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Get-StorageDrive' {
    BeforeAll {
        try {
            $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
            $helperPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Support\Import-AllTestHelpers.ps1')
            . $helperPath.Path -RepositoryRoot $repoRoot
            $functionPath = Resolve-Path -Path (Join-Path -Path $repoRoot -ChildPath 'src\Modules\PSmm\Public\Storage\Get-StorageDrive.ps1')
            . $functionPath.Path
            $script:OriginalForceInline = $env:MEDIA_MANAGER_TEST_FORCE_INLINE_STORAGE
            $env:MEDIA_MANAGER_TEST_FORCE_INLINE_STORAGE = '1'
        }
        catch {
            Write-Host "BeforeAll error (Get-StorageDrive): $($_.Exception.Message)" -ForegroundColor Red
            throw
        }
    }

    AfterAll {
        if ([string]::IsNullOrEmpty($script:OriginalForceInline)) {
            Remove-Item -Path Env:MEDIA_MANAGER_TEST_FORCE_INLINE_STORAGE -ErrorAction SilentlyContinue
        }
        else {
            $env:MEDIA_MANAGER_TEST_FORCE_INLINE_STORAGE = $script:OriginalForceInline
        }
    }

    It 'returns empty result when CIM commands are unavailable' {
        Mock Get-Command { $null } -ModuleName PSmm -ParameterFilter { $Name -eq 'Get-CimInstance' }

        InModuleScope PSmm {
            $result = Get-StorageDrive

            $result | Should -BeNullOrEmpty
        }
    }

    It 'enumerates drives via CIM pipeline and emits computed fields' {
        InModuleScope PSmm {
            $disk = New-CimInstance -ClassName Win32_Diskdrive -ClientOnly -Property @{
                DeviceID = '\\?\PHYSICALDRIVE7'
                Index = 7
                Caption = 'Sample Disk'
                InterfaceType = 'USB'
            }
            $diskMetadata = [pscustomobject]@{
                Number = 7
                Manufacturer = 'Contoso'
                Model = 'External SSD'
                SerialNumber = '  SN-42  '
                PartitionStyle = 'GPT'
                BusType = 'USB'
            }
            $partition = New-CimInstance -ClassName Win32_DiskPartition -ClientOnly -Property @{
                DeviceID = 'Disk #7, Partition #0'
                DiskIndex = 7
                Index = 0
            }
            $logicalDisk = New-CimInstance -ClassName Win32_LogicalDisk -ClientOnly -Property @{
                DeviceID = 'X:'
                DriveType = 3
                Size = [uint64](200GB)
                FreeSpace = [uint64](50GB)
            }
            $volume = [pscustomobject]@{
                DriveLetter = 'X'
                FileSystemLabel = 'Media'
                FileSystem = 'NTFS'
                HealthStatus = 'Healthy'
            }

            Mock Get-CimInstance {
                param($ClassName)
                if ($ClassName -eq 'Win32_Diskdrive') { return @($disk) }
                return @()
            }
            Mock Get-Disk { @($diskMetadata) }
            Mock Get-CimAssociatedInstance {
                param($ResultClassName, $InputObject)
                if ($ResultClassName -eq 'Win32_DiskPartition') { return @($partition) }
                if ($ResultClassName -eq 'Win32_LogicalDisk') { return @($logicalDisk) }
                return @()
            }
            Mock Get-Volume { @($volume) }

            $result = Get-StorageDrive

            $result | Should -HaveCount 1
            $drive = $result | Select-Object -First 1
            $drive.SerialNumber | Should -Be 'SN-42'
            $drive.UsedSpace | Should -Be 150
            $drive.IsRemovable | Should -BeTrue
            $drive.BusType | Should -Be 'USB'
            Should -Invoke Get-CimInstance -Times 1 -ParameterFilter { $ClassName -eq 'Win32_Diskdrive' }
            Should -Invoke Get-Disk -Times 1
            Should -Invoke Get-CimAssociatedInstance -Times 2
            Should -Invoke Get-Volume -Times 1
        }
    }
}
