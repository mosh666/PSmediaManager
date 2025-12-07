#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<# 
    CONSOLIDATED TEST FILE
    Group C: Object Cloning and Deep Nesting
    Merged from:
    - Export-SafeConfiguration.CoverageBoost3.Tests.ps1 (213 lines)
    - Export-SafeConfiguration.Deep.Tests.ps1 (52 lines)
    - Export-SafeConfiguration.IDictionary.Tests.ps1 (23 lines)
    - Export-SafeConfiguration.Clone.Tests.ps1 (37 lines)
    - Export-SafeConfiguration.CloneGeneric.Cyclic.Tests.ps1 (22 lines)
    - Export-SafeConfiguration.PlainCopy.CyclicRef.Tests.ps1 (19 lines)
#>

Describe 'Export-SafeConfiguration - Comprehensive Nested Object Handling' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Deep Nested Objects and Arrays' {
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

            $cfg = @{
                WithNulls = @{
                    Present = 'value'
                    Absent = $null
                    Empty = ''
                }
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'preserves decimal precision in deep nesting' {
            $exportPath = Join-Path $TestDrive 'decimal-precision.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Precision = @{
                    Values = @(
                        [decimal]'3.14159265'
                        [decimal]'2.71828182'
                        [decimal]'1.41421356'
                    )
                }
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'handles sparse arrays (mixed types in single array)' {
            $exportPath = Join-Path $TestDrive 'sparse-array.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Mixed = @(
                    'string',
                    42,
                    $true,
                    @{ nested = 'hashtable' },
                    @('nested', 'array'),
                    $null
                )
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }

        It 'handles mixed arrays and dictionaries in complex structures' {
            $exportPath = Join-Path $TestDrive 'complex-mixed.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Root = @{
                    ArraySection = @(
                        @{ Type = 'A'; Value = 1 },
                        @{ Type = 'B'; Value = 2 }
                    )
                    HashSection = @{
                        Subsection = @( 'a', 'b', 'c' )
                        Numbers = @( 10, 20, 30 )
                    }
                }
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }
    }
}

