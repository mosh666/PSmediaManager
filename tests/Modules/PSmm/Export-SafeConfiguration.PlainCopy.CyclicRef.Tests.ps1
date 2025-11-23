Describe 'Export-SafeConfiguration - _PlainCopy cyclic reference detection' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        & (Join-Path $repoRoot 'tests/Support/Import-PSmmClasses.ps1') -RepositoryRoot $repoRoot
        $psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        if (Get-Module -Name 'PSmm' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm' -Force }
        Import-Module -Name $psmmManifest -Force -ErrorAction Stop
    }

    It 'completes export when configuration contains cyclic references (does not throw)' {
        # use a plain hashtable so we can create cyclic structures freely
        $a = @{}
        $a.Self = $a
        $config = @{ TestCyclic = $a }

        $outPath = Join-Path -Path $env:TEMP -ChildPath 'psmm-safe-cyclic.psd1'
        if (Test-Path -Path $outPath) { Remove-Item -Path $outPath -Force }

        { Export-SafeConfiguration -Configuration $config -Path $outPath } | Should -Not -Throw
        Test-Path -Path $outPath | Should -BeTrue
    }
}
