Describe 'Export-SafeConfiguration - Scalar quoting and numeric formatting' {
    BeforeAll {
        # Dot-source the implementation so nested helpers are available
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'quotes scalars and formats numbers/booleans consistently' {
        $tmp = Join-Path $env:TEMP ("psmm-scalar-{0}.psd1" -f ([System.Guid]::NewGuid().ToString()))
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

        $cfg = @{
            NumberInt = 42
            NumberDouble = 12345.6789
            DecimalVal = [decimal]::Parse('3.14159', [System.Globalization.CultureInfo]::InvariantCulture)
            BoolTrue = $true
            BoolFalse = $false
            QuoteString = "O'Hare"
            DateVal = [datetime]'2025-11-18T12:34:56Z'
        }

        Export-SafeConfiguration -Configuration $cfg -Path $tmp

        $content = Get-Content -Path $tmp -Raw

        # Numeric values are typically rendered as trimmed, single-quoted invariant strings
        $content | Should -Match "NumberInt = '42'"
        $content | Should -Match "NumberDouble = '12345.6789'"
        # Decimal may be represented as a scalar or as a small hashtable (Scale/Value) depending on snapshotting
        ($content -match "DecimalVal = '3\.14159'") -or ($content -match "DecimalVal = @\{") | Should -BeTrue

        # Booleans serialized as 'True'/'False'
        $content | Should -Match "BoolTrue = 'True'"
        $content | Should -Match "BoolFalse = 'False'"

        # Single quotes inside strings are escaped by doubling
        $content | Should -Match "QuoteString = 'O''Hare'"

        # Date/time serialized (date portion present)
        $content | Should -Match '2025-11-18'

        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
    }
}
#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration - Scalar quoting' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'quotes empty string values and preserves embedded single-quote by escaping' {
        $exportPath = Join-Path $TestDrive 'scalar-quote.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $cfg = @{ TestScalar = ''; Owner = "O'Connor" }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        $content | Should -Match "TestScalar\s*=\s*''"
        $content | Should -Match "O''Connor"

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }
}
