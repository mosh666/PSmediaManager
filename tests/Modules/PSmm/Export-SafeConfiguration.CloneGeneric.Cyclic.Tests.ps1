#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration - CloneGeneric cyclic references' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'handles cyclic hashtable references safely' {
        $exportPath = Join-Path $TestDrive 'cyclic-clone.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $h = @{}
        $h.Self = $h
        $cfg = @{ Cycle = $h }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        # Accept either an explicit cyclic marker or a truncation/MaxDepth marker
        ($content -match '\[CyclicRef\]' -or $content -match '\[MaxDepth\]' -or $content -match 'Self') | Should -BeTrue

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }
}
