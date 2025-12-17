#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Projects/Classes/ProjectsRegistryModels.ps1')
}

describe 'ProjectsRegistryCache' {
    It 'FromObject maps legacy hashtable registry shape into typed dictionaries' {
        $p1 = [pscustomobject]@{ Name = 'A'; DriveType = 'Master'; Label = 'M1'; Path = 'X:\Projects\A' }
        $legacy = @{
            Master = @{
                'M1' = @{ Label = 'M1'; Projects = @($p1) }
            }
            Backup = @{}
            LastScanned = [datetime]::MinValue
            ProjectDirs = @{ 'abc_Projects' = (Get-Date) }
        }

        $cache = [ProjectsRegistryCache]::FromObject($legacy)
        $cache.Master.Count | Should -Be 1
        $cache.Backup.Count | Should -Be 0
        $cache.Master.ContainsKey('M1') | Should -BeTrue
        $cache.Master['M1'].Label | Should -Be 'M1'
        $cache.Master['M1'].Projects.Count | Should -Be 1
        $cache.Master['M1'].Projects[0].Name | Should -Be 'A'
        $cache.ProjectDirs.Count | Should -Be 1
    }

    It 'Drive entry Projects property is hidden from Get-Member by default' {
        $entry = [ProjectsDriveRegistryEntry]::new()
        $props = ($entry | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name)
        $props | Should -Not -Contain 'Projects'
        $entry.Projects.Count | Should -Be 0
    }
}
