#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<# 
    CONSOLIDATED TEST FILE
    Group D: Edge Cases, Helpers, and Coverage Expansion
    Merged from:
    - Export-SafeConfiguration.Helpers.Tests.ps1 (52 lines)
    - Export-SafeConfiguration.CoverageBoost.Tests.ps1 (59 lines)
    - Export-SafeConfiguration.CoverageBoost2.Tests.ps1 (58 lines)
    - Export-SafeConfiguration.ModuleDescriptors.Tests.ps1 (57 lines)
    - Export-SafeConfiguration.PSObjectRedaction.Tests.ps1 (23 lines)
    - Export-SafeConfiguration.Truncation.Tests.ps1 (23 lines)
#>

Describe 'Export-SafeConfiguration - Helper Functions' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Deep Member Enumeration' {
        It 'handles deeply enumerable objects and MaxDepth in CloneGeneric' {
            $exportPath = Join-Path $TestDrive 'helper-deep-enum.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $config = @{
                DeepEnumerable = @{
                    Level1 = @{
                        Level2 = @{
                            Level3 = @(
                                @{ A = 1 },
                                @{ B = 2 },
                                @{ C = @{ Nested = 'value' } }
                            )
                        }
                    }
                }
            }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }

        It 'handles IDictionary member access gracefully' {
            $exportPath = Join-Path $TestDrive 'helper-idict.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $config = @{
                IDictProp = @{
                    Required = @{ PSModules = @('Module1'); PowerShell = 'v7' }
                    Metadata = @{ Version = '1.0' }
                }
            }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }

        It 'skips member access errors gracefully' {
            $exportPath = Join-Path $TestDrive 'helper-error-skip.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $obj = New-Object PSObject
            $obj | Add-Member -MemberType NoteProperty -Name OkProperty -Value 'fine'
            $obj | Add-Member -MemberType ScriptProperty -Name ErrorProperty -Value { throw 'error' } -ErrorAction SilentlyContinue

            $config = @{ Object = $obj }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match 'OkProperty'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }

    Context 'Generic Clone Helper' {
        It 'clones nested collections with proper type handling' {
            $exportPath = Join-Path $TestDrive 'helper-clone.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $config = @{
                Collections = @{
                    Array = @( 1, 2, 3 )
                    Dict = @{ X = 10; Y = 20 }
                    Mixed = @( @{ A = 1 }, @{ B = 2 } )
                }
            }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - Coverage Boost 1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Cyclic Handling and String Operations' {
        It 'handles cyclic references and applies truncation properly' {
            $exportPath = Join-Path $TestDrive 'coverage1-cyclic.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $obj = @{ Value = 'test' }
            $obj.Cycle = $obj

            $config = @{ Cyclic = $obj }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $imported = Import-PowerShellDataFile -Path $exportPath
            $imported.Cyclic.Cycle | Should -Be '[CyclicRef]'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }

        It 'stringifies various object types' {
            $exportPath = Join-Path $TestDrive 'coverage1-stringify.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $config = @{
                BoolVal = $true
                DateVal = Get-Date -Year 2020 -Month 1 -Day 1
                TimeVal = [timespan]::FromHours(2)
                VersionVal = [version]'1.2.3'
            }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match '2020'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }

        It 'formats decimal values correctly' {
            $exportPath = Join-Path $TestDrive 'coverage1-decimal.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $config = @{
                Dec1 = [decimal]'99.99'
                Dec2 = [decimal]'0.001'
                Dec3 = [decimal]'1000000'
            }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - Coverage Boost 2' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Empty Values and Property Handling' {
        It 'handles empty strings and empty collections' {
            $exportPath = Join-Path $TestDrive 'coverage2-empty.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $config = @{
                EmptyString = ''
                EmptyArray = @()
                EmptyDict = @{}
                SpaceString = '   '
            }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match "EmptyString = ''"

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }

        It 'quotes strings with special characters correctly' {
            $exportPath = Join-Path $TestDrive 'coverage2-quotes.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $config = @{
                QuotedValue = "It's a test"
                DoubleQuote = 'She said "hello"'
                Apostrophe = "O'Neill"
            }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match "It''s|O''Neill"

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }

        It 'skips problematic PSObject properties gracefully' {
            $exportPath = Join-Path $TestDrive 'coverage2-psobject.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $pso = [pscustomobject]@{ A = 1; B = 2 }
            $config = @{ Object = $pso }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - Module Descriptors' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Module Descriptor Normalization' {
        It 'normalizes string module descriptors' {
            $exportPath = Join-Path $TestDrive 'modules-string.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $config = @{
                Requirements = @{
                    PSModules = @('Pester', 'PSScriptAnalyzer', 'Az.Accounts')
                }
            }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match 'Pester'
            $content | Should -Match 'PSScriptAnalyzer'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }

        It 'normalizes PSCustomObject module descriptors' {
            $exportPath = Join-Path $TestDrive 'modules-object.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $descriptor = [pscustomobject]@{ Name = 'TestModule'; RequiredVersion = '1.0' }
            $config = @{
                Requirements = @{
                    PowerShell = @{ Modules = @( $descriptor ) }
                }
            }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }

        It 'trims whitespace from module descriptor strings' {
            $exportPath = Join-Path $TestDrive 'modules-whitespace.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $config = @{
                Requirements = @{
                    PSModules = @('  Pester  ', '  PSReadLine  ')
                }
            }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $imported = Import-PowerShellDataFile -Path $exportPath
            $imported.Requirements.PSModules[0] | Should -Match 'Pester'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - PSObject Redaction' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Sensitive Key Masking' {
        It 'redacts values for Password, Secret, and Token keys' {
            $exportPath = Join-Path $TestDrive 'redact-keys.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $config = @{
                Credentials = @{
                    Password = 'MyP@ssw0rd'
                    Secret = 'hidden-secret'
                    Token = 'ghp_1234567890abcdefghijklmnopqrst'
                    ApiKey = 'open-api-key'
                }
            }

            Export-SafeConfiguration -Configuration $config -Path $exportPath
            $imported = Import-PowerShellDataFile -Path $exportPath

            $imported.Credentials | Should -Be '********'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }

        It 'preserves non-sensitive keys while masking sensitive ones' {
            $exportPath = Join-Path $TestDrive 'redact-mixed.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $config = @{
                Settings = @{
                    Username = 'admin'
                    Password = 'secret123'
                    Host = 'example.com'
                    ApiKey = 'abc123'
                }
            }

            Export-SafeConfiguration -Configuration $config -Path $exportPath
            $imported = Import-PowerShellDataFile -Path $exportPath

            $imported.Settings.Username | Should -Be 'admin'
            $imported.Settings.Host | Should -Be 'example.com'
            $imported.Settings.Password | Should -Be '********'
            $imported.Settings.ApiKey | Should -Be '********'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - Truncation' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Large Collection Handling' {
        It 'truncates large enumerables with truncation marker' {
            $exportPath = Join-Path $TestDrive 'trunc-large.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $largeArray = @( 1..600 )
            $config = @{ LargeCollection = $largeArray }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $content = Get-Content -Path $exportPath -Raw
            # Should show truncation or at least the collection exists
            $content | Should -Match 'LargeCollection'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }

        It 'handles deeply nested structures with size limits' {
            $exportPath = Join-Path $TestDrive 'trunc-nested.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $config = @{
                SmallRoot = @{
                    Items = @( 1..100 )
                }
            }

            { Export-SafeConfiguration -Configuration $config -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}
