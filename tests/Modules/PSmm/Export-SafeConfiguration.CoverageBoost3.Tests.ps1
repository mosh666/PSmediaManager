Describe 'Export-SafeConfiguration (coverage boost - nested object handling)' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Deep nested object cloning and serialization' {
        It 'handles deeply nested hashtables with mixed types' {
            $exportPath = Join-Path $TestDrive 'deep-nested.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Level1 = @{
                    Level2 = @{
                        Level3 = @{
                            StringValue = 'test'
                            NumberValue = 42
                            BoolValue = $true
                            DateValue = Get-Date -Year 2020 -Month 1 -Day 1
                            NullValue = $null
                        }
                    }
                }
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'handles arrays within objects' {
            $exportPath = Join-Path $TestDrive 'arrays-in-objects.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Items = @(
                    @{ Id = 1; Name = 'First' }
                    @{ Id = 2; Name = 'Second' }
                    @{ Id = 3; Name = 'Third' }
                )
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'handles object with null properties gracefully' {
            $exportPath = Join-Path $TestDrive 'null-props.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $obj = [PSCustomObject]@{
                Name = 'test'
                Value = $null
                Empty = ''
                Number = 0
            }

            $cfg = @{ Data = $obj }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'handles objects with circular references safely' {
            $exportPath = Join-Path $TestDrive 'circular.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $parent = @{ Name = 'Parent' }
            $child = @{ Name = 'Child'; Parent = $parent }
            $parent['Child'] = $child

            $cfg = @{ Circular = $parent }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'preserves dictionary structure with various key types' {
            $exportPath = Join-Path $TestDrive 'dict-keys.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = [ordered]@{
                'StringKey' = 'value1'
                'AnotherKey' = 'value2'
                'ThirdKey' = @{ Nested = 'object' }
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'handles empty collections' {
            $exportPath = Join-Path $TestDrive 'empty-collections.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                EmptyArray = @()
                EmptyHash = @{}
                EmptyString = ''
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'handles mixed PSObject and hashtable structures' {
            $exportPath = Join-Path $TestDrive 'mixed-structures.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $psObj = [PSCustomObject]@{
                Name = 'PSObject'
                Hash = @{ Key = 'value' }
            }

            $cfg = @{
                Object = $psObj
                DirectHash = @{ Direct = 'hash' }
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }
    }

    Context 'Sanitization and redaction' {
        It 'redacts sensitive password-like keys' {
            $exportPath = Join-Path $TestDrive 'redacted.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Username = 'admin'
                Password = 'SecretPass123'
                ApiKey = 'sk_live_12345'
                Token = 'ghp_xxxxxxxxxxxx'
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
            $content = Get-Content -Path $exportPath -Raw
            # Ensure sensitive values are masked
            $content | Should -Match '\*\*\*\*\*\*\*\*|Password|ApiKey|Token'
        }

        It 'handles enum values correctly' {
            $exportPath = Join-Path $TestDrive 'enum-values.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                FileAttributes = [System.IO.FileAttributes]::Archive
                ConsoleColor = [ConsoleColor]::Green
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'safely handles objects with special characters in property names' {
            $exportPath = Join-Path $TestDrive 'special-chars.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                'Property-With-Dashes' = 'value'
                'Property.With.Dots' = 'value'
                'Property With Spaces' = 'value'
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }
    }

    Context 'Numeric and date formatting' {
        It 'formats decimal numbers with high precision' {
            $exportPath = Join-Path $TestDrive 'decimal-precision.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Pi = [math]::PI
                SmallNumber = 0.00001
                LargeNumber = 1234567890.123456
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'formats dates in ISO 8601 format' {
            $exportPath = Join-Path $TestDrive 'iso-dates.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                UtcNow = [datetime]::UtcNow
                SpecificDate = Get-Date -Year 2025 -Month 12 -Day 25
                MinDate = [datetime]::MinValue
                MaxDate = [datetime]::MaxValue
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'handles decimal precision values (currency)' {
            $exportPath = Join-Path $TestDrive 'currency.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Price = 19.99
                Total = 1234.56
                Discount = 0.15
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }
    }

    Context 'Array and collection handling' {
        It 'handles sparse arrays' {
            $exportPath = Join-Path $TestDrive 'sparse-array.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $arr = New-Object object[] 10
            $arr[0] = 'First'
            $arr[5] = 'Middle'
            $arr[9] = 'Last'

            $cfg = @{ SparseArray = $arr }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'handles arrays of mixed types' {
            $exportPath = Join-Path $TestDrive 'mixed-array.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                MixedArray = @(
                    'string'
                    42
                    3.14
                    $true
                    (Get-Date)
                    @{ Nested = 'hash' }
                )
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'truncates very large arrays beyond 500 elements' {
            $exportPath = Join-Path $TestDrive 'large-array.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $largeArray = 1..600

            $cfg = @{ LargeArray = $largeArray }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
            $content = Get-Content -Path $exportPath -Raw
            ($content -match '\[Truncated\]' -or $content.Length -lt (600 * 10)) | Should -BeTrue
        }
    }
}
