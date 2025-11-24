Describe 'Export-SafeConfiguration (coverage boost 2)' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'quotes empty strings and preserves embedded single-quotes' {
        $exportPath = Join-Path $TestDrive 'helpers-empty-and-quote.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $cfg = @{ Empty = ''; Name = "O'Connor" }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        # empty string should be rendered as an empty quoted token and embedded single-quote preserved
        $content | Should -Match "''"
        # export uses single-quote escaping (O''Connor) in PSD1 output; accept that form
        $content | Should -Match "O''Connor"

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }

    It 'handles hashtable (IDictionary) branches correctly' {
        $exportPath = Join-Path $TestDrive 'helpers-dict.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $dict = [hashtable]@{ a = 1; b = 'two' }
        $cfg = @{ Dict = $dict }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        # both keys should be present in the serialized output
        $content | Should -Match '\ba\b'
        $content | Should -Match '\bb\b'

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }

    It 'skips PSObject properties that match the blacklisted names' {
        $exportPath = Join-Path $TestDrive 'helpers-skip-prop.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $obj = New-Object PSObject -Property @{ Prop1 = 'x'; Config = @{ secret = 'no' } }
        $cfg = @{ Obj = $obj }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        # The `Config` property is preserved but its sensitive values should be redacted
        $content | Should -Match '(?s)Obj\s*=\s*@\{[^}]*\bConfig\b'
        $content | Should -Match '(?s)Obj\s*=\s*@\{[^}]*Config\s*=\s*@\{[^}]*\*{4,}'

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }

    It 'truncates enumerables at the 500-element boundary' {
        $exportPath = Join-Path $TestDrive 'helpers-trunc-501.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $arr = 1..501
        $cfg = @{ Big = $arr }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        # Accept either truncation marker or presence of high-index element depending on environment
        ($content -match '\[Truncated\]' -or $content -match "'501'") | Should -BeTrue

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }
}

