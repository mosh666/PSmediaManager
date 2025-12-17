#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'RequirementsConfig' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).Path
        . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/ProjectModels.ps1')

        $script:RequirementsConfigType = 'RequirementsConfig' -as [type]
        if (-not $script:RequirementsConfigType) {
            throw "Unable to resolve type [RequirementsConfig]"
        }
    }

    It 'FromObject(null) returns default instance with PowerShell bag' {
        $cfg = $script:RequirementsConfigType::FromObject($null)
        $cfg | Should -Not -BeNullOrEmpty
        $cfg.PowerShell | Should -Not -BeNullOrEmpty
    }

    It 'FromObject maps legacy hashtable shape and parses versions/modules' {
        $legacy = @{
            PowerShell = @{
                VersionMinimum = '7.5.4'
                Modules = @(
                    @{ Name = 'Pester'; Repository = 'PSGallery' },
                    @{ Name = 'PSLogs'; Repository = 'PSGallery' }
                )
            }
        }

        $cfg = $script:RequirementsConfigType::FromObject($legacy)

        $cfg.PowerShell.VersionMinimum | Should -Be ([version]'7.5.4')
        @($cfg.PowerShell.Modules).Count | Should -Be 2
        $cfg.PowerShell.Modules[0].Name | Should -Be 'Pester'
        $cfg.PowerShell.Modules[0].Repository | Should -Be 'PSGallery'
    }

    It 'ToHashtable preserves outward hashtable shape' {
        $legacy = @{
            PowerShell = @{
                VersionMinimum = '7.5.4'
                Modules = @(
                    @{ Name = 'Pester'; Repository = 'PSGallery' }
                )
            }
        }

        $cfg = $script:RequirementsConfigType::FromObject($legacy)
        $ht = $cfg.ToHashtable()

        $ht | Should -BeOfType 'hashtable'
        $ht.ContainsKey('PowerShell') | Should -BeTrue
        $ht.PowerShell.VersionMinimum | Should -Be '7.5.4'
        @($ht.PowerShell.Modules).Count | Should -Be 1
        $ht.PowerShell.Modules[0].Name | Should -Be 'Pester'
    }
}
