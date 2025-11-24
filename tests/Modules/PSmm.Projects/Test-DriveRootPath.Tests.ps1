#Requires -Version 7.5.4
Set-StrictMode -Version Latest

$localRepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
$manifestPath = Join-Path -Path $localRepoRoot -ChildPath 'src/Modules/PSmm.Projects/PSmm.Projects.psd1'

if (Get-Module -Name 'PSmm.Projects' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'PSmm.Projects' -Force
}
Import-Module -Name $manifestPath -Force -ErrorAction Stop

Describe 'Test-DriveRootPath' {
    InModuleScope 'PSmm.Projects' {
        BeforeAll {
            function New-FsStub {
                param(
                    [scriptblock]$TestPathImpl
                )
                $fs = [pscustomobject]@{}
                $impl = $TestPathImpl
                $sb = {
                    param([string]$Path)
                    & $impl -Path $Path
                }
                $psm = New-Object System.Management.Automation.PSScriptMethod('TestPath', $sb)
                [void]$fs.PSObject.Methods.Add($psm)
                return $fs
            }
            # Publish to global scope to ensure availability across It blocks
            $fn = (Get-Command New-FsStub -CommandType Function).ScriptBlock
            Set-Item -Path 'function:\global:New-FsStub' -Value $fn -Force
        }

        It 'returns false for null/empty drive' {
            Test-DriveRootPath -DriveLetter '' -FileSystem (New-FsStub { $false }) | Should -BeFalse
            Test-DriveRootPath -DriveLetter $null -FileSystem (New-FsStub { $false }) | Should -BeFalse
        }

        It "returns true via fallback when 'E:\\' exists for 'E:'" {
            Mock Test-Path {
                param($Path)
                return ($Path -eq 'E:\\')
            }
            Test-DriveRootPath -DriveLetter 'E:' -FileSystem $null | Should -BeTrue
        }

        It "returns true via fallback when 'F:' exists for 'F\\'" {
            Mock Test-Path {
                param($Path)
                return ($Path -eq 'F:' -or $Path -eq 'F:\\')
            }
            Test-DriveRootPath -DriveLetter 'F:\\' -FileSystem $null | Should -BeTrue
        }

        It 'continues on TestPath exceptions and returns false when none match' {
            $calls = 0
            $fs = New-FsStub {
                param($Path)
                $script:calls++
                throw 'boom'
            }
            Test-DriveRootPath -DriveLetter 'G:' -FileSystem $fs | Should -BeFalse
        }

        It 'falls back to Test-Path when FileSystem is absent' {
            # Force Test-Path to return false for candidates regardless of environment
            Mock Test-Path { $false }
            Test-DriveRootPath -DriveLetter 'Z:' -FileSystem $null | Should -BeFalse
        }
    }
}
