#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration' -Tag 'unit' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $psmmManifest = Join-Path $repoRoot 'src/Modules/PSmm/PSmm.psd1'
        if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) { Remove-Module -Name PSmm -Force }
        Import-Module $psmmManifest -Force -ErrorAction Stop
        $TestOut = Join-Path $TestDrive 'safe.psd1'
    }

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
        # Allow timezone/localization differences; assert date portion appears
        (Get-Content $path -Raw) | Should -Match '2025-02-03'
    }
}
Describe 'Export-SafeConfiguration' {
    BeforeAll {
        # Dot-source the implementation so the exported function is available
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

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

        # Ensure original secret value is not present
        $content | Should -Not -Match 'p@ssw0rd'

        # Token pattern should not contain the original token and ApiKey should be masked
        $content | Should -Not -Match 'ghp_[A-Za-z0-9]{36}'
        $content | Should -Match "ApiKey = '(?:\*{8}|ghp_\*+)'"

        # Confirm at least a short star sequence exists for masked passwords
        $content | Should -Match '\*{4,}'

        # Date should be serialized (date portion should appear)
        $content | Should -Match '2020-01-02'

        Remove-Item -Path $tmp -ErrorAction SilentlyContinue -Force
    }

}
#Requires -Version 7.5.4
Set-StrictMode -Version Latest

$script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
$script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'

if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) {
    Remove-Module -Name PSmm -Force
}
Import-Module -Name $script:psmmManifest -Force -ErrorAction Stop

Describe 'Export-SafeConfiguration' {
    BeforeAll {
        # Build a rich synthetic configuration to exercise many code paths
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
            # Include a token-like string to ensure masking
            TokenLike = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789abcd'
        }
    }

    It 'exports configuration and creates parent directory when missing' {
        $exportPath = Join-Path -Path $TestDrive -ChildPath 'nested\subfolder\export.psd1'

        $result = PSmm\Export-SafeConfiguration -Configuration $script:config -Path $exportPath

        $result | Should -Be $exportPath
        Test-Path -Path $exportPath | Should -BeTrue

        $content = Get-Content -Path $exportPath -Raw
        $content | Should -Match "^@\{"
        # Verify single-quoted string serialization
        $content | Should -Match "'True'"
        $content | Should -Match "'False'"
        $content | Should -Match "'PSmediaManager'"
    }

    It 'masks token-like strings in exported configuration' {
        $exportPath = Join-Path -Path $TestDrive -ChildPath 'masked-export.psd1'

        $null = PSmm\Export-SafeConfiguration -Configuration $script:config -Path $exportPath

        $content = Get-Content -Path $exportPath -Raw
        # Token should be masked (shown as '********' or ghp_**************** when preserving prefix)
        $content | Should -Match "TokenLike = '(?:\*{8}|ghp_\*+)'"
        # Original token should NOT appear
        $content | Should -Not -Match "ghp_abcdefghijklmnopqrstuvwxyz0123456789abcd"
    }

    It 'preserves Requirements.PSModules as array' {
        $exportPath = Join-Path -Path $TestDrive -ChildPath 'requirements-export.psd1'

        $null = PSmm\Export-SafeConfiguration -Configuration $script:config -Path $exportPath

        $content = Get-Content -Path $exportPath -Raw
        # Verify array syntax in exported PSD1
        $content | Should -Match "PSModules = @\('Pester', 'PSReadLine'\)"

        # Verify import preserves array structure
        $imported = Import-PowerShellDataFile -Path $exportPath
        $imported.Requirements.PSModules -is [array] | Should -BeTrue
        @($imported.Requirements.PSModules).Count | Should -Be 2
    }

    It 'handles nested StorageRegistry with multiple drives' {
        $exportPath = Join-Path -Path $TestDrive -ChildPath 'storage-registry-export.psd1'

        $null = PSmm\Export-SafeConfiguration -Configuration $script:config -Path $exportPath

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
        $null = PSmm\Export-SafeConfiguration -Configuration $configWithNulls -Path $exportPath

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
        { PSmm\Export-SafeConfiguration -Configuration $deepConfig -Path $exportPath } | Should -Not -Throw

        Test-Path $exportPath | Should -BeTrue
    }
}
