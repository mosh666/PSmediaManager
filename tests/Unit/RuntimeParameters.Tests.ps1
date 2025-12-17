#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent

    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Interfaces.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Exceptions.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/UiModels.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/ProjectModels.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Services/FileSystemService.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/AppConfiguration.ps1')
}

Describe 'RuntimeParameters' {
    It 'FromObject($null) returns defaults' {
        $p = [RuntimeParameters]::FromObject($null)
        $p | Should -Not -BeNullOrEmpty
        $p.Debug | Should -BeFalse
        $p.Verbose | Should -BeFalse
        $p.Dev | Should -BeFalse
        $p.Update | Should -BeFalse
        $p.NonInteractive | Should -BeFalse
    }

    It 'FromObject maps legacy hashtable shape (explicit bools)' {
        $legacy = @{
            Debug = $true
            Verbose = $false
            Dev = $true
            Update = $true
            NonInteractive = $true
        }

        $p = [RuntimeParameters]::FromObject($legacy)
        $p.Debug | Should -BeTrue
        $p.Verbose | Should -BeFalse
        $p.Dev | Should -BeTrue
        $p.Update | Should -BeTrue
        $p.NonInteractive | Should -BeTrue
    }

    It 'FromObject supports bound-parameters hashtable (switch presence)' {
        $bound = @{ Debug = $true; Verbose = $true }
        $p = [RuntimeParameters]::FromObject($bound)

        $p.Debug | Should -BeTrue
        $p.Verbose | Should -BeTrue
        $p.Dev | Should -BeFalse
        $p.Update | Should -BeFalse
        $p.NonInteractive | Should -BeFalse
    }

    It 'Constructor respects explicit false values in bound-parameters hashtable' {
        $bound = @{ Verbose = $false }
        $p = [RuntimeParameters]::new($bound)
        $p.Verbose | Should -BeFalse
    }

    It 'ToHashtable provides a stable key set' {
        $p = [RuntimeParameters]::new()
        $p.Debug = $true
        $p.NonInteractive = $true

        $table = $p.ToHashtable()
        $table | Should -BeOfType hashtable

        $table.ContainsKey('Debug') | Should -BeTrue
        $table.ContainsKey('Verbose') | Should -BeTrue
        $table.ContainsKey('Dev') | Should -BeTrue
        $table.ContainsKey('Update') | Should -BeTrue
        $table.ContainsKey('NonInteractive') | Should -BeTrue

        $table.Debug | Should -BeTrue
        $table.NonInteractive | Should -BeTrue
    }

    It 'FromObject returns input when already typed' {
        $p = [RuntimeParameters]::new()
        $same = [RuntimeParameters]::FromObject($p)
        $same | Should -Be $p
    }

    It 'ShouldPause respects NonInteractive' {
        $p = [RuntimeParameters]::new()
        $p.Debug = $true
        $p.NonInteractive = $true
        $p.ShouldPause() | Should -BeFalse
    }
}
