#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<# 
    CONSOLIDATED TEST FILE
    Group A: Core Export-SafeConfiguration Functionality
    Merged from:
    - Export-SafeConfiguration.Tests.ps1 (215 lines)
    - Export-SafeConfiguration.BuildSafeSnapshot.RegistryPermutations.Tests.ps1 (31 lines)
    - Export-SafeConfiguration.Serialization.Tests.ps1 (49 lines)
    - Export-SafeConfiguration.Sanitize.Tests.ps1 (38 lines)
#>

Describe 'Export-SafeConfiguration - Core Functionality' -Tag 'unit' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $psmmManifest = Join-Path $repoRoot 'src/Modules/PSmm/PSmm.psd1'
        if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) { Remove-Module -Name PSmm -Force }
        Import-Module $psmmManifest -Force -ErrorAction Stop
        $TestOut = Join-Path $TestDrive 'safe.psd1'
    }

    Context 'Basic Configuration Export' {
        It 'writes a PSD1 including PSModules and masks sensitive tokens' {
            $cfg = @{
                Requirements = @{
                    PSModules = @('Pester','PSScriptAnalyzer')
                    PowerShell = @{ Modules = @(@{ Name='ThreadJob' }, @{ Name='PSReadLine' }) }
                }
                ErrorMessages = @{ GitHubToken = 'ghp_abc123' }
                AppVersion = '1.2.3'
            }

            $path = Export-SafeConfiguration -Configuration $cfg -Path $TestOut -Verbose:$false
            Test-Path $path | Should -BeTrue
            $content = Get-Content $path -Raw
            $content | Should -Match 'Pester'
            $content | Should -Match 'PSScriptAnalyzer'
            $content | Should -Match 'ThreadJob'
            $content | Should -Match 'PSReadLine'
            $content | Should -Not -Match 'ghp_abc123'
        }

        It 'stringifies DateTime and returns written path' {
            $cfg = @{ Timestamp = [datetime]'2025-02-03T04:05:06Z' }
            $path = Export-SafeConfiguration -Configuration $cfg -Path $TestOut -Verbose:$false
            $path | Should -Be $TestOut
            (Get-Content $path -Raw) | Should -Match '2025-02-03'
        }
    }

    Context 'Complex Configuration Structures' {
        BeforeAll {
            $script:now = Get-Date '2025-11-18T10:10:10Z'
            $script:config = [ordered]@{
                InternalName = 'PSmediaManager'
                Version = '1.2.3'
                AppVersion = 'dev'
                Paths = @{
                    Root = 'C:\App\src'
                    RepositoryRoot = 'C:\App'
                    Log  = 'C:\App\Log'
                    App  = @{
                        Root = 'C:\App\src'
                        Config = 'C:\App\src\Config'
                        ConfigDigiKam = 'C:\App\src\Config\digiKam'
                        Modules = 'C:\App\src\Modules'
                        Plugins = @{ Root = 'C:\App\Plugins'; Downloads = 'C:\App\Plugins\_Downloads'; Temp = 'C:\App\Plugins\_Temp' }
                        Vault = 'C:\App\Vault'
                    }
                }
                Logging = @{ Path = 'C:\App\Log'; Level = 'Debug'; DefaultLevel = 'Info'; Format = 'Text'; EnableConsole = $true; EnableFile = $false; MaxFileSizeMB = 5; MaxLogFiles = 3 }
                Parameters = @{ Debug = $true; Verbose = $false; Dev = $true; Update = $false }
                Storage = @{
                    1 = @{
                        GroupId = 1
                        Master = @{ Label = 'M1'; SerialNumber = 'SN-M1'; DriveLetter = 'E'; Path = 'E:\'; IsAvailable = $true; FreeSpaceGB = 100; TotalSpaceGB = 500 }
                        Backups = @{
                            'SN-B1' = @{ Label = 'B1'; SerialNumber = 'SN-B1'; DriveLetter = 'F'; Path = 'F:\'; IsAvailable = $true; FreeSpaceGB = 200; TotalSpaceGB = 500 }
                        }
                        Paths = @{ Media = 'E:\Media'; Backup = 'F:\Backup' }
                    }
                }
                StorageRegistry = @{
                    LastScanned = $script:now
                    Drives = @{
                        'SN-M1' = @{ SerialNumber = 'SN-M1'; DriveLetter = 'E'; Label = 'M1'; HealthStatus = 'Healthy'; PartitionKind = 'GPT'; FreeSpace = 100; TotalSpace = 500; UsedSpace = 400; FileSystem = 'NTFS'; Manufacturer = 'X'; Model = 'Y'; Number = 1 }
                        'SN-B1' = @{ SerialNumber = 'SN-B1'; DriveLetter = 'F'; Label = 'B1'; HealthStatus = 'Healthy'; PartitionKind = 'GPT'; FreeSpace = 200; TotalSpace = 500; UsedSpace = 300; FileSystem = 'NTFS'; Manufacturer = 'X'; Model = 'Y'; Number = 2 }
                    }
                }
                Projects = @{
                    Registry = @{
                        Master = @{ M1 = @{ Label = 'M1'; Projects = @('P1','P2') } }
                        Backup = @{ B1 = @{ Label = 'B1'; Projects = @('P3') } }
                    }
                    All = @('P1','P2','P3')
                }
                Requirements = @{
                    PSModules = @('Pester','PSReadLine')
                    PowerShell = @{
                        Modules = @(
                            @{ Name = 'ThreadJob'; RequiredVersion = '2.0.3' },
                            'Az.Accounts'
                        )
                    }
                }
                ErrorMessages = @{ E1 = 'Oops'; E2 = 'Error' }
                Timestamp = $script:now
                TokenLike = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789abcd'
            }
        }

        It 'exports configuration and creates parent directory when missing' {
            $exportPath = Join-Path -Path $TestDrive -ChildPath 'nested\subfolder\export.psd1'
            $result = Export-SafeConfiguration -Configuration $script:config -Path $exportPath

            $result | Should -Be $exportPath
            Test-Path -Path $exportPath | Should -BeTrue

            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match "^@\{"
            $content | Should -Match "'True'"
            $content | Should -Match "'False'"
            $content | Should -Match "'PSmediaManager'"
        }

        It 'masks token-like strings in exported configuration' {
            $exportPath = Join-Path -Path $TestDrive -ChildPath 'masked-export.psd1'
            $null = Export-SafeConfiguration -Configuration $script:config -Path $exportPath

            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match "TokenLike = '(?:\*{8}|ghp_\*+)'"
            $content | Should -Not -Match "ghp_abcdefghijklmnopqrstuvwxyz0123456789abcd"
        }

        It 'preserves Requirements.PSModules as array' {
            $exportPath = Join-Path -Path $TestDrive -ChildPath 'requirements-export.psd1'
            $null = Export-SafeConfiguration -Configuration $script:config -Path $exportPath

            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match "PSModules = @\('Pester', 'PSReadLine'\)"

            $imported = Import-PowerShellDataFile -Path $exportPath
            $imported.Requirements.PSModules -is [array] | Should -BeTrue
            @($imported.Requirements.PSModules).Count | Should -Be 2
        }

        It 'handles nested StorageRegistry with multiple drives' {
            $exportPath = Join-Path -Path $TestDrive -ChildPath 'storage-registry-export.psd1'
            $null = Export-SafeConfiguration -Configuration $script:config -Path $exportPath

            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match 'StorageRegistry'
            $content | Should -Match 'SN-M1'
            $content | Should -Match 'SN-B1'
            $content | Should -Match 'LastScanned'

            $imported = Import-PowerShellDataFile -Path $exportPath
            $imported.StorageRegistry.Drives.Keys -contains 'SN-M1' | Should -BeTrue
            $imported.StorageRegistry.Drives.Keys -contains 'SN-B1' | Should -BeTrue
        }

        It 'handles null and empty values gracefully' {
            $configWithNulls = @{
                InternalName = 'Test'
                Version = '1.0'
                NullValue = $null
                EmptyString = ''
                EmptyArray = @()
                EmptyHashtable = @{}
            }

            $exportPath = Join-Path -Path $TestDrive -ChildPath 'nulls-export.psd1'
            $null = Export-SafeConfiguration -Configuration $configWithNulls -Path $exportPath

            Test-Path $exportPath | Should -BeTrue
            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match 'InternalName'
        }

        It 'handles deeply nested structures up to maxdepth' {
            $deepConfig = @{
                InternalName = 'Deep'
                Version = '1.0'
                Level1 = @{
                    Level2 = @{
                        Level3 = @{
                            Level4 = @{
                                Level5 = @{
                                    Value = 'DeepValue'
                                }
                            }
                        }
                    }
                }
            }

            $exportPath = Join-Path -Path $TestDrive -ChildPath 'deep-export.psd1'
            { Export-SafeConfiguration -Configuration $deepConfig -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
        }
    }

    Context 'Masking and Token Handling' {
        It 'Masks password and GitHub token values and serializes datetimes' {
            $tmp = Join-Path $env:TEMP ("psmm-export-{0}.psd1" -f ([System.Guid]::NewGuid().ToString()))
            if (Test-Path $tmp) { Remove-Item $tmp -Force }

            $cfg = @{
                Paths = @{ Root = 'C:\App' }
                Sensitive = @{ Password = 'p@ssw0rd'; ApiKey = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD' }
                TestDate = [datetime]'2020-01-02T03:04:05Z'
            }

            Export-SafeConfiguration -Configuration $cfg -Path $tmp
            $content = Get-Content -Raw -Path $tmp

            $content | Should -Not -Match 'p@ssw0rd'
            $content | Should -Not -Match 'ghp_[A-Za-z0-9]{36}'
            $content | Should -Match "ApiKey = '(?:\*{8}|ghp_\*+)'"
            $content | Should -Match '\*{4,}'
            $content | Should -Match '2020-01-02'

            Remove-Item -Path $tmp -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - Serialization' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Mixed Data Types' {
        It 'Serializes mixed arrays and dictionaries to PSD1 correctly' {
            $exportPath = Join-Path $TestDrive 'serialization-mixed-export.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $cfg = @{
                Mixed = @(
                    'alpha',
                    @{ Key = 'Value'; Inner = @('x','y') },
                    42,
                    $true
                )
                Map = @{ A = 1; B = $false; C = @('one','two') }
            }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match "Mixed\s*="
            $content | Should -Match "Map\s*="
            $content | Should -Match "A\s*=\s*'1'|A\s*=\s*1"
            $content | Should -Match "B\s*=\s*'False'|B\s*=\s*False"

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }

    Context 'Error Handling' {
        It 'Does not fail when member access throws (GetMemberValue error path)' {
            $exportPath = Join-Path $TestDrive 'serialization-broken-member.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $obj = New-Object PSObject
            $obj | Add-Member -MemberType ScriptProperty -Name Broken -Value { throw 'boom-access' }

            $cfg = @{ Problem = $obj }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue

            $content = Get-Content -Path $exportPath -Raw
            $content | Should -Match 'Problem'
            $content | Should -Not -Match 'boom-access'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}

Describe 'Export-SafeConfiguration - Sanitization' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Sensitive Data Redaction' {
        It 'redacts sensitive keys, masks GitHub tokens, and preserves scalar formatting' {
            $exportPath = Join-Path -Path $TestDrive -ChildPath 'sanitize-output.psd1'

            $token = 'ghp_' + ('a' * 40)
            $audit = [pscustomobject]@{
                Token = $token
                Password = 'Pa55w0rd!'
                Timestamp = [datetime]::UtcNow
                Duration = [timespan]::FromMinutes(90)
            }
            $audit | Add-Member -MemberType NoteProperty -Name Loop -Value $audit

            $config = @{
                Metadata = @{
                    Secret = 'top-secret'
                    ApiKey = 'xyz'
                    Nested = @{ Credential = 'abc123' }
                }
                Audit = $audit
            }

            Export-SafeConfiguration -Configuration $config -Path $exportPath
            $imported = Import-PowerShellDataFile -Path $exportPath

            $imported.Metadata.Secret | Should -Be '********'
            $imported.Metadata.ApiKey | Should -Be '********'
            $imported.Metadata.Nested.Credential | Should -Be '********'

            $imported.Audit.Token | Should -Match "ghp_\*+"
            $imported.Audit.Password | Should -Be '********'
            $imported.Audit.Timestamp | Should -Match '\d{4}-\d{2}-\d{2}T'
            $imported.Audit.Duration | Should -Be '01:30:00'
            $imported.Audit.Loop | Should -Be '[CyclicRef]'
        }
    }
}

Describe 'Export-SafeConfiguration - Registry Structures' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    Context 'Master/Backup Registry Handling' {
        It 'serializes registry-shaped inputs with nested Master/Backup structures' {
            $exportPath = Join-Path $TestDrive 'registry-perms.psd1'
            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

            $registry = @{
                Master = @{
                    M1 = @{ Label = 'M1'; Path = 'X:\Projects\P1'; SerialNumber = 'SN-M1' }
                }
                Backup = @{
                    B1 = @{ Label = 'B1'; Path = 'Y:\Archive'; SerialNumber = 'SN-B1' }
                }
                ProjectDirs = @{ P1 = 'X:\Projects\P1' }
            }

            $cfg = @{ Projects = @{ Registry = $registry } }

            { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
            Test-Path $exportPath | Should -BeTrue
            $content = Get-Content -Path $exportPath -Raw

            $content | Should -Match '\bRegistry\b'
            $content | Should -Match '\bMaster\b'
            $content | Should -Match 'SN-M1'
            $content | Should -Match 'SN-B1'

            Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
        }
    }
}
