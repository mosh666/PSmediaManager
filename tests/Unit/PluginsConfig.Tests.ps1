#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/ProjectModels.ps1')
}

describe 'PluginsConfig' {
    It 'FromObject maps legacy hashtable shape and keeps typed Paths' {
        $pluginsConfigType = 'PluginsConfig' -as [type]
        $pluginsPathsType = 'PluginsPathsConfig' -as [type]
        $pluginsConfigType | Should -Not -BeNullOrEmpty
        $pluginsPathsType | Should -Not -BeNullOrEmpty

        $src = @{
            Global  = $null
            Project = $null
            Resolved = $null
            Paths   = @{ Global = 'C:\X\Global.psd1'; Project = 'C:\X\Project.psd1' }
        }

        $cfg = $pluginsConfigType::FromObject($src)
        $cfg.GetType().Name | Should -Be 'PluginsConfig'
        $cfg.Paths.GetType().Name | Should -Be 'PluginsPathsConfig'
        $cfg.Paths.Global | Should -Be 'C:\X\Global.psd1'
        $cfg.Paths.Project | Should -Be 'C:\X\Project.psd1'
    }

    It 'FromObject unwraps legacy Plugins root on Global/Project manifests' {
        $pluginsConfigType = 'PluginsConfig' -as [type]
        $pluginsConfigType | Should -Not -BeNullOrEmpty

        $src = @{
            Global  = @{ Plugins = @{ g = @{ p = @{ Name = 'P' } } } }
            Project = @{ Plugins = @{ g = @{ p = @{ Enabled = $true } } } }
            Paths   = @{ Global = 'G'; Project = 'P' }
        }

        $cfg = $pluginsConfigType::FromObject($src)
        $cfg.Global.Keys | Should -Contain 'g'
        $cfg.Project.Keys | Should -Contain 'g'
    }

    It 'ToHashtable provides legacy-compatible structure' {
        $pluginsConfigType = 'PluginsConfig' -as [type]
        $pluginsConfigType | Should -Not -BeNullOrEmpty

        $cfg = $pluginsConfigType::new()
        $cfg.Paths.Global = 'G'
        $cfg.Paths.Project = 'P'

        $ht = $cfg.ToHashtable()
        $ht.Paths.Global | Should -Be 'G'
        $ht.Paths.Project | Should -Be 'P'
    }

    It 'FromObject returns input when already typed' {
        $pluginsConfigType = 'PluginsConfig' -as [type]
        $pluginsConfigType | Should -Not -BeNullOrEmpty

        $typed = $pluginsConfigType::new()
        $result = $pluginsConfigType::FromObject($typed)
        $result | Should -Be $typed
    }
}