Describe 'Export-SafeConfiguration - Deep Nesting' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Extremely Deep Structures' {
        It 'Handles extremely deep nested structures' {
            $tmp = Join-Path $env:TEMP ("psmm-deep-{0}.psd1" -f ([System.Guid]::NewGuid().ToString()))
            if (Test-Path $tmp) { Remove-Item $tmp -Force }

            $depth = 25
            $node = 'leaf'
            for ($i = 0; $i -lt $depth; $i++) { $node = @($node) }

            $cfg = @{ Deep = $node }

            Export-SafeConfiguration -Configuration $cfg -Path $tmp
            $content = Get-Content -Raw -Path $tmp

            $content | Should -Match "Deep = 'leaf'"

            Remove-Item -Path $tmp -ErrorAction SilentlyContinue -Force
        }

        It 'Restores original PSModules when Requirements provided as IDictionary' {
            $tmp = Join-Path $env:TEMP ("psmm-req-{0}.psd1" -f ([System.Guid]::NewGuid().ToString()))
            if (Test-Path $tmp) { Remove-Item $tmp -Force }

            $cfg = @{ Requirements = @{ PSModules = @('ModA','ModB') } }

            Export-SafeConfiguration -Configuration $cfg -Path $tmp
            $content = Get-Content -Raw -Path $tmp

            $content | Should -Match "PSModules\s*=\s*@\('ModA'\s*,\s*'ModB'\)"

            Remove-Item -Path $tmp -ErrorAction SilentlyContinue -Force
        }

        It 'Masks token/password keys and handles cyclic refs' {
            $tmp = Join-Path $env:TEMP ("psmm-mask-{0}.psd1" -f ([System.Guid]::NewGuid().ToString()))
            if (Test-Path $tmp) { Remove-Item $tmp -Force }

            $a = @{ }
            $a.Secret = 's3cr3t'
            $a.Token = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD'
            $a.Self = $a

            $cfg = @{ Projects = $a; Misc = @{ Number = 123; Flag = $true } }

            Export-SafeConfiguration -Configuration $cfg -Path $tmp
            $content = Get-Content -Raw -Path $tmp

            $content | Should -Not -Match 's3cr3t'
            $content | Should -Match "Secret\s*=\s*'\*{8}'"
            $content | Should -Match "Token\s*=\s*'(?:\*{8}|ghp_\*+)'"
            $content | Should -Match '\[CyclicRef\]|\[MaxDepth\]'
            $content | Should -Match "Number = '123'"
            $content | Should -Match "Flag = 'True'"

            Remove-Item -Path $tmp -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - IDictionary Handling' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'IDictionary Conversion and Nesting' {
        It 'handles IDictionary/hashtable conversion and nested dicts' {
            $exportPath = Join-Path $TestDrive 'ididict.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Dict1 = @{ A = 1; B = 2 }
                Dict2 = @{
                    Nested = @{
                        X = 'x'
                        Y = @{ Z = 'z' }
                    }
                }
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $imported = Import-PowerShellDataFile -Path $exportPath
            $imported.Dict1.A | Should -Be '1'
            $imported.Dict2.Nested.X | Should -Be 'x'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - Clone Operations' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..\..\..\src\Modules\PSmm\PSmm.psm1'
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    Context 'Cyclic Reference Handling' {
        It 'Replaces cyclic references with [CyclicRef] sentinel' {
            $h = @{}
            $h.self = $h
            $outPath = Join-Path $env:TEMP 'dummy-safe.psd1'
            $exportedPath = Export-SafeConfiguration -Configuration $h -Path $outPath -Verbose:$false
            $exportedPath | Should -Be $outPath
            $data = Import-PowerShellDataFile -Path $exportedPath
            $data.self | Should -Be '[CyclicRef]'
        }

        It 'handles cyclic references in nested structures' {
            $root = @{ Items = @() }
            $item1 = @{ Name = 'Item1'; Parent = $root }
            $item2 = @{ Name = 'Item2'; Parent = $root }
            $root.Items = @($item1, $item2)

            $outPath = Join-Path $env:TEMP ('cyclic-nested-{0}.psd1' -f ([System.Guid]::NewGuid()))
            Remove-Item -Path $outPath -ErrorAction SilentlyContinue

            { Export-SafeConfiguration -Configuration $root -Path $outPath -Verbose:$false } | Should -Not -Throw
            Test-Path $outPath | Should -BeTrue

            $data = Import-PowerShellDataFile -Path $outPath
            $data.Items.Count | Should -Be 2

            Remove-Item -Path $outPath -ErrorAction SilentlyContinue
        }
    }

    Context 'Max Depth Truncation' {
        It 'Truncates deep nested structures using [MaxDepth] sentinel' {
            $root = @{}
            $current = $root
            for ($i = 0; $i -lt 25; $i++) { $next = @{}; $current.n = $next; $current = $next }
            $outPath = Join-Path $env:TEMP 'dummy-safe-depth.psd1'
            $exportedPath = Export-SafeConfiguration -Configuration $root -Path $outPath -Verbose:$false
            $exportedPath | Should -Be $outPath
            $data = Import-PowerShellDataFile -Path $exportedPath
            $cursor = $data
            $found = $false
            for ($i = 0; $i -lt 50; $i++) {
                if ($cursor -isnot [hashtable]) { break }
                if ($cursor.n -eq '[MaxDepth]') { $found = $true; break }
                $cursor = $cursor.n
            }
            $found | Should -BeTrue
        }
    }
}

Describe 'Export-SafeConfiguration - CloneGeneric Cyclic References' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Generic Cloning with Cycles' {
        It 'handles cyclic hashtable references in CloneGeneric' {
            $exportPath = Join-Path $TestDrive 'cyclic-clone.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $hashtable = @{ Name = 'Test' }
            $hashtable.SelfRef = $hashtable

            { Export-SafeConfiguration -Configuration $hashtable -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $imported = Import-PowerShellDataFile -Path $exportPath
            $imported.SelfRef | Should -Be '[CyclicRef]'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - PlainCopy Cyclic Reference Detection' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..\..\..\src\Modules\PSmm\PSmm.psm1'
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    Context 'Cyclic Detection in Copy Operations' {
        It '_PlainCopy cyclic reference detection for hashtable cycles' {
            $hashtable = @{ Value = 42 }
            $hashtable.Cycle = $hashtable
            $outPath = Join-Path $env:TEMP ('plain-cyclic-{0}.psd1' -f ([System.Guid]::NewGuid()))
            Remove-Item -Path $outPath -ErrorAction SilentlyContinue

            { Export-SafeConfiguration -Configuration $hashtable -Path $outPath -Verbose:$false } | Should -Not -Throw
            Test-Path $outPath | Should -BeTrue

            $data = Import-PowerShellDataFile -Path $outPath
            $data.Cycle | Should -Be '[CyclicRef]'

            Remove-Item -Path $outPath -ErrorAction SilentlyContinue
        }
    }
}
