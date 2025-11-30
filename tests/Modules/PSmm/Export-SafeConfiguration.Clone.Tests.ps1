Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration (untyped clone path)' -Tag 'SafeExport','Clone' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..\..\..\src\Modules\PSmm\PSmm.psm1'
        Import-Module $modulePath -Force -ErrorAction Stop
    }
    Context 'Cyclic reference handling' {
        It 'Replaces cyclic references with [CyclicRef] sentinel' {
            $h = @{}
            $h.self = $h
            $outPath = Join-Path $env:TEMP 'dummy-safe.psd1'
            $exportedPath = Export-SafeConfiguration -Configuration $h -Path $outPath -Verbose:$false
            $exportedPath | Should -Be $outPath
            $data = Import-PowerShellDataFile -Path $exportedPath
            $data.self | Should -Be '[CyclicRef]'
        }
    }

    Context 'Max depth truncation' {
        It 'Truncates deep nested structures using [MaxDepth] sentinel' {
            $root = @{}
            $current = $root
            for ($i = 0; $i -lt 25; $i++) { $next = @{}; $current.n = $next; $current = $next }
            $outPath = Join-Path $env:TEMP 'dummy-safe-depth.psd1'
            $exportedPath = Export-SafeConfiguration -Configuration $root -Path $outPath -Verbose:$false
            $exportedPath | Should -Be $outPath
            $data = Import-PowerShellDataFile -Path $exportedPath
            $cursor = $data
            $found = $false
            for ($i = 0; $i -lt 50; $i++) {
                if ($cursor -isnot [hashtable]) { break }
                if ($cursor.n -eq '[MaxDepth]') { $found = $true; break }
                $cursor = $cursor.n
            }
            $found | Should -BeTrue
        }
    }

}
