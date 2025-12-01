#Requires -Version 7.5.4
Set-StrictMode -Version Latest

$script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
$script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'

if (Get-Module -Name PSmm -ErrorAction SilentlyContinue) {
    Remove-Module -Name PSmm -Force
}
Import-Module -Name $script:psmmManifest -Force -ErrorAction Stop

Describe 'New-DirectoriesFromHashtable' {
    InModuleScope PSmm {
        It 'creates nested directory structure for absolute paths' {
            $root = Join-Path -Path $TestDrive -ChildPath 'App'
            $paths = @{
                Root = $root
                Logs = Join-Path $root 'Logs'
                Data = @{
                    Input  = Join-Path $root 'Data/Input'
                    Output = Join-Path $root 'Data/Output'
                }
                SkippedNumber = 42
            }

            { New-DirectoriesFromHashtable -Structure $paths -Verbose } | Should -Not -Throw

            Test-Path -Path $root -PathType Container | Should -BeTrue
            Test-Path -Path (Join-Path $root 'Logs') -PathType Container | Should -BeTrue
            Test-Path -Path (Join-Path $root 'Data/Input') -PathType Container | Should -BeTrue
            Test-Path -Path (Join-Path $root 'Data/Output') -PathType Container | Should -BeTrue
        }

        It 'skips relative and invalid paths without throwing' {
            $root = Join-Path -Path $TestDrive -ChildPath 'App2'
            $paths = @{
                Root = $root
                Relative = 'relative/path'
                Invalid  = '::invalid::path::'
            }

            { New-DirectoriesFromHashtable -Structure $paths -Verbose } | Should -Not -Throw
            Test-Path -Path $root -PathType Container | Should -BeTrue
        }

        It 'skips directories that already exist' {
            $existingDir = Join-Path -Path $TestDrive -ChildPath 'ExistingDir'
            $null = New-Item -Path $existingDir -ItemType Directory -Force
            $paths = @{ Existing = $existingDir }

            { New-DirectoriesFromHashtable -Structure $paths -Verbose } | Should -Not -Throw
            Test-Path -Path $existingDir -PathType Container | Should -BeTrue
        }

        It 'handles empty hashtable without errors' {
            $emptyPaths = @{}
            { New-DirectoriesFromHashtable -Structure $emptyPaths } | Should -Not -Throw
        }

        It 'creates deeply nested directory trees' {
            $root = Join-Path -Path $TestDrive -ChildPath 'DeepNest'
            $deepPath = Join-Path $root 'Level1/Level2/Level3/Level4/Level5'
            $paths = @{ DeepPath = $deepPath }

            { New-DirectoriesFromHashtable -Structure $paths } | Should -Not -Throw
            Test-Path -Path $deepPath -PathType Container | Should -BeTrue
        }

        It 'handles paths with trailing slashes' {
            $root = Join-Path -Path $TestDrive -ChildPath 'TrailingSlash'
            $pathWithSlash = $root + '\'
            $paths = @{ Root = $pathWithSlash }

            { New-DirectoriesFromHashtable -Structure $paths } | Should -Not -Throw
            Test-Path -Path $root -PathType Container | Should -BeTrue
        }

        It 'processes multiple levels of nested hashtables' {
            $root = Join-Path -Path $TestDrive -ChildPath 'MultiLevel'
            $paths = @{
                Root = $root
                Level1 = @{
                    Level2 = @{
                        Level3 = Join-Path $root 'L1/L2/L3'
                    }
                    Sibling = Join-Path $root 'L1/Sibling'
                }
            }

            { New-DirectoriesFromHashtable -Structure $paths } | Should -Not -Throw
            Test-Path -Path $root -PathType Container | Should -BeTrue
            Test-Path -Path (Join-Path $root 'L1/L2/L3') -PathType Container | Should -BeTrue
            Test-Path -Path (Join-Path $root 'L1/Sibling') -PathType Container | Should -BeTrue
        }

        It 'writes warning when directory creation fails' {
            Mock Write-Warning { param($Message) } -ModuleName PSmm
            Mock New-Item { throw 'creation failed' } -ModuleName PSmm

            $path = Join-Path -Path $TestDrive -ChildPath 'WarnOnFailure'
            $paths = @{ Warn = $path }

            { New-DirectoriesFromHashtable -Structure $paths -Verbose } | Should -Not -Throw
            Should -Invoke Write-Warning -ModuleName PSmm -ParameterFilter { $Message -like "Failed to create directory*" } -Times 1
        }
    }
}
