#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration (module descriptors)' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'normalizes string and PSCustomObject descriptors' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'module-descriptors.psd1'

        $complex = New-Object PSObject -Property @{
            Name = ' Complex '
            Versions = @(' 1.0 ', '2.0')
            Metadata = @{ Path = '  C:\Temp  ' }
        }
        $complex | Add-Member -MemberType ScriptProperty -Name Broken -Value { throw 'broken-access' }

        $config = @{
            Requirements = @{
                PowerShell = @{
                    Modules = @('  SimpleModule  ', $complex)
                }
            }
        }

        Export-SafeConfiguration -Configuration $config -Path $outputPath
        $imported = Import-PowerShellDataFile -Path $outputPath

        $modules = @($imported.Requirements.PowerShell.Modules)
        $modules.Count | Should -Be 2

        $modules[0].Length | Should -Be '16'

        $modules[1].Name | Should -Be 'Complex'
        @($modules[1].Versions)[0] | Should -Be '1.0'
        @($modules[1].Versions)[1] | Should -Be '2.0'
        $modules[1].Metadata.Path | Should -Be 'C:\Temp'
        $modules[1].Broken | Should -Be ''
    }

    It 'wraps scalar descriptors and returns empty list for null modules' {
        $scalarPath = Join-Path -Path $TestDrive -ChildPath 'module-descriptor-scalar.psd1'

        $scalarConfig = @{
            Requirements = @{
                PowerShell = @{ Modules = '  SoloModule  ' }
            }
        }

        Export-SafeConfiguration -Configuration $scalarConfig -Path $scalarPath
        $scalarImport = Import-PowerShellDataFile -Path $scalarPath

        $scalarModules = @($scalarImport.Requirements.PowerShell.Modules)
        $scalarModules.Count | Should -Be 1
        $scalarModules[0].Length | Should -Be '14'

        $nullPath = Join-Path -Path $TestDrive -ChildPath 'module-descriptor-null.psd1'

        $nullConfig = @{
            Requirements = @{
                PowerShell = @{ Modules = @($null, $null) }
            }
        }

        Export-SafeConfiguration -Configuration $nullConfig -Path $nullPath
        $nullImport = Import-PowerShellDataFile -Path $nullPath

        @($nullImport.Requirements.PowerShell.Modules).Count | Should -Be 0
    }
}
