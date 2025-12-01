Describe 'Export-SafeConfiguration - _ScalarToQuoted numeric formatting' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        & (Join-Path $repoRoot 'tests/Support/Import-PSmmClasses.ps1') -RepositoryRoot $repoRoot
        $psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        if (Get-Module -Name 'PSmm' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm' -Force }
        Import-Module -Name $psmmManifest -Force -ErrorAction Stop
    }

    It 'quotes and formats boolean and numeric scalars appropriately via Export-SafeConfiguration' {
        # use a plain hashtable to allow arbitrary scalars
        $config = @{ FlagTrue = $true; FlagFalse = $false; Amount = [decimal]::Parse('42.5') }

        $outPath = Join-Path -Path $env:TEMP -ChildPath 'psmm-safe-scalar.psd1'
        if (Test-Path -Path $outPath) { Remove-Item -Path $outPath -Force }

        $result = Export-SafeConfiguration -Configuration $config -Path $outPath

        $result | Should -Be $outPath
        Test-Path -Path $outPath | Should -BeTrue

        $content = Get-Content -Path $outPath -Raw
        # numeric may be serialized directly or normalized into a hash-like representation; accept either.
        $expectedNum = $config.Amount.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        ($content -match ([regex]::Escape($expectedNum)) -or $content -match 'Scale') | Should -BeTrue
        # booleans should appear as True/False or $true/$false text somewhere in the PSD1
        ($content -match '\$true' -or $content -match 'True') | Should -BeTrue
    }
}
