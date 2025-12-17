#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Interfaces.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/AppConfiguration.ps1')
}

describe 'StorageGroupConfig' {
    It 'FromObject maps legacy hashtable shape (DisplayName, Master, Backup, Paths)' {
        $src = @{
            DisplayName = 'MyGroup'
            Master = @{ Label = 'MasterDisk'; SerialNumber = 'MSN' }
            Backup = @{
                '1' = @{ Label = 'Backup1'; SerialNumber = 'B1' }
                '2' = @{ Label = 'Backup2'; SerialNumber = 'B2' }
            }
            Paths = @{ Assets = 'X:\Assets'; Log = 'X:\Log' }
        }

        $cfg = [StorageGroupConfig]::FromObject('1', $src)
        $cfg.GroupId | Should -Be '1'
        $cfg.DisplayName | Should -Be 'MyGroup'
        $cfg.Master.Label | Should -Be 'MasterDisk'
        $cfg.Master.SerialNumber | Should -Be 'MSN'
        $cfg.Backups['1'].SerialNumber | Should -Be 'B1'
        $cfg.Paths['Assets'] | Should -Be 'X:\Assets'
    }

    It 'FromObject supports safe-export Master.Drive and Master.Backups shape' {
        $src = @{
            DisplayName = 'G'
            Master = @{
                Drive = @{ Label = 'M'; SerialNumber = 'MSN' }
                Backups = @{ '1' = @{ Label = 'B'; SerialNumber = 'BSN' } }
            }
        }

        $cfg = [StorageGroupConfig]::FromObject('9', $src)
        $cfg.Master.Label | Should -Be 'M'
        $cfg.Backups['1'].SerialNumber | Should -Be 'BSN'
    }

    It 'ToHashtable produces legacy-compatible schema (DisplayName, Master, Backup, Paths)' {
        $cfg = [StorageGroupConfig]::new('2')
        $cfg.DisplayName = 'G2'
        $cfg.Master = [StorageDriveConfig]::FromObject(@{ Label = 'M2'; SerialNumber = 'MSN2' })
        $cfg.Backups['1'] = [StorageDriveConfig]::FromObject(@{ Label = 'B1'; SerialNumber = 'BSN1' })
        $cfg.Paths['Assets'] = 'Y:\Assets'

        $ht = $cfg.ToHashtable()
        ($ht -is [hashtable]) | Should -BeTrue
        $ht.DisplayName | Should -Be 'G2'
        $ht.Master.Label | Should -Be 'M2'
        $ht.Backup['1'].SerialNumber | Should -Be 'BSN1'
        $ht.Paths.Assets | Should -Be 'Y:\Assets'
    }
}
