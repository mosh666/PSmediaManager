#Requires -Version 7.5.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\Modules\PSmm\Classes\UiModels.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\Modules\PSmm.UI\Private\Format-UI.ps1')
}

Describe 'UiKeyValueItem' {
    It 'New-UiKeyValueItem creates a UiKeyValueItem with expected properties' {
        $item = New-UiKeyValueItem -Key 'K' -Value 123 -Color 'FG'

        $item.GetType().Name | Should -Be 'UiKeyValueItem'
        $item.Key | Should -Be 'K'
        $item.Value | Should -Be 123
        $item.Color | Should -Be 'FG'
    }

    It 'ToHashtable returns a stable key set' {
        $item = New-UiKeyValueItem -Key 'K' -Value 'V' -Color 'C'
        $ht = $item.ToHashtable()

        $ht | Should -BeOfType 'hashtable'
        $ht.Keys | Should -Contain 'Key'
        $ht.Keys | Should -Contain 'Value'
        $ht.Keys | Should -Contain 'Color'
    }

    It 'FromHashtable round-trips basic fields' {
        $src = @{ Key = 'A'; Value = 'B'; Color = 'C' }
        $item = [UiKeyValueItem]::FromHashtable($src)

        $item.Key | Should -Be 'A'
        $item.Value | Should -Be 'B'
        $item.Color | Should -Be 'C'
    }
}
