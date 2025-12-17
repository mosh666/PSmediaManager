#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/ProjectModels.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Projects/Classes/ProjectsRegistryModels.ps1')
}

describe 'ProjectsConfig' {
    It 'FromObject($null) returns defaults with non-null submodels' {
        $type = 'ProjectsConfig' -as [type]
        $type | Should -Not -BeNullOrEmpty

        $cfg = $type::FromObject($null)
        $cfg.GetType().Name | Should -Be 'ProjectsConfig'
        $cfg.Current | Should -Not -BeNullOrEmpty
        $cfg.Paths | Should -Not -BeNullOrEmpty
        $cfg.PortRegistry | Should -Not -BeNullOrEmpty
    }

    It 'FromObject maps legacy hashtable and normalizes Registry when type is available' {
        $type = 'ProjectsConfig' -as [type]
        $type | Should -Not -BeNullOrEmpty

        $src = @{
            Current = @{ Name = 'TestProject'; Path = 'C:\Projects\TestProject'; Config = 'C:\Projects\TestProject\Config'; Databases = 'C:\Projects\TestProject\Databases' }
            Paths = @{ Assets = 'C:\PSmm\Assets' }
            PortRegistry = @{ TestProject = 3311 }
            Registry = @{
                Master = @{ C = @{ Label = 'C'; Path = 'C:\'; Projects = @('TestProject') } }
                Backup = @{}
                LastScanned = [datetime]::UtcNow
                ProjectDirs = @{ 'C:\Projects' = [datetime]::UtcNow }
            }
        }

        $cfg = $type::FromObject($src)
        $cfg.Current.Name | Should -Be 'TestProject'
        $cfg.PortRegistry.GetPort('TestProject') | Should -Be 3311

        $cfg.Registry | Should -Not -BeNullOrEmpty
        $cfg.Registry.GetType().Name | Should -Be 'ProjectsRegistryCache'
        $cfg.Registry.Master['C'].GetType().Name | Should -Be 'ProjectsDriveRegistryEntry'
    }

    It 'ToHashtable provides legacy-compatible structure (including Registry passthrough hashtable)' {
        $type = 'ProjectsConfig' -as [type]
        $type | Should -Not -BeNullOrEmpty

        $cfg = $type::new()
        $cfg.Current.Name = 'X'
        $cfg.Paths.Assets = 'C:\Assets'
        $cfg.PortRegistry.SetPort('X', 3312)
        $cfg.Registry = @{ LastScanned = [datetime]::MinValue; Master = @{}; Backup = @{}; ProjectDirs = @{} }

        $ht = $cfg.ToHashtable()
        ($ht -is [hashtable]) | Should -BeTrue
        ($ht.Current -is [hashtable]) | Should -BeTrue
        ($ht.Paths -is [hashtable]) | Should -BeTrue
        ($ht.PortRegistry -is [hashtable]) | Should -BeTrue
        ($ht.Registry -is [hashtable]) | Should -BeTrue

        $ht.Current.Name | Should -Be 'X'
        $ht.Paths.Assets | Should -Be 'C:\Assets'
        $ht.PortRegistry.X | Should -Be 3312
    }

    It 'FromObject returns input when already typed' {
        $type = 'ProjectsConfig' -as [type]
        $type | Should -Not -BeNullOrEmpty

        $typed = $type::new()
        $result = $type::FromObject($typed)
        $result | Should -Be $typed
    }
}
