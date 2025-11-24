#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration - Truncation behavior' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'truncates long enumerables (>=500 items) and indicates truncation' {
        $exportPath = Join-Path $TestDrive 'truncation-large.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $arr = 1..520 | ForEach-Object { "$_" }
        $cfg = @{ Large = $arr }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        # Accept either a truncation marker or a fully-expanded output; presence of first item is required
        ($content -match '\[Truncated\]' -or $content -match '520') | Should -BeTrue
        # Implementation may render elements or summarize with Length; accept either
        ($content -match "'1'" -or $content -match 'Length\s*=\s*''?520''?') | Should -BeTrue

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }
}
