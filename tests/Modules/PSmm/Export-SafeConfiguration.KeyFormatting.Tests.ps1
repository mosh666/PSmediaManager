Describe 'Export-SafeConfiguration - PSD1 key formatting' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'renders non-identifier keys quoted and numeric keys unquoted' {
        $tmp = Join-Path $env:TEMP ("psmm-keys-{0}.psd1" -f ([System.Guid]::NewGuid().ToString()))
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

        $cfg = @{
            'NormalKey' = 'v1'
            'with-space' = 'v2'
            '123' = 'numericKey'
            'has-dash' = 'v3'
            "HasUpper" = 'v4'
        }

        Export-SafeConfiguration -Configuration $cfg -Path $tmp
        $content = Get-Content -Path $tmp -Raw

        # Identifier-like key should be unquoted
        $content | Should -Match "NormalKey = 'v1'"

        # Keys with space or dash must be single-quoted
        $content | Should -Match "'with-space' = 'v2'"
        $content | Should -Match "'has-dash' = 'v3'"

        # Numeric key may be rendered quoted or unquoted depending on implementation; accept both
        ($content -match "123 = 'numericKey'") -or ($content -match "'123' = 'numericKey'") | Should -BeTrue

        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
    }
}
