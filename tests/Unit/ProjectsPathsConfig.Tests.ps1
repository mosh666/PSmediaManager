#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/ProjectModels.ps1')
}

describe 'ProjectsPathsConfig' {
    It 'FromObject maps legacy hashtable shape and ToHashtable round-trips' {
        $src = @{ Assets = 'Libraries\Assets' }

        $paths = [ProjectsPathsConfig]::FromObject($src)
        $paths.Assets | Should -Be 'Libraries\Assets'

        $roundTrip = $paths.ToHashtable()
        $roundTrip.Assets | Should -Be 'Libraries\Assets'
    }

    It 'FromObject returns input when already typed' {
        $typed = [ProjectsPathsConfig]::new('X')
        $result = [ProjectsPathsConfig]::FromObject($typed)
        $result | Should -Be $typed
    }
}
