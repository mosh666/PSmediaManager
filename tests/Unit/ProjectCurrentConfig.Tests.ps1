#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/ProjectModels.ps1')
}

describe 'ProjectCurrentConfig' {
    It 'FromObject maps legacy hashtable shape and ToHashtable round-trips' {
        $src = @{
            Name = 'P1'
            Path = 'X:\Projects\P1'
            Config = 'X:\Projects\P1\Config'
            Databases = 'X:\Projects\P1\Databases'
            StorageDrive = @{
                Label = 'Disk1'
                DriveLetter = 'X:'
                SerialNumber = 'SN'
                DriveLabel = 'D1'
            }
        }

        $current = [ProjectCurrentConfig]::FromObject($src)
        $current.Name | Should -Be 'P1'
        $current.Path | Should -Be 'X:\Projects\P1'
        $current.StorageDrive.Label | Should -Be 'Disk1'

        $roundTrip = $current.ToHashtable()
        $roundTrip.Name | Should -Be 'P1'
        $roundTrip.StorageDrive.Label | Should -Be 'Disk1'
    }

    It 'FromObject returns input when already typed' {
        $typed = [ProjectCurrentConfig]::new()
        $typed.Name = 'P2'

        $result = [ProjectCurrentConfig]::FromObject($typed)
        $result | Should -Be $typed
    }
}
