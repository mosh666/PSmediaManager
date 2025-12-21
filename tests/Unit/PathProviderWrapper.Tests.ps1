#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent

    # Force test-mode behavior for any path initialization.
    Set-Variable -Name '__psmm_prevTestMode' -Scope Script -Value $env:MEDIA_MANAGER_TEST_MODE -Force
    $env:MEDIA_MANAGER_TEST_MODE = '1'

    $bootstrapPath = Join-Path -Path $repoRoot -ChildPath 'src/Core/BootstrapServices.ps1'
    . $bootstrapPath

    # Load AppPaths (inner provider) dependencies for delegation tests
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Exceptions.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Services/FileSystemService.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/AppConfiguration.ps1')

    $pathProviderPath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Services/PathProvider.ps1'

    Set-Variable -Name '__psmm_PathProviderPath' -Scope Script -Value $pathProviderPath -Force
}

AfterAll {
    $env:MEDIA_MANAGER_TEST_MODE = $script:__psmm_prevTestMode
}

Describe 'PathProvider wrapper' {
    It 'Bootstrap does not define PathProvider; PSmm service file defines it' {
        ('PathProvider' -as [type]) | Should -BeNullOrEmpty

        . $script:__psmm_PathProviderPath

        ([PathProvider] -as [type]) | Should -Not -BeNullOrEmpty

        $pp = [PathProvider]::new()
        $combined = $pp.CombinePath(@('a', 'b'))

        $combined | Should -Be ([System.IO.Path]::Combine('a', 'b'))
    }

    It 'Delegates to inner IPathProvider when supplied' {
        . $script:__psmm_PathProviderPath

        $inner = [AppPaths]::new($TestDrive, $TestDrive)
        $pp = [PathProvider]::new([IPathProvider]$inner)

        $pp.CombinePath(@('x', 'y')) | Should -Be $inner.CombinePath(@('x', 'y'))
        $pp.GetPath('Root') | Should -Be $inner.GetPath('Root')
    }
}
