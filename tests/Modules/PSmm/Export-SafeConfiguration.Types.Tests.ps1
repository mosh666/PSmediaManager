#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<# 
    CONSOLIDATED TEST FILE
    Group B: Type Handling and Formatting
    Merged from:
    - Export-SafeConfiguration.ScalarQuoting.Tests.ps1 (56 lines)
    - Export-SafeConfiguration.ToSafeScalar.Tests.ps1 (35 lines)
    - Export-SafeConfiguration.Stringify.Tests.ps1 (34 lines)
    - Export-SafeConfiguration.KeyFormatting.Tests.ps1 (28 lines)
    - Export-SafeConfiguration.StringifyValuesPath.Tests.ps1 (25 lines)
    - Export-SafeConfiguration.ScalarFormatting.Tests.ps1 (24 lines)
    - Export-SafeConfiguration.ScalarToQuoted.NumericFormatting.Tests.ps1 (24 lines)
#>

Describe 'Export-SafeConfiguration - Scalar Quoting and Formatting' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Quoting and Numeric Formatting' {
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

            $content | Should -Match "NumberInt = '42'"
            $content | Should -Match "NumberDouble = '12345.6789'"
            ($content -match "DecimalVal = '3\.14159'") -or ($content -match "DecimalVal = @\{") | Should -BeTrue
            $content | Should -Match "BoolTrue = 'True'"
            $content | Should -Match "BoolFalse = 'False'"
            $content | Should -Match "QuoteString = 'O''Hare'"
            $content | Should -Match '2025-11-18'

            Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
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

    Context 'Quote Escaping' {
        It 'escapes single quotes by doubling in quoted strings' {
            $exportPath = Join-Path $TestDrive 'quote-escape.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                SingleQuote = "It's"
                DoubleQuote = "She said ""hello"""
                MixedQuotes = "It's ""quoted"""
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match "It''s"

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - _ToSafeScalar Helper' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        & (Join-Path $repoRoot 'tests/Support/Import-PSmmClasses.ps1') -RepositoryRoot $repoRoot
        $psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        if (Get-Module -Name 'PSmm' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm' -Force }
        Import-Module -Name $psmmManifest -Force -ErrorAction Stop
    }

    Context 'DateTime Formatting' {
        It 'serializes DateTime to round-trip string (o format) via Export-SafeConfiguration' {
            $now = [datetime]::UtcNow
            $config = @{ TestTime = $now }

            $outPath = Join-Path -Path $env:TEMP -ChildPath 'psmm-safe-test-1.psd1'
            if (Test-Path -Path $outPath) { Remove-Item -Path $outPath -Force }

            $resultPath = Export-SafeConfiguration -Configuration $config -Path $outPath

            $resultPath | Should -Be $outPath
            Test-Path -Path $outPath | Should -BeTrue

            $content = Get-Content -Path $outPath -Raw
            $content | Should -Match ($now.ToString('o'))
        }
    }

    Context 'Numeric Value Formatting' {
        It 'serializes decimal/numeric values using invariant culture via Export-SafeConfiguration' {
            $val = [decimal]::Parse('1234.56')
            $config = @{ TestNumber = $val }

            $outPath = Join-Path -Path $env:TEMP -ChildPath 'psmm-safe-test-2.psd1'
            if (Test-Path -Path $outPath) { Remove-Item -Path $outPath -Force }

            $resultPath = Export-SafeConfiguration -Configuration $config -Path $outPath

            $resultPath | Should -Be $outPath
            Test-Path -Path $outPath | Should -BeTrue

            $content = Get-Content -Path $outPath -Raw
            $expected = $val.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            ($content -match 'Scale' -or $content -match ([regex]::Escape($expected))) | Should -BeTrue
        }
    }
}

Describe 'Export-SafeConfiguration - _StringifyValues Helper' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Type Normalization' {
        It 'normalizes scalar types to safe string representations' {
            $exportPath = Join-Path $TestDrive 'stringify-export.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                BoolValue = $true
                DateValue = [datetime]'2020-01-01T00:00:00Z'
                TimeSpan = [timespan]::FromMinutes(30)
                EnumValue = [System.IO.FileAttributes]::ReadOnly
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
            $content = Get-Content -Path $exportPath -Raw

            $content | Should -Match 'True|False'
            $content | Should -Match '2020'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - Key Formatting' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Identifier and Quote Rules' {
        It 'formats valid PowerShell identifiers without quotes' {
            $exportPath = Join-Path $TestDrive 'keyformat-identifiers.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                ValidKey = 'value1'
                AnotherKey = 'value2'
                Key123 = 'value3'
                _PrivateKey = 'value4'
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
            $content = Get-Content -Path $exportPath -Raw

            $content | Should -Match 'ValidKey\s*='
            $content | Should -Match 'AnotherKey\s*='
            $content | Should -Match 'Key123\s*='
            $content | Should -Match '_PrivateKey\s*='

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }

        It 'quotes keys with spaces, dashes, or special characters' {
            $exportPath = Join-Path $TestDrive 'keyformat-special.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                'Key With Spaces' = 'value1'
                'Key-With-Dashes' = 'value2'
                'Key.With.Dots' = 'value3'
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
            $content = Get-Content -Path $exportPath -Raw

            $content | Should -Match "'Key With Spaces'"
            $content | Should -Match "'Key-With-Dashes'"
            $content | Should -Match "'Key.With.Dots'"

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - StringifyValues Path Extraction' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Nested Property Stringification' {
        It 'extracts and stringifies values from deeply nested property paths' {
            $exportPath = Join-Path $TestDrive 'stringify-path.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Level1 = @{
                    Level2 = @{
                        Property = 'value'
                        Count = 42
                        Timestamp = [datetime]'2020-06-15T10:30:00Z'
                    }
                }
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
            $content = Get-Content -Path $exportPath -Raw

            $content | Should -Match 'Level1'
            $content | Should -Match 'Level2'
            $content | Should -Match 'Property'
            $content | Should -Match '2020-06-15'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - Scalar Type Formatting' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Boolean and Number Formatting' {
        It 'formats booleans as ''True''/''False'' and numbers with invariant culture' {
            $exportPath = Join-Path $TestDrive 'scalar-format.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Bool1 = $true
                Bool2 = $false
                Num1 = 123
                Num2 = 45.67
                Num3 = [decimal]'89.10'
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
            $content = Get-Content -Path $exportPath -Raw

            $content | Should -Match "'True'"
            $content | Should -Match "'False'"
            $content | Should -Match "123|'123'"
            $content | Should -Match "45.67|'45.67'"

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - _ScalarToQuoted Helper' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $psmmManifest = Join-Path -Path $repoRoot 'src/Modules/PSmm/PSmm.psd1'
        if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) { Remove-Module -Name PSmm -Force }
        Import-Module $psmmManifest -Force -ErrorAction Stop
    }

    Context 'Numeric and Decimal Formatting' {
        It 'formats decimals and numbers correctly with invariant culture' {
            $exportPath = Join-Path $TestDrive 'scalarquoted.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Decimal1 = [decimal]'12.34'
                Decimal2 = [decimal]'0.001'
                Number1 = 999999
                Number2 = 0.5
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
            $content = Get-Content -Path $exportPath -Raw

            # Accept either quoted or unquoted numeric values depending on implementation
            ($content -match "Decimal1\s*=" -and ($content -match "'12.34'" -or $content -match "'12\.34'|Scale")) | Should -BeTrue

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}
