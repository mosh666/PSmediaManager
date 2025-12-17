#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/UiModels.ps1')
}

describe 'UiProjectsIndex' {
    It 'FromObject maps Master and Backup drive dictionaries' {
        $p1 = [pscustomobject]@{ Name = 'A' }
        $p2 = [pscustomobject]@{ Name = 'B' }

        $src = @{
            Master = @{
                'M1' = @($p1)
            }
            Backup = @{
                'B1' = @($p2)
            }
        }

        $idx = [UiProjectsIndex]::FromObject($src)
        $idx.Master.Count | Should -Be 1
        $idx.Backup.Count | Should -Be 1
        $idx.Master['M1'].Count | Should -Be 1
        $idx.Backup['B1'].Count | Should -Be 1
        $idx.Master['M1'][0].Name | Should -Be 'A'
        $idx.Backup['B1'][0].Name | Should -Be 'B'
    }

    It 'FromObject returns empty dictionaries when input is null' {
        $idx = [UiProjectsIndex]::FromObject($null)
        $idx.Master.Count | Should -Be 0
        $idx.Backup.Count | Should -Be 0
    }
}
