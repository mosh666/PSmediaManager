#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/ProjectModels.ps1')
}

describe 'UIConfig' {
    It 'FromObject($null) returns defaults with non-null ANSI bags' {
        $uiType = 'UIConfig' -as [type]
        $ansiType = 'AnsiConfig' -as [type]
        $basicType = 'AnsiBasicConfig' -as [type]
        $uiType | Should -Not -BeNullOrEmpty
        $ansiType | Should -Not -BeNullOrEmpty
        $basicType | Should -Not -BeNullOrEmpty

        $cfg = $uiType::FromObject($null)
        $cfg.GetType().Name | Should -Be 'UIConfig'
        $cfg.ANSI | Should -Not -BeNullOrEmpty
        $cfg.ANSI.Basic | Should -Not -BeNullOrEmpty
        ($cfg.ANSI.FG -is [hashtable]) | Should -BeTrue
        ($cfg.ANSI.BG -is [hashtable]) | Should -BeTrue
    }

    It 'FromObject maps legacy hashtable shape (Width, ANSI.Basic, ANSI.FG/BG)' {
        $uiType = 'UIConfig' -as [type]
        $uiType | Should -Not -BeNullOrEmpty

        $src = @{
            Width = 90
            ANSI = @{
                Basic = @{
                    Bold = '[1m'
                    Italic = '[3m'
                    Underline = '[4m'
                    Dim = '[2m'
                    Blink = '[5m'
                    Strikethrough = '[9m'
                }
                FG = @{ Primary = '[38;5;33m'; Error = '[38;5;196m' }
                BG = @{ Primary = '[48;5;33m' }
            }
        }

        $cfg = $uiType::FromObject($src)
        $cfg.Width | Should -Be 90
        $cfg.ANSI.Basic.Bold | Should -Be '[1m'
        $cfg.ANSI.Basic.Italic | Should -Be '[3m'
        $cfg.ANSI.Basic.Underline | Should -Be '[4m'
        $cfg.ANSI.FG.Primary | Should -Be '[38;5;33m'
        $cfg.ANSI.FG.Error | Should -Be '[38;5;196m'
        $cfg.ANSI.BG.Primary | Should -Be '[48;5;33m'
    }

    It 'ToHashtable provides legacy-compatible structure' {
        $uiType = 'UIConfig' -as [type]
        $uiType | Should -Not -BeNullOrEmpty

        $cfg = $uiType::new()
        $cfg.Width = 123
        $cfg.ANSI.Basic.Bold = '[1m'
        $cfg.ANSI.FG.Primary = '[38;5;33m'
        $cfg.ANSI.BG.Primary = '[48;5;33m'

        $ht = $cfg.ToHashtable()
        $ht.Width | Should -Be 123
        $ht.ANSI.Basic.Bold | Should -Be '[1m'
        $ht.ANSI.FG.Primary | Should -Be '[38;5;33m'
        $ht.ANSI.BG.Primary | Should -Be '[48;5;33m'
    }

    It 'FromObject returns input when already typed' {
        $uiType = 'UIConfig' -as [type]
        $uiType | Should -Not -BeNullOrEmpty

        $typed = $uiType::new()
        $result = $uiType::FromObject($typed)
        $result | Should -Be $typed
    }
}
