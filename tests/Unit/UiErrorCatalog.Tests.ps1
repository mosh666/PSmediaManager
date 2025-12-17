#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/UiModels.ps1')
}

describe 'UiErrorCatalog' {
    It 'FromObject maps Storage errors and FilterStorageGroup filters by prefix' {
        $src = @{
            Storage = @{
                '1.Master'  = 'Master missing'
                '1.Backup.2' = 'Backup 2 missing'
                '2.Master'  = 'Other group'
                '1.Empty'   = ''
            }
        }

        $catalog = [UiErrorCatalog]::FromObject($src)
        $catalog.Storage.Count | Should -Be 3

        $filtered = $catalog.FilterStorageGroup('1')
        $filtered.Storage.Count | Should -Be 2

        $msgs = $filtered.GetAllMessages()
        $msgs | Should -Contain 'Master missing'
        $msgs | Should -Contain 'Backup 2 missing'
        $msgs | Should -Not -Contain 'Other group'
    }
}
