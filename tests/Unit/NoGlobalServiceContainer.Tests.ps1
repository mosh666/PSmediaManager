#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Global ServiceContainer policy' {

    It 'does not reference PSmmServiceContainer anywhere (service-first DI only)' {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent

        $scanRoots = @(
            (Join-Path -Path $repoRoot -ChildPath 'src'),
            (Join-Path -Path $repoRoot -ChildPath 'tests')
        )

        $selfPath = $PSCommandPath

        $files = foreach ($root in $scanRoots) {
            if (-not (Test-Path -LiteralPath $root -PathType Container)) {
                continue
            }

            Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction Stop |
                Where-Object {
                    $_.Extension -in @('.ps1', '.psm1', '.psd1')
                }
        }

        $matches = foreach ($f in $files) {
            if ($null -ne $selfPath -and $f.FullName -eq $selfPath) {
                continue
            }

            $content = $null
            try {
                $content = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop
            }
            catch {
                throw "Failed to read file '$($f.FullName)': $($_.Exception.Message)"
            }

            if ($content -match '\bPSmmServiceContainer\b') {
                $f.FullName
            }
        }

        if (@($matches).Count -gt 0) {
            $list = ($matches | Sort-Object | Select-Object -First 25) -join [System.Environment]::NewLine
            throw "Found forbidden global DI reference(s) to PSmmServiceContainer in:${([System.Environment]::NewLine)}$list"
        }
    }
}
