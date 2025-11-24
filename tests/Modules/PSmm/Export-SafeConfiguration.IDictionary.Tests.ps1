#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration - IDictionary handling' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'converts hashtable/dictionary values into safe serializable form' {
        $exportPath = Join-Path $TestDrive 'dict-example.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $dict = [hashtable]@{ Alpha = 1; Beta = 'two'; Nested = @{ Inner = 'value' } }
        $cfg = @{ DictionaryExample = $dict }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        $content | Should -Match 'DictionaryExample\s*=\s*@\{'
        $content | Should -Match '\bAlpha\b'
        $content | Should -Match "Beta\s*=\s*'two'"
        $content | Should -Match 'Nested'

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }
}
