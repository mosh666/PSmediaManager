#Requires -Version 7.5.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\Modules\PSmm\Classes\UiModels.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\Modules\PSmm.UI\Private\Format-UI.ps1')
}

Describe 'UiColumn' {
    It 'New-UiColumn creates a UiColumn with expected properties' {
        $col = New-UiColumn -Text 'Hello' -Width '50%' -Alignment 'r' -Padding 2 -TextColor 'FG' -BackgroundColor 'BG' -Bold -Italic -Underline -Dim -Blink -Strikethrough -MinWidth 5 -MaxWidth 10

        $col.GetType().Name | Should -Be 'UiColumn'
        $col.Text | Should -Be 'Hello'
        $col.Width | Should -Be '50%'
        $col.Alignment | Should -Be 'r'
        $col.Padding | Should -Be 2
        $col.TextColor | Should -Be 'FG'
        $col.BackgroundColor | Should -Be 'BG'
        $col.Bold | Should -BeTrue
        $col.Italic | Should -BeTrue
        $col.Underline | Should -BeTrue
        $col.Dim | Should -BeTrue
        $col.Blink | Should -BeTrue
        $col.Strikethrough | Should -BeTrue
        $col.MinWidth | Should -Be 5
        $col.MaxWidth | Should -Be 10
    }

    It 'ToHashtable returns a stable key set' {
        $col = New-UiColumn -Text 'X' -Width 12 -Bold
        $ht = $col.ToHashtable()

        $ht | Should -BeOfType 'hashtable'
        $ht.Keys | Should -Contain 'Text'
        $ht.Keys | Should -Contain 'Width'
        $ht.Keys | Should -Contain 'Alignment'
        $ht.Keys | Should -Contain 'Padding'
        $ht.Keys | Should -Contain 'TextColor'
        $ht.Keys | Should -Contain 'BackgroundColor'
        $ht.Keys | Should -Contain 'Bold'
        $ht.Keys | Should -Contain 'Italic'
        $ht.Keys | Should -Contain 'Underline'
        $ht.Keys | Should -Contain 'Dim'
        $ht.Keys | Should -Contain 'Blink'
        $ht.Keys | Should -Contain 'Strikethrough'
        $ht.Keys | Should -Contain 'MinWidth'
        $ht.Keys | Should -Contain 'MaxWidth'
    }
}
