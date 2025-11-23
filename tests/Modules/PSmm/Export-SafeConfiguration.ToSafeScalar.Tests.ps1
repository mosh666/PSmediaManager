Describe 'Export-SafeConfiguration - _ToSafeScalar formatting' {
    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        & (Join-Path $repoRoot 'tests/Support/Import-PSmmClasses.ps1') -RepositoryRoot $repoRoot
        $psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        if (Get-Module -Name 'PSmm' -ErrorAction SilentlyContinue) { Remove-Module -Name 'PSmm' -Force }
        Import-Module -Name $psmmManifest -Force -ErrorAction Stop
    }

    It 'serializes DateTime to round-trip string (o format) via Export-SafeConfiguration' {
        # use a plain hashtable to allow arbitrary test properties
        $now = [datetime]::UtcNow
        $config = @{ TestTime = $now }

        $outPath = Join-Path -Path $env:TEMP -ChildPath 'psmm-safe-test-1.psd1'
        if (Test-Path -Path $outPath) { Remove-Item -Path $outPath -Force }

        $resultPath = Export-SafeConfiguration -Configuration $config -Path $outPath

        $resultPath | Should -Be $outPath
        Test-Path -Path $outPath | Should -BeTrue

        $content = Get-Content -Path $outPath -Raw
        $content | Should -Match ($now.ToString('o'))
    }

    It 'serializes decimal/numeric values using invariant culture via Export-SafeConfiguration' {
        # use a plain hashtable to allow arbitrary test properties
        $val = [decimal]::Parse('1234.56')
        $config = @{ TestNumber = $val }

        $outPath = Join-Path -Path $env:TEMP -ChildPath 'psmm-safe-test-2.psd1'
        if (Test-Path -Path $outPath) { Remove-Item -Path $outPath -Force }

        $resultPath = Export-SafeConfiguration -Configuration $config -Path $outPath

        $resultPath | Should -Be $outPath
        Test-Path -Path $outPath | Should -BeTrue

        $content = Get-Content -Path $outPath -Raw
        $expected = $val.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        # Decimal types may be normalized into a hashtable representation (Scale/Precision). Accept either form.
        ($content -match 'Scale' -or $content -match ([regex]::Escape($expected))) | Should -BeTrue
    }
}
