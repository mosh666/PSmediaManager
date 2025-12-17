#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/ProjectModels.ps1')
}

describe 'ProjectsPortRegistry' {
    It 'FromObject maps legacy hashtable and ToHashtable round-trips' {
        $src = @{
            P1 = 3310
            P2 = '3311'
        }

        $reg = [ProjectsPortRegistry]::FromObject($src)
        $reg.GetCount() | Should -Be 2
        $reg.ContainsKey('P1') | Should -BeTrue
        $reg.GetPort('P2') | Should -Be 3311

        $roundTrip = $reg.ToHashtable()
        $roundTrip.P1 | Should -Be 3310
        $roundTrip.P2 | Should -Be 3311
    }

    It 'FromObject returns input when already typed' {
        $typed = [ProjectsPortRegistry]::new()
        $typed.SetPort('P3', 3312)

        $result = [ProjectsPortRegistry]::FromObject($typed)
        $result | Should -Be $typed
        $result.GetPort('P3') | Should -Be 3312
    }
}
